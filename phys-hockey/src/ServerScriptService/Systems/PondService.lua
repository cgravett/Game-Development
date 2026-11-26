--!strict
-- The Pond: one shared open world for everyone on it, run on the server like the match. Each
-- player's skater lives in one World on the pond's layout (lake shore, the match rink as a solid
-- block, the open rink's end boards, five nets). Pucks are their own little Worlds sharing those
-- skaters (the practice "extra puck" pattern), so every stick and body plays every puck the same.
-- Mini-game pucks are private: only their player's skater touches them. Clients still only send
-- stick and skate intent; every goal, gate, target and record is decided here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("GameConfig"))
local Sim = require(Shared:WaitForChild("Sim"))
local Protocol = require(Shared:WaitForChild("Protocol"))
local PondLayout = require(Shared:WaitForChild("PondLayout"))

local PondService = {}

local World = Sim.World
local L = PondLayout.LAYOUT
local TICK = Config.Tick
local SEC = Config.Security
-- Snapshots go out every tick (60 a second, like the match) while the packet is small, and every
-- other tick once the pond is busy (up to 16 skaters and 40 pucks is 935 bytes, under the
-- 1,000-byte unreliable limit), so bandwidth stays flat. Build 27 sent 30 a second always, and a
-- puck in the air was drawn from samples a long way apart.
local FULL_RATE_BYTES = 420
local MAX_CUES_PER_TICK = 6
local CUE_RANGE = 140
local GOAL_FX_RANGE = 95
local PUCK_IDLE_HOME = 45 -- a loose shared puck nobody has touched for this long goes home
local GAME_SECONDS = { Targets = 60, Slalom = 60, Speed = 60 }
local SPEED_SHOTS = 5
local MISS_RETURN = 4 -- a missed mini-game puck still sliding comes back after this many untouched seconds

type PuckEntry = {
	id: number,
	world: Sim.World,
	prev: Vector3,
	home: Vector3,
	kind: string, -- "Rink", "Lake", "Own" or "Game"
	owner: Member?,
	resetAt: number, -- respawn at home at this pond time (0 = not pending)
}

type Game = {
	station: PondLayout.Station,
	member: Member,
	puck: PuckEntry,
	startedAt: number, -- server clock (GetServerTimeNow) when the clock started (0 = not yet)
	started: number, -- pond time the game began
	hits: { boolean }, -- targets
	gate: number, -- slalom: next gate
	shots: number, -- hardest shot: attempts taken
	best: number,
	shotLive: boolean, -- hardest shot: the current puck has been hit and not yet counted
}

export type Member = {
	player: Player,
	id: number,
	skater: Sim.Skater,
	queue: { Protocol.Frame },
	lastSeq: number,
	ack: number,
	repeated: number,
	ownPucks: { PuckEntry }, -- oldest first; up to PondLayout.OWN_PUCKS
	pad: { [string]: number }, -- seconds stood in each start ring
	padLocked: { [string]: boolean }, -- must step out of the ring before it starts again
	game: Game?,
	prevPos: Vector3,
}

local world = World.new()
world.layout = L
world.controlsEnabled = true
world.stickHits = true
world.goalsEnabled = true

local members: { [Player]: Member } = {}
local byId: { [number]: Member } = {}
local pucks: { PuckEntry } = {} -- every puck; pucks[1] is the open rink's, stepped by World.step
local usedPuckIds: { [number]: boolean } = {}
local busy: { [string]: Member } = {}
local records: { [string]: { name: string, value: number } } = {}
local bots: { Sim.Skater } = {} -- Studio test skaters only (PondTestHook)

local snapshotRemote: any
local cueRemote: any
local eventRemote: any
local lookOf: (Player) -> any = function()
	return nil
end

local CUE_KINDS = Protocol.CueKinds

local function newPuckWorld(skaters: { Sim.Skater }): Sim.World
	local w = World.new()
	w.layout = L
	w.skaters = skaters
	w.controlsEnabled = true
	w.stickHits = true
	w.goalsEnabled = true
	return w
end

local function freePuckId(): number?
	for id = 1, PondLayout.MAX_PUCKS do
		if not usedPuckIds[id] then
			return id
		end
	end
	return nil
end

local function placePuck(entry: PuckEntry, at: Vector3)
	local w = entry.world
	World.placePuck(w, at)
	w.goalLatched = false
	w.touch1 = nil
	w.touch2 = nil
	table.clear(w.touchHistory)
	entry.prev = w.puck.pos
	entry.resetAt = 0
end

local function addPuck(kind: string, home: Vector3, skaters: { Sim.Skater }, owner: Member?): PuckEntry?
	local id = freePuckId()
	if not id then
		return nil
	end
	usedPuckIds[id] = true
	local entry: PuckEntry = { id = id, world = newPuckWorld(skaters), prev = home, home = home, kind = kind, owner = owner, resetAt = 0 }
	placePuck(entry, home)
	table.insert(pucks, entry)
	return entry
end

local function removePuck(entry: PuckEntry)
	local i = table.find(pucks, entry)
	if i then
		table.remove(pucks, i)
	end
	usedPuckIds[entry.id] = nil
end

-- The open rink's puck is the main world's own puck; the lake's shared pucks sit near the spawn.
do
	usedPuckIds[1] = true
	local main: PuckEntry = { id = 1, world = world, prev = PondLayout.OPEN_PUCK, home = PondLayout.OPEN_PUCK, kind = "Rink", owner = nil, resetAt = 0 }
	placePuck(main, PondLayout.OPEN_PUCK)
	table.insert(pucks, main)
	for _, home in PondLayout.LAKE_PUCKS do
		addPuck("Lake", home, world.skaters, nil)
	end
end

local function send(member: Member, payload: any)
	eventRemote:FireClient(member.player, payload)
end

local function broadcast(payload: any)
	for _, member in members do
		eventRemote:FireClient(member.player, payload)
	end
end

local function rosterPayload(): any
	local list = {}
	for id, member in byId do
		table.insert(list, { id = id, name = member.player.DisplayName, userId = member.player.UserId, look = lookOf(member.player) })
	end
	return { kind = "Roster", list = list }
end

function PondService.refreshRoster()
	if next(members) then
		broadcast(rosterPayload())
	end
end

local function recordsPayload(): any
	return { kind = "Records", records = records }
end

-- Somewhere just ahead of a skater, on clear ice.
local function aheadOf(s: Sim.Skater, distance: number): Vector3
	local spot = s.pos + Vector3.new(math.cos(s.aimYaw), 0, math.sin(s.aimYaw)) * distance
	local outer = Sim.useLayout(L)
	local clear = Sim.insideRink(spot.X, spot.Z, 2) and Sim.netFrame(spot.X, spot.Z) < -50
	Sim.useLayout(outer)
	if clear then
		return Vector3.new(spot.X, 0, spot.Z)
	end
	return Vector3.new(s.pos.X, 0, s.pos.Z)
end

local function homeOf(entry: PuckEntry): Vector3
	if entry.kind == "Own" and entry.owner then
		return aheadOf(entry.owner.skater, 6)
	elseif entry.kind == "Game" then
		return entry.home
	end
	return entry.home
end

---------------------------------------------------------------------------------------------
-- Mini games
---------------------------------------------------------------------------------------------

local function stationById(id: string): PondLayout.Station?
	for _, station in PondLayout.STATIONS do
		if station.id == id then
			return station
		end
	end
	return nil
end

local function better(id: string, value: number, old: number): boolean
	if id == "Speed" then
		return value > old
	end
	return value < old
end

local function finishGame(member: Member, result: string, value: number?)
	local game = member.game
	if not game then
		return
	end
	local id = game.station.id
	member.game = nil
	busy[id] = nil
	member.padLocked[id] = true
	removePuck(game.puck)
	local record = false
	if value then
		local old = records[id]
		if not old or better(id, value, old.value) then
			records[id] = { name = member.player.DisplayName, value = value }
			record = true
		end
	end
	send(member, { kind = "Game", phase = "end", id = id, title = game.station.title, text = result, record = record })
	if record then
		broadcast(recordsPayload())
	end
end

local function startGame(member: Member, station: PondLayout.Station)
	local puck = addPuck("Game", station.spot, { member.skater }, member)
	if not puck then
		return
	end
	busy[station.id] = member
	local game: Game = {
		station = station,
		member = member,
		puck = puck,
		startedAt = 0,
		started = world.time,
		hits = { false, false, false, false },
		gate = 1,
		shots = 0,
		best = 0,
		shotLive = false,
	}
	member.game = game
	if station.id ~= "Slalom" then
		game.startedAt = workspace:GetServerTimeNow()
	end
	send(member, {
		kind = "Game",
		phase = "start",
		id = station.id,
		title = station.title,
		text = station.blurb,
		startedAt = game.startedAt,
		limit = GAME_SECONDS[station.id],
		shots = if station.id == "Speed" then SPEED_SHOTS else nil,
	})
end

local function progress(member: Member, fields: any)
	fields.kind = "Game"
	fields.phase = "progress"
	send(member, fields)
end

local function elapsed(game: Game): number
	return if game.startedAt > 0 then workspace:GetServerTimeNow() - game.startedAt else 0
end

local function round1(n: number): number
	return math.round(n * 10) / 10
end

-- Start rings: stand in one for a moment to begin; one player at a time per station.
local function checkPads(member: Member)
	local pos = member.skater.pos
	for _, station in PondLayout.STATIONS do
		local d = (Vector3.new(pos.X, 0, pos.Z) - station.pad).Magnitude
		if d < PondLayout.PAD_RADIUS then
			if not member.padLocked[station.id] and not member.game then
				member.pad[station.id] = (member.pad[station.id] or 0) + TICK
				if member.pad[station.id] >= 0.6 then
					member.pad[station.id] = 0
					member.padLocked[station.id] = true
					local holder = busy[station.id]
					if holder then
						send(member, { kind = "Busy", title = station.title, name = holder.player.DisplayName })
					else
						startGame(member, station)
					end
				end
			end
		else
			member.pad[station.id] = 0
			member.padLocked[station.id] = nil
		end
	end
end

local function respawnGamePuck(game: Game, delay: number)
	if delay <= 0 then
		placePuck(game.puck, game.station.spot)
	else
		game.puck.resetAt = world.time + delay
	end
end

-- Runs after the step: gates, a lost puck, the clock, leaving the area.
local function stepGame(member: Member)
	local game = member.game
	if not game then
		return
	end
	local station = game.station
	local s = member.skater
	local flat = Vector3.new(s.pos.X, 0, s.pos.Z)
	if (flat - station.area).Magnitude > PondLayout.AREA_RADIUS then
		finishGame(member, "You skated away, so the game ended.", nil)
		return
	end
	local limit = GAME_SECONDS[station.id]
	if game.startedAt > 0 and elapsed(game) > limit then
		if station.id == "Targets" then
			local count = 0
			for _, hit in game.hits do
				count += if hit then 1 else 0
			end
			finishGame(member, `Time! You hit {count} of 4 targets.`, nil)
		elseif station.id == "Speed" then
			finishGame(member, if game.best > 0 then `Time! Hardest shot {round1(game.best)} KPH.` else "Time! No shots on net.", if game.best > 0 then game.best else nil)
		else
			finishGame(member, "Out of time. Try again!", nil)
		end
		return
	end

	local pw = game.puck.world
	local puck = pw.puck
	local fromSpot = (Vector3.new(puck.pos.X, 0, puck.pos.Z) - station.spot).Magnitude

	if station.id == "Slalom" then
		local prev = member.prevPos
		if game.startedAt == 0 then
			if prev.X < PondLayout.SLALOM_START_X and s.pos.X >= PondLayout.SLALOM_START_X then
				game.startedAt = workspace:GetServerTimeNow()
				progress(member, { id = "Slalom", startedAt = game.startedAt, gate = 0, gates = #PondLayout.GATES })
			end
		else
			local gate = PondLayout.GATES[game.gate]
			if gate and prev.X < gate.X and s.pos.X >= gate.X then
				local carried = (Vector3.new(puck.pos.X, 0, puck.pos.Z) - flat).Magnitude < 9
				if math.abs(s.pos.Z - gate.Y) <= PondLayout.GATE_HALF and carried then
					progress(member, { id = "Slalom", gate = game.gate, gates = #PondLayout.GATES })
					game.gate += 1
				else
					-- Missed a gate (or left the puck behind): back to the start.
					game.gate = 1
					game.startedAt = 0
					respawnGamePuck(game, 0)
					progress(member, {
						id = "Slalom",
						reset = true,
						text = if carried then "Missed a gate. Back to the start ring and go again." else "Bring the puck with you. Back to the start and go again.",
					})
				end
			end
		end
		-- A puck lost far away comes back to the start.
		if fromSpot > 40 and (Vector3.new(puck.pos.X, 0, puck.pos.Z) - flat).Magnitude > 25 then
			game.gate = 1
			game.startedAt = 0
			respawnGamePuck(game, 0)
			progress(member, { id = "Slalom", reset = true, text = "Lost the puck. Back to the start and go again." })
		end
	else
		-- Targets and hardest shot: a missed puck stays on the ice where it went, so you can see the
		-- miss, and comes back to the spot once it has stopped, or after a while if it is still
		-- sliding away (MISS_RETURN seconds untouched), or straight away if it leaves the area.
		local speed = Vector3.new(puck.vel.X, 0, puck.vel.Z).Magnitude
		local stopped = speed < 1 and fromSpot > 3 and pw.idle > 1.2
		local gone = fromSpot > 3 and pw.idle > MISS_RETURN
		local away = (Vector3.new(puck.pos.X, 0, puck.pos.Z) - station.area).Magnitude > PondLayout.AREA_RADIUS
		if game.puck.resetAt == 0 and (stopped or gone or away) then
			if station.id == "Speed" and game.shotLive then
				game.shotLive = false
				game.shots += 1
				progress(member, { id = "Speed", shots = game.shots, best = game.best, miss = true })
				if game.shots >= SPEED_SHOTS then
					finishGame(member, if game.best > 0 then `Hardest shot: {round1(game.best)} KPH` else "No shots on net. Try again!", if game.best > 0 then game.best else nil)
					return
				end
			end
			respawnGamePuck(game, 0)
		end
		if station.id == "Speed" and not game.shotLive and pw.touch1 == member.id and speed > 12 then
			game.shotLive = true
		end
	end
end

local function onGameGoal(member: Member, entry: PuckEntry, event: Sim.Event)
	local game = member.game
	if not game or game.puck ~= entry then
		return
	end
	local station = game.station
	if event.net ~= station.net then
		-- Into some other net: just bring it back.
		respawnGamePuck(game, 0.5)
		return
	end
	local net = L.nets[station.net]
	if station.id == "Targets" then
		local across = event.z - net.z
		local height = entry.world.puck.pos.Y
		local r = PondLayout.TARGET_RADIUS
		for i, t in PondLayout.TARGETS do
			if not game.hits[i] then
				local dx, dy = across - t.X, height - t.Y
				if dx * dx + dy * dy <= r * r then
					game.hits[i] = true
					local count = 0
					for _, hit in game.hits do
						count += if hit then 1 else 0
					end
					progress(member, { id = "Targets", target = i, count = count })
					if count == 4 then
						local t2 = round1(elapsed(game))
						finishGame(member, `All four in {t2} s!`, t2)
						return
					end
					break
				end
			end
		end
		respawnGamePuck(game, 0.6)
	elseif station.id == "Slalom" then
		if game.startedAt > 0 and game.gate > #PondLayout.GATES then
			local t2 = round1(elapsed(game))
			finishGame(member, `Slalom done in {t2} s!`, t2)
			return
		end
		progress(member, { id = "Slalom", text = "Go through every gate first. Back to the start ring!" })
		game.gate = 1
		game.startedAt = 0
		respawnGamePuck(game, 0.6)
	elseif station.id == "Speed" then
		local speed = event.strength
		game.shotLive = false
		game.shots += 1
		game.best = math.max(game.best, speed)
		progress(member, { id = "Speed", shots = game.shots, best = round1(game.best), speed = round1(speed) })
		if game.shots >= SPEED_SHOTS then
			finishGame(member, `Hardest shot: {round1(game.best)} KPH`, round1(game.best))
			return
		end
		respawnGamePuck(game, 0.6)
	end
end

---------------------------------------------------------------------------------------------
-- Joining and leaving
---------------------------------------------------------------------------------------------

function PondService.init(remotes: { snapshot: any, cue: any, event: any }, look: (Player) -> any)
	snapshotRemote = remotes.snapshot
	cueRemote = remotes.cue
	eventRemote = remotes.event
	lookOf = look
end

function PondService.has(player: Player): boolean
	return members[player] ~= nil
end

function PondService.count(): number
	local n = 0
	for _ in members do
		n += 1
	end
	return n
end

-- Puts the player on the pond. False when the pond is full.
function PondService.join(player: Player): boolean
	if members[player] then
		return true
	end
	local id: number? = nil
	for i = 1, PondLayout.MAX_SKATERS do
		if not byId[i] then
			id = i
			break
		end
	end
	if not id then
		eventRemote:FireClient(player, { kind = "Full" })
		return false
	end
	local s = Sim.newSkater(id, 1)
	-- Arrivals spread round the spawn so nobody lands inside someone else.
	local a = (id - 1) / PondLayout.MAX_SKATERS * math.pi * 2
	local at = PondLayout.SPAWN + Vector3.new(math.cos(a) * 9, 0, math.sin(a) * 9)
	local outer = Sim.useLayout(L)
	World.placeSkater(s, at)
	Sim.useLayout(outer)
	local member: Member = {
		player = player,
		id = id,
		skater = s,
		queue = {},
		lastSeq = 0,
		ack = 0,
		repeated = 0,
		ownPucks = {},
		pad = {},
		padLocked = {},
		game = nil,
		prevPos = s.pos,
	}
	members[player] = member
	byId[id] = member
	table.insert(world.skaters, s)
	send(member, { kind = "Welcome", you = id })
	PondService.refreshRoster()
	send(member, recordsPayload())
	return true
end

function PondService.leave(player: Player)
	local member = members[player]
	if not member then
		return
	end
	if member.game then
		finishGame(member, "Game ended.", nil)
	end
	for _, entry in member.ownPucks do
		removePuck(entry)
	end
	table.clear(member.ownPucks)
	members[player] = nil
	byId[member.id] = nil
	local i = table.find(world.skaters, member.skater)
	if i then
		table.remove(world.skaters, i)
	end
	PondService.refreshRoster()
end

-- Input frames from a pond player (the same packets as a match; only intent).
function PondService.queueFrames(player: Player, frames: { Protocol.Frame })
	local member = members[player]
	if not member then
		return
	end
	for _, frame in frames do
		if frame.seq > member.lastSeq then
			member.lastSeq = frame.seq
			table.insert(member.queue, frame)
		end
	end
	if #member.queue > SEC.MaxQueuedFrames then
		local excess = #member.queue - SEC.TrimQueueTo
		table.move(member.queue, excess + 1, #member.queue, 1)
		for i = #member.queue, #member.queue - excess + 1, -1 do
			member.queue[i] = nil
		end
	end
end

-- Your own pucks: each press drops one in front of you, up to PondLayout.OWN_PUCKS. After that
-- (or when the pond is out of pucks) your oldest one is brought back to you instead.
function PondService.addPuck(player: Player)
	local member = members[player]
	if not member then
		return
	end
	local at = aheadOf(member.skater, 6)
	local own = member.ownPucks
	if #own < PondLayout.OWN_PUCKS then
		local entry = addPuck("Own", at, world.skaters, member)
		if entry then
			table.insert(own, entry)
			return
		end
	end
	local oldest = table.remove(own, 1)
	if oldest then
		placePuck(oldest, at)
		table.insert(own, oldest)
	end
end

---------------------------------------------------------------------------------------------
-- The step
---------------------------------------------------------------------------------------------

local function consumeInputs()
	for _, member in members do
		local input = member.skater.input
		local frame = table.remove(member.queue, 1)
		if frame then
			member.ack = frame.seq
			member.repeated = 0
			input.moveX, input.moveZ = frame.moveX, frame.moveZ
			input.aimX, input.aimZ = frame.aimX, frame.aimZ
			input.charge, input.sprint = frame.charge, frame.sprint
			input.lift, input.loft, input.brake = frame.lift, frame.loft, frame.brake
		else
			member.repeated += 1
			if member.repeated > SEC.MaxRepeatedTicks then
				input.moveX, input.moveZ = 0, 0
				input.charge, input.sprint = false, false
				input.lift, input.loft, input.brake = false, false, false
			end
		end
	end
	-- Studio test skaters wander in slow circles.
	for i, bot in bots do
		local a = world.time * 0.5 + i * 1.7
		bot.input.moveX, bot.input.moveZ = math.cos(a) * 0.6, math.sin(a) * 0.6
	end
end

local function cue(kind: string, x: number, z: number, strength: number, budget: { n: number })
	local id = CUE_KINDS[kind]
	if not id or budget.n >= MAX_CUES_PER_TICK then
		return
	end
	budget.n += 1
	for _, member in members do
		local dx, dz = member.skater.pos.X - x, member.skater.pos.Z - z
		if dx * dx + dz * dz < CUE_RANGE * CUE_RANGE then
			cueRemote:FireClient(member.player, id, x, z, strength)
		end
	end
end

local function handleEvents(entry: PuckEntry, budget: { n: number })
	for _, event in World.drainEvents(entry.world) do
		local kind = event.kind
		if kind == "Goal" then
			if entry.kind == "Game" and entry.owner then
				onGameGoal(entry.owner, entry, event)
			else
				entry.resetAt = world.time + 1.5
			end
			-- Goal lights and horn for whoever is near that net.
			local net = event.net and L.nets[event.net]
			if net then
				local payload = { kind = "Goal", net = event.net, x = event.x, z = event.z, speed = event.strength, scorer = event.scorer, game = entry.kind == "Game" }
				for _, member in members do
					local dx, dz = member.skater.pos.X - net.x, member.skater.pos.Z - net.z
					if dx * dx + dz * dz < GOAL_FX_RANGE * GOAL_FX_RANGE or member.id == event.scorer then
						send(member, payload)
					end
				end
			end
		elseif kind == "Stuck" then
			if entry.kind == "Game" and entry.owner and entry.owner.game then
				respawnGamePuck(entry.owner.game, 0)
			else
				placePuck(entry, homeOf(entry))
			end
		else
			cue(kind, event.x, event.z, event.strength, budget)
		end
	end
end

local snapshotTick = 0

local function sendSnapshot(stateTime: number)
	local skaterCount = #world.skaters
	local puckCount = #pucks
	local b = buffer.create(Protocol.pondSnapshotBytes(skaterCount, puckCount))
	Protocol.writePondHeader(b, world.tick, stateTime, skaterCount, puckCount)
	for i, s in world.skaters do
		local member = byId[s.slot]
		local flags = (if s.stickState == Sim.WINDING then 1 else 0)
			+ (if s.stickState == Sim.ACTIVE then 2 else 0)
			+ (if s.sprinting then 4 else 0)
			+ (if s.stun > 0 then 8 else 0)
			+ (if s.lifted then 16 else 0)
			+ (if s.lofting then 32 else 0)
			+ (if s.spinLock > 0 then 64 else 0)
		Protocol.writePondSkater(b, i, s.slot, s.pos.X, s.pos.Z, s.vel.X, s.vel.Z, s.aimYaw, s.aimRadius, flags, s.charge, s.stamina, if member then member.ack else 0, s.spin)
	end
	for i, entry in pucks do
		local p = entry.world.puck
		Protocol.writePondPuck(b, skaterCount, i, entry.id, entry.kind == "Game", if entry.owner then entry.owner.id else 0, p.pos, p.vel)
	end
	for _, member in members do
		snapshotRemote:FireClient(member.player, b)
	end
end

-- One fixed tick of the pond. stateTime: the server time this state belongs to.
function PondService.step(stateTime: number)
	if not next(members) then
		return
	end
	local outer = Sim.useLayout(L)
	consumeInputs()
	for _, member in members do
		member.prevPos = member.skater.pos
		checkPads(member)
	end

	World.step(world, TICK)
	for i = 2, #pucks do
		local entry = pucks[i]
		local w = entry.world
		entry.prev = w.puck.pos
		w.tick += 1
		w.time += TICK
		w.idle += TICK
		World.stepPuck(w, TICK)
	end
	-- Build 31: the shared pucks (not private mini-game ones) knock into each other.
	local budget = { n = 0 }
	do
		local shared = {}
		for _, entry in pucks do
			if entry.kind ~= "Game" then
				table.insert(shared, entry.world)
			end
		end
		local outerLayout = Sim.useLayout(L)
		local hit, hx, hz = World.collidePucks(shared)
		Sim.useLayout(outerLayout)
		if hit > 8 then
			cue("Hit", hx, hz, math.min(hit, 60), budget)
		end
	end

	-- Copy: a goal can end a game, which removes its puck from the list.
	for _, entry in table.clone(pucks) do
		handleEvents(entry, budget)
	end
	for _, entry in table.clone(pucks) do
		local w = entry.world
		if entry.resetAt > 0 and world.time >= entry.resetAt then
			if entry.kind == "Game" then
				entry.resetAt = 0
				placePuck(entry, entry.home)
			else
				placePuck(entry, homeOf(entry))
			end
		elseif entry.kind ~= "Game" and entry ~= pucks[1] then
			-- Shared pucks: one resting dead in a net, or left alone a long while, goes home.
			if (w.idle >= 2 and World.deadInNet(w)) or w.idle >= PUCK_IDLE_HOME then
				placePuck(entry, homeOf(entry))
			end
		end
	end
	for _, member in members do
		stepGame(member)
	end

	snapshotTick += 1
	local every = if Protocol.pondSnapshotBytes(#world.skaters, #pucks) <= FULL_RATE_BYTES then 1 else 2
	if snapshotTick % every == 0 then
		sendSnapshot(stateTime)
	end
	Sim.useLayout(outer)
end

-- Studio only: a hook for play tests (teleport, place a game shot, add wandering skaters, read
-- the state). A BindableFunction in ServerStorage, so no client can reach it, and it is never
-- made on a live server.
if RunService:IsStudio() then
	local function memberOf(userId: number): Member?
		for player, member in members do
			if player.UserId == userId then
				return member
			end
		end
		return nil
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "PondTestHook"
	hook.OnInvoke = function(command: string, ...: any): any
		local args = { ... }
		if command == "state" then
			local lines = {}
			for player, member in members do
				local s = member.skater
				local line = `{player.Name} id={member.id} pos=({math.round(s.pos.X)},{math.round(s.pos.Z)})`
				local g = member.game
				if g then
					local hits = {}
					for i, hit in g.hits do
						hits[i] = if hit then "1" else "0"
					end
					line ..= ` game={g.station.id} hits={table.concat(hits)} gate={g.gate} shots={g.shots} best={round1(g.best)} clock={g.startedAt > 0}`
				end
				table.insert(lines, line)
			end
			for _, entry in pucks do
				local p = entry.world.puck.pos
				table.insert(lines, `puck {entry.id} {entry.kind} ({round1(p.X)},{round1(p.Y)},{round1(p.Z)})`)
			end
			for id, r in records do
				table.insert(lines, `record {id} {r.name} {r.value}`)
			end
			table.insert(lines, `skaters={#world.skaters} bots={#bots}`)
			return table.concat(lines, "\n")
		elseif command == "teleport" then
			local member = memberOf(args[1])
			if member then
				local outer = Sim.useLayout(L)
				World.placeSkater(member.skater, args[2])
				Sim.useLayout(outer)
				member.prevPos = member.skater.pos
				if args[3] then
					member.skater.vel = args[3]
				end
			end
		elseif command == "shoot" then
			-- Puts the member's mini-game puck at pos with vel, as if they had just shot it.
			local member = memberOf(args[1])
			local g = member and member.game
			if member and g then
				placePuck(g.puck, args[2])
				local w = g.puck.world
				w.puck.pos = args[2]
				w.puck.vel = args[3]
				w.touch1 = member.id
				if g.station.id == "Speed" then
					g.shotLive = true
				end
			end
		elseif command == "bots" then
			for i = 1, args[1] or 3 do
				local s = Sim.newSkater(40 + #bots, 1)
				local outer = Sim.useLayout(L)
				World.placeSkater(s, PondLayout.SPAWN + Vector3.new(10 + i * 6, 0, 12))
				Sim.useLayout(outer)
				table.insert(bots, s)
				table.insert(world.skaters, s)
			end
		elseif command == "clearBots" then
			for _, s in bots do
				local i = table.find(world.skaters, s)
				if i then
					table.remove(world.skaters, i)
				end
			end
			table.clear(bots)
		end
		return "ok"
	end
	hook.Parent = game:GetService("ServerStorage")
end

Players.PlayerRemoving:Connect(function(player: Player)
	PondService.leave(player)
end)

return PondService
