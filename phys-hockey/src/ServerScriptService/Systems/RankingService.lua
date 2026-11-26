--!strict
-- Global top-50 boards for the RANKINGS tab. Vault: "Global Leaderboards End to End" and
-- "OrderedDataStores and Leaderboards". The profile is the truth and each board is only an
-- index of it: scores come from the session-locked profile's career stats, are written rarely
-- (each player, each board, every 2 minutes and only when changed, plus once on leave) with
-- UpdateAsync that never lowers a score, and every board is read once per 2 minutes per server
-- and pushed to every client. Studio never writes to the live boards.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Protocol = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Protocol"))
local PlayerData = require(script.Parent.Parent:WaitForChild("Data"):WaitForChild("PlayerData"))

local RankingService = {}

local TOP_N = 50
local REFRESH_SECONDS = 120
local WRITE_SECONDS = 120
local STORE_PREFIX = "PuckPals_Rank_v1_"
-- Budget (Roblox docs): ordered writes 30 + 5 x players a minute per server. Six boards for
-- every player every 2 minutes is 3 x players a minute at most, and only changed scores write.
local WRITES_IN_STUDIO = false

type Row = { rank: number, name: string, value: number, userId: number }

local remote: RemoteEvent
local stores: { [string]: OrderedDataStore } = {}
local boards: { [string]: { Row } } = {}
local status = "loading" -- "ok" once a read has worked, "offline" when the store can't be reached
local written: { [Player]: { [string]: number } } = {}
local names: { [number]: string } = {}

local function store(stat: string): OrderedDataStore
	local s = stores[stat]
	if not s then
		s = DataStoreService:GetOrderedDataStore(STORE_PREFIX .. stat)
		stores[stat] = s
	end
	return s
end

local function canWrite(): boolean
	return WRITES_IN_STUDIO or not RunService:IsStudio()
end

-- Writes this player's changed scores. Ordered values are integers and only ever go up.
local function writePlayer(player: Player)
	if not canWrite() then
		return
	end
	local stats = PlayerData.stats(player)
	if not stats then
		return
	end
	local last = written[player] or {}
	written[player] = last
	for _, stat in Protocol.RankingStats do
		local value = math.floor(tonumber(stats[stat]) or 0)
		if value > 0 and last[stat] ~= value then
			local ok = pcall(function()
				store(stat):UpdateAsync(tostring(player.UserId), function(old: number?)
					if old and old >= value then
						return nil -- a stale server never lowers a score
					end
					return value
				end)
			end)
			if ok then
				last[stat] = value
			end
		end
	end
end

-- Display names in one batched call per refresh, cached; unknown ids show neutrally.
local function resolveNames(ids: { number })
	local missing = {}
	for _, id in ids do
		if not names[id] then
			table.insert(missing, id)
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and type(infos) == "table" then
		for _, info in infos do
			names[info.Id] = info.DisplayName
		end
	end
end

local function readBoards()
	local anyOk = false
	for _, stat in Protocol.RankingStats do
		local ok, page = pcall(function()
			return store(stat):GetSortedAsync(false, TOP_N):GetCurrentPage()
		end)
		if ok and type(page) == "table" then
			anyOk = true
			local ids = {}
			for _, entry in page do
				local id = tonumber(entry.key)
				if id then
					table.insert(ids, id)
				end
			end
			resolveNames(ids)
			local rows: { Row } = {}
			for i, entry in page do
				local id = tonumber(entry.key) or 0
				table.insert(rows, { rank = i, name = names[id] or "Player", value = entry.value, userId = id })
			end
			boards[stat] = rows
		end
	end
	status = if anyOk then "ok" else "offline"
end

local function payload(): any
	return { status = status, boards = boards }
end

function RankingService.init(rankingsRemote: RemoteEvent)
	remote = rankingsRemote
	Players.PlayerAdded:Connect(function(player: Player)
		remote:FireClient(player, payload())
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		task.spawn(writePlayer, player)
		written[player] = nil
	end)
	task.spawn(function()
		while true do
			-- Stagger the writes across the interval so they never land in one burst.
			local list = Players:GetPlayers()
			local gap = if #list > 0 then math.min(2, WRITE_SECONDS / 2 / #list) else 0
			for _, player in list do
				if player.Parent then
					writePlayer(player)
				end
				task.wait(gap)
			end
			readBoards()
			remote:FireAllClients(payload())
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return RankingService
