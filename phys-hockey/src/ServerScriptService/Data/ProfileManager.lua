--!strict
-- Session-locked profile store, from the vault note "Session Locking and Profile Libraries".
-- Claims with retries, builds or migrates the profile, saves with token fencing, releases on
-- leave. The lease check and the data write always happen in the same UpdateAsync.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Schema = require(script.Parent.Schema)
local Config = require(game:GetService("ReplicatedStorage").Shared.GameConfig)

local STORE_NAME = "PuckPals_Player_v1"
local LEASE_SECONDS = 90
local CLAIM_ATTEMPTS = 6

local IS_STUDIO = RunService:IsStudio()
local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn(`[ProfileManager] DataStore unavailable: {result}`)
	end
end

export type LoadStatus = "ready" | "locked" | "failed" | "left"
export type Profile = {
	UserId: number,
	Key: string,
	Token: string,
	Data: { [string]: any },
	SaveVersion: number,
	IsNew: boolean,
	State: "active" | "lost" | "released",
	Saving: boolean,
}

local ProfileManager = {}
ProfileManager.LeaseSeconds = LEASE_SECONDS

-- Studio-only isolated key: ServerStorage attribute TestProfileKey = "fresh1" plays on a
-- separate save. Ignored on live servers.
-- Build 41: with no TestProfileKey set, Studio plays on a fresh save for each build ("b41"):
-- the first Play of a new build is a brand-new player's first visit (tutorial, intro, first-match
-- reward), and later Plays of the same build carry on from it. TestProfileKey = "real" plays on
-- the real save. Live servers always use the real key, so real players see the first-time flow once.
local function testKey(): string?
	if not IS_STUDIO then
		return nil
	end
	local test = ServerStorage:GetAttribute("TestProfileKey")
	if test == "real" then
		return nil
	elseif type(test) == "string" and test ~= "" and #test <= 20 then
		return test
	end
	return `b{Config.Build}`
end
ProfileManager.testKey = testKey

local function keyFor(userId: number): string
	local test = testKey()
	if test then
		return `TEST_{test}_{userId}`
	end
	return `User_{userId}`
end
ProfileManager.keyFor = keyFor

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value :: any do
		out[deepCopy(k)] = deepCopy(v)
	end
	return out :: any
end
ProfileManager.deepCopy = deepCopy

local function newSession(token: string)
	return {
		Token = token,
		JobId = game.JobId,
		PlaceId = game.PlaceId,
		ExpiresAt = os.time() + LEASE_SECONDS,
		Studio = if IS_STUDIO then true else nil,
	}
end

local function tryClaim(key: string, userId: number, token: string): (string, any, number?)
	local ds = store
	if not ds then
		return "error", nil, nil
	end
	local outcome, lockedUntil = "error", nil :: number?
	local ok, result = pcall(function()
		return ds:UpdateAsync(key, function(old: any, keyInfo: DataStoreKeyInfo?)
			outcome, lockedUntil = "error", nil -- the transform can run several times
			if old ~= nil and type(old) ~= "table" then
				outcome = "malformed"
				return nil
			end
			local record = old or { SaveVersion = 0 }
			local held = record.Session
			if type(held) == "table" and held.Token ~= token then
				local expires = tonumber(held.ExpiresAt) or 0
				local studioTakeover = IS_STUDIO and held.Studio == true
				if expires > os.time() and not studioTakeover then
					outcome, lockedUntil = "locked", expires
					return nil
				end
			end
			record.Session = newSession(token)
			outcome = "claimed"
			local userIds = if keyInfo then keyInfo:GetUserIds() else { userId }
			local metadata = if keyInfo then keyInfo:GetMetadata() else nil
			return record, userIds, metadata
		end)
	end)
	if not ok then
		warn(`[ProfileManager] claim error for {key}: {result}`)
		return "error", nil, nil
	end
	return outcome, result, lockedUntil
end

function ProfileManager.load(player: Player): (LoadStatus, Profile?)
	local userId = player.UserId
	local key = keyFor(userId)
	local token = HttpService:GenerateGUID(false)
	local lastOutcome = "error"
	-- In Studio without API access every call fails; don't make the tester wait 30 s.
	local attempts = if IS_STUDIO then 2 else CLAIM_ATTEMPTS
	for attempt = 1, attempts do
		if not player.Parent then
			return "left", nil
		end
		local outcome, record, lockedUntil = tryClaim(key, userId, token)
		lastOutcome = outcome
		if outcome == "claimed" and type(record) == "table" then
			local isNew = record.Data == nil
			local okMigrate, data = pcall(function()
				return if isNew then Schema.newProfile() else Schema.migrate(record.Data)
			end)
			if not okMigrate then
				warn(`[ProfileManager] migrate failed for {key}: {data}`)
				ProfileManager.releaseUnsaved(key, token)
				return "failed", nil
			end
			return "ready", {
				UserId = userId,
				Key = key,
				Token = token,
				Data = data,
				SaveVersion = tonumber(record.SaveVersion) or 0,
				IsNew = isNew,
				State = "active",
				Saving = false,
			}
		elseif outcome == "malformed" then
			return "failed", nil
		elseif outcome == "locked" and attempt == 1 and lockedUntil then
			warn(`[ProfileManager] {key} held by another server, lease ends in {lockedUntil - os.time()} s`)
		end
		if attempt < attempts then
			task.wait(math.min(8, attempt * 1.5) + math.random())
		end
	end
	return if lastOutcome == "locked" then "locked" else "failed", nil
end

-- Writes Data (and optionally clears the lease). Fenced by the token.
-- Returns "saved" | "lost" | "error".
function ProfileManager.save(profile: Profile, release: boolean): string
	local ds = store
	if profile.State ~= "active" or not ds then
		return "lost"
	end
	while profile.Saving do
		task.wait(0.1)
	end
	if profile.State ~= "active" then
		return "lost"
	end
	profile.Saving = true
	local snapshot = deepCopy(profile.Data)
	local result = "error"
	local writtenVersion = profile.SaveVersion
	local ok, err = pcall(function()
		ds:UpdateAsync(profile.Key, function(old: any, keyInfo: DataStoreKeyInfo?)
			result = "error"
			if type(old) ~= "table" or type(old.Session) ~= "table" or old.Session.Token ~= profile.Token then
				result = "lost"
				return nil
			end
			writtenVersion = math.max(tonumber(old.SaveVersion) or 0, profile.SaveVersion) + 1
			old.Data = snapshot
			old.SaveVersion = writtenVersion
			old.SavedAt = os.time()
			old.Session = if release then nil else newSession(profile.Token)
			result = "saved"
			local userIds = if keyInfo then keyInfo:GetUserIds() else { profile.UserId }
			local metadata = if keyInfo then keyInfo:GetMetadata() else nil
			return old, userIds, metadata
		end)
	end)
	profile.Saving = false
	if not ok then
		warn(`[ProfileManager] save error for {profile.Key}: {err}`)
		return "error"
	end
	if result == "lost" then
		profile.State = "lost"
		return "lost"
	end
	if result == "saved" then
		profile.SaveVersion = writtenVersion
		if release then
			profile.State = "released"
		end
	end
	return result
end

-- Drops our lease without writing data (load refused after the claim).
function ProfileManager.releaseUnsaved(key: string, token: string)
	local ds = store
	if not ds then
		return
	end
	pcall(function()
		ds:UpdateAsync(key, function(old: any, keyInfo: DataStoreKeyInfo?)
			if type(old) ~= "table" or type(old.Session) ~= "table" or old.Session.Token ~= token then
				return nil
			end
			old.Session = nil
			return old, if keyInfo then keyInfo:GetUserIds() else nil, if keyInfo then keyInfo:GetMetadata() else nil
		end)
	end)
end

return ProfileManager
