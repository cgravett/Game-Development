--!strict
-- Loads, autosaves and releases every player's profile (vault note "Saving Correctly -
-- Autosave and BindToClose"), and is the only place that changes saved values: coins, XP,
-- stats, owned items and the equipped look. Every change is synchronous, then pushed to the
-- owning client.
--
-- Load outcomes:
--   ready  -> normal play, saved.
--   locked -> live servers kick ("still saving elsewhere"); nothing is overwritten.
--   failed -> the player plays on a temporary profile that is NEVER written (banner shown),
--             so a bad load can never replace real data with defaults.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Config = require(ReplicatedStorage.Shared.GameConfig)
local Settings = require(ReplicatedStorage.Shared.Settings)
local SeasonPass = require(ReplicatedStorage.Shared.SeasonPass)
local Rank = require(ReplicatedStorage.Shared.Rank)
local Challenges = require(ReplicatedStorage.Shared.Challenges)
local LoginRewards = require(ReplicatedStorage.Shared.LoginRewards)
local MysteryBox = require(ReplicatedStorage.Shared.MysteryBox)
local ProfileManager = require(script.Parent.ProfileManager)
local Schema = require(script.Parent.Schema)

local PlayerData = {}

local AUTOSAVE_INTERVAL = math.min(120, math.floor(ProfileManager.LeaseSeconds / 3))
local FINAL_SAVE_ATTEMPTS = 4
local SHUTDOWN_BUDGET = 25
local MAX_COINS = 10_000_000

type Entry = {
	status: string, -- "loading" | "ready" | "temporary"
	profile: ProfileManager.Profile?,
	data: { [string]: any },
}

local IS_STUDIO = RunService:IsStudio()

-- The server's clock for daily things. Studio only: the ServerStorage attribute DailyDayOffset
-- moves it whole days (1 = tomorrow), to test streaks and resets.
local function now(): number
	local t = os.time()
	if IS_STUDIO then
		local offset = game:GetService("ServerStorage"):GetAttribute("DailyDayOffset")
		if type(offset) == "number" then
			t += math.floor(offset) * 86400
		end
	end
	return t
end

local entries: { [Player]: Entry } = {}
local inFlight = 0
local saveQueued: { [Player]: boolean } = {}
local lastSaveAt: { [Player]: number } = {}
local profileRemote: RemoteEvent
local onLoaded: ((Player) -> ())? = nil

-- The running season's progress for the client to draw (nil between seasons).
local function seasonView(data: { [string]: any }): any
	local season = SeasonPass.current(os.time())
	if not season then
		return nil
	end
	local s = data.seasons and data.seasons[season.id]
	return {
		id = season.id,
		xp = if s then s.xp else 0,
		premium = s ~= nil and s.premium == true,
		claimedFree = if s then s.claimedFree else {},
		claimedPremium = if s then s.claimedPremium else {},
	}
end

-- Today's challenges with the save's progress (none yet if the save is from an older day).
local function challengesView(data: { [string]: any }): any
	local t = now()
	local week = Challenges.period(t)
	local c = data.challenges
	local current = c and c.week == week
	local list = {}
	for _, ch in Challenges.forPeriod(week) do
		table.insert(list, {
			id = ch.id,
			text = ch.text,
			target = ch.target,
			progress = if current then math.min(ch.target, c.progress[ch.id] or 0) else 0,
			done = current and c.done[ch.id] == true,
			claimed = current and type(c.claimed) == "table" and c.claimed[ch.id] == true,
		})
	end
	return { week = week, resetsIn = Challenges.secondsLeft(t), resetsAt = os.time() + Challenges.secondsLeft(t), reward = Challenges.Reward, rewardUnit = if SeasonPass.current(os.time()) then "PASS XP" else "COINS", list = list }
end

-- A brand-new player (no tutorial, no matches) gets day 1 by finishing the tutorial.
local function needsTutorial(data: { [string]: any }): boolean
	return data.tutorialDone ~= true and (data.stats and data.stats.matches or 0) == 0
end

-- The login track for the client to draw.
local function loginView(data: { [string]: any }): any
	local t = now()
	local today = LoginRewards.dayIndex(t)
	local saved = data.login or { day = -1, streak = 0 }
	local state = LoginRewards.evaluate(saved.day, saved.streak, today)
	return {
		track = LoginRewards.Track,
		canClaim = state.canClaim,
		slot = state.slot,
		streak = state.streak,
		needsTutorial = state.canClaim and state.slot == 1 and needsTutorial(data),
		-- Real server time of the next reset (the client counts down with GetServerTimeNow).
		resetsAt = os.time() + (LoginRewards.dayEnds(today) - t),
	}
end

local function payload(entry: Entry): any
	local data = entry.data
	return {
		elo = data.elo or Rank.START,
		titles = data.titles or {},
		challenges = challengesView(data),
		login = loginView(data),
		season = seasonView(data),
		status = entry.status,
		coins = data.coins,
		-- The level bar counts full games (xp / xpNext kept as the field names the client reads).
		xp = data.levelGames or 0,
		level = data.level,
		xpNext = Schema.GAMES_PER_LEVEL,
		owned = data.owned,
		look = data.look,
		stats = data.stats,
		settings = data.settings,
		tutorialDone = data.tutorialDone == true,
	}
end

function PlayerData.push(player: Player)
	local entry = entries[player]
	if entry and player.Parent then
		profileRemote:FireClient(player, payload(entry))
	end
end

local function saveWithRetries(player: Player, release: boolean, attempts: number): boolean
	local entry = entries[player]
	local profile = entry and entry.profile
	if not profile or profile.State ~= "active" then
		return false
	end
	inFlight += 1
	local result = "error"
	local delay = 1
	for attempt = 1, attempts do
		result = ProfileManager.save(profile, release)
		if result ~= "error" then
			break
		end
		if attempt < attempts then
			task.wait(delay * (0.5 + math.random()))
			delay = math.min(delay * 2, 8)
		end
	end
	inFlight -= 1
	lastSaveAt[player] = os.clock()
	if result == "lost" and player.Parent then
		player:SetAttribute("DataNotice", "Your data was opened on another server. Rejoin to keep playing safely.")
	end
	return result == "saved"
end

-- Debounced save after something valuable (a purchase, match rewards).
local function saveSoon(player: Player)
	if saveQueued[player] then
		return
	end
	saveQueued[player] = true
	local since = os.clock() - (lastSaveAt[player] or -math.huge)
	task.delay(math.max(2, 8 - since), function()
		saveQueued[player] = nil
		if player.Parent then
			saveWithRetries(player, false, 2)
		end
	end)
end

local function startAutosave(player: Player)
	task.spawn(function()
		task.wait(math.random() * AUTOSAVE_INTERVAL)
		while player.Parent do
			local entry = entries[player]
			local profile = entry and entry.profile
			if not profile or profile.State ~= "active" then
				break
			end
			saveWithRetries(player, false, 1)
			task.wait(AUTOSAVE_INTERVAL + math.random() * 5)
		end
	end)
end

local function onPlayerAdded(player: Player)
	entries[player] = { status = "loading", profile = nil, data = Schema.newProfile() }
	local status, profile = ProfileManager.load(player)
	if status == "left" then
		entries[player] = nil
		return
	end
	if not player.Parent then
		if profile then
			ProfileManager.save(profile, true)
		end
		entries[player] = nil
		return
	end
	if status == "locked" and not RunService:IsStudio() then
		entries[player] = nil
		player:Kick("Your data is still saving from your last server. Please rejoin in a minute.")
		return
	end
	if status ~= "ready" or not profile then
		-- Temporary profile: playable, never written.
		local entry = entries[player]
		if entry then
			entry.status = "temporary"
		end
		player:SetAttribute("DataNotice", "Your progress couldn't load, so nothing this session will be saved. Rejoin later to try again.")
		warn(`[PlayerData] {player.Name}: load {status}; using a temporary profile`)
	else
		entries[player] = { status = "ready", profile = profile, data = profile.Data }
		startAutosave(player)
		-- Build 36: the game's admins own every item, to test looks in game (Config.Admins, by
		-- UserId, checked here on the server only). Not on a Studio test profile, so a fresh
		-- TestProfileKey save still starts with nothing. Build 41: nor the per-build fresh Studio save
		-- (only TestProfileKey = "real" plays on the real save in Studio).
		local testing = ProfileManager.testKey() ~= nil
		if table.find(Config.Admins, player.UserId) and not testing then
			local owned = profile.Data.owned
			local added = 0
			for _, item in Catalog.Items do
				if not owned[item.id] then
					owned[item.id] = true
					added += 1
				end
			end
			if added > 0 then
				print(`[PlayerData] admin {player.Name}: unlocked {added} items`)
			end
		end
	end
	PlayerData.push(player)
	if onLoaded then
		onLoaded(player)
	end
end

-- Build 36: Main.server's chance to settle a player's match (a forfeit) before the last save.
local beforeLeave: ((Player) -> ())? = nil
function PlayerData.setBeforeLeave(fn: (Player) -> ())
	beforeLeave = fn
end

local function onPlayerRemoving(player: Player)
	if beforeLeave then
		pcall(beforeLeave, player)
	end
	saveQueued[player] = nil
	saveWithRetries(player, true, FINAL_SAVE_ATTEMPTS)
	entries[player] = nil
	lastSaveAt[player] = nil
end

function PlayerData.init(remote: RemoteEvent, loaded: ((Player) -> ())?)
	profileRemote = remote
	onLoaded = loaded
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
	-- At the daily reset, everyone online gets the new day straight away: new challenges and a
	-- login reward to claim, without having to rejoin.
	task.spawn(function()
		local day = LoginRewards.dayIndex(now())
		while true do
			task.wait(10)
			local today = LoginRewards.dayIndex(now())
			if today ~= day then
				day = today
				for player in entries do
					-- Build 32: pays yesterday's uncollected challenges before the new day shows.
					PlayerData.settleSeasons(player)
					PlayerData.push(player)
				end
			end
		end
	end)
	game:BindToClose(function(reason: Enum.CloseReason)
		if RunService:IsStudio() then
			for _, p in Players:GetPlayers() do
				task.spawn(saveWithRetries, p, true, 1)
			end
			task.wait(1)
			return
		end
		for _, p in Players:GetPlayers() do
			task.spawn(saveWithRetries, p, true, 3)
		end
		local started = os.clock()
		task.wait(0.5)
		while inFlight > 0 and os.clock() - started < SHUTDOWN_BUDGET do
			task.wait(0.1)
		end
		if inFlight > 0 then
			warn(`[PlayerData] shutdown ({reason.Name}) ended with {inFlight} saves still running`)
		end
	end)
end

function PlayerData.isLoaded(player: Player): boolean
	local entry = entries[player]
	return entry ~= nil and entry.status ~= "loading"
end

-- A copy of the player's career stats (nil until the profile has loaded).
function PlayerData.stats(player: Player): { [string]: number }?
	local entry = entries[player]
	if not entry or entry.status == "loading" or type(entry.data.stats) ~= "table" then
		return nil
	end
	return table.clone(entry.data.stats)
end

function PlayerData.look(player: Player): Catalog.Look
	local entry = entries[player]
	return Catalog.sanitizeLook(entry and entry.data.look)
end

-- Applies a synchronous change, pushes it, and schedules a save when it matters.
local function change(player: Player, valuable: boolean, fn: (data: { [string]: any }) -> boolean): boolean
	local entry = entries[player]
	if not entry or entry.status == "loading" then
		return false
	end
	if entry.profile and entry.profile.State ~= "active" then
		return false
	end
	if not fn(entry.data) then
		return false
	end
	PlayerData.push(player)
	if valuable and entry.status == "ready" then
		saveSoon(player)
	end
	return true
end

-- Returns ok plus a short reason for the client toast.
function PlayerData.buy(player: Player, id: any): (boolean, string)
	local item = type(id) == "string" and Catalog.ById[id]
	if not item then
		return false, "Unknown item"
	end
	if not Catalog.inShop(item) then
		return false, if item.pass then "Earned from the season pass" elseif item.reward == "tutorial" then "Earned by finishing the tutorial" elseif item.reward == "firstgame" then "Earned by finishing your first match" else "Not for sale"
	end
	local reason = "Not enough coins"
	local ok = change(player, true, function(data)
		if data.owned[item.id] then
			reason = "Already owned"
			return false
		end
		if data.coins < item.price then
			return false
		end
		data.coins -= item.price
		data.owned[item.id] = true
		data.look[item.kind] = item.id -- wear it straight away
		return true
	end)
	return ok, if ok then `Bought {item.name}!` else reason
end

-- Build 34: may this player be offered a Mystery Box right now? Only on a real (saved) profile,
-- with something left to win. Checked before the prompt opens (never at receipt time).
function PlayerData.canOpenBox(player: Player): (boolean, string)
	local entry = entries[player]
	if not entry or entry.status ~= "ready" then
		return false, "Your data hasn't loaded, so you can't buy this right now."
	end
	if #MysteryBox.odds(entry.data.owned) == 0 then
		return false, "You already own everything in the Mystery Box!"
	end
	return true, ""
end

-- Build 34: one Mystery Box receipt (StoreService.ProcessReceipt). Grants once per PurchaseId:
-- the roll, the new item and the receipt go into the profile together, and "granted" comes
-- back only once that profile has saved. Anything else is "retry" (Roblox delivers the receipt
-- again later); a receipt already in the profile is only saved again, never re-rolled.
-- Returns the result, the item won ("" = coins instead) and the coins paid.
function PlayerData.grantBox(player: Player, purchaseId: string, productId: number, robux: number): (string, string, number)
	local entry = entries[player]
	if not entry or entry.status ~= "ready" or not entry.profile or entry.profile.State ~= "active" then
		return "retry", "", 0
	end
	local data = entry.data
	for _, r in data.receipts do
		if r.id == purchaseId then
			local saved = saveWithRetries(player, false, 2)
			return if saved then "granted" else "retry", r.item, if r.item == "" then Config.Box.CompensationCoins else 0
		end
	end
	local won = MysteryBox.pick(data.owned, math.random())
	local coins = 0
	if won then
		data.owned[won] = true
	else
		coins = Config.Box.CompensationCoins
		data.coins = math.min(MAX_COINS, data.coins + coins)
	end
	table.insert(data.receipts, { id = purchaseId, product = productId, item = won or "", robux = robux, t = os.time() })
	while #data.receipts > Schema.MAX_RECEIPTS do
		table.remove(data.receipts, 1)
	end
	PlayerData.push(player)
	local saved = saveWithRetries(player, false, 3)
	return if saved then "granted" else "retry", won or "", coins
end

-- Build 35: may this player be offered a coin pack? Only on a real (saved) profile, and never
-- one that would push them past MAX_COINS (refused at prompt time, never at receipt time).
function PlayerData.canBuyCoins(player: Player, coins: number): (boolean, string)
	local entry = entries[player]
	if not entry or entry.status ~= "ready" then
		return false, "Your data hasn't loaded, so you can't buy this right now."
	end
	if entry.data.coins + coins > MAX_COINS then
		return false, "You have too many coins to buy more right now."
	end
	return true, ""
end

-- Build 35: one coin-pack receipt (StoreService.ProcessReceipt). Same rules as grantBox: the
-- coins and the receipt go into the profile together, once per PurchaseId, and "granted" comes
-- back only after that profile has saved.
function PlayerData.grantCoins(player: Player, purchaseId: string, productId: number, coins: number, robux: number): string
	local entry = entries[player]
	if not entry or entry.status ~= "ready" or not entry.profile or entry.profile.State ~= "active" then
		return "retry"
	end
	local data = entry.data
	for _, r in data.receipts do
		if r.id == purchaseId then
			return if saveWithRetries(player, false, 2) then "granted" else "retry"
		end
	end
	data.coins = math.min(MAX_COINS, data.coins + coins)
	table.insert(data.receipts, { id = purchaseId, product = productId, item = `coins:{coins}`, robux = robux, t = os.time() })
	while #data.receipts > Schema.MAX_RECEIPTS do
		table.remove(data.receipts, 1)
	end
	PlayerData.push(player)
	return if saveWithRetries(player, false, 3) then "granted" else "retry"
end

-- The first-time tutorial reward: the reward stick (worn straight away) and coins, paid once per
-- player ever. Returns whether it was paid now, and the coins.
function PlayerData.finishTutorial(player: Player): (boolean, number)
	local item = Catalog.ById[Config.Tutorial.RewardItem]
	local coins = Config.Tutorial.RewardCoins
	local ok = change(player, true, function(data)
		if data.tutorialDone then
			return false
		end
		data.tutorialDone = true
		if item then
			data.owned[item.id] = true
			data.look[item.kind] = item.id
		end
		data.coins = math.min(MAX_COINS, data.coins + coins)
		-- The tutorial's coins are the login track's day 1: if day 1 is today's claim, it counts.
		local today = LoginRewards.dayIndex(now())
		local saved = data.login or { day = -1, streak = 0 }
		local state = LoginRewards.evaluate(saved.day, saved.streak, today)
		if state.canClaim and state.slot == 1 then
			data.login = { day = today, streak = 1 }
		end
		return true
	end)
	return ok, if ok then coins else 0
end

-- Today's login reward. Takes nothing from the client: the day, the slot and the coins all come
-- from the save and the server clock, checked and paid in one synchronous change (nothing
-- yields between the check and the mark), so a day can't be claimed twice. Returns ok, the
-- coins, the day slot, and a reason when refused.
function PlayerData.claimLogin(player: Player): (boolean, number, number, string)
	local paid, slot, reason = 0, 0, "Already claimed today"
	change(player, true, function(data)
		local today = LoginRewards.dayIndex(now())
		local saved = data.login or { day = -1, streak = 0 }
		local state = LoginRewards.evaluate(saved.day, saved.streak, today)
		if not state.canClaim then
			return false
		end
		if state.slot == 1 and needsTutorial(data) then
			reason = "Finish the tutorial to collect day 1"
			return false
		end
		local coins = LoginRewards.Track[state.slot]
		data.coins = math.min(MAX_COINS, data.coins + coins)
		data.login = { day = today, streak = state.streak + 1 }
		paid, slot = coins, state.slot
		return true
	end)
	return paid > 0, paid, slot, reason
end

function PlayerData.equip(player: Player, kind: any, value: any): boolean
	return change(player, false, function(data)
		if kind == "skin" or kind == "hairColor" then
			local list = if kind == "skin" then Catalog.SkinTones else Catalog.HairColors
			local index = tonumber(value)
			if not index or index ~= math.floor(index) or not list[index] then
				return false
			end
			data.look[kind] = index
			return true
		end
		local item = type(value) == "string" and Catalog.ById[value]
		if not item or item.kind ~= kind or not data.owned[item.id] then
			return false
		end
		data.look[kind] = item.id
		return true
	end)
end

-- Controls, camera and audio settings. The whole table is cleaned with the shared rules.
function PlayerData.setSettings(player: Player, raw: any): boolean
	return change(player, false, function(data)
		data.settings = Settings.sanitize(raw)
		return true
	end)
end

---------------------------------------------------------------------------------------------
-- Season pass (vault note "Battle Pass and Season Design"). Rewards are granted the moment a
-- tier is reached, premium ones back to tier 1 the moment premium is owned. Each tier and track
-- is marked claimed before its reward is applied, with no yield in between, so nothing is ever
-- granted twice.
---------------------------------------------------------------------------------------------

local function seasonState(data: { [string]: any }, id: string): { [string]: any }
	data.seasons = data.seasons or {}
	local s = data.seasons[id]
	if not s then
		s = Schema.cleanSeason(nil)
		data.seasons[id] = s
	end
	return s
end

local function applyReward(data: { [string]: any }, reward: SeasonPass.Reward)
	if reward.item and Catalog.ById[reward.item] then
		data.owned[reward.item] = true
	end
	if reward.coins then
		data.coins = math.min(MAX_COINS, data.coins + reward.coins)
	end
end

-- Grants everything reached and not yet claimed. Returns how many rewards it granted.
local function payOut(data: { [string]: any }, season: SeasonPass.Season): number
	local s = seasonState(data, season.id)
	local reached = SeasonPass.tierFor(season, s.xp)
	local granted = 0
	for i = 1, reached do
		local tier = season.tiers[i]
		local key = tostring(i)
		-- A "soon" reward is a placeholder: never granted or marked, so the real one pays later.
		if tier.free and not tier.free.soon and not s.claimedFree[key] then
			s.claimedFree[key] = true
			applyReward(data, tier.free)
			granted += 1
		end
		if s.premium and tier.premium and not tier.premium.soon and not s.claimedPremium[key] then
			s.claimedPremium[key] = true
			applyReward(data, tier.premium)
			granted += 1
		end
	end
	return granted
end

-- Adds pass XP to the running season. Returns the XP added and the tier before and after.
function PlayerData.addSeasonXp(player: Player, amount: number): (number, number, number)
	local season = SeasonPass.current(os.time())
	amount = math.floor(amount)
	if not season or amount <= 0 then
		return 0, 0, 0
	end
	local before, after = 0, 0
	local ok = change(player, true, function(data)
		local s = seasonState(data, season.id)
		before = SeasonPass.tierFor(season, s.xp)
		s.xp += amount
		after = SeasonPass.tierFor(season, s.xp)
		payOut(data, season)
		return true
	end)
	if not ok then
		return 0, 0, 0
	end
	return amount, before, after
end

-- Premium for a season, once the server has confirmed the game pass is owned. Idempotent:
-- calling it again only pays out anything still owed. Works after the season ended too (a
-- purchase at the boundary still pays out everything reached).
function PlayerData.setSeasonPremium(player: Player, seasonId: string): boolean
	local season = SeasonPass.ById[seasonId]
	if not season then
		return false
	end
	return change(player, true, function(data)
		local s = seasonState(data, seasonId)
		local was = s.premium
		s.premium = true
		local granted = payOut(data, season)
		return not was or granted > 0
	end)
end

-- Build 32: one challenge's reward, inside a change: Challenges.Reward pass XP into the running
-- season (paying any tiers it reaches), else that many coins. Returns the amount and its unit.
local function payChallenge(data: { [string]: any }): (number, string)
	local season = SeasonPass.current(os.time())
	if season then
		local s = seasonState(data, season.id)
		s.xp += Challenges.Reward
		payOut(data, season)
		return Challenges.Reward, "PASS XP"
	end
	data.coins = math.min(MAX_COINS, data.coins + Challenges.Reward)
	return Challenges.Reward, "COINS"
end

-- Build 32: challenges are collected by hand. When the day turns over, any that were done but
-- never collected are paid now (so nothing earned is lost), then today's start fresh. Returns
-- what it paid (0 if the saved day is today's).
local function settleOldChallenges(data: { [string]: any }): number
	local week = Challenges.period(now())
	local c = data.challenges
	if type(c) == "table" and c.week == week then
		return 0
	end
	local paid = 0
	if type(c) == "table" and type(c.done) == "table" then
		local claimed = if type(c.claimed) == "table" then c.claimed else {}
		for id in c.done do
			if not claimed[id] then
				paid += (payChallenge(data))
			end
		end
	end
	data.challenges = { week = week, progress = {}, done = {}, claimed = {} }
	return paid
end

-- Collects one of today's finished challenges, once. The id comes from the client, so it only
-- counts if today's save has it done and not yet collected; checked, marked and paid in one
-- synchronous change. Returns ok, the amount and its unit ("COINS" or "PASS XP").
function PlayerData.claimChallenge(player: Player, id: any): (boolean, number, string)
	if type(id) ~= "string" or #id > 24 then
		return false, 0, ""
	end
	local amount, unit = 0, ""
	change(player, true, function(data)
		local settled = settleOldChallenges(data)
		local c = data.challenges
		if type(c) ~= "table" or type(c.done) ~= "table" or not c.done[id] then
			return settled > 0
		end
		c.claimed = if type(c.claimed) == "table" then c.claimed else {}
		if c.claimed[id] then
			return settled > 0
		end
		c.claimed[id] = true
		amount, unit = payChallenge(data)
		return true
	end)
	return amount > 0, amount, unit
end

-- On load: pay out anything owed in every season the save knows (the instant tier 1 reward,
-- and any season that ended with rewards unclaimed).
function PlayerData.settleSeasons(player: Player)
	change(player, true, function(data)
		local granted = settleOldChallenges(data)
		local current = SeasonPass.current(os.time())
		if current then
			seasonState(data, current.id)
		end
		for id in data.seasons or {} do
			local season = SeasonPass.ById[id]
			if season then
				granted += payOut(data, season)
				-- A season that has ended leaves its rank behind as a title, once.
				data.titles = data.titles or {}
				if os.time() >= season.endsAt and data.titles[id] == nil then
					data.titles[id] = Rank.index(data.elo or Rank.START)
					granted += 1
				end
			end
		end
		return granted > 0
	end)
end

-- late: joined after the match was under way (a loss then doesn't count against them).
-- full: counts toward the level (joined before the halfway point).
export type MatchLine = { won: boolean, lost: boolean, goals: number, assists: number, shots: number, saves: number, points: number, late: boolean?, full: boolean? }
export type MatchResult = { eloBefore: number, eloAfter: number, challengesDone: { string }, challengeCoins: number, challengeXp: number, scoreCoins: number, firstGame: { string }? }

-- Daily challenges: adds a finished match to today's progress and marks the ones it completes
-- done. Build 32: nothing is paid here; the player collects each one from the menu
-- (PlayerData.claimChallenge), and any left uncollected are paid when the day turns over.
-- Runs inside the same synchronous change as the match grant.
local function progressChallenges(data: { [string]: any }, line: MatchLine, result: MatchResult)
	local week = Challenges.period(now())
	settleOldChallenges(data)
	local c = data.challenges
	c.claimed = if type(c.claimed) == "table" then c.claimed else {}
	local amounts = {
		matches = 1,
		wins = if line.won then 1 else 0,
		goals = line.goals,
		assists = line.assists,
		saves = line.saves,
		shots = line.shots,
	}
	for _, ch in Challenges.forPeriod(week) do
		local add = amounts[ch.stat] or 0
		if add > 0 and not c.done[ch.id] then
			c.progress[ch.id] = math.min(ch.target, (c.progress[ch.id] or 0) + add)
			if c.progress[ch.id] >= ch.target then
				c.done[ch.id] = true
				table.insert(result.challengesDone, ch.text)
			end
		end
	end
end

-- Match rewards (Build 35: half the score in coins, the score in pass XP (Main.server), and every
-- GAMES_PER_LEVEL full games a level worth LEVEL_COINS). Returns the coins granted (the level
-- reward), the games counted toward the level (0 or 1), whether the player levelled, and what
-- the match did to their rank and challenges. A late joiner's loss counts for nothing.
function PlayerData.grantMatch(player: Player, line: MatchLine): (number, number, boolean, MatchResult)
	local result: MatchResult = { eloBefore = 0, eloAfter = 0, challengesDone = {}, challengeCoins = 0, challengeXp = 0, scoreCoins = 0 }
	local coins = 0
	-- Build 35: half the match score in coins (SeasonPass.matchCoins).
	local scoreCoins = SeasonPass.matchCoins(line.points)
	local games = if line.full == false then 0 else 1
	local lossCounts = line.lost and not line.late
	local leveled = false
	change(player, true, function(data)
		local s = data.stats
		s.matches += 1
		s.wins += if line.won then 1 else 0
		s.losses += if lossCounts then 1 else 0
		s.goals += line.goals
		s.assists += line.assists
		s.shots += line.shots
		s.saves += line.saves
		s.points += line.points
		if scoreCoins > 0 then
			local before = data.coins
			data.coins = math.min(MAX_COINS, data.coins + scoreCoins)
			result.scoreCoins = data.coins - before
		end
		data.levelGames = (data.levelGames or 0) + games
		if data.levelGames >= Schema.GAMES_PER_LEVEL then
			data.levelGames = 0
			data.level += 1
			data.coins = math.min(MAX_COINS, data.coins + Schema.LEVEL_COINS)
			coins = Schema.LEVEL_COINS
			leveled = true
		end
		local elo = data.elo or Rank.START
		result.eloBefore = elo
		data.elo = Rank.after(elo, line.won, lossCounts)
		result.eloAfter = data.elo
		progressChallenges(data, line, result)
		-- Build 40: the first whole match gives the Nova set, worn straight away. Owning the
		-- armour is the marker, so it is given once (players who played before Build 40 get it
		-- on their next whole match), and it lands in this same change as the match itself.
		local set = Catalog.FirstGameReward
		if games == 1 and not data.owned[set[1]] then
			for _, id in set do
				local item = Catalog.ById[id]
				if item then
					data.owned[id] = true
					data.look[item.kind] = id
				end
			end
			result.firstGame = table.clone(set)
		end
		return true
	end)
	return coins, games, leveled, result
end

-- Build 36: leaving a match under way (quitting the game, going back to the lobby or being sent
-- there for idling) is a loss: a match played and lost, and the ELO a loss costs. No coins or
-- challenge progress. Build 41: the pass XP their score had earned so far is kept (points: the
-- server's own score for the match, SeasonPass.matchXp), in the same save as the loss. A late
-- joiner (countLoss false) keeps the XP and takes no loss. Returns the ELO before and after
-- (equal if nothing changed) and the pass XP added.
function PlayerData.recordForfeit(player: Player, points: number?, countLoss: boolean?): (number, number, number)
	local before, after, xp = 0, 0, 0
	local season = SeasonPass.current(os.time())
	local earned = if season then SeasonPass.matchXp(points or 0) else 0
	local loss = countLoss ~= false
	if not loss and earned <= 0 then
		return 0, 0, 0
	end
	local ok = change(player, true, function(data)
		if loss then
			data.stats.matches += 1
			data.stats.losses += 1
			local elo = data.elo or Rank.START
			before = elo
			data.elo = Rank.after(elo, false, true)
			after = data.elo
		end
		if season and earned > 0 then
			local s = seasonState(data, season.id)
			s.xp += earned
			payOut(data, season)
			xp = earned
		end
		return true
	end)
	if not ok then
		return 0, 0, 0
	end
	return before, after, xp
end

return PlayerData
