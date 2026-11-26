--!strict
-- The Pond: one shared open world on a frozen lake. The match rink sits in the middle (solid
-- from outside, its matches are the server's 3v3), an open rink with boards only round its two
-- ends lies to the north, and the mini-game stations to the south. The physics (Sim), the
-- server (PondService) and the scene (ArenaBuilder) all read this one layout, so what you see
-- is exactly what you collide with.

local Config = require(script.Parent:WaitForChild("GameConfig"))

local ARENA = Config.Arena
local GOAL = Config.Goal
local HX = ARENA.Length / 2
local HZ = ARENA.Width / 2
local CR = ARENA.CornerRadius

local PondLayout = {}

export type Box = { cx: number, cz: number, hx: number, hz: number, cr: number }
export type Net = { x: number, z: number, side: number }
export type WallZone = { minX: number, maxX: number, minZ: number, maxZ: number, cx: number, cz: number, walls: { { number } } }
export type Layout = {
	bound: Box, -- the lake shore: skaters and pucks stay inside it
	blocks: { Box }, -- solid from outside; blocks[1] is the match rink (the arena, at the origin)
	wallHalf: number, -- half the thickness of the open rink's boards
	wallZones: { WallZone }, -- the open rink's end boards, as centre-line segments {ax, az, bx, bz}
	nets: { Net }, -- every net: its goal line at x, centred on z, open toward -side * X
}

-- Centre of the open rink (north of the match rink). Same size and markings as the match rink.
local OPEN_Z = 185
PondLayout.OPEN_Z = OPEN_Z
PondLayout.OPEN_CENTER = Vector3.new(0, 0, OPEN_Z)

-- The open rink keeps its boards only round the ends: the end boards behind the nets and the two
-- corner curves on each end. Both long sides are open ice.
local WALL_HALF = 0.6 -- the drawn boards are 1.2 thick behind the face

local zones: { WallZone } = {}
do
	local ix, iz = HX - CR, HZ - CR
	local r = CR + WALL_HALF
	local ARC_STEPS = 16
	for _, sx in { -1, 1 } do
		local walls: { { number } } = {}
		local function add(ax: number, az: number, bx: number, bz: number)
			table.insert(walls, { ax, az, bx, bz })
		end
		add(sx * (HX + WALL_HALF), OPEN_Z - iz, sx * (HX + WALL_HALF), OPEN_Z + iz)
		for _, sz in { -1, 1 } do
			local px, pz = nil, nil
			for i = 0, ARC_STEPS do
				local a = (math.pi / 2) * i / ARC_STEPS
				local x, z = sx * (ix + math.cos(a) * r), OPEN_Z + sz * (iz + math.sin(a) * r)
				if px and pz then
					add(px, pz, x, z)
				end
				px, pz = x, z
			end
		end
		local lo, hi = ix - 6, HX + 6
		table.insert(zones, {
			minX = if sx > 0 then lo else -hi,
			maxX = if sx > 0 then hi else -lo,
			minZ = OPEN_Z - HZ - 6,
			maxZ = OPEN_Z + HZ + 6,
			cx = 0,
			cz = OPEN_Z,
			walls = walls,
		})
	end
end

-- Net indices: 1, 2 the open rink; 3 targets; 4 slalom finish; 5 hardest shot.
PondLayout.NET_OPEN_A = 1
PondLayout.NET_OPEN_B = 2
PondLayout.NET_TARGETS = 3
PondLayout.NET_SLALOM = 4
PondLayout.NET_SPEED = 5

local NETS: { Net } = {
	{ x = -GOAL.X, z = OPEN_Z, side = -1 },
	{ x = GOAL.X, z = OPEN_Z, side = 1 },
	{ x = 112, z = -98, side = 1 },
	{ x = -18, z = -128, side = 1 },
	{ x = 112, z = -158, side = 1 },
}

-- Slalom gates: the skater passes between each pair of cones in order (gate centre x, z).
PondLayout.GATE_HALF = 7 -- Build 28: wider gates (12.4 studs clear between the cones; 7.4 before)
PondLayout.GATES = {
	Vector2.new(-128, -122),
	Vector2.new(-108, -134),
	Vector2.new(-88, -122),
	Vector2.new(-68, -134),
	Vector2.new(-48, -122),
}
PondLayout.SLALOM_START_X = -138

-- The slalom cones are solid: each is a small round block that skaters and pucks bounce off.
PondLayout.CONE_RADIUS = 0.8
local BLOCKS: { Box } = { { cx = 0, cz = 0, hx = HX + 1.4, hz = HZ + 1.4, cr = CR + 1.4 } }
for _, g in PondLayout.GATES do
	for _, s in { -1, 1 } do
		local r = PondLayout.CONE_RADIUS
		table.insert(BLOCKS, { cx = g.X, cz = g.Y + s * PondLayout.GATE_HALF, hx = r, hz = r, cr = r })
	end
end

PondLayout.LAYOUT = table.freeze({
	bound = { cx = 0, cz = 45, hx = 178, hz = 232, cr = 100 },
	blocks = BLOCKS,
	wallHalf = WALL_HALF,
	wallZones = zones,
	nets = NETS,
}) :: Layout

-- Where everyone arrives, the shared pucks' homes, and the match queue ring.
PondLayout.SPAWN = Vector3.new(-30, 0, 95)
PondLayout.QUEUE = Vector3.new(0, 0, 74)
PondLayout.QUEUE_RADIUS = 6
PondLayout.OPEN_PUCK = Vector3.new(0, 0, OPEN_Z)
PondLayout.LAKE_PUCKS = { Vector3.new(-62, 0, 90), Vector3.new(26, 0, 102), Vector3.new(66, 0, 86) }

-- Mini games. Stand in a station's ring to start it; one player at a time per station.
export type Station = {
	id: string,
	title: string,
	blurb: string,
	pad: Vector3, -- the start ring
	spot: Vector3, -- where the game's puck is placed
	net: number,
	area: Vector3, -- leave this far from it (AREA_RADIUS) and the game ends
}
PondLayout.PAD_RADIUS = 5
PondLayout.AREA_RADIUS = 75

PondLayout.STATIONS = {
	{
		id = "Targets",
		title = "TARGETS",
		blurb = "Hit all four corner targets. Lift the puck for the top two.",
		pad = Vector3.new(70, 0, -98),
		spot = Vector3.new(90, 0, -98),
		net = 3,
		area = Vector3.new(92, 0, -98),
	},
	{
		id = "Slalom",
		title = "SLALOM",
		blurb = "Carry the puck through every gate, then score.",
		pad = Vector3.new(-150, 0, -128),
		spot = Vector3.new(-143, 0, -128),
		net = 4,
		area = Vector3.new(-85, 0, -128),
	},
	{
		id = "Speed",
		title = "HARDEST SHOT",
		blurb = "Five shots. Your fastest one into the net counts.",
		pad = Vector3.new(70, 0, -158),
		spot = Vector3.new(92, 0, -158),
		net = 5,
		area = Vector3.new(92, 0, -158),
	},
} :: { Station }

-- Targets in the mouth of the targets net: (across the mouth, height of the puck's centre).
PondLayout.TARGETS = { Vector2.new(-5, 1.0), Vector2.new(5, 1.0), Vector2.new(-5, 5.0), Vector2.new(5, 5.0) }
PondLayout.TARGET_RADIUS = 1.8


PondLayout.MAX_SKATERS = 16
-- Every puck rides in one snapshot: 15 + 20 x 16 skaters + 15 x 40 pucks = 935 bytes, under the
-- 1,000-byte limit for unreliable remotes.
PondLayout.MAX_PUCKS = 40
PondLayout.OWN_PUCKS = 5 -- pucks each player can drop with P

return PondLayout
