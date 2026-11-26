--!strict
-- Player save shape and migrations. migrate() never guesses at data written by a newer
-- release: it errors, and the loader refuses to overwrite that save.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Settings = require(ReplicatedStorage.Shared.Settings)
local Rank = require(ReplicatedStorage.Shared.Rank)

local Schema = {}

-- 2: adds season pass progress (seasons). A server still on version 1 refuses these saves
-- instead of dropping the field, so pass progress is never lost mid-update.
-- 3: adds rank (elo), season titles (titles) and weekly challenge progress (challenges). Same
-- protection: a version 2 server refuses these saves rather than dropping the new fields.
-- 4: adds tutorialDone (the first-time tutorial reward was paid). A version 3 server refuses
-- these saves, so the flag can never be dropped and the reward paid twice.
-- 5: adds the login reward streak (login: last claimed UTC day and streak). A version 4 server
-- refuses these saves, so a claimed day can never be dropped and paid again.
-- 6: adds levelGames (Build 31: a level is 3 full games, not XP). A version 5 server refuses
-- these saves rather than dropping the count. The old xp field is kept as it was (unused).
-- 7: adds challenges.claimed (Build 32: a done challenge is collected by hand). A version 6
-- server refuses these saves, so a collected challenge can never be dropped and paid again.
-- Older saves were paid the moment a challenge was done, so their done ones count as claimed.
Schema.VERSION = 8
Schema.STARTING_COINS = 250

local STAT_KEYS = { "matches", "wins", "losses", "goals", "assists", "shots", "saves", "points" }
Schema.StatKeys = STAT_KEYS

local function num(value: any, fallback: number): number
	local n = tonumber(value)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return fallback
	end
	return math.max(0, math.floor(n))
end

function Schema.newProfile(): { [string]: any }
	local owned = {}
	for _, id in Catalog.Starter do
		owned[id] = true
	end
	local stats = {}
	for _, key in STAT_KEYS do
		stats[key] = 0
	end
	return {
		v = Schema.VERSION,
		coins = Schema.STARTING_COINS,
		xp = 0, -- level XP before Build 31; kept, no longer used
		level = 1,
		-- Full games played toward the next level (0 to GAMES_PER_LEVEL - 1).
		levelGames = 0,
		owned = owned,
		look = table.clone(Catalog.DefaultLook),
		stats = stats,
		settings = Settings.defaults(),
		-- Season pass progress, keyed by season id: { xp, premium, claimedFree, claimedPremium }.
		-- Claimed tiers use string keys ("1", "2"), never a sparse array.
		seasons = {},
		-- Competitive rank (Shared/Rank).
		elo = Rank.START,
		-- Season titles: season id -> the rank index held when that season ended.
		titles = {},
		-- This week's challenges (Shared/Challenges): progress and done, keyed by challenge id.
		challenges = { week = -1, progress = {}, done = {}, claimed = {} },
		-- The first-time tutorial was finished and its reward paid (once per player, ever).
		tutorialDone = false,
		-- Login rewards (Shared/LoginRewards): the last UTC day claimed (-1 = never) and the streak.
		login = { day = -1, streak = 0 },
		-- Build 34 (version 8): Robux purchases, newest last: { id = PurchaseId, product, item,
		-- robux, t }. Kept in this same document as what they granted, so one save records both
		-- (a receipt delivered twice grants once). Also the purchase log for support.
		receipts = {},
	}
end

-- Daily challenge progress, cleaned. legacy: a save from before version 7, whose done
-- challenges were already paid (they count as claimed).
function Schema.cleanChallenges(raw: any, legacy: boolean?): { [string]: any }
	local out = { week = -1, progress = {}, done = {}, claimed = {} }
	if type(raw) ~= "table" then
		return out
	end
	local week = tonumber(raw.week)
	out.week = if week and week == math.floor(week) then week else -1
	if type(raw.progress) == "table" then
		for id, n in raw.progress do
			if type(id) == "string" and #id <= 24 then
				out.progress[id] = num(n, 0)
			end
		end
	end
	if type(raw.done) == "table" then
		for id, has in raw.done do
			if type(id) == "string" and #id <= 24 and has == true then
				out.done[id] = true
				if legacy then
					out.claimed[id] = true
				end
			end
		end
	end
	if not legacy and type(raw.claimed) == "table" then
		for id, has in raw.claimed do
			if type(id) == "string" and #id <= 24 and has == true and out.done[id] then
				out.claimed[id] = true
			end
		end
	end
	return out
end

-- One season's saved progress, cleaned (unknown or broken fields dropped).
function Schema.cleanSeason(raw: any): { [string]: any }
	local out = { xp = 0, premium = false, claimedFree = {}, claimedPremium = {} }
	if type(raw) ~= "table" then
		return out
	end
	out.xp = num(raw.xp, 0)
	out.premium = raw.premium == true
	for _, key in { "claimedFree", "claimedPremium" } do
		if type(raw[key]) == "table" then
			for tier, has in raw[key] do
				local n = tonumber(tier)
				if has == true and n and n == math.floor(n) and n >= 1 and n <= 1000 then
					out[key][tostring(n)] = true
				end
			end
		end
	end
	return out
end

function Schema.migrate(data: any): { [string]: any }
	if type(data) ~= "table" then
		error("save is not a table")
	end
	local v = tonumber(data.v) or 0
	if v > Schema.VERSION then
		error(`save version {v} is newer than this server ({Schema.VERSION})`)
	end
	local fresh = Schema.newProfile()
	fresh.coins = num(data.coins, fresh.coins)
	fresh.xp = num(data.xp, 0)
	fresh.level = math.max(1, num(data.level, 1))
	-- Version 5 saves have no game count: they keep their level and start the next one at 0.
	fresh.levelGames = math.min(Schema.GAMES_PER_LEVEL - 1, num(data.levelGames, 0))
	if type(data.owned) == "table" then
		for id, has in data.owned do
			if has == true and type(id) == "string" and Catalog.ById[id] then
				fresh.owned[id] = true
			end
		end
	end
	if type(data.stats) == "table" then
		for _, key in STAT_KEYS do
			fresh.stats[key] = num(data.stats[key], 0)
		end
	end
	local look = Catalog.sanitizeLook(data.look)
	-- An equipped item the save no longer owns falls back to the default for that slot.
	for _, kind in Catalog.Kinds do
		if not fresh.owned[(look :: any)[kind]] then
			(look :: any)[kind] = (Catalog.DefaultLook :: any)[kind]
		end
	end
	fresh.look = look
	-- Saves from before settings existed simply get the defaults.
	fresh.settings = Settings.sanitize(data.settings)
	-- Version 1 saves have no season progress yet.
	if type(data.seasons) == "table" then
		for id, season in data.seasons do
			if type(id) == "string" and #id <= 16 then
				fresh.seasons[id] = Schema.cleanSeason(season)
			end
		end
	end
	-- Version 2 saves have no rank, titles or challenges yet: they get the defaults.
	if data.elo ~= nil then
		fresh.elo = num(data.elo, Rank.START)
	end
	if type(data.titles) == "table" then
		for id, index in data.titles do
			local n = tonumber(index)
			if type(id) == "string" and #id <= 16 and n and n == math.floor(n) and n >= 1 and n <= Rank.COUNT then
				fresh.titles[id] = n
			end
		end
	end
	fresh.challenges = Schema.cleanChallenges(data.challenges, v < 7)
	-- Version 3 saves have no tutorial flag: not done yet (anyone can still earn the reward).
	fresh.tutorialDone = data.tutorialDone == true
	-- Version 4 saves have no login streak: day 1 is next.
	if type(data.login) == "table" then
		local day = tonumber(data.login.day)
		fresh.login = {
			day = if day and day == math.floor(day) and day >= -1 then day else -1,
			streak = num(data.login.streak, 0),
		}
	end
	-- Version 7 saves have no purchases yet.
	fresh.receipts = Schema.cleanReceipts(data.receipts)
	fresh.v = Schema.VERSION
	return fresh
end

Schema.MAX_RECEIPTS = 200
function Schema.cleanReceipts(raw: any): { any }
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, r in raw do
		if type(r) == "table" and type(r.id) == "string" and #r.id <= 64 then
			table.insert(out, {
				id = r.id,
				product = num(r.product, 0),
				item = if type(r.item) == "string" and #r.item <= 32 then r.item else "",
				robux = num(r.robux, 0),
				t = num(r.t, 0),
			})
		end
	end
	while #out > Schema.MAX_RECEIPTS do
		table.remove(out, 1)
	end
	return out
end

-- Levels (Build 31): a new level every GAMES_PER_LEVEL full games, paying LEVEL_COINS.
Schema.GAMES_PER_LEVEL = 3
Schema.LEVEL_COINS = 500

return Schema
