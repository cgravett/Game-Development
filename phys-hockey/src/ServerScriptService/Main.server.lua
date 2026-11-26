--!strict
-- Server entry: owns the World, runs the fixed-step loop, validates input, publishes state.
-- A client can only ever influence the game by sending stick and skate intent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

Players.CharacterAutoLoads = false

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("GameConfig"))
local Sim = require(Shared:WaitForChild("Sim"))
local Protocol = require(Shared:WaitForChild("Protocol"))

local Systems = script.Parent:WaitForChild("Systems")
local SecurityService = require(Systems:WaitForChild("SecurityService"))
local StoreService = require(Systems:WaitForChild("StoreService"))
local TeamService = require(Systems:WaitForChild("TeamService"))
local MatchService = require(Systems:WaitForChild("MatchService"))
local PlayerData = require(script.Parent:WaitForChild("Data"):WaitForChild("PlayerData"))
local RankingService = require(Systems:WaitForChild("RankingService"))
local PondService = require(Systems:WaitForChild("PondService"))
local SeasonService = require(Systems:WaitForChild("SeasonService"))
local SeasonPass = require(Shared:WaitForChild("SeasonPass"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local MAP_ROTATION = { "Arena", "Night", "Timberline" } -- the pond rink only hosts matches queued from the pond

local World = Sim.World
local SEC = Config.Security
local TICK = Config.Tick
local SNAPSHOT_EVERY = math.max(1, math.round(1 / (TICK * Config.SnapshotRate)))
local MAX_STEPS_PER_FRAME = 4
local MAX_CUES_PER_TICK = 4
local CLOCK_REPUBLISH_SECONDS = 5

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local function makeRemote(name: string, class: string): any
	local remote = Instance.new(class)
	remote.Name = name
	remote.Parent = remotes
	return remote
end
local InputRemote = makeRemote(Protocol.Remotes.Input, "UnreliableRemoteEvent")
local SnapshotRemote = makeRemote(Protocol.Remotes.Snapshot, "UnreliableRemoteEvent")
local CueRemote = makeRemote(Protocol.Remotes.Cue, "UnreliableRemoteEvent")
local StateRemote = makeRemote(Protocol.Remotes.State, "RemoteEvent")
local GoalRemote = makeRemote(Protocol.Remotes.Goal, "RemoteEvent")
local ActionRemote = makeRemote(Protocol.Remotes.Action, "RemoteEvent")
local ProfileRemote = makeRemote(Protocol.Remotes.Profile, "RemoteEvent")
local ShopRemote = makeRemote(Protocol.Remotes.Shop, "RemoteEvent")
local RewardRemote = makeRemote(Protocol.Remotes.Reward, "RemoteEvent")
local NoticeRemote = makeRemote(Protocol.Remotes.Notice, "RemoteEvent")
local RankingsRemote = makeRemote(Protocol.Remotes.Rankings, "RemoteEvent")
local PondSnapshotRemote = makeRemote(Protocol.Remotes.PondSnapshot, "UnreliableRemoteEvent")
local PondCueRemote = makeRemote(Protocol.Remotes.PondCue, "UnreliableRemoteEvent")
local PondEventRemote = makeRemote(Protocol.Remotes.PondEvent, "RemoteEvent")
local IdleRemote = makeRemote(Protocol.Remotes.Idle, "RemoteEvent")
remotes.Parent = ReplicatedStorage

type PlayerNet = {
	queue: { Protocol.Frame },
	lastSeq: number,
	ack: number,
	repeated: number,
	-- Idle tracking (Config.Idle): the last input applied, whether this tick showed activity,
	-- seconds of live play without any, and the last whole second sent in a warning (0 = none).
	last: Protocol.Frame?,
	active: boolean,
	idle: number,
	warned: number,
}

type SlotStats = { goals: number, assists: number, shots: number, saves: number, points: number }

local world = World.new()
local nets: { [Player]: PlayerNet } = {}
local helloed: { [Player]: boolean } = {}
-- When each player last started the tutorial (os.clock), to check a finish is plausible.
local tutorialStarted: { [Player]: number } = {}
local againVotes: { [Player]: boolean } = {} -- who picked PLAY AGAIN on the post-game screen
-- Who joined this match after it was under way (taking a bot's seat): a loss doesn't count
-- against them, and the game only counts toward their level if they joined before halfway.
local lateJoin: { [Player]: { full: boolean } } = {}
local LATE_GRACE = 15 -- seconds of play before a join counts as late
-- Goal replay skip: each player on the ice clicks to vote; the replay is skipped for everyone once
-- two thirds of them have (4 of 6 in a full game, 1 of 1 alone with bots).
local skipVotes: { [Player]: boolean } = {}
local skipDone = false

local function skipNeeded(): number
	return math.max(1, math.ceil(TeamService.humansOnIce() * 2 / 3))
end
local stats: { SlotStats } = {}
local snapshotBuffer = buffer.create(Protocol.SNAPSHOT_BYTES)
local lastPublishedPhaseId = 0
local mapIndex = 1
local rotateMap = false
local currentMap = MAP_ROTATION[1]
-- Shots and saves count only what really threatened the net. A swing that sends the puck on
-- course into the net (inside the posts, under the bar) is pending: it becomes a shot for the
-- shooter when it goes in, or when a defender close to their own net stops it, which is also a
-- save for that defender. A miss, or a block far out from the net, counts as neither.
local SAVE_RANGE = 26 -- a save must be made within this many studs of the goal line
local pendingSave: { team: number, shooter: number, expires: number }? = nil
local lastTouch: number? = nil
-- Build 38: the last swing shot as it left the stick (Sim's Shot event), for judging a shot a
-- defender smothers in the same tick it is taken.
local lastLaunch: { slot: number, pos: Vector3, vel: Vector3, at: number }? = nil

local function resetStats()
	table.clear(lateJoin)
	for slot = 1, Protocol.SLOTS do
		stats[slot] = { goals = 0, assists = 0, shots = 0, saves = 0, points = 0 }
	end
	pendingSave = nil
end

local function refreshPoints(slot: number)
	local s = stats[slot]
	s.points = s.goals * 100 + s.assists * 50 + s.shots * 10 + s.saves * 25
end
resetStats()

local function statePayload(): any
	local m = MatchService.get()
	return {
		phase = m.phase,
		phaseId = m.phaseId,
		revision = m.revision,
		matchId = m.matchId,
		endsAt = m.phaseEndsAt,
		clock = m.clock,
		scores = m.scores,
		overtime = m.inOvertime,
		winner = m.winner,
		roster = TeamService.roster(),
		stats = stats,
		map = currentMap,
	}
end

local function publish()
	local phaseId = MatchService.phaseId()
	if phaseId ~= lastPublishedPhaseId then
		-- Late frames from the old phase must not act on the newly placed puck.
		lastPublishedPhaseId = phaseId
		for _, net in nets do
			table.clear(net.queue)
			net.repeated = 0
		end
	end
	StateRemote:FireAllClients(statePayload())
end

-- Build 36: a player leaving a match under way (quitting, LEAVE, the pond, idling out) takes a
-- loss: a game played and lost and the ELO a loss costs. Not before the opening face-off or once
-- the final buzzer has gone, and not for a late joiner (they were promised a loss won't count).
-- Safe to call twice: it only acts while they still hold a seat, and the callers free it.
-- Build 41: either way they keep the pass XP their score had earned (a late joiner keeps the XP
-- and still takes no loss).
local forfeited: { [Player]: number } = {}
local function forfeit(player: Player)
	local slot = TeamService.slotOf(player)
	if not slot then
		return
	end
	local m = MatchService.get()
	if m.phase == "Waiting" or m.phase == "Countdown" or m.phase == "Final" or m.phase == "Cleanup" then
		return
	end
	if forfeited[player] == MatchService.phaseId() then
		return
	end
	forfeited[player] = MatchService.phaseId()
	local late = lateJoin[player] ~= nil
	local points = if stats[slot] then stats[slot].points else 0
	local before, after, xp = PlayerData.recordForfeit(player, points, not late)
	if player.Parent and not late then
		local kept = if xp > 0 then `, +{xp} PASS XP KEPT` else ""
		NoticeRemote:FireClient(player, `LEFT MID-MATCH: COUNTED AS A LOSS ({after - before} ELO{kept})`, false, "corner")
	elseif player.Parent and xp > 0 then
		NoticeRemote:FireClient(player, `LEFT MID-MATCH: +{xp} PASS XP KEPT`, false, "corner")
	end
end

TeamService.init(world)
MatchService.init(world, publish, {
	humanCount = function(): number
		return #Players:GetPlayers()
	end,
	onMatchReset = function()
		resetStats()
		-- After a finished match the next one moves to the next rink (not during the podium).
		-- A match queued from the pond plays again on the pond rink while anyone is still on it.
		if rotateMap and currentMap == "Pond" and TeamService.humansOnIce() > 0 then
			rotateMap = false
		end
		if rotateMap then
			rotateMap = false
			mapIndex = mapIndex % #MAP_ROTATION + 1
			currentMap = MAP_ROTATION[mapIndex]
		end
	end,
	readyForNext = function(waited: number): boolean
		if TeamService.humansOnIce() == 0 then
			return waited >= Config.Match.FinalSeconds
		end
		for slot = 1, Protocol.SLOTS do
			local player = TeamService.playerIn(slot)
			if player and not againVotes[player] then
				return false
			end
		end
		return true
	end,
	onFinal = function(winner: number)
		table.clear(againVotes)
		rotateMap = true
		for slot = 1, Protocol.SLOTS do
			local player = TeamService.playerIn(slot)
			if player then
				local team = if slot <= 3 then 1 else 2
				local s = stats[slot]
				local late = lateJoin[player]
				local coins, games, leveled, result = PlayerData.grantMatch(player, {
					won = winner == team,
					lost = winner ~= 0 and winner ~= team,
					goals = s.goals,
					assists = s.assists,
					shots = s.shots,
					saves = s.saves,
					points = s.points,
					late = late ~= nil,
					full = late == nil or late.full,
				})
				-- Season pass XP for the match plus any challenge it completed (rewards for any
				-- tier reached are granted inside).
				-- Build 35: the score pays pass XP 1:1 and half of it in coins (granted in grantMatch).
				local matchXp = SeasonPass.matchXp(s.points)
				local passXp, tierBefore, tierAfter = PlayerData.addSeasonXp(player, matchXp + result.challengeXp)
				RewardRemote:FireClient(player, {
					coins = coins + result.challengeCoins + result.scoreCoins,
					scoreCoins = result.scoreCoins,
					score = s.points,
					levelCoins = coins,
					games = games,
					late = late ~= nil,
					challengeXp = result.challengeXp,
					xp = games,
					leveled = leveled,
					passXp = passXp,
					tierBefore = tierBefore,
					tierAfter = tierAfter,
					eloBefore = result.eloBefore,
					eloAfter = result.eloAfter,
					challengesDone = result.challengesDone,
					challengeCoins = result.challengeCoins,
					firstGame = result.firstGame, -- Build 40: the Nova set, on a first whole match
				})
			end
		end
	end,
})

TeamService.setLookProvider(PlayerData.look)
PondService.init({ snapshot = PondSnapshotRemote, cue = PondCueRemote, event = PondEventRemote }, PlayerData.look)
RankingService.init(RankingsRemote)

SeasonService.init()
-- Build 34: Robux purchases (the Mystery Box). The reveal plays once the win is saved.
StoreService.init(function(player: Player, item: string, coins: number)
	if player.Parent then
		RewardRemote:FireClient(player, { box = true, item = if item ~= "" then item else nil, coins = coins })
		if TeamService.slotOf(player) then
			publish()
		end
	end
end, function(player: Player, coins: number)
	if player.Parent then
		RewardRemote:FireClient(player, { coinPack = true, coins = coins })
	end
end)
PlayerData.init(ProfileRemote, function(player: Player)
	SeasonService.onLoaded(player)
	publish()
end)
PlayerData.setBeforeLeave(forfeit)

ShopRemote.OnServerEvent:Connect(function(player: Player, verb: any, a: any, b: any)
	if not SecurityService.allowAction(player) then
		return
	end
	if typeof(verb) ~= "string" then
		SecurityService.violation(player)
		return
	end
	if verb == "Buy" then
		local ok, message = PlayerData.buy(player, a)
		NoticeRemote:FireClient(player, message, ok)
		if ok and TeamService.slotOf(player) then
			publish()
		end
	elseif verb == "Equip" then
		if (a == "skin" or a == "hairColor" or (type(a) == "string" and table.find(Catalog.Kinds, a) ~= nil)) and PlayerData.equip(player, a, b) then
			if TeamService.slotOf(player) then
				publish()
			end
			PondService.refreshRoster()
		end
	elseif verb == "Settings" then
		PlayerData.setSettings(player, a)
	elseif verb == "ClaimChallenge" then
		-- Build 32: a finished daily challenge is collected from the menu (validated and paid
		-- once in PlayerData); the reply drives the "+200" pop on the card.
		local ok, amount, unit = PlayerData.claimChallenge(player, a)
		RewardRemote:FireClient(player, { challenge = true, ok = ok, id = if type(a) == "string" then a else nil, amount = amount, unit = unit })
	elseif verb == "OpenBox" then
		-- Build 34: the server decides whether the Robux prompt may open (StoreService).
		local ok, message = StoreService.promptBox(player)
		if not ok and message ~= "" then
			NoticeRemote:FireClient(player, message, false)
		end
	elseif verb == "BuyCoins" then
		-- Build 35: a coin pack (a Config.CoinPacks key); StoreService validates it.
		local ok, message = StoreService.promptCoins(player, if type(a) == "string" and #a <= 16 then a else nil)
		if not ok and message ~= "" then
			NoticeRemote:FireClient(player, message, false)
		end
	else
		SecurityService.violation(player)
	end
end)

InputRemote.OnServerEvent:Connect(function(player: Player, packet: any)
	if not SecurityService.allowPacket(player) then
		return
	end
	local net = nets[player]
	if not net then
		return
	end
	local phaseId, frames = Protocol.decodeInput(packet, SEC.MaxFramesPerPacket)
	if not phaseId or not frames then
		SecurityService.violation(player)
		return
	end
	-- Players on the pond send the same packets; the pond runs them.
	if PondService.has(player) then
		PondService.queueFrames(player, frames)
		return
	end
	if phaseId ~= MatchService.phaseId() or not TeamService.slotOf(player) then
		return
	end
	-- One frame is consumed per tick, whatever arrives, so sending faster gains no speed.
	for _, frame in frames do
		if frame.seq > net.lastSeq then
			net.lastSeq = frame.seq
			table.insert(net.queue, frame)
		end
	end
	if #net.queue > SEC.MaxQueuedFrames then
		local excess = #net.queue - SEC.TrimQueueTo
		table.move(net.queue, excess + 1, #net.queue, 1)
		for i = #net.queue, #net.queue - excess + 1, -1 do
			net.queue[i] = nil
		end
	end
end)

ActionRemote.OnServerEvent:Connect(function(player: Player, action: any)
	if not SecurityService.allowAction(player) then
		return
	end
	if typeof(action) ~= "string" or not Protocol.Actions[action] then
		SecurityService.violation(player)
		return
	end
	if action == "Hello" then
		helloed[player] = true
		StateRemote:FireClient(player, statePayload())
		PlayerData.push(player)
	elseif action == "Play" or action == "PlayPond" then
		PondService.leave(player)
		-- A fresh start on the ice: no idle time carried over from an earlier match.
		local fresh = nets[player]
		if fresh then
			fresh.idle, fresh.warned, fresh.last = 0, 0, nil
		end
		local wasEmpty = TeamService.humansOnIce() == 0
		local wasOn = TeamService.slotOf(player) ~= nil
		local slot = TeamService.assign(player)
		if slot and not wasOn and not wasEmpty and not lateJoin[player] then
			-- Backfilling a bot's seat in a match already under way.
			local m = MatchService.get()
			local length = Config.Match.LengthSeconds
			local played = length - m.clock
			local running = m.phase ~= "Waiting" and m.phase ~= "Countdown" and m.phase ~= "Final" and m.phase ~= "Cleanup"
			if running and (m.inOvertime or played > LATE_GRACE) then
				lateJoin[player] = { full = not m.inOvertime and played <= length / 2 }
				NoticeRemote:FireClient(player, "JOINED LATE - A LOSS WON'T AFFECT YOUR STATS", true, "corner")
			end
		end
		if slot and wasEmpty then
			-- Queued at the pond rink: a fresh match plays there.
			if action == "PlayPond" then
				currentMap = "Pond"
			end
			MatchService.restart()
		end
		publish()
	elseif action == "Leave" then
		forfeit(player) -- Build 36: walking out of a match under way is a loss
		TeamService.release(player)
		publish()
	elseif action == "TutorialStart" then
		tutorialStarted[player] = os.clock()
	elseif action == "TutorialDone" then
		-- Paid once ever (PlayerData), and only for a run that took as long as a real one can.
		local started = tutorialStarted[player]
		if started and os.clock() - started >= Config.Tutorial.MinSeconds then
			tutorialStarted[player] = nil
			local paid, coins = PlayerData.finishTutorial(player)
			if paid then
				RewardRemote:FireClient(player, { tutorial = true, item = Config.Tutorial.RewardItem, coins = coins })
				PondService.refreshRoster()
			end
		end
	elseif action == "ClaimLogin" then
		-- Today's login reward: the server works out the day and the coins (PlayerData).
		local ok, coins, day, reason = PlayerData.claimLogin(player)
		RewardRemote:FireClient(player, { login = true, ok = ok, coins = coins, day = day, reason = if ok then nil else reason })
	elseif action == "StillHere" then
		-- The in-game menu is open: reading settings is not being idle.
		local net = nets[player]
		if net then
			net.active = true
		end
	elseif action == "Again" then
		if MatchService.get().phase == "Final" and TeamService.slotOf(player) then
			againVotes[player] = true
		end
	elseif action == "SkipReplay" then
		if MatchService.get().phase == "GoalFrozen" and TeamService.slotOf(player) and not skipDone then
			skipVotes[player] = true
			local votes = 0
			for voter in skipVotes do
				if voter.Parent and TeamService.slotOf(voter) then
					votes += 1
				end
			end
			local need = skipNeeded()
			if votes >= need then
				skipDone = true
				MatchService.skipReplay()
			end
			GoalRemote:FireAllClients({ kind = "SkipVote", votes = votes, need = need, skip = skipDone })
		end
	elseif action == "Pond" then
		if TeamService.slotOf(player) then
			forfeit(player)
			TeamService.release(player)
			publish()
		end
		PondService.join(player)
	elseif action == "LeavePond" then
		PondService.leave(player)
	elseif action == "PondPuck" then
		PondService.addPuck(player)
	end
end)

local function onPlayerAdded(player: Player)
	SecurityService.add(player)
	nets[player] = { queue = {}, lastSeq = 0, ack = 0, repeated = 0, active = false, idle = 0, warned = 0 }
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	forfeit(player) -- Build 36: quitting mid-match is a loss (PlayerData also asks, before its last save)
	TeamService.release(player)
	SecurityService.remove(player)
	nets[player] = nil
	helloed[player] = nil
	tutorialStarted[player] = nil
	againVotes[player] = nil
	skipVotes[player] = nil
	lateJoin[player] = nil
	forfeited[player] = nil
	publish()
end)

local function consumeInputs()
	for slot = 1, Protocol.SLOTS do
		local player = TeamService.playerIn(slot)
		local net = player and nets[player]
		if net then
			local input = world.skaters[slot].input
			local frame = table.remove(net.queue, 1)
			if frame then
				-- Any change in skate input is activity; the same input held is not. The aim counts
				-- only when it points away from where the stick already is: the client re-syncs its
				-- aim to the stick each tick, so a stick knocked about by a bot isn't the player.
				local last = net.last
				local skater = world.skaters[slot]
				local aimYaw = math.atan2(frame.aimZ, frame.aimX)
				local aimOff = math.abs((aimYaw - skater.aimYaw + math.pi) % (2 * math.pi) - math.pi)
				-- (A faceoff turns the stick under an unchanged aim; that isn't the player either.)
				local aimMoved = last ~= nil and (math.abs(frame.aimX - last.aimX) > 0.02 or math.abs(frame.aimZ - last.aimZ) > 0.02)
				if
					last == nil
					or math.abs(frame.moveX - last.moveX) > 0.05
					or math.abs(frame.moveZ - last.moveZ) > 0.05
					or (aimMoved and aimOff > 0.15)
					or frame.sprint ~= last.sprint
					or frame.lift ~= last.lift
					or frame.loft ~= last.loft
					or frame.brake ~= last.brake
				then
					net.active = true
				end
				net.last = frame
				net.ack = frame.seq
				net.repeated = 0
				input.moveX, input.moveZ = frame.moveX, frame.moveZ
				input.aimX, input.aimZ = frame.aimX, frame.aimZ
				input.charge, input.sprint = frame.charge, frame.sprint
				input.lift, input.loft, input.brake = frame.lift, frame.loft, frame.brake
			else
				-- Briefly hold the last input through jitter, then let the skater coast.
				net.repeated += 1
				if net.repeated > SEC.MaxRepeatedTicks then
					input.moveX, input.moveZ = 0, 0
					input.charge, input.sprint = false, false
					input.lift, input.loft, input.brake = false, false, false
				end
			end
		end
	end
end

-- Idle players (Config.Idle): only live play counts. A warning goes out at WarnSeconds and
-- then once a second with the seconds left; at KickSeconds the player is sent back to the
-- lobby (a bot takes the slot). Activity at any point clears it.
local function sendToLobby(player: Player)
	forfeit(player) -- Build 36: idling out of a match is a loss
	TeamService.release(player)
	IdleRemote:FireClient(player, 0)
	publish()
end

local function trackIdle(dt: number)
	local phase = MatchService.get().phase
	local counting = phase == "Live" or phase == "Overtime"
	for slot = 1, Protocol.SLOTS do
		local player = TeamService.playerIn(slot)
		local net = player and nets[player]
		if player and net then
			if net.active then
				net.idle = 0
				if net.warned > 0 then
					net.warned = 0
					IdleRemote:FireClient(player, -1)
				end
			elseif counting then
				net.idle += dt
				if net.idle >= Config.Idle.KickSeconds then
					net.idle, net.warned = 0, 0
					sendToLobby(player)
				elseif net.idle >= Config.Idle.WarnSeconds then
					local left = math.ceil(Config.Idle.KickSeconds - net.idle)
					if left ~= net.warned then
						net.warned = left
						IdleRemote:FireClient(player, left)
					end
				end
			end
			net.active = false
		end
	end
end

local function processEvents()
	local cues = 0
	for _, event in World.drainEvents(world) do
		local kind = event.kind
		if kind == "Goal" then
			local team = event.team :: number
			local goalId = MatchService.awardGoal(team)
			if goalId then
				local scorer = event.scorer
				if scorer and not event.ownGoal then
					stats[scorer].goals += 1
					-- Every goal is a shot that went in.
					stats[scorer].shots += 1
					refreshPoints(scorer)
				end
				if event.assist then
					stats[event.assist].assists += 1
					refreshPoints(event.assist)
				end
				pendingSave = nil
				table.clear(skipVotes)
				skipDone = false
				GoalRemote:FireAllClients({
					goalId = goalId,
					skipNeed = skipNeeded(),
					team = team,
					scorer = scorer,
					assist = event.assist,
					ownGoal = event.ownGoal,
					-- The scorer's goals this match, so clients can mark a hat trick.
					scorerGoals = if scorer and not event.ownGoal then stats[scorer].goals else 0,
					x = event.x,
					z = event.z,
					speed = event.strength,
				})
				publish()
			end
		elseif kind == "Stuck" then
			MatchService.puckStuck()
		else
			if kind == "Shot" and event.slot and event.launchPos and event.launchVel then
				lastLaunch = { slot = event.slot, pos = event.launchPos, vel = event.launchVel, at = world.time }
			end
			local cueKind = Protocol.CueKinds[kind]
			if cueKind and cues < MAX_CUES_PER_TICK then
				cues += 1
				CueRemote:FireAllClients(cueKind, event.x, event.z, event.strength)
			end
		end
	end
end

-- Build 31: a shot is any puck that leaves a stick (a swing, a sweep, a flick, a tip) on course
-- for the net, released in the half of the ice the shooter attacks. Its flight is played forward
-- with the ice's own slow-down and gravity; if it crosses the goal line inside the posts and
-- under the bar it is on target. A clear from your own half never counts, even on target (one
-- that goes in is still a goal, and every goal is a shot).
local RELEASE_TICKS = 2 -- the puck is "off the stick" after this many ticks without a touch
local AIM_WINDOW = 0.35 -- seconds after release the flight is checked (sweeps finish over a few ticks)
-- Build 32: the puck's whole speed, as long as it is heading up the ice toward the net (the
-- speed straight down the ice alone missed every shot from an angle, and most wrist shots).
local MIN_SHOT_SPEED = 10 -- studs/s; slower is a pass or a dribble
local release: { shooter: number, x: number, at: number, done: boolean }? = nil

-- Build 38: the puck as the previous tick left it, so a shot a defender reaches before it was
-- checked can still be judged on the flight it had (see trackSaves).
local prevPuckPos: Vector3? = nil
local prevPuckVel: Vector3? = nil

-- Seconds until the puck crosses the goal line at goalX on target, or nil. pos and vel default
-- to the puck now.
local function onTarget(goalX: number, pos: Vector3?, vel: Vector3?): number?
	local P = Config.Puck
	local puck = world.puck
	local p, v = pos or puck.pos, vel or puck.vel
	local x, y, z = p.X, p.Y, p.Z
	local vx, vy, vz = v.X, v.Y, v.Z
	local dt = 1 / 60
	local rest = P.Thickness / 2
	for i = 1, 150 do
		local airborne = y > rest + 1e-3 or vy > 0
		if airborne then
			vy -= P.Gravity * dt
			y += vy * dt
			if y <= rest then
				y, vy = rest, 0
			end
		else
			local speed = math.sqrt(vx * vx + vz * vz)
			if speed <= 0 then
				return nil
			end
			local slowed = speed - (P.IceDeceleration + speed * P.IceDragPerSecond) * dt
			if slowed <= 0 then
				return nil
			end
			vx, vz = vx / speed * slowed, vz / speed * slowed
		end
		local nx = x + vx * dt
		if (nx - goalX) * (x - goalX) <= 0 then
			local f = if nx ~= x then (goalX - x) / (nx - x) else 0
			local zc = z + vz * dt * f
			local inside = math.abs(zc) < Config.Goal.Width / 2
			local under = y < Config.Goal.CrossbarHeight - P.Thickness
			return if inside and under then i * dt else nil
		end
		x, z = nx, z + vz * dt
		if math.abs(z) > 60 then
			return nil
		end
	end
	return nil
end

local function trackShots()
	local touch = world.touch1
	if not touch or world.puckHeld then
		release = nil
		return
	end
	-- Build 32: the shooter is the last stick on the puck. A bounce off a teammate's body (or
	-- the shooter's own) keeps it their shot; an opponent's touch is theirs.
	local shooter = touch
	local lastStick = world.stickHistory[1]
	if lastStick and lastStick ~= touch and (lastStick <= 3) == (touch <= 3) then
		shooter = lastStick
	end
	if world.idle < RELEASE_TICKS * TICK - 1e-6 then
		-- Still on (or just touched by) a stick or body: the release is wherever it leaves from.
		release = { shooter = shooter, x = world.puck.pos.X, at = world.time, done = false }
		return
	end
	local r = release
	if not r or r.done or r.shooter ~= shooter then
		return
	end
	if world.time - r.at > AIM_WINDOW then
		r.done = true
		return
	end
	local team = if shooter <= 3 then 1 else 2
	local dir = if team == 1 then 1 else -1
	-- Only from the half of the ice this skater attacks.
	if r.x * dir <= 0 then
		r.done = true
		return
	end
	local vx, vz = world.puck.vel.X, world.puck.vel.Z
	if vx * dir <= 0 or vx * vx + vz * vz < MIN_SHOT_SPEED * MIN_SHOT_SPEED then
		return
	end
	local t = onTarget(dir * Config.Goal.X)
	if t then
		r.done = true
		pendingSave = { team = team, shooter = shooter, expires = world.time + t + 0.3 }
	end
end

local function countSave(saver: number, shooter: number)
	stats[saver].saves += 1
	refreshPoints(saver)
	stats[shooter].shots += 1
	refreshPoints(shooter)
	-- The crowd reacts to the save (everyone hears it).
	CueRemote:FireAllClients(Protocol.CueKinds.Save, world.puck.pos.X, world.puck.pos.Z, 1)
end

local function trackSaves()
	-- The shot as it stood before this tick: trackShots replaces it once someone else touches it.
	local shotBefore = release
	trackShots()
	local touch = world.touch1
	if touch ~= lastTouch then
		lastTouch = touch
		local pending = pendingSave
		if pending and touch then
			local team = if touch <= 3 then 1 else 2
			-- The shooter's own touch (same tick) or a teammate's tip keeps the shot live.
			if team ~= pending.team then
				-- A save is made near the net: the puck is stopped within SAVE_RANGE of the goal
				-- line it was heading for.
				local goalX = if pending.team == 1 then Config.Goal.X else -Config.Goal.X
				local near = math.abs(goalX - world.puck.pos.X) <= SAVE_RANGE
				if world.time <= pending.expires and near then
					countSave(touch, pending.shooter)
				end
				pendingSave = nil
			end
		elseif touch and shotBefore and not shotBefore.done and prevPuckPos and prevPuckVel then
			-- Build 38: a defender got to the puck before the shot was checked (it is checked a
			-- couple of ticks after it leaves the stick, so a sweep can finish). Close in, or with
			-- the goalie coming out to meet it, that is most saves; none of them counted. Judge it
			-- on the flight it had the tick before the touch, by the same rules, or, for a swing
			-- the goalie smothered in the very tick it was taken, on how it left the stick.
			local team = if touch <= 3 then 1 else 2
			local shooterTeam = if shotBefore.shooter <= 3 then 1 else 2
			if team ~= shooterTeam then
				shotBefore.done = true
				local fromPos, fromVel = prevPuckPos, prevPuckVel
				local launch = lastLaunch
				if launch and launch.slot == shotBefore.shooter and world.time - launch.at <= RELEASE_TICKS * TICK + 1e-6 then
					fromPos, fromVel = launch.pos, launch.vel
				end
				local dir = if shooterTeam == 1 then 1 else -1
				local vx, vz = fromVel.X, fromVel.Z
				local goalX = dir * Config.Goal.X
				if
					shotBefore.x * dir > 0
					and vx * dir > 0
					and vx * vx + vz * vz >= MIN_SHOT_SPEED * MIN_SHOT_SPEED
					and math.abs(goalX - world.puck.pos.X) <= SAVE_RANGE
					and onTarget(goalX, fromPos, fromVel)
				then
					countSave(touch, shotBefore.shooter)
				end
			end
		end
	end
	if pendingSave and world.time > pendingSave.expires then
		pendingSave = nil
	end
	prevPuckPos, prevPuckVel = world.puck.pos, world.puck.vel
end

-- The server time the simulated state belongs to (set before each fixed step). Stamping
-- snapshots with this instead of the wall clock at send keeps their spacing exactly one tick
-- apart, so clients interpolate at an even pace instead of judder from Heartbeat timing.
local stateTime = 0

local function sendSnapshot()
	local puck = world.puck
	Protocol.writeSnapshotHeader(
		snapshotBuffer,
		world.tick,
		stateTime,
		puck.pos.X,
		puck.pos.Y,
		puck.pos.Z,
		puck.vel.X,
		puck.vel.Z,
		puck.vel.Y
	)
	for slot = 1, Protocol.SLOTS do
		local s = world.skaters[slot]
		local player = TeamService.playerIn(slot)
		local net = player and nets[player]
		local flags = (if s.stickState == Sim.WINDING then 1 else 0)
			+ (if s.stickState == Sim.ACTIVE then 2 else 0)
			+ (if s.sprinting then 4 else 0)
			+ (if s.stun > 0 then 8 else 0)
			+ (if s.lifted then 16 else 0)
			+ (if s.lofting then 32 else 0)
			+ (if s.spinLock > 0 then 64 else 0)
		Protocol.writeSnapshotSkater(
			snapshotBuffer,
			slot,
			s.pos.X,
			s.pos.Z,
			s.vel.X,
			s.vel.Z,
			s.aimYaw,
			s.aimRadius,
			flags,
			s.charge,
			s.stamina,
			if net then net.ack else 0,
			s.spin
		)
	end
	-- Only clients that said Hello have their listener connected; firing earlier just drops.
	for player in helloed do
		SnapshotRemote:FireClient(player, snapshotBuffer)
	end
end

local accumulator = 0
local sinceClockPublish = 0

local IS_STUDIO = RunService:IsStudio()

local function fixedStep()
	-- The match rink is the default layout; the pond switches to its own only inside its step.
	Sim.useLayout(nil)
	consumeInputs()
	trackIdle(TICK)
	TeamService.stepBots(TICK)
	-- Studio only: set the workspace attribute DebugGoal to a skater slot and the puck flies into
	-- the net that skater attacks, off their stick (for checking the goal celebration).
	if IS_STUDIO then
		local slot = workspace:GetAttribute("DebugGoal")
		if type(slot) == "number" and world.skaters[slot] then
			workspace:SetAttribute("DebugGoal", nil)
			local side = if world.skaters[slot].team == 1 then 1 else -1
			World.placePuck(world, Vector3.new(side * (Config.Goal.X - 3), 0, 0), Vector3.new(side * 40, 0, 0))
			world.touch1 = slot
			table.insert(world.touchHistory, 1, slot)
		end
		-- DebugClock: jump the match clock to that many seconds (for the end-of-game call-outs).
		local clock = workspace:GetAttribute("DebugClock")
		if type(clock) == "number" then
			workspace:SetAttribute("DebugClock", nil)
			MatchService.debugClock(clock)
			publish()
		end
	end
	World.step(world, TICK)
	processEvents()
	trackSaves()
	MatchService.step(TICK)
	if world.tick % SNAPSHOT_EVERY == 0 and #Players:GetPlayers() > 0 then
		sendSnapshot()
	end
	PondService.step(stateTime)
	sinceClockPublish += TICK
	if sinceClockPublish >= CLOCK_REPUBLISH_SECONDS then
		sinceClockPublish = 0
		local phase = MatchService.get().phase
		if phase == "Live" then
			publish()
		end
	end
end

RunService.Heartbeat:Connect(function(dt: number)
	accumulator = math.min(accumulator + dt, TICK * MAX_STEPS_PER_FRAME)
	local now = workspace:GetServerTimeNow()
	while accumulator >= TICK do
		accumulator -= TICK
		stateTime = now - accumulator
		fixedStep()
	end
end)

print(`[PuckPals] server {Config.Version} build {Config.Build} ready`)
