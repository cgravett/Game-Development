--!strict
-- The one authoritative game model. Pure Luau with no engine physics or instances:
-- the server runs World, the client reuses stepMotion/stepStick for prediction, and
-- Training runs a local World. One puck-velocity writer, no tunnelling, no owned parts.

local Config = require(script.Parent.GameConfig)

local Sim = {}

local ARENA = Config.Arena
local GOAL = Config.Goal
local SKATER = Config.Skater
local STICK = Config.Stick
local PUCK = Config.Puck

local HX = ARENA.Length / 2
local HZ = ARENA.Width / 2
local CR = ARENA.CornerRadius
local HALF_MOUTH = GOAL.Width / 2
local PUCK_REST_Y = PUCK.Thickness / 2
local BODY_R = SKATER.CollisionRadius
local BOARD_R = SKATER.BoardRadius
local TOUCH_R = PUCK.Radius + STICK.BladeThickness
-- No shot ever flies over the net: the highest the puck's centre may reach, so its top stays
-- STICK.ShotCeilingGap under the crossbar. Every lift is capped from the height the blade meets
-- the puck (it can be met up to BladeDrawnHeight off the ice, where an uncapped flick cleared
-- the bar).
-- And no shot ever goes over a skater's head: every skater has the same standard hitbox
-- (PUCK.BodyHeight, whatever hat they wear), and the puck never rises above it, so a shot can't
-- sail over a goalie's head into the net.
local MAX_PUCK_Y = math.min(GOAL.CrossbarHeight - PUCK.Thickness / 2 - STICK.ShotCeilingGap, PUCK.BodyHeight - PUCK.Thickness / 2 - 0.05)
local function liftCap(up: number, y: number): number
	local room = MAX_PUCK_Y - y
	if room <= 0 then
		return math.min(up, 0)
	end
	return math.min(up, math.sqrt(2 * PUCK.Gravity * room))
end
Sim.MAX_PUCK_Y = MAX_PUCK_Y
-- A lofted flick spends what would have been height on distance: it leaves this much faster
-- along the ice (never past the puck's top speed).
local function loftCarry(x: number, z: number): (number, number)
	local m = math.sqrt(x * x + z * z)
	local k = STICK.LoftCarry
	if m * k > PUCK.MaxSpeed then
		k = PUCK.MaxSpeed / math.max(m, 1e-6)
	end
	return x * math.max(k, 1), z * math.max(k, 1)
end

-- The blade as drawn (Looks, classic stick): a straight, flat, rectangular blade. Points along it
-- from the heel, their sideways offset (negative = toward the forehand) and half-thickness, so
-- the puck stops right on the face you see, with no gap and no overlap.
local BLADE_ANGLE = STICK.BladeAngle
local BLADE_HALF = STICK.BladeLength / 2
local HEEL_R = STICK.Reach - BLADE_HALF -- the heel's distance out from the body, along the stick
local SHAPE_ALONG = { 0, 0.25 * STICK.BladeLength, 0.5 * STICK.BladeLength, 0.75 * STICK.BladeLength, STICK.BladeLength }
-- A very slight curve: the toe half bends STICK.BladeCurve along the blade's right (the backhand
-- face). BladeCurve is negative, so the toe hooks toward the forehand and the forehand face is
-- the hollow one, like a real curved blade. The drawn blade is two boxes that follow these
-- points exactly.
local SHAPE_SIDE = { 0, 0, 0, STICK.BladeCurve / 2, STICK.BladeCurve }
local SHAPE_HALF = { STICK.BladeThickness, STICK.BladeThickness, STICK.BladeThickness, STICK.BladeThickness, STICK.BladeThickness }

Sim.IDLE = 0
Sim.WINDING = 1
Sim.ACTIVE = 2
Sim.RECOVERY = 3

export type Input = {
	moveX: number,
	moveZ: number,
	aimX: number,
	aimZ: number,
	charge: boolean,
	sprint: boolean,
	lift: boolean?, -- hold to raise the blade over the puck
	loft: boolean?, -- hold to open the blade face so hits chip the puck up
	brake: boolean?, -- hold to stop hard
}

export type Skater = {
	slot: number,
	team: number,
	goalie: boolean,
	faceoffIdx: number?, -- Build 32: which face-off spot this skater takes (1 = the centre who takes the draw)
	pos: Vector3,
	vel: Vector3,
	stamina: number,
	staminaDelay: number,
	stun: number,
	sprinting: boolean,
	dashTimer: number,
	dashCooldown: number,
	dashSpeed: number, -- speed the current dash pushes toward
	carveSpin: number, -- current turn rate of the skater's travel (radians a second)
	carveAcc: number, -- current change of speed along the travel (studs a second, per second)
	wishX: number, -- the push the keys are asking for, eased toward them (see WishResponse)
	wishZ: number,
	sprintHeld: boolean,
	aimYaw: number,
	aimYawPrev: number, -- aim at the start of the tick, so substeps can sweep the blade
	aimRadius: number,
	blade: Vector3,
	bladePrev: Vector3,
	stickState: number,
	stickTimer: number,
	windTime: number,
	charge: number,
	swingSpeed: number,
	swingLift: number,
	swingUsed: boolean,
	lifted: boolean,
	lofting: boolean,
	cooldown: number,
	ignoreTimer: number,
	spin: number, -- spin meter, 1 = full; fast stick turns drain it
	spinLock: number, -- seconds left spun out (stick turns sluggishly)
	spinRest: number, -- calm seconds since the last fast turn
	input: Input,
}

export type Puck = { pos: Vector3, vel: Vector3 }

export type Event = {
	kind: string,
	x: number,
	z: number,
	strength: number,
	slot: number?,
	team: number?,
	scorer: number?,
	assist: number?,
	ownGoal: boolean?,
	net: number?, -- open-world goals: which net (index into the layout's nets)
	launchPos: Vector3?, -- Build 38: a Shot's puck position and velocity as it left the stick
	launchVel: Vector3?,
}

-- An open-world layout (The Pond): a lake shore to stay inside, solid blocks to stay outside,
-- thin two-sided board walls and any number of nets. nil everywhere means the match rink, whose
-- code path is untouched. Shapes are described in PondLayout.
export type Box = { cx: number, cz: number, hx: number, hz: number, cr: number }
export type Net = { x: number, z: number, side: number }
export type WallZone = { minX: number, maxX: number, minZ: number, maxZ: number, cx: number, cz: number, walls: { { number } } }
export type Layout = { bound: Box, blocks: { Box }, wallHalf: number, wallZones: { WallZone }, nets: { Net } }

export type World = {
	layout: Layout?, -- nil: the match rink
	skaters: { Skater },
	puck: Puck,
	tick: number,
	time: number,
	events: { Event },
	controlsEnabled: boolean,
	stickHits: boolean,
	goalsEnabled: boolean,
	goalLatched: boolean,
	puckHeld: boolean, -- face-off: the puck hangs in the air over the dot until play starts
	lastBodyCue: number,
	touch1: number?,
	touch2: number?,
	touchHistory: { number }, -- recent distinct touchers, newest first (goal credit)
	stickHistory: { number }, -- Build 32: the same, stick touches only (a bounce off a body takes no credit)
	idle: number,
	bottlesDown: { [number]: boolean }, -- by side: that net's drink bottle was knocked off (reset at the faceoff)
	bottleZ: { [number]: number }, -- Build 36: by side: where across the net top the bottle lies (practice moves it)
}

local function sign(n: number): number
	return if n < 0 then -1 else 1
end

local function clamp(n: number, a: number, b: number): number
	return if n < a then a elseif n > b then b else n
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function closestOnSegment(px: number, pz: number, ax: number, az: number, bx: number, bz: number): (number, number)
	local abx, abz = bx - ax, bz - az
	local len2 = abx * abx + abz * abz
	if len2 < 1e-9 then
		return ax, az
	end
	local t = clamp(((px - ax) * abx + (pz - az) * abz) / len2, 0, 1)
	return ax + abx * t, az + abz * t
end

-- The net's footprint, shared by the drawn net and every collision with it. Points are
-- (X = depth behind the goal line, Y = across the mouth), running from one post straight back,
-- round a wide curved corner, across the back and round to the other post. The mouth is open.
local NET_ARC_STEPS = 9
local NET_OUTLINE: { Vector2 } = {}
do
	local d, r = GOAL.Depth, GOAL.CornerRadius
	table.insert(NET_OUTLINE, Vector2.new(0, -HALF_MOUTH))
	-- A point where the top shelf ends, so the side walls follow the roof's kink.
	table.insert(NET_OUTLINE, Vector2.new(GOAL.ShelfDepth, -HALF_MOUTH))
	for i = 0, NET_ARC_STEPS do
		local a = -math.pi / 2 + (math.pi / 2) * i / NET_ARC_STEPS
		table.insert(NET_OUTLINE, Vector2.new(d - r + math.cos(a) * r, -(HALF_MOUTH - r) + math.sin(a) * r))
	end
	for i = 0, NET_ARC_STEPS do
		local a = (math.pi / 2) * i / NET_ARC_STEPS
		table.insert(NET_OUTLINE, Vector2.new(d - r + math.cos(a) * r, (HALF_MOUTH - r) + math.sin(a) * r))
	end
	table.insert(NET_OUTLINE, Vector2.new(GOAL.ShelfDepth, HALF_MOUTH))
	table.insert(NET_OUTLINE, Vector2.new(0, HALF_MOUTH))
	table.freeze(NET_OUTLINE)
end
Sim.NET_OUTLINE = NET_OUTLINE

-- Height of the net's top at a depth behind the goal line: flat over the shelf, then sloping
-- down to the back.
function Sim.netRoofAt(depth: number): number
	if depth <= GOAL.ShelfDepth then
		return GOAL.CrossbarHeight
	end
	local t = clamp((depth - GOAL.ShelfDepth) / (GOAL.Depth - GOAL.ShelfDepth), 0, 1)
	return GOAL.CrossbarHeight + (GOAL.BackHeight - GOAL.CrossbarHeight) * t
end

-- True when (depth behind the goal line, across) is inside the net's footprint.
function Sim.insideNet(depth: number, across: number): boolean
	if depth < 0 or depth > GOAL.Depth then
		return false
	end
	local r = GOAL.CornerRadius
	local straight = GOAL.Depth - r
	local half = HALF_MOUTH
	if depth > straight then
		local k = depth - straight
		half = HALF_MOUTH - r + math.sqrt(math.max(0, r * r - k * k))
	end
	return math.abs(across) <= half
end

function Sim.newInput(): Input
	return { moveX = 0, moveZ = 0, aimX = 0, aimZ = 0, charge = false, sprint = false, lift = false, loft = false, brake = false }
end

---------------------------------------------------------------------------------------------
-- Open-world layout (The Pond). World.step and World.stepPuck switch to the world's layout
-- for the step; the client's prediction sets it with Sim.useLayout while on the pond.
---------------------------------------------------------------------------------------------

local LAYOUT: Layout? = nil
-- Events raised while a net is checked in its own (shifted) frame are moved back by this much.
local EMIT_DX, EMIT_DZ = 0, 0

function Sim.useLayout(layout: Layout?): Layout?
	local old = LAYOUT
	LAYOUT = layout
	return old
end

function Sim.layout(): Layout?
	return LAYOUT
end

-- Signed distance from a rounded box (negative inside) and the outward normal.
local function boxSd(b: Box, x: number, z: number): (number, number, number)
	local lx, lz = x - b.cx, z - b.cz
	local qx, qz = math.abs(lx) - (b.hx - b.cr), math.abs(lz) - (b.hz - b.cr)
	if qx > 0 and qz > 0 then
		local d = math.sqrt(qx * qx + qz * qz)
		if d < 1e-6 then
			return -b.cr, sign(lx), 0
		end
		return d - b.cr, sign(lx) * qx / d, sign(lz) * qz / d
	end
	if qx > qz then
		return qx - b.cr, sign(lx), 0
	end
	return qz - b.cr, 0, sign(lz)
end
Sim.boxSd = boxSd

local function segmentsCross(ax: number, az: number, bx: number, bz: number, cx: number, cz: number, dx: number, dz: number): boolean
	local function orient(px: number, pz: number, qx: number, qz: number, rx: number, rz: number): number
		return (qx - px) * (rz - pz) - (qz - pz) * (rx - px)
	end
	local o1, o2 = orient(ax, az, bx, bz, cx, cz), orient(ax, az, bx, bz, dx, dz)
	local o3, o4 = orient(cx, cz, dx, dz, ax, az), orient(cx, cz, dx, dz, bx, bz)
	return o1 * o2 < 0 and o3 * o4 < 0
end

local function inZone(zone: WallZone, x: number, z: number): boolean
	return x >= zone.minX and x <= zone.maxX and z >= zone.minZ and z <= zone.maxZ
end

-- Distance from one wall's surface (its centre line less its half thickness) and the normal
-- away from it. On the centre line itself, the normal points into the rink the wall belongs to.
local function wallGapOne(L: Layout, zone: WallZone, wall: { number }, x: number, z: number): (number, number, number)
	local qx, qz = closestOnSegment(x, z, wall[1], wall[2], wall[3], wall[4])
	local dx, dz = x - qx, z - qz
	local d = math.sqrt(dx * dx + dz * dz)
	if d > 1e-6 then
		return d - L.wallHalf, dx / d, dz / d
	end
	local ex, ez = wall[3] - wall[1], wall[4] - wall[2]
	local len = math.max(1e-6, math.sqrt(ex * ex + ez * ez))
	local nx, nz = -ez / len, ex / len
	if nx * (zone.cx - qx) + nz * (zone.cz - qz) < 0 then
		nx, nz = -nx, -nz
	end
	return -L.wallHalf, nx, nz
end

-- Free distance from the nearest obstacle (shore, block or wall) and the normal into free space.
local function pondClear(x: number, z: number): (number, number, number)
	local L = LAYOUT :: Layout
	local d, nx, nz = boxSd(L.bound, x, z)
	local best, bnx, bnz = -d, -nx, -nz
	for _, b in L.blocks do
		local bd, bx, bz = boxSd(b, x, z)
		if bd < best then
			best, bnx, bnz = bd, bx, bz
		end
	end
	for _, zone in L.wallZones do
		if inZone(zone, x, z) then
			for _, wall in zone.walls do
				local g, gx, gz = wallGapOne(L, zone, wall, x, z)
				if g < best then
					best, bnx, bnz = g, gx, gz
				end
			end
		end
	end
	return best, bnx, bnz
end

-- True when the straight line between two points passes through a board wall.
local function crossesWall(ax: number, az: number, bx: number, bz: number): boolean
	local L = LAYOUT :: Layout
	for _, zone in L.wallZones do
		if inZone(zone, ax, az) or inZone(zone, bx, bz) then
			for _, wall in zone.walls do
				if segmentsCross(ax, az, bx, bz, wall[1], wall[2], wall[3], wall[4]) then
					return true
				end
			end
		end
	end
	return false
end

-- Keeps a circle of `radius` in free space: inside the shore, outside the blocks, off the walls.
local function pondBoards(p: Vector3, v: Vector3, radius: number, restitution: number, hugBelow: number?): (Vector3, Vector3, number)
	local L = LAYOUT :: Layout
	local hit = 0
	local function push(gap: number, nx: number, nz: number)
		if gap >= radius then
			return
		end
		p = Vector3.new(p.X + nx * (radius - gap), p.Y, p.Z + nz * (radius - gap))
		local vn = v.X * nx + v.Z * nz
		if vn < 0 then
			hit = math.max(hit, -vn)
			local e = if hugBelow and -vn < hugBelow then restitution * -vn / hugBelow else restitution
			local j = (1 + e) * vn
			v = Vector3.new(v.X - j * nx, v.Y, v.Z - j * nz)
		end
	end
	local d, nx, nz = boxSd(L.bound, p.X, p.Z)
	push(-d, -nx, -nz)
	for _, b in L.blocks do
		local bd, bx, bz = boxSd(b, p.X, p.Z)
		push(bd, bx, bz)
	end
	for _, zone in L.wallZones do
		if inZone(zone, p.X, p.Z) then
			for _, wall in zone.walls do
				local g, gx, gz = wallGapOne(L, zone, wall, p.X, p.Z)
				push(g, gx, gz)
			end
		end
	end
	return p, v, hit
end

-- The net (if any) within `range` of a point, and the shift that moves it onto the match rink's
-- net on the same side, so all of the match rink's net code runs on it unchanged.
local function netShift(x: number, z: number, range: number): (Net?, number, number)
	local L = LAYOUT :: Layout
	for _, n in L.nets do
		local depth = n.side * (x - n.x)
		if depth > -range and depth < GOAL.Depth + range and math.abs(z - n.z) < HALF_MOUTH + range then
			return n, n.side * GOAL.X - n.x, -n.z
		end
	end
	return nil, 0, 0
end

-- (depth behind the goal line, across the mouth) of a point, for the nearest net.
function Sim.netFrame(x: number, z: number): (number, number)
	if LAYOUT then
		local n = netShift(x, z, 2)
		if not n then
			return -100, 0
		end
		return n.side * (x - n.x), z - n.z
	end
	return math.abs(x) - GOAL.X, z
end

local function arenaInside(x: number, z: number, margin: number): boolean
	local ix, iz = HX - CR, HZ - CR
	local ax, az = math.abs(x), math.abs(z)
	if ax > ix and az > iz then
		local dx, dz = ax - ix, az - iz
		return dx * dx + dz * dz <= (CR - margin) * (CR - margin)
	end
	return ax <= HX - margin and az <= HZ - margin
end

local function insideRink(x: number, z: number, margin: number): boolean
	if LAYOUT then
		return pondClear(x, z) >= margin
	end
	return arenaInside(x, z, margin)
end
Sim.insideRink = insideRink

-- Distance from a point to the boards and the unit normal pointing back into the rink.
local function boardGap(x: number, z: number): (number, number, number)
	if LAYOUT then
		return pondClear(x, z)
	end
	local ix, iz = HX - CR, HZ - CR
	local ax, az = math.abs(x), math.abs(z)
	if ax > ix and az > iz then
		local dx, dz = ax - ix, az - iz
		local d = math.sqrt(dx * dx + dz * dz)
		if d < 1e-4 then
			return CR, 0, 0
		end
		return CR - d, -sign(x) * dx / d, -sign(z) * dz / d
	end
	local gx, gz = HX - ax, HZ - az
	if gx < gz then
		return gx, -sign(x), 0
	end
	return gz, 0, -sign(z)
end
Sim.boardGap = boardGap

local TOE_LEN = STICK.BladeLength + 0.05
local TOE_SIDE = SHAPE_SIDE[#SHAPE_SIDE] -- the toe hooks this far toward the forehand
local MIN_HEEL = 0.2
local TIP_MARGIN = 0.3 -- the toe's half-thickness and tape, plus a little air before the boards

-- The toe's outer corner (hook included) for a stick at `yaw` whose heel sits `heelR` out
-- from the body.
local function toeAt(pos: Vector3, yaw: number, heelR: number): (number, number)
	local by = yaw + BLADE_ANGLE
	local dx, dz = math.cos(by), math.sin(by)
	local hx, hz = pos.X + math.cos(yaw) * heelR, pos.Z + math.sin(yaw) * heelR
	return hx + dx * TOE_LEN - dz * TOE_SIDE, hz + dz * TOE_LEN + dx * TOE_SIDE
end

-- True when a toe at (tx, tz), on a stick held by a body at pos, is clear of the boards. On the
-- pond the stick also may not reach through a board wall; a skater drawn inside the match rink
-- (seen from the pond) keeps the match rink's own rules.
local function tipOk(pos: Vector3, tx: number, tz: number): boolean
	local L = LAYOUT
	if not L then
		return insideRink(tx, tz, TIP_MARGIN)
	end
	if boxSd(L.blocks[1], pos.X, pos.Z) < 0 then
		return arenaInside(tx, tz, TIP_MARGIN)
	end
	return pondClear(tx, tz) >= TIP_MARGIN and not crossesWall(pos.X, pos.Z, tx, tz)
end

-- True when the blade's toe, held at full reach, is inside the boards.
function Sim.tipInside(pos: Vector3, yaw: number): boolean
	local tx, tz = toeAt(pos, yaw, HEEL_R)
	return tipOk(pos, tx, tz)
end

-- Which way the blade runs (heel to toe) for a stick at `yaw`.
function Sim.bladeYaw(yaw: number): number
	return yaw + BLADE_ANGLE
end

-- The stick is rigid, like part of the body: when its toe meets the boards, the boards push
-- the whole skater back (and bounce them off a little) instead of the stick sliding inward.
function Sim.resolveStick(pos: Vector3, vel: Vector3, yaw: number): (Vector3, Vector3)
	local tx, tz = toeAt(pos, yaw, HEEL_R)
	if LAYOUT and crossesWall(pos.X, pos.Z, tx, tz) then
		-- Reached through a board wall (it can't be turned there; this is a body sliding past
		-- the wall end): only the nets can still push it.
		return Sim.resolveStickNets(pos, vel, yaw)
	end
	local tip = Vector3.new(tx, 0, tz)
	local fixed, v = Sim.resolveBoards(tip, vel, TIP_MARGIN, SKATER.StickWallRestitution)
	local push = fixed - tip
	if push.X * push.X + push.Z * push.Z >= 1e-10 then
		pos, vel = Vector3.new(pos.X + push.X, pos.Y, pos.Z + push.Z), Vector3.new(v.X, vel.Y, v.Z)
	end
	-- The posts and the netting are just as solid to the stick.
	return Sim.resolveStickNets(pos, vel, yaw)
end

-- Turns the aim from `from` toward `to`, stopping where the toe would meet the boards.
function Sim.clampAim(pos: Vector3, from: number, to: number): number
	if Sim.tipInside(pos, to) or not Sim.tipInside(pos, from) then
		return to
	end
	local turn = wrapAngle(to - from)
	local lo, hi = 0, 1
	for _ = 1, 10 do
		local mid = (lo + hi) / 2
		if Sim.tipInside(pos, from + turn * mid) then
			lo = mid
		else
			hi = mid
		end
	end
	return wrapAngle(from + turn * lo)
end

function Sim.bladeAt(pos: Vector3, yaw: number, _radius: number): Vector3
	-- The blade always sits at the same tucked distance; only its angle around the body changes.
	-- Against the boards it slides in toward the body instead of poking through the glass.
	-- Returns the blade's centre: the heel sits out along the stick, the blade runs from it at
	-- BladeAngle toward the backhand.
	local r = HEEL_R
	local tx, tz = toeAt(pos, yaw, r)
	if not tipOk(pos, tx, tz) then
		local lo, hi = MIN_HEEL, r
		for _ = 1, 8 do
			local mid = (lo + hi) / 2
			local mx, mz = toeAt(pos, yaw, mid)
			if tipOk(pos, mx, mz) then
				lo = mid
			else
				hi = mid
			end
		end
		r = lo
	end
	local by = yaw + BLADE_ANGLE
	return Vector3.new(pos.X + math.cos(yaw) * r + math.cos(by) * BLADE_HALF, 0, pos.Z + math.sin(yaw) * r + math.sin(by) * BLADE_HALF)
end

function Sim.newSkater(slot: number, team: number): Skater
	local yaw = if team == 1 then 0 else math.pi
	local pos = Vector3.zero
	local blade = Sim.bladeAt(pos, yaw, 1)
	return {
		slot = slot,
		team = team,
		goalie = false,
		pos = pos,
		vel = Vector3.zero,
		stamina = 1,
		staminaDelay = 0,
		stun = 0,
		sprinting = false,
		dashTimer = 0,
		dashCooldown = 0,
		dashSpeed = 0,
		carveSpin = 0,
		carveAcc = 0,
		wishX = 0,
		wishZ = 0,
		sprintHeld = false,
		aimYaw = yaw,
		aimYawPrev = yaw,
		aimRadius = 1,
		blade = blade,
		bladePrev = blade,
		stickState = Sim.IDLE,
		stickTimer = 0,
		windTime = 0,
		charge = 0,
		swingSpeed = 0,
		swingLift = 0,
		swingUsed = true,
		lifted = false,
		lofting = false,
		cooldown = 0,
		ignoreTimer = 0,
		spin = 1,
		spinLock = 0,
		spinRest = 0,
		input = Sim.newInput(),
	}
end

-- Rink boundary: a rounded rectangle solved analytically, so nothing can tunnel through it.
-- hugBelow: a hit slower than this (into the boards) bounces less in proportion, down to none,
-- so a puck rimming round the boards rides them smoothly instead of skipping off them.
function Sim.resolveBoards(p: Vector3, v: Vector3, radius: number, restitution: number, hugBelow: number?): (Vector3, Vector3, number)
	if LAYOUT then
		return pondBoards(p, v, radius, restitution, hugBelow)
	end
	local ix, iz = HX - CR, HZ - CR
	local ax, az = math.abs(p.X), math.abs(p.Z)
	local hit = 0
	local function bounce(into: number): number
		if hugBelow and into < hugBelow then
			return restitution * into / hugBelow
		end
		return restitution
	end
	if ax > ix and az > iz then
		local dx, dz = ax - ix, az - iz
		local d = math.sqrt(dx * dx + dz * dz)
		local limit = CR - radius
		if d > limit then
			local sx, sz = sign(p.X), sign(p.Z)
			local ox, oz = dx / d, dz / d
			p = Vector3.new(sx * (ix + ox * limit), p.Y, sz * (iz + oz * limit))
			local nx, nz = -sx * ox, -sz * oz
			local vn = v.X * nx + v.Z * nz
			if vn < 0 then
				hit = -vn
				local j = (1 + bounce(-vn)) * vn
				v = Vector3.new(v.X - j * nx, v.Y, v.Z - j * nz)
			end
		end
	else
		if ax > HX - radius then
			local sx = sign(p.X)
			p = Vector3.new(sx * (HX - radius), p.Y, p.Z)
			if v.X * sx > 0 then
				hit = math.abs(v.X)
				v = Vector3.new(-v.X * bounce(hit), v.Y, v.Z)
			end
		end
		if az > HZ - radius then
			local sz = sign(p.Z)
			p = Vector3.new(p.X, p.Y, sz * (HZ - radius))
			if v.Z * sz > 0 then
				local into = math.abs(v.Z)
				hit = math.max(hit, into)
				v = Vector3.new(v.X, v.Y, -v.Z * bounce(into))
			end
		end
	end
	return p, v, hit
end

-- A skater can skate in through the open mouth of a net; its posts, sides and back are solid
-- from both sides.
local function netsForSkaterArena(p: Vector3, v: Vector3, radius: number): (Vector3, Vector3)
	local ax = math.abs(p.X)
	if ax < GOAL.X - radius - 0.5 or ax > GOAL.X + GOAL.Depth + radius + 0.5 or math.abs(p.Z) > HALF_MOUTH + radius + 0.5 then
		return p, v
	end
	local sx = sign(p.X)
	local lx, lz = ax - GOAL.X, p.Z
	for k = 1, #NET_OUTLINE - 1 do
		local a, b = NET_OUTLINE[k], NET_OUTLINE[k + 1]
		local qx, qz = closestOnSegment(lx, lz, a.X, a.Y, b.X, b.Y)
		local dx, dz = lx - qx, lz - qz
		local d2 = dx * dx + dz * dz
		if d2 < radius * radius then
			local nx, nz
			if d2 > 1e-8 then
				local d = math.sqrt(d2)
				nx, nz = dx / d, dz / d
			else
				-- Exactly on the netting: out of the net, away from its middle.
				local ex, ez = b.X - a.X, b.Y - a.Y
				local len = math.max(1e-6, math.sqrt(ex * ex + ez * ez))
				nx, nz = ez / len, -ex / len
				if nx * (qx - GOAL.Depth / 2) + nz * qz < 0 then
					nx, nz = -nx, -nz
				end
			end
			lx, lz = qx + nx * radius, qz + nz * radius
			local worldNx = nx * sx
			local vn = v.X * worldNx + v.Z * nz
			if vn < 0 then
				v = Vector3.new(v.X - vn * worldNx, v.Y, v.Z - vn * nz)
			end
		end
	end
	return Vector3.new(sx * (GOAL.X + lx), p.Y, lz), v
end

function Sim.resolveNetsForSkater(p: Vector3, v: Vector3, radius: number): (Vector3, Vector3)
	if LAYOUT then
		local n, ox, oz = netShift(p.X, p.Z, radius + 0.5)
		if not n then
			return p, v
		end
		local off = Vector3.new(ox, 0, oz)
		local q, w = netsForSkaterArena(p + off, v, radius)
		return q - off, w
	end
	return netsForSkaterArena(p, v, radius)
end

-- The stick against the nets: the shaft and the blade (hook included) are a row of small discs
-- that can't pass a post or the netting, from inside the net or out. Returns how far the skater
-- must move, and which way, to free the stick (0 when it is clear).
local STICK_W = STICK.StickHalfWidth
local SHAFT_IN = BODY_R * 0.8
local SHAFT_STEPS = 3

local function crosses(ax: number, az: number, bx: number, bz: number, cx: number, cz: number, dx: number, dz: number): boolean
	local function orient(px: number, pz: number, qx: number, qz: number, rx: number, rz: number): number
		return (qx - px) * (rz - pz) - (qz - pz) * (rx - px)
	end
	local o1, o2 = orient(ax, az, bx, bz, cx, cz), orient(ax, az, bx, bz, dx, dz)
	local o3, o4 = orient(cx, cz, dx, dz, ax, az), orient(cx, cz, dx, dz, bx, bz)
	return o1 * o2 < 0 and o3 * o4 < 0
end

local function stickNetPushArena(pos: Vector3, yaw: number): (number, number, number)
	local ax = math.abs(pos.X)
	if ax < GOAL.X - 8 or ax > GOAL.X + GOAL.Depth + 8 or math.abs(pos.Z) > HALF_MOUTH + 8 then
		return 0, 0, 0
	end
	local sx = sign(pos.X)
	local c, sn = math.cos(yaw), math.sin(yaw)
	local by = yaw + BLADE_ANGLE
	local dx, dz = math.cos(by), math.sin(by)
	local rx, rz = -dz, dx
	local hx, hz = pos.X + c * HEEL_R, pos.Z + sn * HEEL_R
	-- Everything in the net's own frame: depth behind the goal line, and across the mouth.
	local bl, bz = sx * pos.X - GOAL.X, pos.Z
	local best, bnx, bnz = 0, 0, 0
	local function test(px: number, pz: number)
		local lx, lz = sx * px - GOAL.X, pz
		for zs = -1, 1, 2 do
			local ox, oz = lx, lz - zs * HALF_MOUTH
			local d = math.sqrt(ox * ox + oz * oz)
			local limit = GOAL.PostRadius + STICK_W
			if d < limit then
				local nx, nz = -1, 0
				if d > 1e-4 then
					nx, nz = ox / d, oz / d
				end
				if limit - d > best then
					best, bnx, bnz = limit - d, nx, nz
				end
			end
		end
		for k = 1, #NET_OUTLINE - 1 do
			local a, b = NET_OUTLINE[k], NET_OUTLINE[k + 1]
			local qx, qz = closestOnSegment(lx, lz, a.X, a.Y, b.X, b.Y)
			local ox, oz = lx - qx, lz - qz
			local d = math.sqrt(ox * ox + oz * oz)
			if crosses(bl, bz, lx, lz, a.X, a.Y, b.X, b.Y) then
				-- Through the netting: back out to the skater's side of it.
				local ex, ez = b.X - a.X, b.Y - a.Y
				local len = math.max(1e-6, math.sqrt(ex * ex + ez * ez))
				local nx, nz = ez / len, -ex / len
				if nx * (bl - a.X) + nz * (bz - a.Y) < 0 then
					nx, nz = -nx, -nz
				end
				if d + STICK_W > best then
					best, bnx, bnz = d + STICK_W, nx, nz
				end
			elseif d < STICK_W and d > 1e-6 and STICK_W - d > best then
				best, bnx, bnz = STICK_W - d, ox / d, oz / d
			end
		end
	end
	for i = 0, SHAFT_STEPS do
		local r = SHAFT_IN + (HEEL_R - SHAFT_IN) * i / SHAFT_STEPS
		test(pos.X + c * r, pos.Z + sn * r)
	end
	for k = 2, #SHAPE_ALONG do
		local a0, a1 = SHAPE_ALONG[k - 1], SHAPE_ALONG[k]
		local s0, s1 = SHAPE_SIDE[k - 1], SHAPE_SIDE[k]
		local am, smid = (a0 + a1) / 2, (s0 + s1) / 2
		test(hx + dx * am + rx * smid, hz + dz * am + rz * smid)
		test(hx + dx * a1 + rx * s1, hz + dz * a1 + rz * s1)
	end
	return best, bnx * sx, bnz
end

local function stickNetPush(pos: Vector3, yaw: number): (number, number, number)
	if LAYOUT then
		local n, ox, oz = netShift(pos.X, pos.Z, 8)
		if not n then
			return 0, 0, 0
		end
		return stickNetPushArena(pos + Vector3.new(ox, 0, oz), yaw)
	end
	return stickNetPushArena(pos, yaw)
end
Sim.stickNetPush = stickNetPush

function Sim.resolveStickNets(pos: Vector3, vel: Vector3, yaw: number): (Vector3, Vector3)
	for _ = 1, 3 do
		local pen, nx, nz = stickNetPush(pos, yaw)
		if pen <= 1e-4 then
			break
		end
		pos = Vector3.new(pos.X + nx * pen, pos.Y, pos.Z + nz * pen)
		local vn = vel.X * nx + vel.Z * nz
		if vn < 0 then
			vel = Vector3.new(vel.X - vn * nx, vel.Y, vel.Z - vn * nz)
		end
	end
	return pos, vel
end

-- Turning the stick from `from` toward `to`: it stops where it meets a post or the netting
-- (turning away from one is always free), so it can never be spun through them.
local function clampAimNets(pos: Vector3, from: number, to: number): number
	local turn = wrapAngle(to - from)
	local steps = math.ceil(math.abs(turn) / 0.08)
	if steps == 0 then
		return to
	end
	if LAYOUT then
		if not netShift(pos.X, pos.Z, 8) then
			return to
		end
	else
		local ax = math.abs(pos.X)
		if ax < GOAL.X - 8 or ax > GOAL.X + GOAL.Depth + 8 or math.abs(pos.Z) > HALF_MOUTH + 8 then
			return to
		end
	end
	local start = stickNetPush(pos, from)
	local last = from
	for i = 1, steps do
		local yaw = from + turn * i / steps
		if stickNetPush(pos, yaw) > start + 0.05 then
			return wrapAngle(last)
		end
		last = yaw
	end
	return to
end

local REVERSE_DIG = math.max(SKATER.Acceleration, SKATER.ReverseAcceleration)

-- Appendix C with sprint, braking and stun. Shared by server and client prediction.
function Sim.stepMotion(s: Skater, input: Input, dt: number, enabled: boolean)
	local wish = if enabled then Vector3.new(input.moveX, 0, input.moveZ) else Vector3.zero
	local wishMag = wish.Magnitude
	if wishMag > 1 then
		wish = wish / wishMag
		wishMag = 1
	end
	if s.stun > 0 then
		s.stun = math.max(0, s.stun - dt)
		wish *= SKATER.StunMoveScale
	end
	-- Feet, not switches: the keys swing the skater's push round over about a tenth of a second
	-- instead of jumping, so W to D, or W to S, rolls from one into the other with no snap.
	local heldMag = wish.Magnitude -- how hard the keys / stick ask, used for the speed to aim at
	local follow = 1 - math.exp(-SKATER.WishResponse * dt)
	s.wishX += (wish.X - s.wishX) * follow
	s.wishZ += (wish.Z - s.wishZ) * follow
	if math.abs(s.wishX) < 1e-3 and math.abs(s.wishZ) < 1e-3 and wishMag == 0 then
		s.wishX, s.wishZ = 0, 0
	end
	wish = Vector3.new(s.wishX, 0, s.wishZ)
	wishMag = wish.Magnitude
	local braking = enabled and input.brake == true

	-- Dash: fires once on the press (holding does nothing more), costs a chunk of stamina,
	-- then a short cooldown. The push builds over a couple of ticks, holds, then fades smoothly.
	local pressed = enabled and input.sprint == true
	local tapped = pressed and not s.sprintHeld
	s.sprintHeld = pressed
	s.dashTimer = math.max(0, s.dashTimer - dt)
	s.dashCooldown = math.max(0, s.dashCooldown - dt)
	if tapped and s.dashCooldown <= 0 and s.stamina >= SKATER.DashCost and s.stun <= 0 and not braking then
		local dir = if wishMag > 0.1 then wish.Unit elseif s.vel.Magnitude > 1 then s.vel.Unit else nil
		if dir then
			-- The burst goes exactly where the keys / stick point, keeping any speed already
			-- heading that way.
			local carried = math.max(s.vel:Dot(dir), SKATER.MaxSpeed * 0.6)
			s.dashSpeed = math.min(SKATER.DashMaxSpeed, carried + SKATER.DashImpulse)
			s.dashTimer = SKATER.DashTime
			s.dashCooldown = SKATER.DashCooldown
			s.stamina -= SKATER.DashCost
			s.staminaDelay = SKATER.StaminaRegenDelay
		end
	end
	local sprinting = s.dashTimer > 0
	s.sprinting = sprinting
	if s.staminaDelay > 0 then
		s.staminaDelay = math.max(0, s.staminaDelay - dt)
	else
		s.stamina = math.min(1, s.stamina + SKATER.StaminaRegen * dt)
	end

	local vel = s.vel
	local wishDir = if wishMag > 0.001 then wish / wishMag else Vector3.zero
	-- Dash push: the velocity closes on the dash speed along the keys (or the current travel
	-- with no keys) over a few ticks, then holds. Braking or a stun ends the burst.
	local dashAge = SKATER.DashTime - s.dashTimer -- 0 on the tick the dash fires
	local fading = false
	if sprinting and (braking or s.stun > 0) then
		s.dashTimer, sprinting = 0, false
		s.sprinting = false
	elseif sprinting and dashAge < SKATER.DashPush then
		local dir = if wishMag > 0.1 then wishDir elseif vel.Magnitude > 1 then vel.Unit else nil
		if dir then
			local gain = SKATER.DashGain * math.min(1, (dashAge + dt) / SKATER.DashOnset)
			vel += (dir * s.dashSpeed - vel) * (1 - math.exp(-gain * dt))
		end
	elseif sprinting then
		fading = true
	end
	-- While the dash pushes the skater holds its burst speed (steering only); as it fades the
	-- cap eases from the dash speed back to top speed along a cosine, so there's no lurch.
	local maxSpeed = SKATER.MaxSpeed
	if fading then
		local p = math.clamp((dashAge - SKATER.DashPush) / (SKATER.DashTime - SKATER.DashPush), 0, 1)
		local top = math.max(s.dashSpeed, SKATER.MaxSpeed)
		maxSpeed = SKATER.MaxSpeed + (top - SKATER.MaxSpeed) * 0.5 * (1 + math.cos(math.pi * p))
	elseif sprinting then
		maxSpeed = math.clamp(vel.Magnitude, SKATER.MaxSpeed, SKATER.DashMaxSpeed)
	end
	local speedNow = vel.Magnitude
	local carving = false
	if braking then
		-- Stop held: the skates dig in hard, but the keys still creep the skater along slowly.
		local delta = wish * SKATER.BrakeMoveSpeed - vel
		local maxChange = SKATER.BrakeAcceleration * dt
		if delta.Magnitude > maxChange then
			delta = delta.Unit * maxChange
		end
		vel += delta
	elseif wishMag > 0.001 and speedNow > SKATER.CarveMinSpeed then
		-- Carve: on the move, skates swing the direction of travel round toward the stick and
		-- keep the momentum, so turns are smooth arcs instead of sliding to a halt and pushing
		-- off again. Tighter at low speed, wider at full speed; a hard turn bleeds a little speed.
		-- Asked to go back the way it came (keys well behind the travel, like S then A then W),
		-- the skater keeps carving round but digs in as it turns, and the turn eases out as the
		-- keys point more nearly straight back (then it is a plain stop). Everything here changes
		-- smoothly with the angle, so there's no lurch where one kind of turn hands over to
		-- another.
		local dir = vel / speedNow
		local along = dir:Dot(wishDir)
		local cross = dir.X * wishDir.Z - dir.Z * wishDir.X
		local angle = math.atan2(cross, along)
		local rate = SKATER.CarveTurnRate + (SKATER.CarveTurnRateTop - SKATER.CarveTurnRate) * math.min(1, speedNow / SKATER.MaxSpeed)
		rate *= math.clamp((along + SKATER.CarveStopAlong) / (SKATER.CarveStopAlong - 0.2), 0, 1)
		if along < 0 then
			-- Keys behind the travel: the skates also swing the path round as hard as the dig-in
			-- below CarveMinSpeed does, so the turn rate is the same on both sides of that speed.
			local dx, dz = wish.X * maxSpeed - vel.X, wish.Z * maxSpeed - vel.Z
			local dLen = math.sqrt(dx * dx + dz * dz)
			if dLen > 1e-4 then
				local side = math.abs(dir.X * dz - dir.Z * dx) / dLen
				rate = math.max(rate, REVERSE_DIG * math.min(1, wishMag) * side / speedNow)
			end
		end
		-- The turn rate builds up and eases out near the new heading, instead of jumping to full
		-- rate on the tick a key goes down and stopping dead when the heading is reached.
		carving = true
		local want = clamp(angle / SKATER.CarveSettle, -rate, rate)
		local spinStep = SKATER.CarveSpinAccel * dt
		if s.carveSpin * angle > 0 and math.abs(want) < math.abs(s.carveSpin) then
			-- Still turning fast as the heading comes up (say, swinging out of a hockey stop): ease
			-- the turn off at whatever steady rate lands it on the heading, never stopping dead.
			spinStep = math.max(spinStep, s.carveSpin * s.carveSpin / (2 * math.abs(angle)) * dt)
		end
		s.carveSpin += clamp(want - s.carveSpin, -spinStep, spinStep)
		local turn = s.carveSpin * dt
		if turn * angle > 0 and math.abs(turn) > math.abs(angle) then
			turn = angle
			s.carveSpin = angle / dt
		end
		local c, sn = math.cos(turn), math.sin(turn)
		dir = Vector3.new(dir.X * c - dir.Z * sn, 0, dir.X * sn + dir.Z * c)
		-- Aim for the speed the keys ask for now (not the eased push, which dips mid-turn and
		-- would brake and release the skater as it swings round).
		local target = heldMag * maxSpeed
		local speed = speedNow
		-- Keys behind the travel: dig in, harder the further back they point. Between square
		-- across (along 0) and DigBlend behind it, the push fades out as the dig-in fades in.
		local dig = math.clamp(-along / SKATER.CarveDigBlend, 0, 1)
		if dig > 0 then
			target *= 1 - dig
			-- The same dig-in as the push-back below CarveMinSpeed, so slowing past it is seamless.
			speed = math.max(0, speed - REVERSE_DIG * math.max(0, -along) * math.min(1, wishMag) * dt)
		end
		if speed < target then
			-- Strong push from slow, easing off toward top speed.
			local accel = SKATER.Acceleration * (1.25 - 0.5 * math.min(1, speed / SKATER.MaxSpeed))
			-- The last few studs a second come on gently, so reaching top speed is a glide, not a
			-- sudden cut-off of the push.
			accel *= math.clamp((target - speed) / 5, 0.2, 1)
			speed = math.min(target, speed + accel * dt)
		elseif speed <= maxSpeed then
			-- Easing off the stick: glide down toward the slower wish. (Speed above the top,
			-- after a dash or a check, is shed by the overspeed decay just below.)
			-- The drag comes on over the first few studs a second (no lurch when the target drops
			-- just under the speed), and gives way to the dig-in when the keys point back.
			speed = math.max(target, speed - SKATER.CoastDrag * (1 - dig) * math.clamp((speed - target) / 4, 0.2, 1) * dt)
		end
		-- The change of speed itself eases from one tick to the next: as the keys swing past square
		-- across, the skater rolls from digging in to pushing off instead of lurching between them.
		local wantAcc = (speed - speedNow) / dt
		-- Digging in to stop builds up much faster than the push does, so reversing stops short.
		local jerkStep = (if dig > 0 and wantAcc < s.carveAcc then SKATER.CarveDigJerk else SKATER.CarveJerk) * dt
		local acc = s.carveAcc + clamp(wantAcc - s.carveAcc, -jerkStep, jerkStep)
		speed = speedNow + acc * dt
		if wantAcc >= 0 and acc > wantAcc then
			speed = math.min(speed, math.max(target, speedNow)) -- easing off the push never overshoots
		end
		speed = math.max(0, speed)
		s.carveAcc = (speed - speedNow) / dt
		speed *= 1 - math.abs(turn) * SKATER.CarveBleed
		vel = dir * speed
	elseif wishMag > 0.001 then
		-- From a standstill, or turning right round (a hockey stop and push back the other way).
		-- The same strong-from-slow push as a carve, so pushing back off after a stop gets going
		-- without a sluggish pause.
		local accel = SKATER.Acceleration * (1.25 - 0.5 * math.min(1, vel.Magnitude / SKATER.MaxSpeed))
		if vel:Dot(wish) < 0 then
			accel = math.max(accel, SKATER.ReverseAcceleration)
		end
		local delta = wish * maxSpeed - vel
		-- The push grows with the eased keys, so the first stride and the dig-in to reverse build
		-- up over a few ticks instead of arriving all at once.
		local maxChange = accel * math.min(1, wishMag) * dt
		if delta.Magnitude > maxChange then
			delta = delta.Unit * maxChange
		end
		-- A skater above top speed (after a sprint or a check) sheds it gradually.
		local speed = vel.Magnitude
		vel += delta
		if speed > maxSpeed and vel.Magnitude > speed then
			vel = vel.Unit * speed
		end
	else
		local speed = vel.Magnitude
		if speed > 0 then
			-- Space / LT digs the skates in; otherwise the skater coasts.
			local drag = if braking then SKATER.BrakeAcceleration else SKATER.CoastDrag
			vel *= math.max(0, 1 - drag * dt / speed)
		end
	end
	if not carving then
		-- Carry how the travel is actually turning and speeding up into the next carve, so moving
		-- in and out of it (slowing through CarveMinSpeed, letting go of the brake) has no seam.
		local newSpeed = vel.Magnitude
		local spin = 0
		local oldSpeed = s.vel.Magnitude
		if oldSpeed > 0.5 and newSpeed > 0.5 then
			local ox, oz = s.vel.X / oldSpeed, s.vel.Z / oldSpeed
			local nx, nz = vel.X / newSpeed, vel.Z / newSpeed
			spin = math.atan2(ox * nz - oz * nx, ox * nx + oz * nz) / dt
		end
		s.carveSpin = clamp(spin, -SKATER.CarveTurnRate, SKATER.CarveTurnRate)
		s.carveAcc = clamp((newSpeed - speedNow) / dt, -REVERSE_DIG, SKATER.Acceleration * 1.25)
	end
	local speed = vel.Magnitude
	if speed > maxSpeed then
		-- Fading out of a dash follows the smooth cap; other extra speed (a check) bleeds off.
		vel = vel.Unit * (if fading then maxSpeed else math.max(maxSpeed, speed - SKATER.OverspeedDecay * dt))
	end

	local pos = s.pos + vel * dt
	pos, vel = Sim.resolveStick(pos, vel, s.aimYaw)
	pos, vel = Sim.resolveBoards(pos, vel, BOARD_R, SKATER.BoardRestitution)
	pos, vel = Sim.resolveNetsForSkater(pos, vel, BODY_R)
	s.pos = pos
	s.vel = vel
end

-- Turns the stick toward the input's aim (rate-limited), levering the skater off the boards
-- when the stick is turned into them. Its own step so the client can replay it when it corrects
-- its prediction. locked: whether the skater is spun out (defaults to its own state).
function Sim.turnAim(s: Skater, input: Input, dt: number, locked: boolean?)
	s.aimYawPrev = s.aimYaw
	local aimMag = math.sqrt(input.aimX * input.aimX + input.aimZ * input.aimZ)
	if aimMag > 0.01 then
		local delta = wrapAngle(math.atan2(input.aimZ, input.aimX) - s.aimYaw)
		local spunOut = if locked ~= nil then locked else s.spinLock > 0
		local maxTurn = (if spunOut then STICK.SpinLockedAimRate else STICK.MaxAimRadiansPerSecond) * dt
		local from = s.aimYaw
		local to = wrapAngle(from + clamp(delta, -maxTurn, maxTurn))
		-- A rigid stick can't pass through the boards, so turning it into them levers the skater
		-- off the wall instead: the toe stays on the boards and the body is pushed away (plus some
		-- push-off speed). Only a turn too big for one tick's push is cut short.
		if Sim.tipInside(s.pos, from) and not Sim.tipInside(s.pos, to) then
			local pos, vel = s.pos, s.vel
			local tx, tz = toeAt(pos, to, HEEL_R)
			local moved = 0
			for _ = 1, 2 do -- twice, for a toe wedged into a corner
				if LAYOUT and crossesWall(pos.X, pos.Z, tx, tz) then
					break -- reaching through a wall: no lever, the turn just stops at it
				end
				local gap, nx, nz = boardGap(tx, tz)
				local pen = TIP_MARGIN - gap
				if pen <= 0 then
					break
				end
				local step = math.min(pen, STICK.StickLeverMaxStep - moved)
				if step <= 0 then
					break
				end
				moved += step
				pos = Vector3.new(pos.X + nx * step, pos.Y, pos.Z + nz * step)
				tx, tz = tx + nx * step, tz + nz * step
				local want = math.min(STICK.StickLeverMaxSpeed, step / dt * STICK.StickLeverShare)
				local vn = vel.X * nx + vel.Z * nz
				if vn < want then
					vel = Vector3.new(vel.X + nx * (want - vn), vel.Y, vel.Z + nz * (want - vn))
				end
			end
			pos, vel = Sim.resolveBoards(pos, vel, BOARD_R, SKATER.BoardRestitution)
			pos, vel = Sim.resolveNetsForSkater(pos, vel, BODY_R)
			s.pos, s.vel = pos, vel
			to = Sim.clampAim(pos, from, to)
		end
		to = clampAimNets(s.pos, from, to)
		s.aimYaw = to
	end
end

-- Rate-limited aim plus the Idle/Winding/Active/Recovery swing machine (chapters 19 and 20).
function Sim.stepStick(s: Skater, input: Input, dt: number)
	Sim.turnAim(s, input, dt)

	-- Swing stamina: turning faster than the free rate drains it; empty means spun out.
	local turnRate = math.abs(wrapAngle(s.aimYaw - s.aimYawPrev)) / dt
	if s.spinLock > 0 then
		-- Spun out: the bar refills through the lock-out, so it shows exactly when the stick is
		-- free again, and it comes back full.
		s.spinLock = math.max(0, s.spinLock - dt)
		s.spin = 1 - s.spinLock / STICK.SpinLockSeconds
		s.spinRest = 0
	elseif turnRate > STICK.SpinFreeRate then
		s.spinRest = 0
		s.spin -= (turnRate - STICK.SpinFreeRate) * STICK.SpinDrainPerRadian * dt
		if s.spin <= 0 then
			s.spin = 0
			s.spinLock = STICK.SpinLockSeconds
		end
	else
		s.spinRest += dt
		if s.spinRest >= STICK.SpinRegenDelay then
			s.spin = math.min(1, s.spin + STICK.SpinRegenPerSecond * dt)
		end
	end

	s.bladePrev = s.blade
	s.blade = Sim.bladeAt(s.pos, s.aimYaw, s.aimRadius)
	s.lifted = input.lift == true
	s.lofting = input.loft == true and not s.lifted
	s.cooldown = math.max(0, s.cooldown - dt)
	s.ignoreTimer = math.max(0, s.ignoreTimer - dt)

	local state = s.stickState
	if state == Sim.IDLE then
		if input.charge then
			s.stickState = Sim.WINDING
			s.windTime = 0
			s.charge = 0
		end
	elseif state == Sim.WINDING then
		s.windTime += dt
		s.charge = clamp((s.windTime - STICK.QuickThreshold) / STICK.ChargeTime, 0, 1)
		if not input.charge then
			if s.windTime < STICK.QuickThreshold then
				s.swingSpeed = STICK.QuickShotSpeed
				s.swingLift = 0
			else
				local curve = s.charge ^ 0.8
				s.swingSpeed = STICK.MinChargedSpeed + (STICK.MaxChargedSpeed - STICK.MinChargedSpeed) * curve
				s.swingLift = STICK.MaxLiftSpeed * curve
			end
			s.swingUsed = false
			s.stickState = Sim.ACTIVE
			s.stickTimer = STICK.ActiveTime
			s.charge = 0
		end
	elseif state == Sim.ACTIVE then
		s.stickTimer -= dt
		if s.stickTimer <= 0 then
			s.swingUsed = true
			s.stickState = Sim.RECOVERY
			s.stickTimer = STICK.RecoveryTime
		end
	else
		s.stickTimer -= dt
		if s.stickTimer <= 0 then
			s.stickState = Sim.IDLE
		end
	end
end

-- Appendix N, for a disc resting on ice. The appendix's lower height bound (Y >= radius * 0.6)
-- would reject every sliding puck, whose centre sits below that, so it is left out.
-- Build 36: the whole puck has to be past the far edge of the painted line (it used to count
-- once it was past the line's middle, still touching the paint).
function Sim.crossedGoal(prev: Vector3, current: Vector3, side: number): boolean
	local threshold = side * (GOAL.X + GOAL.LineWidth / 2 + PUCK.Radius)
	local a = side * (prev.X - threshold)
	local b = side * (current.X - threshold)
	if a >= 0 or b < 0 then
		return false
	end
	local t = -a / (b - a)
	local at = prev:Lerp(current, t)
	return math.abs(at.Z) <= HALF_MOUTH - PUCK.Radius and at.Y + PUCK.Thickness / 2 <= GOAL.CrossbarHeight
end

-- Closest point on the drawn blade (centre cx, cz; heel-to-toe direction dx, dz) to the point
-- (px, pz), and the blade's half-thickness there.
local function closestOnBlade(px: number, pz: number, cx: number, cz: number, dx: number, dz: number): (number, number, number)
	local rx, rz = -dz, dx -- the blade's right: the backhand face
	local hx, hz = cx - dx * BLADE_HALF, cz - dz * BLADE_HALF
	local bestD, bx, bz, bh = math.huge, cx, cz, SHAPE_HALF[1]
	for k = 1, #SHAPE_ALONG - 1 do
		local ax = hx + dx * SHAPE_ALONG[k] + rx * SHAPE_SIDE[k]
		local az = hz + dz * SHAPE_ALONG[k] + rz * SHAPE_SIDE[k]
		local ex = hx + dx * SHAPE_ALONG[k + 1] + rx * SHAPE_SIDE[k + 1]
		local ez = hz + dz * SHAPE_ALONG[k + 1] + rz * SHAPE_SIDE[k + 1]
		local qx, qz = closestOnSegment(px, pz, ax, az, ex, ez)
		local d = (px - qx) * (px - qx) + (pz - qz) * (pz - qz)
		if d < bestD then
			local len2 = (ex - ax) * (ex - ax) + (ez - az) * (ez - az)
			local t = if len2 > 1e-9 then ((qx - ax) * (ex - ax) + (qz - az) * (ez - az)) / len2 else 0
			bestD, bx, bz = d, qx, qz
			bh = SHAPE_HALF[k] + (SHAPE_HALF[k + 1] - SHAPE_HALF[k]) * t
		end
	end
	return bx, bz, bh
end
Sim.closestOnBlade = closestOnBlade

local World = {}
Sim.World = World

function World.new(): World
	return {
		skaters = {},
		puck = { pos = Vector3.new(0, PUCK_REST_Y, 0), vel = Vector3.zero },
		tick = 0,
		time = 0,
		events = {},
		controlsEnabled = true,
		stickHits = true,
		goalsEnabled = true,
		goalLatched = false,
		puckHeld = false,
		lastBodyCue = -100,
		touch1 = nil,
		touch2 = nil,
		touchHistory = {},
		stickHistory = {},
		idle = 0,
		bottlesDown = {},
		bottleZ = { [-1] = 0, [1] = 0 },
	}
end

local function emit(w: World, kind: string, x: number, z: number, strength: number, slot: number?)
	table.insert(w.events, { kind = kind, x = x + EMIT_DX, z = z + EMIT_DZ, strength = strength, slot = slot })
end

-- body: the puck bounced off the skater's body, not their stick. Every touch counts for saves and
-- the release of a shot, but only stick touches count for goal credit (Build 32: a shot that went
-- in off a teammate's body was that teammate's goal).
local function recordTouch(w: World, slot: number, body: boolean?)
	w.idle = 0
	if w.touch1 ~= slot then
		w.touch2 = w.touch1
		w.touch1 = slot
		table.insert(w.touchHistory, 1, slot)
		if #w.touchHistory > 8 then
			table.remove(w.touchHistory)
		end
	end
	if not body then
		local sticks = w.stickHistory
		if sticks and sticks[1] ~= slot then
			table.insert(sticks, 1, slot)
			if #sticks > 8 then
				table.remove(sticks)
			end
		end
	end
end
Sim.recordTouch = recordTouch

-- Build 34: the centre, back right and back left. The goalie seat lines up on the third spot
-- (it skates back to its net, or not, after the drop: BotBrain).
-- Build 36: the centres stand 5.5 from the dot (were 7), so the two taking the draw are closer.
local FACEOFF_SPOTS = {
	Vector3.new(-5.5, 0, 0),
	Vector3.new(-16, 0, 16),
	Vector3.new(-16, 0, -16),
}

-- Build 32: who takes the draw is random. Each face-off, every team's skaters (not the goalie)
-- are dealt the spots in a shuffled order, so a bot is as likely to take it as the player.
local faceoffRng = Random.new()
local function dealFaceoffSpots(w: World)
	for team = 1, 2 do
		local field = {}
		for _, s in w.skaters do
			if s.team == team and not s.goalie then
				table.insert(field, s)
			end
		end
		table.sort(field, function(a, b)
			return a.slot < b.slot
		end)
		for i = #field, 2, -1 do
			local j = faceoffRng:NextInteger(1, i)
			field[i], field[j] = field[j], field[i]
		end
		for i, s in field do
			s.faceoffIdx = i
		end
	end
end

function World.faceoffSpot(s: Skater): Vector3
	local mirror = if s.team == 1 then 1 else -1
	local spot = FACEOFF_SPOTS[if s.goalie then 3 else ((s.faceoffIdx or s.slot) - 1) % 3 + 1]
	return Vector3.new(spot.X * mirror, 0, spot.Z * mirror)
end

function World.placeSkater(s: Skater, pos: Vector3)
	s.pos = pos
	s.vel = Vector3.zero
	s.stun = 0
	s.stamina = 1
	s.staminaDelay = 0
	s.sprinting = false
	s.dashTimer = 0
	s.dashCooldown = 0
	s.dashSpeed = 0
	s.carveSpin = 0
	s.carveAcc = 0
	s.wishX, s.wishZ = 0, 0
	s.sprintHeld = false
	s.aimYaw = if s.team == 1 then 0 else math.pi
	s.aimYawPrev = s.aimYaw
	s.aimRadius = 1
	s.blade = Sim.bladeAt(pos, s.aimYaw, s.aimRadius)
	s.bladePrev = s.blade
	s.stickState = Sim.IDLE
	s.stickTimer = 0
	s.charge = 0
	s.swingUsed = true
	s.cooldown = 0
	s.ignoreTimer = 0
	s.spin = 1
	s.spinLock = 0
	s.spinRest = 0
	s.input = Sim.newInput()
end

-- height: how far above the ice to put the puck (a face-off drop); it rests on the ice otherwise.
function World.placePuck(w: World, pos: Vector3, vel: Vector3?, height: number?)
	w.puck.pos = Vector3.new(pos.X, math.max(PUCK_REST_Y, height or 0), pos.Z)
	w.puck.vel = vel or Vector3.zero
	w.idle = 0
	-- A puck put somewhere new has no stick history (callers clear touchHistory themselves).
	if w.stickHistory then
		table.clear(w.stickHistory)
	end
end

-- Atomic reset for a faceoff: positions, velocities, swing buffers, touches and the goal latch.
-- random: deal the face-off spots afresh (the match does; tests keep them by slot).
function World.resetForFaceoff(w: World, random: boolean?)
	if random then
		dealFaceoffSpots(w)
	end
	for _, s in w.skaters do
		World.placeSkater(s, World.faceoffSpot(s))
	end
	-- The puck starts above the players' heads and drops when play begins (the match holds it
	-- there through the count with w.puckHeld).
	World.placePuck(w, Vector3.zero, nil, PUCK.DropHeight)
	w.goalLatched = false
	w.touch1 = nil
	w.touch2 = nil
	table.clear(w.touchHistory)
	table.clear(w.bottlesDown)
end

-- One body-on-body contact, shared by the server and the client's own prediction (which passes
-- a stand-in for the other skater and no world). Equal masses: the bodies are pushed apart
-- evenly and swap the closing speed with some bounce. A hard enough hit is a body check: the
-- skater moving slower along the contact line is knocked off balance and takes a little extra
-- of the hitter's momentum, so a clean check visibly sends them away.
local CHECK_TRANSFER = 0.02 -- a hard check knocks the victim back a little (was 0.05: it sent them too far)
function Sim.bodyContact(a: Skater, b: Skater, w: World?): boolean
	local delta = b.pos - a.pos
	local d = delta.Magnitude
	local minDist = BODY_R * 2
	if d >= minDist then
		return false
	end
	local n = if d > 1e-4 then delta / d else Vector3.xAxis
	local push = n * ((minDist - d) / 2)
	a.pos -= push
	b.pos += push
	local vn = (b.vel - a.vel):Dot(n)
	if vn < 0 then
		local approach = -vn
		local j2 = (1 + SKATER.PlayerRestitution) * approach / 2
		local aAlong = a.vel:Dot(n)
		local bAlong = -b.vel:Dot(n)
		a.vel -= n * j2
		b.vel += n * j2
		if approach >= SKATER.CheckSpeed then
			-- The outcome depends only on momentum, never on cosmetics or chance.
			local victim = if aAlong >= bAlong then b else a
			local extra = approach * CHECK_TRANSFER
			if victim == b then
				b.vel += n * extra
				a.vel -= n * extra
			else
				a.vel -= n * extra
				b.vel += n * extra
			end
			victim.stun = SKATER.StunTime
			if w then
				emit(w, "Check", (a.pos.X + b.pos.X) / 2, (a.pos.Z + b.pos.Z) / 2, approach, victim.slot)
			end
		end
	end
	return true
end

local function stepSkaterPairs(w: World)
	local skaters = w.skaters
	for i = 1, #skaters do
		for j = i + 1, #skaters do
			Sim.bodyContact(skaters[i], skaters[j], w)
		end
	end
end

-- Stick lift held by the blade: `want` is whether the player is holding lift. A lifted stick
-- whose blade is still over the puck stays up after the lift is let go, and only comes down once
-- the blade has moved off it (Stick.LiftClear), so it never lands on the puck and knocks it away.
function Sim.holdLift(s: Skater, puck: Vector3, want: boolean): boolean
	if want or not s.lifted or puck.Y - PUCK_REST_Y > STICK.BladeDrawnHeight then
		return want
	end
	local yaw = s.aimYaw + BLADE_ANGLE
	local qx, qz, thick = closestOnBlade(puck.X, puck.Z, s.blade.X, s.blade.Z, math.cos(yaw), math.sin(yaw))
	local dx, dz = puck.X - qx, puck.Z - qz
	local reach = PUCK.Radius + thick + STICK.LiftClear
	return dx * dx + dz * dz < reach * reach
end

-- True when another skater's blade (heel to toe) crosses the line from (fx, fz), a point on s's
-- blade, to the puck's centre (tx, tz).
local function bladeBlocked(w: World, s: Skater, fx: number, fz: number, tx: number, tz: number): boolean
	for _, o in w.skaters do
		if o ~= s and not o.lifted then
			local yaw = o.aimYaw + BLADE_ANGLE
			local hx, hz = math.cos(yaw) * BLADE_HALF, math.sin(yaw) * BLADE_HALF
			if segmentsCross(fx, fz, tx, tz, o.blade.X - hx, o.blade.Z - hz, o.blade.X + hx, o.blade.Z + hz) then
				return true
			end
		end
	end
	return false
end

-- The pocket: a puck tucked in on the backhand, between the blade and the body, stays there
-- while the skater skates and turns. Its speed relative to the skater is soaked up and it is
-- drawn gently in against the body, so it only comes out when the stick moves it or someone
-- knocks it loose (a hard knock is faster than PocketMaxSlip and escapes).
local function holdPocket(w: World, s: Skater, dt: number)
	local puck = w.puck
	if s.lifted or s.ignoreTimer > 0 or s.stun > 0 or s.stickState == Sim.ACTIVE or puck.pos.Y - PUCK_REST_Y > 0.3 then
		return
	end
	local yaw = s.aimYaw + BLADE_ANGLE
	local px, pz = math.cos(yaw), math.sin(yaw)
	local qx, qz, thick = closestOnBlade(puck.pos.X, puck.pos.Z, s.blade.X, s.blade.Z, px, pz)
	local dx, dz = puck.pos.X - qx, puck.pos.Z - qz
	local faceGap = math.sqrt(dx * dx + dz * dz) - (PUCK.Radius + thick)
	-- Backhand side of the blade, touching or nearly, and close in to the body.
	if dx * -pz + dz * px <= 0 or faceGap > STICK.PocketReach then
		return
	end
	local bx, bz = puck.pos.X - s.pos.X, puck.pos.Z - s.pos.Z
	local bodyD = math.sqrt(bx * bx + bz * bz)
	if bodyD > SKATER.PuckBodyRadius + PUCK.Radius + STICK.PocketDepth or bodyD < 1e-3 then
		return
	end
	if bladeBlocked(w, s, qx, qz, puck.pos.X, puck.pos.Z) then
		return
	end
	local carry = Vector3.new(s.vel.X, 0, s.vel.Z)
	local cs = carry.Magnitude
	if cs > SKATER.MaxSpeed then
		carry *= SKATER.MaxSpeed / cs
	end
	local rel = Vector3.new(puck.vel.X, 0, puck.vel.Z) - carry
	if rel.Magnitude > STICK.PocketMaxSlip then
		return
	end
	-- Soak up the slip, then draw it in toward the body (the body's dead bounce stops it there).
	rel *= math.exp(-STICK.PocketGrip * dt)
	local gap = bodyD - (SKATER.PuckBodyRadius + PUCK.Radius)
	if gap > 0.02 then
		local pull = math.min(STICK.PocketPull, gap * 10)
		rel += Vector3.new(-bx / bodyD, 0, -bz / bodyD) * pull * math.min(1, STICK.PocketGrip * dt)
	end
	puck.vel = Vector3.new(carry.X + rel.X, puck.vel.Y, carry.Z + rel.Z)
end

-- Build 30: the blade is angled, so a puck held out on the toe slides down the face toward the
-- heel instead of riding on the tip: on the forehand it settles in the middle of the blade, on
-- the backhand it carries on in toward the body, into the pocket. A puck balanced beyond the
-- very tip slips off onto the face it leans toward. Speeds are relative to the blade, so this
-- works the same standing, skating or sweeping the stick.
local function slideToHeel(w: World, s: Skater, dt: number)
	local puck = w.puck
	if s.lifted or s.ignoreTimer > 0 or s.stun > 0 or s.stickState == Sim.ACTIVE or puck.pos.Y - PUCK_REST_Y > 0.3 then
		return
	end
	local yaw = s.aimYaw + BLADE_ANGLE
	local px, pz = math.cos(yaw), math.sin(yaw)
	local qx, qz, thick = closestOnBlade(puck.pos.X, puck.pos.Z, s.blade.X, s.blade.Z, px, pz)
	local dx, dz = puck.pos.X - qx, puck.pos.Z - qz
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist - (PUCK.Radius + thick) > STICK.HeelSlideReach then
		return
	end
	local hx, hz = s.blade.X - px * BLADE_HALF, s.blade.Z - pz * BLADE_HALF
	local along = (puck.pos.X - hx) * px + (puck.pos.Z - hz) * pz
	local sweet = STICK.BladeLength * STICK.HeelSlideSweet
	local rx, rz = -pz, px -- the blade's right: the backhand face
	local side = dx * rx + dz * rz
	local backhand = side > 0
	if along <= sweet and not (along > 0.15 * STICK.BladeLength and not backhand) then
		return
	end
	if bladeBlocked(w, s, qx, qz, puck.pos.X, puck.pos.Z) then
		return
	end
	-- The blade's own velocity where the puck touches it: the skating plus the stick's spin.
	local omega = wrapAngle(s.aimYaw - s.aimYawPrev) / Config.Tick
	local bvx = s.vel.X - (qz - s.pos.Z) * omega
	local bvz = s.vel.Z + (qx - s.pos.X) * omega
	local rvx, rvz = puck.vel.X - bvx, puck.vel.Z - bvz
	local k = math.min(1, STICK.HeelSlideGrip * dt)
	local onTip = along > STICK.BladeLength - 0.05 and math.abs(side) < 0.7 * (PUCK.Radius + thick)
	if onTip then
		-- On the end of the toe: slip off sideways onto a face (the forehand when dead centre).
		local sgn = if side > 0.02 then 1 else -1
		local cur = rvx * rx + rvz * rz
		if cur * sgn < STICK.TipSlip then
			local dv = (sgn * STICK.TipSlip - cur) * k
			rvx += rx * dv
			rvz += rz * dv
		end
	else
		local cur = rvx * px + rvz * pz -- positive is toward the toe
		local want = if along > sweet then -math.min(STICK.HeelSlideMax, (along - sweet) * STICK.HeelSlideRate) else 0
		-- Out past the sweet spot it is drawn heelward; on the forehand, short of it, a slide
		-- toward the heel is soaked up so it settles in the cup of the blade.
		if cur > want or (along <= sweet and cur < 0) then
			local dv = (want - cur) * k
			rvx += px * dv
			rvz += pz * dv
		end
	end
	puck.vel = Vector3.new(bvx + rvx, puck.vel.Y, bvz + rvz)
end

local function contactBlade(w: World, s: Skater, fraction: number, prevFraction: number, prevPuck: Vector3)
	local puck = w.puck
	-- A lifted blade hovers just over the puck, so it passes underneath untouched.
	-- A puck whose underside is above the blade's top passes over it.
	if s.lifted or puck.pos.Y - PUCK_REST_Y > STICK.BladeDrawnHeight or s.ignoreTimer > 0 then
		return
	end
	local turn = wrapAngle(s.aimYaw - s.aimYawPrev)
	local blade = s.bladePrev:Lerp(s.blade, fraction)
	-- The blade runs out from the heel at BladeAngle off the stick, so spinning the stick
	-- sweeps its face. The puck meets the blade exactly where it is drawn.
	local yaw = s.aimYawPrev + turn * fraction + BLADE_ANGLE
	local px, pz = math.cos(yaw), math.sin(yaw)
	local half = BLADE_HALF
	local qx, qz, thick = closestOnBlade(puck.pos.X, puck.pos.Z, blade.X, blade.Z, px, pz)
	local touchR = PUCK.Radius + thick
	local dx, dz = puck.pos.X - qx, puck.pos.Z - qz
	local dist = math.sqrt(dx * dx + dz * dz)

	-- Swept test: if the puck was on one face of the blade last substep and is on the other
	-- face now (a fast spin or a fast puck), it went through. Put it back on the face it was on.
	local crossedSide = 0
	do
		local before = s.bladePrev:Lerp(s.blade, prevFraction)
		local yawBefore = s.aimYawPrev + turn * prevFraction + BLADE_ANGLE
		local bx, bz = math.cos(yawBefore), math.sin(yawBefore)
		local sideBefore = (prevPuck.X - before.X) * -bz + (prevPuck.Z - before.Z) * bx
		local sideNow = (puck.pos.X - blade.X) * -pz + (puck.pos.Z - blade.Z) * px
		local alongNow = (puck.pos.X - blade.X) * px + (puck.pos.Z - blade.Z) * pz
		local alongBefore = (prevPuck.X - before.X) * bx + (prevPuck.Z - before.Z) * bz
		local reachAlong = half + PUCK.Radius * 0.5
		if sideBefore * sideNow < 0 and math.abs(sideBefore) > 1e-3 and (math.abs(alongNow) <= reachAlong or math.abs(alongBefore) <= reachAlong) then
			crossedSide = if sideBefore > 0 then 1 else -1
			-- Treat it as a touch on the original face.
			local nx, nz = -pz * crossedSide, px * crossedSide
			qx, qz, thick = closestOnBlade(puck.pos.X, puck.pos.Z, blade.X, blade.Z, px, pz)
			touchR = PUCK.Radius + thick
			dx, dz = nx * 1e-3, nz * 1e-3
			dist = 0
		end
	end

	-- No reaching through another stick: if another skater's blade lies between this blade and
	-- the puck, this blade can't touch it (a poke can't go through a stick to knock the puck off it).
	if dist <= touchR + STICK.ShotForgiveness and bladeBlocked(w, s, qx, qz, puck.pos.X, puck.pos.Z) then
		return
	end

	-- A validated swing token applies exactly one shot impulse.
	-- It fires only once the swing has come down for ShotDelay (see GameConfig).
	local swingDown = STICK.ActiveTime - s.stickTimer >= STICK.ShotDelay - 1e-6
	if s.stickState == Sim.ACTIVE and swingDown and not s.swingUsed and dist <= touchR + STICK.ShotForgiveness then
		s.swingUsed = true
		s.ignoreTimer = STICK.ActiveTime - STICK.ShotDelay + 0.05
		s.cooldown = STICK.ContactCooldown
		local dir = Vector3.new(math.cos(s.aimYaw), 0, math.sin(s.aimYaw))
		local planar = dir * s.swingSpeed + Vector3.new(s.vel.X, 0, s.vel.Z) * STICK.CarrySpeedShare
		local lift = s.swingLift
		if s.lofting then
			lift = math.max(lift, math.min(STICK.MaxLoftSpeed, s.swingSpeed * STICK.LoftShare))
		end
		puck.vel = Vector3.new(planar.X, liftCap(lift, puck.pos.Y), planar.Z)
		recordTouch(w, s.slot)
		emit(w, "Shot", puck.pos.X, puck.pos.Z, s.swingSpeed, s.slot)
		-- Build 38: where and how the shot left the stick, for the server's shot count (a goalie
		-- smothering it can turn the puck in the very same tick).
		local shotEvent = w.events[#w.events]
		shotEvent.launchPos, shotEvent.launchVel = puck.pos, puck.vel
		return
	end

	-- Speed of the blade where it meets the puck: the centre's speed plus the spin about it
	-- (the heel by the body moves slower than the toe).
	local omega = turn / Config.Tick
	-- Taken from the skater's skating plus the stick's spin about the body, not from how far the
	-- blade moved: a blade shifted by the boards (it slides in along the stick when the toe meets
	-- them) or a skater nudged off a wall, a post or another body would otherwise count as a
	-- 100-studs/s swing and fire the puck off the stick (the jumps along the boards).
	local bladeVel = Vector3.new(s.vel.X, 0, s.vel.Z) + Vector3.new(-(qz - s.pos.Z), 0, qx - s.pos.X) * omega
	-- A dash jumps the skater's speed in a single tick. The blade carries the puck along at no
	-- more than normal top speed, so the burst never bats the puck away off the stick.
	local skaterVel = Vector3.new(s.vel.X, 0, s.vel.Z)
	local skaterSpeed = skaterVel.Magnitude
	if skaterSpeed > SKATER.MaxSpeed then
		bladeVel -= skaterVel * (1 - SKATER.MaxSpeed / skaterSpeed)
	end
	local bladeSpeed = bladeVel.Magnitude
	if bladeSpeed > STICK.MaxBladeSpeed then
		bladeVel = bladeVel / bladeSpeed * STICK.MaxBladeSpeed
	end
	local planarVel = Vector3.new(puck.vel.X, 0, puck.vel.Z)

	-- The boards: where the puck sits against them and which way is back into the rink.
	local wallGap, inx, inz = boardGap(puck.pos.X, puck.pos.Z)
	local onWall = wallGap < PUCK.Radius + STICK.ScoopBoardGap

	-- Cradle: a blade on the ice side of a puck tight to the boards holds it there. The puck goes
	-- along the boards at the blade's pace and comes off them only as fast as the blade draws
	-- away, so it rides the stick smoothly and can be flicked straight off the wall. (It used to
	-- pop off the wall at a fixed speed, through the blade, which read as the puck jumping.)
	if crossedSide == 0 and onWall and dist < touchR + STICK.ScoopReach then
		local bladeSide = (qx - puck.pos.X) * inx + (qz - puck.pos.Z) * inz
		if bladeSide > 0.1 then
			local tx, tz = -inz, inx
			local bladeAlong = bladeVel.X * tx + bladeVel.Z * tz
			local bladeOff = bladeVel.X * inx + bladeVel.Z * inz
			local puckAlong = planarVel.X * tx + planarVel.Z * tz
			-- Along the boards the blade's face carries the puck; off them it follows the blade out.
			local along = puckAlong + (bladeAlong - puckAlong) * 0.6
			local backhandSide = dx * -pz + dz * px > 0
			if backhandSide then
				-- Scooping on the backhand: the puck is on the pocket side of the blade, so the toe
				-- swinging along the wall must not shove it away. It goes along with the skater
				-- and is drawn in toward the body, into the pocket.
				local skaterAlong = s.vel.X * tx + s.vel.Z * tz
				local draw = clamp(((s.pos.X - puck.pos.X) * tx + (s.pos.Z - puck.pos.Z) * tz) * 4, -STICK.PocketPull * 2, STICK.PocketPull * 2)
				along = puckAlong + (skaterAlong + draw - puckAlong) * 0.6
			end
			local off = math.max(0, bladeOff)
			-- Keep it just clear of the face, never overlapping it.
			local nx, nz = dx, dz
			if dist > 1e-4 then
				nx, nz = dx / dist, dz / dist
			else
				nx, nz = -inx, -inz
			end
			if dist < touchR then
				local px2, pz2 = qx + nx * touchR, qz + nz * touchR
				local g = boardGap(px2, pz2)
				if g >= PUCK.Radius then
					puck.pos = Vector3.new(px2, puck.pos.Y, pz2)
				end
			end
			local up = puck.vel.Y
			local vx, vz = tx * along + inx * off, tz * along + inz * off
			if s.lofting and off >= STICK.LoftMinSpeed then
				up = math.max(up, liftCap(math.clamp(math.sqrt(along * along + off * off) * STICK.LoftRatio, STICK.LoftMinUp, STICK.MaxLoftSpeed), puck.pos.Y))
				vx, vz = loftCarry(vx, vz)
			end
			puck.vel = Vector3.new(vx, up, vz)
			recordTouch(w, s.slot)
			return
		end
	end

	if dist < touchR then
		local nx, nz
		if crossedSide ~= 0 then
			nx, nz = -pz * crossedSide, px * crossedSide
		elseif dist > 1e-4 then
			nx, nz = dx / dist, dz / dist
		else
			nx, nz = px, pz
		end
		local n = Vector3.new(nx, 0, nz)
		puck.pos = Vector3.new(qx + nx * touchR, puck.pos.Y, qz + nz * touchR)
		-- Soft hands: the stick's own push (the blade's speed beyond the skater's skating) passes
		-- on only partly when it is slow, so stickhandling nudges the puck instead of batting it
		-- off the blade; a real swing passes on all of it.
		local carry = if skaterSpeed > SKATER.MaxSpeed then skaterVel * (SKATER.MaxSpeed / skaterSpeed) else skaterVel
		local handN = (bladeVel - carry):Dot(n)
		-- Catching: the puck comes into the face faster than the skater is moving and the blade
		-- isn't swinging at it. The blade gives, like soft hands receiving a pass.
		local catching = (planarVel - carry):Dot(n) < -STICK.CatchMinSpeed and handN < STICK.CatchMaxSwing
		local push = bladeVel
		if handN > 0 then
			local transfer = if catching
				then STICK.CatchTransfer
				else STICK.HandTransferSlow + (1 - STICK.HandTransferSlow) * clamp(handN / STICK.HandTransferFullSpeed, 0, 1)
			push -= n * (handN * (1 - transfer))
		end
		local rel = planarVel - push
		local vn = rel:Dot(n)
		if vn < 0 then
			local hardness = clamp(-vn / 60, 0, 1)
			local e = if catching then 0 else STICK.SoftRestitution + (STICK.HardRestitution - STICK.SoftRestitution) * hardness
			local out = planarVel - n * ((1 + e) * vn)
			local backhandFace = nx * -pz + nz * px > 0
			if catching then
				-- Take off some of its slide along the face (relative to the blade) as well.
				local relOut = out - push
				out -= (relOut - n * relOut:Dot(n)) * STICK.CatchFriction
			elseif backhandFace and handN < STICK.CatchMaxSwing then
				-- Carrying on the backhand: grip the puck so it doesn't slide off the convex face.
				local relOut = out - push
				out -= (relOut - n * relOut:Dot(n)) * STICK.BackhandGrip
			end
			-- Squeezed against the boards: the puck can't go into them, so it slides along them
			-- with the blade instead of being shoved through and bouncing back (the old jitter).
			local gap2, wnx, wnz = boardGap(puck.pos.X, puck.pos.Z)
			if gap2 < PUCK.Radius + 0.05 then
				local into = out.X * wnx + out.Z * wnz
				if into < 0 then
					out = Vector3.new(out.X - wnx * into, 0, out.Z - wnz * into)
				end
				if gap2 < PUCK.Radius then
					puck.pos = Vector3.new(puck.pos.X + wnx * (PUCK.Radius - gap2), puck.pos.Y, puck.pos.Z + wnz * (PUCK.Radius - gap2))
				end
			end
			local up = puck.vel.Y
			if s.lofting then
				-- The opened blade face scoops the puck up in proportion to how fast it leaves the
				-- skater, so a flick lifts it and a puck carried along with you stays down. The
				-- backhand face gets extra lift: a backhand flick, near the heel, is slower.
				local away = (out - skaterVel).Magnitude
				if away >= STICK.LoftMinSpeed then
					local backhand = nx * -pz + nz * px > 0
					local ratio = if backhand then STICK.BackhandLoftRatio else STICK.LoftRatio
					up = math.max(up, liftCap(math.clamp(away * ratio, STICK.LoftMinUp, STICK.MaxLoftSpeed), puck.pos.Y))
					local cx, cz = loftCarry(out.X, out.Z)
					out = Vector3.new(cx, 0, cz)
				end
			end
			puck.vel = Vector3.new(out.X, up, out.Z)
			recordTouch(w, s.slot)
			if -vn >= STICK.ContactCueSpeed and s.cooldown <= 0 then
				s.cooldown = STICK.ContactCooldown
				emit(w, "Hit", puck.pos.X, puck.pos.Z, -vn, s.slot)
			end
		end
	end
end

local function collideCircle(w: World, cx: number, cz: number, radius: number, restitution: number, slot: number?): boolean
	local puck = w.puck
	local dx, dz = puck.pos.X - cx, puck.pos.Z - cz
	local limit = radius + PUCK.Radius
	local d2 = dx * dx + dz * dz
	if d2 >= limit * limit then
		return false
	end
	local d = math.sqrt(d2)
	local nx, nz = 1, 0
	if d > 1e-4 then
		nx, nz = dx / d, dz / d
	end
	puck.pos = Vector3.new(cx + nx * limit, puck.pos.Y, cz + nz * limit)
	local vn = puck.vel.X * nx + puck.vel.Z * nz
	if vn < 0 then
		local j = (1 + restitution) * vn
		puck.vel = Vector3.new(puck.vel.X - j * nx, puck.vel.Y, puck.vel.Z - j * nz)
		if slot then
			recordTouch(w, slot)
		end
		return true
	end
	return false
end

-- A skater's body: solid and far heavier than the puck, so the puck bounces off it relative to
-- how the body is moving. Skating into a loose puck knocks it ahead; a shot into a moving body
-- comes off with the body's speed added.
local function collideBody(w: World, s: Skater)
	local puck = w.puck
	local dx, dz = puck.pos.X - s.pos.X, puck.pos.Z - s.pos.Z
	local limit = SKATER.PuckBodyRadius + PUCK.Radius
	local d2 = dx * dx + dz * dz
	if d2 >= limit * limit then
		return
	end
	local d = math.sqrt(d2)
	local nx, nz = 1, 0
	if d > 1e-4 then
		nx, nz = dx / d, dz / d
	elseif s.vel.X * s.vel.X + s.vel.Z * s.vel.Z > 1e-4 then
		local sp = math.sqrt(s.vel.X * s.vel.X + s.vel.Z * s.vel.Z)
		nx, nz = s.vel.X / sp, s.vel.Z / sp
	end
	puck.pos = Vector3.new(s.pos.X + nx * limit, puck.pos.Y, s.pos.Z + nz * limit)
	local puckN = puck.vel.X * nx + puck.vel.Z * nz
	-- Like the blade, a dashing body carries the puck at no more than normal top speed.
	local bvx, bvz = s.vel.X, s.vel.Z
	local bodySpeed = math.sqrt(bvx * bvx + bvz * bvz)
	if bodySpeed > SKATER.MaxSpeed then
		bvx, bvz = bvx * SKATER.MaxSpeed / bodySpeed, bvz * SKATER.MaxSpeed / bodySpeed
	end
	local bodyN = bvx * nx + bvz * nz
	local vn = puckN - bodyN
	if vn < 0 then
		-- The puck leaves at the body's own speed along the contact line (a skater walking into
		-- a loose puck pushes it along, never kicks it away). A square hit is dead: almost no
		-- bounce, and most of its slide across the body is soaked up too. A hit on the side glances
		-- off with a little bounce.
		local relX, relZ = puck.vel.X - bvx, puck.vel.Z - bvz
		local relSpeed = math.sqrt(relX * relX + relZ * relZ)
		local square = if relSpeed > 1e-4 then (-vn / relSpeed) ^ 2 else 1
		local e = PUCK.BodySideRestitution + (PUCK.BodyRestitution - PUCK.BodySideRestitution) * square
		local out = bodyN + e * math.max(0, -puckN)
		local j = out - puckN
		local vx, vz = puck.vel.X + j * nx, puck.vel.Z + j * nz
		-- Slide across the body, relative to it, loses BodyGrip of itself on a square hit.
		local tx, tz = -nz, nx
		local slide = (vx - bvx) * tx + (vz - bvz) * tz
		local keep = 1 - PUCK.BodyGrip * square
		vx, vz = vx - tx * slide * (1 - keep), vz - tz * slide * (1 - keep)
		puck.vel = Vector3.new(vx, puck.vel.Y, vz)
		recordTouch(w, s.slot, true)
		if -vn >= PUCK.BodyCueSpeed and w.tick - w.lastBodyCue > 8 then
			w.lastBodyCue = w.tick
			-- Build 31: only a puck off the ice makes the skater grunt (BodyAir); one along the ice
			-- (skating into it to pick it up) is just the thud.
			emit(w, if puck.pos.Y > PUCK_REST_Y + 0.35 then "BodyAir" else "Body", puck.pos.X, puck.pos.Z, -vn, s.slot)
		end
	end
end

-- prev: where the puck was at the start of this substep. Build 33: the netting is checked along
-- the puck's path, not just where it ends up. A fast puck (off a post, say) could cross the thin
-- netting inside one substep and then be pushed out on the far side: it went through the net.
local function collideNetWall(w: World, side: number, ax: number, az: number, bx: number, bz: number, prev: Vector3)
	local puck = w.puck
	local ex, ez = bx - ax, bz - az
	local len = math.sqrt(ex * ex + ez * ez)
	if len < 1e-6 then
		return
	end
	local wnx, wnz = -ez / len, ex / len -- the wall's normal
	local sPrev = (prev.X - ax) * wnx + (prev.Z - az) * wnz
	local sNow = (puck.pos.X - ax) * wnx + (puck.pos.Z - az) * wnz
	if sPrev * sNow < 0 then
		-- The centre crossed the wall's line this substep. Where?
		local f = sPrev / (sPrev - sNow)
		local cx = prev.X + (puck.pos.X - prev.X) * f
		local cz = prev.Z + (puck.pos.Z - prev.Z) * f
		local cy = prev.Y + (puck.pos.Y - prev.Y) * f
		local t = ((cx - ax) * ex + (cz - az) * ez) / (len * len)
		if t >= 0 and t <= 1 and cy - PUCK_REST_Y <= Sim.netRoofAt(side * cx - GOAL.X) then
			-- Through the netting: back out on the side it came from, just touching, bounced.
			local sg = if sPrev > 0 then 1 else -1
			local nx, nz = wnx * sg, wnz * sg
			local back = math.abs(sNow) + PUCK.Radius
			puck.pos = Vector3.new(puck.pos.X + nx * back, puck.pos.Y, puck.pos.Z + nz * back)
			local vn = puck.vel.X * nx + puck.vel.Z * nz
			if vn < 0 then
				local j = (1 + PUCK.NetRestitution) * vn
				puck.vel = Vector3.new(puck.vel.X - j * nx, puck.vel.Y, puck.vel.Z - j * nz)
			end
			return
		end
	end
	local qx, qz = closestOnSegment(puck.pos.X, puck.pos.Z, ax, az, bx, bz)
	local dx, dz = puck.pos.X - qx, puck.pos.Z - qz
	local d2 = dx * dx + dz * dz
	if d2 >= PUCK.Radius * PUCK.Radius then
		return
	end
	-- The netting only reaches up to the net's top there; a puck above it flies over.
	if puck.pos.Y - PUCK_REST_Y > Sim.netRoofAt(side * qx - GOAL.X) then
		return
	end
	local nx, nz
	local d = math.sqrt(d2)
	if d > 1e-4 and not (math.abs(sPrev) > 1e-4 and (dx * wnx + dz * wnz) * sPrev < 0) then
		nx, nz = dx / d, dz / d
	else
		-- Dead on the wall, or past its line from where it started: push back to the start side.
		local sg = if sPrev >= 0 then 1 else -1
		nx, nz = wnx * sg, wnz * sg
	end
	puck.pos = Vector3.new(qx + nx * PUCK.Radius, puck.pos.Y, qz + nz * PUCK.Radius)
	local vn = puck.vel.X * nx + puck.vel.Z * nz
	if vn < 0 then
		local j = (1 + PUCK.NetRestitution) * vn
		puck.vel = Vector3.new(puck.vel.X - j * nx, puck.vel.Y, puck.vel.Z - j * nz)
	end
end

-- The drink bottle on top of a net pops off when a shot goes in top shelf (high in the net
-- under it) or a puck lands on the net top beside it. Once per net until the next faceoff.
local function checkBottle(w: World, side: number)
	if LAYOUT or w.bottlesDown[side] then
		return
	end
	local puck = w.puck
	local d = side * puck.pos.X - GOAL.X
	local y = puck.pos.Y - PUCK_REST_Y
	local bz = w.bottleZ[side] or 0 -- Build 36: the bottle can lie anywhere across the top
	if d < 0.2 or d > GOAL.Depth or math.abs(puck.pos.Z - bz) > GOAL.BottleReach then
		return
	end
	local high = y > GOAL.BottleTopShelf and y < GOAL.CrossbarHeight and puck.vel.Magnitude > 12
	local onTop = y >= GOAL.CrossbarHeight - 0.1 and y < GOAL.CrossbarHeight + 2.5 and math.abs(d - GOAL.BottleDepth) < 1.6 and math.abs(puck.pos.Z - bz) < 1.6
	if high or onTop then
		w.bottlesDown[side] = true
		emit(w, "Bottle", side * (GOAL.X + GOAL.BottleDepth), bz, puck.vel.Magnitude)
	end
end

local function collideNetSide(w: World, prev: Vector3, side: number)
	local puck = w.puck
	local gx, depth = GOAL.X, GOAL.Depth
	checkBottle(w, side)
	do
		-- Broad check: posts and netting only matter near this net.
		if puck.pos.X * side > gx - 4 and puck.pos.X * side < gx + depth + 4 then
			local front = side * gx
			if puck.pos.Y - PUCK_REST_Y < GOAL.CrossbarHeight then
				for zSign = -1, 1, 2 do
					local z = zSign * HALF_MOUTH
					if collideCircle(w, front, z, GOAL.PostRadius, PUCK.PostRestitution, nil) then
						emit(w, "Post", front, z, puck.vel.Magnitude)
					end
				end
			end
			-- Crossbar: a round bar across the top of the mouth. A puck meeting it is knocked down,
			-- up or back out; one under it goes in, one over it lands on the net. (Without it a puck
			-- entering right at crossbar height slipped in above the roof and out through the top.)
			if math.abs(puck.pos.Z) < HALF_MOUTH then
				local d = side * puck.pos.X - gx
				local bottom = puck.pos.Y - PUCK_REST_Y
				-- Nearest point of the puck's side-on profile (a rectangle) to the bar's centre.
				local od = clamp(0, d - PUCK.Radius, d + PUCK.Radius)
				local oy = clamp(GOAL.CrossbarHeight, bottom, bottom + PUCK.Thickness) - GOAL.CrossbarHeight
				local dist = math.sqrt(od * od + oy * oy)
				if dist < GOAL.PostRadius then
					local vd = side * puck.vel.X
					local nd, ny
					if dist > 1e-4 then
						nd, ny = od / dist, oy / dist
					else
						nd, ny = if vd > 0 then -1 else 1, 0
					end
					local push = GOAL.PostRadius - dist
					puck.pos += Vector3.new(side * nd * push, ny * push, 0)
					local vn = vd * nd + puck.vel.Y * ny
					if vn < 0 then
						local j = (1 + PUCK.PostRestitution) * vn
						puck.vel = Vector3.new(side * (vd - j * nd), puck.vel.Y - j * ny, puck.vel.Z)
						emit(w, "Post", side * gx, puck.pos.Z, -vn)
					end
				end
			end
			for k = 1, #NET_OUTLINE - 1 do
				local a, b = NET_OUTLINE[k], NET_OUTLINE[k + 1]
				collideNetWall(w, side, side * (gx + a.X), a.Y, side * (gx + b.X), b.Y, prev)
			end
			-- The top netting: a puck dropping onto the net settles on it and rolls off the back;
			-- one rising inside the net is stopped by it.
			local depthNow = side * puck.pos.X - gx
			if Sim.insideNet(depthNow, puck.pos.Z) then
				local roof = Sim.netRoofAt(depthNow)
				local wasRoof = Sim.netRoofAt(clamp(side * prev.X - gx, 0, depth))
				local y = puck.pos.Y - PUCK_REST_Y
				local was = prev.Y - PUCK_REST_Y
				local v = puck.vel
				if y < roof and was >= wasRoof - 0.05 then
					local up = if v.Y < -3 then -v.Y * PUCK.NetRestitution else 0
					local back = if depthNow > GOAL.ShelfDepth then side * 0.05 else 0
					puck.pos = Vector3.new(puck.pos.X, roof + PUCK_REST_Y, puck.pos.Z)
					puck.vel = Vector3.new(v.X * 0.98 + back, up, v.Z * 0.98)
				elseif y > roof - PUCK.Thickness and was <= wasRoof - PUCK.Thickness + 0.05 then
					-- Inside the net the puck meets the netting overhead, the flat shelf or the slope
					-- down to the back, however it is moving (a high shot flying level into the slope
					-- used to pass straight through it). It stays under it and loses the speed it
					-- had into it.
					local nd, ny = 0, 1 -- the roof's outward normal, in (depth, up)
					if depthNow > GOAL.ShelfDepth then
						local k = (GOAL.CrossbarHeight - GOAL.BackHeight) / (depth - GOAL.ShelfDepth)
						local m = math.sqrt(1 + k * k)
						nd, ny = k / m, 1 / m
					end
					puck.pos = Vector3.new(puck.pos.X, roof - PUCK.Thickness + PUCK_REST_Y, puck.pos.Z)
					local vd = side * v.X
					local into = vd * nd + v.Y * ny
					if into > 0 then
						local j = (1 + PUCK.NetRestitution) * into
						v = Vector3.new(side * (vd - j * nd), v.Y - j * ny, v.Z)
					end
					puck.vel = v
				end
			end
		end
	end
end

local function collideNets(w: World, prev: Vector3)
	if LAYOUT then
		-- The net near the puck, moved onto the match rink's net for the check, then back.
		local p = w.puck.pos
		local n, ox, oz = netShift(p.X, p.Z, 4)
		if n then
			local off = Vector3.new(ox, 0, oz)
			w.puck.pos += off
			EMIT_DX, EMIT_DZ = -ox, -oz
			collideNetSide(w, prev + off, n.side)
			EMIT_DX, EMIT_DZ = 0, 0
			w.puck.pos -= off
		end
		return
	end
	for side = -1, 1, 2 do
		collideNetSide(w, prev, side)
	end
end

local function checkGoal(w: World, prev: Vector3)
	if w.goalLatched or not w.goalsEnabled then
		return
	end
	if LAYOUT then
		-- Open world: any net, no teams. The last toucher gets the credit.
		local p = w.puck.pos
		for i, n in LAYOUT.nets do
			local off = Vector3.new(n.side * GOAL.X - n.x, 0, -n.z)
			if Sim.crossedGoal(prev + off, p + off, n.side) then
				w.goalLatched = true
				table.insert(w.events, {
					kind = "Goal",
					x = p.X,
					z = p.Z,
					strength = w.puck.vel.Magnitude,
					team = 0,
					scorer = w.touch1,
					net = i,
				})
				return
			end
		end
		return
	end
	for side = -1, 1, 2 do
		if Sim.crossedGoal(prev, w.puck.pos, side) then
			w.goalLatched = true
			local team = if side == 1 then 1 else 2
			-- No own goals: credit goes to the last player on the scoring team to touch the puck (a
			-- defender or the goalie knocking it in after them doesn't take it from them). The assist
			-- goes to the teammate before, but only when the scorer's touch was the last one (a puck
			-- the other team put in gets no assist). With no touch from the scoring team the goal
			-- still counts for the team, credited to nobody.
			-- Build 32: stick touches decide it, so a shot in off a teammate's body (or a skate)
			-- is still the shooter's goal; a puck only ever touched by bodies falls back to those.
			local function credit(list: { number }): (number?, number?)
				local sc, asst = nil, nil
				for _, slot in list do
					local sk = w.skaters[slot]
					if sk and sk.team == team then
						if not sc then
							sc = slot
						elseif slot ~= sc then
							asst = slot
							break
						end
					end
				end
				return sc, asst
			end
			local sticks = w.stickHistory or {}
			local scorer, assist = credit(sticks)
			local lastSlot = sticks[1]
			if not scorer then
				scorer, assist = credit(w.touchHistory)
				lastSlot = w.touch1
			end
			local lastSkater = lastSlot and w.skaters[lastSlot]
			if scorer and lastSkater and lastSkater.team ~= team then
				assist = nil
			end
			local ownGoal = false
			table.insert(w.events, {
				kind = "Goal",
				x = w.puck.pos.X,
				z = w.puck.pos.Z,
				strength = w.puck.vel.Magnitude,
				team = team,
				scorer = scorer,
				assist = assist,
				ownGoal = ownGoal,
			})
			return
		end
	end
end

-- The stick is part of the body: a stick skated or swung into any other skater, teammate or
-- opponent, nudges them out of its way (the shaft from the body to the toe is a solid capsule),
-- and only a really fast one stuns them.
local STICK_IN = BODY_R * 0.8
local STICK_REACH_R = BODY_R + STICK.StickBodyRadius
-- a's stick against b's body. Shared with the client's prediction of its own skater (which
-- passes a stand-in for the other one and no world).
function Sim.stickBodyContact(a: Skater, b: Skater, dt: number, w: World?)
	local c, sn = math.cos(a.aimYaw), math.sin(a.aimYaw)
	local ax, az = a.pos.X + c * STICK_IN, a.pos.Z + sn * STICK_IN
	local by = a.aimYaw + BLADE_ANGLE
	local bx = a.pos.X + c * HEEL_R + math.cos(by) * (STICK.BladeLength - 0.1)
	local bz = a.pos.Z + sn * HEEL_R + math.sin(by) * (STICK.BladeLength - 0.1)
	local qx, qz = closestOnSegment(b.pos.X, b.pos.Z, ax, az, bx, bz)
	local dx, dz = b.pos.X - qx, b.pos.Z - qz
	local d = math.sqrt(dx * dx + dz * dz)
	if d >= STICK_REACH_R then
		return
	end
	local nx, nz
	if d > 1e-4 then
		nx, nz = dx / d, dz / d
	else
		nx, nz = -sn, c
	end
	local n = Vector3.new(nx, 0, nz)
	local share = STICK.StickKnockShare
	-- Ease them apart over a few ticks rather than teleporting, so a stick resting on
	-- a body leans on it instead of shoving it across the ice.
	local overlap = STICK_REACH_R - d
	b.pos += n * math.min(overlap * share, STICK.StickPushMaxStep)
	a.pos -= n * math.min(overlap * (1 - share), STICK.StickPushMaxStep)
	-- Speed of the stick where it touches: the skater's own speed plus the spin.
	local omega = wrapAngle(a.aimYaw - a.aimYawPrev) / dt
	local pointVel = a.vel + Vector3.new(-(qz - a.pos.Z), 0, qx - a.pos.X) * omega
	local pointSpeed = pointVel.Magnitude
	if pointSpeed > STICK.MaxBladeSpeed then
		pointVel = pointVel / pointSpeed * STICK.MaxBladeSpeed
	end
	local vn = (pointVel - b.vel):Dot(n)
	if vn > 0 then
		local j = (1 + STICK.StickBodyRestitution) * vn
		-- A bump is a nudge: it never adds more than StickBumpMaxSpeed to them.
		j = math.min(j, STICK.StickBumpMaxSpeed / share)
		b.vel += n * (j * share)
		a.vel -= n * (j * (1 - share))
		if vn >= STICK.StickKnockSpeed and b.stun <= 0 then
			b.stun = SKATER.StunTime
			if w then
				emit(w, "Check", qx, qz, vn, b.slot)
			end
		end
	end
end

-- Stick on stick: each stick is part of its skater's body, so two sticks can't pass through each
-- other. A stick is the low end of the shaft (out to the heel) plus the blade (heel, middle, toe
-- with its hook). Touching sticks push both skaters apart, half each, eased over a few ticks like
-- a stick on a body, and a stick swung into another one bumps both skaters. Sticks that have
-- already crossed (a fast swing can jump one in a tick) are pushed back out the way they came.
local STICK_GAP = STICK.StickStickGap
local STICK_LOW = STICK.StickLowShaft
local STICK_SPAN = HEEL_R + STICK.BladeLength + math.abs(STICK.BladeCurve) + STICK_GAP
local pathA: { number } = table.create(8, 0)
local pathB: { number } = table.create(8, 0)

local function fillStickPath(out: { number }, s: Skater, yaw: number)
	local c, sn = math.cos(yaw), math.sin(yaw)
	local by = yaw + BLADE_ANGLE
	local dx, dz = math.cos(by), math.sin(by)
	local rx, rz = -dz, dx
	local hx, hz = s.pos.X + c * HEEL_R, s.pos.Z + sn * HEEL_R
	local low = HEEL_R * STICK_LOW
	local mid, toe = SHAPE_ALONG[3], SHAPE_ALONG[#SHAPE_ALONG]
	out[1], out[2] = s.pos.X + c * low, s.pos.Z + sn * low
	out[3], out[4] = hx, hz
	out[5], out[6] = hx + dx * mid + rx * SHAPE_SIDE[3], hz + dz * mid + rz * SHAPE_SIDE[3]
	out[7], out[8] = hx + dx * toe + rx * SHAPE_SIDE[#SHAPE_SIDE], hz + dz * toe + rz * SHAPE_SIDE[#SHAPE_SIDE]
end

-- Closest gap between segment a1-a2 and segment b1-b2 (not crossing), with the two closest points.
local function segmentGap(a1x: number, a1z: number, a2x: number, a2z: number, b1x: number, b1z: number, b2x: number, b2z: number): (number, number, number, number, number)
	local best, pax, paz, pbx, pbz = math.huge, a1x, a1z, b1x, b1z
	local qx, qz = closestOnSegment(a1x, a1z, b1x, b1z, b2x, b2z)
	local d = (a1x - qx) * (a1x - qx) + (a1z - qz) * (a1z - qz)
	if d < best then
		best, pax, paz, pbx, pbz = d, a1x, a1z, qx, qz
	end
	qx, qz = closestOnSegment(a2x, a2z, b1x, b1z, b2x, b2z)
	d = (a2x - qx) * (a2x - qx) + (a2z - qz) * (a2z - qz)
	if d < best then
		best, pax, paz, pbx, pbz = d, a2x, a2z, qx, qz
	end
	qx, qz = closestOnSegment(b1x, b1z, a1x, a1z, a2x, a2z)
	d = (b1x - qx) * (b1x - qx) + (b1z - qz) * (b1z - qz)
	if d < best then
		best, pax, paz, pbx, pbz = d, qx, qz, b1x, b1z
	end
	qx, qz = closestOnSegment(b2x, b2z, a1x, a1z, a2x, a2z)
	d = (b2x - qx) * (b2x - qx) + (b2z - qz) * (b2z - qz)
	if d < best then
		best, pax, paz, pbx, pbz = d, qx, qz, b2x, b2z
	end
	return math.sqrt(best), pax, paz, pbx, pbz
end

-- How far a's stick (at yawA) and b's stick (at yawB) overlap, the direction that pushes a away
-- from b, and the two touching points.
local function stickOverlap(a: Skater, b: Skater, yawA: number, yawB: number): (number, number, number, number, number, number, number)
	local ox, oz = b.pos.X - a.pos.X, b.pos.Z - a.pos.Z
	fillStickPath(pathA, a, yawA)
	fillStickPath(pathB, b, yawB)
	local gap, pax, paz, pbx, pbz = math.huge, 0, 0, 0, 0
	local nx, nz = 0, 0 -- pushes a away from b
	local overlap = 0
	for i = 1, 5, 2 do
		local a1x, a1z, a2x, a2z = pathA[i], pathA[i + 1], pathA[i + 2], pathA[i + 3]
		for j = 1, 5, 2 do
			local b1x, b1z, b2x, b2z = pathB[j], pathB[j + 1], pathB[j + 2], pathB[j + 3]
			if crosses(a1x, a1z, a2x, a2z, b1x, b1z, b2x, b2z) then
				-- Crossed: push a back to its own body's side of b's segment, by however far its
				-- stick reaches past that line, plus the gap.
				local ex, ez = b2x - b1x, b2z - b1z
				local len = math.max(1e-6, math.sqrt(ex * ex + ez * ez))
				local px, pz = -ez / len, ex / len
				if px * (a.pos.X - b1x) + pz * (a.pos.Z - b1z) < 0 then
					px, pz = -px, -pz
				end
				local s1 = px * (a1x - b1x) + pz * (a1z - b1z)
				local s2 = px * (a2x - b1x) + pz * (a2z - b1z)
				local past = -math.min(s1, s2, 0)
				if past + STICK_GAP > overlap then
					overlap, nx, nz = past + STICK_GAP, px, pz
					local fx, fz = if s1 < s2 then a1x else a2x, if s1 < s2 then a1z else a2z
					pax, paz = fx, fz
					pbx, pbz = closestOnSegment(fx, fz, b1x, b1z, b2x, b2z)
					gap = 0
				end
			else
				local g, qax, qaz, qbx, qbz = segmentGap(a1x, a1z, a2x, a2z, b1x, b1z, b2x, b2z)
				if g < STICK_GAP and STICK_GAP - g > overlap then
					local dx, dz = qax - qbx, qaz - qbz
					local d = math.sqrt(dx * dx + dz * dz)
					if d > 1e-5 then
						dx, dz = dx / d, dz / d
					else
						dx, dz = -ox, -oz
						local m = math.max(1e-6, math.sqrt(dx * dx + dz * dz))
						dx, dz = dx / m, dz / m
					end
					overlap, nx, nz, gap = STICK_GAP - g, dx, dz, g
					pax, paz, pbx, pbz = qax, qaz, qbx, qbz
				end
			end
		end
	end
	return overlap, nx, nz, pax, paz, pbx, pbz
end

-- Most yaw a stick check steps through at once, so a fast swing can't jump clean over another
-- stick between two ticks (it used to, and the bump never happened).
local STICK_SWEEP_STEP = 0.12

-- a's stick against b's stick. Shared with the client's prediction of its own skater.
function Sim.stickStickContact(a: Skater, b: Skater, dt: number)
	local ox, oz = b.pos.X - a.pos.X, b.pos.Z - a.pos.Z
	if ox * ox + oz * oz > 4 * STICK_SPAN * STICK_SPAN then
		return
	end
	local overlap, nx, nz, pax, paz, pbx, pbz = 0, 0, 0, 0, 0, 0, 0
	local swept = false
	-- Build 30: sticks are solid. A stick turned into another one stops where they meet (both
	-- stop, at the same share of their turn, when both were turning) instead of passing through
	-- it while the skaters are eased apart. The meeting still bumps both skaters, below.
	local turnA0 = wrapAngle(a.aimYaw - a.aimYawPrev)
	local turnB0 = wrapAngle(b.aimYaw - b.aimYawPrev)
	local most = math.max(math.abs(turnA0), math.abs(turnB0))
	if most > 1e-4 and stickOverlap(a, b, a.aimYawPrev, b.aimYawPrev) <= 0 then
		local steps = math.clamp(math.ceil(most / STICK_SWEEP_STEP), 1, 12)
		local free, hit = 0, -1
		for k = 1, steps do
			local f = k / steps
			if stickOverlap(a, b, a.aimYawPrev + turnA0 * f, b.aimYawPrev + turnB0 * f) > 0 then
				hit = f
				break
			end
			free = f
		end
		if hit > 0 then
			-- Narrow the meeting point down between the last clear step and the first touching one.
			for _ = 1, 4 do
				local f = (free + hit) / 2
				if stickOverlap(a, b, a.aimYawPrev + turnA0 * f, b.aimYawPrev + turnB0 * f) > 0 then
					hit = f
				else
					free = f
				end
			end
			overlap, nx, nz, pax, paz, pbx, pbz = stickOverlap(a, b, a.aimYawPrev + turnA0 * hit, b.aimYawPrev + turnB0 * hit)
			-- The bump below uses each stick's speed as it was swung, so take it before stopping them.
			local function spinVel(s: Skater, turn: number, px: number, pz: number): Vector3
				local v = Vector3.new(s.vel.X, 0, s.vel.Z) + Vector3.new(-(pz - s.pos.Z), 0, px - s.pos.X) * (turn / dt)
				local m = v.Magnitude
				if m > STICK.MaxBladeSpeed then
					v = v / m * STICK.MaxBladeSpeed
				end
				return v
			end
			local n = Vector3.new(nx, 0, nz)
			local vn = (spinVel(b, turnB0, pbx, pbz) - spinVel(a, turnA0, pax, paz)):Dot(n)
			a.aimYaw = a.aimYawPrev + turnA0 * free
			b.aimYaw = b.aimYawPrev + turnB0 * free
			if vn > 0 then
				local j = math.min((1 + STICK.StickBodyRestitution) * vn * 0.5, STICK.StickBumpMaxSpeed)
				a.vel += n * j
				b.vel -= n * j
			end
			return
		end
		if hit < 0 and free >= 1 then
			return -- clear all the way through the turn
		end
	end
	overlap, nx, nz, pax, paz, pbx, pbz = stickOverlap(a, b, a.aimYaw, b.aimYaw)
	if overlap <= 0 then
		-- Not touching now: did either stick swing through the other during the tick?
		local turnA = wrapAngle(a.aimYaw - a.aimYawPrev)
		local turnB = wrapAngle(b.aimYaw - b.aimYawPrev)
		local steps = math.min(8, math.ceil(math.max(math.abs(turnA), math.abs(turnB)) / STICK_SWEEP_STEP))
		for k = 1, steps - 1 do
			local f = k / steps
			overlap, nx, nz, pax, paz, pbx, pbz = stickOverlap(a, b, a.aimYawPrev + turnA * f, b.aimYawPrev + turnB * f)
			if overlap > 0 then
				swept = true
				break
			end
		end
		if overlap <= 0 then
			return
		end
	end
	local n = Vector3.new(nx, 0, nz)
	if not swept then
		local step = math.min(overlap * 0.5, STICK.StickPushMaxStep)
		a.pos += n * step
		b.pos -= n * step
	end
	-- Speed of each stick where they touch: the skater's own speed plus its spin.
	local function pointVel(s: Skater, px: number, pz: number): Vector3
		local omega = wrapAngle(s.aimYaw - s.aimYawPrev) / dt
		local v = Vector3.new(s.vel.X, 0, s.vel.Z) + Vector3.new(-(pz - s.pos.Z), 0, px - s.pos.X) * omega
		local m = v.Magnitude
		if m > STICK.MaxBladeSpeed then
			v = v / m * STICK.MaxBladeSpeed
		end
		return v
	end
	local vn = (pointVel(b, pbx, pbz) - pointVel(a, pax, paz)):Dot(n)
	if vn > 0 then
		local j = math.min((1 + STICK.StickBodyRestitution) * vn * 0.5, STICK.StickBumpMaxSpeed)
		a.vel += n * j
		b.vel -= n * j
	end
end

local function stickHitsBodies(w: World, dt: number)
	local skaters = w.skaters
	for _, a in skaters do
		for _, b in skaters do
			if b ~= a then
				Sim.stickBodyContact(a, b, dt, w)
			end
		end
	end
	for i = 1, #skaters - 1 do
		for j = i + 1, #skaters do
			Sim.stickStickContact(skaters[i], skaters[j], dt)
		end
	end
	for _, s in skaters do
		local p, v = Sim.resolveStickNets(s.pos, s.vel, s.aimYaw)
		p, v = Sim.resolveBoards(p, v, BOARD_R, SKATER.BoardRestitution)
		s.pos, s.vel = Sim.resolveNetsForSkater(p, v, BODY_R)
		s.blade = Sim.bladeAt(s.pos, s.aimYaw, s.aimRadius)
	end
end
World.stickHitsBodies = stickHitsBodies

local function stepPuck(w: World, dt: number)
	local puck = w.puck
	if w.puckHeld then
		-- Face-off: the puck hangs still over the dot until the match lets it go.
		puck.vel = Vector3.zero
		w.idle = 0
		return
	end
	local substeps = PUCK.Substeps
	local sub = dt / substeps
	local skaters = w.skaters
	local count = #skaters

	for i = 1, substeps do
		local prev = puck.pos
		local vel = puck.vel
		local y, vy = puck.pos.Y, vel.Y
		local airborne = y > PUCK_REST_Y + 1e-3 or vy > 0
		if airborne then
			vy -= PUCK.Gravity * sub
			y += vy * sub
			if y <= PUCK_REST_Y then
				y = PUCK_REST_Y
				-- Build 29: a puck coming down from a real height smacks the ice (a cue only).
				if -vy >= PUCK.LandCueSpeed then
					emit(w, "Land", puck.pos.X, puck.pos.Z, -vy)
				end
				-- Pucks don't bounce: whatever height it falls from, it lands flat and stays down.
				vy = 0
			end
		else
			vy = 0
		end

		local planar = Vector3.new(vel.X, 0, vel.Z)
		local speed = planar.Magnitude
		if speed > 0 and not airborne then
			local slowed = speed - (PUCK.IceDeceleration + speed * PUCK.IceDragPerSecond) * sub
			planar = if slowed > 0 then planar / speed * slowed else Vector3.zero
		end
		puck.vel = Vector3.new(planar.X, vy, planar.Z)
		puck.pos = Vector3.new(prev.X + planar.X * sub, y, prev.Z + planar.Z * sub)

		if w.stickHits and count > 0 then
			-- The start index rotates by tick, so no slot always wins a contested puck.
			local start = w.tick % count
			local fraction = i / substeps
			local prevFraction = (i - 1) / substeps
			for offset = 0, count - 1 do
				contactBlade(w, skaters[(start + offset) % count + 1], fraction, prevFraction, prev)
			end
		end

		if puck.pos.Y < PUCK.BodyHeight then
			for _, s in skaters do
				collideBody(w, s)
			end
		end
		if w.stickHits then
			for _, s in skaters do
				slideToHeel(w, s, sub)
				holdPocket(w, s, sub)
			end
		end

		collideNets(w, prev)
		local pos, v, hit = Sim.resolveBoards(puck.pos, puck.vel, PUCK.Radius, PUCK.BoardRestitution, PUCK.BoardHugSpeed)
		puck.pos, puck.vel = pos, v
		if hit >= PUCK.BoardCueSpeed then
			emit(w, "Board", pos.X, pos.Z, hit)
		end

		local out = puck.vel
		local outSpeed = math.sqrt(out.X * out.X + out.Z * out.Z)
		if outSpeed > PUCK.MaxSpeed then
			local scale = PUCK.MaxSpeed / outSpeed
			puck.vel = Vector3.new(out.X * scale, out.Y, out.Z * scale)
		end

		checkGoal(w, prev)
	end

	-- Bad numbers must never reach clients: re-centre instead.
	local p = puck.pos
	if p.X ~= p.X or p.Y ~= p.Y or p.Z ~= p.Z or puck.vel.X ~= puck.vel.X or puck.vel.Z ~= puck.vel.Z then
		World.placePuck(w, Vector3.zero)
		emit(w, "Stuck", 0, 0, 0)
	end
end

function World.step(w: World, dt: number)
	local outer = LAYOUT
	LAYOUT = w.layout
	w.tick += 1
	w.time += dt
	w.idle += dt
	for _, s in w.skaters do
		Sim.stepMotion(s, s.input, dt, w.controlsEnabled)
	end
	stepSkaterPairs(w)
	for _, s in w.skaters do
		local p, v = Sim.resolveStick(s.pos, s.vel, s.aimYaw)
		p, v = Sim.resolveBoards(p, v, BOARD_R, SKATER.BoardRestitution)
		s.pos, s.vel = Sim.resolveNetsForSkater(p, v, BODY_R)
		Sim.stepStick(s, s.input, dt)
	end
	stickHitsBodies(w, dt)
	stepPuck(w, dt)
	-- A puck that ends up resting inside a net without counting (say it dropped in over the
	-- crossbar) is out of everyone's reach, so call the faceoff after a short moment.
	local p = w.puck.pos
	local depthIn, across = Sim.netFrame(p.X, p.Z)
	local deadInNet = Sim.insideNet(depthIn - PUCK.Radius, across) and p.Y < Sim.netRoofAt(depthIn) and not w.goalLatched and w.idle >= 2
	if (w.idle >= PUCK.IdleResetSeconds or deadInNet) and w.goalsEnabled then
		w.idle = 0
		emit(w, "Stuck", w.puck.pos.X, w.puck.pos.Z, 0)
	end
	LAYOUT = outer
end

-- Puck-only step, for client-side puck prediction around the local stick and extra pucks that
-- share another world's skaters.
function World.stepPuck(w: World, dt: number)
	local outer = LAYOUT
	LAYOUT = w.layout
	stepPuck(w, dt)
	LAYOUT = outer
end

-- Build 31: pucks that live in separate worlds (the pond's shared pucks, practice's extra pucks)
-- knock into each other instead of sliding through. Two overlapping pucks at about the same
-- height are pushed apart (half each) and swap the part of their speed along the line between
-- them, with a little loss; two dropped on the very same spot are split along a fixed direction.
-- Returns the hardest impact speed this step (0 = none), for a click.
local PUCK_RESTITUTION = 0.75
function World.collidePucks(worlds: { World }): (number, number, number)
	local hardest, hx, hz = 0, 0, 0
	local r2 = PUCK.Radius * 2
	local n = #worlds
	for i = 1, n - 1 do
		local a = worlds[i].puck
		for j = i + 1, n do
			local b = worlds[j].puck
			if math.abs(a.pos.Y - b.pos.Y) < PUCK.Thickness then
				local dx, dz = b.pos.X - a.pos.X, b.pos.Z - a.pos.Z
				local d2 = dx * dx + dz * dz
				if d2 < r2 * r2 then
					local d = math.sqrt(d2)
					local nx, nz = 1, 0
					if d > 1e-4 then
						nx, nz = dx / d, dz / d
					else
						local k = (i * 7 + j * 13) % 8
						nx, nz = math.cos(k * math.pi / 4), math.sin(k * math.pi / 4)
					end
					local push = (r2 - d) / 2 + 1e-3
					a.pos = Vector3.new(a.pos.X - nx * push, a.pos.Y, a.pos.Z - nz * push)
					b.pos = Vector3.new(b.pos.X + nx * push, b.pos.Y, b.pos.Z + nz * push)
					local va = a.vel.X * nx + a.vel.Z * nz
					local vb = b.vel.X * nx + b.vel.Z * nz
					local closing = va - vb
					if closing > 0 then
						local jn = (1 + PUCK_RESTITUTION) * closing / 2
						a.vel = Vector3.new(a.vel.X - nx * jn, a.vel.Y, a.vel.Z - nz * jn)
						b.vel = Vector3.new(b.vel.X + nx * jn, b.vel.Y, b.vel.Z + nz * jn)
						if closing > hardest then
							hardest, hx, hz = closing, (a.pos.X + b.pos.X) / 2, (a.pos.Z + b.pos.Z) / 2
						end
					end
					-- A puck knocked by another counts as moving: neither goes home as forgotten.
					worlds[i].idle = math.min(worlds[i].idle, 1)
					worlds[j].idle = math.min(worlds[j].idle, 1)
				end
			end
		end
	end
	return hardest, hx, hz
end

-- True when the puck sits dead inside a net (dropped in without counting).
function World.deadInNet(w: World): boolean
	local outer = LAYOUT
	LAYOUT = w.layout
	local p = w.puck.pos
	local depthIn, across = Sim.netFrame(p.X, p.Z)
	local dead = Sim.insideNet(depthIn - PUCK.Radius, across) and p.Y < Sim.netRoofAt(depthIn) and not w.goalLatched
	LAYOUT = outer
	return dead
end

function World.drainEvents(w: World): { Event }
	local events = w.events
	w.events = {}
	return events
end

return Sim
