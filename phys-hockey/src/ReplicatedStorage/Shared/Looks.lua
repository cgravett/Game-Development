--!strict
-- Builds the original cartoon skater from smooth primitives: a pin-shaped body, a big round
-- head with a painted-on face, mitts, a stick and a team ring on the ice. Every cosmetic in
-- Catalog maps to a few parts here. The rig is purely visual; hitboxes live in Sim.

local Catalog = require(script.Parent.Catalog)
local GameConfig = require(script.Parent.GameConfig)

local Looks = {}

export type Kit = {
	jersey: Color3,
	trim: Color3,
	band: Color3,
	pants: Color3,
	glove: Color3,
	helmet: Color3,
	ring: Color3,
	tag: Color3,
}

export type Rig = {
	model: Model,
	body: { BasePart }, -- parts that ride the leaning body
	offsets: { CFrame }, -- each body part relative to the feet origin, facing -Z
	head: BasePart,
	gloveA: BasePart,
	gloveB: BasePart,
	cuffA: BasePart, -- the glove cuffs ride with the gloves
	cuffB: BasePart,
	gloveOffset: CFrame, -- each glove part relative to its hand frame
	cuffOffset: CFrame,
	stick: { StickPiece }, -- every visible piece of the stick, placed by Looks.placeStick
	stickModel: Model, -- the stick's parts, grouped so it can be outlined through the body
	ring: { BasePart },
	ringOffsets: { CFrame },
	look: Catalog.Look,
	team: number,
	scale: number, -- body size (1 = full); the hands follow it
	anim: RigAnim?, -- Build 40: animated pieces (spinning, bobbing, pulsing), if it wears any
}

-- Build 40: what Looks.animate moves on a rig. `spins` are body parts (index i into body and
-- offsets) that turn about `axis` through their own centre and bob; `pulses` are neon parts whose
-- colour breathes between a and b. Build 41: a spin may turn about a point `piv` away from its
-- centre (piv is that point minus the centre: the scanner light sweeping round the head, planets
-- orbiting it), and may swing back and forth (`swing` radians each way) instead of turning round.
export type RigAnim = {
	spins: { { i: number, at: Vector3, rot: CFrame, axis: Vector3?, rate: number, bob: number, piv: Vector3?, swing: number?, phase: number? } },
	pulses: { { part: BasePart, a: Color3, b: Color3, rate: number, phase: number } },
}

-- One visible piece of a stick. Pieces ride either the shaft (measured from the butt or the
-- heel end) or the blade (an offset in the blade frame: -Z toward the toe, +Y up). A piece with
-- `stretch` spans the whole shaft and is resized as the shaft length changes.
export type StickPiece = {
	part: BasePart,
	on: string, -- "shaft" or "blade"
	at: CFrame, -- offset (rotation included) in that frame
	fromButt: number?, -- shaft pieces: distance from the butt end
	fromHeel: number?, -- shaft pieces: distance from the heel end
	stretch: boolean?, -- shaft pieces: spans the shaft; Size.X follows its length
}

-- Proportions follow the toy-like references: a squat pawn body, a big round head and a round
-- helmet shell that sits just above the eyes.
Looks.HEAD_Y = 4.95
Looks.HEAD_R = 1.75 -- half the head's width; hats are placed against this
Looks.GRIP_Y = 2.75
Looks.SHAFT_D = 0.34 -- shaft depth (along the blade); was 0.38, thinned a touch in Build 26
-- Modelled sticks (StickMeshes) draw their shaft this much thinner than modelled, to match.
local SHAFT_THIN = 0.88
Looks.SHAFT_W = 0.39 -- shaft width (across the blade face); was 0.44
-- thickness, height, heel to toe (the sim's blade length, so the drawn blade is the hitbox)
Looks.BLADE_SIZE = Vector3.new(GameConfig.Stick.BladeThickness * 2, GameConfig.Stick.BladeDrawnHeight, GameConfig.Stick.BladeLength)
Looks.REACH = GameConfig.Stick.Reach -- the heel sits REACH - half a blade out from the skater
Looks.BLADE_ANGLE = GameConfig.Stick.BladeAngle -- the blade runs this far off the stick's line

-- Where the blade's centre sits for a stick pointing at `yaw` (matches Sim.bladeAt in open ice).
function Looks.bladeCentre(origin: Vector3, yaw: number): Vector3
	local half = Looks.BLADE_SIZE.Z / 2
	local heel = Looks.REACH - half
	local by = yaw + Looks.BLADE_ANGLE
	return Vector3.new(origin.X + math.cos(yaw) * heel + math.cos(by) * half, origin.Y, origin.Z + math.sin(yaw) * heel + math.sin(by) * half)
end
Looks.PLAY_SCALE = 0.85 -- skaters in a match are a little smaller than the locker model
local BUTT_EXTRA = 0.6 -- how far the shaft pokes out above the top hand
-- Cylinders run along X; this lays one along a frame's Z axis.
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)

local WHITE = Color3.fromRGB(246, 247, 250)
-- The nebula image on the Galaxy Body's Cosmos meshes (OutfitMeshes.Galaxy), shared by the
-- Galaxy Puck so the two read as one set.
local GALAXY_TEXTURE = "rbxassetid://129462815559609"
local INK = Color3.fromRGB(26, 26, 32)
local ICE = Color3.fromRGB(226, 238, 248)
local RIVET = Color3.fromRGB(170, 174, 182)

-- Away: white jersey with blue bands. Home: red jersey with black and white bands. Both wear
-- black pants, which is what makes the pawn silhouette read from the high camera.
local KITS: { [number]: Kit } = {
	[1] = {
		jersey = Color3.fromRGB(244, 246, 250),
		trim = Color3.fromRGB(40, 104, 214),
		band = Color3.fromRGB(24, 44, 110),
		pants = Color3.fromRGB(34, 36, 44),
		glove = Color3.fromRGB(40, 104, 214),
		helmet = Color3.fromRGB(40, 92, 196),
		ring = Color3.fromRGB(46, 112, 226),
		tag = Color3.fromRGB(40, 104, 214),
	},
	[2] = {
		jersey = Color3.fromRGB(222, 54, 58),
		trim = Color3.fromRGB(30, 30, 36),
		band = Color3.fromRGB(250, 250, 250),
		pants = Color3.fromRGB(30, 30, 36),
		glove = Color3.fromRGB(70, 72, 82),
		helmet = Color3.fromRGB(58, 60, 68),
		ring = Color3.fromRGB(228, 56, 60),
		tag = Color3.fromRGB(214, 48, 52),
	},
	-- Neutral kit for the lobby and the pond.
	[0] = {
		jersey = Color3.fromRGB(222, 54, 58),
		trim = Color3.fromRGB(30, 30, 36),
		band = Color3.fromRGB(250, 250, 250),
		pants = Color3.fromRGB(30, 30, 36),
		glove = Color3.fromRGB(70, 72, 82),
		helmet = Color3.fromRGB(58, 60, 68),
		ring = Color3.fromRGB(255, 160, 50),
		tag = Color3.fromRGB(255, 140, 40),
	},
}

function Looks.kit(team: number): Kit
	return KITS[team] or KITS[0]
end

local function part(model: Model, name: string, size: Vector3, color: Color3, shape: string?, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = true
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape == "ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "cyl" then
		p.Shape = Enum.PartType.Cylinder
	elseif shape == "egg" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = model
	return p
end

-- Modelled gear: Blender meshes kept as MeshPart templates in ReplicatedStorage.GearMeshes
-- (assets/gear in the project; built by the gear script). Roblox centres each mesh on its
-- bounding box, so GEAR_CENTRE is where that centre sits in the piece's own frame: the head
-- centre for helmet pieces, the hand (on the shaft) for gloves, the blade centre for blades.
-- Without the templates the rig falls back to the primitive shapes.
local GEAR_CENTRE = {
	Helmet = Vector3.new(0, 0.577, 0.1115),
	HelmetTrim = Vector3.new(0, -0.28, 0.335),
	Visor = Vector3.new(0, 0.0643, -1.3904),
	Glove = Vector3.new(0.0663, 0.0819, 0.1246),
	GloveCuff = Vector3.new(0.1203, 0.9605, 0),
	Blade = Vector3.new(-0.1087, 0.1108, 0),
	BladeTape = Vector3.new(-0.0877, 0, -0.21),
}
local GLOVE_SCALE = 0.8 -- the modelled glove is sized for a real grip; this fits the cartoon hands
local gearFolder: Instance? = nil
local function gear(model: Instance, name: string, color: Color3): MeshPart?
	if not gearFolder then
		gearFolder = game:GetService("ReplicatedStorage"):FindFirstChild("GearMeshes")
	end
	local template = gearFolder and gearFolder:FindFirstChild(name)
	if not (template and template:IsA("MeshPart")) then
		return nil
	end
	local p = template:Clone()
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = model
	return p
end

local function hasGear(name: string): boolean
	if not gearFolder then
		gearFolder = game:GetService("ReplicatedStorage"):FindFirstChild("GearMeshes")
	end
	local template = gearFolder and gearFolder:FindFirstChild(name)
	return template ~= nil and template:IsA("MeshPart")
end

-- Build 40: the Nova set (the first-full-match reward): graphite and gunmetal with cyan and
-- magenta neon. Its neon breathes in one rhythm across all four pieces (PULSE), the reactor's
-- rings spin and its core bobs (BACK_ANIM), and the blade throws sparks (meshStick).
local NOVA_GRAPH = Color3.fromRGB(26, 28, 42)
local NOVA_GUN = Color3.fromRGB(60, 66, 88)
local NOVA_CYAN = Color3.fromRGB(0, 225, 255)
local NOVA_MAG = Color3.fromRGB(255, 50, 200)
local NOVA_CYAN_DIM = Color3.fromRGB(0, 105, 150)
local NOVA_CYAN_HOT = Color3.fromRGB(200, 250, 255)
local NOVA_MAG_HOT = Color3.fromRGB(255, 175, 238)
local NOVA_MAG_DIM = Color3.fromRGB(140, 20, 110)
local NOVA_BEAT = 3.2 -- radians a second: one breath about every two seconds

-- Neon regions whose colour pulses, by style (outfit, back, headwear and stick styles share one
-- table: their names never clash) then region: { a, b, rate, phase }.
local PULSE: { [string]: { [string]: { any } } } = {
	Nova = {
		Glow = { NOVA_CYAN, NOVA_CYAN_DIM, NOVA_BEAT, 0 },
		Core = { NOVA_MAG, NOVA_MAG_HOT, NOVA_BEAT * 1.5, 0 },
	},
	NovaReactor = {
		PlateGlow = { NOVA_CYAN, NOVA_CYAN_DIM, NOVA_BEAT, 0 },
		EmitterGlow = { NOVA_MAG, NOVA_MAG_HOT, NOVA_BEAT * 2, 0 },
		Core = { NOVA_MAG, NOVA_MAG_HOT, NOVA_BEAT * 1.5, 0 },
		RingAGlow = { NOVA_CYAN, NOVA_CYAN_HOT, NOVA_BEAT, 1.6 },
		RingBGlow = { NOVA_MAG, NOVA_MAG_DIM, NOVA_BEAT, 0.8 },
	},
	NovaVisor = {
		Glow = { NOVA_CYAN, NOVA_CYAN_DIM, NOVA_BEAT, 0 },
		PodGlow = { NOVA_MAG, NOVA_MAG_HOT, NOVA_BEAT * 1.5, 0 },
	},
	NovaBlade = {
		Edge = { NOVA_CYAN, NOVA_CYAN_DIM, NOVA_BEAT, 0 },
		Inlay = { NOVA_MAG, NOVA_MAG_HOT, NOVA_BEAT * 1.5, 0 },
		BandGlow = { NOVA_CYAN, NOVA_CYAN_DIM, NOVA_BEAT, 0 },
		Gem = { NOVA_MAG, NOVA_MAG_HOT, NOVA_BEAT * 1.5, 0 },
	},
	-- Build 41: the animated season-pass pieces. "accent", "accentHot" and "accentDim" are the
	-- item's own accent colour (one mesh, several items in their own colours).
	ScanVisor = {
		Scan = { "accentHot", "accent", 9, 0 },
		Glow = { "accent", "accentDim", NOVA_BEAT, 0 },
	},
	HoloSpecs = {
		RingL = { "accent", "accentHot", NOVA_BEAT, 0 },
		RingR = { "accent", "accentHot", NOVA_BEAT, math.pi },
	},
	LavaGoggles = {
		Lava = { Color3.fromRGB(255, 96, 16), Color3.fromRGB(255, 196, 60), 2.2, 0 },
		Drips = { Color3.fromRGB(255, 110, 20), Color3.fromRGB(255, 180, 50), 2.2, 0.6 },
	},
	Halo = {
		Gem = { "accent", "accentHot", NOVA_BEAT * 1.5, 0 },
		RingGlow = { "accent", "accentHot", NOVA_BEAT, 0 },
	},
	OrbitCrown = {
		Core = { "accent", "accentHot", NOVA_BEAT * 1.5, 0 },
		PlanetRing = { "accent", "accentHot", NOVA_BEAT, 1 },
	},
	ToxicSludge = {
		Goo = { Color3.fromRGB(110, 245, 50), Color3.fromRGB(200, 255, 110), 2.4, 0 },
		Ooze = { Color3.fromRGB(110, 245, 50), Color3.fromRGB(200, 255, 110), 2.4, 0.8 },
		Bubbles = { Color3.fromRGB(200, 255, 110), Color3.fromRGB(120, 255, 60), 4, 0 },
		ShaftGlow = { Color3.fromRGB(110, 245, 50), Color3.fromRGB(60, 150, 30), 2.4, 1.6 },
		BandGlow = { Color3.fromRGB(110, 245, 50), Color3.fromRGB(60, 150, 30), 2.4, 1.6 },
		Gem = { Color3.fromRGB(110, 245, 50), Color3.fromRGB(200, 255, 110), 2.4, 0 },
	},
	CarbonStrike = {
		-- A heartbeat: quick and bright.
		Circuit = { Color3.fromRGB(255, 31, 51), Color3.fromRGB(255, 170, 180), 7, 0 },
		Edge = { Color3.fromRGB(255, 31, 51), Color3.fromRGB(120, 10, 20), 7, 1.2 },
		ShaftGlow = { Color3.fromRGB(255, 31, 51), Color3.fromRGB(120, 10, 20), 3.5, 0 },
		BandGlow = { Color3.fromRGB(255, 31, 51), Color3.fromRGB(120, 10, 20), 3.5, 0 },
		Gem = { Color3.fromRGB(255, 31, 51), Color3.fromRGB(255, 170, 180), 7, 0 },
	},
	ChampionGold = {
		Star = { Color3.fromRGB(255, 247, 209), Color3.fromRGB(255, 200, 70), NOVA_BEAT, 0 },
		Gems = { Color3.fromRGB(255, 247, 209), Color3.fromRGB(255, 200, 70), NOVA_BEAT, 1.5 },
		TrophyGem = { Color3.fromRGB(255, 247, 209), Color3.fromRGB(255, 200, 70), NOVA_BEAT, 0.7 },
	},
}

-- A PULSE colour: a fixed Color3, or one of the item's own colours.
local function pulseTint(v: any, main: Color3?, accent: Color3?): Color3
	if typeof(v) == "Color3" then
		return v
	end
	local a = accent or main or Color3.new(1, 1, 1)
	if v == "accentHot" then
		return a:Lerp(Color3.new(1, 1, 1), 0.6)
	elseif v == "accentDim" then
		return a:Lerp(Color3.new(0, 0, 0), 0.55)
	elseif v == "main" then
		return main or a
	end
	return a
end

-- Back bling regions that float: each bobs (bob = 1) and may spin about `axis` through its own
-- centre at `rate` radians a second. Every such region is modelled centred on its pivot, so its
-- bounding-box centre (the row's offset) is the point it turns about.
local BACK_ANIM: { [string]: { [string]: { axis: Vector3?, rate: number?, bob: number?, pivot: Vector3?, swing: number? } } } = {
	NovaReactor = {
		Core = { bob = 1 },
		CoreShell = { bob = 1 },
		-- Both rings turn about Z (straight out of the back): ring A like a wheel, the tilted ring
		-- B wobbling round the core; about Z neither ever reaches the other or the emitter post.
		RingA = { axis = Vector3.zAxis, rate = 1.7, bob = 1 },
		RingAGlow = { axis = Vector3.zAxis, rate = 1.7, bob = 1 },
		RingB = { axis = Vector3.zAxis, rate = -3.4, bob = 1 },
		RingBGlow = { axis = Vector3.zAxis, rate = -3.4, bob = 1 },
	},
	-- Build 41: headwear (Looks HEADWEAR). `pivot` is the point turned about, relative to the head
	-- centre (else the region's own centre); `swing` swings it that far each way instead.
	-- The scanner light runs along the visor, an arc about the head's vertical axis.
	ScanVisor = {
		Scan = { axis = Vector3.yAxis, rate = 2.6, swing = 0.72, pivot = Vector3.new(0, 0.02, 0) },
	},
	-- The reticles turn in their own planes (the lens normals), one each way.
	HoloSpecs = {
		RingL = { axis = Vector3.new(-0.3273, 0.0119, -0.9448), rate = 1.4 },
		RingR = { axis = Vector3.new(0.3273, 0.0119, -0.9448), rate = -1.4 },
	},
	-- The halo turns about its own (tilted) axis and floats.
	Halo = {
		Ring = { axis = Vector3.new(0, 0.9759, -0.2182), rate = 1.1, bob = 1 },
		RingGlow = { axis = Vector3.new(0, 0.9759, -0.2182), rate = 1.1, bob = 1 },
	},
	-- The planet (and its ring) and the moon orbit the head round the tilted track.
	OrbitCrown = {
		Planet = { axis = Vector3.new(0, 0.9287, 0.3709), rate = 0.9, pivot = Vector3.new(0, 0.85, 0.03) },
		PlanetRing = { axis = Vector3.new(0, 0.9287, 0.3709), rate = 0.9, pivot = Vector3.new(0, 0.85, 0.03) },
		Moon = { axis = Vector3.new(0, 0.9287, 0.3709), rate = 1.5, pivot = Vector3.new(0, 0.85, 0.03) },
	},
}
local BOB_AMP, BOB_RATE = 0.09, 2.2

-- Outfits (assets/outfits/outfits.py, built in Blender): a modelled body that takes the place of
-- the primitive jersey drum, shoulders, bands, collar, pants and hem. The templates are MeshParts
-- in ReplicatedStorage.OutfitMeshes.<Style> (cloud place only, like StickMeshes). Each row is
-- { region, its centre in the body frame, colour, material, transparency? }. The team still reads
-- from the ring on the ice, the name tag, the gloves and the helmet. Without the folder the skater
-- keeps the team kit.
type Outfit = {
	parts: { { any } },
	cuff: Color3, -- glove cuffs
	hood: boolean?, -- covers the head: no hat or hair is drawn
	fx: string?, -- "stars" (twinkling inside the body), "wisps" (rising from the hem) or "nova" (motes off the hover ring)
	mesh: string?, -- Build 34: another outfit's meshes in new colours (Mystery Box outfits)
}
local REPLACED_BY_OUTFIT = { Hem = true, Pants = true, Jersey = true, Shoulders = true, Band = true, Band2 = true, Band3 = true, Collar = true }
local OUTFITS: { [string]: Outfit } = {
	Santa = {
		cuff = Color3.fromRGB(250, 248, 242),
		parts = {
			{ "Coat", Vector3.new(0, 2.3, -0.006), Color3.fromRGB(199, 28, 38), Enum.Material.Fabric },
			{ "Trousers", Vector3.new(0, 0.63, 0), Color3.fromRGB(163, 20, 31), Enum.Material.Fabric },
			{ "Fur", Vector3.new(0, 2.289, 0), Color3.fromRGB(250, 247, 242), Enum.Material.Fabric },
			{ "Boots", Vector3.new(0, 0.26, 0), Color3.fromRGB(23, 22, 26), Enum.Material.SmoothPlastic },
			{ "Belt", Vector3.new(0, 1.725, -0.068), Color3.fromRGB(26, 23, 28), Enum.Material.SmoothPlastic },
			{ "Buckle", Vector3.new(0, 1.725, -2.137), Color3.fromRGB(242, 191, 61), Enum.Material.Metal },
			{ "Holly", Vector3.new(1.043, 2.889, -1.613), Color3.fromRGB(33, 133, 61), Enum.Material.SmoothPlastic },
			{ "Berries", Vector3.new(0.969, 2.745, -1.744), Color3.fromRGB(224, 26, 38), Enum.Material.SmoothPlastic },
		},
	},
	Reaper = {
		cuff = Color3.fromRGB(31, 26, 38),
		hood = true,
		fx = "wisps",
		parts = {
			{ "Cloak", Vector3.new(0.03, 1.942, 0.004), Color3.fromRGB(31, 26, 38), Enum.Material.Fabric },
			{ "Mantle", Vector3.new(-0.021, 3.065, 0.015), Color3.fromRGB(48, 41, 59), Enum.Material.Fabric },
			{ "Hood", Vector3.new(0, 5.532, 0.343), Color3.fromRGB(38, 33, 48), Enum.Material.Fabric },
			{ "HoodLining", Vector3.new(0, 5.511, 0.326), Color3.fromRGB(9, 6, 13), Enum.Material.Fabric },
			{ "Rope", Vector3.new(0, 1.42, -0.057), Color3.fromRGB(107, 92, 71), Enum.Material.Fabric },
			{ "Skull", Vector3.new(0, 3.47, -1.86), Color3.fromRGB(232, 224, 204), Enum.Material.SmoothPlastic },
			{ "SoulGlow", Vector3.new(0, 3.415, -2.098), Color3.fromRGB(178, 92, 255), Enum.Material.Neon },
			{ "Chain", Vector3.new(0, 3.512, -1.463), Color3.fromRGB(82, 79, 89), Enum.Material.Metal },
		},
	},
	Snowman = {
		cuff = Color3.fromRGB(41, 143, 214),
		parts = {
			{ "Snow", Vector3.new(-0.038, 1.93, -0.019), Color3.fromRGB(242, 247, 252), Enum.Material.Snow },
			{ "Coal", Vector3.new(0.01, 2.14, -1.83), Color3.fromRGB(36, 33, 38), Enum.Material.Slate },
			{ "Scarf", Vector3.new(0, 2.952, -0.14), Color3.fromRGB(41, 143, 214), Enum.Material.Fabric },
			{ "ScarfStripe", Vector3.new(0, 2.952, -0.142), Color3.fromRGB(247, 247, 247), Enum.Material.Fabric },
			{ "Twigs", Vector3.new(0, 3.611, -0.132), Color3.fromRGB(97, 66, 41), Enum.Material.Wood },
		},
	},
	-- Build 40 first-full-match reward (assets/outfits/outfits4.py, out_b40n): the Nova Armor.
	Nova = {
		cuff = NOVA_GUN,
		fx = "nova",
		parts = {
			{ "Suit", Vector3.new(0, 2.115, -0.0318), NOVA_GRAPH, Enum.Material.SmoothPlastic },
			{ "Plates", Vector3.new(0, 2.48, 0), NOVA_GUN, Enum.Material.Metal },
			{ "Glow", Vector3.new(0, 1.9156, 0), NOVA_CYAN, Enum.Material.Neon },
			{ "Core", Vector3.new(0, 2.5188, -0.337), NOVA_MAG, Enum.Material.Neon },
			{ "Boots", Vector3.new(0, 0.26, 0), NOVA_GUN, Enum.Material.Metal },
		},
	},
	-- Build 31 (assets/outfits/outfits2.py): goes with the Chef Hat.
	Chef = {
		cuff = Color3.fromRGB(247, 247, 242),
		parts = {
			{ "Coat", Vector3.new(0, 2.45, 0), Color3.fromRGB(247, 247, 242), Enum.Material.SmoothPlastic },
			{ "Placket", Vector3.new(-0.1288, 2.35, -1.66), Color3.fromRGB(237, 237, 232), Enum.Material.SmoothPlastic },
			{ "Collar", Vector3.new(0, 3.57, 0), Color3.fromRGB(247, 247, 242), Enum.Material.SmoothPlastic },
			{ "Buttons", Vector3.new(-0.2185, 2.41, -1.7967), Color3.fromRGB(36, 36, 41), Enum.Material.SmoothPlastic },
			{ "Neckerchief", Vector3.new(0, 3.043, -0.182), Color3.fromRGB(219, 33, 38), Enum.Material.Fabric },
			{ "CheckDark", Vector3.new(0, 0.83, 0), Color3.fromRGB(31, 31, 36), Enum.Material.Fabric },
			{ "CheckLight", Vector3.new(0, 0.83, 0), Color3.fromRGB(230, 230, 224), Enum.Material.Fabric },
			{ "Clogs", Vector3.new(0, 0.23, 0), Color3.fromRGB(26, 26, 31), Enum.Material.SmoothPlastic },
			{ "Pen", Vector3.new(-1.2414, 3.03, -1.5086), Color3.fromRGB(51, 107, 217), Enum.Material.SmoothPlastic },
		},
	},
	Galaxy = {
		cuff = Color3.fromRGB(60, 34, 120),
		fx = "stars",
		parts = {
			{ "Cosmos", Vector3.new(0, 1.95, 0), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, 0.3 },
			{ "CosmosCore", Vector3.new(0, 1.931, 0), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic },
			{ "Aura", Vector3.new(0, 2.04, 0), Color3.fromRGB(158, 115, 255), Enum.Material.ForceField },
			-- The orbit ring, planet and moon are left out: seen side-on the tilted ring and the
			-- planet on it read as a wizard's staff in the skater's hand.
		},
	},
}

-- Build 34: Mystery Box outfits, the season outfits' meshes in new colours.
OUTFITS.ShadowReaper = {
	mesh = "Reaper",
	cuff = Color3.fromRGB(22, 16, 24),
	hood = true,
	fx = "wisps",
	parts = {
		{ "Cloak", Vector3.new(0.03, 1.942, 0.004), Color3.fromRGB(22, 16, 24), Enum.Material.Fabric },
		{ "Mantle", Vector3.new(-0.021, 3.065, 0.015), Color3.fromRGB(110, 18, 26), Enum.Material.Fabric },
		{ "Hood", Vector3.new(0, 5.532, 0.343), Color3.fromRGB(30, 22, 32), Enum.Material.Fabric },
		{ "HoodLining", Vector3.new(0, 5.511, 0.326), Color3.fromRGB(8, 4, 8), Enum.Material.Fabric },
		{ "Rope", Vector3.new(0, 1.42, -0.057), Color3.fromRGB(150, 24, 32), Enum.Material.Fabric },
		{ "Skull", Vector3.new(0, 3.47, -1.86), Color3.fromRGB(40, 36, 44), Enum.Material.SmoothPlastic },
		{ "SoulGlow", Vector3.new(0, 3.415, -2.098), Color3.fromRGB(255, 40, 40), Enum.Material.Neon },
		{ "Chain", Vector3.new(0, 3.512, -1.463), Color3.fromRGB(150, 150, 160), Enum.Material.Metal },
	},
}
OUTFITS.GoldenSuit = {
	mesh = "Santa",
	cuff = Color3.fromRGB(250, 247, 242),
	parts = {
		{ "Coat", Vector3.new(0, 2.3, -0.006), Color3.fromRGB(240, 186, 40), Enum.Material.Metal },
		{ "Trousers", Vector3.new(0, 0.63, 0), Color3.fromRGB(34, 32, 40), Enum.Material.Fabric },
		{ "Fur", Vector3.new(0, 2.289, 0), Color3.fromRGB(250, 247, 242), Enum.Material.Fabric },
		{ "Boots", Vector3.new(0, 0.26, 0), Color3.fromRGB(23, 22, 26), Enum.Material.SmoothPlastic },
		{ "Belt", Vector3.new(0, 1.725, -0.068), Color3.fromRGB(26, 23, 28), Enum.Material.SmoothPlastic },
		{ "Buckle", Vector3.new(0, 1.725, -2.137), Color3.fromRGB(250, 250, 255), Enum.Material.Metal },
		{ "Holly", Vector3.new(1.043, 2.889, -1.613), Color3.fromRGB(40, 40, 48), Enum.Material.SmoothPlastic },
		{ "Berries", Vector3.new(0.969, 2.745, -1.744), Color3.fromRGB(80, 200, 255), Enum.Material.Neon },
	},
}
OUTFITS.SlimeSnowman = {
	mesh = "Snowman",
	cuff = Color3.fromRGB(150, 60, 220),
	parts = {
		{ "Snow", Vector3.new(-0.038, 1.93, -0.019), Color3.fromRGB(130, 240, 90), Enum.Material.SmoothPlastic },
		{ "Coal", Vector3.new(0.01, 2.14, -1.83), Color3.fromRGB(36, 33, 38), Enum.Material.Slate },
		{ "Scarf", Vector3.new(0, 2.952, -0.14), Color3.fromRGB(150, 60, 220), Enum.Material.Fabric },
		{ "ScarfStripe", Vector3.new(0, 2.952, -0.142), Color3.fromRGB(255, 220, 60), Enum.Material.Fabric },
		{ "Twigs", Vector3.new(0, 3.611, -0.132), Color3.fromRGB(70, 46, 30), Enum.Material.Wood },
	},
}

local function outfitTemplates(style: string): Instance?
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("OutfitMeshes")
	local outfit = OUTFITS[style]
	return folder and folder:FindFirstChild(if outfit and outfit.mesh then outfit.mesh else style)
end

-- Particle effects ride on an invisible part in the body, so they move with the skater.
local function outfitFx(model: Model, fx: string?): (Part?, CFrame?)
	if fx == "stars" then
		-- Stars twinkling deep inside the see-through sky shell.
		local p = part(model, "StarField", Vector3.new(2.4, 3.0, 2.4), WHITE)
		p.Transparency = 1
		p.CastShadow = false
		local e = Instance.new("ParticleEmitter")
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.Rate = 26
		e.Lifetime = NumberRange.new(1.2, 2.4)
		e.Speed = NumberRange.new(0)
		e.LockedToPart = true
		e.LightEmission = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.24), NumberSequenceKeypoint.new(1, 0) })
		e.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 190, 245)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 230, 255)),
		})
		e.Parent = p
		return p, CFrame.new(0, 1.95, 0)
	elseif fx == "wisps" then
		-- Ghostly wisps curling up off the ragged hem and trailing behind on the ice.
		local p = part(model, "Wisps", Vector3.new(4.2, 0.3, 4.2), WHITE)
		p.Transparency = 1
		p.CastShadow = false
		local e = Instance.new("ParticleEmitter")
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.EmissionDirection = Enum.NormalId.Top
		e.Rate = 9
		e.Lifetime = NumberRange.new(1.4, 2.4)
		e.Speed = NumberRange.new(0.6, 1.3)
		e.Drag = 1
		e.LightEmission = 0.7
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		e.Color = ColorSequence.new(Color3.fromRGB(176, 110, 255), Color3.fromRGB(90, 230, 210))
		e.Parent = p
		return p, CFrame.new(0, 0.35, 0)
	elseif fx == "nova" then
		-- Build 40 (Nova Armor): cyan-to-magenta energy motes rising off the hover ring.
		local p = part(model, "NovaMotes", Vector3.new(4.3, 0.12, 4.3), WHITE)
		p.Transparency = 1
		p.CastShadow = false
		local e = Instance.new("ParticleEmitter")
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		e.EmissionDirection = Enum.NormalId.Top
		e.Rate = 16
		e.Lifetime = NumberRange.new(0.6, 1.1)
		e.Speed = NumberRange.new(1.4, 2.6)
		e.Drag = 1.6
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.16), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.6) })
		e.Color = ColorSequence.new(NOVA_CYAN, NOVA_MAG)
		e.Parent = p
		return p, CFrame.new(0, 0.1, 0)
	end
	return nil, nil
end

---------------------------------------------------------------------------------------------
-- Back bling: modelled pieces worn on the back (assets/backbling, meshes kept as MeshPart
-- templates in ReplicatedStorage.BackMeshes.<Style>). Each row: the region mesh, where its
-- bounding-box centre sits in the body frame, its colour, material and transparency.
---------------------------------------------------------------------------------------------
type Back = { parts: { any }, fx: string? }
local BACKS: { [string]: Back } = {
	-- BACKS_START (rows written from assets/backbling/out/backbling_info.json)
	HockeyBag = {
		fx = nil,
		parts = {
			{ "Bag", Vector3.new(0, 2.72, 2.42), Color3.fromRGB(34, 58, 128), Enum.Material.SmoothPlastic },
			{ "BagEnds", Vector3.new(0, 2.72, 2.42), Color3.fromRGB(210, 45, 50), Enum.Material.SmoothPlastic },
			{ "Straps", Vector3.new(0, 3.2347, 0.4608), Color3.fromRGB(35, 35, 42), Enum.Material.SmoothPlastic },
			{ "Zip", Vector3.new(-0.2186, 3.6763, 2.7394), Color3.fromRGB(236, 236, 240), Enum.Material.SmoothPlastic },
			{ "Patch", Vector3.new(0, 2.72, 3.05), Color3.fromRGB(255, 196, 50), Enum.Material.SmoothPlastic },
			{ "StickShaft", Vector3.new(-1.175, 3.8, 2.46), Color3.fromRGB(196, 150, 96), Enum.Material.Wood },
			{ "StickBlade", Vector3.new(-2.1115, 5.2549, 2.505), Color3.fromRGB(36, 36, 42), Enum.Material.SmoothPlastic },
		},
	},
	IceWings = {
		fx = "frost",
		parts = {
			{ "Shards", Vector3.new(0, 4.0541, 2.4947), Color3.fromRGB(176, 226, 255), Enum.Material.Glass, 0.25 },
			{ "ShardCore", Vector3.new(0, 3.8312, 2.4109), Color3.fromRGB(130, 210, 255), Enum.Material.Neon },
			{ "Mount", Vector3.new(0, 2.9, 1.99), Color3.fromRGB(210, 220, 235), Enum.Material.Metal },
			{ "Gem", Vector3.new(0, 2.9, 2.25), Color3.fromRGB(90, 200, 255), Enum.Material.Neon },
			{ "Straps", Vector3.new(0, 3.1926, 0.2854), Color3.fromRGB(60, 92, 140), Enum.Material.SmoothPlastic },
		},
	},
	Jetpack = {
		fx = "flames",
		parts = {
			{ "Tanks", Vector3.new(0, 2.37, 2.38), Color3.fromRGB(226, 64, 48), Enum.Material.SmoothPlastic },
			{ "TankCaps", Vector3.new(0, 3.66, 2.38), Color3.fromRGB(205, 210, 220), Enum.Material.Metal },
			{ "Nozzles", Vector3.new(0, 1.21, 2.38), Color3.fromRGB(70, 72, 80), Enum.Material.Metal },
			{ "NozzleGlow", Vector3.new(0, 1.1, 2.38), Color3.fromRGB(255, 150, 40), Enum.Material.Neon },
			{ "Frame", Vector3.new(0, 2.55, 1.9506), Color3.fromRGB(110, 116, 128), Enum.Material.Metal },
			{ "Stripes", Vector3.new(0, 2.825, 2.38), Color3.fromRGB(245, 245, 245), Enum.Material.SmoothPlastic },
			{ "Fins", Vector3.new(0, 1.625, 2.7975), Color3.fromRGB(255, 196, 40), Enum.Material.SmoothPlastic },
			{ "Straps", Vector3.new(0, 3.2318, 0.1046), Color3.fromRGB(40, 40, 46), Enum.Material.SmoothPlastic },
			{ "Lights", Vector3.new(0, 2.62, 2.05), Color3.fromRGB(80, 255, 120), Enum.Material.Neon },
		},
	},
	PuckPack = {
		fx = nil,
		parts = {
			{ "Puck", Vector3.new(0, 2.55, 2.13), Color3.fromRGB(32, 32, 38), Enum.Material.SmoothPlastic },
			{ "Grip", Vector3.new(0, 2.55, 2.13), Color3.fromRGB(74, 76, 86), Enum.Material.SmoothPlastic },
			{ "Logo", Vector3.new(0, 2.55, 2.43), Color3.fromRGB(255, 140, 40), Enum.Material.SmoothPlastic },
			{ "Zip", Vector3.new(0, 2.55, 2.4325), Color3.fromRGB(205, 210, 220), Enum.Material.Metal },
			{ "Straps", Vector3.new(0, 3.2347, 0.1885), Color3.fromRGB(40, 40, 46), Enum.Material.SmoothPlastic },
		},
	},
	MiniNet = {
		fx = nil,
		parts = {
			{ "Frame", Vector3.new(0, 2.5025, 2.72), Color3.fromRGB(220, 40, 44), Enum.Material.SmoothPlastic },
			{ "Base", Vector3.new(0, 1.72, 2.3125), Color3.fromRGB(245, 245, 250), Enum.Material.SmoothPlastic },
			{ "Net", Vector3.new(0, 2.4706, 2.342), Color3.fromRGB(236, 238, 244), Enum.Material.SmoothPlastic },
			{ "Puck", Vector3.new(0.38, 2.12, 2.11), Color3.fromRGB(28, 28, 32), Enum.Material.SmoothPlastic },
			{ "Straps", Vector3.new(0, 3.2347, 0.2487), Color3.fromRGB(40, 40, 46), Enum.Material.SmoothPlastic },
		},
	},
	Snowboard = {
		fx = nil,
		parts = {
			{ "Deck", Vector3.new(0, 3, 2.1559), Color3.fromRGB(40, 182, 222), Enum.Material.SmoothPlastic },
			{ "Base", Vector3.new(0, 3, 2.1084), Color3.fromRGB(30, 32, 42), Enum.Material.SmoothPlastic },
			{ "Graphic", Vector3.new(0, 3, 2.0405), Color3.fromRGB(255, 92, 150), Enum.Material.SmoothPlastic },
			{ "Bindings", Vector3.new(0, 2.9898, 2.203), Color3.fromRGB(46, 48, 56), Enum.Material.SmoothPlastic },
			{ "Buckles", Vector3.new(0.0787, 3.1054, 2.165), Color3.fromRGB(255, 210, 60), Enum.Material.SmoothPlastic },
			{ "Straps", Vector3.new(0, 3.2347, 0.239), Color3.fromRGB(40, 40, 46), Enum.Material.SmoothPlastic },
		},
	},
	PenguinPal = {
		fx = nil,
		parts = {
			{ "Body", Vector3.new(0, 2.705, 2.42), Color3.fromRGB(36, 40, 56), Enum.Material.SmoothPlastic },
			{ "Belly", Vector3.new(0, 2.67, 2.72), Color3.fromRGB(246, 246, 250), Enum.Material.SmoothPlastic },
			{ "Beak", Vector3.new(0, 2.4493, 2.8512), Color3.fromRGB(255, 154, 40), Enum.Material.SmoothPlastic },
			{ "Eyes", Vector3.new(0, 3.4, 2.95), Color3.fromRGB(22, 22, 28), Enum.Material.SmoothPlastic },
			{ "Glint", Vector3.new(0.03, 3.44, 3.005), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic },
			{ "Scarf", Vector3.new(0, 2.7619, 2.4697), Color3.fromRGB(226, 52, 64), Enum.Material.SmoothPlastic },
			{ "Straps", Vector3.new(0, 3.2347, 0.2293), Color3.fromRGB(40, 40, 46), Enum.Material.SmoothPlastic },
		},
	},
	ChampCup = {
		fx = "sparkle",
		parts = {
			{ "Cup", Vector3.new(0, 2.69, 2.72), Color3.fromRGB(214, 220, 230), Enum.Material.Metal },
			{ "Gold", Vector3.new(0, 2.5802, 2.72), Color3.fromRGB(255, 200, 60), Enum.Material.Metal },
			{ "Base", Vector3.new(0, 1.615, 2.72), Color3.fromRGB(96, 62, 40), Enum.Material.Wood },
			{ "Harness", Vector3.new(0, 2.8597, 1.0108), Color3.fromRGB(70, 46, 32), Enum.Material.SmoothPlastic },
		},
	},
	-- Build 25 shop back bling (assets/backbling/backbling2.py, out_b25).
	CocoaMug = {
		fx = nil,
		parts = {
			{ "Mug", Vector3.new(0.23, 2.51, 2.72), Color3.fromRGB(206, 44, 52), Enum.Material.SmoothPlastic },
			{ "Band", Vector3.new(0, 2.72, 2.7275), Color3.fromRGB(246, 246, 250), Enum.Material.SmoothPlastic },
			{ "Cocoa", Vector3.new(0, 3.06, 2.72), Color3.fromRGB(96, 56, 36), Enum.Material.SmoothPlastic },
			{ "Mallows", Vector3.new(-0.0078, 3.2226, 2.7653), Color3.fromRGB(252, 246, 240), Enum.Material.SmoothPlastic },
			{ "Straps", Vector3.new(0, 3.2347, 1.0958), Color3.fromRGB(40, 40, 46), Enum.Material.SmoothPlastic },
		},
	},
	SkatePair = {
		fx = nil,
		parts = {
			{ "Boots", Vector3.new(0, 2.42, 2.3343), Color3.fromRGB(30, 30, 36), Enum.Material.SmoothPlastic },
			{ "Cuffs", Vector3.new(0, 2.87, 2.2843), Color3.fromRGB(40, 110, 220), Enum.Material.SmoothPlastic },
			{ "Holders", Vector3.new(0, 1.82, 2.32), Color3.fromRGB(244, 244, 248), Enum.Material.SmoothPlastic },
			{ "Runners", Vector3.new(0, 1.64, 2.3236), Color3.fromRGB(200, 206, 216), Enum.Material.Metal },
			{ "Laces", Vector3.new(0.0019, 2.7763, 2.309), Color3.fromRGB(250, 250, 252), Enum.Material.SmoothPlastic },
			{ "Straps", Vector3.new(0, 3.2347, 0.3608), Color3.fromRGB(40, 40, 46), Enum.Material.SmoothPlastic },
		},
	},
	MiniScoreboard = {
		fx = nil,
		parts = {
			{ "Case", Vector3.new(0, 2.72, 2.235), Color3.fromRGB(34, 36, 44), Enum.Material.SmoothPlastic },
			{ "Screens", Vector3.new(0, 2.66, 2.53), Color3.fromRGB(10, 10, 14), Enum.Material.SmoothPlastic },
			{ "Digits", Vector3.new(0.0162, 2.66, 2.5475), Color3.fromRGB(255, 196, 40), Enum.Material.Neon },
			{ "TeamBars", Vector3.new(-0.48, 3.11, 2.53), Color3.fromRGB(220, 50, 56), Enum.Material.SmoothPlastic },
			{ "TeamBars2", Vector3.new(0.48, 3.11, 2.53), Color3.fromRGB(50, 110, 220), Enum.Material.SmoothPlastic },
			{ "Trim", Vector3.new(0, 2.7727, 2.2775), Color3.fromRGB(200, 206, 216), Enum.Material.Metal },
			{ "Lamp", Vector3.new(0, 3.59, 2.235), Color3.fromRGB(255, 40, 40), Enum.Material.Neon },
			{ "Straps", Vector3.new(0, 3.2347, 0.239), Color3.fromRGB(40, 40, 46), Enum.Material.SmoothPlastic },
		},
	},
	-- Build 26 shop back bling (assets/backbling/backbling3.py, out_b26).
	Resurfacer = {
		fx = nil,
		parts = {
			{ "Body", Vector3.new(0, 2.575, 2.72), Color3.fromRGB(244, 246, 250), Enum.Material.SmoothPlastic },
			{ "Trim", Vector3.new(0.13, 2.67, 2.72), Color3.fromRGB(36, 96, 206), Enum.Material.SmoothPlastic },
			{ "Wheels", Vector3.new(0, 1.92, 2.72), Color3.fromRGB(30, 30, 36), Enum.Material.SmoothPlastic },
			{ "Seat", Vector3.new(0.273, 3.1623, 2.72), Color3.fromRGB(46, 48, 58), Enum.Material.SmoothPlastic },
			{ "Lamp", Vector3.new(-0.75, 3.62, 3.07), Color3.fromRGB(255, 170, 40), Enum.Material.Neon },
			{ "Straps", Vector3.new(0, 3.2347, 0.239), Color3.fromRGB(40, 40, 46), Enum.Material.SmoothPlastic },
		},
	},
	SnowPal = {
		fx = nil,
		parts = {
			{ "Snow", Vector3.new(0.0246, 2.6894, 2.62), Color3.fromRGB(246, 250, 255), Enum.Material.SmoothPlastic },
			{ "Coal", Vector3.new(0.06, 3.15, 2.8392), Color3.fromRGB(30, 30, 36), Enum.Material.SmoothPlastic },
			{ "Carrot", Vector3.new(0, 3.35, 3.4162), Color3.fromRGB(255, 128, 30), Enum.Material.SmoothPlastic },
			{ "Scarf", Vector3.new(0.0319, 3.2121, 2.62), Color3.fromRGB(214, 40, 52), Enum.Material.SmoothPlastic },
			{ "Twigs", Vector3.new(-0.0002, 2.9577, 2.6701), Color3.fromRGB(110, 72, 40), Enum.Material.SmoothPlastic },
			{ "Straps", Vector3.new(0, 3.2347, 0.239), Color3.fromRGB(40, 40, 46), Enum.Material.SmoothPlastic },
		},
	},
	-- Build 40 first-full-match reward (assets/backbling/backbling5.py, out_b40n): the Nova
	-- Reactor. The core, its shell and both rings float, bob and spin (BACK_ANIM).
	NovaReactor = {
		fx = "reactor",
		parts = {
			{ "Housing", Vector3.new(0, 2.8, 1.675), NOVA_GRAPH, Enum.Material.Metal },
			{ "HousingTrim", Vector3.new(0, 2.8, 2.17), NOVA_GUN, Enum.Material.Metal },
			{ "Plate", Vector3.new(0, 2.8, 2.04), NOVA_GRAPH, Enum.Material.SmoothPlastic },
			{ "PlateGlow", Vector3.new(0, 2.8, 1.8175), NOVA_CYAN, Enum.Material.Neon },
			{ "EmitterGlow", Vector3.new(0, 2.8, 2.18), NOVA_MAG, Enum.Material.Neon },
			{ "Core", Vector3.new(0, 2.8, 3.0), NOVA_MAG, Enum.Material.Neon },
			{ "CoreShell", Vector3.new(0, 2.8, 3.0), NOVA_CYAN, Enum.Material.ForceField },
			{ "RingA", Vector3.new(0, 2.8, 3.0), NOVA_GUN, Enum.Material.Metal },
			{ "RingAGlow", Vector3.new(0, 2.8, 3.0), NOVA_CYAN, Enum.Material.Neon },
			{ "RingB", Vector3.new(0, 2.8, 3.0), NOVA_GUN, Enum.Material.Metal },
			{ "RingBGlow", Vector3.new(0, 2.8, 3.0), NOVA_MAG, Enum.Material.Neon },
			{ "Straps", Vector3.new(0, 3.2612, 0.1314), NOVA_GRAPH, Enum.Material.SmoothPlastic },
		},
	},
	-- BACKS_END
}

local function backTemplates(style: string): Instance?
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("BackMeshes")
	return folder and folder:FindFirstChild(style)
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

-- Effects on a back bling: jetpack flames under the two nozzles, frost drifting off the wings.
-- `at` is where each effect part sits in the body frame (BACK_FX, from the model's info).
local BACK_FX: { [string]: { Vector3 } } = {
	-- BACKFX_START
	IceWings = { Vector3.new(-1.75, 3.95, 2.5), Vector3.new(1.75, 3.95, 2.5) },
	Jetpack = { Vector3.new(-0.64, 0.82, 2.38), Vector3.new(0.64, 0.82, 2.38) },
	ChampCup = { Vector3.new(0, 3.3, 2.72) },
	NovaReactor = { Vector3.new(0, 2.8, 3.0) },
	-- BACKFX_END
}
local function backFx(model: Model, style: string, fx: string?): { { part: Part, at: CFrame } }
	local out = {}
	local spots = BACK_FX[style] or {}
	if fx == "flames" then
		for _, at in spots do
			local p = part(model, "JetFlame", Vector3.new(0.5, 0.2, 0.5), WHITE)
			p.Transparency = 1
			p.CastShadow = false
			emitter(p, {
				EmissionDirection = Enum.NormalId.Bottom,
				Rate = 40,
				Lifetime = NumberRange.new(0.16, 0.3),
				Speed = NumberRange.new(5, 8),
				SpreadAngle = Vector2.new(8, 8),
				LightEmission = 1,
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.42), NumberSequenceKeypoint.new(1, 0.05) }),
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 200)),
					ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 160, 40)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 20)),
				}),
				Transparency = NumberSequence.new(0.1, 1),
			})
			table.insert(out, { part = p, at = CFrame.new(at) })
		end
	elseif fx == "frost" then
		for _, at in spots do
			local p = part(model, "WingFrost", Vector3.new(2.6, 2.2, 0.5), WHITE)
			p.Transparency = 1
			p.CastShadow = false
			emitter(p, {
				Shape = Enum.ParticleEmitterShape.Box,
				ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
				Rate = 6,
				Lifetime = NumberRange.new(0.8, 1.6),
				Speed = NumberRange.new(0.2, 0.6),
				Acceleration = Vector3.new(0, -1.5, 0),
				LightEmission = 0.8,
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.16), NumberSequenceKeypoint.new(1, 0) }),
				Color = ColorSequence.new(Color3.fromRGB(230, 248, 255), Color3.fromRGB(150, 215, 255)),
			})
			table.insert(out, { part = p, at = CFrame.new(at) })
		end
	elseif fx == "sparkle" then
		-- A few gold glints twinkling round the cup's bowl.
		for _, at in spots do
			local p = part(model, "CupSparkle", Vector3.new(1.8, 1.4, 1.8), WHITE)
			p.Transparency = 1
			p.CastShadow = false
			emitter(p, {
				Shape = Enum.ParticleEmitterShape.Box,
				ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
				Rate = 5,
				Lifetime = NumberRange.new(0.4, 0.7),
				Speed = NumberRange.new(0, 0.2),
				Rotation = NumberRange.new(0, 90),
				LightEmission = 1,
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.28), NumberSequenceKeypoint.new(1, 0) }),
				Color = ColorSequence.new(Color3.fromRGB(255, 250, 220), Color3.fromRGB(255, 210, 90)),
			})
			table.insert(out, { part = p, at = CFrame.new(at) })
		end
	elseif fx == "reactor" then
		-- Build 40 (Nova Reactor): sparks spitting off the floating core, and its magenta glow.
		for _, at in spots do
			local p = part(model, "ReactorSparks", Vector3.new(0.5, 0.5, 0.5), WHITE)
			p.Transparency = 1
			p.CastShadow = false
			emitter(p, {
				Rate = 14,
				Lifetime = NumberRange.new(0.35, 0.7),
				Speed = NumberRange.new(1.2, 2.6),
				SpreadAngle = Vector2.new(180, 180),
				Drag = 3,
				LightEmission = 1,
				LightInfluence = 0,
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.14), NumberSequenceKeypoint.new(1, 0) }),
				Color = ColorSequence.new(NOVA_MAG_HOT, NOVA_CYAN),
			})
			local light = Instance.new("PointLight")
			light.Color = NOVA_MAG
			light.Range = 7
			light.Brightness = 1.2
			light.Shadows = false
			light.Parent = p
			table.insert(out, { part = p, at = CFrame.new(at) })
		end
	end
	return out
end

---------------------------------------------------------------------------------------------
-- Skins (the "finish" slot): one treatment over the whole body, whatever the outfit.
---------------------------------------------------------------------------------------------
local FROST = Color3.fromRGB(176, 226, 255)
local GOLD_CHROME = Color3.fromRGB(255, 192, 52)

local function luminance(c: Color3): number
	return c.R * 0.3 + c.G * 0.59 + c.B * 0.11
end

local function applyFinish(style: string?, p: BasePart)
	if style == "Frost" then
		-- Clear blue ice: the outfit's light and dark parts show through as paler and deeper ice.
		local l = luminance(p.Color)
		p.Color = FROST:Lerp(Color3.fromRGB(64, 140, 214), math.clamp(0.75 - l, 0, 0.75))
		p.Material = Enum.Material.Glass
		p.Transparency = math.max(p.Transparency, 0.12)
		p.Reflectance = 0.1
	elseif style == "GoldChrome" then
		-- Polished gold; darker parts of the outfit become deeper gold, so the design still reads.
		local l = luminance(p.Color)
		p.Color = GOLD_CHROME:Lerp(Color3.fromRGB(150, 92, 16), math.clamp(0.7 - l, 0, 0.7))
		p.Material = Enum.Material.Metal
		p.Reflectance = 0.32
	end
end

local function finishFx(model: Model, style: string?): Part?
	if style ~= "Frost" and style ~= "GoldChrome" then
		return nil
	end
	local p = part(model, "FinishSparkle", Vector3.new(3.6, 3.8, 3.6), WHITE)
	p.Transparency = 1
	p.CastShadow = false
	emitter(p, {
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Rate = if style == "Frost" then 9 else 6,
		Lifetime = NumberRange.new(0.5, 1.0),
		Speed = NumberRange.new(0),
		LockedToPart = true,
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, if style == "Frost" then 0.22 else 0.28), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(if style == "Frost" then Color3.fromRGB(235, 250, 255) else Color3.fromRGB(255, 246, 200)),
	})
	return p
end

---------------------------------------------------------------------------------------------
-- Body types: how much bigger the body is across (x, z) and up (y). Looks only; the hitbox is
-- always the sim's.
---------------------------------------------------------------------------------------------
local BUILDS: { [string]: { across: number, up: number, pads: boolean } } = {
	Bruiser = { across = 1.24, up = 1.1, pads = true },
}

-- Scales one part by world-axis factors (across for x and z, up for y), whatever way it is
-- turned in the body frame, and moves its offset to match.
local function scaleBody(p: BasePart, offset: CFrame, across: number, up: number): CFrame
	local r = offset.Rotation
	local function factor(axis: Vector3): number
		local y = math.abs(r:VectorToWorldSpace(axis).Y)
		return up * y + across * (1 - y)
	end
	p.Size = Vector3.new(p.Size.X * factor(Vector3.xAxis), p.Size.Y * factor(Vector3.yAxis), p.Size.Z * factor(Vector3.zAxis))
	local pos = offset.Position
	return CFrame.new(pos.X * across, pos.Y * up, pos.Z * across) * r
end

-- Dresses a puck part in a puck style (the Snowflake, Lava and Galaxy pass pucks), or back to
-- the plain game puck in `plain`. Its extra pieces are children named PuckStyle, replaced on
-- every change. The puck is a cylinder lying flat: its x axis is up.
function Looks.dressPuck(puck: BasePart, style: string?, plain: Color3)
	for _, child in puck:GetChildren() do
		if child.Name == "PuckStyle" then
			child:Destroy()
		end
	end
	puck.Material = Enum.Material.SmoothPlastic
	puck.Reflectance = 0
	puck.Color = plain
	local d = puck.Size.Y
	local function plates(scale: number, thick: number, color: Color3, material: Enum.Material)
		-- A disc on each flat face, welded so it rides with the puck.
		for _, side in { -1, 1 } do
			local plate = Instance.new("Part")
			plate.Name = "PuckStyle"
			plate.Shape = Enum.PartType.Cylinder
			plate.Size = Vector3.new(thick, d * scale, d * scale)
			plate.Color = color
			plate.Material = material
			plate.CanCollide, plate.CanTouch, plate.CanQuery = false, false, false
			plate.Anchored = false
			plate.Massless = true
			plate.CastShadow = false
			plate.CFrame = puck.CFrame * CFrame.new(side * (puck.Size.X / 2 + thick / 2 - 0.005), 0, 0)
			-- Welded, so it follows the puck when the puck (anchored) is moved by its CFrame.
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = puck, plate
			weld.Parent = plate
			plate.Parent = puck
		end
	end
	local function sparkle(props: { [string]: any })
		local a = Instance.new("Attachment")
		a.Name = "PuckStyle"
		a.Parent = puck
		emitter(a, props)
	end
	if style == "Snowflake" then
		puck.Color = Color3.fromRGB(236, 246, 255)
		puck.Material = Enum.Material.Ice
		plates(0.66, 0.03, Color3.fromRGB(120, 196, 255), Enum.Material.Neon)
		plates(0.34, 0.05, Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic)
		sparkle({
			Rate = 14,
			Lifetime = NumberRange.new(0.4, 0.8),
			Speed = NumberRange.new(0.5, 1.5),
			SpreadAngle = Vector2.new(180, 180),
			LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.16), NumberSequenceKeypoint.new(1, 0) }),
			Color = ColorSequence.new(Color3.fromRGB(220, 244, 255)),
		})
	elseif style == "Lava" then
		puck.Color = Color3.fromRGB(44, 30, 28)
		puck.Material = Enum.Material.Basalt
		plates(0.8, 0.03, Color3.fromRGB(255, 110, 20), Enum.Material.Neon)
		plates(0.5, 0.05, Color3.fromRGB(52, 34, 30), Enum.Material.Basalt)
		sparkle({
			Rate = 18,
			Lifetime = NumberRange.new(0.3, 0.6),
			Speed = NumberRange.new(1, 3),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, 6, 0),
			LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0) }),
			Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 70, 20)),
		})
		local light = Instance.new("PointLight")
		light.Name = "PuckStyle"
		light.Color = Color3.fromRGB(255, 120, 40)
		light.Range = 7
		light.Brightness = 1.5
		light.Parent = puck
	elseif style == "Gold" then
		-- Build 34 (Mystery Box): polished gold with white-gold faces and a slow glint.
		puck.Color = Color3.fromRGB(255, 196, 46)
		puck.Material = Enum.Material.Metal
		puck.Reflectance = 0.15
		plates(0.72, 0.03, Color3.fromRGB(255, 236, 160), Enum.Material.Metal)
		plates(0.4, 0.05, Color3.fromRGB(255, 200, 60), Enum.Material.Neon)
		sparkle({
			Rate = 6,
			Lifetime = NumberRange.new(0.4, 0.7),
			Speed = NumberRange.new(0),
			SpreadAngle = Vector2.new(180, 180),
			LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 0) }),
			Color = ColorSequence.new(Color3.fromRGB(255, 250, 220)),
		})
	elseif style == "Toxic" then
		-- Build 34 (Mystery Box): black with glowing green faces and rising bubbles.
		puck.Color = Color3.fromRGB(30, 34, 30)
		plates(0.82, 0.03, Color3.fromRGB(120, 255, 60), Enum.Material.Neon)
		plates(0.46, 0.05, Color3.fromRGB(26, 30, 26), Enum.Material.SmoothPlastic)
		sparkle({
			Rate = 14,
			Lifetime = NumberRange.new(0.4, 0.8),
			Speed = NumberRange.new(0.6, 1.6),
			SpreadAngle = Vector2.new(30, 30),
			Acceleration = Vector3.new(0, 4, 0),
			LightEmission = 0.6,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0.24) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
			Color = ColorSequence.new(Color3.fromRGB(150, 255, 90)),
		})
	elseif style == "Galaxy" then
		-- The same window onto space as the Galaxy Body: its nebula image painted over the whole
		-- puck (decals project onto the cylinder, so the faces show it as round), inside a faint
		-- force-field aura, with stars twinkling round it.
		puck.Color = Color3.fromRGB(255, 255, 255)
		puck.Material = Enum.Material.SmoothPlastic
		for _, face in Enum.NormalId:GetEnumItems() do
			local decal = Instance.new("Decal")
			decal.Name = "PuckStyle"
			decal.Texture = GALAXY_TEXTURE
			decal.Face = face
			decal.Parent = puck
		end
		local aura = Instance.new("Part")
		aura.Name = "PuckStyle"
		aura.Shape = Enum.PartType.Cylinder
		aura.Size = puck.Size + Vector3.new(0.12, 0.18, 0.18)
		aura.Color = Color3.fromRGB(158, 115, 255)
		aura.Material = Enum.Material.ForceField
		aura.CanCollide, aura.CanTouch, aura.CanQuery = false, false, false
		aura.Anchored = false
		aura.Massless = true
		aura.CastShadow = false
		aura.CFrame = puck.CFrame
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = puck, aura
		weld.Parent = aura
		aura.Parent = puck
		sparkle({
			Rate = 16,
			Lifetime = NumberRange.new(0.5, 1),
			Speed = NumberRange.new(0.3, 1),
			SpreadAngle = Vector2.new(180, 180),
			LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.18), NumberSequenceKeypoint.new(1, 0) }),
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 150, 255)),
		})
	end
end

-- Modelled cosmetics (assets/cosmetics, built in Blender on the same head): where each mesh's
-- bounding-box centre sits relative to the head centre.
local COS_CENTRE = {
	HatBeanie = Vector3.new(0, 1.383, 0),
	HatBeanieCuff = Vector3.new(0, 0.48, 0),
	HatBeaniePom = Vector3.new(0.004, 2.368, 0.048),
	HatCap = Vector3.new(0, 1.182, -0.733),
	HatCapButton = Vector3.new(0, 2.05, 0.001),
	HatArmy = Vector3.new(0, 1.135, 0),
	HatArmyStrap = Vector3.new(0, -0.737, -0.642),
	HatChef = Vector3.new(0, 0.95, 0),
	HatChefPuff = Vector3.new(-0.104, 2.55, 0),
	HatParty = Vector3.new(0, 2.585, 0),
	HatPartyStripe = Vector3.new(-0.093, 2.794, 0.098),
	HatTop = Vector3.new(0, 2.295, 0),
	HatTopRibbon = Vector3.new(0, 1.325, 0),
	HatViking = Vector3.new(0, 1.225, 0),
	HatVikingBand = Vector3.new(0, 0.46, 0),
	HatVikingHorns = Vector3.new(0, 1.632, -0.254),
	HatMelon = Vector3.new(0, 1.28, 0),
	HatMelonStripes = Vector3.new(0, 1.291, 0),
	HatMelonFlesh = Vector3.new(0, 0.26, 0),
	HatMelonSeeds = Vector3.new(0, 0.261, 0),
	HatCrown = Vector3.new(0, 2.145, 0),
	HatCrownGems = Vector3.new(0, 1.66, -0.14),
	HairCap = Vector3.new(0, 0.371, 0.076),
	HairTucked = Vector3.new(0, 0.336, 0.067),
	HairFringe = Vector3.new(-0.005, 1.036, -1.15),
	HairSpikes = Vector3.new(0, 1.939, 0.078),
	HairFlow = Vector3.new(0, -0.414, 0.627),
	HairMohawk = Vector3.new(0, 0.812, 0.184),
	HairPuff = Vector3.new(0.007, 0.832, 0.225),
	FaceShades = Vector3.new(0, -0.063, -0.539),
	FaceSpecs = Vector3.new(0, -0.022, -0.542),
	FaceSpecsLens = Vector3.new(0, -0.021, -1.552),
	FaceStache = Vector3.new(0, -0.401, -1.633),
	FaceNose = Vector3.new(0, -0.251, -1.824),
}
-- Each hat's meshes and their colours: "main" and "accent" are the item's own colours.
local VIKING_BAND = Color3.fromRGB(120, 90, 60)
local MELON_FLESH = Color3.fromRGB(236, 72, 80)
local COS_HATS: { [string]: { { any } } } = {
	beanie = { { "HatBeanie", "main" }, { "HatBeanieCuff", "accent" }, { "HatBeaniePom", "accent" } },
	cap = { { "HatCap", "main" }, { "HatCapButton", "accent" } },
	army = { { "HatArmy", "main" }, { "HatArmyStrap", "accent" } },
	chef = { { "HatChef", "main" }, { "HatChefPuff", "accent" } },
	party = { { "HatParty", "main" }, { "HatPartyStripe", "accent" } },
	tophat = { { "HatTop", "main" }, { "HatTopRibbon", "accent" } },
	viking = { { "HatViking", "main" }, { "HatVikingBand", VIKING_BAND }, { "HatVikingHorns", "accent" } },
	melon = { { "HatMelon", "main" }, { "HatMelonStripes", "accent" }, { "HatMelonFlesh", MELON_FLESH }, { "HatMelonSeeds", Color3.fromRGB(28, 26, 30) } },
	crown = { { "HatCrown", "main" }, { "HatCrownGems", "accent" } },
}
local COS_HAIR = { spiky = "HairSpikes", long = "HairFlow", mohawk = "HairMohawk", afro = "HairPuff" }

---------------------------------------------------------------------------------------------
-- Headwear (assets/headwear/headwear.py, built in Blender on the same head; MeshPart templates in
-- ReplicatedStorage.HeadMeshes.<Style>.<Region>, cloud place only). Each row: where the region's
-- bounding-box centre sits relative to the head centre, its tint ("main" / "accent" are the item's
-- colours, "accentDark" a deeper accent, "ink" the outline colour, "hair" the hair colour) or a
-- fixed colour, its material and transparency. These take over from the older cosmetics above
-- whenever a style's folder is present.
---------------------------------------------------------------------------------------------
local HEADWEAR: { [string]: { [string]: { any } } } = {
	-- HEADWEAR_START (rows written from assets/headwear/out/headwear_info.json)
	Helmet = {
		Shell = { Vector3.new(0, 0.4231, 0.1157), "main", Enum.Material.SmoothPlastic },
		Trim = { Vector3.new(0, 0.2803, -0.0311), "ink", Enum.Material.SmoothPlastic },
		Clips = { Vector3.new(0, 0.2756, -0.3524), Color3.fromRGB(196, 200, 208), Enum.Material.Metal },
		Decal = { Vector3.new(0, 1.3008, -0.0002), "accent", Enum.Material.SmoothPlastic },
		Visor = { Vector3.new(0, 0.16, -1.3332), Color3.fromRGB(205, 228, 248), Enum.Material.Glass, 0.6 },
	},
	Beanie = {
		Knit = { Vector3.new(0, 0.8399, 0.088), "main", Enum.Material.SmoothPlastic },
		Cuff = { Vector3.new(0, 0.1801, 0.0393), "accent", Enum.Material.SmoothPlastic },
		Pom = { Vector3.new(0.0028, 2.538, 0.0008), "accent", Enum.Material.SmoothPlastic },
	},
	Cap = {
		Crown = { Vector3.new(0, 0.7272, 0.0139), "main", Enum.Material.SmoothPlastic },
		Brim = { Vector3.new(0, 0.417, -2.1149), "main", Enum.Material.SmoothPlastic },
		Trim = { Vector3.new(0, 1.1455, -1.0364), "accent", Enum.Material.SmoothPlastic },
	},
	Army = {
		Shell = { Vector3.new(0, 0.941, 0.0619), "main", Enum.Material.SmoothPlastic },
		Camo = { Vector3.new(0.0378, 1.2699, 0.0803), "accent", Enum.Material.SmoothPlastic },
		Strap = { Vector3.new(0, -0.5449, -0.4851), Color3.fromRGB(70, 52, 36), Enum.Material.SmoothPlastic },
	},
	Chef = {
		Band = { Vector3.new(0, 0.885, 0), "main", Enum.Material.SmoothPlastic },
		Puff = { Vector3.new(-0.02, 2.3495, 0.0121), "accent", Enum.Material.SmoothPlastic },
	},
	Party = {
		Cone = { Vector3.new(0, 2.3226, 0.05), "main", Enum.Material.SmoothPlastic },
		Stripes = { Vector3.new(0.0601, 2.2961, 0.05), "accent", Enum.Material.SmoothPlastic },
		Pom = { Vector3.new(0.0066, 2.5362, 0.0501), "accent", Enum.Material.SmoothPlastic },
	},
	TopHat = {
		Hat = { Vector3.new(0, 2.0107, 0.0454), "main", Enum.Material.SmoothPlastic },
		Ribbon = { Vector3.new(0.085, 1.3246, 0.0537), "accent", Enum.Material.SmoothPlastic },
	},
	Viking = {
		Helm = { Vector3.new(0, 0.9171, 0.0484), "main", Enum.Material.Metal },
		Bands = { Vector3.new(0, 0.7879, -0.0556), Color3.fromRGB(150, 108, 58), Enum.Material.Metal },
		Horns = { Vector3.new(0, 1.2422, 0.0765), "accent", Enum.Material.SmoothPlastic },
	},
	Melon = {
		Rind = { Vector3.new(0, 0.9002, 0.0444), "main", Enum.Material.SmoothPlastic },
		Stripes = { Vector3.new(0.0113, 0.9488, 0.0478), "accent", Enum.Material.SmoothPlastic },
		Pith = { Vector3.new(0, 0.3218, 0.0326), Color3.fromRGB(232, 240, 206), Enum.Material.SmoothPlastic },
		Flesh = { Vector3.new(0, 0.3356, 0.0225), Color3.fromRGB(236, 72, 80), Enum.Material.SmoothPlastic },
		Seeds = { Vector3.new(-0.0006, 0.1042, 0.0184), Color3.fromRGB(28, 26, 30), Enum.Material.SmoothPlastic },
	},
	Crown = {
		Gold = { Vector3.new(0, 1.8327, 0.0499), "main", Enum.Material.Metal },
		Gems = { Vector3.new(0, 1.52, 0.043), "accent", Enum.Material.Glass },
		Velvet = { Vector3.new(0, 1.4, 0.03), "accentDark", Enum.Material.SmoothPlastic },
		Fur = { Vector3.new(0.0047, 1.03, 0.03), Color3.fromRGB(250, 250, 250), Enum.Material.SmoothPlastic },
	},
	Hair = {
		Cap = { Vector3.new(0, 0.4259, 0.0487), "hair", Enum.Material.SmoothPlastic },
		Tucked = { Vector3.new(0, 0.3227, 0.046), "hair", Enum.Material.SmoothPlastic },
		Fringe = { Vector3.new(0.2415, 0.7616, -1.1569), "hair", Enum.Material.SmoothPlastic },
		Spikes = { Vector3.new(0.0274, 1.7627, 0.8069), "hair", Enum.Material.SmoothPlastic },
		Flow = { Vector3.new(-0.0105, -0.622, 0.713), "hair", Enum.Material.SmoothPlastic },
		Mohawk = { Vector3.new(0, 0.7301, 0.4304), "hair", Enum.Material.SmoothPlastic },
		Puff = { Vector3.new(-0.0034, 0.6606, 0.3934), "hair", Enum.Material.SmoothPlastic },
		-- Build 25 (assets/headwear/headwear2.py, Hair2)
		Bun = { Vector3.new(0, 1.8327, -0.1167), "hair", Enum.Material.SmoothPlastic },
		Pigtails = { Vector3.new(0.0016, -0.9305, 0.6314), "hair", Enum.Material.SmoothPlastic },
		Bob = { Vector3.new(0, 0.1569, 0.1793), "hair", Enum.Material.SmoothPlastic },
		Quiff = { Vector3.new(0, 1.7369, -0.4182), "hair", Enum.Material.SmoothPlastic },
		-- Build 26 (assets/headwear/headwear3.py, Hair3)
		Curls = { Vector3.new(0.0047, 0.9899, 0.1044), "hair", Enum.Material.SmoothPlastic },
		Ponytail = { Vector3.new(0, 0.3979, 1.9845), "hair", Enum.Material.SmoothPlastic },
	},
	Face = {
		ShadesFrame = { Vector3.new(0, 0.0447, -0.7215), "main", Enum.Material.SmoothPlastic },
		ShadesLens = { Vector3.new(0, 0.0231, -1.645), Color3.fromRGB(28, 34, 48), Enum.Material.Glass },
		SpecsFrame = { Vector3.new(0, 0.0229, -0.7229), "main", Enum.Material.Metal },
		SpecsLens = { Vector3.new(0, 0.0229, -1.6703), Color3.fromRGB(215, 234, 250), Enum.Material.Glass, 0.5 },
		Stache = { Vector3.new(0, -0.3524, -1.5717), "main", Enum.Material.SmoothPlastic },
		Nose = { Vector3.new(0, -0.2794, -1.7794), "main", Enum.Material.SmoothPlastic },
		-- Build 25 (assets/headwear/headwear2.py, Face2)
		Beard = { Vector3.new(0.001, -0.9599, -0.8005), "main", Enum.Material.SmoothPlastic },
		Patch = { Vector3.new(0.6347, 0.0215, -1.5327), "main", Enum.Material.SmoothPlastic },
		PatchStrap = { Vector3.new(0.0635, 0.3279, 0.039), Color3.fromRGB(36, 32, 30), Enum.Material.SmoothPlastic },
		GogglesFrame = { Vector3.new(0, 0.0609, -1.4294), "main", Enum.Material.SmoothPlastic },
		GogglesLens = { Vector3.new(0, 0.0596, -1.5462), Color3.fromRGB(255, 148, 40), Enum.Material.Glass },
		GogglesStrap = { Vector3.new(0, 0.0787, 0.2333), Color3.fromRGB(40, 40, 48), Enum.Material.SmoothPlastic },
		MonocleRim = { Vector3.new(-0.7877, -0.6139, -1.2576), "main", Enum.Material.Metal },
		MonocleLens = { Vector3.new(-0.6781, 0.023, -1.664), Color3.fromRGB(215, 234, 250), Enum.Material.Glass, 0.5 },
		-- Build 26 (assets/headwear/headwear3.py, Face3)
		StarFrame = { Vector3.new(0, 0.1062, -0.7227), "main", Enum.Material.SmoothPlastic },
		StarLens = { Vector3.new(0, 0.0873, -1.6209), Color3.fromRGB(36, 30, 60), Enum.Material.Glass },
		Plaster = { Vector3.new(-0.3315, -0.4515, -1.389), "main", Enum.Material.SmoothPlastic },
		Pad = { Vector3.new(-0.4176, -0.4222, -1.514), Color3.fromRGB(250, 238, 222), Enum.Material.SmoothPlastic },
	},
	-- Build 25 (assets/headwear/headwear2.py)
	Propeller = {
		Dome = { Vector3.new(0, 0.7817, -0.4326), "main", Enum.Material.SmoothPlastic },
		Panels = { Vector3.new(0, 0.8847, 0.1804), "accent", Enum.Material.SmoothPlastic },
		Blades = { Vector3.new(0.1137, 2.28, -0.1515), "accent", Enum.Material.SmoothPlastic },
		Hub = { Vector3.new(0, 2.095, 0), Color3.fromRGB(226, 52, 60), Enum.Material.SmoothPlastic },
	},
	-- Build 26 (assets/headwear/headwear3.py)
	Trapper = {
		Shell = { Vector3.new(0, 0.2161, 0.0467), "main", Enum.Material.SmoothPlastic },
		Fur = { Vector3.new(0.0258, -0.5132, 0.0531), "accent", Enum.Material.SmoothPlastic },
		Ties = { Vector3.new(0, -1.8337, 0.1353), Color3.fromRGB(110, 30, 30), Enum.Material.SmoothPlastic },
	},
	Antlers = {
		Band = { Vector3.new(0, 0.7683, -0.2188), "main", Enum.Material.SmoothPlastic },
		Antlers = { Vector3.new(0, 1.8636, -0.3045), "accent", Enum.Material.SmoothPlastic },
		Bells = { Vector3.new(0, -0.4085, -0.2756), Color3.fromRGB(255, 200, 60), Enum.Material.Metal },
	},
	-- Build 31 (assets/headwear/headwear4.py): the Santa Suit's hat and the Snowman's head.
	SantaHat = {
		Cap = { Vector3.new(0.071, 1.8926, 0.1028), "main", Enum.Material.Fabric },
		Fur = { Vector3.new(0.0172, 0.2801, 0.0676), "accent", Enum.Material.Fabric },
		Pom = { Vector3.new(1.9229, 2.4665, 1.7286), "accent", Enum.Material.Fabric },
	},
	SnowmanHead = {
		Snow = { Vector3.new(0.005, 0.1191, 0.0429), "main", Enum.Material.Snow },
		Coal = { Vector3.new(0.0034, 0.0427, -1.7387), Color3.fromRGB(36, 33, 38), Enum.Material.Slate },
		Carrot = { Vector3.new(0, 0.0725, -2.4011), "accent", Enum.Material.SmoothPlastic },
		Hat = { Vector3.new(0, 2.488, 0.1223), Color3.fromRGB(26, 26, 30), Enum.Material.SmoothPlastic },
		HatBand = { Vector3.new(0, 2.1963, 0.1603), Color3.fromRGB(41, 143, 214), Enum.Material.Fabric },
	},
	-- Build 40 first-full-match reward (assets/headwear/headwear6.py, out_b40n): the Nova Visor
	-- (fixed colours: it doesn't take the item's).
	NovaVisor = {
		Shell = { Vector3.new(0, 0.4317, 0.0923), NOVA_GRAPH, Enum.Material.SmoothPlastic },
		Metal = { Vector3.new(0, 0.8655, 0.1026), NOVA_GUN, Enum.Material.Metal },
		Glow = { Vector3.new(0, 0.6468, 0.0495), NOVA_CYAN, Enum.Material.Neon },
		PodGlow = { Vector3.new(0, 0.6734, 0.3256), NOVA_MAG, Enum.Material.Neon },
		Visor = { Vector3.new(0, 0.03, -1.0192), NOVA_CYAN, Enum.Material.Glass, 0.35 },
	},
	-- Build 41 animated season-pass pieces (assets/headwear/headwear7.py, out_b41b). Face items:
	ScanVisor = {
		Frame = { Vector3.new(0, 0.155, -0.1549), "main", Enum.Material.SmoothPlastic },
		Lens = { Vector3.new(0, 0.03, -1.2997), Color3.fromRGB(18, 20, 30), Enum.Material.Glass, 0.15 },
		Glow = { Vector3.new(0, 0.035, -1.2379), "accent", Enum.Material.Neon },
		Scan = { Vector3.new(0, 0.03, -1.89), "accent", Enum.Material.Neon },
	},
	HoloSpecs = {
		Frame = { Vector3.new(0, 0.0229, -0.7645), "main", Enum.Material.Metal },
		Lens = { Vector3.new(0, 0.0229, -1.6522), "accent", Enum.Material.Glass, 0.55 },
		RingL = { Vector3.new(-0.7837, 0.0259, -1.9685), "accent", Enum.Material.Neon },
		RingR = { Vector3.new(0.7837, 0.0259, -1.9685), "accent", Enum.Material.Neon },
	},
	LavaGoggles = {
		Frame = { Vector3.new(0.0434, 0.1672, -1.6154), Color3.fromRGB(34, 27, 25), Enum.Material.CrackedLava },
		Lava = { Vector3.new(0, 0.0505, -1.759), Color3.fromRGB(255, 110, 20), Enum.Material.Neon },
		Crust = { Vector3.new(-0.0215, 0.0441, -1.7388), Color3.fromRGB(38, 28, 26), Enum.Material.Slate },
		Drips = { Vector3.new(0, -0.6785, -1.5387), Color3.fromRGB(255, 120, 24), Enum.Material.Neon },
		Strap = { Vector3.new(0, 0.2017, 0.2113), Color3.fromRGB(52, 38, 34), Enum.Material.Fabric },
	},
	-- Hats:
	Halo = {
		Band = { Vector3.new(0, 1.0033, -0.0101), "main", Enum.Material.Metal },
		Gem = { Vector3.new(0, 0.99, -1.7714), "accent", Enum.Material.Neon },
		Ring = { Vector3.new(0, 2.25, 0.07), "main", Enum.Material.Metal },
		RingGlow = { Vector3.new(0, 2.3378, 0.0504), "accent", Enum.Material.Neon },
	},
	OrbitCrown = {
		Band = { Vector3.new(0, 1.1098, 0), "main", Enum.Material.Metal },
		Core = { Vector3.new(0, 1.2, -0.1546), "accent", Enum.Material.Neon },
		Track = { Vector3.new(0, 0.85, 0.03), "accent", Enum.Material.Neon, 0.35 },
		Planet = { Vector3.new(0, 1.7588, -2.2452), Color3.fromRGB(255, 150, 40), Enum.Material.SmoothPlastic },
		PlanetRing = { Vector3.new(0, 1.7588, -2.2452), "accent", Enum.Material.Neon },
		Moon = { Vector3.new(0, -0.0588, 2.3052), Color3.fromRGB(235, 240, 255), Enum.Material.Neon },
	},
	-- HEADWEAR_END
}
-- Which headwear style each hat style wears, the hair style regions, and each face extra's regions.
local HAT_HEADWEAR = {
	helmet = "Helmet", beanie = "Beanie", cap = "Cap", army = "Army", chef = "Chef",
	party = "Party", tophat = "TopHat", viking = "Viking", melon = "Melon", crown = "Crown",
	propeller = "Propeller", trapper = "Trapper", antlers = "Antlers",
	santahat = "SantaHat", snowmanhead = "SnowmanHead",
	novavisor = "NovaVisor",
	halo = "Halo", orbit = "OrbitCrown", -- Build 41
}
-- Hats worn with the hair style showing (they sit round the head over the hair).
local HAIR_SHOWS = { crown = true, halo = true, orbit = true }
-- Build 41: face items that are whole modelled styles of their own (HEADWEAR[style]).
local FACE_MESH = { ScanVisor = true, HoloSpecs = true, LavaGoggles = true }
local HAIR_HEADWEAR = {
	spiky = "Spikes", long = "Flow", mohawk = "Mohawk", afro = "Puff",
	bun = "Bun", pigtails = "Pigtails", bob = "Bob", quiff = "Quiff",
	curly = "Curls", ponytail = "Ponytail",
}
-- Styles that replace the hair cap bare-headed (their own region covers the head).
local HAIR_NO_CAP = { mohawk = true, bob = true }
-- Styles that also wear the fringe bare-headed.
local HAIR_FRINGE = { short = true, long = true, pigtails = true, ponytail = true }
local FACE_HEADWEAR = {
	shades = { "ShadesFrame", "ShadesLens" },
	glasses = { "SpecsFrame", "SpecsLens" },
	mustache = { "Stache" },
	rednose = { "Nose" },
	beard = { "Beard" },
	eyepatch = { "Patch", "PatchStrap" },
	goggles = { "GogglesFrame", "GogglesLens", "GogglesStrap" },
	monocle = { "MonocleRim", "MonocleLens" },
	starshades = { "StarFrame", "StarLens" },
	bandage = { "Plaster", "Pad" },
}

local headFolder: Instance? = nil
local function headTemplates(style: string): Instance?
	if not headFolder then
		headFolder = game:GetService("ReplicatedStorage"):FindFirstChild("HeadMeshes")
	end
	return headFolder and headFolder:FindFirstChild(style)
end

local function headTint(t: any, main: Color3, accent: Color3): Color3
	if typeof(t) == "Color3" then
		return t
	elseif t == "accent" then
		return accent
	elseif t == "accentDark" then
		return accent:Lerp(Color3.new(0, 0, 0), 0.4)
	elseif t == "ink" then
		return INK
	end
	return main -- "main" and "hair"
end

-- Cylinders in Roblox run along X; this turns one upright.
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)
-- And this faces a disc toward -Z (the face direction).
local FACING = CFrame.Angles(0, math.pi / 2, 0)

-- The head is a round ellipsoid, like the references. Face parts sit on its curved front and
-- turn to follow the surface, so they read as painted on rather than stuck to a flat plate.
local HEAD_SIZE = Vector3.new(3.5, 3.3, 3.2)
local HEAD_Z = 0.05
local HEAD_A, HEAD_B, HEAD_C = HEAD_SIZE.X / 2, HEAD_SIZE.Y / 2, HEAD_SIZE.Z / 2

local function faceDepth(x: number, y: number): number
	local u = (x / HEAD_A) ^ 2 + ((y - Looks.HEAD_Y) / HEAD_B) ^ 2
	return HEAD_C * math.sqrt(math.max(0, 1 - u))
end

local function faceZ(x: number, y: number, inset: number?): number
	-- The z of the head's front surface at (x, y), pushed in by inset (parts half-sink in).
	return HEAD_Z - faceDepth(x, y) - 0.02 + ((inset or 0.08) - 0.08)
end

-- A frame on the face at (x, y) whose -Z looks straight out of the curved surface.
local function faceAt(x: number, y: number, inset: number?): CFrame
	local z = faceZ(x, y, inset)
	local normal = Vector3.new(x / (HEAD_A * HEAD_A), (y - Looks.HEAD_Y) / (HEAD_B * HEAD_B), (z - HEAD_Z) / (HEAD_C * HEAD_C))
	local at = Vector3.new(x, y, z)
	return CFrame.lookAt(at, at + normal.Unit)
end

-- scale shrinks the body (1 = full size, used in the locker; matches use Looks.PLAY_SCALE).
function Looks.build(parent: Instance?, rawLook: any, team: number, scale: number?): Rig
	local look = Catalog.sanitizeLook(rawLook)
	local kit = Looks.kit(team)
	local skin = Catalog.SkinTones[look.skin]
	local hairColor = Catalog.HairColors[look.hairColor]
	local model = Instance.new("Model")
	model.Name = "Skater"

	local body: { BasePart } = {}
	local offsets: { CFrame } = {}
	local function add(p: BasePart, offset: CFrame)
		table.insert(body, p)
		table.insert(offsets, offset)
	end
	-- Build 40: animated pieces, gathered as they're made and handed to Looks.animate.
	local spinOf: { [BasePart]: { axis: Vector3?, rate: number?, bob: number? } } = {}
	local pulses: { { part: BasePart, a: Color3, b: Color3, rate: number, phase: number } } = {}
	local function notePulse(style: string?, region: string, p: BasePart, main: Color3?, accent: Color3?)
		local row = style and PULSE[style] and PULSE[style][region]
		if row then
			table.insert(pulses, { part = p, a = pulseTint(row[1], main, accent), b = pulseTint(row[2], main, accent), rate = row[3], phase = row[4] or 0 })
		end
	end
	-- Build 41: where a spinning piece turns, if not about its own centre (relative to its centre).
	local pivotOf: { [BasePart]: Vector3 } = {}

	local HY = Looks.HEAD_Y

	-- Body: a squat pawn. Black pants flare onto the ice; the jersey is a drum with a rounded
	-- shoulder dome and two bold bands, like the reference kits.
	add(part(model, "Hem", Vector3.new(0.45, 3.95, 3.95), kit.pants, "cyl"), CFrame.new(0, 0.25, 0) * UPRIGHT)
	add(part(model, "Pants", Vector3.new(1.0, 3.75, 3.75), kit.pants, "cyl"), CFrame.new(0, 0.7, 0) * UPRIGHT)
	add(part(model, "Jersey", Vector3.new(2.0, 3.6, 3.6), kit.jersey, "cyl"), CFrame.new(0, 2.2, 0) * UPRIGHT)
	add(part(model, "Shoulders", Vector3.new(3.6, 1.1, 3.6), kit.jersey, "egg"), CFrame.new(0, 3.2, 0))
	add(part(model, "Band", Vector3.new(0.42, 3.66, 3.66), kit.trim, "cyl"), CFrame.new(0, 1.75, 0) * UPRIGHT)
	add(part(model, "Band2", Vector3.new(0.16, 3.67, 3.67), kit.band, "cyl"), CFrame.new(0, 2.06, 0) * UPRIGHT)
	add(part(model, "Band3", Vector3.new(0.16, 3.67, 3.67), kit.band, "cyl"), CFrame.new(0, 1.44, 0) * UPRIGHT)
	add(part(model, "Collar", Vector3.new(0.35, 2.3, 2.3), kit.trim, "cyl"), CFrame.new(0, 3.65, 0) * UPRIGHT)

	-- An outfit swaps that body for its modelled pieces.
	local outfitItem = Catalog.ById[look.outfit]
	local outfit = outfitItem and outfitItem.style and OUTFITS[outfitItem.style]
	local templates = outfit and outfitTemplates((outfitItem :: Catalog.Item).style :: string)
	if outfit and templates then
		for i = #body, 1, -1 do
			if REPLACED_BY_OUTFIT[body[i].Name] then
				body[i]:Destroy()
				table.remove(body, i)
				table.remove(offsets, i)
			end
		end
		for _, row in outfit.parts do
			local template = templates:FindFirstChild(row[1])
			if template and template:IsA("MeshPart") then
				local p = template:Clone()
				p.Anchored = true
				p.CanCollide = false
				p.CanTouch = false
				p.CanQuery = false
				p.Color = row[3]
				p.Material = row[4]
				p.Transparency = row[5] or 0
				p.CastShadow = row[4] ~= Enum.Material.Neon and row[4] ~= Enum.Material.ForceField and (row[5] or 0) == 0
				p.Parent = model
				add(p, CFrame.new(row[2]))
				notePulse((outfitItem :: Catalog.Item).style, row[1], p)
			end
		end
		local fxPart, fxAt = outfitFx(model, outfit.fx)
		if fxPart and fxAt then
			add(fxPart, fxAt)
		end
	else
		outfit = nil
	end
	local hooded = outfit ~= nil and outfit.hood == true

	-- Skin finish over every body piece so far (the jersey or the outfit).
	local finishItem = Catalog.ById[look.finish]
	local finish = finishItem and finishItem.style
	if finish then
		for _, p in body do
			if p.Transparency < 1 and p.Material ~= Enum.Material.ForceField then
				applyFinish(finish, p)
			end
		end
		local sparkle = finishFx(model, finish)
		if sparkle then
			add(sparkle, CFrame.new(0, 1.95, 0))
		end
	end

	-- Body type: a wider, taller body (and shoulder pads on the Bruiser).
	-- Build 37: no item changes the body's size any more (the Big Bruiser's pass tier is the
	-- Galaxy Head now), so a saved build is ignored and every body is the standard one.
	local bodyBuild: typeof(BUILDS.Bruiser)? = nil
	local liftHead = 0
	if bodyBuild then
		for i, p in body do
			offsets[i] = scaleBody(p, offsets[i], bodyBuild.across, bodyBuild.up)
		end
		liftHead = 3.75 * (bodyBuild.up - 1)
		if bodyBuild.pads then
			local padColor = if outfit then (outfit :: any).cuff else kit.jersey
			for _, side in { -1, 1 } do
				local pad = part(model, "ShoulderPad", Vector3.new(2.0, 1.15, 2.3), padColor, "egg")
				applyFinish(finish, pad)
				add(pad, CFrame.new(side * 1.75, 3.55 + liftHead, 0.1) * CFrame.Angles(0, 0, side * -0.38))
			end
		end
	end

	-- Back bling, on the back (+z), clear of the body (pushed out on a wider body).
	local backItem = Catalog.ById[look.back]
	local backStyle = backItem and backItem.style
	local back = backStyle and BACKS[backStyle]
	local backParts = backStyle and backTemplates(backStyle)
	if back and backParts and backStyle then
		local shift = Vector3.new(0, liftHead * 0.6, if bodyBuild then (bodyBuild.across - 1) * 1.9 else 0)
		for _, row in back.parts do
			local template = backParts:FindFirstChild(row[1])
			if template and template:IsA("MeshPart") then
				local p = template:Clone()
				p.Anchored = true
				p.CanCollide = false
				p.CanTouch = false
				p.CanQuery = false
				p.Color = row[3]
				p.Material = row[4]
				p.Transparency = row[5] or 0
				p.CastShadow = row[4] ~= Enum.Material.Neon and row[4] ~= Enum.Material.ForceField and (row[5] or 0) == 0
				p.Parent = model
				add(p, CFrame.new(row[2] + shift))
				notePulse(backStyle, row[1], p)
				local moves = BACK_ANIM[backStyle] and BACK_ANIM[backStyle][row[1]]
				if moves then
					spinOf[p] = moves
				end
			end
		end
		for _, fx in backFx(model, backStyle, back.fx) do
			add(fx.part, fx.at + shift)
		end
	end

	-- Head: one smooth round ellipsoid with a simple painted-on face.
	local headStart = #body + 1
	local function liftFromHead()
		-- Everything from the head up sits on the taller body.
		if liftHead ~= 0 then
			for i = headStart, #body do
				offsets[i] = offsets[i] + Vector3.new(0, liftHead, 0)
			end
		end
	end
	-- Build 37: the Galaxy Head (a face item, pass tier 30): the whole head is a window onto
	-- space like the Galaxy Body, with no face and no ears. A ball (decals project onto a ball,
	-- as on the Galaxy Puck's cylinder) in a faint force-field aura, stars twinkling round it.
	local galaxyHead = Catalog.styleOf(look.face) == "GalaxyHead"
	if galaxyHead then
		local orb = part(model, "Head", Vector3.new(3.3, 3.3, 3.3), Color3.fromRGB(255, 255, 255), "ball")
		for _, faceId in Enum.NormalId:GetEnumItems() do
			local decal = Instance.new("Decal")
			decal.Texture = GALAXY_TEXTURE
			decal.Face = faceId
			decal.Parent = orb
		end
		local stars = Instance.new("ParticleEmitter")
		stars.Rate = 5
		stars.Lifetime = NumberRange.new(0.6, 1.1)
		stars.Speed = NumberRange.new(0.2, 0.6)
		stars.SpreadAngle = Vector2.new(180, 180)
		stars.LightEmission = 1
		stars.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.16), NumberSequenceKeypoint.new(1, 0) })
		stars.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 150, 255))
		stars.Parent = orb
		add(orb, CFrame.new(0, HY, HEAD_Z))
		local aura = part(model, "HeadAura", Vector3.new(3.42, 3.42, 3.42), Color3.fromRGB(158, 115, 255), "ball")
		aura.Material = Enum.Material.ForceField
		aura.CastShadow = false
		add(aura, CFrame.new(0, HY, HEAD_Z))
	else
		add(part(model, "Head", HEAD_SIZE, skin, "egg"), CFrame.new(0, HY, HEAD_Z))
	end
	local head = body[headStart]
	-- The modelled hockey helmet's ear guards (and the trapper hat's flaps) cover the ears, so
	-- they're left off under them.
	local hatStyle = if hooded then "nohat" else Catalog.styleOf(look.hat)
	local earsCovered = (hatStyle == "helmet" and headTemplates("Helmet") ~= nil) or (hatStyle == "trapper" and headTemplates("Trapper") ~= nil)
		or (hatStyle == "snowmanhead" and headTemplates("SnowmanHead") ~= nil) -- the snowball swallows the whole head
		or galaxyHead
	if not earsCovered then
		for _, side in { -1, 1 } do
			add(part(model, "Ear", Vector3.new(0.6, 0.8, 0.5), skin, "egg"), CFrame.new(side * (HEAD_A - 0.05), HY - 0.15, HEAD_Z + 0.2))
		end
	end
	-- The face is painted on: every feature is a paper-thin shape lying on the curved skin, so
	-- nothing sticks out of the head (each one rises about 0.03 studs at most).
	local function paint(name: string, size: Vector3, color: Color3, at: CFrame): Part
		local p = part(model, name, size, color, "egg")
		p.CastShadow = false
		add(p, at)
		return p
	end
	-- (The Galaxy Head has no face.)
	for _, x in if galaxyHead then {} else { -0.58, 0.58 } do
		local y = HY - 0.02
		paint("Eye", Vector3.new(0.34, 0.5, 0.03), INK, faceAt(x, y))
		paint("Glint", Vector3.new(0.12, 0.12, 0.02), WHITE, faceAt(x + 0.06, y + 0.12, 0.066))
	end
	-- Smile: one smooth curved line, drawn as short overlapping strokes along a gentle arc.
	local SMILE_HALF, SMILE_CURVE = 0.3, 0.1
	for i = 0, if galaxyHead then -1 else 8 do
		local t = i / 4 - 1
		local x = t * SMILE_HALF
		local y = HY - 0.6 + SMILE_CURVE * t * t
		local slope = 2 * SMILE_CURVE * t / SMILE_HALF
		paint("Smile", Vector3.new(0.13, 0.065, 0.03), INK, faceAt(x, y) * CFrame.Angles(0, 0, math.atan(slope)))
	end
	for _, x in if galaxyHead then {} else { -1.0, 1.0 } do
		local cheek = paint("Cheek", Vector3.new(0.52, 0.3, 0.02), Color3.fromRGB(240, 140, 130), faceAt(x, HY - 0.4, 0.075))
		cheek.Transparency = 0.35
	end

	-- Hair: a round cap over the top and back of the head, its hairline above the eyes.
	local hair = if hooded then "bald" else look.hair
	local hatOn = not hooded and look.hat ~= "nohat"
	-- Under the modelled helmet the cap is tucked lower and smaller, so it shows below the rim
	-- but never pokes through the vents.
	local tucked = hatOn and look.hat == "helmet" and (gearFolder or game:GetService("ReplicatedStorage"):FindFirstChild("GearMeshes")) ~= nil
	local headAt = Vector3.new(0, HY, HEAD_Z)
	local function cosmetic(name: string, color: Color3): MeshPart?
		local p = gear(model, name, color)
		if p then
			add(p, CFrame.new(headAt + COS_CENTRE[name]))
		end
		return p
	end
	-- One headwear region (HEADWEAR), placed on the head in its tint.
	local function headwear(style: string, region: string, main: Color3, accent: Color3): MeshPart?
		local row = HEADWEAR[style] and HEADWEAR[style][region]
		local folder = headTemplates(style)
		local template = folder and folder:FindFirstChild(region)
		if not (row and template and template:IsA("MeshPart")) then
			return nil
		end
		local p = template:Clone()
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Color = headTint(row[2], main, accent)
		p.Material = row[3]
		p.Transparency = row[4] or 0
		p.CastShadow = (row[4] or 0) == 0
		p.Parent = model
		add(p, CFrame.new(headAt + row[1]))
		notePulse(style, region, p, main, accent)
		local moves = BACK_ANIM[style] and BACK_ANIM[style][region]
		if moves then
			spinOf[p] = moves
			if moves.pivot then
				pivotOf[p] = moves.pivot - row[1]
			end
		end
		if style == "LavaGoggles" and region == "Lava" then
			-- Build 41: embers drift up off the molten lenses.
			local embers = Instance.new("ParticleEmitter")
			embers.Rate = 5
			embers.Lifetime = NumberRange.new(0.6, 1.1)
			embers.Speed = NumberRange.new(0.6, 1.4)
			embers.SpreadAngle = Vector2.new(25, 25)
			embers.EmissionDirection = Enum.NormalId.Top
			embers.Acceleration = Vector3.new(0, 1.5, 0)
			embers.LightEmission = 1
			embers.LightInfluence = 0
			embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0) })
			embers.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 80, 20))
			embers.Parent = p
		elseif style == "Halo" and region == "Gem" then
			local glints = Instance.new("ParticleEmitter")
			glints.Rate = 3
			glints.Lifetime = NumberRange.new(0.4, 0.8)
			glints.Speed = NumberRange.new(0.3, 0.8)
			glints.SpreadAngle = Vector2.new(180, 180)
			glints.LightEmission = 1
			glints.LightInfluence = 0
			glints.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.14), NumberSequenceKeypoint.new(1, 0) })
			glints.Color = ColorSequence.new(accent:Lerp(Color3.new(1, 1, 1), 0.5))
			glints.Parent = p
		end
		return p
	end
	-- The headwear meshes when they're in the place, then the older cosmetics (GearMeshes), else
	-- the primitive shapes.
	local newHair = headTemplates("Hair") ~= nil
	local modelled = not newHair and hasGear("HairCap")
	if newHair then
		-- Under any hat but the crown, a short tucked cap that never pokes through. Bare-headed (or
		-- crowned) the full cap, a fringe for short and long hair, and the style itself (the puff
		-- only bare-headed; the mohawk replaces the cap, its sides shaved).
		local styleOn = not hatOn or (HAIR_SHOWS[hatStyle] and hair ~= "afro")
		if hair ~= "bald" then
			if hatOn and not HAIR_SHOWS[hatStyle] then
				headwear("Hair", "Tucked", hairColor, hairColor)
			else
				if not (HAIR_NO_CAP[hair] and styleOn) then
					headwear("Hair", "Cap", hairColor, hairColor)
				end
				if not hatOn and HAIR_FRINGE[hair] then
					headwear("Hair", "Fringe", hairColor, hairColor)
				end
				local region = HAIR_HEADWEAR[hair]
				if region and styleOn then
					headwear("Hair", region, hairColor, hairColor)
				end
			end
		end
	elseif modelled then
		-- A short cap of hair on every look; under the helmet a smaller tucked one. A style (spikes,
		-- flow, mohawk, puff) shows with no hat, or under the crown (the puff only bare-headed).
		local styleOn = not hatOn or (Catalog.styleOf(look.hat) == "crown" and hair ~= "afro")
		if hair ~= "bald" then
			if not (hair == "mohawk" and styleOn) then
				cosmetic(if tucked then "HairTucked" else "HairCap", hairColor)
			end
			if not hatOn and (hair == "short" or hair == "long") then
				cosmetic("HairFringe", hairColor)
			end
			local style = COS_HAIR[hair]
			if style and styleOn then
				cosmetic(style, hairColor)
			end
		end
	elseif hair ~= "bald" and tucked then
		add(part(model, "Hair", Vector3.new(HEAD_SIZE.X + 0.12, 1.6, HEAD_SIZE.Z + 0.2), hairColor, "egg"), CFrame.new(0, HY + 0.45, HEAD_Z + 0.14))
	elseif hair ~= "bald" then
		add(part(model, "Hair", Vector3.new(HEAD_SIZE.X + 0.2, 2.2, HEAD_SIZE.Z + 0.25), hairColor, "egg"), CFrame.new(0, HY + 0.75, HEAD_Z + 0.12))
		if not hatOn then
			add(part(model, "Fringe", Vector3.new(2.5, 0.5, 0.5), hairColor, "egg"), faceAt(0.2, HY + 0.78, 0.12) * CFrame.Angles(0, 0, -0.12))
		end
	end
	if modelled or newHair then
		-- (styles placed above)
	elseif hair == "spiky" then
		for i = 0, 5 do
			local a = i / 6 * math.pi * 2
			add(part(model, "Spike", Vector3.new(0.8, 1.3, 0.8), hairColor, "egg"), CFrame.new(math.cos(a) * 0.9, HY + 1.75, math.sin(a) * 0.9 + 0.2) * CFrame.Angles(math.sin(a) * 0.5, 0, -math.cos(a) * 0.5))
		end
	elseif hair == "long" then
		add(part(model, "Flow", Vector3.new(3.4, 2.8, 1.3), hairColor, "egg"), CFrame.new(0, HY - 0.5, 1.15))
	elseif hair == "mohawk" then
		for i = -2, 2 do
			add(part(model, "Hawk", Vector3.new(0.5, 1.1, 0.9), hairColor, "egg"), CFrame.new(0, HY + 1.85 - math.abs(i) * 0.12, i * 0.62))
		end
	elseif hair == "afro" then
		add(part(model, "Puff", Vector3.new(4.5, 3.7, 4.4), hairColor, "egg"), CFrame.new(0, HY + 0.85, 0.3))
	end

	-- Headwear.
	-- A season item reuses another hat's shape (its style) in its own colours.
	local hat = if hooded then "nohat" else Catalog.styleOf(look.hat)
	local item = Catalog.ById[look.hat]
	local hc = (item and item.color) or kit.helmet
	local ha = (item and item.accent) or kit.trim
	local hatHeadwear = HAT_HEADWEAR[hat]
	local newHat = hatHeadwear ~= nil and headTemplates(hatHeadwear) ~= nil
	local helmetShell = if hat == "helmet" and not newHat then gear(model, "Helmet", kit.helmet) else nil
	if newHat then
		-- Each region of the modelled hat in the item's colours (the helmet in the team's).
		for region in HEADWEAR[hatHeadwear] do
			headwear(hatHeadwear, region, hc, ha)
		end
	elseif helmetShell then
		-- Modelled hockey helmet: a ribbed, vented shell with a brow band and flared back, dark
		-- ear guards and clips, and a clear half visor over the eyes.
		local headAt = Vector3.new(0, HY, HEAD_Z)
		add(helmetShell, CFrame.new(headAt + GEAR_CENTRE.Helmet))
		-- Dark foam liner just inside the shell, so the vents read as openings.
		add(part(model, "Liner", Vector3.new(3.56, 2.66, 3.5), INK, "egg"), CFrame.new(0, HY + 0.35, HEAD_Z + 0.1))
		local trim = gear(model, "HelmetTrim", INK)
		if trim then
			add(trim, CFrame.new(headAt + GEAR_CENTRE.HelmetTrim))
		end
		local visor = gear(model, "Visor", Color3.fromRGB(205, 228, 248))
		if visor then
			visor.Transparency = 0.62
			visor.CastShadow = false
			add(visor, CFrame.new(headAt + GEAR_CENTRE.Visor))
		end
	elseif hat == "helmet" then
		-- Hockey helmet: a smooth round shell a little bigger than the head and set higher, so
		-- its rim crosses the forehead just above the eyes; a team stripe over the crown, round
		-- ear cups and grey rivets that sit on the shell's surface.
		local hA, hB, hC = HEAD_A + 0.24, 1.3, HEAD_C + 0.24
		local cy, cz = HY + 0.85, HEAD_Z + 0.2
		local function onShell(x: number, y: number, out: number): CFrame
			local u = (x / hA) ^ 2 + ((y - cy) / hB) ^ 2
			local z = cz - hC * math.sqrt(math.max(0, 1 - u))
			local normal = Vector3.new(x / (hA * hA), (y - cy) / (hB * hB), (z - cz) / (hC * hC)).Unit
			local at = Vector3.new(x, y, z) + normal * out
			return CFrame.lookAt(at, at + normal)
		end
		add(part(model, "Helmet", Vector3.new(hA * 2, hB * 2, hC * 2), kit.helmet, "egg"), CFrame.new(0, cy, cz))
		add(part(model, "HelmetStripe", Vector3.new(0.7, hB * 2 + 0.06, hC * 2 + 0.06), kit.trim, "egg"), CFrame.new(0, cy, cz))
		-- A rolled rim along the front edge, just above the eyes.
		add(part(model, "HelmetRim", Vector3.new(hA * 2 - 0.3, 0.34, 0.5), kit.helmet, "egg"), onShell(0, HY + 0.32, -0.05))
		for _, side in { -1, 1 } do
			add(part(model, "EarCup", Vector3.new(0.4, 1.25, 1.25), kit.helmet, "cyl"), CFrame.new(side * (HEAD_A + 0.08), HY - 0.15, HEAD_Z + 0.25))
			add(part(model, "EarHole", Vector3.new(0.42, 0.45, 0.45), INK, "cyl"), CFrame.new(side * (HEAD_A + 0.1), HY - 0.15, HEAD_Z + 0.25))
			add(part(model, "Rivet", Vector3.new(0.22, 0.22, 0.22), RIVET, "ball"), onShell(side * 1.05, HY + 0.62, 0.02))
		end
	elseif modelled and COS_HATS[hat] then
		for _, piece in COS_HATS[hat] do
			local tint = piece[2]
			local color = if tint == "main" then hc elseif tint == "accent" then ha else tint
			cosmetic(piece[1], color)
		end
	elseif hat == "beanie" then
		add(part(model, "Beanie", Vector3.new(3.8, 2.7, 3.85), hc, "egg"), CFrame.new(0, HY + 0.75, 0.08))
		add(part(model, "Cuff", Vector3.new(3.9, 0.6, 3.95), ha, "egg"), CFrame.new(0, HY + 0.45, 0.08))
		add(part(model, "Pom", Vector3.new(1.0, 1.0, 1.0), ha, "ball"), CFrame.new(0, HY + 2.2, 0.1))
	elseif hat == "cap" then
		add(part(model, "Cap", Vector3.new(3.8, 2.5, 3.85), hc, "egg"), CFrame.new(0, HY + 0.75, 0.1))
		add(part(model, "Brim", Vector3.new(0.18, 2.6, 2.6), hc, "cyl"), CFrame.new(0, HY + 0.62, -1.5) * CFrame.Angles(math.rad(-8), 0, 0) * UPRIGHT)
		add(part(model, "Button", Vector3.new(0.4, 0.4, 0.4), ha, "ball"), CFrame.new(0, HY + 1.95, 0.1))
	elseif hat == "army" then
		add(part(model, "Shell", Vector3.new(4.1, 2.9, 4.2), hc, "egg"), CFrame.new(0, HY + 0.75, 0.05))
		add(part(model, "Lip", Vector3.new(4.5, 0.4, 4.6), ha, "egg"), CFrame.new(0, HY + 0.38, 0.05))
		add(part(model, "Strap", Vector3.new(0.16, 1.2, 0.16), ha), CFrame.new(-1.55, HY - 0.55, -0.4))
	elseif hat == "chef" then
		add(part(model, "Band", Vector3.new(2.0, 3.5, 3.5), hc, "cyl"), CFrame.new(0, HY + 1.15, 0.05) * UPRIGHT)
		add(part(model, "Puff", Vector3.new(4.0, 2.4, 4.0), ha, "egg"), CFrame.new(0, HY + 2.55, 0.05))
	elseif hat == "party" then
		for i = 0, 5 do
			local d = 2.6 - i * 0.42
			add(part(model, "Cone", Vector3.new(0.5, d, d), if i % 2 == 0 then hc else ha, "cyl"), CFrame.new(0, HY + 1.45 + i * 0.45, 0) * UPRIGHT)
		end
		add(part(model, "Tip", Vector3.new(0.55, 0.55, 0.55), ha, "ball"), CFrame.new(0, HY + 4.2, 0))
	elseif hat == "tophat" then
		add(part(model, "Crown", Vector3.new(2.5, 2.7, 2.7), hc, "cyl"), CFrame.new(0, HY + 2.35, 0) * UPRIGHT)
		add(part(model, "Ribbon", Vector3.new(0.45, 2.78, 2.78), ha, "cyl"), CFrame.new(0, HY + 1.4, 0) * UPRIGHT)
		add(part(model, "Brim", Vector3.new(0.18, 4.0, 4.0), hc, "cyl"), CFrame.new(0, HY + 1.12, 0) * UPRIGHT)
	elseif hat == "viking" then
		add(part(model, "Helm", Vector3.new(3.9, 2.8, 4.0), hc, "egg"), CFrame.new(0, HY + 0.65, 0.05))
		add(part(model, "Rim", Vector3.new(3.95, 0.4, 4.05), Color3.fromRGB(120, 90, 60), "egg"), CFrame.new(0, HY + 0.4, 0.05))
		for _, side in { -1, 1 } do
			for i = 0, 2 do
				local s = 0.95 - i * 0.25
				add(part(model, "Horn", Vector3.new(s, s, s), ha, "ball"), CFrame.new(side * (1.9 + i * 0.5), HY + 1.2 + i * 0.55, 0))
			end
		end
	elseif hat == "melon" then
		add(part(model, "Rind", Vector3.new(3.95, 2.9, 4.05), hc, "egg"), CFrame.new(0, HY + 0.65, 0.05))
		for i = 0, 3 do
			add(part(model, "Stripe", Vector3.new(0.45, 2.95, 4.1), ha, "egg"), CFrame.new(0, HY + 0.65, 0.05) * CFrame.Angles(0, i * math.pi / 4, 0))
		end
		add(part(model, "Flesh", Vector3.new(3.8, 0.3, 3.9), Color3.fromRGB(236, 72, 80), "egg"), CFrame.new(0, HY + 0.3, 0.05))
	elseif hat == "crown" then
		add(part(model, "Band", Vector3.new(0.9, 2.7, 2.7), hc, "cyl", Enum.Material.SmoothPlastic), CFrame.new(0, HY + 1.75, 0.1) * UPRIGHT)
		for i = 0, 4 do
			local a = i / 5 * math.pi * 2
			add(part(model, "Point", Vector3.new(0.5, 0.5, 0.5), hc, "ball"), CFrame.new(math.cos(a) * 1.2, HY + 2.35, math.sin(a) * 1.2 + 0.1))
		end
		add(part(model, "Gem", Vector3.new(0.5, 0.5, 0.25), ha, "egg"), CFrame.new(0, HY + 1.75, -1.3))
	end

	-- Face extras, laid on the curved face like the eyes.
	local face = Catalog.styleOf(look.face)
	local fitem = Catalog.ById[look.face]
	local fc = (fitem and fitem.color) or INK
	local faceRegions = FACE_HEADWEAR[face]
	if FACE_MESH[face] and headTemplates(face) then
		-- Build 41: a modelled face style of its own, in the item's colours (frame "main", glow
		-- "accent"), some of it animated (PULSE, BACK_ANIM).
		local fa = (fitem and fitem.accent) or fc
		for region in HEADWEAR[face] do
			headwear(face, region, fc, fa)
		end
	elseif faceRegions and headTemplates("Face") then
		-- Build 36: the Frost Goggles (pass tier 45) have a white frame and a glossy lens that
		-- runs light blue to dark blue (a painted texture, assets/headwear/frost_goggles_lens.png).
		local frost = look.face == "s1_frostgoggles"
		-- (Build 41: the Lava Goggles are a modelled style of their own now, FACE_MESH.)
		for _, region in faceRegions do
			local p = headwear("Face", region, if frost then Color3.fromRGB(248, 250, 255) else fc, fc)
			if frost and p and region == "GogglesLens" then
				p.Color = Color3.fromRGB(70, 150, 235)
				p.Material = Enum.Material.SmoothPlastic
				p.Reflectance = 0.2
				local glaze = Instance.new("Decal")
				glaze.Texture = "rbxassetid://139582449239872"
				glaze.Face = Enum.NormalId.Front
				glaze.Parent = p
			end
		end
	elseif modelled and face == "shades" then
		cosmetic("FaceShades", fc)
	elseif modelled and face == "glasses" then
		cosmetic("FaceSpecs", fc)
		local lens = cosmetic("FaceSpecsLens", Color3.fromRGB(215, 234, 250))
		if lens then
			lens.Transparency = 0.45
			lens.CastShadow = false
		end
	elseif modelled and face == "mustache" then
		cosmetic("FaceStache", fc)
	elseif modelled and face == "rednose" then
		cosmetic("FaceNose", fc)
	elseif face == "shades" then
		add(part(model, "Shades", Vector3.new(2.5, 0.62, 0.35), fc, "egg"), faceAt(0, HY + 0.02, 0.02))
	elseif face == "glasses" then
		for _, x in { -0.58, 0.58 } do
			local y = HY
			local lens = part(model, "Lens", Vector3.new(0.08, 0.85, 0.85), fc, "cyl")
			lens.Transparency = 0.15
			add(lens, faceAt(x, y, -0.06) * FACING)
			local glass = part(model, "Glass", Vector3.new(0.1, 0.62, 0.62), Color3.fromRGB(220, 236, 250), "cyl")
			glass.Transparency = 0.35
			add(glass, faceAt(x, y, -0.09) * FACING)
		end
	elseif face == "mustache" then
		for _, x in { -0.32, 0.32 } do
			add(part(model, "Stache", Vector3.new(0.85, 0.36, 0.36), fc, "egg"), faceAt(x, HY - 0.4, 0.04) * CFrame.Angles(0, 0, x * 0.6))
		end
	elseif face == "rednose" then
		add(part(model, "Nose", Vector3.new(0.6, 0.6, 0.6), fc, "ball"), faceAt(0, HY - 0.25, 0.12))
	end

	liftFromHead()

	-- Hockey gloves (posed every frame by the animator): the modelled glove with its cuff in the
	-- jersey colour, or round padded mitts when the meshes are missing.
	local gloveA: BasePart, gloveB: BasePart, cuffA: BasePart, cuffB: BasePart
	local gloveCentre, cuffCentre = Vector3.zero, Vector3.zero
	local meshA = gear(model, "Glove", kit.glove)
	if meshA then
		gloveA = meshA
		gloveB = gear(model, "Glove", kit.glove) :: MeshPart
		local cuffColor = if outfit then outfit.cuff else kit.jersey
		cuffA = gear(model, "GloveCuff", cuffColor) :: MeshPart
		cuffB = gear(model, "GloveCuff", cuffColor) :: MeshPart
		for _, p in { gloveA, gloveB, cuffA, cuffB } do
			p.Size *= GLOVE_SCALE
		end
		gloveCentre, cuffCentre = GEAR_CENTRE.Glove * GLOVE_SCALE, GEAR_CENTRE.GloveCuff * GLOVE_SCALE
	else
		gloveA = part(model, "GloveA", Vector3.new(1.15, 1.05, 1.3), kit.glove, "egg")
		gloveB = part(model, "GloveB", Vector3.new(1.05, 0.98, 1.2), kit.glove, "egg")
		cuffA = part(model, "CuffA", Vector3.new(0.1, 0.1, 0.1), kit.jersey)
		cuffB = part(model, "CuffB", Vector3.new(0.1, 0.1, 0.1), kit.jersey)
		cuffA.Transparency, cuffB.Transparency = 1, 1
	end
	gloveA.Name, gloveB.Name, cuffA.Name, cuffB.Name = "GloveA", "GloveB", "CuffA", "CuffB"
	if finish then
		for _, p in { gloveA, gloveB, cuffA, cuffB } do
			if p.Transparency < 1 then
				applyFinish(finish, p)
			end
		end
	end

	-- The stick lives in its own sub-model, so the see-through outline can adorn just the stick.
	local stickModel = Instance.new("Model")
	stickModel.Name = "Stick"
	stickModel.Parent = model
	local stickItem = Catalog.ById[look.stick]
	local style = (stickItem and stickItem.style) or "classic"
	local builder = Looks.STICK_STYLES[style] or Looks.STICK_STYLES.classic
	local stick = builder(stickModel, stickItem)
	for _, piece in stick do
		piece.part.CastShadow = false
		notePulse(style, piece.part.Name, piece.part)
	end

	-- Team ring on the ice: a coloured disc with an ice-coloured centre reads as a ring.
	local ringOuter = part(model, "RingOuter", Vector3.new(0.06, 5.0, 5.0), kit.ring, "cyl")
	local ringInner = part(model, "RingInner", Vector3.new(0.07, 3.7, 3.7), ICE, "cyl")
	for _, p in { ringOuter, ringInner } do
		p.CastShadow = false
	end

	-- Shrink the body, mitts and ring about the feet (the stick keeps its size: its blade is the
	-- sim's hitbox).
	local k = scale or 1
	local ringOffsets = { CFrame.new(0, 0.04, 0) * UPRIGHT, CFrame.new(0, 0.06, 0) * UPRIGHT }
	if k ~= 1 then
		for i, p in body do
			p.Size *= k
			offsets[i] = CFrame.new(offsets[i].Position * k) * offsets[i].Rotation
		end
		for _, p in { gloveA, gloveB, cuffA, cuffB } do
			p.Size *= k
		end
		for _, p in { ringOuter, ringInner } do
			p.Size = Vector3.new(p.Size.X, p.Size.Y * k, p.Size.Z * k)
		end
	end

	-- Build 40: the rig's animated pieces (after the shrink, so pivots and bob are to scale).
	local anim: RigAnim? = nil
	if #pulses > 0 or next(spinOf) ~= nil then
		local spins = {}
		for i, p in body do
			local moves = spinOf[p]
			if moves then
				table.insert(spins, {
					i = i,
					at = offsets[i].Position,
					rot = offsets[i].Rotation,
					axis = moves.axis,
					rate = moves.rate or 0,
					bob = (moves.bob or 0) * BOB_AMP * k,
					piv = if pivotOf[p] then pivotOf[p] * k else nil,
					swing = moves.swing,
				})
			end
		end
		anim = { spins = spins, pulses = pulses }
	end

	model.Parent = parent
	return {
		anim = anim,
		model = model,
		body = body,
		offsets = offsets,
		head = head,
		gloveA = gloveA,
		gloveB = gloveB,
		cuffA = cuffA,
		cuffB = cuffB,
		gloveOffset = CFrame.new(gloveCentre * k),
		cuffOffset = CFrame.new(cuffCentre * k),
		stick = stick,
		stickModel = stickModel,
		ring = { ringOuter, ringInner },
		ringOffsets = ringOffsets,
		look = look,
		team = team,
		scale = k,
	}
end

-- Stick styles. Each builder makes the visible pieces of one kind of stick inside `model` and
-- returns them; Looks.placeStick poses them every frame. The hitbox never changes: it is the
-- sim's blade, so a sword or a spatula plays exactly like the classic stick.
type StickBuilder = (model: Model, item: Catalog.Item?) -> { StickPiece }
Looks.STICK_STYLES = {} :: { [string]: StickBuilder }

-- Classic: a squared-off shaft and a tall, flat, rectangular blade (like a toy hockey stick),
-- with tape wrapped round most of the blade so its dark ends show at the heel and the toe, and
-- grip tape and a cap at the top of the shaft. Plain boxes, so it reads chunky from the camera.
Looks.STICK_STYLES.classic = function(model: Model, item: Catalog.Item?): { StickPiece }
	local shaftColor = (item and item.color) or INK
	-- Default blade is dark carbon so it reads against white ice; shop sticks keep their accent.
	local bladeColor = (item and item.accent) or Color3.fromRGB(40, 42, 52)
	local tapeColor = if bladeColor == WHITE or bladeColor == ICE or bladeColor.R + bladeColor.G + bladeColor.B > 2.4 then INK else WHITE
	local size = Looks.BLADE_SIZE
	local T, H, L = size.X, size.Y, size.Z
	local W, D = Looks.SHAFT_W, Looks.SHAFT_D
	local pieces: { StickPiece } = {}
	local function onShaft(name: string, sz: Vector3, color: Color3, at: CFrame, fromButt: number?, fromHeel: number?, stretch: boolean?)
		table.insert(pieces, { part = part(model, name, sz, color), on = "shaft", at = at, fromButt = fromButt, fromHeel = fromHeel, stretch = stretch })
	end
	local function onBlade(name: string, sz: Vector3, color: Color3, at: CFrame)
		table.insert(pieces, { part = part(model, name, sz, color), on = "blade", at = at })
	end

	-- Shaft pieces run along X; ALONG_Z lays them down the shaft. The shaft is wider across the
	-- blade's face than it is deep.
	onShaft("Shaft", Vector3.new(4, W, D), shaftColor, ALONG_Z, nil, nil, true)
	onShaft("Grip", Vector3.new(1.1, W + 0.06, D + 0.06), tapeColor, ALONG_Z, 0.55)
	onShaft("Cap", Vector3.new(0.16, W + 0.1, D + 0.1), shaftColor, ALONG_Z, 0.02)

	-- Blade frame: -Z runs from the heel (by the body) out to the toe, +Y is up, X is the
	-- thickness. The heel half is straight; the toe half bends a touch toward +X (the puck side),
	-- matching the sim's blade shape. The tape leaves a dark strip at each end.
	local curve = GameConfig.Stick.BladeCurve
	local half = L / 2
	local toeTurn = math.atan2(curve, half)
	local toeLen = math.sqrt(half * half + curve * curve)
	-- The toe box starts at the blade's middle and turns about it; a little overlap hides the joint.
	local toeFrame = CFrame.Angles(0, -toeTurn, 0)
	onBlade("Blade", Vector3.new(T, H, half + 0.04), bladeColor, CFrame.new(0, 0, half / 2 - 0.02))
	onBlade("BladeToe", Vector3.new(T, H, toeLen), bladeColor, toeFrame * CFrame.new(0, 0, -toeLen / 2))
	onBlade("BladeTape", Vector3.new(T + 0.04, H - 0.1, L * 0.34), tapeColor, CFrame.new(0, 0, L * 0.17))
	onBlade("BladeTapeToe", Vector3.new(T + 0.04, H - 0.1, L * 0.4), tapeColor, toeFrame * CFrame.new(0, 0, -L * 0.2))
	-- Where the shaft meets the blade: a block on top of the heel.
	onBlade("Hosel", Vector3.new(T + 0.06, 0.36, 0.5), bladeColor, CFrame.new(0, H / 2 + 0.1, L / 2 - 0.3))
	return pieces
end

-- Modelled sticks (assets/sticks/sticks.py, built in Blender). Each style is a folder of MeshPart
-- templates in ReplicatedStorage.StickMeshes (cloud place only, like GearMeshes), one per colour
-- region. Each row: region, the frame it rides in, its mesh centre in that frame, colour,
-- material, transparency. Frames: "blade" = the blade frame; "butt" = the shaft frame at the
-- butt (-Z down the shaft); "heel" = the same frame, modelled on a 4.2-stud shaft and kept at
-- that distance from the heel; "stretch" = spans the shaft and is resized to its length.
-- Without the templates a modelled stick falls back to the classic one.
local MODEL_SHAFT = 4.2
type MeshRow = { any }
local STICK_MESHES: { [string]: { MeshRow } } = {
	OldTimber = {
		{ "Wood", "blade", Vector3.new(0, 0.1, -0.015), Color3.fromRGB(204, 153, 97), Enum.Material.Wood },
		{ "Laminate", "blade", Vector3.new(0, 0.15, 0.0625), Color3.fromRGB(107, 66, 38), Enum.Material.Wood },
		{ "Tape", "blade", Vector3.new(0, -0.07, -0.2575), Color3.fromRGB(26, 26, 31), Enum.Material.Fabric },
		{ "Brass", "blade", Vector3.new(0, 0.26, 0.835), Color3.fromRGB(214, 168, 71), Enum.Material.Metal },
		{ "Shaft", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(204, 153, 97), Enum.Material.Wood },
		{ "Grain", "stretch", Vector3.new(0, 0, 0.014), Color3.fromRGB(107, 66, 38), Enum.Material.Wood },
		{ "Knob", "butt", Vector3.new(0, 0, -0.4153), Color3.fromRGB(242, 240, 230), Enum.Material.Fabric },
		{ "Collar", "heel", Vector3.new(0, 0, -4.035), Color3.fromRGB(107, 66, 38), Enum.Material.Wood },
	},
	Ripsaw = {
		{ "Bar", "blade", Vector3.new(0, -0.18, -0.25), Color3.fromRGB(178, 184, 194), Enum.Material.Metal },
		{ "BarInlay", "blade", Vector3.new(0, -0.18, -0.24), Color3.fromRGB(64, 66, 76), Enum.Material.Metal },
		{ "Chain", "blade", Vector3.new(0, -0.18, -0.3343), Color3.fromRGB(76, 79, 87), Enum.Material.Metal },
		{ "Engine", "blade", Vector3.new(0, 0.0573, 1), Color3.fromRGB(250, 115, 20), Enum.Material.SmoothPlastic },
		{ "EngineDark", "blade", Vector3.new(0, 0.2088, 1.0134), Color3.fromRGB(26, 26, 28), Enum.Material.SmoothPlastic },
		{ "EngineMetal", "blade", Vector3.new(0.01, -0.12, 0.1075), Color3.fromRGB(140, 143, 153), Enum.Material.Metal },
		{ "Stripe", "blade", Vector3.new(0, -0.265, 1), Color3.fromRGB(245, 245, 245), Enum.Material.SmoothPlastic },
		{ "Handle", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(26, 26, 28), Enum.Material.SmoothPlastic },
		{ "Trigger", "butt", Vector3.new(0, -0.035, -0.41), Color3.fromRGB(217, 31, 26), Enum.Material.SmoothPlastic },
		{ "Grip", "butt", Vector3.new(0, -0.1164, -0.49), Color3.fromRGB(250, 115, 20), Enum.Material.SmoothPlastic },
		{ "Collar", "heel", Vector3.new(0, 0, -4.025), Color3.fromRGB(250, 115, 20), Enum.Material.SmoothPlastic },
	},
	FrostFang = {
		{ "Steel", "blade", Vector3.new(0, -0.03, -0.175), Color3.fromRGB(199, 209, 224), Enum.Material.Metal },
		{ "Fuller", "blade", Vector3.new(0, 0.3209, 0.2), Color3.fromRGB(92, 102, 120), Enum.Material.Metal },
		{ "Edge", "blade", Vector3.new(0, -0.4228, -0.0887), Color3.fromRGB(140, 224, 255), Enum.Material.Neon },
		{ "Guard", "blade", Vector3.new(0, 0.04, 1.1413), Color3.fromRGB(61, 66, 79), Enum.Material.Metal },
		{ "Gem", "blade", Vector3.new(0, 0.05, 1.17), Color3.fromRGB(115, 217, 255), Enum.Material.Neon },
		{ "Grip", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(66, 43, 31), Enum.Material.Fabric },
		{ "Wrap", "butt", Vector3.new(0, 0, -0.67), Color3.fromRGB(31, 102, 122), Enum.Material.Fabric },
		{ "Pommel", "butt", Vector3.new(0, 0, 0.13), Color3.fromRGB(61, 66, 79), Enum.Material.Metal },
		{ "Bolster", "heel", Vector3.new(0, 0, -4.05), Color3.fromRGB(61, 66, 79), Enum.Material.Metal },
	},
	Shredder = {
		{ "Body", "blade", Vector3.new(0, 0.0908, 0.0051), Color3.fromRGB(204, 20, 36), Enum.Material.SmoothPlastic },
		{ "Pickguard", "blade", Vector3.new(0, 0.0939, 0.3454), Color3.fromRGB(247, 247, 242), Enum.Material.SmoothPlastic },
		{ "Chrome", "blade", Vector3.new(0, -0.0445, -0.3065), Color3.fromRGB(219, 224, 235), Enum.Material.Metal },
		{ "Pickups", "blade", Vector3.new(0, -0.0086, -0.2864), Color3.fromRGB(20, 20, 23), Enum.Material.SmoothPlastic },
		{ "Strings", "blade", Vector3.new(-0.0018, 0.261, 0.2444), Color3.fromRGB(230, 230, 224), Enum.Material.Metal },
		{ "Neck", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(235, 191, 128), Enum.Material.Wood },
		{ "Fretboard", "stretch", Vector3.new(0, 0.225, 0), Color3.fromRGB(61, 36, 26), Enum.Material.Wood },
		{ "Frets", "stretch", Vector3.new(0, 0.26, 0), Color3.fromRGB(219, 224, 235), Enum.Material.Metal },
		{ "Inlays", "stretch", Vector3.new(0.032, 0.252, 0), Color3.fromRGB(247, 245, 235), Enum.Material.SmoothPlastic },
		{ "NeckStrings", "stretch", Vector3.new(0, 0.29, 0.0044), Color3.fromRGB(230, 230, 224), Enum.Material.Metal },
		{ "Headstock", "butt", Vector3.new(-0.0092, 0.02, 0.5041), Color3.fromRGB(204, 20, 36), Enum.Material.SmoothPlastic },
		{ "Pegs", "butt", Vector3.new(-0.02, 0.15, 0.39), Color3.fromRGB(219, 224, 235), Enum.Material.Metal },
		{ "NeckPlate", "heel", Vector3.new(0, 0, -4.09), Color3.fromRGB(219, 224, 235), Enum.Material.Metal },
	},
	PlasmaSaber = {
		{ "Core", "blade", Vector3.new(0, 0, -0.15), Color3.fromRGB(235, 250, 255), Enum.Material.Neon },
		{ "Glow", "blade", Vector3.new(0, 0, -0.205), Color3.fromRGB(255, 64, 204), Enum.Material.Neon, 0.45 },
		{ "Emitter", "blade", Vector3.new(0, 0.05, 1.22), Color3.fromRGB(178, 184, 199), Enum.Material.Metal },
		{ "EmitterDark", "blade", Vector3.new(0, 0.025, 1.3), Color3.fromRGB(26, 26, 31), Enum.Material.SmoothPlastic },
		{ "Lights", "blade", Vector3.new(0, 0.05, 1.18), Color3.fromRGB(255, 64, 204), Enum.Material.Neon },
		{ "Hilt", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(153, 158, 173), Enum.Material.Metal },
		{ "GripRibs", "butt", Vector3.new(0, 0, -0.81), Color3.fromRGB(26, 26, 31), Enum.Material.SmoothPlastic },
		{ "Pommel", "butt", Vector3.new(0, 0, 0.1251), Color3.fromRGB(178, 184, 199), Enum.Material.Metal },
		{ "Jewel", "butt", Vector3.new(0, 0, 0.26), Color3.fromRGB(255, 64, 204), Enum.Material.Neon },
		{ "Button", "butt", Vector3.new(0, 0.215, -1.51), Color3.fromRGB(255, 38, 38), Enum.Material.Neon },
		{ "NeckRing", "heel", Vector3.new(0, 0, -4.01), Color3.fromRGB(178, 184, 199), Enum.Material.Metal },
	},
	DragonBone = {
		{ "Bone", "blade", Vector3.new(0, 0.0688, -0.015), Color3.fromRGB(235, 222, 189), Enum.Material.SmoothPlastic },
		{ "BoneDark", "blade", Vector3.new(0, 0.3347, 0.105), Color3.fromRGB(148, 122, 92), Enum.Material.SmoothPlastic },
		{ "Teeth", "blade", Vector3.new(0, -0.2564, -0.255), Color3.fromRGB(250, 245, 230), Enum.Material.SmoothPlastic },
		{ "Socket", "blade", Vector3.new(0, 0.1089, -0.12), Color3.fromRGB(33, 20, 18), Enum.Material.SmoothPlastic },
		{ "Eye", "blade", Vector3.new(0, 0.52, 0.55), Color3.fromRGB(255, 89, 13), Enum.Material.Neon },
		{ "Horn", "blade", Vector3.new(0, 0.98, 0.9536), Color3.fromRGB(56, 43, 36), Enum.Material.SmoothPlastic },
		{ "Shaft", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(235, 222, 189), Enum.Material.SmoothPlastic },
		{ "Spine", "butt", Vector3.new(0, 0.08, -0.715), Color3.fromRGB(235, 222, 189), Enum.Material.SmoothPlastic },
		{ "Claws", "butt", Vector3.new(0.004, -0.0814, 0.2729), Color3.fromRGB(56, 43, 36), Enum.Material.SmoothPlastic },
		{ "HeelSpine", "heel", Vector3.new(0, 0, -3.98), Color3.fromRGB(148, 122, 92), Enum.Material.SmoothPlastic },
	},
	SharkBite = {
		{ "Back", "blade", Vector3.new(0, 0.278, -0.2), Color3.fromRGB(107, 135, 163), Enum.Material.SmoothPlastic },
		{ "Belly", "blade", Vector3.new(0, -0.2396, -0.1207), Color3.fromRGB(242, 242, 240), Enum.Material.SmoothPlastic },
		{ "Fins", "blade", Vector3.new(0, 0.1407, 0.4673), Color3.fromRGB(92, 117, 145), Enum.Material.SmoothPlastic },
		{ "Mouth", "blade", Vector3.new(0, -0.2064, -1.0357), Color3.fromRGB(115, 18, 26), Enum.Material.SmoothPlastic },
		{ "Teeth", "blade", Vector3.new(0, -0.0893, -0.9875), Color3.fromRGB(255, 255, 247), Enum.Material.SmoothPlastic },
		{ "Eye", "blade", Vector3.new(0, 0.17, -1), Color3.fromRGB(13, 13, 15), Enum.Material.SmoothPlastic },
		{ "Gills", "blade", Vector3.new(0, 0.09, -0.48), Color3.fromRGB(61, 79, 97), Enum.Material.SmoothPlastic },
		{ "Rod", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(20, 46, 107), Enum.Material.SmoothPlastic },
		{ "Line", "stretch", Vector3.new(0, 0.28, -0.0013), Color3.fromRGB(191, 255, 51), Enum.Material.Neon },
		{ "Guides", "heel", Vector3.new(0, 0.2346, -3.275), Color3.fromRGB(204, 209, 219), Enum.Material.Metal },
		{ "Cork", "butt", Vector3.new(0, 0, -0.455), Color3.fromRGB(204, 158, 107), Enum.Material.Sand },
		{ "ButtCap", "butt", Vector3.new(0.105, -0.2688, -0.445), Color3.fromRGB(26, 26, 31), Enum.Material.SmoothPlastic },
		{ "Reel", "butt", Vector3.new(0.0538, -0.2878, -1.1164), Color3.fromRGB(76, 82, 92), Enum.Material.Metal },
		{ "Spool", "butt", Vector3.new(0, -0.52, -1.27), Color3.fromRGB(242, 184, 51), Enum.Material.Metal },
		{ "SpoolLine", "butt", Vector3.new(0, -0.52, -1.27), Color3.fromRGB(191, 255, 51), Enum.Material.Neon },
		{ "Ferrule", "heel", Vector3.new(0, 0, -4.05), Color3.fromRGB(26, 26, 31), Enum.Material.SmoothPlastic },
	},
	Peppermint = {
		{ "Candy", "blade", Vector3.new(0, 0, -0.01), Color3.fromRGB(250, 247, 242), Enum.Material.SmoothPlastic },
		{ "Stripes", "blade", Vector3.new(0, 0, 0), Color3.fromRGB(219, 20, 31), Enum.Material.SmoothPlastic },
		{ "Mint", "blade", Vector3.new(0, 0, -0.0075), Color3.fromRGB(31, 158, 76), Enum.Material.SmoothPlastic },
		{ "Ribbon", "blade", Vector3.new(0, 0.7784, 1.1), Color3.fromRGB(199, 10, 26), Enum.Material.SmoothPlastic },
		{ "Holly", "blade", Vector3.new(0, 0.821, 0.56), Color3.fromRGB(20, 107, 46), Enum.Material.SmoothPlastic },
		{ "Berries", "blade", Vector3.new(0, 0.77, 0.905), Color3.fromRGB(219, 20, 31), Enum.Material.SmoothPlastic },
		{ "Bell", "blade", Vector3.new(0, 0.82, 1.1), Color3.fromRGB(242, 191, 64), Enum.Material.Metal },
		{ "Shaft", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(250, 247, 242), Enum.Material.SmoothPlastic },
		{ "ShaftStripes", "stretch", Vector3.new(0.0275, 0, 0), Color3.fromRGB(219, 20, 31), Enum.Material.SmoothPlastic },
		{ "ShaftMint", "stretch", Vector3.new(-0.0345, 0, 0), Color3.fromRGB(31, 158, 76), Enum.Material.SmoothPlastic },
		{ "Crook", "butt", Vector3.new(0, 0.38, 0.4148), Color3.fromRGB(250, 247, 242), Enum.Material.SmoothPlastic },
		{ "CrookStripes", "butt", Vector3.new(-0.0002, 0.319, 0.3933), Color3.fromRGB(219, 20, 31), Enum.Material.SmoothPlastic },
		{ "Collar", "heel", Vector3.new(0, 0, -4.12), Color3.fromRGB(219, 20, 31), Enum.Material.SmoothPlastic },
	},
	Trident = {
		{ "Gold", "blade", Vector3.new(0, 0.1074, -0.0505), Color3.fromRGB(255, 199, 64), Enum.Material.Metal },
		{ "Engraving", "blade", Vector3.new(0, 0.08, 0.8175), Color3.fromRGB(158, 107, 26), Enum.Material.Metal },
		{ "Shell", "blade", Vector3.new(0, 0.08, 1.1), Color3.fromRGB(255, 219, 204), Enum.Material.SmoothPlastic },
		{ "Pearls", "blade", Vector3.new(0, 0.08, 1.24), Color3.fromRGB(247, 245, 255), Enum.Material.SmoothPlastic },
		{ "Gems", "blade", Vector3.new(0, 0.45, 0.841), Color3.fromRGB(26, 242, 217), Enum.Material.Neon },
		{ "Shaft", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(255, 199, 64), Enum.Material.Metal },
		{ "Wrap", "butt", Vector3.new(0, 0, -0.65), Color3.fromRGB(13, 140, 140), Enum.Material.Fabric },
		{ "Finial", "butt", Vector3.new(0, 0, 0.15), Color3.fromRGB(255, 199, 64), Enum.Material.Metal },
		{ "FinialPearl", "butt", Vector3.new(0, 0, 0.48), Color3.fromRGB(247, 245, 255), Enum.Material.SmoothPlastic },
		{ "Collar", "heel", Vector3.new(0, 0, -4.02), Color3.fromRGB(255, 199, 64), Enum.Material.Metal },
		{ "CollarGems", "heel", Vector3.new(0, 0, -4.01), Color3.fromRGB(26, 242, 217), Enum.Material.Neon },
	},
	RoboClaw = {
		{ "Armor", "blade", Vector3.new(0, 0.09, 0.785), Color3.fromRGB(71, 76, 87), Enum.Material.Metal },
		{ "Panels", "blade", Vector3.new(0, 0.08, 0.114), Color3.fromRGB(33, 36, 41), Enum.Material.SmoothPlastic },
		{ "Hazard", "blade", Vector3.new(0, 0, 0.1), Color3.fromRGB(255, 199, 26), Enum.Material.SmoothPlastic },
		{ "Joints", "blade", Vector3.new(0, 0, 0.25), Color3.fromRGB(26, 26, 31), Enum.Material.SmoothPlastic },
		{ "Chrome", "blade", Vector3.new(0, 0.0352, -0.0975), Color3.fromRGB(209, 214, 224), Enum.Material.Metal },
		{ "Lights", "blade", Vector3.new(0, 0.0762, 0.215), Color3.fromRGB(51, 242, 255), Enum.Material.Neon },
		{ "Arm", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(71, 76, 87), Enum.Material.Metal },
		{ "ArmLights", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(51, 242, 255), Enum.Material.Neon },
		{ "Cables", "stretch", Vector3.new(0, 0.235, 0), Color3.fromRGB(242, 97, 20), Enum.Material.SmoothPlastic },
		{ "Cell", "butt", Vector3.new(0, 0, -0.05), Color3.fromRGB(209, 214, 224), Enum.Material.Metal },
		{ "Core", "butt", Vector3.new(0, 0, 0.0252), Color3.fromRGB(51, 242, 255), Enum.Material.Neon },
		{ "Grip", "butt", Vector3.new(0, 0, -0.865), Color3.fromRGB(26, 26, 31), Enum.Material.SmoothPlastic },
		{ "Wrist", "heel", Vector3.new(0, 0, -4.05), Color3.fromRGB(26, 26, 31), Enum.Material.SmoothPlastic },
		{ "WristBolts", "heel", Vector3.new(0, 0, -4.05), Color3.fromRGB(209, 214, 224), Enum.Material.Metal },
	},
	-- Shop sticks (sold for coins): assets/sticks/shopsticks.py.
	Spatula = {
		{ "Steel", "blade", Vector3.new(0, 0.11, -0.01), Color3.fromRGB(204, 209, 219), Enum.Material.Metal },
		{ "Slots", "blade", Vector3.new(0, 0, -0.25), Color3.fromRGB(41, 43, 51), Enum.Material.SmoothPlastic },
		{ "Rivets", "blade", Vector3.new(0, 0, 0.95), Color3.fromRGB(158, 163, 173), Enum.Material.Metal },
		{ "Handle", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(219, 41, 36), Enum.Material.SmoothPlastic },
		{ "Grip", "butt", Vector3.new(0, 0, -0.45), Color3.fromRGB(178, 26, 26), Enum.Material.SmoothPlastic },
		{ "HangRing", "butt", Vector3.new(0, 0, 0.2), Color3.fromRGB(204, 209, 219), Enum.Material.Metal },
		{ "Neck", "heel", Vector3.new(0, 0, -4.015), Color3.fromRGB(204, 209, 219), Enum.Material.Metal },
	},
	Baguette = {
		{ "Crust", "blade", Vector3.new(0, 0.05, 0), Color3.fromRGB(189, 117, 51), Enum.Material.SmoothPlastic },
		{ "Crumb", "blade", Vector3.new(0, 0.036, 0), Color3.fromRGB(250, 230, 184), Enum.Material.SmoothPlastic },
		{ "Butter", "blade", Vector3.new(0.2025, 0.1063, -0.1387), Color3.fromRGB(255, 219, 92), Enum.Material.SmoothPlastic },
		{ "Loaf", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(204, 133, 56), Enum.Material.SmoothPlastic },
		{ "Scores", "stretch", Vector3.new(-0.0025, 0.2365, 0), Color3.fromRGB(242, 199, 122), Enum.Material.SmoothPlastic },
		{ "LoafEnd", "butt", Vector3.new(0, 0, -0.05), Color3.fromRGB(184, 112, 46), Enum.Material.SmoothPlastic },
		{ "Twine", "heel", Vector3.new(0, 0, -4.005), Color3.fromRGB(235, 224, 204), Enum.Material.Fabric },
	},
	CurlingBroom = {
		{ "Pad", "blade", Vector3.new(0, -0.425, 0), Color3.fromRGB(209, 31, 41), Enum.Material.Fabric },
		{ "Housing", "blade", Vector3.new(0, 0.47, 0), Color3.fromRGB(26, 26, 31), Enum.Material.SmoothPlastic },
		{ "Trim", "blade", Vector3.new(0, 0.065, 0), Color3.fromRGB(242, 242, 245), Enum.Material.SmoothPlastic },
		{ "Shaft", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(26, 26, 31), Enum.Material.SmoothPlastic },
		{ "Stripe", "stretch", Vector3.new(-0.055, 0, 0), Color3.fromRGB(209, 31, 41), Enum.Material.SmoothPlastic },
		{ "Foam", "butt", Vector3.new(0, 0, -0.5915), Color3.fromRGB(51, 51, 61), Enum.Material.Fabric },
		{ "Swivel", "heel", Vector3.new(0, 0, -4.0527), Color3.fromRGB(178, 184, 194), Enum.Material.Metal },
	},
	Bamboo = {
		{ "Slats", "blade", Vector3.new(0, 0.1, 0.0025), Color3.fromRGB(158, 178, 76), Enum.Material.Wood },
		{ "Lashing", "blade", Vector3.new(0, 0.03, 0), Color3.fromRGB(92, 56, 31), Enum.Material.Fabric },
		{ "Cane", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(115, 168, 66), Enum.Material.Wood },
		{ "Nodes", "stretch", Vector3.new(-0.0275, 0, 0), Color3.fromRGB(87, 133, 46), Enum.Material.Wood },
		{ "Leaves", "butt", Vector3.new(0.3417, -0.04, 0.1829), Color3.fromRGB(61, 158, 56), Enum.Material.SmoothPlastic },
		{ "Top", "butt", Vector3.new(0, 0, 0), Color3.fromRGB(87, 133, 46), Enum.Material.Wood },
		{ "Rope", "heel", Vector3.new(0, 0, -4.0025), Color3.fromRGB(92, 56, 31), Enum.Material.Fabric },
	},
	VikingOar = {
		{ "OarWood", "blade", Vector3.new(0, 0.0788, 0.0605), Color3.fromRGB(148, 97, 56), Enum.Material.Wood },
		{ "Paint", "blade", Vector3.new(0, -0.035, -0.29), Color3.fromRGB(199, 36, 31), Enum.Material.SmoothPlastic },
		{ "PaintLight", "blade", Vector3.new(0, -0.035, -0.29), Color3.fromRGB(240, 230, 204), Enum.Material.SmoothPlastic },
		{ "Iron", "blade", Vector3.new(0, -0.05, -0.1646), Color3.fromRGB(76, 79, 87), Enum.Material.Metal },
		{ "Loom", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(102, 64, 38), Enum.Material.Wood },
		{ "Rings", "stretch", Vector3.new(-0.035, 0, 0), Color3.fromRGB(76, 79, 87), Enum.Material.Metal },
		{ "Knob", "butt", Vector3.new(0, 0, -0.065), Color3.fromRGB(102, 64, 38), Enum.Material.Wood },
		{ "Collar", "heel", Vector3.new(0, 0, -4.035), Color3.fromRGB(76, 79, 87), Enum.Material.Metal },
	},
	Thunderbolt = {
		{ "Frame", "blade", Vector3.new(0, 0.1, 0), Color3.fromRGB(56, 59, 71), Enum.Material.Metal },
		{ "Bolt", "blade", Vector3.new(0, -0.02, -0.1), Color3.fromRGB(255, 219, 31), Enum.Material.Neon },
		{ "Shaft", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(46, 48, 61), Enum.Material.Metal },
		{ "GlowStripe", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(255, 219, 31), Enum.Material.Neon },
		{ "Cloud", "butt", Vector3.new(0.0001, 0.04, -0.064), Color3.fromRGB(107, 112, 133), Enum.Material.SmoothPlastic },
		{ "Collar", "heel", Vector3.new(0, 0, -4.085), Color3.fromRGB(255, 219, 31), Enum.Material.Neon },
	},
	-- Build 26 shop sticks (assets/sticks/shopsticks3.py, out_b26).
	Banana = {
		{ "Peel", "blade", Vector3.new(0.0183, -0.0184, -0.1), Color3.fromRGB(252, 214, 46), Enum.Material.SmoothPlastic },
		{ "Tips", "blade", Vector3.new(0, 0.5511, -0.1356), Color3.fromRGB(92, 64, 36), Enum.Material.SmoothPlastic },
		{ "Spots", "blade", Vector3.new(0, -0.2116, -0.15), Color3.fromRGB(140, 97, 41), Enum.Material.SmoothPlastic },
		{ "Stem", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(237, 219, 107), Enum.Material.SmoothPlastic },
		{ "StemCap", "butt", Vector3.new(0, 0, -0.075), Color3.fromRGB(107, 76, 41), Enum.Material.SmoothPlastic },
		{ "Sticker", "heel", Vector3.new(0, 0, -3.3), Color3.fromRGB(51, 117, 235), Enum.Material.SmoothPlastic },
	},
	HotDog = {
		{ "Bun", "blade", Vector3.new(0, 0.1645, -0.04), Color3.fromRGB(219, 153, 76), Enum.Material.SmoothPlastic },
		{ "Crumb", "blade", Vector3.new(0, -0.15, -0.165), Color3.fromRGB(250, 224, 168), Enum.Material.SmoothPlastic },
		{ "Sausage", "blade", Vector3.new(0, 0.06, -0.175), Color3.fromRGB(184, 66, 41), Enum.Material.SmoothPlastic },
		{ "Mustard", "blade", Vector3.new(0, 0.27, -0.165), Color3.fromRGB(255, 209, 26), Enum.Material.SmoothPlastic },
		{ "Skewer", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(224, 184, 128), Enum.Material.Wood },
		{ "Wrap", "butt", Vector3.new(0, 0, -0.455), Color3.fromRGB(219, 36, 41), Enum.Material.SmoothPlastic },
		{ "WrapCheck", "butt", Vector3.new(0, 0, -0.51), Color3.fromRGB(247, 247, 245), Enum.Material.SmoothPlastic },
		{ "Ketchup", "heel", Vector3.new(0.024, -0.0625, -3.915), Color3.fromRGB(219, 36, 41), Enum.Material.SmoothPlastic },
	},
	-- Build 29 tutorial reward (assets/sticks/rookiestick.py, out_b29), replacing the Foam Finger.
	-- Build 30: the tutorial reward, Golden Comet (assets/sticks/cometstick.py, out_b30). Replaces
	-- Build 29's Rookie Gold, which read as dark and muddy.
	GoldenComet = {
		{ "Blade", "blade", Vector3.new(0, 0.11, -0.0232), Color3.fromRGB(255, 196, 46), Enum.Material.Metal },
		{ "Hosel", "blade", Vector3.new(0, 0.775, 1.1457), Color3.fromRGB(15, 17, 20), Enum.Material.SmoothPlastic },
		{ "IceEdge", "blade", Vector3.new(0, -0.745, 0.15), Color3.fromRGB(38, 217, 255), Enum.Material.Neon },
		{ "Streak", "blade", Vector3.new(0, 0.1529, 0.068), Color3.fromRGB(38, 217, 255), Enum.Material.Neon },
		{ "Star", "blade", Vector3.new(0, 0.0579, -0.7311), Color3.fromRGB(237, 250, 255), Enum.Material.Neon },
		{ "Shaft", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(242, 242, 245), Enum.Material.SmoothPlastic },
		{ "Stripe", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(38, 217, 255), Enum.Material.Neon },
		{ "Chevrons", "heel", Vector3.new(0, 0, -3.37), Color3.fromRGB(255, 196, 46), Enum.Material.Metal },
		{ "Collar", "heel", Vector3.new(0, 0, -4.04), Color3.fromRGB(15, 17, 20), Enum.Material.SmoothPlastic },
		{ "CollarGlow", "heel", Vector3.new(0, 0, -4.04), Color3.fromRGB(38, 217, 255), Enum.Material.Neon },
		{ "Grip", "butt", Vector3.new(0, 0, -0.405), Color3.fromRGB(15, 17, 20), Enum.Material.Fabric },
		{ "Cap", "butt", Vector3.new(0, 0, -0.005), Color3.fromRGB(255, 196, 46), Enum.Material.Metal },
		{ "Gem", "butt", Vector3.new(0, 0, 0.085), Color3.fromRGB(38, 217, 255), Enum.Material.Neon },
	},
	-- Build 40 first-full-match reward (assets/sticks/novastick.py, out_b40n): the Nova Blade. Its
	-- rim pulses and it throws sparks (meshStick).
	NovaBlade = {
		{ "Blade", "blade", Vector3.new(0, 0.1, -0.03), NOVA_GRAPH, Enum.Material.SmoothPlastic },
		{ "Edge", "blade", Vector3.new(0, 0.1, -0.03), NOVA_CYAN, Enum.Material.Neon },
		{ "Inlay", "blade", Vector3.new(0, -0.18, -0.27), NOVA_MAG, Enum.Material.Neon },
		{ "Armor", "blade", Vector3.new(0, 0.25, 0.9086), NOVA_GUN, Enum.Material.Metal },
		{ "Shaft", "stretch", Vector3.new(0, 0, 0), NOVA_GRAPH, Enum.Material.SmoothPlastic },
		{ "ShaftGlow", "stretch", Vector3.new(0, 0, 0), NOVA_CYAN, Enum.Material.Neon },
		{ "Bands", "heel", Vector3.new(0, 0, -3.765), NOVA_GUN, Enum.Material.Metal },
		{ "BandGlow", "heel", Vector3.new(0, 0, -3.545), NOVA_CYAN, Enum.Material.Neon },
		{ "Grip", "butt", Vector3.new(0, 0, -0.45), NOVA_GRAPH, Enum.Material.Fabric },
		{ "Cap", "butt", Vector3.new(0, 0, -0.005), NOVA_GUN, Enum.Material.Metal },
		{ "Gem", "butt", Vector3.new(0, 0, 0.1), NOVA_MAG, Enum.Material.Neon },
	},
	-- Build 41 animated season-pass sticks (assets/sticks/passsticks41.py, out_b41): the Toxic,
	-- Carbon and Champion Gold sticks remade. Their neon pulses (PULSE) and each throws its own
	-- particles (meshStick).
	ToxicSludge = {
		{ "Casing", "blade", Vector3.new(0, 0.15, 0.0005), Color3.fromRGB(43, 48, 51), Enum.Material.Metal },
		{ "Frame", "blade", Vector3.new(0, -0.175, 0.035), Color3.fromRGB(18, 20, 20), Enum.Material.SmoothPlastic },
		{ "Bolts", "blade", Vector3.new(0, -0.175, -0.3), Color3.fromRGB(120, 128, 132), Enum.Material.Metal },
		{ "Goo", "blade", Vector3.new(0, -0.2268, -0.3), Color3.fromRGB(110, 245, 50), Enum.Material.Neon },
		{ "Glass", "blade", Vector3.new(0, -0.175, -0.3), Color3.fromRGB(191, 255, 204), Enum.Material.Glass, 0.6 },
		{ "Bubbles", "blade", Vector3.new(0, -0.25, -0.285), Color3.fromRGB(200, 255, 110), Enum.Material.Neon },
		{ "Ooze", "blade", Vector3.new(0, 0.3707, -0.2614), Color3.fromRGB(110, 245, 50), Enum.Material.Neon },
		{ "Hazard", "blade", Vector3.new(0, -0.19, 0.99), Color3.fromRGB(255, 204, 26), Enum.Material.SmoothPlastic },
		{ "Shaft", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(18, 20, 20), Enum.Material.SmoothPlastic },
		{ "Tube", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(191, 255, 204), Enum.Material.Glass, 0.55 },
		{ "ShaftGlow", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(110, 245, 50), Enum.Material.Neon },
		{ "Bands", "heel", Vector3.new(0, 0, -3.75), Color3.fromRGB(43, 48, 51), Enum.Material.Metal },
		{ "BandGlow", "heel", Vector3.new(0, 0, -3.545), Color3.fromRGB(110, 245, 50), Enum.Material.Neon },
		{ "Grip", "butt", Vector3.new(0, 0, -0.4479), Color3.fromRGB(18, 20, 20), Enum.Material.Fabric },
		{ "Cap", "butt", Vector3.new(0, 0, -0.005), Color3.fromRGB(43, 48, 51), Enum.Material.Metal },
		{ "Gem", "butt", Vector3.new(0, 0, 0.1), Color3.fromRGB(110, 245, 50), Enum.Material.Neon },
	},
	CarbonStrike = {
		{ "Blade", "blade", Vector3.new(0, 0.1, -0.03), Color3.fromRGB(18, 18, 22), Enum.Material.SmoothPlastic },
		{ "Weave", "blade", Vector3.new(0, -0.2425, -0.25), Color3.fromRGB(38, 38, 46), Enum.Material.SmoothPlastic },
		{ "Circuit", "blade", Vector3.new(0, -0.1752, -0.05), Color3.fromRGB(255, 31, 51), Enum.Material.Neon },
		{ "Edge", "blade", Vector3.new(0, -0.69, 0.0913), Color3.fromRGB(255, 31, 51), Enum.Material.Neon },
		{ "Fins", "blade", Vector3.new(0, 0.22, 0.1601), Color3.fromRGB(204, 209, 219), Enum.Material.Metal },
		{ "Shaft", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(18, 18, 22), Enum.Material.SmoothPlastic },
		{ "ShaftGlow", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(255, 31, 51), Enum.Material.Neon },
		{ "Bands", "heel", Vector3.new(0, 0, -3.765), Color3.fromRGB(204, 209, 219), Enum.Material.Metal },
		{ "BandGlow", "heel", Vector3.new(0, 0, -3.545), Color3.fromRGB(255, 31, 51), Enum.Material.Neon },
		{ "Grip", "butt", Vector3.new(0, 0, -0.45), Color3.fromRGB(18, 18, 22), Enum.Material.Fabric },
		{ "Cap", "butt", Vector3.new(0, 0, -0.005), Color3.fromRGB(204, 209, 219), Enum.Material.Metal },
		{ "Gem", "butt", Vector3.new(0, 0, 0.1), Color3.fromRGB(255, 31, 51), Enum.Material.Neon },
	},
	ChampionGold = {
		{ "Blade", "blade", Vector3.new(0, 0.15, 0.0008), Color3.fromRGB(255, 184, 20), Enum.Material.Metal },
		{ "Rim", "blade", Vector3.new(0, 0.1, -0.0192), Color3.fromRGB(128, 74, 13), Enum.Material.Metal },
		{ "Medal", "blade", Vector3.new(0, -0.2, 0.305), Color3.fromRGB(26, 26, 31), Enum.Material.SmoothPlastic },
		{ "Star", "blade", Vector3.new(0, -0.2043, -0.3548), Color3.fromRGB(255, 247, 209), Enum.Material.Neon },
		{ "Laurel", "blade", Vector3.new(0, -0.2268, -0.35), Color3.fromRGB(255, 242, 204), Enum.Material.Metal },
		{ "Shaft", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(255, 184, 20), Enum.Material.Metal },
		{ "Stripe", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(26, 26, 31), Enum.Material.SmoothPlastic },
		{ "Bands", "heel", Vector3.new(0, 0, -3.765), Color3.fromRGB(26, 26, 31), Enum.Material.SmoothPlastic },
		{ "Gems", "heel", Vector3.new(0, 0, -3.545), Color3.fromRGB(255, 247, 209), Enum.Material.Neon },
		{ "Grip", "butt", Vector3.new(0, 0, -0.45), Color3.fromRGB(26, 26, 31), Enum.Material.Fabric },
		{ "Cap", "butt", Vector3.new(0, 0, -0.005), Color3.fromRGB(255, 184, 20), Enum.Material.Metal },
		{ "Trophy", "butt", Vector3.new(0, 0, 0.525), Color3.fromRGB(255, 184, 20), Enum.Material.Metal },
		{ "TrophyGem", "butt", Vector3.new(0, 0, 1.1391), Color3.fromRGB(255, 247, 209), Enum.Material.Neon },
	},
	-- Build 25 shop sticks (assets/sticks/shopsticks2.py, out_b25).
	RockAxe = {
		{ "Body", "blade", Vector3.new(0, 0.0902, 0.0014), Color3.fromRGB(219, 31, 36), Enum.Material.SmoothPlastic },
		{ "Pickguard", "blade", Vector3.new(0, -0.0387, 0.0272), Color3.fromRGB(245, 242, 235), Enum.Material.SmoothPlastic },
		{ "Pickups", "blade", Vector3.new(0, 0, 0.2), Color3.fromRGB(26, 26, 31), Enum.Material.SmoothPlastic },
		{ "Chrome", "blade", Vector3.new(0, -0.105, 0.06), Color3.fromRGB(204, 209, 219), Enum.Material.Metal },
		{ "Neck", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(199, 143, 82), Enum.Material.Wood },
		{ "Frets", "stretch", Vector3.new(-0.0075, 0, 0), Color3.fromRGB(214, 219, 230), Enum.Material.Metal },
		{ "Headstock", "butt", Vector3.new(0, -0.0087, 0.4056), Color3.fromRGB(219, 31, 36), Enum.Material.SmoothPlastic },
		{ "Pegs", "butt", Vector3.new(0, 0, 0.44), Color3.fromRGB(204, 209, 219), Enum.Material.Metal },
		{ "NeckJoint", "heel", Vector3.new(0, 0, -4.025), Color3.fromRGB(199, 143, 82), Enum.Material.Wood },
	},
	IcePop = {
		{ "Pop", "blade", Vector3.new(0, 0.041, -0.9199), Color3.fromRGB(240, 51, 66), Enum.Material.SmoothPlastic },
		{ "PopMid", "blade", Vector3.new(0, 0.04, 0.02), Color3.fromRGB(250, 247, 240), Enum.Material.SmoothPlastic },
		{ "PopTop", "blade", Vector3.new(0, 0.09, 0.9399), Color3.fromRGB(56, 133, 245), Enum.Material.SmoothPlastic },
		{ "Drips", "blade", Vector3.new(0, -0.9903, -0.85), Color3.fromRGB(240, 51, 66), Enum.Material.SmoothPlastic },
		{ "PopStick", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(230, 194, 133), Enum.Material.Wood },
		{ "StickTip", "butt", Vector3.new(0, 0, 0.075), Color3.fromRGB(230, 194, 133), Enum.Material.Wood },
		{ "Tag", "heel", Vector3.new(0, 0, -4), Color3.fromRGB(102, 178, 255), Enum.Material.SmoothPlastic },
	},
	FairwayClub = {
		{ "ClubHead", "blade", Vector3.new(0, 0.1, 0), Color3.fromRGB(31, 33, 41), Enum.Material.SmoothPlastic },
		{ "Face", "blade", Vector3.new(0, -0.06, -0.025), Color3.fromRGB(199, 204, 214), Enum.Material.Metal },
		{ "Grooves", "blade", Vector3.new(0, -0.0075, -0.025), Color3.fromRGB(76, 79, 89), Enum.Material.Metal },
		{ "Accent", "blade", Vector3.new(0, -0.73, 0.025), Color3.fromRGB(51, 191, 89), Enum.Material.SmoothPlastic },
		{ "Graphite", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(41, 43, 51), Enum.Material.SmoothPlastic },
		{ "ShaftBand", "stretch", Vector3.new(0.265, 0, 0), Color3.fromRGB(51, 191, 89), Enum.Material.SmoothPlastic },
		{ "Grip", "butt", Vector3.new(0, 0, -0.5159), Color3.fromRGB(31, 31, 36), Enum.Material.Fabric },
		{ "Hosel", "heel", Vector3.new(0, 0, -4.01), Color3.fromRGB(199, 204, 214), Enum.Material.Metal },
	},
	-- Build 31 (assets/sticks/scythestick.py): goes with the Reaper Cloak.
	ReaperScythe = {
		{ "Blade", "blade", Vector3.new(0, 0.1476, -0.1233), Color3.fromRGB(115, 120, 135), Enum.Material.Metal },
		{ "SoulEdge", "blade", Vector3.new(0, -0.2327, -0.0423), Color3.fromRGB(178, 92, 255), Enum.Material.Neon },
		{ "Rivets", "blade", Vector3.new(0, 0.435, 0.84), Color3.fromRGB(232, 224, 204), Enum.Material.SmoothPlastic },
		{ "Skull", "blade", Vector3.new(0, 1.06, 1.117), Color3.fromRGB(232, 224, 204), Enum.Material.SmoothPlastic },
		{ "Eyes", "blade", Vector3.new(0, 1.11, 0.875), Color3.fromRGB(178, 92, 255), Enum.Material.Neon },
		{ "Sockets", "blade", Vector3.new(0, 1.075, 0.8945), Color3.fromRGB(13, 8, 15), Enum.Material.SmoothPlastic },
		{ "Shaft", "stretch", Vector3.new(0, 0, 0), Color3.fromRGB(51, 38, 31), Enum.Material.Wood },
		{ "Wraps", "heel", Vector3.new(0, 0, -3.425), Color3.fromRGB(232, 224, 204), Enum.Material.Fabric },
		{ "Grip", "butt", Vector3.new(0, 0, -0.455), Color3.fromRGB(232, 224, 204), Enum.Material.Fabric },
		{ "Pommel", "butt", Vector3.new(0, 0, 0.1329), Color3.fromRGB(232, 224, 204), Enum.Material.SmoothPlastic },
	},
}
local stickFolder: Instance? = nil
-- Build 37: the Reaper Scythe's blade hung with its whole cutting edge 0.6 studs off the ice
-- (only the hooked point came down). It is turned 11 degrees point-up about the socket, so the
-- heel of the edge and the point both rest on the ice with the curve arching between, and slid
-- down the shaft's line 0.8 studs (in the blade's frame the shaft runs about (0.15, -0.81,
-- -0.57)); a short length of shaft carries on past the heel into the lowered socket.
local SCYTHE_SOCKET = Vector3.new(0, 0.82, 1.1)
local SCYTHE_DROP = 0.8
local SCYTHE_SET = CFrame.new(Vector3.new(0.12, -0.647, -0.457)) * CFrame.new(SCYTHE_SOCKET) * CFrame.Angles(0.194, 0, 0) * CFrame.new(-SCYTHE_SOCKET)
local function meshStick(style: string): StickBuilder
	return function(model: Model, item: Catalog.Item?): { StickPiece }
		if not stickFolder then
			stickFolder = game:GetService("ReplicatedStorage"):FindFirstChild("StickMeshes")
		end
		local set = stickFolder and stickFolder:FindFirstChild(style)
		local pieces: { StickPiece } = {}
		if set then
			for _, row in STICK_MESHES[style] do
				local name, kind, centre, color, material, transparency = row[1], row[2], row[3], row[4], row[5], row[6]
				local template = set:FindFirstChild(name)
				if template and template:IsA("MeshPart") then
					local p = template:Clone()
					p.Name = name
					p.Anchored = true
					p.CanCollide = false
					p.CanTouch = false
					p.CanQuery = false
					p.Color = color
					p.Material = material
					p.Transparency = transparency or 0
					p.Parent = model
					if style == "PlasmaSaber" and name == "Glow" then
						-- The faintest pink light off the energy blade.
						local light = Instance.new("PointLight")
						light.Color = color
						light.Range = 5
						light.Brightness = 0.7
						light.Shadows = false
						light.Parent = p
					end
					if style == "NovaBlade" and name == "Edge" then
						-- Build 40: the Nova Blade throws a few sparks off the ice near the toe (Build 41: its
						-- light trail is gone; it was distracting when spinning). The attachment's position is
						-- relative to the part, whose centre sits at `centre` in the blade frame.
						local bottom = Instance.new("Attachment")
						bottom.Name = "SparkPoint"
						bottom.Position = Vector3.new(0, -0.7, -0.8) - centre
						bottom.Parent = p
						local sparks = Instance.new("ParticleEmitter")
						sparks.Rate = 6
						sparks.Lifetime = NumberRange.new(0.2, 0.4)
						sparks.Speed = NumberRange.new(1.5, 3.5)
						sparks.SpreadAngle = Vector2.new(70, 70)
						sparks.Acceleration = Vector3.new(0, -10, 0)
						sparks.LightEmission = 1
						sparks.LightInfluence = 0
						sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0) })
						sparks.Color = ColorSequence.new(NOVA_CYAN_HOT, NOVA_CYAN)
						sparks.Parent = bottom
					end
					-- Build 41: the animated pass sticks' particles, off the blade.
					local fx: ParticleEmitter? = nil
					if style == "ToxicSludge" and name == "Goo" then
						fx = Instance.new("ParticleEmitter")
						fx.Rate = 5
						fx.Lifetime = NumberRange.new(0.5, 0.9)
						fx.Speed = NumberRange.new(0.8, 1.6)
						fx.SpreadAngle = Vector2.new(20, 20)
						fx.EmissionDirection = Enum.NormalId.Top
						fx.Acceleration = Vector3.new(0, 2, 0)
						fx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.06), NumberSequenceKeypoint.new(0.7, 0.14), NumberSequenceKeypoint.new(1, 0) })
						fx.Transparency = NumberSequence.new(0.2, 0.6)
						fx.Color = ColorSequence.new(Color3.fromRGB(200, 255, 110), Color3.fromRGB(110, 245, 50))
					elseif style == "CarbonStrike" and name == "Edge" then
						fx = Instance.new("ParticleEmitter")
						fx.Rate = 6
						fx.Lifetime = NumberRange.new(0.2, 0.35)
						fx.Speed = NumberRange.new(1.5, 3.5)
						fx.SpreadAngle = Vector2.new(70, 70)
						fx.Acceleration = Vector3.new(0, -10, 0)
						fx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.09), NumberSequenceKeypoint.new(1, 0) })
						fx.Color = ColorSequence.new(Color3.fromRGB(255, 200, 200), Color3.fromRGB(255, 31, 51))
					elseif style == "ChampionGold" and name == "Star" then
						fx = Instance.new("ParticleEmitter")
						fx.Rate = 4
						fx.Lifetime = NumberRange.new(0.4, 0.8)
						fx.Speed = NumberRange.new(0.3, 0.9)
						fx.SpreadAngle = Vector2.new(180, 180)
						fx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.13), NumberSequenceKeypoint.new(1, 0) })
						fx.Color = ColorSequence.new(Color3.fromRGB(255, 247, 209), Color3.fromRGB(255, 200, 70))
					end
					if fx then
						fx.LightEmission = 1
						fx.LightInfluence = 0
						fx.Parent = p
					end
					local function place(part: BasePart, grow: number)
						if kind == "blade" then
							part.Size *= grow
							table.insert(pieces, { part = part, on = "blade", at = if style == "ReaperScythe" then SCYTHE_SET * CFrame.new(centre) else CFrame.new(centre) })
						elseif kind == "butt" then
							part.Size *= grow
							table.insert(pieces, { part = part, on = "shaft", at = CFrame.new(centre), fromButt = 0 })
						elseif kind == "heel" then
							part.Size *= grow
							table.insert(pieces, { part = part, on = "shaft", at = CFrame.new(centre + Vector3.new(0, 0, MODEL_SHAFT)), fromHeel = 0 })
						else
							part.Size = Vector3.new(part.Size.X, part.Size.Y * SHAFT_THIN * grow, part.Size.Z * SHAFT_THIN * grow)
							table.insert(pieces, { part = part, on = "shaft", at = ALONG_Z * CFrame.new(centre), stretch = true })
						end
					end
					if style == "Thunderbolt" and (name == "Bolt" or name == "GlowStripe") then
						-- Build 35: the lightning bolt and the yellow shaft stripe glow a little: a faint
						-- see-through Neon shell round each (a soft halo) and a small warm light.
						local halo = p:Clone()
						halo.Name = name .. "Halo"
						halo.Transparency = 0.78
						halo.CastShadow = false
						halo.Parent = model
						place(halo, if name == "Bolt" then 1.12 else 1.6)
						local light = Instance.new("PointLight")
						light.Color = color
						light.Range = if name == "Bolt" then 6 else 4
						light.Brightness = if name == "Bolt" then 1.1 else 0.6
						light.Shadows = false
						light.Parent = p
					end
					place(p, 1)
					if style == "ReaperScythe" and name == "Shaft" then
						-- The shaft carried on past the heel, down into the lowered blade's socket.
						local tip = template:Clone()
						tip.Name = "ShaftTip"
						tip.Anchored, tip.CanCollide, tip.CanTouch, tip.CanQuery = true, false, false, false
						tip.Color = color
						tip.Material = material
						tip.Size = Vector3.new(SCYTHE_DROP + 0.25, tip.Size.Y * SHAFT_THIN, tip.Size.Z * SHAFT_THIN)
						tip.Parent = model
						table.insert(pieces, { part = tip, on = "shaft", at = ALONG_Z, fromHeel = -(SCYTHE_DROP + 0.05) / 2 })
					end
				end
			end
		end
		if #pieces == 0 then
			model:ClearAllChildren()
			return Looks.STICK_STYLES.classic(model, item)
		end
		return pieces
	end
end
for style in STICK_MESHES do
	Looks.STICK_STYLES[style] = meshStick(style)
end

export type StickFrames = {
	gloveA: CFrame,
	gloveB: CFrame,
	shaftBase: CFrame, -- at the butt end, -Z running down the shaft to the heel
	shaftLength: number,
	blade: CFrame, -- blade centre, -Z toward the toe, +Y up
}

-- Lays out hands, shaft and blade like the reference: the stick is tucked against the body.
-- The blade points straight out from the body, standing on its edge, with its inner end
-- touching the body; the hands hold the shaft against the chest on the stick-hand side.
-- `bladeAt` is the sim's blade centre, so the visual blade always covers the real hitbox.
-- Puck lift tips the blade back: its top edge leans toward `back` (toward the camera, so the
-- face looking up the rink opens for a lifted shot or pass), whichever way the blade points.
-- It pivots about the blade's bottom centre and is then raised so no corner dips into the ice.
local function openBlade(blade: CFrame, back: Vector3, tilt: number): CFrame
	local flatBack = Vector3.new(back.X, 0, back.Z)
	if tilt < 0.01 or flatBack.Magnitude < 1e-3 then
		return blade
	end
	local size = Looks.BLADE_SIZE
	local half = size.Y / 2
	local bottom = blade * CFrame.new(0, -half, 0)
	-- Rotating about (up x back) carries the up axis toward `back`.
	local axis = Vector3.yAxis:Cross(flatBack.Unit)
	local tipped = CFrame.new(bottom.Position) * CFrame.fromAxisAngle(axis, tilt * 0.42) * bottom.Rotation -- Build 29: about 24 degrees open (was 43, leaned too far back)
	local lowest = math.huge
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			lowest = math.min(lowest, (tipped * Vector3.new(sx * size.X / 2, 0, sz * size.Z / 2)).Y)
		end
	end
	local raise = math.max(0, bottom.Position.Y - lowest)
	return CFrame.new(0, raise, 0) * tipped * CFrame.new(0, half, 0)
end

function Looks.stickFrames(origin: Vector3, yaw: number, bladeAt: Vector3, lift: number, bob: number, side: number, tilt: number?, back: Vector3?, scale: number?): StickFrames
	local k = scale or 1
	local along = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
	local across = Vector3.new(-along.Z, 0, along.X)
	-- The blade runs from the heel at BLADE_ANGLE off the stick, toe toward the backhand.
	local by = yaw + Looks.BLADE_ANGLE
	local bladeDir = Vector3.new(math.cos(by), 0, math.sin(by))
	local size = Looks.BLADE_SIZE
	local base = Vector3.new(bladeAt.X, 0, bladeAt.Z)
	local bladeCentre = base + Vector3.new(0, lift + size.Y / 2 + 0.02, 0)
	local frame = openBlade(CFrame.lookAt(bladeCentre, bladeCentre + bladeDir), back or -along, tilt or 0)
	-- The shaft meets the blade at the hosel, on top of the heel, even when it is tipped.
	local heel = (frame * CFrame.new(0, size.Y / 2 + 0.1, size.Z / 2 - 0.3)).Position

	-- Top hand on the chest surface, toward the blade and off to the stick-hand side.
	local grip = origin + along * (1.45 * k) + across * (side * 0.95 * k) + Vector3.new(0, (Looks.GRIP_Y + 0.8) * k + bob, 0)
	local toHeel = heel - grip
	local shaftDir = if toHeel.Magnitude > 0.05 then toHeel.Unit else -Vector3.yAxis
	local butt = grip - shaftDir * BUTT_EXTRA
	local lowerHand = grip + toHeel * 0.45
	-- Each hand's frame: -Z down the shaft, +Y back along the forearm toward the shoulder (the
	-- glove's cuff points that way).
	local shoulder = origin + across * (side * 1.2 * k) - along * (0.3 * k) + Vector3.new(0, 3.7 * k + bob, 0)
	local function hand(at: Vector3): CFrame
		return CFrame.lookAt(at, at + shaftDir, shoulder - at)
	end
	return {
		gloveA = hand(grip),
		-- The bottom hand grips from the other side: turned round the forearm, so its palm faces
		-- where the top hand's back does.
		gloveB = hand(lowerHand) * CFrame.Angles(0, math.pi, 0),
		-- Square shaft: its depth lines up with the blade, so the flat sides face where the blade does.
		shaftBase = CFrame.lookAt(butt, heel, if math.abs(bladeDir:Dot(shaftDir)) < 0.98 then bladeDir:Cross(shaftDir) else Vector3.yAxis),
		shaftLength = (heel - butt).Magnitude,
		blade = frame,
	}
end

-- Resizes the pieces that span the shaft. Call when the shaft length changes noticeably.
function Looks.sizeStick(rig: Rig, shaftLength: number)
	for _, piece in rig.stick do
		if piece.stretch then
			local s = piece.part.Size
			piece.part.Size = Vector3.new(shaftLength, s.Y, s.Z)
		end
	end
end

-- Writes the frame of every stick piece into `cframes` after index `n`; returns the new count.
function Looks.placeStick(rig: Rig, f: StickFrames, cframes: { CFrame }, n: number): number
	local length = f.shaftLength
	for _, piece in rig.stick do
		local cf: CFrame
		if piece.on == "blade" then
			cf = f.blade * piece.at
		else
			local d = if piece.stretch then length / 2 elseif piece.fromHeel then length - piece.fromHeel else (piece.fromButt or 0)
			cf = f.shaftBase * CFrame.new(0, 0, -d) * piece.at
		end
		n += 1
		cframes[n] = cf
	end
	return n
end

-- Writes the two gloves and their cuffs into `cframes` after index `n`; returns the new count.
function Looks.placeHands(rig: Rig, f: StickFrames, cframes: { CFrame }, n: number): number
	cframes[n + 1] = f.gloveA * rig.gloveOffset
	cframes[n + 2] = f.gloveB * rig.gloveOffset
	cframes[n + 3] = f.gloveA * rig.cuffOffset
	cframes[n + 4] = f.gloveB * rig.cuffOffset
	return n + 4
end

-- Every part the animator moves, in the order SkaterView and Looks.pose fill frames: body,
-- ring, the two gloves and their cuffs, then the stick pieces.
function Looks.movingParts(rig: Rig): { BasePart }
	local parts: { BasePart } = {}
	for _, p in rig.body do
		table.insert(parts, p)
	end
	for _, p in rig.ring do
		table.insert(parts, p)
	end
	table.insert(parts, rig.gloveA)
	table.insert(parts, rig.gloveB)
	table.insert(parts, rig.cuffA)
	table.insert(parts, rig.cuffB)
	for _, piece in rig.stick do
		table.insert(parts, piece.part)
	end
	return parts
end

-- Build 40: moves a rig's animated pieces for time `t` (seconds, any clock): back bling regions
-- that bob and spin about their own centres (overwriting their entries in `cframes`, where entry
-- i holds `body * offsets[i]` for body part i) and neon parts whose colour pulses. Costs nothing
-- for a rig that wears no animated item.
function Looks.animate(rig: Rig, body: CFrame, cframes: { CFrame }, t: number)
	local anim = rig.anim
	if not anim then
		return
	end
	local bob = math.sin(t * BOB_RATE)
	for _, s in anim.spins do
		local cf = CFrame.new(s.at + Vector3.new(0, s.bob * bob, 0))
		if s.axis then
			local angle = if s.swing then s.swing * math.sin(t * s.rate) else t * s.rate
			if s.piv then
				-- Turned about a point away from its centre: round the pivot, then back out to it.
				cf = cf * CFrame.new(s.piv) * CFrame.fromAxisAngle(s.axis, angle) * CFrame.new(-s.piv)
			else
				cf *= CFrame.fromAxisAngle(s.axis, angle)
			end
		end
		cframes[s.i] = body * cf * s.rot
	end
	for _, p in anim.pulses do
		p.part.Color = p.a:Lerp(p.b, 0.5 + 0.5 * math.sin(t * p.rate + p.phase))
	end
end

-- Places a rig standing still with the stick tucked against the body and the blade out to one
-- side on the ice: used by the locker, the results podium and the pond NPCs.
function Looks.pose(rig: Rig, root: CFrame, stickSide: number?)
	local parts = Looks.movingParts(rig)
	local cframes: { CFrame } = {}
	local n = 0
	for i in rig.body do
		n += 1
		cframes[n] = root * rig.offsets[i]
	end
	Looks.animate(rig, root, cframes, os.clock())
	for i in rig.ring do
		n += 1
		cframes[n] = root * rig.ringOffsets[i]
	end
	local side = stickSide or -1
	local origin = root.Position
	-- Front and a little to the stick side, at the same tucked distance as in play.
	local out = root:VectorToWorldSpace(Vector3.new(-side * 0.6, 0, -1))
	out = Vector3.new(out.X, 0, out.Z).Unit
	local outYaw = math.atan2(out.Z, out.X)
	local f = Looks.stickFrames(origin, outYaw, Looks.bladeCentre(origin, outYaw), 0, 0, side, nil, nil, rig.scale)
	Looks.sizeStick(rig, f.shaftLength)
	Looks.placeStick(rig, f, cframes, Looks.placeHands(rig, f, cframes, n))
	-- A rig in a ViewportFrame's WorldModel (the shop pictures) moves within that world.
	local world = rig.model:FindFirstAncestorWhichIsA("WorldRoot")
	if world and world ~= workspace then
		for i, p in parts do
			p.CFrame = cframes[i]
		end
	else
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- One whole headwear style as loose prop parts (the helmets on the lobby's locker shelves): each
-- region placed round `at` (the head centre it was modelled on) and scaled by `scale`. Returns no
-- parts when the style's meshes aren't in the place.
function Looks.headwearProp(parent: Instance, style: string, main: Color3, accent: Color3, at: CFrame, scale: number): { BasePart }
	local out = {}
	local rows = HEADWEAR[style]
	local folder = headTemplates(style)
	if not (rows and folder) then
		return out
	end
	for region, row in rows do
		local template = folder:FindFirstChild(region)
		if template and template:IsA("MeshPart") then
			local p = template:Clone()
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.Size *= scale
			p.CFrame = at * CFrame.new(row[1] * scale)
			p.Color = headTint(row[2], main, accent)
			p.Material = row[3]
			p.Transparency = row[4] or 0
			p.CastShadow = false
			p.Parent = parent
			table.insert(out, p)
		end
	end
	return out
end

return Looks
