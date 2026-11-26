--!strict
-- Wire format. Everything is integers in fixed-size buffers: compact, versioned, and a NaN
-- cannot be expressed. Clients never send a position, score, puck state or inventory.

local Protocol = {}

Protocol.VERSION = 1
Protocol.SLOTS = 6

Protocol.Remotes = {
	Input = "Input", -- UnreliableRemoteEvent, client to server
	Snapshot = "Snapshot", -- UnreliableRemoteEvent, server to clients
	Cue = "Cue", -- UnreliableRemoteEvent, server to clients (impact sounds and sparks)
	State = "State", -- RemoteEvent, server to clients (phase, score, roster)
	Goal = "Goal", -- RemoteEvent, server to clients
	Action = "Action", -- RemoteEvent, client to server (fixed allowlist)
	Profile = "Profile", -- RemoteEvent, server to owner (coins, XP, items, stats)
	Shop = "Shop", -- RemoteEvent, client to server (Buy / Equip), validated against Catalog
	Reward = "Reward", -- RemoteEvent, server to owner (match rewards)
	Notice = "Notice", -- RemoteEvent, server to owner (short toast text)
	Rankings = "Rankings", -- RemoteEvent, server to clients (global top 50 boards)
	PondSnapshot = "PondSnapshot", -- UnreliableRemoteEvent, server to pond players (everyone on the pond)
	PondCue = "PondCue", -- UnreliableRemoteEvent, server to pond players (impact sounds)
	PondEvent = "PondEvent", -- RemoteEvent, server to pond players (roster, mini games, goals)
	Idle = "Idle", -- RemoteEvent, server to owner (idle warning: seconds left, 0 = sent to the lobby, -1 = cleared)
}

-- Global boards shown on the RANKINGS tab, keyed by the career stat they rank.
Protocol.RankingStats = { "points", "wins", "goals", "assists", "saves", "shots" }

Protocol.Actions = { Hello = true, Play = true, Leave = true, Pond = true, LeavePond = true, PlayPond = true, PondPuck = true, Again = true, SkipReplay = true, TutorialStart = true, TutorialDone = true, StillHere = true, ClaimLogin = true }

Protocol.CueKinds = { Hit = 1, Shot = 2, Board = 3, Post = 4, Check = 5, Body = 6, Save = 7, Bottle = 8, Land = 9, BodyAir = 10 }

export type Frame = {
	seq: number,
	moveX: number,
	moveZ: number,
	aimX: number,
	aimZ: number,
	charge: boolean,
	sprint: boolean,
	lift: boolean?,
	loft: boolean?,
	brake: boolean?,
}

export type SkaterSnap = {
	x: number,
	z: number,
	vx: number,
	vz: number,
	yaw: number,
	radius: number,
	charging: boolean,
	active: boolean,
	sprinting: boolean,
	stunned: boolean,
	lifted: boolean,
	lofting: boolean,
	spunOut: boolean,
	charge: number,
	stamina: number,
	spin: number,
	ack: number,
}

export type Snapshot = {
	tick: number,
	time: number,
	puckX: number,
	puckY: number,
	puckZ: number,
	puckVx: number,
	puckVz: number,
	puckVy: number,
	skaters: { SkaterSnap },
}

local FRAME_BYTES = 11
local INPUT_HEADER = 4
local POS_SCALE = 32
local VEL_SCALE = 32
local YAW_SCALE = 32767 / math.pi
local SKATER_BYTES = 19
local SNAP_HEADER = 13 + 12

Protocol.SNAPSHOT_BYTES = SNAP_HEADER + SKATER_BYTES * Protocol.SLOTS

local function i16(n: number): number
	return math.clamp(math.round(n), -32768, 32767)
end

local function i8(n: number): number
	return math.clamp(math.round(n * 127), -127, 127)
end

function Protocol.encodeInput(phaseId: number, frames: { Frame }, first: number, last: number): buffer
	local count = last - first + 1
	local b = buffer.create(INPUT_HEADER + count * FRAME_BYTES)
	buffer.writeu8(b, 0, Protocol.VERSION)
	buffer.writeu16(b, 1, phaseId % 65536)
	buffer.writeu8(b, 3, count)
	local o = INPUT_HEADER
	for i = first, last do
		local f = frames[i]
		buffer.writeu32(b, o, f.seq)
		buffer.writei8(b, o + 4, i8(f.moveX))
		buffer.writei8(b, o + 5, i8(f.moveZ))
		buffer.writei16(b, o + 6, i16(f.aimX * 32767))
		buffer.writei16(b, o + 8, i16(f.aimZ * 32767))
		buffer.writeu8(b, o + 10, (if f.charge then 1 else 0) + (if f.sprint then 2 else 0) + (if f.lift then 4 else 0) + (if f.loft then 8 else 0) + (if f.brake then 16 else 0))
		o += FRAME_BYTES
	end
	return b
end

-- Returns nil for anything malformed. Never errors, whatever a client sends.
function Protocol.decodeInput(b: any, maxFrames: number): (number?, { Frame }?)
	if typeof(b) ~= "buffer" then
		return nil, nil
	end
	local len = buffer.len(b)
	if len < INPUT_HEADER + FRAME_BYTES then
		return nil, nil
	end
	if buffer.readu8(b, 0) ~= Protocol.VERSION then
		return nil, nil
	end
	local count = buffer.readu8(b, 3)
	if count < 1 or count > maxFrames or len ~= INPUT_HEADER + count * FRAME_BYTES then
		return nil, nil
	end
	local phaseId = buffer.readu16(b, 1)
	local frames = table.create(count)
	local o = INPUT_HEADER
	for i = 1, count do
		local flags = buffer.readu8(b, o + 10)
		local moveX, moveZ = buffer.readi8(b, o + 4) / 127, buffer.readi8(b, o + 5) / 127
		local aimX, aimZ = buffer.readi16(b, o + 6) / 32767, buffer.readi16(b, o + 8) / 32767
		if flags > 31 or moveX * moveX + moveZ * moveZ > 1.05 or aimX * aimX + aimZ * aimZ > 1.05 then
			return nil, nil
		end
		frames[i] = {
			seq = buffer.readu32(b, o),
			moveX = moveX,
			moveZ = moveZ,
			aimX = aimX,
			aimZ = aimZ,
			charge = bit32.btest(flags, 1),
			sprint = bit32.btest(flags, 2),
			lift = bit32.btest(flags, 4),
			loft = bit32.btest(flags, 8),
			brake = bit32.btest(flags, 16),
		}
		o += FRAME_BYTES
	end
	return phaseId, frames
end

function Protocol.writeSnapshotHeader(b: buffer, tick: number, time: number, px: number, py: number, pz: number, vx: number, vz: number, vy: number?)
	buffer.writeu8(b, 0, Protocol.VERSION)
	buffer.writeu32(b, 1, tick)
	buffer.writef64(b, 5, time)
	buffer.writei16(b, 13, i16(px * POS_SCALE))
	buffer.writei16(b, 15, i16(py * POS_SCALE))
	buffer.writei16(b, 17, i16(pz * POS_SCALE))
	buffer.writei16(b, 19, i16(vx * VEL_SCALE))
	buffer.writei16(b, 21, i16(vz * VEL_SCALE))
	buffer.writei16(b, 23, i16((vy or 0) * VEL_SCALE))
end

local function writeSkaterAt(
	b: buffer,
	o: number,
	x: number,
	z: number,
	vx: number,
	vz: number,
	yaw: number,
	radius: number,
	flags: number,
	charge: number,
	stamina: number,
	ack: number,
	spin: number?
)
	buffer.writei16(b, o, i16(x * POS_SCALE))
	buffer.writei16(b, o + 2, i16(z * POS_SCALE))
	buffer.writei16(b, o + 4, i16(vx * VEL_SCALE))
	buffer.writei16(b, o + 6, i16(vz * VEL_SCALE))
	buffer.writei16(b, o + 8, i16(yaw * YAW_SCALE))
	buffer.writeu8(b, o + 10, math.clamp(math.round(radius * 255), 0, 255))
	buffer.writeu8(b, o + 11, flags)
	buffer.writeu8(b, o + 12, math.clamp(math.round(charge * 255), 0, 255))
	buffer.writeu8(b, o + 13, math.clamp(math.round(stamina * 255), 0, 255))
	buffer.writeu32(b, o + 14, ack)
	buffer.writeu8(b, o + 18, math.clamp(math.round((spin or 1) * 255), 0, 255))
end

function Protocol.writeSnapshotSkater(
	b: buffer,
	index: number,
	x: number,
	z: number,
	vx: number,
	vz: number,
	yaw: number,
	radius: number,
	flags: number,
	charge: number,
	stamina: number,
	ack: number,
	spin: number?
)
	writeSkaterAt(b, SNAP_HEADER + (index - 1) * SKATER_BYTES, x, z, vx, vz, yaw, radius, flags, charge, stamina, ack, spin)
end

function Protocol.newSnapshot(): Snapshot
	local skaters = table.create(Protocol.SLOTS)
	for i = 1, Protocol.SLOTS do
		skaters[i] = {
			x = 0, z = 0, vx = 0, vz = 0, yaw = 0, radius = 0.7,
			charging = false, active = false, sprinting = false, stunned = false, lifted = false, lofting = false,
			spunOut = false, charge = 0, stamina = 1, spin = 1, ack = 0,
		}
	end
	return { tick = 0, time = 0, puckX = 0, puckY = 0, puckZ = 0, puckVx = 0, puckVz = 0, puckVy = 0, skaters = skaters }
end

local function readSkaterAt(b: buffer, o: number, s: SkaterSnap)
	s.x = buffer.readi16(b, o) / POS_SCALE
	s.z = buffer.readi16(b, o + 2) / POS_SCALE
	s.vx = buffer.readi16(b, o + 4) / VEL_SCALE
	s.vz = buffer.readi16(b, o + 6) / VEL_SCALE
	s.yaw = buffer.readi16(b, o + 8) / YAW_SCALE
	s.radius = buffer.readu8(b, o + 10) / 255
	local flags = buffer.readu8(b, o + 11)
	s.charging = bit32.btest(flags, 1)
	s.active = bit32.btest(flags, 2)
	s.sprinting = bit32.btest(flags, 4)
	s.stunned = bit32.btest(flags, 8)
	s.lifted = bit32.btest(flags, 16)
	s.lofting = bit32.btest(flags, 32)
	s.spunOut = bit32.btest(flags, 64)
	s.charge = buffer.readu8(b, o + 12) / 255
	s.stamina = buffer.readu8(b, o + 13) / 255
	s.ack = buffer.readu32(b, o + 14)
	s.spin = buffer.readu8(b, o + 18) / 255
end

-- Decodes into a reused table so the ring buffer allocates nothing per snapshot.
function Protocol.readSnapshot(b: buffer, into: Snapshot): boolean
	if buffer.len(b) ~= Protocol.SNAPSHOT_BYTES or buffer.readu8(b, 0) ~= Protocol.VERSION then
		return false
	end
	into.tick = buffer.readu32(b, 1)
	into.time = buffer.readf64(b, 5)
	into.puckX = buffer.readi16(b, 13) / POS_SCALE
	into.puckY = buffer.readi16(b, 15) / POS_SCALE
	into.puckZ = buffer.readi16(b, 17) / POS_SCALE
	into.puckVx = buffer.readi16(b, 19) / VEL_SCALE
	into.puckVz = buffer.readi16(b, 21) / VEL_SCALE
	into.puckVy = buffer.readi16(b, 23) / VEL_SCALE
	for i = 1, Protocol.SLOTS do
		readSkaterAt(b, SNAP_HEADER + (i - 1) * SKATER_BYTES, into.skaters[i])
	end
	return true
end

-- The pond: any number of skaters (each with its pond id) and pucks, every snapshot sized to fit.
-- Header: version, tick, time, skater count, puck count. Skater: id + the match skater block.
-- Puck: id, flags (1 = private to its owner), owner id, position and velocity.
local POND_HEADER = 15
local POND_SKATER = 1 + SKATER_BYTES
local POND_PUCK = 15

export type PondPuckSnap = { id: number, private: boolean, owner: number, x: number, y: number, z: number, vx: number, vy: number, vz: number }
export type PondSkaterSnap = SkaterSnap & { id: number }
export type PondSnapshot = {
	tick: number,
	time: number,
	skaterCount: number,
	puckCount: number,
	skaters: { PondSkaterSnap },
	pucks: { PondPuckSnap },
	skaterById: { [number]: PondSkaterSnap },
	puckById: { [number]: PondPuckSnap },
}

function Protocol.pondSnapshotBytes(skaters: number, pucks: number): number
	return POND_HEADER + POND_SKATER * skaters + POND_PUCK * pucks
end

function Protocol.writePondHeader(b: buffer, tick: number, time: number, skaters: number, pucks: number)
	buffer.writeu8(b, 0, Protocol.VERSION)
	buffer.writeu32(b, 1, tick)
	buffer.writef64(b, 5, time)
	buffer.writeu8(b, 13, skaters)
	buffer.writeu8(b, 14, pucks)
end

function Protocol.writePondSkater(
	b: buffer,
	index: number,
	id: number,
	x: number,
	z: number,
	vx: number,
	vz: number,
	yaw: number,
	radius: number,
	flags: number,
	charge: number,
	stamina: number,
	ack: number,
	spin: number?
)
	local o = POND_HEADER + (index - 1) * POND_SKATER
	buffer.writeu8(b, o, id)
	writeSkaterAt(b, o + 1, x, z, vx, vz, yaw, radius, flags, charge, stamina, ack, spin)
end

function Protocol.writePondPuck(b: buffer, skaters: number, index: number, id: number, private: boolean, owner: number, pos: Vector3, vel: Vector3)
	local o = POND_HEADER + POND_SKATER * skaters + (index - 1) * POND_PUCK
	buffer.writeu8(b, o, id)
	buffer.writeu8(b, o + 1, if private then 1 else 0)
	buffer.writeu8(b, o + 2, owner)
	buffer.writei16(b, o + 3, i16(pos.X * POS_SCALE))
	buffer.writei16(b, o + 5, i16(pos.Y * POS_SCALE))
	buffer.writei16(b, o + 7, i16(pos.Z * POS_SCALE))
	buffer.writei16(b, o + 9, i16(vel.X * VEL_SCALE))
	buffer.writei16(b, o + 11, i16(vel.Y * VEL_SCALE))
	buffer.writei16(b, o + 13, i16(vel.Z * VEL_SCALE))
end

function Protocol.newPondSnapshot(): PondSnapshot
	return { tick = 0, time = 0, skaterCount = 0, puckCount = 0, skaters = {}, pucks = {}, skaterById = {}, puckById = {} }
end

local function blankSkater(): any
	return {
		id = 0, x = 0, z = 0, vx = 0, vz = 0, yaw = 0, radius = 0.7,
		charging = false, active = false, sprinting = false, stunned = false, lifted = false, lofting = false,
		spunOut = false, charge = 0, stamina = 1, spin = 1, ack = 0,
	}
end

-- Decodes into a reused table (entries are reused too). False for anything malformed.
function Protocol.readPondSnapshot(b: buffer, into: PondSnapshot): boolean
	local len = buffer.len(b)
	if len < POND_HEADER or buffer.readu8(b, 0) ~= Protocol.VERSION then
		return false
	end
	local ns, np = buffer.readu8(b, 13), buffer.readu8(b, 14)
	if len ~= Protocol.pondSnapshotBytes(ns, np) then
		return false
	end
	into.tick = buffer.readu32(b, 1)
	into.time = buffer.readf64(b, 5)
	into.skaterCount, into.puckCount = ns, np
	table.clear(into.skaterById)
	table.clear(into.puckById)
	for i = 1, ns do
		local o = POND_HEADER + (i - 1) * POND_SKATER
		local s = into.skaters[i]
		if not s then
			s = blankSkater()
			into.skaters[i] = s
		end
		s.id = buffer.readu8(b, o)
		readSkaterAt(b, o + 1, s)
		into.skaterById[s.id] = s
	end
	for i = 1, np do
		local o = POND_HEADER + POND_SKATER * ns + (i - 1) * POND_PUCK
		local p = into.pucks[i]
		if not p then
			p = { id = 0, private = false, owner = 0, x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0 }
			into.pucks[i] = p
		end
		p.id = buffer.readu8(b, o)
		p.private = buffer.readu8(b, o + 1) == 1
		p.owner = buffer.readu8(b, o + 2)
		p.x = buffer.readi16(b, o + 3) / POS_SCALE
		p.y = buffer.readi16(b, o + 5) / POS_SCALE
		p.z = buffer.readi16(b, o + 7) / POS_SCALE
		p.vx = buffer.readi16(b, o + 9) / VEL_SCALE
		p.vy = buffer.readi16(b, o + 11) / VEL_SCALE
		p.vz = buffer.readi16(b, o + 13) / VEL_SCALE
		into.puckById[p.id] = p
	end
	return true
end

return Protocol
