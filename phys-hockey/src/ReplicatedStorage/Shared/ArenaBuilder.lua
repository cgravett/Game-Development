--!strict
-- Builds every place the camera can see: three rinks (Arena, Night, Pond) and the locker-room
-- lobby. Everything is decorative: gameplay collision is analytic in Sim, so no part here can
-- deflect a puck, and every part skips collision, touch and queries.

local Config = require(script.Parent.GameConfig)
local Sim = require(script.Parent.Sim)
local PondLayout = require(script.Parent.PondLayout)
local Looks = require(script.Parent.Looks)
local TweenService = game:GetService("TweenService")

local ArenaBuilder = {}

local ARENA = Config.Arena
local GOAL = Config.Goal
local HX = ARENA.Length / 2
local HZ = ARENA.Width / 2
local CR = ARENA.CornerRadius
local BOARD_H = ARENA.BoardHeight

export type Theme = {
	name: string,
	ice: Color3,
	red: Color3,
	blue: Color3,
	crease: Color3,
	board: Color3,
	kick: Color3,
	rail: Color3,
	adText: Color3,
	adAccent: Color3,
	concourse: Color3,
	step: Color3,
	seats: { Color3 },
	wall: Color3,
	indoor: boolean,
	crowdFill: number,
	rows: number,
	scratch: number,
	-- "lake": the Frozen Lake rink (a season pass rink): the match rink out on a frozen lake by
	-- day (Build 39; was dusk), with the old pond scenery round it. "forest": Timberline, a rink in a forest clearing.
	-- Nil: indoor stands or the Pond open world.
	scenery: string?,
}

local THEMES: { [string]: Theme } = {
	Arena = {
		name = "Arena",
		ice = Color3.fromRGB(206, 222, 238),
		red = Color3.fromRGB(232, 98, 98),
		blue = Color3.fromRGB(92, 146, 226),
		crease = Color3.fromRGB(148, 196, 240),
		board = Color3.fromRGB(246, 247, 250),
		kick = Color3.fromRGB(40, 72, 160),
		rail = Color3.fromRGB(48, 52, 64),
		adText = Color3.fromRGB(38, 52, 92),
		adAccent = Color3.fromRGB(40, 110, 220),
		concourse = Color3.fromRGB(58, 62, 74),
		step = Color3.fromRGB(70, 74, 88),
		seats = { Color3.fromRGB(196, 50, 56), Color3.fromRGB(44, 82, 170) },
		wall = Color3.fromRGB(34, 36, 46),
		indoor = true,
		crowdFill = 0.72,
		rows = 11,
		scratch = 0.74, -- faint skate marks, like the reference ice
	},
	Night = {
		name = "Night",
		ice = Color3.fromRGB(46, 50, 60),
		red = Color3.fromRGB(226, 84, 92),
		blue = Color3.fromRGB(60, 190, 226),
		crease = Color3.fromRGB(56, 150, 190),
		board = Color3.fromRGB(232, 236, 242),
		kick = Color3.fromRGB(206, 50, 58),
		rail = Color3.fromRGB(32, 34, 42),
		adText = Color3.fromRGB(40, 44, 60),
		adAccent = Color3.fromRGB(214, 52, 60),
		concourse = Color3.fromRGB(30, 32, 40),
		step = Color3.fromRGB(42, 44, 54),
		seats = { Color3.fromRGB(176, 40, 48), Color3.fromRGB(36, 70, 150) },
		wall = Color3.fromRGB(18, 20, 28),
		indoor = true,
		crowdFill = 0.72,
		rows = 11,
		scratch = 0.85,
	},
	Pond = {
		name = "Pond",
		ice = Color3.fromRGB(124, 182, 194),
		red = Color3.fromRGB(214, 92, 100),
		blue = Color3.fromRGB(86, 140, 200),
		crease = Color3.fromRGB(120, 180, 214),
		board = Color3.fromRGB(240, 242, 236),
		kick = Color3.fromRGB(132, 96, 64),
		rail = Color3.fromRGB(116, 84, 56),
		adText = Color3.fromRGB(70, 60, 50),
		adAccent = Color3.fromRGB(200, 70, 60),
		concourse = Color3.fromRGB(240, 244, 248),
		step = Color3.fromRGB(150, 110, 76),
		seats = { Color3.fromRGB(196, 50, 56), Color3.fromRGB(44, 82, 170) },
		wall = Color3.fromRGB(240, 244, 248),
		indoor = false,
		crowdFill = 0.55,
		rows = 4,
		scratch = 0.65,
	},
}
-- Frozen Lake (season pass rink): the rink out on a lake on a bright winter day (Build 39; it was
-- dusk), wooden boards, snowbanks, fans on the bleachers.
THEMES.FrozenLake = {
	name = "FrozenLake",
	ice = Color3.fromRGB(150, 196, 224),
	red = Color3.fromRGB(214, 92, 100),
	blue = Color3.fromRGB(70, 120, 196),
	crease = Color3.fromRGB(120, 180, 220),
	board = Color3.fromRGB(236, 228, 214),
	kick = Color3.fromRGB(122, 86, 58),
	rail = Color3.fromRGB(98, 70, 48),
	adText = Color3.fromRGB(70, 60, 50),
	adAccent = Color3.fromRGB(200, 70, 60),
	concourse = Color3.fromRGB(240, 244, 248),
	step = Color3.fromRGB(150, 110, 76),
	seats = { Color3.fromRGB(196, 50, 56), Color3.fromRGB(44, 82, 170) },
	wall = Color3.fromRGB(240, 244, 248),
	indoor = false,
	crowdFill = 0.6, -- Build 39: the bleachers now have fans (was 0.4, unused)
	rows = 4,
	scratch = 0.6,
	scenery = "lake",
}
-- Timberline (a Quick Play map, Build 28): an outdoor rink in a forest clearing on a winter day,
-- wooden boards, timber stands. It replaces the pond rink in the rotation (the pond rink still
-- hosts the matches queued from the pond).
THEMES.Timberline = {
	name = "Timberline",
	ice = Color3.fromRGB(200, 224, 238),
	red = Color3.fromRGB(218, 80, 86),
	blue = Color3.fromRGB(70, 126, 204),
	crease = Color3.fromRGB(130, 186, 226),
	board = Color3.fromRGB(232, 214, 184),
	kick = Color3.fromRGB(116, 78, 50),
	rail = Color3.fromRGB(92, 62, 40),
	adText = Color3.fromRGB(70, 54, 40),
	adAccent = Color3.fromRGB(176, 52, 46),
	concourse = Color3.fromRGB(240, 244, 248),
	step = Color3.fromRGB(150, 110, 76),
	seats = { Color3.fromRGB(196, 50, 56), Color3.fromRGB(44, 82, 170) },
	wall = Color3.fromRGB(240, 244, 248),
	indoor = false,
	crowdFill = 0.7,
	rows = 6,
	scratch = 0.7,
	scenery = "forest",
}
-- Build 34: five rinks sold in the shop (looks only: the same ice, boards and nets as every
-- rink). Each dresses the rink in its own world, built by buildShopScenery below.
local function shopTheme(name: string, scenery: string, indoor: boolean, c: { [string]: Color3 }, rows: number, fill: number): Theme
	return {
		name = name,
		ice = c.ice,
		red = c.red,
		blue = c.blue,
		crease = c.crease,
		board = c.board,
		kick = c.kick,
		rail = c.rail,
		adText = c.adText,
		adAccent = c.adAccent,
		concourse = c.concourse or Color3.fromRGB(58, 62, 74),
		step = c.step or Color3.fromRGB(70, 74, 88),
		seats = { c.seatA or Color3.fromRGB(196, 50, 56), c.seatB or Color3.fromRGB(44, 82, 170) },
		wall = c.wall or Color3.fromRGB(34, 36, 46),
		indoor = indoor,
		crowdFill = fill,
		rows = rows,
		scratch = 0.7,
		scenery = scenery,
	}
end
local rgb = Color3.fromRGB
THEMES.NeonArcade = shopTheme("NeonArcade", "neon", true, {
	ice = rgb(34, 30, 58), red = rgb(255, 70, 170), blue = rgb(60, 220, 255), crease = rgb(70, 50, 140),
	board = rgb(28, 26, 46), kick = rgb(255, 60, 170), rail = rgb(16, 14, 28),
	adText = rgb(120, 40, 200), adAccent = rgb(0, 150, 200),
	concourse = rgb(22, 20, 38), step = rgb(36, 32, 60), seatA = rgb(230, 50, 160), seatB = rgb(40, 170, 230), wall = rgb(14, 12, 26),
}, 11, 0.72)
THEMES.CandyLand = shopTheme("CandyLand", "candy", false, {
	ice = rgb(255, 232, 244), red = rgb(236, 70, 120), blue = rgb(120, 140, 255), crease = rgb(200, 180, 255),
	board = rgb(255, 250, 252), kick = rgb(255, 120, 180), rail = rgb(150, 90, 210),
	adText = rgb(170, 70, 170), adAccent = rgb(255, 100, 160),
}, 5, 0.6)
THEMES.TropicalBeach = shopTheme("TropicalBeach", "beach", false, {
	ice = rgb(214, 240, 248), red = rgb(240, 96, 80), blue = rgb(30, 160, 200), crease = rgb(130, 214, 236),
	board = rgb(255, 246, 226), kick = rgb(30, 170, 170), rail = rgb(190, 140, 84),
	adText = rgb(20, 110, 140), adAccent = rgb(250, 120, 60),
}, 5, 0.65)
THEMES.Volcano = shopTheme("Volcano", "volcano", false, {
	ice = rgb(214, 206, 208), red = rgb(230, 50, 30), blue = rgb(70, 110, 200), crease = rgb(255, 196, 150),
	board = rgb(56, 48, 50), kick = rgb(255, 96, 20), rail = rgb(30, 26, 28),
	adText = rgb(150, 40, 20), adAccent = rgb(230, 110, 20),
}, 5, 0.6)
THEMES.MoonBase = shopTheme("MoonBase", "moon", false, {
	ice = rgb(222, 228, 240), red = rgb(230, 80, 90), blue = rgb(90, 150, 255), crease = rgb(150, 190, 255),
	board = rgb(214, 218, 226), kick = rgb(60, 66, 82), rail = rgb(120, 128, 146),
	adText = rgb(40, 52, 90), adAccent = rgb(70, 130, 230),
}, 4, 0.5)
ArenaBuilder.Themes = THEMES
ArenaBuilder.MatchThemes = { "Arena", "Night", "Timberline" }

-- Fictional sponsors only.
local SPONSORS = { "FROSTBITE COLA", "PHYSHOCKEY", "GLIDEWAX", "ZIPPY'S", "PHYSHOCKEY", "SNOWCAP BANK", "CRUNCHOS" }

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, transparency: number?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Parent = parent
	return p
end

local function ball(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = part(parent, name, size, cf, color, material)
	if size.X == size.Y and size.Y == size.Z then
		p.Shape = Enum.PartType.Ball
	else
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	return p
end

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

local function disc(parent: Instance, name: string, diameter: number, height: number, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = part(parent, name, Vector3.new(height, diameter, diameter), cf * UPRIGHT, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Build 35: every sign in the world uses the game's own face (Sarpanch, as the HUD and menus),
-- never Roblox's stock Fredoka/Gotham. The old Enum fonts passed in only pick the weight.
local GAME_FONT = Font.fromName("Sarpanch", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local GAME_FONT_BODY = Font.fromName("Sarpanch", Enum.FontWeight.Bold)
local function gameFont(font: Enum.Font?): Font
	if font == Enum.Font.GothamBold or font == Enum.Font.GothamMedium then
		return GAME_FONT_BODY
	end
	return GAME_FONT
end

local function textSign(p: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?, font: Enum.Font?, ppS: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppS or 20
	gui.LightInfluence = 0.6
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if bg then 0 else 1
	label.BackgroundColor3 = bg or Color3.new(1, 1, 1)
	label.FontFace = gameFont(font)
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color
	label.Parent = gui
	-- Side padding too: the italic leans past the box and clipped the last letter.
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.Parent = label
end

-- In-game action shots (captured in the game, uploaded as decals; see assets/lobby/LOBBY_ASSETS.md).
local ACTION_SHOTS = {
	{ image = "rbxassetid://103385555319000", title = "SNIPE CITY" },
	{ image = "rbxassetid://127154381493599", title = "FACE-OFF" },
	{ image = "rbxassetid://137610395392686", title = "BREAKAWAY" },
}
local POSTER_INK = Color3.fromRGB(16, 30, 64)
local POSTER_RED = Color3.fromRGB(226, 46, 56)

local function surface(p: BasePart, ppS: number, light: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppS
	gui.LightInfluence = light
	gui.Parent = p
	return gui
end

local function shotImage(parent: Instance, image: string, z: number): ImageLabel
	local img = Instance.new("ImageLabel")
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.Image = image
	img.ScaleType = Enum.ScaleType.Crop
	img.ZIndex = z
	img.Parent = parent
	return img
end

local function words(parent: Instance, text: string, size: UDim2, pos: UDim2, color: Color3, font: Enum.Font, z: number, stroke: number?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = size
	t.Position = pos
	t.Text = text
	t.FontFace = gameFont(font)
	t.TextScaled = true
	t.TextColor3 = color
	t.ZIndex = z
	t.Parent = parent
	if stroke then
		local s = Instance.new("UIStroke")
		s.Thickness = stroke
		s.Color = POSTER_INK
		s.LineJoinMode = Enum.LineJoinMode.Round
		s.Parent = t
	end
	return t
end

-- A shade that fades from dark at one edge to clear, so text reads on top of a photo.
local function shade(parent: Instance, fromTop: boolean, depth: number, z: number)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.fromRGB(6, 12, 30)
	f.Size = UDim2.fromScale(1, depth)
	f.Position = if fromTop then UDim2.fromScale(0, 0) else UDim2.fromScale(0, 1 - depth)
	f.ZIndex = z
	f.Parent = parent
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = if fromTop
		then NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.55, 0.45), NumberSequenceKeypoint.new(1, 1) })
		else NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.45, 0.45), NumberSequenceKeypoint.new(1, 0.05) })
	g.Parent = f
end

-- The game's sport face (Sarpanch heavy italic), the same as the HUD, menus and buttons.
local POSTER_SPORT = Font.fromName("Sarpanch", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)

local function sportWords(parent: Instance, text: string, size: UDim2, pos: UDim2, color: Color3, z: number, stroke: number?): TextLabel
	local t = words(parent, text, size, pos, color, Enum.Font.GothamBlack, z, stroke)
	t.FontFace = POSTER_SPORT
	return t
end

local function gradient(parent: Instance, rotation: number, a: Color3, b: Color3)
	local g = Instance.new("UIGradient")
	g.Rotation = rotation
	g.Color = ColorSequence.new(a, b)
	g.Parent = parent
end

-- A thin bar (a speed line or a burst ray) centred on pos, turned by `angle` degrees, fading out
-- at both ends.
local function streak(parent: Instance, pos: UDim2, size: UDim2, angle: number, color: Color3, alpha: number, z: number)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = pos
	f.Size = size
	f.Rotation = angle
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = parent
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, alpha),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = f
	return f
end

-- The alcove key art (Build 28): a breakaway bursting out of a blue light-burst, speed lines and
-- ice spray across it, the PHYSHOCKEY title slammed on at an angle in the game's sport font, and
-- a red season ribbon cutting across the bottom.
local function keyArtPoster(p: BasePart)
	local gui = surface(p, 50, 0.2)
	gui.ClipsDescendants = true
	-- Deep navy into electric blue.
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.new(1, 1, 1)
	back.BorderSizePixel = 0
	back.ZIndex = 0
	back.Parent = gui
	gradient(back, 90, Color3.fromRGB(8, 14, 40), Color3.fromRGB(24, 92, 210))
	-- Light-burst behind the action: rays from just above the middle.
	for i = 0, 11 do
		streak(gui, UDim2.fromScale(0.55, 0.5), UDim2.fromScale(1.9, 0.035), i * 15, Color3.fromRGB(150, 230, 255), 0.55, 1)
	end
	-- The action shot, tilted a touch, with dark shades top and bottom for the words.
	local photo = shotImage(gui, ACTION_SHOTS[3].image, 2)
	photo.AnchorPoint = Vector2.new(0.5, 0.5)
	photo.Position = UDim2.fromScale(0.5, 0.56)
	photo.Size = UDim2.fromScale(1.12, 0.7)
	photo.Rotation = -4
	local frame = Instance.new("UIStroke")
	frame.Thickness = 4
	frame.Color = Color3.fromRGB(255, 255, 255)
	frame.Parent = photo
	shade(gui, true, 0.36, 3)
	shade(gui, false, 0.3, 3)
	-- Speed lines and ice spray across the shot.
	local rng = Random.new(28)
	for _ = 1, 9 do
		streak(gui, UDim2.fromScale(rng:NextNumber(0.1, 0.9), rng:NextNumber(0.35, 0.75)), UDim2.fromScale(rng:NextNumber(0.3, 0.6), 0.008), -16, Color3.new(1, 1, 1), 0.15, 4)
	end
	for _ = 1, 16 do
		local chip = Instance.new("Frame")
		chip.AnchorPoint = Vector2.new(0.5, 0.5)
		local s = rng:NextNumber(0.012, 0.03)
		chip.Size = UDim2.fromScale(s, s * 0.75)
		chip.Position = UDim2.fromScale(rng:NextNumber(0.05, 0.45), rng:NextNumber(0.62, 0.8))
		chip.Rotation = rng:NextNumber(0, 90)
		chip.BackgroundColor3 = Color3.fromRGB(230, 248, 255)
		chip.BackgroundTransparency = rng:NextNumber(0, 0.4)
		chip.BorderSizePixel = 0
		chip.ZIndex = 4
		chip.Parent = gui
	end
	-- The title: a red drop shadow, then the gold-to-orange word on top, both slammed at an angle.
	local shadow = sportWords(gui, "PHYSHOCKEY", UDim2.fromScale(0.98, 0.16), UDim2.fromScale(0.025, 0.065), POSTER_RED, 5, 4)
	shadow.Rotation = -7
	local title = sportWords(gui, "PHYSHOCKEY", UDim2.fromScale(0.98, 0.16), UDim2.fromScale(0.005, 0.05), Color3.new(1, 1, 1), 6, 5)
	title.Rotation = -7
	gradient(title, 90, Color3.fromRGB(255, 236, 120), Color3.fromRGB(255, 132, 24))
	local kicker = sportWords(gui, "3v3 ONLINE HOCKEY", UDim2.fromScale(0.6, 0.045), UDim2.fromScale(0.2, 0.215), Color3.fromRGB(170, 236, 255), 6, 2)
	kicker.Rotation = -7
	-- A round "NEW SEASON" badge stamped top right.
	local badge = Instance.new("Frame")
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromScale(0.84, 0.34)
	badge.Size = UDim2.fromScale(0.24, 0.18)
	badge.SizeConstraint = Enum.SizeConstraint.RelativeXX
	badge.Rotation = 12
	badge.BackgroundColor3 = Color3.fromRGB(255, 200, 40)
	badge.BorderSizePixel = 0
	badge.ZIndex = 6
	badge.Parent = gui
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = badge
	local ring = Instance.new("UIStroke")
	ring.Thickness = 3
	ring.Color = POSTER_INK
	ring.Parent = badge
	sportWords(badge, "NEW\nSEASON", UDim2.fromScale(0.8, 0.6), UDim2.fromScale(0.1, 0.2), POSTER_INK, 7)
	-- Tilted red ribbon with the season's name.
	local ribbon = Instance.new("Frame")
	ribbon.AnchorPoint = Vector2.new(0.5, 0.5)
	ribbon.Position = UDim2.fromScale(0.5, 0.83)
	ribbon.Size = UDim2.fromScale(1.3, 0.1)
	ribbon.Rotation = -7
	ribbon.BackgroundColor3 = POSTER_RED
	ribbon.BorderSizePixel = 0
	ribbon.ZIndex = 6
	ribbon.Parent = gui
	local edge = Instance.new("UIStroke")
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Thickness = 3
	edge.Color = Color3.fromRGB(255, 255, 255)
	edge.Parent = ribbon
	sportWords(ribbon, "SEASON 1 · FIRST FREEZE", UDim2.fromScale(0.7, 0.72), UDim2.fromScale(0.15, 0.14), Color3.fromRGB(255, 255, 255), 7)
	sportWords(gui, "GRAB YOUR STICK. HIT THE ICE.", UDim2.fromScale(0.84, 0.045), UDim2.fromScale(0.08, 0.925), Color3.fromRGB(200, 236, 255), 6)
end

-- A framed print of one action shot with a caption strip.
local function actionPrint(p: BasePart, shot)
	local gui = surface(p, 50, 0.4)
	shotImage(gui, shot.image, 1)
	shade(gui, false, 0.4, 2)
	words(gui, shot.title, UDim2.fromScale(0.6, 0.18), UDim2.fromScale(0.05, 0.78), Color3.fromRGB(255, 255, 255), Enum.Font.FredokaOne, 3, 3)
end

-- The wall TV: the three shots on a slow crossfade loop, with a LIVE pill and a lower third.
local function highlightScreen(p: BasePart, owner: Instance)
	local gui = surface(p, 40, 0)
	gui.Brightness = 1.4
	local slides = {}
	for i, shot in ACTION_SHOTS do
		local img = shotImage(gui, shot.image, 1)
		img.ImageTransparency = if i == 1 then 0 else 1
		slides[i] = img
	end
	shade(gui, false, 0.36, 2)
	local pill = Instance.new("Frame")
	pill.Size = UDim2.fromScale(0.15, 0.1)
	pill.Position = UDim2.fromScale(0.04, 0.06)
	pill.BackgroundColor3 = POSTER_RED
	pill.BorderSizePixel = 0
	pill.ZIndex = 3
	pill.Parent = gui
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = pill
	words(pill, "● LIVE", UDim2.fromScale(0.8, 0.7), UDim2.fromScale(0.1, 0.15), Color3.fromRGB(255, 255, 255), Enum.Font.GothamBlack, 4)
	words(gui, "PHYSHOCKEY HIGHLIGHTS", UDim2.fromScale(0.5, 0.07), UDim2.fromScale(0.04, 0.72), Color3.fromRGB(150, 230, 255), Enum.Font.GothamBold, 3)
	local caption = words(gui, ACTION_SHOTS[1].title, UDim2.fromScale(0.7, 0.15), UDim2.fromScale(0.04, 0.8), Color3.fromRGB(255, 255, 255), Enum.Font.FredokaOne, 3, 3)
	caption.TextXAlignment = Enum.TextXAlignment.Left
	local alive = true
	owner.Destroying:Connect(function()
		alive = false
	end)
	task.spawn(function()
		local fade = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		local current = 1
		while alive do
			task.wait(5)
			if not (alive and owner.Parent) then
				break
			end
			local nextIndex = current % #slides + 1
			-- The next slide sits on top and fades in over the current one.
			slides[nextIndex].ZIndex = 1
			slides[current].ZIndex = 0
			TweenService:Create(slides[nextIndex], fade, { ImageTransparency = 0 }):Play()
			caption.Text = ACTION_SHOTS[nextIndex].title
			task.wait(0.9)
			slides[current].ImageTransparency = 1
			current = nextIndex
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Ice
---------------------------------------------------------------------------------------------

local function buildIce(parent: Instance, theme: Theme, origin: Vector3?)
	local o = origin or Vector3.zero
	-- The slab covers the whole rounded rink; the corners outside the boards hide under them.
	-- Outdoors the rinks sit on the frozen lake, which is already level ice: a slab of their own
	-- there would share the lake's top face and flicker, so they only get their painted lines.
	-- Build 34: only the lake rinks; the shop rinks stand on their own ground and need a slab.
	local onLake = not theme.indoor and (theme.scenery == nil or theme.scenery == "lake")
	if theme.indoor then
		part(parent, "Ice", Vector3.new(ARENA.Length + 2, 2, ARENA.Width + 2), CFrame.new(o + Vector3.new(0, -1, 0)), theme.ice, Enum.Material.SmoothPlastic)
	elseif not onLake then
		-- Build 34: outdoors nothing hides the slab's corners, so it is rounded like the boards.
		local lx, lz, lr = HX + 1, HZ + 1, CR + 1
		local ix, iz = lx - lr, lz - lr
		part(parent, "Ice", Vector3.new(lx * 2, 2, iz * 2), CFrame.new(o + Vector3.new(0, -1, 0)), theme.ice, Enum.Material.SmoothPlastic)
		part(parent, "Ice", Vector3.new(ix * 2, 2, lz * 2), CFrame.new(o + Vector3.new(0, -1, 0)), theme.ice, Enum.Material.SmoothPlastic)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				disc(parent, "Ice", lr * 2, 2, CFrame.new(o + Vector3.new(sx * ix, -1, sz * iz)), theme.ice, Enum.Material.SmoothPlastic)
			end
		end
	end

	local plane = part(parent, "Markings", Vector3.new(ARENA.Length, 0.02, ARENA.Width), CFrame.new(o + Vector3.new(0, 0.02, 0)), theme.ice, nil, 1)
	local PPS = 10
	local gui = Instance.new("SurfaceGui")
	gui.Name = "IceMarkings"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PPS
	gui.LightInfluence = 1
	gui.ClipsDescendants = true
	gui.Parent = plane

	-- On a Top face of an unrotated part the canvas is 92 x 180 studs: canvas X runs along
	-- world Z and canvas Y along world X (measured in Studio). Markings are symmetric, so
	-- only the axis swap matters.
	local function px(x: number): number
		return (x + HX) * PPS
	end
	local function pz(z: number): number
		return (z + HZ) * PPS
	end
	local function rect(x: number, z: number, sx: number, sz: number, color: Color3, transparency: number?, rotation: number?)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromOffset(pz(z), px(x))
		f.Size = UDim2.fromOffset(sz * PPS, sx * PPS)
		f.BackgroundColor3 = color
		f.BackgroundTransparency = transparency or 0
		f.BorderSizePixel = 0
		f.Rotation = rotation or 0
		f.Parent = gui
		return f
	end
	local function circle(x: number, z: number, radius: number, color: Color3, thickness: number, fill: number?)
		local f = rect(x, z, radius * 2, radius * 2, color, fill or 1)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = f
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = thickness * PPS
		stroke.Parent = f
		return f, stroke
	end

	-- Scratches first so the paint sits on top.
	local rng = Random.new(77)
	-- The pond's ice is kept clean: only a handful of marks.
	for _ = 1, if onLake then 26 else 260 do
		local x = rng:NextNumber(-HX + 4, HX - 4)
		local z = rng:NextNumber(-HZ + 4, HZ - 4)
		local len = rng:NextNumber(3, 16)
		rect(x, z, len, 0.12, Color3.new(1, 1, 1), theme.scratch + rng:NextNumber(0, 0.2), rng:NextNumber(-60, 60))
	end
	for _ = 1, if onLake then 3 else 40 do
		local x = rng:NextNumber(-HX + 10, HX - 10)
		local z = rng:NextNumber(-HZ + 8, HZ - 8)
		local r = rng:NextNumber(4, 9)
		local _, stroke = circle(x, z, r, Color3.new(1, 1, 1), 0.12)
		stroke.Transparency = math.min(0.95, theme.scratch + 0.12)
	end

	-- Lines.
	rect(0, 0, 1.1, ARENA.Width, theme.red)
	for _, sx in { -1, 1 } do
		rect(sx * ARENA.BlueLineX, 0, 1.3, ARENA.Width, theme.blue)
		-- The goal line runs right to the boards (they cover the last bit), like the reference.
		local cr = ARENA.CornerRadius
		local intoCorner = math.max(0, GOAL.X - (HX - cr))
		local halfAcross = HZ - cr + math.sqrt(math.max(0, cr * cr - intoCorner * intoCorner))
		rect(sx * GOAL.X, 0, GOAL.LineWidth, halfAcross * 2 + 1, theme.red)
	end

	-- Centre circle and dot.
	circle(0, 0, 13, theme.blue, 0.5)
	circle(0, 0, 0.7, theme.blue, 0.2, 0)

	-- End-zone faceoff circles with hash marks and L-shaped spot marks: big circles out toward
	-- the side boards whose near edge almost reaches the goal line (fitted to the reference).
	local FACEOFF_R = 15
	local spotX, spotZ = GOAL.X - FACEOFF_R - 1.5, 31
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local cx, cz = sx * spotX, sz * spotZ
			circle(cx, cz, FACEOFF_R, theme.red, 0.45)
			circle(cx, cz, 0.8, theme.red, 0.2, 0)
			for _, hx in { -1, 1 } do
				for _, hz in { -1, 1 } do
					rect(cx + hx * 2.2, cz + hz * 1.6, 0.3, 1.8, theme.red)
					rect(cx + hx * 3.0, cz + hz * 0.8, 1.6, 0.3, theme.red)
				end
				-- Hash marks outside the circle.
				rect(cx + hx * 1.8, cz + FACEOFF_R + 0.9, 0.3, 1.8, theme.red)
				rect(cx + hx * 1.8, cz - FACEOFF_R - 0.9, 0.3, 1.8, theme.red)
			end
		end
		-- Neutral-zone dots.
		for _, sz in { -1, 1 } do
			circle(sx * (ARENA.BlueLineX - 6), sz * spotZ, 0.8, theme.red, 0.2, 0)
		end
		-- Crease, NHL shape: 8 ft wide (straight red sides running 4.5 ft out from the goal line)
		-- closed by a 6 ft arc round the middle of the goal line, here at 2.2 studs a foot. Drawn as
		-- a disc clipped to the crease's box, so nothing is painted behind the line or past the
		-- sides, plus the two side lines.
		local HALF_W, ARC_R = 8.8, 13.2
		local sideLen = math.sqrt(ARC_R * ARC_R - HALF_W * HALF_W)
		local clip = rect(sx * (GOAL.X - ARC_R / 2), 0, ARC_R, HALF_W * 2, theme.ice, 1)
		clip.ClipsDescendants = true
		local crease = circle(sx * GOAL.X, 0, ARC_R, theme.red, 0.25, 0.35)
		crease.BackgroundColor3 = theme.crease
		crease.Parent = clip
		crease.Position = UDim2.fromOffset(HALF_W * PPS, px(sx * GOAL.X) - px(sx * (GOAL.X - ARC_R / 2)) + ARC_R / 2 * PPS)
		for _, sz in { -1, 1 } do
			rect(sx * (GOAL.X - sideLen / 2), sz * (HALF_W - 0.125), sideLen, 0.25, theme.red)
		end
	end

	-- Centre logo, faint, readable from the default camera.
	local logo = Instance.new("TextLabel")
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.Position = UDim2.fromOffset(pz(0), px(0))
	logo.Size = UDim2.fromOffset(9 * PPS, 20 * PPS)
	logo.Rotation = 90
	logo.BackgroundTransparency = 1
	logo.Font = Enum.Font.FredokaOne
	logo.Text = ""
	logo.Parent = gui
end

---------------------------------------------------------------------------------------------
-- Boards and glass
---------------------------------------------------------------------------------------------

-- One board panel: a white face over a dark kick plate along the ice, a flat cap with a
-- rounded rail on its ice-side edge, and (indoors) a glass pane with a thin rail along its top.
-- On a curve (`arc` = the angle the panel turns through, `radius` = the curve's radius at the
-- board face) every piece is sized to its own radius so neighbours meet edge to edge.
-- Overlapping faces at the same depth are what made the old corners shimmer (z-fighting), so
-- nothing here overlaps in the same plane; the rails, which must overlap a little to stay
-- continuous, alternate height by `parity`.
local GLASS_TINT = Color3.fromRGB(200, 222, 240)
local function boardSegment(parent: Instance, center: Vector3, inward: Vector3, width: number, theme: Theme, glass: boolean, arc: number?, radius: number?, parity: number?): Part
	local thick = 1.2
	local pos = Vector3.new(center.X, BOARD_H / 2, center.Z) - inward * (thick / 2)
	local cf = CFrame.lookAt(pos, pos + inward)
	local function across(frontRadius: number): number
		if arc and radius then
			return 2 * frontRadius * math.tan(arc / 2)
		end
		return width
	end
	local r = radius or 0
	local lift = if parity == 1 then 0.03 else 0
	local board = part(parent, "Board", Vector3.new(across(r), BOARD_H, thick), cf, theme.board)
	-- Kick plate: a hair proud of the face (never the same plane), taller than before so the
	-- dark band reads from the high camera like the reference rinks.
	part(parent, "Kick", Vector3.new(across(r - 0.04), 1.0, thick + 0.08), cf * CFrame.new(0, -BOARD_H / 2 + 0.5, 0), theme.kick)
	-- The top of the boards, under the glass, is each team's colour in its own half (Build 29):
	-- blue at the -X end, red at the +X end.
	local function teamColor(x: number): Color3
		return if x < 0 then theme.blue else theme.red
	end
	if math.abs(center.X) < 0.5 and not arc then
		-- The panel across centre ice: each half of its top in its own team's colour.
		for _, k in { -1, 1 } do
			local half = cf * CFrame.new(k * width / 4, 0, 0)
			local color = teamColor(half.Position.X)
			part(parent, "Cap", Vector3.new(width / 2, 0.3, thick + 0.4), half * CFrame.new(0, BOARD_H / 2 + 0.15 + lift, 0.05), color)
			local rail = part(parent, "Rail", Vector3.new(width / 2 + 0.02, 0.5, 0.5), half * CFrame.new(0, BOARD_H / 2 + 0.26 + lift, -thick / 2 - 0.02), color)
			rail.Shape = Enum.PartType.Cylinder
		end
	else
		local capColor = teamColor(center.X)
		part(parent, "Cap", Vector3.new(across(r + 0.4), 0.3, thick + 0.4), cf * CFrame.new(0, BOARD_H / 2 + 0.15 + lift, 0.05), capColor)
		local rail = part(parent, "Rail", Vector3.new(across(r - 0.25) + 0.04, 0.5, 0.5), cf * CFrame.new(0, BOARD_H / 2 + 0.26 + lift, -thick / 2 - 0.02), capColor)
		rail.Shape = Enum.PartType.Cylinder
	end
	if glass then
		local g = part(parent, "Glass", Vector3.new(across(r + 0.3), 6, 0.15), cf * CFrame.new(0, BOARD_H / 2 + 3.4, 0.3), GLASS_TINT, Enum.Material.Glass, 0.8)
		g.CastShadow = false
		part(parent, "GlassRail", Vector3.new(across(r + 0.3) + 0.03, 0.2, 0.3), cf * CFrame.new(0, BOARD_H / 2 + 6.45 + lift, 0.3), theme.rail)
	end
	return board
end

-- Sponsor panels: each message sits on its own coloured, rounded panel above the kick plate,
-- so the boards read as real rink advertising instead of loose text.
local function adBoard(board: Part, messages: { string }, theme: Theme)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Ads"
	-- The board faces inward along its LookVector, so the ads go on the Front face.
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 16
	gui.LightInfluence = 0.8
	gui.Parent = board
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	-- The kick plate covers the bottom stud and the rail the top edge; panels sit between.
	holder.Position = UDim2.fromScale(0, 0.1)
	holder.Size = UDim2.fromScale(1, 0.66)
	holder.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 40)
	layout.Parent = holder
	for i, message in messages do
		local panel = Instance.new("Frame")
		panel.Size = UDim2.new(1 / #messages, -40, 0.82, 0)
		panel.BackgroundColor3 = if i % 2 == 0 then theme.adAccent else theme.adText
		panel.BorderSizePixel = 0
		panel.Parent = holder
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = panel
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.fromScale(0.86, 0.66)
		-- Build 31: the game's own sport italic (the menu logo's font), not plain Gotham.
		label.FontFace = POSTER_SPORT
		label.Text = message
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.Parent = panel
	end
end

local function buildBoards(parent: Instance, theme: Theme)
	local ix, iz = HX - CR, HZ - CR
	local long = ix * 2
	local short = iz * 2
	local glass = theme.indoor
	-- A dark stanchion between glass panes, standing on the cap at `at` (on the board face line)
	-- with the glass plane `inward` of it.
	local function divider(at: Vector3, inward: Vector3)
		local pos = Vector3.new(at.X, BOARD_H + 3.4, at.Z) - inward * 0.9
		part(parent, "Divider", Vector3.new(0.28, 6.1, 0.36), CFrame.lookAt(pos, pos + inward), theme.rail)
	end
	-- Long sides are split in three so each panel carries readable ads.
	for _, sz in { -1, 1 } do
		for i = -1, 1 do
			local board = boardSegment(parent, Vector3.new(i * long / 3, 0, sz * HZ), Vector3.new(0, 0, -sz), long / 3, theme, glass)
			local a = SPONSORS[(i + 2 + (if sz > 0 then 3 else 0)) % #SPONSORS + 1]
			local b = SPONSORS[(i + 4 + (if sz > 0 then 1 else 0)) % #SPONSORS + 1]
			adBoard(board, { a, b }, theme)
		end
		if glass then
			local panes = math.max(1, math.round(long / 10))
			for k = 0, panes do
				divider(Vector3.new(-ix + long * k / panes, 0, sz * HZ), Vector3.new(0, 0, -sz))
			end
		end
	end
	for _, sx in { -1, 1 } do
		local board = boardSegment(parent, Vector3.new(sx * HX, 0, 0), Vector3.new(-sx, 0, 0), short, theme, glass)
		adBoard(board, { "PHYSHOCKEY" }, theme)
		if glass then
			local panes = math.max(1, math.round(short / 10))
			for k = 0, panes do
				divider(Vector3.new(sx * HX, 0, -iz + short * k / panes), Vector3.new(-sx, 0, 0))
			end
		end
	end
	-- Corners: 48 panels per quarter, each tangent to the curve, so the corner reads smooth.
	local segments = 48
	local arc = math.pi / 2 / segments
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local c = Vector3.new(sx * ix, 0, sz * iz)
			for i = 1, segments do
				local angle = (i - 0.5) * arc
				local outward = Vector3.new(sx * math.cos(angle), 0, sz * math.sin(angle))
				boardSegment(parent, c + outward * CR, -outward, 0, theme, glass, arc, CR, i % 2)
			end
			if glass then
				for i = 8, segments - 8, 8 do
					local angle = i * arc
					local outward = Vector3.new(sx * math.cos(angle), 0, sz * math.sin(angle))
					divider(c + outward * CR, -outward)
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Goals: a frame in the defending team's colour, white mesh
---------------------------------------------------------------------------------------------

local GOAL_RED = Color3.fromRGB(226, 44, 44)
local GOAL_BLUE = Color3.fromRGB(40, 104, 226) -- the blue (away) team's net
local NET_WHITE = Color3.fromRGB(248, 248, 250)

-- One triangle of netting from two wedges (each wedge is half of it, split at the foot of the
-- height from the longest side).
local function triangle(parent: Instance, a: Vector3, b: Vector3, c: Vector3, color: Color3, transparency: number)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	if ac:Cross(ab).Magnitude < 1e-6 then
		return
	end
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	for k = 1, 2 do
		local w = Instance.new("WedgePart")
		w.Name = "Net"
		w.Anchored = true
		w.CanCollide = false
		w.CanTouch = false
		w.CanQuery = false
		w.CastShadow = false
		w.Material = Enum.Material.SmoothPlastic
		w.Color = color
		w.Transparency = transparency
		if k == 1 then
			w.Size = Vector3.new(0.05, height, math.abs(ab:Dot(back)))
			w.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
		else
			w.Size = Vector3.new(0.05, height, math.abs(ac:Dot(back)))
			w.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
		end
		w.Parent = parent
	end
end

-- A traditional net built on the sim's own outline (Sim.NET_OUTLINE), so the puck stops exactly
-- on the netting you see: red posts and crossbar, a flat top shelf, netting sloping down to the
-- back, and a base tube that curves round the wide back corners.
-- origin: where the net's rink is centred (the pond's nets sit all round the lake).
local function buildGoal(parent: Instance, side: number, origin: Vector3?, name: string?): Model
	local o = origin or Vector3.zero
	local model = Instance.new("Model")
	model.Name = name or (if side == 1 then "GoalB" else "GoalA")
	local gx, w, h = GOAL.X, GOAL.Width, GOAL.CrossbarHeight
	local tube = GOAL.PostRadius * 2
	local outline = Sim.NET_OUTLINE
	-- Each net in its team's colour (Build 29): the -X net is the blue (away) team's, the +X
	-- net the red (home) team's.
	local frameColor = if side < 0 then GOAL_BLUE else GOAL_RED

	local function at(p: Vector2, y: number): Vector3
		return o + Vector3.new(side * (gx + p.X), y, p.Y)
	end
	local function mouth(z: number, y: number): Vector3
		return o + Vector3.new(side * gx, y, z)
	end
	local function top(p: Vector2): number
		return Sim.netRoofAt(p.X)
	end
	-- A round tube from a to b, with a ball at b so bends in a run of tubes stay round.
	local function bar(a: Vector3, b: Vector3, thickness: number, color: Color3, name: string, joint: boolean?)
		local mid, len = (a + b) / 2, (a - b).Magnitude
		if len < 1e-3 then
			return
		end
		local p = part(model, name, Vector3.new(len, thickness, thickness), CFrame.lookAt(mid, b) * CFrame.Angles(0, math.pi / 2, 0), color)
		p.Shape = Enum.PartType.Cylinder
		p.CastShadow = name ~= "Mesh"
		if joint then
			ball(model, name .. "Joint", Vector3.one * thickness, CFrame.new(b), color)
		end
	end

	-- Frame: posts, crossbar with rounded top corners, and the curved base and top tubes.
	-- Build 33: each post bends into the crossbar round a short arc (MouthCornerRadius).
	local mr = GOAL.MouthCornerRadius
	for _, sz in { -1, 1 } do
		local z = sz * w / 2
		bar(mouth(z, 0), mouth(z, h - mr), tube, frameColor, "Post", true)
		local prev = mouth(z, h - mr)
		for i = 1, 6 do
			local a = math.pi / 2 * i / 6
			local p = mouth(sz * (w / 2 - mr + math.cos(a) * mr), h - mr + math.sin(a) * mr)
			bar(prev, p, tube, frameColor, "Post", true)
			prev = p
		end
	end
	bar(mouth(-w / 2 + mr, h), mouth(w / 2 - mr, h), tube, frameColor, "Crossbar")
	for k = 1, #outline - 1 do
		local a, b = outline[k], outline[k + 1]
		bar(at(a, 0.15), at(b, 0.15), tube * 0.75, frameColor, "Base", true)
	end
	-- The top frame round the shelf: back from each post, across the net where the shelf ends
	-- (the top back bar, where the netting drops to the base), with wide rounded back corners.
	local shelf, rc = GOAL.ShelfDepth, 1.5 -- Build 33: 1.5 (was 1.2)
	local rim: { Vector2 } = { Vector2.new(0, -w / 2) }
	for i = 0, 8 do
		local a = math.pi / 2 * i / 8
		table.insert(rim, Vector2.new(shelf - rc + math.sin(a) * rc, -w / 2 + rc - math.cos(a) * rc))
	end
	for i = 0, 8 do
		local a = math.pi / 2 * i / 8
		table.insert(rim, Vector2.new(shelf - rc + math.cos(a) * rc, w / 2 - rc + math.sin(a) * rc))
	end
	table.insert(rim, Vector2.new(0, w / 2))
	for k = 1, #rim - 1 do
		bar(at(rim[k], h), at(rim[k + 1], h), tube * 0.6, frameColor, "TopFrame", true)
	end

	-- Netting: the walls round the outline, then the top, triangle by triangle.
	local NET_T = 0.62
	for k = 1, #outline - 1 do
		local a, b = outline[k], outline[k + 1]
		local a0, b0, a1, b1 = at(a, 0.05), at(b, 0.05), at(a, top(a)), at(b, top(b))
		triangle(model, a0, b0, b1, NET_WHITE, NET_T)
		triangle(model, a0, b1, a1, NET_WHITE, NET_T)
	end
	-- The outline is mirror-symmetric: point i pairs with point n + 1 - i across the net.
	local n = #outline
	for i = 1, n // 2 - 1 do
		local a, b = outline[i], outline[i + 1]
		local a2, b2 = outline[n + 1 - i], outline[n - i]
		local p1, p2, p3, p4 = at(a, top(a)), at(b, top(b)), at(b2, top(b2)), at(a2, top(a2))
		triangle(model, p1, p2, p3, NET_WHITE, NET_T)
		triangle(model, p1, p3, p4, NET_WHITE, NET_T)
	end

	-- Mesh lines: uprights at every outline point, rings round the walls, ribs across the top.
	local thin = 0.07
	for k = 2, n - 1 do
		local p = outline[k]
		bar(at(p, 0.1), at(p, top(p)), thin, NET_WHITE, "Mesh")
	end
	for ring = 1, 3 do
		local f = ring / 4
		for k = 1, n - 1 do
			local a, b = outline[k], outline[k + 1]
			bar(at(a, top(a) * f), at(b, top(b) * f), thin, NET_WHITE, "Mesh")
		end
	end
	for i = 2, n // 2 do
		local a, a2 = outline[i], outline[n + 1 - i]
		bar(at(a, top(a)), at(a2, top(a2)), thin, NET_WHITE, "Mesh")
	end
	model.Parent = parent
	return model
end

---------------------------------------------------------------------------------------------
-- Crowd: peg people on stepped seating
---------------------------------------------------------------------------------------------

-- more: extra parts that jump with the fan (the Moon Base aliens' eyes and antenna stalk).
export type Fan = { body: BasePart, head: BasePart, extra: BasePart?, home: CFrame, more: { BasePart }? }

local SHIRTS = {
	Color3.fromRGB(214, 56, 60),
	Color3.fromRGB(46, 92, 190),
	Color3.fromRGB(246, 246, 248),
	Color3.fromRGB(214, 56, 60),
	Color3.fromRGB(46, 92, 190),
	Color3.fromRGB(40, 40, 48),
	Color3.fromRGB(246, 246, 248),
	Color3.fromRGB(240, 170, 50),
}
local SKINS = {
	Color3.fromRGB(255, 219, 186),
	Color3.fromRGB(241, 194, 160),
	Color3.fromRGB(224, 172, 128),
	Color3.fromRGB(190, 132, 92),
	Color3.fromRGB(141, 92, 62),
}
local HAIRS = {
	Color3.fromRGB(46, 34, 30),
	Color3.fromRGB(96, 62, 38),
	Color3.fromRGB(176, 120, 64),
	Color3.fromRGB(30, 30, 36),
	Color3.fromRGB(196, 50, 56),
	Color3.fromRGB(46, 92, 190),
}

local function addFan(crowd: Instance, fans: { Fan }, rng: Random, home: CFrame)
	local shirt = SHIRTS[rng:NextInteger(1, #SHIRTS)]
	local body = ball(crowd, "Fan", Vector3.new(1.6, 2.0, 1.4), home * CFrame.new(0, 1.0, 0), shirt)
	local head = ball(crowd, "Head", Vector3.new(1.45, 1.45, 1.45), home * CFrame.new(0, 2.5, 0), SKINS[rng:NextInteger(1, #SKINS)])
	local extra: BasePart? = nil
	if rng:NextNumber() < 0.75 then
		extra = ball(crowd, "Hair", Vector3.new(1.55, 0.9, 1.55), home * CFrame.new(0, 2.85, 0.12), HAIRS[rng:NextInteger(1, #HAIRS)])
	end
	table.insert(fans, { body = body, head = head, extra = extra, home = home })
end

-- Stepped seating around a rectangle that hugs the rounded rink, with fans facing the ice.
local function buildStands(parent: Instance, theme: Theme, lowGraphics: boolean): { Fan }
	local stands = folder(parent, "Stands")
	local crowd = folder(parent, "Crowd")
	local fans: { Fan } = {}
	local rng = Random.new(2024)

	local walk = 7 -- concourse between glass and first row
	local rowDepth = 3.1
	local rowRise = 1.75
	local baseX, baseZ = HX + walk, HZ + walk
	local rows = theme.rows
	local fill = if lowGraphics then theme.crowdFill * 0.3 else theme.crowdFill

	-- Concourse: a walkway ring between the boards and the first row (never over the ice).
	local cy = BOARD_H - 0.7
	-- The walkway starts behind the boards (1.2 thick). Starting at the board face put its edge
	-- in the same plane as the face just under the rail, and the two flickered through each other.
	local inset = 1.25
	local deep = walk + 1 - inset
	for _, sz in { -1, 1 } do
		part(stands, "Concourse", Vector3.new(baseX * 2 + 2, 1, deep), CFrame.new(0, cy, sz * (HZ + inset + deep / 2)), theme.concourse)
	end
	for _, sx in { -1, 1 } do
		part(stands, "Concourse", Vector3.new(deep, 1, (HZ + inset) * 2), CFrame.new(sx * (HX + inset + deep / 2), cy, 0), theme.concourse)
	end
	-- Fill the square corners behind the curved boards, strip by strip, never over the ice.
	local step = 1.5
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local dx = 0 -- offset from the arc centre along X
			while dx < CR do
				-- The arc is furthest out at the strip's inner side, so the strip starts there.
				-- Measured from behind the curved boards, so no corner of a strip touches their face.
				local behind = CR + inset
				local edge = math.sqrt(math.max(0, behind * behind - dx * dx))
				local fromZ = HZ - CR + edge
				local depth = HZ - fromZ
				if depth > 0.05 then
					local width = math.min(step, CR - dx)
					local cx = HX - CR + dx + width / 2
					local h = cy + 0.5
					part(stands, "CornerFill", Vector3.new(width, h, depth), CFrame.new(sx * cx, h / 2, sz * (fromZ + depth / 2)), theme.concourse)
				end
				dx += step
			end
		end
	end

	local sectionWidth = 22
	for row = 0, rows - 1 do
		local outX = baseX + row * rowDepth
		local outZ = baseZ + row * rowDepth
		local y = BOARD_H + row * rowRise
		local longLen = (outX + rowDepth) * 2
		local shortLen = outZ * 2
		for _, sz in { -1, 1 } do
			part(stands, "Step", Vector3.new(longLen, y, rowDepth), CFrame.new(0, y / 2, sz * (outZ + rowDepth / 2)), theme.step)
		end
		for _, sx in { -1, 1 } do
			part(stands, "Step", Vector3.new(rowDepth, y, shortLen), CFrame.new(sx * (outX + rowDepth / 2), y / 2, 0), theme.step)
		end

		-- Seat strips in alternating red and blue sections, then fans.
		local function seatRun(a: Vector3, b: Vector3, facing: Vector3)
			local dir = (b - a)
			local len = dir.Magnitude
			local unit = dir.Unit
			local s = 0
			local section = 0
			while s < len do
				local segLen = math.min(sectionWidth, len - s)
				local mid = a + unit * (s + segLen / 2)
				local color = theme.seats[section % #theme.seats + 1]
				local cf = CFrame.lookAt(mid, mid + facing)
				part(stands, "Seats", Vector3.new(segLen - 1.2, 0.8, 1.4), cf * CFrame.new(0, 0.4, 0.5), color)
				part(stands, "SeatBack", Vector3.new(segLen - 1.2, 1.2, 0.35), cf * CFrame.new(0, 1.0, 1.25), color:Lerp(Color3.new(0, 0, 0), 0.15))
				local t = 0.9
				while t < segLen - 0.9 do
					if rng:NextNumber() < fill then
						addFan(crowd, fans, rng, cf * CFrame.new(-segLen / 2 + t, 0.2, 0.55))
					end
					t += 1.95
				end
				s += segLen
				section += 1
			end
		end
		for _, sz in { -1, 1 } do
			local zLine = sz * (outZ + rowDepth / 2)
			seatRun(Vector3.new(-outX, y, zLine), Vector3.new(outX, y, zLine), Vector3.new(0, 0, -sz))
		end
		for _, sx in { -1, 1 } do
			local xLine = sx * (outX + rowDepth / 2)
			seatRun(Vector3.new(xLine, y, -outZ + 4), Vector3.new(xLine, y, outZ - 4), Vector3.new(-sx, 0, 0))
		end
		if row % 2 == 1 then
			task.wait()
		end
	end

	local topX = baseX + rows * rowDepth
	local topZ = baseZ + rows * rowDepth
	local topY = BOARD_H + rows * rowRise

	if theme.indoor then
		-- Aisles cut through the seating.
		for _, sz in { -1, 1 } do
			for x = -88, 88, 44 do
				part(stands, "Aisle", Vector3.new(2.2, 0.4, rows * rowDepth), CFrame.new(x, BOARD_H + rows * rowRise / 2 + 0.2, sz * (baseZ + rows * rowDepth / 2)) * CFrame.Angles(sz * math.atan(rowRise / rowDepth), 0, 0), theme.concourse)
			end
		end
		-- Upper wall, light bands, roof (no shadow so the ice stays bright).
		local wallH = 60
		for _, sz in { -1, 1 } do
			part(stands, "UpperWall", Vector3.new(topX * 2 + 8, wallH, 3), CFrame.new(0, topY + wallH / 2 - 2, sz * (topZ + 1.5)), theme.wall)
			part(stands, "Band", Vector3.new(topX * 2 + 8, 1.2, 0.4), CFrame.new(0, topY + 3, sz * (topZ - 0.1)), Color3.fromRGB(60, 120, 230), Enum.Material.Neon)
		end
		for _, sx in { -1, 1 } do
			part(stands, "UpperWall", Vector3.new(3, wallH, topZ * 2 + 8), CFrame.new(sx * (topX + 1.5), topY + wallH / 2 - 2, 0), theme.wall)
			part(stands, "Band", Vector3.new(0.4, 1.2, topZ * 2 + 8), CFrame.new(sx * (topX - 0.1), topY + 3, 0), Color3.fromRGB(220, 60, 64), Enum.Material.Neon)
		end
		part(stands, "Roof", Vector3.new(topX * 2 + 10, 2, topZ * 2 + 10), CFrame.new(0, topY + wallH - 4, 0), theme.wall)

		-- Big screens above each end, facing the ice.
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local pos = Vector3.new(sx * (topX - 1.5), topY + 10, sz * 18)
				local screen = part(stands, "Screen", Vector3.new(26, 14, 1.2), CFrame.lookAt(pos, Vector3.new(0, topY + 6, sz * 18)), Color3.fromRGB(20, 22, 30))
				textSign(screen, Enum.NormalId.Front, "PHYSHOCKEY\nSEASON 1", Color3.fromRGB(255, 255, 255), Color3.fromRGB(34, 96, 200), Enum.Font.FredokaOne, 12)
			end
		end
		-- Team benches and penalty box on one long side, behind the glass.
		for _, sx in { -1, 1 } do
			local bench = part(stands, "Bench", Vector3.new(26, 1.6, 4), CFrame.new(sx * 22, BOARD_H - 0.4, -(HZ + 3.2)), Color3.fromRGB(30, 32, 40))
			bench.CastShadow = true
		end
	else
		-- Outdoor: wooden bleachers only (no walls), handled by the pond scenery.
	end
	return fans
end

---------------------------------------------------------------------------------------------
-- Pond scenery
---------------------------------------------------------------------------------------------

local SNOW = Color3.fromRGB(242, 246, 250)
local PINE = Color3.fromRGB(46, 96, 70)
local WOOD = Color3.fromRGB(122, 86, 58)
local DARK_WOOD = Color3.fromRGB(78, 56, 40)

local function pine(parent: Instance, pos: Vector3, scale: number)
	part(parent, "Trunk", Vector3.new(1.2, 4, 1.2) * scale, CFrame.new(pos + Vector3.new(0, 2 * scale, 0)), DARK_WOOD)
	for i = 0, 3 do
		local d = (9 - i * 2) * scale
		local y = (4 + i * 3.2) * scale
		disc(parent, "Needles", d, 3.2 * scale, CFrame.new(pos + Vector3.new(0, y, 0)), PINE)
		disc(parent, "SnowCap", d * 0.8, 0.5 * scale, CFrame.new(pos + Vector3.new(0, y + 1.7 * scale, 0)), SNOW)
	end
	ball(parent, "Top", Vector3.new(2, 2.6, 2) * scale, CFrame.new(pos + Vector3.new(0, 17 * scale, 0)), SNOW)
end

local function snowman(parent: Instance, pos: Vector3, facing: Vector3)
	local cf = CFrame.lookAt(pos, pos + facing)
	ball(parent, "Base", Vector3.new(5, 5, 5), cf * CFrame.new(0, 2.2, 0), SNOW)
	ball(parent, "Middle", Vector3.new(3.6, 3.6, 3.6), cf * CFrame.new(0, 5.3, 0), SNOW)
	ball(parent, "Head", Vector3.new(2.6, 2.6, 2.6), cf * CFrame.new(0, 7.8, 0), SNOW)
	for _, x in { -0.45, 0.45 } do
		ball(parent, "Coal", Vector3.new(0.35, 0.35, 0.35), cf * CFrame.new(x, 8.1, -1.15), Color3.fromRGB(30, 30, 34))
	end
	local nose = part(parent, "Carrot", Vector3.new(0.35, 0.35, 1.2), cf * CFrame.new(0, 7.8, -1.6), Color3.fromRGB(240, 130, 40))
	nose.Shape = Enum.PartType.Block
	disc(parent, "HatBrim", 2.8, 0.2, cf * CFrame.new(0, 8.95, 0), Color3.fromRGB(34, 34, 40))
	disc(parent, "Hat", 1.9, 1.6, cf * CFrame.new(0, 9.8, 0), Color3.fromRGB(34, 34, 40))
	part(parent, "Scarf", Vector3.new(2.8, 0.6, 2.8), cf * CFrame.new(0, 6.7, 0), Color3.fromRGB(214, 56, 60))
end

export type Penguin = { parts: { BasePart }, offsets: { CFrame }, home: Vector3, phase: number }

local function penguin(parent: Instance, pos: Vector3): Penguin
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	local function add(p: BasePart, offset: CFrame)
		table.insert(parts, p)
		table.insert(offsets, offset)
	end
	local black = Color3.fromRGB(34, 36, 46)
	local orange = Color3.fromRGB(246, 160, 40)
	add(ball(parent, "Body", Vector3.new(2.6, 3.6, 2.4), CFrame.identity, black), CFrame.new(0, 1.9, 0))
	add(ball(parent, "Belly", Vector3.new(2.0, 2.9, 1.4), CFrame.identity, SNOW), CFrame.new(0, 1.7, -0.6))
	add(ball(parent, "Head", Vector3.new(2.0, 2.0, 2.0), CFrame.identity, black), CFrame.new(0, 3.9, 0))
	for _, x in { -0.42, 0.42 } do
		add(ball(parent, "EyeWhite", Vector3.new(0.5, 0.55, 0.3), CFrame.identity, SNOW), CFrame.new(x, 4.05, -0.85))
		add(ball(parent, "Eye", Vector3.new(0.24, 0.3, 0.2), CFrame.identity, black), CFrame.new(x, 4.05, -0.98))
	end
	add(ball(parent, "Beak", Vector3.new(0.6, 0.35, 0.9), CFrame.identity, orange), CFrame.new(0, 3.75, -1.05))
	for _, x in { -0.6, 0.6 } do
		add(ball(parent, "Foot", Vector3.new(0.8, 0.3, 1.0), CFrame.identity, orange), CFrame.new(x, 0.15, -0.35))
		add(ball(parent, "Wing", Vector3.new(0.4, 2.2, 1.2), CFrame.identity, black), CFrame.new(x * 2.15, 2.1, 0) * CFrame.Angles(0, 0, x * 0.35))
	end
	local p: Penguin = { parts = parts, offsets = offsets, home = pos, phase = math.random() * 10 }
	local cfs = {}
	for i, offset in offsets do
		cfs[i] = CFrame.new(pos) * offset
	end
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	return p
end

local function cocoaStand(parent: Instance, pos: Vector3, facing: Vector3)
	local cf = CFrame.lookAt(pos, pos + facing)
	part(parent, "Counter", Vector3.new(16, 4, 4), cf * CFrame.new(0, 2, 0), DARK_WOOD)
	part(parent, "CounterTop", Vector3.new(16.6, 0.5, 4.6), cf * CFrame.new(0, 4.25, 0), WOOD)
	for _, x in { -7.6, 7.6 } do
		part(parent, "Pole", Vector3.new(0.8, 12, 0.8), cf * CFrame.new(x, 6, 1.6), DARK_WOOD)
	end
	local sign = part(parent, "Sign", Vector3.new(17, 3.6, 0.6), cf * CFrame.new(0, 12, 1.6), Color3.fromRGB(70, 36, 30))
	textSign(sign, Enum.NormalId.Front, "HOT COCOA", Color3.fromRGB(255, 236, 214), nil, Enum.Font.FredokaOne, 16)
	for i = -2, 2 do
		local mug = disc(parent, "Mug", 1.1, 1.3, cf * CFrame.new(i * 2.4, 5.1, -0.6), if i % 2 == 0 then Color3.fromRGB(240, 240, 240) else Color3.fromRGB(214, 56, 60))
		mug.CastShadow = true
	end
	part(parent, "Box", Vector3.new(3, 2, 2.4), cf * CFrame.new(6, 5.5, 0.4), Color3.fromRGB(206, 140, 60))
end

local function campfire(parent: Instance, pos: Vector3)
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		ball(parent, "Stone", Vector3.new(1.8, 1.3, 1.6), CFrame.new(pos + Vector3.new(math.cos(a) * 3.2, 0.5, math.sin(a) * 3.2)), Color3.fromRGB(200, 204, 214))
	end
	for i = 0, 2 do
		part(parent, "Log", Vector3.new(0.8, 0.8, 4.4), CFrame.new(pos + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, i * math.pi / 3, 0.15), DARK_WOOD)
	end
	local fire = ball(parent, "Fire", Vector3.new(1.8, 2.6, 1.8), CFrame.new(pos + Vector3.new(0, 1.8, 0)), Color3.fromRGB(255, 150, 40), Enum.Material.Neon)
	fire.Transparency = 0.15
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 160, 80)
	light.Range = 18
	light.Brightness = 2
	light.Parent = fire
	local smoke = Instance.new("ParticleEmitter")
	smoke.Rate = 6
	smoke.Lifetime = NumberRange.new(2, 3.5)
	smoke.Speed = NumberRange.new(3, 5)
	smoke.SpreadAngle = Vector2.new(12, 12)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	smoke.Color = ColorSequence.new(Color3.fromRGB(230, 230, 236))
	smoke.LightInfluence = 0.5
	smoke.Parent = fire
end

local function cabin(parent: Instance, pos: Vector3, facing: Vector3)
	local cf = CFrame.lookAt(pos, pos + facing)
	part(parent, "Walls", Vector3.new(24, 12, 16), cf * CFrame.new(0, 6, 0), Color3.fromRGB(96, 68, 48))
	for i = 0, 5 do
		part(parent, "LogLine", Vector3.new(24.2, 0.3, 16.2), cf * CFrame.new(0, 1 + i * 2, 0), DARK_WOOD)
	end
	part(parent, "RoofL", Vector3.new(26, 1, 11), cf * CFrame.new(0, 14.4, -4.2) * CFrame.Angles(math.rad(32), 0, 0), Color3.fromRGB(60, 44, 34))
	part(parent, "RoofR", Vector3.new(26, 1, 11), cf * CFrame.new(0, 14.4, 4.2) * CFrame.Angles(math.rad(-32), 0, 0), Color3.fromRGB(60, 44, 34))
	part(parent, "SnowL", Vector3.new(26.4, 0.6, 11.2), cf * CFrame.new(0, 15.0, -4.2) * CFrame.Angles(math.rad(32), 0, 0), SNOW)
	part(parent, "SnowR", Vector3.new(26.4, 0.6, 11.2), cf * CFrame.new(0, 15.0, 4.2) * CFrame.Angles(math.rad(-32), 0, 0), SNOW)
	part(parent, "Door", Vector3.new(4.4, 7.5, 0.3), cf * CFrame.new(0, 3.75, -8.1), DARK_WOOD)
	for _, x in { -7, 7 } do
		local w = part(parent, "Window", Vector3.new(4, 3.4, 0.3), cf * CFrame.new(x, 6.5, -8.1), Color3.fromRGB(255, 214, 140), Enum.Material.Neon)
		w.Transparency = 0.1
	end
	part(parent, "Chimney", Vector3.new(2.4, 7, 2.4), cf * CFrame.new(7, 16, 3), Color3.fromRGB(120, 120, 128))
end

local function stringLights(parent: Instance, a: Vector3, b: Vector3, count: number)
	local colors = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 220, 80), Color3.fromRGB(80, 200, 255), Color3.fromRGB(120, 255, 140) }
	for _, end_ in { a, b } do
		part(parent, "LightPole", Vector3.new(0.6, end_.Y, 0.6), CFrame.new(end_.X, end_.Y / 2, end_.Z), DARK_WOOD)
	end
	-- Build 31: a black wire runs pole to pole through every bulb (on their own the bulbs looked
	-- like they floated, or lay on the ground), and each bulb hangs just under it on a socket.
	local wire = Color3.fromRGB(18, 18, 20)
	local prev: Vector3? = nil
	for i = 0, count do
		local t = i / count
		local p = a:Lerp(b, t) - Vector3.new(0, math.sin(t * math.pi) * 2.5, 0)
		if prev then
			local mid = (prev + p) / 2
			local wirePart = part(parent, "Wire", Vector3.new(0.12, 0.12, (p - prev).Magnitude + 0.06), CFrame.lookAt(mid, p), wire)
			wirePart.CastShadow = false
		end
		prev = p
		if i > 0 and i < count then
			part(parent, "Socket", Vector3.new(0.22, 0.3, 0.22), CFrame.new(p - Vector3.new(0, 0.17, 0)), wire).CastShadow = false
			ball(parent, "Bulb", Vector3.new(0.6, 0.6, 0.6), CFrame.new(p - Vector3.new(0, 0.55, 0)), colors[i % #colors + 1], Enum.Material.Neon)
		end
	end
end

local function buildPondScenery(parent: Instance, penguins: { Penguin })
	local scene = folder(parent, "Scenery")
	part(scene, "Snow", Vector3.new(900, 2, 900), CFrame.new(0, -1.3, 0), SNOW)

	-- Wooden bleachers on both long sides.
	for _, sz in { -1, 1 } do
		for i = -1, 1 do
			local base = Vector3.new(i * 50, 0, sz * (HZ + 12))
			for step = 0, 3 do
				part(scene, "Bleacher", Vector3.new(30, 0.6, 2.4), CFrame.new(base + Vector3.new(0, 1.2 + step * 1.6, sz * step * 2.6)), WOOD)
			end
			for _, x in { -14, 14 } do
				part(scene, "Leg", Vector3.new(0.6, 6.4, 0.6), CFrame.new(base + Vector3.new(x, 3.2, sz * 4)), DARK_WOOD)
			end
		end
	end

	local rng = Random.new(5)
	-- Ring of pines around the clearing.
	for i = 1, 70 do
		local a = rng:NextNumber(0, math.pi * 2)
		local rx = rng:NextNumber(150, 260)
		local rz = rng:NextNumber(95, 190)
		pine(scene, Vector3.new(math.cos(a) * rx, 0, math.sin(a) * rz), rng:NextNumber(1.1, 2.0))
		if i % 10 == 0 then
			task.wait()
		end
	end
	for _ = 1, 22 do
		local x = rng:NextNumber(-200, 200)
		local z = rng:NextNumber(-150, 150)
		if math.abs(x) > HX + 30 or math.abs(z) > HZ + 34 then
			ball(scene, "Drift", Vector3.new(rng:NextNumber(8, 18), rng:NextNumber(2, 4), rng:NextNumber(6, 14)), CFrame.new(x, 0, z), SNOW)
		end
	end

	-- Social corner behind the far end: cabin, cocoa, campfire, snowmen, penguins.
	cabin(scene, Vector3.new(HX + 50, 0, -40), Vector3.new(-1, 0, 0.3))
	cocoaStand(scene, Vector3.new(HX + 30, 0, 34), Vector3.new(-1, 0, -0.4))
	campfire(scene, Vector3.new(HX + 26, 0, -4))
	for _, z in { -14, 6 } do
		part(scene, "LogSeat", Vector3.new(7, 1.4, 1.6), CFrame.new(HX + 26, 0.7, z) * CFrame.Angles(0, 0, 0), WOOD)
	end
	snowman(scene, Vector3.new(-HX - 22, 0, 28), Vector3.new(1, 0, -0.3))
	snowman(scene, Vector3.new(-HX - 30, 0, -20), Vector3.new(1, 0, 0.4))
	snowman(scene, Vector3.new(10, 0, HZ + 34), Vector3.new(0, 0, -1))
	stringLights(scene, Vector3.new(-60, 14, -(HZ + 24)), Vector3.new(60, 14, -(HZ + 24)), 28)
	stringLights(scene, Vector3.new(-60, 14, HZ + 26), Vector3.new(60, 14, HZ + 26), 28)
	for i = 0, 5 do
		table.insert(penguins, penguin(scene, Vector3.new(-HX - 12 - (i % 3) * 5, 0, -6 + i * 3.4)))
	end
	for i = 0, 2 do
		table.insert(penguins, penguin(scene, Vector3.new(HX + 18 + i * 4, 0, 12 + i * 2)))
	end
end

-- The Frozen Lake rink: the pond scenery (bleachers, pines, cabin, campfire, snowmen, penguins,
-- string lights) round a sheet of lake ice under the rink, snowbanks along the shore, warm lamp
-- posts (lit since the Build 39 daytime only as decoration), fans on the bleachers, and snow falling.
local function buildFrozenLake(parent: Instance, theme: Theme, penguins: { Penguin }, lowGraphics: boolean): { Fan }
	buildPondScenery(parent, penguins)
	-- Build 39: fans on the pond's wooden bleachers (buildPondScenery: three 30-stud sections a
	-- side, four steps each), facing the ice, so the lake has a crowd to cheer the goals.
	local crowd = folder(parent, "Crowd")
	local fans: { Fan } = {}
	do
		local crowdRng = Random.new(1939)
		local fill = if lowGraphics then theme.crowdFill * 0.3 else theme.crowdFill
		for _, sz in { -1, 1 } do
			for i = -1, 1 do
				for step = 0, 3 do
					local y = 1.2 + step * 1.6 + 0.3
					local z = sz * (HZ + 12 + step * 2.6)
					local x = i * 50 - 13
					while x <= i * 50 + 13 do
						if crowdRng:NextNumber() < fill then
							addFan(crowd, fans, crowdRng, CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(x, y, 0)))
						end
						x += 2.3
					end
				end
			end
			task.wait()
		end
	end
	local lake = folder(parent, "Lake")
	-- Lake ice under and round the rink (the rink itself only paints its lines on it). The shore
	-- follows the rink's own rounded outline, a fixed margin out, so the Frozen Lake is the same
	-- rink shape as every other arena with a ring of lake round it.
	local margin = 8
	local lx, lz, lr = HX + margin, HZ + margin, CR + margin
	local ix, iz = lx - lr, lz - lr
	part(lake, "LakeIce", Vector3.new(lx * 2, 2, iz * 2), CFrame.new(0, -1, 0), theme.ice)
	part(lake, "LakeIce", Vector3.new(ix * 2, 2, lz * 2), CFrame.new(0, -1, 0), theme.ice)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			disc(lake, "LakeIce", lr * 2, 2, CFrame.new(sx * ix, -1, sz * iz), theme.ice)
		end
	end
	-- True when (x, z) lies on the lake (inside the rounded shore), `pad` studs in from it.
	local function onLake(x: number, z: number, pad: number): boolean
		local dx, dz = math.max(0, math.abs(x) - ix), math.max(0, math.abs(z) - iz)
		return dx * dx + dz * dz <= (lr - pad) ^ 2
	end
	-- Darker, glassy patches and long cracks out past the boards: thick lake ice.
	local rng = Random.new(77)
	for _ = 1, 40 do
		local x, z = rng:NextNumber(-lx + 3, lx - 3), rng:NextNumber(-lz + 2, lz - 2)
		if (math.abs(x) > HX + 1 or math.abs(z) > HZ + 1) and onLake(x, z, 3) then
			local len = rng:NextNumber(3, 7)
			part(lake, "Crack", Vector3.new(len, 0.02, 0.1), CFrame.new(x, 0.01, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), Color3.fromRGB(240, 250, 255), nil, 0.5)
		end
	end
	-- Snowbanks heaped along the rounded shore, so the ice meets the snow in a soft edge.
	local step = 6
	local function bank(x: number, z: number, nx: number, nz: number)
		local at = Vector3.new(x + nx * 1.2, -0.2, z + nz * 1.2)
		local cf = CFrame.lookAt(at, at + Vector3.new(nx, 0, nz))
		ball(lake, "Snowbank", Vector3.new(step + 4, rng:NextNumber(1.6, 2.6), rng:NextNumber(3.5, 5)), cf, SNOW)
	end
	for _, s in { -1, 1 } do
		for x = -ix, ix, step do
			bank(x, s * lz, 0, s)
		end
		for z = -iz, iz, step do
			bank(s * lx, z, s, 0)
		end
	end
	local arcSteps = math.max(2, math.floor(lr * math.pi / 2 / step))
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			for i = 0, arcSteps do
				local a = (math.pi / 2) * i / arcSteps
				local nx, nz = sx * math.cos(a), sz * math.sin(a)
				bank(sx * ix + nx * lr, sz * iz + nz * lr, nx, nz)
			end
		end
	end
	-- Lamp posts at the four corners and halfway down each side, their warm light on the ice.
	local lamps = folder(parent, "Lamps")
	-- Corner lamps stand on the shore at the middle of each rounded corner.
	local cornerX, cornerZ = ix + (lr + 3) * 0.7071, iz + (lr + 3) * 0.7071
	for _, at in { Vector2.new(-1, -1), Vector2.new(-1, 1), Vector2.new(1, -1), Vector2.new(1, 1), Vector2.new(0, -1), Vector2.new(0, 1) } do
		local base = if at.X == 0 then Vector3.new(0, 0, at.Y * (lz + 3)) else Vector3.new(at.X * cornerX, 0, at.Y * cornerZ)
		part(lamps, "LampPost", Vector3.new(0.7, 22, 0.7), CFrame.new(base + Vector3.new(0, 11, 0)), DARK_WOOD)
		local head = part(lamps, "LampHead", Vector3.new(2.6, 1.0, 2.6), CFrame.new(base + Vector3.new(0, 22.4, 0)), Color3.fromRGB(44, 40, 38), Enum.Material.Metal)
		local glow = disc(lamps, "LampGlow", 2.2, 0.2, CFrame.new(base + Vector3.new(0, 21.85, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(255, 214, 150), Enum.Material.Neon)
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Bottom
		light.Angle = 80
		light.Range = 48
		light.Brightness = 1.4
		light.Color = Color3.fromRGB(255, 206, 150)
		light.Shadows = false
		light.Parent = head
		glow.CastShadow = false
	end
	-- String lights across the ice, end to end, above the glass line.
	stringLights(lamps, Vector3.new(-cornerX, 21, -cornerZ), Vector3.new(cornerX, 21, cornerZ), 40)
	stringLights(lamps, Vector3.new(-cornerX, 21, cornerZ), Vector3.new(cornerX, 21, -cornerZ), 40)
	-- Snow falling over the rink.
	if not lowGraphics then
		local sky = part(parent, "Snowfall", Vector3.new(HX * 2 + 80, 1, HZ * 2 + 80), CFrame.new(0, 60, 0), Color3.new(1, 1, 1), nil, 1)
		sky.CastShadow = false
		local snow = Instance.new("ParticleEmitter")
		snow.Shape = Enum.ParticleEmitterShape.Box
		snow.EmissionDirection = Enum.NormalId.Bottom
		snow.Rate = 140
		snow.Lifetime = NumberRange.new(9, 12)
		snow.Speed = NumberRange.new(5, 8)
		snow.SpreadAngle = Vector2.new(12, 12)
		snow.RotSpeed = NumberRange.new(-40, 40)
		snow.Size = NumberSequence.new(0.28)
		snow.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		snow.LightEmission = 0.3
		snow.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.1), NumberSequenceKeypoint.new(0.9, 0.1), NumberSequenceKeypoint.new(1, 1) })
		snow.Parent = sky
	end
	return fans
end

---------------------------------------------------------------------------------------------
-- Timberline (a Quick Play map): an outdoor rink in a forest clearing on a bright winter day.
-- The pond's rustic feel (wood, snow, pines, a warming hut, a campfire) but its own place: no
-- lake, no penguins, snow banked round the boards, timber bleachers full of fans, a log
-- scoreboard tower, lanterns, and mountains past the trees.
---------------------------------------------------------------------------------------------

local SPORT_FONT = Font.fromName("Sarpanch", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local SLATE = Color3.fromRGB(118, 128, 150)
local PACKED = Color3.fromRGB(226, 233, 240) -- trodden snow round the rink
local TIMBER_RED = Color3.fromRGB(176, 52, 46)

-- Big stepped mountains far beyond the trees (the atmosphere fades them into the sky).
local function mountain(parent: Instance, pos: Vector3, size: number)
	for i = 0, 4 do
		local d = size * (1 - i * 0.19)
		local h = size * 0.16
		disc(parent, "Mountain", d, h, CFrame.new(pos + Vector3.new(0, h * (i + 0.5), 0)), if i >= 3 then SNOW else SLATE)
	end
	ball(parent, "Peak", Vector3.new(size * 0.18, size * 0.2, size * 0.18), CFrame.new(pos + Vector3.new(0, size * 0.82, 0)), SNOW)
end

-- A stack of split firewood under a little roof.
local function woodpile(parent: Instance, pos: Vector3, facing: Vector3)
	local cf = CFrame.lookAt(pos, pos + facing)
	for row = 0, 3 do
		for i = -3, 3 do
			disc(parent, "Firewood", 1.3, 4, cf * CFrame.new(i * 1.25 + (row % 2) * 0.6, 0.7 + row * 1.15, 0) * CFrame.Angles(0, math.pi / 2, 0), if (i + row) % 3 == 0 then DARK_WOOD else WOOD)
		end
	end
	part(parent, "PileRoof", Vector3.new(10, 0.5, 5), cf * CFrame.new(0, 5.6, 0) * CFrame.Angles(math.rad(-12), 0, 0), DARK_WOOD)
	part(parent, "PileSnow", Vector3.new(10.2, 0.4, 5.2), cf * CFrame.new(0, 5.95, 0) * CFrame.Angles(math.rad(-12), 0, 0), SNOW)
end

-- A rack of hockey sticks leaning on a rail.
local function stickRack(parent: Instance, pos: Vector3, facing: Vector3)
	local cf = CFrame.lookAt(pos, pos + facing)
	part(parent, "RackRail", Vector3.new(10, 0.5, 0.5), cf * CFrame.new(0, 4, 0.6), DARK_WOOD)
	for _, x in { -4.6, 4.6 } do
		part(parent, "RackLeg", Vector3.new(0.5, 4.2, 0.5), cf * CFrame.new(x, 2.1, 0.6), DARK_WOOD)
	end
	for i = -3, 3 do
		local tilt = CFrame.Angles(math.rad(-14), 0, math.rad(i * 2))
		local shaft = part(parent, "RackStick", Vector3.new(0.25, 5.2, 0.35), cf * CFrame.new(i * 1.2, 2.6, 0) * tilt, if i % 2 == 0 then Color3.fromRGB(34, 36, 44) else WOOD)
		part(parent, "RackBlade", Vector3.new(0.25, 0.7, 1.6), shaft.CFrame * CFrame.new(0, -2.5, -0.6), if i % 3 == 0 then TIMBER_RED else Color3.fromRGB(34, 36, 44))
	end
end

-- A lantern on a post: warm light, small enough not to wash out the daylight.
local function lanternPost(parent: Instance, pos: Vector3)
	part(parent, "LanternPost", Vector3.new(0.6, 9, 0.6), CFrame.new(pos + Vector3.new(0, 4.5, 0)), DARK_WOOD)
	part(parent, "LanternArm", Vector3.new(0.4, 0.4, 2.2), CFrame.new(pos + Vector3.new(0, 8.8, 0.9)), DARK_WOOD)
	local glass = part(parent, "Lantern", Vector3.new(1.1, 1.5, 1.1), CFrame.new(pos + Vector3.new(0, 7.9, 1.8)), Color3.fromRGB(255, 206, 120), Enum.Material.Neon)
	glass.Transparency = 0.1
	part(parent, "LanternCap", Vector3.new(1.4, 0.35, 1.4), CFrame.new(pos + Vector3.new(0, 8.8, 1.8)), Color3.fromRGB(40, 38, 36), Enum.Material.Metal)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 196, 130)
	light.Range = 14
	light.Brightness = 0.8
	light.Shadows = false
	light.Parent = glass
end

-- A sign in the game's sport font (Sarpanch heavy italic, like the HUD and menus).
local function sportSign(p: BasePart, face: Enum.NormalId, text: string, color: Color3, ppS: number)
	textSign(p, face, text, color, nil, nil, ppS)
	local gui = p:FindFirstChildWhichIsA("SurfaceGui")
	local label = gui and gui:FindFirstChildWhichIsA("TextLabel")
	if label then
		label.FontFace = SPORT_FONT
	end
end

-- Timber bleachers along one long side (sz = -1 south, 1 north): plank rows on posts with fans
-- on every row; the big one gets a pitched roof on log columns.
local function bleachers(parent: Instance, crowd: Instance, fans: { Fan }, rng: Random, sz: number, rows: number, fill: number, roofed: boolean)
	local front = HZ + 9
	local width = ARENA.Length - 40
	for row = 0, rows - 1 do
		local z = sz * (front + row * 3)
		local y = 1.2 + row * 1.7
		part(parent, "Bench", Vector3.new(width, 0.6, 2.2), CFrame.new(0, y, z), WOOD)
		part(parent, "Riser", Vector3.new(width, y, 0.4), CFrame.new(0, y / 2, z + sz * 1.3), DARK_WOOD)
		local x = -width / 2 + 2
		while x < width / 2 - 2 do
			if rng:NextNumber() < fill then
				addFan(crowd, fans, rng, CFrame.lookAt(Vector3.new(x, y + 0.3, z), Vector3.new(x, y + 0.3, 0)))
			end
			x += 2.3
		end
	end
	local topRow = 1.2 + rows * 1.7
	for i = -4, 4 do
		part(parent, "BleacherPost", Vector3.new(0.7, topRow, 0.7), CFrame.new(i * width / 8, topRow / 2, sz * (front + (rows - 1) * 3 + 1.4)), DARK_WOOD)
	end
	if roofed then
		local back = sz * (front + rows * 3 + 1)
		local frontZ = sz * (front - 1.5)
		local topY = topRow + 10
		for i = -4, 4, 2 do
			local x = i * width / 8
			part(parent, "Column", Vector3.new(1.2, topY, 1.2), CFrame.new(x, topY / 2, back), DARK_WOOD)
			part(parent, "Column", Vector3.new(1.2, topY - 3, 1.2), CFrame.new(x, (topY - 3) / 2, frontZ), DARK_WOOD)
		end
		local depth = math.abs(back - frontZ) + 4
		local midZ = (back + frontZ) / 2
		local tilt = CFrame.Angles(-sz * math.rad(8), 0, 0)
		part(parent, "Roof", Vector3.new(width + 6, 0.8, depth), CFrame.new(0, topY - 1.2, midZ) * tilt, TIMBER_RED)
		part(parent, "RoofSnow", Vector3.new(width + 6.4, 0.6, depth + 0.4), CFrame.new(0, topY - 0.6, midZ) * tilt, SNOW)
		local fascia = part(parent, "Fascia", Vector3.new(width + 6, 2.4, 0.5), CFrame.lookAt(Vector3.new(0, topY - 3.2, frontZ - sz * 1.8), Vector3.new(0, topY - 3.2, 0)), DARK_WOOD)
		sportSign(fascia, Enum.NormalId.Front, "TIMBERLINE RINK  ·  EST. 1952", Color3.fromRGB(255, 236, 200), 10)
	end
end

-- The log scoreboard tower behind one end, carrying the game's name.
local function scoreTower(parent: Instance, pos: Vector3, facing: Vector3)
	local cf = CFrame.lookAt(pos, pos + facing)
	for _, x in { -9, 9 } do
		part(parent, "TowerLog", Vector3.new(1.6, 26, 1.6), cf * CFrame.new(x, 13, 0), DARK_WOOD)
	end
	part(parent, "TowerBeam", Vector3.new(21, 1.2, 1.4), cf * CFrame.new(0, 12.5, 0), DARK_WOOD)
	local board = part(parent, "ScoreBoard", Vector3.new(19, 8, 0.8), cf * CFrame.new(0, 19.5, 0), Color3.fromRGB(24, 30, 44))
	sportSign(board, Enum.NormalId.Front, Config.GameName, Color3.fromRGB(255, 200, 60), 12)
	local strip = part(parent, "ScoreStrip", Vector3.new(19, 2, 0.9), cf * CFrame.new(0, 14.4, 0), TIMBER_RED)
	sportSign(strip, Enum.NormalId.Front, "TIMBERLINE RINK", Color3.new(1, 1, 1), 12)
	part(parent, "TowerRoof", Vector3.new(22, 0.8, 3), cf * CFrame.new(0, 24.2, 0), DARK_WOOD)
	part(parent, "TowerSnow", Vector3.new(22.4, 0.6, 3.2), cf * CFrame.new(0, 24.7, 0), SNOW)
end

local function buildTimberline(parent: Instance, theme: Theme, lowGraphics: boolean): { Fan }
	local scene = folder(parent, "Timberline")
	local crowd = folder(parent, "Crowd")
	local fans: { Fan } = {}
	local rng = Random.new(1952)
	part(scene, "Snow", Vector3.new(1400, 2, 1400), CFrame.new(0, -1.3, 0), SNOW)

	-- Trodden snow round the boards, rounded like the rink, a step lower than the ice.
	local margin = 7
	local lx, lz, lr = HX + margin, HZ + margin, CR + margin
	local ix, iz = lx - lr, lz - lr
	part(scene, "Apron", Vector3.new(lx * 2, 1, iz * 2), CFrame.new(0, -0.62, 0), PACKED)
	part(scene, "Apron", Vector3.new(ix * 2, 1, lz * 2), CFrame.new(0, -0.62, 0), PACKED)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			disc(scene, "Apron", lr * 2, 1, CFrame.new(sx * ix, -0.62, sz * iz), PACKED)
		end
	end
	-- Snow ploughed off the ice, heaped behind the end boards.
	for _, sx in { -1, 1 } do
		for z = -iz - 10, iz + 10, 7 do
			ball(scene, "Snowbank", Vector3.new(rng:NextNumber(4, 6), rng:NextNumber(2, 3.4), 9), CFrame.new(sx * (HX + 5), 0, z), SNOW)
		end
	end

	-- Timber bleachers: the roofed main stand on the south side, a low stand on the north.
	local fill = if lowGraphics then 0.25 else theme.crowdFill
	bleachers(scene, crowd, fans, rng, -1, theme.rows, fill, true)
	task.wait()
	bleachers(scene, crowd, fans, rng, 1, 3, fill * 0.8, false)
	task.wait()

	-- Lanterns round the rink, string lights over the north side.
	for _, sz in { -1, 1 } do
		for i = -2, 2 do
			lanternPost(scene, Vector3.new(i * 40, 0, sz * (HZ + 4.5)))
		end
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			lanternPost(scene, Vector3.new(sx * (ix + (lr - 2) * 0.7071), 0, sz * (iz + (lr - 2) * 0.7071)))
		end
	end
	stringLights(scene, Vector3.new(-HX + 10, 16, HZ + 6), Vector3.new(HX - 10, 16, HZ + 6), 34)

	-- West end: the log scoreboard tower and stick racks. East end: the warming hut, firewood
	-- and a campfire with log seats.
	scoreTower(scene, Vector3.new(-HX - 24, 0, 0), Vector3.new(1, 0, 0))
	stickRack(scene, Vector3.new(-HX - 14, 0, 30), Vector3.new(1, 0, 0))
	stickRack(scene, Vector3.new(-HX - 14, 0, -30), Vector3.new(1, 0, 0))
	snowman(scene, Vector3.new(-HX - 20, 0, -46), Vector3.new(1, 0, 0.5))
	cabin(scene, Vector3.new(HX + 40, 0, -26), Vector3.new(-1, 0, 0.2))
	local hutSign = part(scene, "HutSign", Vector3.new(14, 2.4, 0.4), CFrame.lookAt(Vector3.new(HX + 31.4, 10.6, -24.3), Vector3.new(0, 10.6, -6)), TIMBER_RED)
	sportSign(hutSign, Enum.NormalId.Front, "WARMING HUT", Color3.fromRGB(255, 236, 200), 14)
	woodpile(scene, Vector3.new(HX + 36, 0, 8), Vector3.new(-1, 0, 0))
	campfire(scene, Vector3.new(HX + 26, 0, 28))
	for _, a in { 0, 2.1, 4.2 } do
		part(scene, "LogSeat", Vector3.new(6, 1.4, 1.6), CFrame.new(HX + 26 + math.cos(a) * 6.5, 0.7, 28 + math.sin(a) * 6.5) * CFrame.Angles(0, -a + math.pi / 2, 0), WOOD)
	end

	-- The forest: two loose rings of pines round the clearing, the far ring taller.
	local count = if lowGraphics then 60 else 120
	for i = 1, count do
		local a = rng:NextNumber(0, math.pi * 2)
		local far = i % 3 == 0
		local rx = if far then rng:NextNumber(230, 330) else rng:NextNumber(165, 230)
		local rz = if far then rng:NextNumber(170, 260) else rng:NextNumber(115, 170)
		pine(scene, Vector3.new(math.cos(a) * rx, 0, math.sin(a) * rz), if far then rng:NextNumber(1.8, 2.6) else rng:NextNumber(1.2, 1.9))
		if i % 12 == 0 then
			task.wait()
		end
	end
	-- Mountains past the trees.
	for i, spot in { Vector3.new(-520, 0, -420), Vector3.new(-120, 0, -560), Vector3.new(300, 0, -520), Vector3.new(600, 0, -200), Vector3.new(560, 0, 260), Vector3.new(-600, 0, 160) } do
		mountain(scene, spot, 260 + (i % 3) * 70)
	end

	-- Light snow drifting down.
	if not lowGraphics then
		local sky = part(parent, "Snowfall", Vector3.new(HX * 2 + 80, 1, HZ * 2 + 80), CFrame.new(0, 60, 0), Color3.new(1, 1, 1), nil, 1)
		local snow = Instance.new("ParticleEmitter")
		snow.Shape = Enum.ParticleEmitterShape.Box
		snow.EmissionDirection = Enum.NormalId.Bottom
		snow.Rate = 60
		snow.Lifetime = NumberRange.new(9, 12)
		snow.Speed = NumberRange.new(4, 6)
		snow.SpreadAngle = Vector2.new(15, 15)
		snow.RotSpeed = NumberRange.new(-40, 40)
		snow.Size = NumberSequence.new(0.25)
		snow.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		snow.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.15), NumberSequenceKeypoint.new(0.9, 0.15), NumberSequenceKeypoint.new(1, 1) })
		snow.Parent = sky
	end
	return fans
end

---------------------------------------------------------------------------------------------
-- The Pond open world (PondLayout): the lake, its shore, the open rink with boards only round
-- its ends, the mini-game stations and the 3v3 queue ring. The big rink at the origin is the
-- normal rink built above.
---------------------------------------------------------------------------------------------

local NEON_ORANGE = Color3.fromRGB(255, 96, 16) -- neon blooms lighter: this reads orange on the ice
local NEON_CYAN = Color3.fromRGB(80, 210, 255)

-- Points every `step` studs round a rounded box's edge, each with its outward normal.
local function aroundBox(b: PondLayout.Box, step: number): { { pos: Vector3, out: Vector3 } }
	local points = {}
	local ix, iz = b.hx - b.cr, b.hz - b.cr
	local function add(x: number, z: number, nx: number, nz: number)
		table.insert(points, { pos = Vector3.new(b.cx + x, 0, b.cz + z), out = Vector3.new(nx, 0, nz) })
	end
	for _, s in { -1, 1 } do
		for x = -ix, ix, step do
			add(x, s * b.hz, 0, s)
		end
		for z = -iz, iz, step do
			add(s * b.hx, z, s, 0)
		end
	end
	local arcSteps = math.max(2, math.floor(b.cr * math.pi / 2 / step))
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			for i = 1, arcSteps - 1 do
				local a = (math.pi / 2) * i / arcSteps
				local nx, nz = sx * math.cos(a), sz * math.sin(a)
				add(sx * ix + nx * b.cr, sz * iz + nz * b.cr, nx, nz)
			end
		end
	end
	return points
end

-- Rustic wooden boards for the open rink: weathered planks with a darker kick plank along the
-- ice, a split-log cap and posts behind. The ice-side face sits exactly where the sim's wall face
-- is (the same 1.2-thick panel as boardSegment), and nothing shares a plane with a neighbour.
local PLANK = Color3.fromRGB(168, 122, 80)
local PLANK_DARK = Color3.fromRGB(112, 78, 50)
local function rusticSegment(parent: Instance, center: Vector3, inward: Vector3, width: number, arc: number?, radius: number?, parity: number?, post: boolean?)
	local thick = 1.2
	local pos = Vector3.new(center.X, BOARD_H / 2, center.Z) - inward * (thick / 2)
	local cf = CFrame.lookAt(pos, pos + inward)
	local function across(frontRadius: number): number
		if arc and radius then
			return 2 * frontRadius * math.tan(arc / 2)
		end
		return width
	end
	local r = radius or 0
	local lift = if parity == 1 then 0.03 else 0
	part(parent, "Board", Vector3.new(across(r), BOARD_H, thick), cf, if parity == 1 then PLANK else PLANK:Lerp(PLANK_DARK, 0.12), Enum.Material.WoodPlanks)
	part(parent, "Kick", Vector3.new(across(r - 0.04), 0.8, thick + 0.08), cf * CFrame.new(0, -BOARD_H / 2 + 0.4, 0), PLANK_DARK, Enum.Material.Wood)
	part(parent, "Cap", Vector3.new(across(r + 0.4), 0.35, thick + 0.5), cf * CFrame.new(0, BOARD_H / 2 + 0.175 + lift, 0.05), PLANK_DARK, Enum.Material.Wood)
	if post then
		part(parent, "Post", Vector3.new(0.8, BOARD_H + 0.9, 0.8), cf * CFrame.new(0, 0.45, thick / 2 + 0.4), PLANK_DARK, Enum.Material.Wood)
	end
end

-- The open rink keeps its boards only round the ends: the end board behind each net and the two
-- corner curves on each end (exactly PondLayout's walls). The long sides are open.
local function buildEndBoards(parent: Instance, origin: Vector3)
	local ix, iz = HX - CR, HZ - CR
	for _, sx in { -1, 1 } do
		local steps = 6
		for i = 1, steps do
			local z = -iz + (i - 0.5) * (iz * 2 / steps)
			rusticSegment(parent, origin + Vector3.new(sx * HX, 0, z), Vector3.new(-sx, 0, 0), iz * 2 / steps, nil, nil, i % 2, true)
		end
		-- A painted sign on the end board, like a backyard rink.
		local sign = part(parent, "Sign", Vector3.new(16, 2.2, 0.12), CFrame.lookAt(origin + Vector3.new(sx * (HX - 0.07), BOARD_H * 0.55, 0), origin + Vector3.new(0, BOARD_H * 0.55, 0)), PLANK_DARK, Enum.Material.Wood)
		textSign(sign, Enum.NormalId.Front, "PHYSHOCKEY POND", Color3.fromRGB(246, 238, 220), nil, Enum.Font.FredokaOne, 24)
		for _, sz in { -1, 1 } do
			local c = origin + Vector3.new(sx * ix, 0, sz * iz)
			local segments = 48
			local arc = math.pi / 2 / segments
			for i = 1, segments do
				local angle = (i - 0.5) * arc
				local outward = Vector3.new(sx * math.cos(angle), 0, sz * math.sin(angle))
				rusticSegment(parent, c + outward * CR, -outward, 0, arc, CR, i % 2, i % 8 == 4)
			end
		end
	end
end

-- A floating sign over a ring: title, a line of help and (for stations) the pond record.
local function floatSign(parent: Instance, at: Vector3, title: string, blurb: string, color: Color3, recordName: string?)
	local anchor = part(parent, "SignAnchor", Vector3.new(0.2, 0.2, 0.2), CFrame.new(at + Vector3.new(0, 11, 0)), color, nil, 1)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(260, if recordName then 92 else 70)
	gui.LightInfluence = 0
	gui.MaxDistance = 140 -- far signs would pile on top of each other across the lake
	gui.AlwaysOnTop = false
	gui.Parent = anchor
	local box = Instance.new("Frame")
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundColor3 = Color3.fromRGB(28, 32, 46)
	box.BackgroundTransparency = 0.15
	box.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = box
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.Parent = box
	local function line(name: string, y: number, h: number, text: string, font: Enum.Font, c: Color3)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Position = UDim2.new(0, 10, 0, y)
		label.Size = UDim2.new(1, -20, 0, h)
		label.FontFace = gameFont(font)
		label.Text = text
		label.TextScaled = true
		label.TextWrapped = true
		label.TextColor3 = c
		label.Parent = box
	end
	line("Title", 6, 26, title, Enum.Font.FredokaOne, color)
	line("Blurb", 34, 30, blurb, Enum.Font.GothamBold, Color3.fromRGB(235, 240, 248))
	if recordName then
		line(recordName, 66, 18, "POND RECORD: NONE YET", Enum.Font.GothamBlack, Color3.fromRGB(255, 214, 90))
	end
end

-- A glowing ring on the ice to stand in: a thin neon band round a lightly tinted centre (an
-- opaque centre, so the neon reads as a ring and not a glowing disc).
local function standRing(parent: Instance, at: Vector3, radius: number, color: Color3, ice: Color3)
	disc(parent, "Ring", radius * 2, 0.06, CFrame.new(at + Vector3.new(0, 0.05, 0)), color, Enum.Material.Neon)
	disc(parent, "RingInner", radius * 2 - 1.2, 0.07, CFrame.new(at + Vector3.new(0, 0.055, 0)), ice:Lerp(color, 0.1), Enum.Material.SmoothPlastic)
end

local CONE_ORANGE = Color3.fromRGB(255, 120, 30)
local function cone(parent: Instance, at: Vector3)
	part(parent, "ConeBase", Vector3.new(1.8, 0.2, 1.8), CFrame.new(at + Vector3.new(0, 0.1, 0)), CONE_ORANGE)
	for i, d in { 1.4, 1.1, 0.8, 0.5 } do
		disc(parent, "Cone", d, 0.62, CFrame.new(at + Vector3.new(0, 0.2 + (i - 0.5) * 0.6, 0)), if i == 3 then SNOW else CONE_ORANGE)
	end
end

local function buildPondWorld(parent: Instance, theme: Theme, penguins: { Penguin })
	local L = PondLayout.LAYOUT
	local world = folder(parent, "PondWorld")
	local scene = folder(world, "Scenery")
	part(scene, "Snow", Vector3.new(1000, 2, 1000), CFrame.new(0, -1.3, 45), SNOW)

	-- The lake: one solid sheet of the rinks' ice, level with the rinks (on the pond the rinks
	-- don't get slabs of their own, only their painted lines). Three strips that only meet at
	-- their edges, with the round corners set a little lower so where they lie under the strips
	-- nothing shares a plane (overlapping faces at one height flicker).
	local b = L.bound
	local lake = folder(world, "Lake")
	local ic, iz = b.hx - b.cr, b.hz - b.cr
	part(lake, "LakeIce", Vector3.new(b.hx * 2, 2, iz * 2), CFrame.new(b.cx, -1, b.cz), theme.ice)
	for _, sz in { -1, 1 } do
		part(lake, "LakeIce", Vector3.new(ic * 2, 2, b.cr), CFrame.new(b.cx, -1, b.cz + sz * (iz + b.cr / 2)), theme.ice)
		for _, sx in { -1, 1 } do
			disc(lake, "LakeIce", b.cr * 2, 2, CFrame.new(b.cx + sx * ic, -1.05, b.cz + sz * iz), theme.ice)
		end
	end
	-- Just a few long skate marks out on the open ice.
	local rng = Random.new(31)
	for _ = 1, 28 do
		local x, z = rng:NextNumber(-b.hx + 20, b.hx - 20), rng:NextNumber(b.cz - b.hz + 20, b.cz + b.hz - 20)
		if Sim.boxSd(L.bound, x, z) < -10 and Sim.boxSd(L.blocks[1], x, z) > 6 then
			local len = rng:NextNumber(6, 16)
			part(lake, "Scratch", Vector3.new(len, 0.02, 0.12), CFrame.new(x, 0.01, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), Color3.new(1, 1, 1), nil, 0.72)
		end
	end

	-- The shore: a soft snowbank all the way round.
	local shore = folder(world, "Shore")
	for i, p in aroundBox(b, 8) do
		local along = Vector3.new(-p.out.Z, 0, p.out.X)
		local size = Vector3.new(rng:NextNumber(11, 16), rng:NextNumber(3.2, 5), rng:NextNumber(7, 10))
		ball(shore, "Snowbank", size, CFrame.fromMatrix(p.pos + p.out * (size.Z / 2 - 0.5), along, Vector3.yAxis), SNOW)
		if i % 25 == 0 then
			task.wait()
		end
	end

	-- The open rink: same lines and nets as the big rink, boards only round the ends.
	local openRink = folder(world, "OpenRink")
	local o = PondLayout.OPEN_CENTER
	buildIce(folder(openRink, "Ice"), theme, o)
	buildEndBoards(folder(openRink, "Boards"), o)
	buildGoal(openRink, -1, o, "OpenGoalA")
	buildGoal(openRink, 1, o, "OpenGoalB")
	-- String lights across both open sides, from the end of one curve to the other.
	for _, sz in { -1, 1 } do
		local z = o.Z + sz * (HZ + 0.6)
		stringLights(openRink, Vector3.new(-(HX - CR), 14, z), Vector3.new(HX - CR, 14, z), 40)
	end
	task.wait()

	-- The 3v3 queue: an orange ring just outside the big rink.
	local queue = folder(world, "Queue")
	standRing(queue, PondLayout.QUEUE, PondLayout.QUEUE_RADIUS, NEON_ORANGE, theme.ice)
	floatSign(queue, PondLayout.QUEUE, "PLAY 3v3", "Stand in the ring to join a match on this rink", NEON_ORANGE, nil)

	-- Mini-game stations: a net each, a start ring and a sign with the pond record.
	local games = folder(world, "MiniGames")
	for _, station in PondLayout.STATIONS do
		local n = L.nets[station.net]
		local stationFolder = folder(games, station.id)
		buildGoal(stationFolder, n.side, Vector3.new(n.x - n.side * GOAL.X, 0, n.z), `{station.id}Goal`)
		standRing(stationFolder, station.pad, PondLayout.PAD_RADIUS, NEON_CYAN, theme.ice)
		floatSign(stationFolder, station.pad, station.title, station.blurb, NEON_CYAN, `Record_{station.id}`)
		-- A painted spot where the game's puck appears.
		disc(stationFolder, "Spot", 2.2, 0.03, CFrame.new(station.spot + Vector3.new(0, 0.03, 0)), Color3.fromRGB(60, 120, 210))
		if station.id == "Targets" then
			for i, t in PondLayout.TARGETS do
				local center = Vector3.new(n.x + n.side * 0.25, t.Y, n.z + t.X)
				local ring = part(stationFolder, "TargetRing", Vector3.new(0.12, PondLayout.TARGET_RADIUS * 2 + 0.5, PondLayout.TARGET_RADIUS * 2 + 0.5), CFrame.new(center + Vector3.new(n.side * 0.05, 0, 0)), SNOW)
				ring.Shape = Enum.PartType.Cylinder
				local target = part(stationFolder, `Target{i}`, Vector3.new(0.14, PondLayout.TARGET_RADIUS * 2, PondLayout.TARGET_RADIUS * 2), CFrame.new(center), Color3.fromRGB(240, 70, 70), Enum.Material.Neon)
				target.Shape = Enum.PartType.Cylinder
				target.Transparency = 0.25
			end
		elseif station.id == "Slalom" then
			for _, g in PondLayout.GATES do
				for _, s in { -1, 1 } do
					cone(stationFolder, Vector3.new(g.X, 0, g.Y + s * PondLayout.GATE_HALF))
				end
			end
			-- Start line.
			part(stationFolder, "StartLine", Vector3.new(0.6, 0.03, 26), CFrame.new(PondLayout.SLALOM_START_X, 0.03, station.pad.Z), Color3.fromRGB(226, 52, 60))
		end
	end
	task.wait()

	-- Pines round the shore, the cabin corner west of the spawn, snowmen and penguins.
	local trees = 0
	for _, p in aroundBox(b, 14) do
		local offset = rng:NextNumber(14, 60)
		local at = p.pos + p.out * offset + Vector3.new(-p.out.Z, 0, p.out.X) * rng:NextNumber(-5, 5)
		-- Leave the cabin clearing open.
		if not (at.X < -170 and at.Z > 40 and at.Z < 150) then
			pine(scene, at, rng:NextNumber(1.1, 2.0))
			trees += 1
			if trees % 10 == 0 then
				task.wait()
			end
		end
	end
	cabin(scene, Vector3.new(b.cx - b.hx - 34, 0, 92), Vector3.new(1, 0, 0))
	cocoaStand(scene, Vector3.new(b.cx - b.hx - 16, 0, 58), Vector3.new(1, 0, 0.3))
	campfire(scene, Vector3.new(b.cx - b.hx - 16, 0, 128))
	for _, z in { 120, 136 } do
		part(scene, "LogSeat", Vector3.new(7, 1.4, 1.6), CFrame.new(b.cx - b.hx - 24, 0.7, z), WOOD)
	end
	snowman(scene, Vector3.new(b.cx + b.hx + 14, 0, 40), Vector3.new(-1, 0, 0))
	snowman(scene, Vector3.new(b.cx + b.hx + 18, 0, 160), Vector3.new(-1, 0, -0.3))
	snowman(scene, Vector3.new(30, 0, b.cz - b.hz - 14), Vector3.new(0, 0, 1))
	for i = 0, 5 do
		table.insert(penguins, penguin(scene, Vector3.new(b.cx - b.hx - 10 - (i % 3) * 4, 0, 18 + i * 3.4)))
	end
	for i = 0, 2 do
		table.insert(penguins, penguin(scene, Vector3.new(b.cx + b.hx + 10 + i * 4, 0, 96 + i * 2)))
	end
end

---------------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------------

export type Built = { model: Model, fans: { Fan }, penguins: { Penguin }, theme: Theme, bottles: { Model } }

-- A green squeeze bottle of sports drink lying on top of a net, behind the crossbar (Fx pops
-- it off when a shot goes in top shelf). The Blender model lives in
-- ReplicatedStorage.PropMeshes.DrinkBottle (bottom centre at the origin); a simple stand-in is
-- built when it is missing (a place file without the cloud meshes).
local function buildBottle(parent: Instance, side: number): Model
	-- Lying on its side across the top shelf (the pivot is the bottom of the bottle, on its axis),
	-- cap toward one post and turned a little off square.
	local spot = CFrame.new(side * (GOAL.X + GOAL.BottleDepth), GOAL.CrossbarHeight + 0.47, 0)
		* CFrame.Angles(0, math.rad(side * 8), 0)
		* CFrame.Angles(math.pi / 2, 0, 0)
		* CFrame.new(0, -1.15, 0)
	local props = game:GetService("ReplicatedStorage"):FindFirstChild("PropMeshes")
	local template = props and props:FindFirstChild("DrinkBottle")
	local model: Model
	if template and template:IsA("Model") then
		model = template:Clone()
	else
		model = Instance.new("Model")
		local green = Color3.fromRGB(70, 200, 60)
		local body = part(model, "Body", Vector3.new(1.7, 0.84, 0.84), CFrame.new(0, 0.85, 0) * CFrame.Angles(0, 0, math.pi / 2), green)
		body.Shape = Enum.PartType.Cylinder
		local cap = part(model, "Cap", Vector3.new(0.3, 0.7, 0.7), CFrame.new(0, 1.85, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(240, 240, 244))
		cap.Shape = Enum.PartType.Cylinder
		part(model, "Spout", Vector3.new(0.12, 0.5, 0.12), CFrame.new(0, 2.2, 0), Color3.fromRGB(240, 240, 244))
		model.WorldPivot = CFrame.new()
	end
	model.Name = "DrinkBottle"
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end
	model:PivotTo(spot)
	model:SetAttribute("Side", side)
	model.Parent = parent
	return model
end

---------------------------------------------------------------------------------------------
-- Build 34: the shop rinks' worlds. The rink itself is untouched; everything here sits outside
-- the boards (bleachers start 9 studs out, props further), and nothing collides.
---------------------------------------------------------------------------------------------

-- A wide ground plane and a rounded apron hugging the boards, a step under the ice.
local function groundAndApron(scene: Instance, ground: Color3, groundMat: Enum.Material, apron: Color3, apronMat: Enum.Material)
	part(scene, "Ground", Vector3.new(1400, 2, 1400), CFrame.new(0, -1.3, 0), ground, groundMat)
	local margin = 7
	local lx, lz, lr = HX + margin, HZ + margin, CR + margin
	local ix, iz = lx - lr, lz - lr
	part(scene, "Apron", Vector3.new(lx * 2, 1, iz * 2), CFrame.new(0, -0.62, 0), apron, apronMat)
	part(scene, "Apron", Vector3.new(ix * 2, 1, lz * 2), CFrame.new(0, -0.62, 0), apron, apronMat)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			disc(scene, "Apron", lr * 2, 1, CFrame.new(sx * ix, -0.62, sz * iz), apron, apronMat)
		end
	end
end

-- Build 35: a bleacher behind one end (sx = -1 west, 1 east), rows running along the end boards,
-- fans facing the ice. It stays inside the side stands' ends and the rink's corner billboards.
local END_ROWS = 6
local END_FRONT = HX + 10
local function endBleachers(parent: Instance, crowd: Instance, fans: { Fan }, rng: Random, sx: number, rows: number, fill: number)
	local width = (HZ - 6) * 2
	for row = 0, rows - 1 do
		local x = sx * (END_FRONT + row * 3)
		local y = 1.2 + row * 1.7
		part(parent, "Bench", Vector3.new(2.2, 0.6, width), CFrame.new(x, y, 0), WOOD)
		part(parent, "Riser", Vector3.new(0.4, y, width), CFrame.new(x + sx * 1.3, y / 2, 0), DARK_WOOD)
		local z = -width / 2 + 2
		while z < width / 2 - 2 do
			if rng:NextNumber() < fill then
				addFan(crowd, fans, rng, CFrame.lookAt(Vector3.new(x, y + 0.3, z), Vector3.new(0, y + 0.3, z)))
			end
			z += 2.3
		end
	end
	local topRow = 1.2 + rows * 1.7
	for i = -2, 2 do
		part(parent, "BleacherPost", Vector3.new(0.7, topRow, 0.7), CFrame.new(sx * (END_FRONT + (rows - 1) * 3 + 1.4), topRow / 2, i * width / 4), DARK_WOOD)
	end
	-- A rail along the back of the top row.
	part(parent, "BackRail", Vector3.new(0.5, 0.5, width), CFrame.new(sx * (END_FRONT + (rows - 1) * 3 + 1.4), topRow + 2.2, 0), DARK_WOOD)
end

-- The four corner billboards stand here (diagonally off each corner, between the stands).
local CORNER_BOARDS = {
	Vector3.new(-(HX + 18), 0, -(HZ + 30)),
	Vector3.new(HX + 18, 0, -(HZ + 30)),
	Vector3.new(-(HX + 18), 0, HZ + 30),
	Vector3.new(HX + 18, 0, HZ + 30),
}

-- A billboard on two posts facing centre ice: an action shot on one side and the words in the
-- game's sport face on the other, framed in the rink's colours.
local function billboard(scene: Instance, at: Vector3, width: number, height: number, lift: number, shot: { image: string, title: string }, title: string, kicker: string, board: Color3, ink: Color3, post: Color3, material: Enum.Material?)
	local cf = CFrame.lookAt(at, Vector3.new(0, at.Y, 0))
	local postH = lift + height
	for _, z in { -width * 0.36, width * 0.36 } do
		part(scene, "SignPost", Vector3.new(1.4, postH, 1.4), cf * CFrame.new(z, postH / 2, 0.8), post, material)
	end
	local centreY = lift + height / 2
	part(scene, "BillboardFrame", Vector3.new(width + 1.6, height + 1.6, 0.8), cf * CFrame.new(0, centreY, 0.3), post, material)
	local panel = part(scene, "Billboard", Vector3.new(width, height, 0.6), cf * CFrame.new(0, centreY, 0), board)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Billboard"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	-- Self-lit like a real billboard, so it reads on the night rinks (Volcano, Moon Base) too.
	gui.LightInfluence = 0
	gui.Brightness = 1.1
	gui.ClipsDescendants = true
	gui.Parent = panel
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.new(1, 1, 1)
	back.BorderSizePixel = 0
	back.Parent = gui
	gradient(back, 90, board:Lerp(Color3.new(1, 1, 1), 0.18), board:Lerp(Color3.new(0, 0, 0), 0.25))
	-- The photo, tilted a touch, white-edged.
	local photo = shotImage(gui, shot.image, 2)
	photo.AnchorPoint = Vector2.new(0.5, 0.5)
	photo.Position = UDim2.fromScale(0.27, 0.5)
	photo.Size = UDim2.fromScale(0.46, 0.84)
	photo.Rotation = -3
	local edge = Instance.new("UIStroke")
	edge.Thickness = 5
	edge.Color = Color3.new(1, 1, 1)
	edge.Parent = photo
	-- Light streaks behind the words.
	for i = 0, 2 do
		streak(gui, UDim2.fromScale(0.74, 0.3 + i * 0.2), UDim2.fromScale(0.7, 0.02), -8, Color3.new(1, 1, 1), 0.6, 1)
	end
	local kick = sportWords(gui, kicker, UDim2.fromScale(0.44, 0.16), UDim2.fromScale(0.52, 0.1), ink:Lerp(board, 0.25), 3, 2)
	kick.TextXAlignment = Enum.TextXAlignment.Left
	local big = sportWords(gui, title, UDim2.fromScale(0.45, 0.44), UDim2.fromScale(0.52, 0.28), ink, 3, 4)
	big.TextXAlignment = Enum.TextXAlignment.Left
	big.TextWrapped = true
	local tag = sportWords(gui, shot.title, UDim2.fromScale(0.3, 0.13), UDim2.fromScale(0.52, 0.76), Color3.new(1, 1, 1), 3, 2)
	tag.TextXAlignment = Enum.TextXAlignment.Left
	-- A lamp bar along the top so the board reads in every rink's light.
	part(scene, "BillboardLamp", Vector3.new(width * 0.8, 0.5, 0.8), cf * CFrame.new(0, lift + height + 1.2, -0.9), Color3.fromRGB(255, 250, 230), Enum.Material.Neon)
end

-- The rink's six billboards: one big one behind each end (above the end stand) and one off each
-- corner, each carrying a different action shot.
local function rinkBillboards(scene: Instance, titles: { string }, kicker: string, board: Color3, ink: Color3, post: Color3, material: Enum.Material?)
	local behind = END_FRONT + END_ROWS * 3 + 6
	billboard(scene, Vector3.new(-behind, 0, 0), 52, 20, 16, ACTION_SHOTS[1], titles[1], kicker, board, ink, post, material)
	billboard(scene, Vector3.new(behind, 0, 0), 52, 20, 16, ACTION_SHOTS[2], titles[2], kicker, board, ink, post, material)
	for i, at in CORNER_BOARDS do
		billboard(scene, at, 30, 12, 9, ACTION_SHOTS[(i + 1) % #ACTION_SHOTS + 1], titles[(i + 1) % #titles + 1], "PHYSHOCKEY", board, ink, post, material)
	end
end

-- The bleachers from Timberline (no roof), repainted in the rink's colours.
local function paintedBleachers(scene: Instance, crowd: Instance, fans: { Fan }, rng: Random, theme: Theme, lowGraphics: boolean, bench: Color3, riser: Color3, material: Enum.Material?)
	local stands = folder(scene, "Bleachers")
	local fill = if lowGraphics then 0.25 else theme.crowdFill
	-- Build 35: deeper side stands and a stand behind each net (the follow camera looks down the
	-- rink, so the far end's seats fill the background; it rides high enough to clear them).
	bleachers(stands, crowd, fans, rng, -1, theme.rows + 3, fill, false)
	task.wait()
	bleachers(stands, crowd, fans, rng, 1, theme.rows + 1, fill * 0.8, false)
	task.wait()
	for _, sx in { -1, 1 } do
		endBleachers(stands, crowd, fans, rng, sx, END_ROWS, fill * 0.7)
		task.wait()
	end
	for _, p in stands:GetChildren() do
		if p:IsA("BasePart") then
			p.Color = if p.Name == "Bench" then bench else riser
			p.Material = material or Enum.Material.SmoothPlastic
		end
	end
end

-- Spots on a loose ring round the rink, clear of the bleachers and the ends.
local function aroundRink(rng: Random, count: number, near: number, far: number, fn: (Vector3, number) -> ())
	for i = 1, count do
		local a = rng:NextNumber(0, math.pi * 2)
		local k = rng:NextNumber(near, far)
		local at = Vector3.new(math.cos(a) * (HX + 40) * k, 0, math.sin(a) * (HZ + 50) * k)
		local clear = true
		for _, board in CORNER_BOARDS do
			if (at - board).Magnitude < 26 then
				clear = false -- keep the corner billboards in view
			end
		end
		if clear then
			fn(at, i)
		end
		if i % 15 == 0 then
			task.wait()
		end
	end
end

-- Falling (or rising) bits over the rink: sprinkles, embers.
local function drift(parent: Instance, y: number, up: boolean, rate: number, colors: ColorSequence, size: number, light: number)
	local sky = part(parent, "Drift", Vector3.new(HX * 2 + 120, 1, HZ * 2 + 120), CFrame.new(0, y, 0), Color3.new(1, 1, 1), nil, 1)
	local e = Instance.new("ParticleEmitter")
	e.Shape = Enum.ParticleEmitterShape.Box
	e.EmissionDirection = if up then Enum.NormalId.Top else Enum.NormalId.Bottom
	e.Rate = rate
	e.Lifetime = NumberRange.new(8, 11)
	e.Speed = NumberRange.new(3, 5)
	e.SpreadAngle = Vector2.new(20, 20)
	e.RotSpeed = NumberRange.new(-60, 60)
	e.Rotation = NumberRange.new(0, 360)
	e.Size = NumberSequence.new(size)
	e.Color = colors
	e.LightEmission = light
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.1), NumberSequenceKeypoint.new(0.85, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = sky
end

-- A cylinder whose axis runs from `a` to `b`.
local function rod(parent: Instance, name: string, a: Vector3, b: Vector3, thick: number, color: Color3, material: Enum.Material?): Part
	local p = part(parent, name, Vector3.new((b - a).Magnitude, thick, thick), CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Build 37: horizon scenery. The replay's broadcast camera looks level across the rink, so the
-- outdoor rinks showed a flat edge of ground and then sky; each now has a ring of something tall
-- far out (mountains, dunes, trees) that closes the horizon. Kept within about 480 studs of the
-- rink centre (graphics quality 1 stops drawing parts at about 500 from the camera).
local function ellipseSpot(a: number, rx: number, rz: number): Vector3
	return Vector3.new(math.cos(a) * rx, 0, math.sin(a) * rz)
end

-- A faceted low-poly peak: a tall block stood on one corner, mostly under the ground, so three
-- flat faces meet at the summit. `size` shapes it (a tall, thin block gives a steep peak), `height`
-- is the summit; `cap` adds a smaller block on the same corner (snow, or a paler top).
local function facetPeak(parent: Instance, at: Vector3, size: Vector3, height: number, yaw: number, color: Color3, material: Enum.Material, cap: Color3?)
	local c = size.Unit
	local axis = c:Cross(Vector3.yAxis)
	local tip = CFrame.Angles(0, yaw, 0) * CFrame.fromAxisAngle(axis.Unit, math.acos(c.Y))
	local half = size.Magnitude / 2
	part(parent, "Peak", size, CFrame.new(at.X, height - half, at.Z) * tip, color, material)
	if cap then
		local k = 0.28
		part(parent, "PeakCap", size * k, CFrame.new(at.X, height + 1.2 - half * k, at.Z) * tip, cap, material)
	end
end

-- A full ring of peaks round the rink (two staggered rows, the back row taller).
local function peakRing(parent: Instance, rng: Random, count: number, color: Color3, dark: Color3, material: Enum.Material, cap: Color3?)
	for row = 0, 1 do
		for i = 1, count do
			local a = (i + row * 0.5) / count * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
			local r = if row == 0 then 1 else 1.12
			local at = ellipseSpot(a, 420 * r, 360 * r)
			local h = (if row == 0 then rng:NextNumber(70, 130) else rng:NextNumber(120, 190))
			local w = rng:NextNumber(70, 110)
			facetPeak(parent, at, Vector3.new(w, h * 1.7, w * rng:NextNumber(0.8, 1.2)), h, rng:NextNumber(0, 6.28), color:Lerp(dark, rng:NextNumber(0, 0.6)), material, if row == 1 or h > 115 then cap else nil)
		end
		task.wait()
	end
end

-- Stars: small glowing dots on a dome over the rink (a night sky the replay camera sees).
local function starDome(parent: Instance, rng: Random, count: number)
	local stars = folder(parent, "Stars")
	local tints = { rgb(255, 255, 255), rgb(200, 220, 255), rgb(255, 240, 200), rgb(220, 200, 255) }
	for i = 1, count do
		local a = rng:NextNumber(0, math.pi * 2)
		local up = math.asin(rng:NextNumber(0.12, 0.98)) -- more stars low over the hills than overhead
		local d = 400
		local at = Vector3.new(math.cos(a) * math.cos(up) * d, 60 + math.sin(up) * d * 0.8, math.sin(a) * math.cos(up) * d)
		local s = if rng:NextNumber() < 0.12 then rng:NextNumber(2.2, 3.2) else rng:NextNumber(0.9, 1.8)
		local star = part(stars, "Star", Vector3.new(s, s, s), CFrame.new(at), tints[i % #tints + 1], Enum.Material.Neon)
		star.Shape = Enum.PartType.Ball
		if i % 40 == 0 then
			task.wait()
		end
	end
end

-- Turns the crowd into little aliens, green and purple: an egg head with two big black eyes and
-- an antenna with a glowing tip, in a space suit.
local ALIEN_SKIN = { rgb(110, 220, 90), rgb(160, 92, 236), rgb(80, 196, 110), rgb(186, 120, 255) }
local ALIEN_SUIT = { rgb(214, 218, 228), rgb(70, 74, 92), rgb(120, 60, 180), rgb(60, 150, 70) }
local function alienCrowd(crowd: Instance, fans: { Fan }, rng: Random)
	for i, fan in fans do
		local skin = ALIEN_SKIN[rng:NextInteger(1, #ALIEN_SKIN)]
		fan.body.Color = ALIEN_SUIT[rng:NextInteger(1, #ALIEN_SUIT)]
		local head = fan.head
		head.Shape = Enum.PartType.Block
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = head
		head.Size = Vector3.new(1.55, 1.9, 1.5)
		head.CFrame = fan.home * CFrame.new(0, 2.65, 0)
		head.Color = skin
		if fan.extra then
			fan.extra:Destroy()
		end
		local knob = ball(crowd, "Antenna", Vector3.new(0.45, 0.45, 0.45), fan.home * CFrame.new(0, 4.05, 0.1), if rng:NextNumber() < 0.5 then rgb(140, 255, 120) else rgb(220, 140, 255), Enum.Material.Neon)
		fan.extra = knob
		local stalk = part(crowd, "Stalk", Vector3.new(0.12, 0.6, 0.12), fan.home * CFrame.new(0, 3.72, 0.06), skin)
		local more = { stalk }
		for _, x in { -0.3, 0.3 } do
			local eye = ball(crowd, "Eye", Vector3.new(0.42, 0.58, 0.22), fan.home * CFrame.new(x, 2.75, -0.66) * CFrame.Angles(0, 0, -x * 0.9), rgb(14, 12, 20), Enum.Material.SmoothPlastic)
			eye.Reflectance = 0.25
			table.insert(more, eye)
		end
		fan.more = more
		if i % 60 == 0 then
			task.wait()
		end
	end
end

-- Candy Land ---------------------------------------------------------------------------------
local CANDY = { rgb(255, 90, 150), rgb(120, 200, 255), rgb(255, 210, 70), rgb(140, 230, 150), rgb(190, 130, 255), rgb(255, 150, 90) }

local function lollipop(parent: Instance, pos: Vector3, s: number, color: Color3)
	part(parent, "LolliStick", Vector3.new(0.8 * s, 14 * s, 0.8 * s), CFrame.new(pos + Vector3.new(0, 7 * s, 0)), rgb(250, 250, 250))
	local centre = pos + Vector3.new(0, 15 * s, 0)
	local face = CFrame.lookAt(centre, Vector3.new(0, centre.Y, 0)) * CFrame.Angles(0, math.pi / 2, 0)
	for i, d in { 10, 7.4, 4.8, 2.2 } do
		local p = part(parent, "Lolli", Vector3.new(1.4 * s + i * 0.04, d * s, d * s), face, if i % 2 == 1 then color else rgb(255, 255, 255))
		p.Shape = Enum.PartType.Cylinder
	end
end

local function candyCane(parent: Instance, pos: Vector3, s: number)
	local h = 16 * s
	for i = 0, 7 do
		part(parent, "Cane", Vector3.new(1.4 * s, h / 8 + 0.02, 1.4 * s), CFrame.new(pos + Vector3.new(0, h / 8 * (i + 0.5), 0)), if i % 2 == 0 then rgb(230, 40, 60) else rgb(255, 255, 255))
	end
	local hookR = 3 * s
	local top = pos + Vector3.new(hookR, h, 0)
	for i = 0, 7 do
		local a = math.pi * i / 7
		ball(parent, "Hook", Vector3.new(1.6 * s, 1.6 * s, 1.6 * s), CFrame.new(top + Vector3.new(-math.cos(a) * hookR, math.sin(a) * hookR, 0)), if i % 2 == 0 then rgb(230, 40, 60) else rgb(255, 255, 255))
	end
end

local function cupcake(parent: Instance, pos: Vector3, s: number, frosting: Color3)
	disc(parent, "Cup", 8 * s, 4 * s, CFrame.new(pos + Vector3.new(0, 2 * s, 0)), rgb(255, 214, 110))
	ball(parent, "Frosting", Vector3.new(9 * s, 5 * s, 9 * s), CFrame.new(pos + Vector3.new(0, 5 * s, 0)), frosting)
	ball(parent, "Swirl", Vector3.new(5 * s, 4 * s, 5 * s), CFrame.new(pos + Vector3.new(0, 7.6 * s, 0)), frosting:Lerp(rgb(255, 255, 255), 0.35))
	ball(parent, "Cherry", Vector3.new(1.8 * s, 1.8 * s, 1.8 * s), CFrame.new(pos + Vector3.new(0, 10 * s, 0)), rgb(220, 20, 50))
end

local function candyHill(parent: Instance, pos: Vector3, size: number, color: Color3)
	for i = 0, 3 do
		local d = size * (1 - i * 0.22)
		local h = size * 0.14
		disc(parent, "CandyHill", d, h, CFrame.new(pos + Vector3.new(0, h * (i + 0.5), 0)), if i == 3 then rgb(255, 255, 255) else color)
	end
	ball(parent, "Icing", Vector3.new(size * 0.3, size * 0.22, size * 0.3), CFrame.new(pos + Vector3.new(0, size * 0.6, 0)), rgb(255, 255, 255))
end

-- Build 35 Candy Land extras ------------------------------------------------------------------
local function cottonCandyTree(parent: Instance, pos: Vector3, s: number, color: Color3)
	disc(parent, "CandyTrunk", 1.3 * s, 13 * s, CFrame.new(pos + Vector3.new(0, 6.5 * s, 0)), rgb(255, 255, 255))
	for i = 1, 3 do
		disc(parent, "TrunkStripe", 1.4 * s, 0.7 * s, CFrame.new(pos + Vector3.new(0, i * 3.2 * s, 0)), rgb(255, 90, 150))
	end
	for k, off in { Vector3.new(0, 14, 0), Vector3.new(3.4, 12.6, 1), Vector3.new(-3.2, 12.8, -1.2), Vector3.new(0.4, 17, 0.4) } do
		local size = if k == 4 then 5.6 else 8
		ball(parent, "Floss", Vector3.new(size, size * 0.86, size) * s, CFrame.new(pos + off * s), color:Lerp(rgb(255, 255, 255), 0.12 * k))
	end
end

local function iceCreamCone(parent: Instance, pos: Vector3, s: number, scoop: Color3, scoop2: Color3)
	-- The waffle cone stands point-down, built from thin rings widening upward.
	for i = 0, 5 do
		local d = (1.2 + i * 1.1) * s
		disc(parent, "Cone", d, 1.6 * s + 0.02, CFrame.new(pos + Vector3.new(0, (0.8 + i * 1.6) * s, 0)), if i % 2 == 0 then rgb(222, 164, 92) else rgb(206, 146, 76))
	end
	ball(parent, "Scoop", Vector3.new(7.4, 6.4, 7.4) * s, CFrame.new(pos + Vector3.new(0, 11, 0) * s), scoop)
	ball(parent, "Scoop", Vector3.new(6, 5.4, 6) * s, CFrame.new(pos + Vector3.new(0, 15, 0) * s), scoop2)
	ball(parent, "Drip", Vector3.new(1.6, 2.6, 1.6) * s, CFrame.new(pos + Vector3.new(2.6, 9.4, 1) * s), scoop)
	ball(parent, "Cherry", Vector3.new(1.8, 1.8, 1.8) * s, CFrame.new(pos + Vector3.new(0, 18.2, 0) * s), rgb(220, 20, 50))
end

local function gingerbreadHouse(parent: Instance, pos: Vector3, yaw: number)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	local GINGER, ICING = rgb(176, 104, 52), rgb(255, 255, 255)
	part(parent, "Gingerbread", Vector3.new(14, 10, 14), cf * CFrame.new(0, 5, 0), GINGER)
	-- Gables: a diamond turned 45 degrees, its lower half hidden in the walls.
	part(parent, "Gable", Vector3.new(13.6, 9.9, 9.9), cf * CFrame.new(0, 10, 0) * CFrame.Angles(math.pi / 4, 0, 0), GINGER)
	for _, side in { -1, 1 } do
		part(parent, "Roof", Vector3.new(16, 1.2, 11), cf * CFrame.new(0, 13.7, side * 3.6) * CFrame.Angles(side * math.pi / 4, 0, 0), rgb(255, 150, 200))
		part(parent, "RoofIcing", Vector3.new(16.4, 0.8, 1), cf * CFrame.new(0, 10, side * 7.5), ICING)
	end
	for k = -2, 2 do
		ball(parent, "Gumdrop", Vector3.new(1.8, 1.6, 1.8), cf * CFrame.new(k * 3, 17.6, 0), CANDY[k + 3])
	end
	part(parent, "Door", Vector3.new(3.6, 6, 0.4), cf * CFrame.new(0, 3, -7.1), rgb(110, 60, 30))
	part(parent, "DoorIcing", Vector3.new(4.4, 0.5, 0.5), cf * CFrame.new(0, 6.2, -7.2), ICING)
	for _, x in { -4.6, 4.6 } do
		part(parent, "Window", Vector3.new(2.6, 2.6, 0.4), cf * CFrame.new(x, 5.4, -7.1), rgb(255, 230, 120), Enum.Material.Neon)
		part(parent, "WindowIcing", Vector3.new(3.4, 0.5, 0.5), cf * CFrame.new(x, 6.9, -7.2), ICING)
	end
end

local function donut(parent: Instance, pos: Vector3, s: number, icing: Color3, rng: Random)
	local N = 10
	for k = 0, N - 1 do
		local a = k / N * math.pi * 2
		local at = pos + Vector3.new(math.cos(a) * 3.6 * s, 1.7 * s, math.sin(a) * 3.6 * s)
		ball(parent, "Dough", Vector3.new(3.6, 3.4, 3.6) * s, CFrame.new(at), rgb(226, 170, 100))
		ball(parent, "Icing", Vector3.new(3.4, 1.6, 3.4) * s, CFrame.new(at + Vector3.new(0, 1.1 * s, 0)), icing)
	end
	for _ = 1, 8 do
		local a = rng:NextNumber(0, math.pi * 2)
		part(parent, "Sprinkle", Vector3.new(0.3, 0.3, 1) * s, CFrame.new(pos + Vector3.new(math.cos(a) * 3.6 * s, 3.5 * s, math.sin(a) * 3.6 * s)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), CANDY[rng:NextInteger(1, #CANDY)])
	end
end

-- Balloon bunches tied to the ends of the side stands.
local function balloons(parent: Instance, pos: Vector3, rng: Random)
	for k = 1, 5 do
		local top = pos + Vector3.new(rng:NextNumber(-2.5, 2.5), 9 + k * 1.3, rng:NextNumber(-2.5, 2.5))
		ball(parent, "Balloon", Vector3.new(2.4, 2.9, 2.4), CFrame.new(top), CANDY[(k % #CANDY) + 1])
		rod(parent, "BalloonString", pos, top - Vector3.new(0, 1.4, 0), 0.08, rgb(255, 255, 255))
	end
end

-- Build 37: a tall, thin, striped trunk with a little bend, under one big fluffy tuft: the far
-- forest round Candy Land.
local TUFTS = { rgb(255, 92, 160), rgb(255, 170, 60), rgb(255, 226, 80), rgb(190, 120, 255), rgb(255, 80, 80), rgb(90, 220, 220) }
local function tuftTree(parent: Instance, pos: Vector3, height: number, color: Color3, rng: Random)
	local lean = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * height * 0.06
	local prev = pos
	local SEGS = 8
	for k = 1, SEGS do
		local t = k / SEGS
		-- Straight at the foot, bending more toward the top.
		local at = pos + Vector3.new(0, height * t, 0) + lean * t * t
		rod(parent, "TuftTrunk", prev, at, 2.2, if k % 2 == 0 then rgb(255, 250, 244) else color:Lerp(rgb(30, 30, 40), 0.25))
		prev = at
	end
	local s = height * 0.32
	ball(parent, "Tuft", Vector3.new(s, s * 0.82, s), CFrame.new(prev + Vector3.new(0, s * 0.3, 0)), color, Enum.Material.SmoothPlastic)
	ball(parent, "Tuft", Vector3.new(s * 0.7, s * 0.6, s * 0.7), CFrame.new(prev + Vector3.new(s * 0.32, s * 0.12, s * 0.1)), color:Lerp(rgb(255, 255, 255), 0.18), Enum.Material.SmoothPlastic)
	ball(parent, "Tuft", Vector3.new(s * 0.66, s * 0.56, s * 0.66), CFrame.new(prev + Vector3.new(-s * 0.3, s * 0.1, -s * 0.12)), color:Lerp(rgb(0, 0, 0), 0.1), Enum.Material.SmoothPlastic)
end

local function candyForest(scene: Instance, rng: Random, lowGraphics: boolean)
	local forest = folder(scene, "TuftForest")
	local count = if lowGraphics then 36 else 70
	for i = 1, count do
		local row = i % 2
		local a = i / count * math.pi * 2 + rng:NextNumber(-0.04, 0.04)
		local r = if row == 0 then rng:NextNumber(0.86, 0.95) else rng:NextNumber(1.0, 1.08)
		tuftTree(forest, ellipseSpot(a, 400 * r, 330 * r), rng:NextNumber(55, 95) * (if row == 1 then 1.15 else 1), TUFTS[rng:NextInteger(1, #TUFTS)], rng)
		if i % 10 == 0 then
			task.wait()
		end
	end
	-- Soft pastel hills behind the trees close the horizon.
	for i = 1, 16 do
		local a = i / 16 * math.pi * 2
		local at = ellipseSpot(a, 470, 420)
		local w = rng:NextNumber(170, 240)
		ball(forest, "PastelHill", Vector3.new(w, rng:NextNumber(110, 160), w * 0.8), CFrame.new(at) * CFrame.Angles(0, -a, 0), CANDY[i % #CANDY + 1]:Lerp(rgb(255, 255, 255), 0.45))
	end
end

local function candyExtras(scene: Instance, rng: Random, lowGraphics: boolean)
	local extras = folder(scene, "CandyExtras")
	-- Gingerbread houses in the gaps at the four corners, out past the billboards.
	for _, spot in { Vector3.new(-200, 0, -120), Vector3.new(210, 0, -110), Vector3.new(-205, 0, 125), Vector3.new(200, 0, 120) } do
		gingerbreadHouse(extras, spot, math.atan2(-spot.X, -spot.Z) + math.pi)
	end
	local rows = 8
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			balloons(extras, Vector3.new(sx * 97, 1.2 + rows * 1.7, sz * (HZ + 9 + (rows - 1) * 3)), rng)
		end
	end
	aroundRink(rng, if lowGraphics then 18 else 40, 1.2, 2.4, function(at: Vector3, i: number)
		local color = CANDY[i % #CANDY + 1]
		local pick = i % 3
		if pick == 0 then
			cottonCandyTree(extras, at, rng:NextNumber(1.1, 1.8), color)
		elseif pick == 1 then
			iceCreamCone(extras, at, rng:NextNumber(0.9, 1.5), color, CANDY[(i + 2) % #CANDY + 1])
		else
			donut(extras, at, rng:NextNumber(1, 1.6), color, rng)
		end
	end)
end

local function buildCandyLand(scene: Instance, crowd: Instance, fans: { Fan }, theme: Theme, lowGraphics: boolean)
	local rng = Random.new(3434)
	groundAndApron(scene, rgb(150, 228, 180), Enum.Material.SmoothPlastic, rgb(255, 214, 232), Enum.Material.SmoothPlastic)
	paintedBleachers(scene, crowd, fans, rng, theme, lowGraphics, rgb(140, 200, 255), rgb(240, 120, 180))
	-- Candy canes along the boards, lollipops at the corners.
	for _, sz in { -1, 1 } do
		for i = -2, 2 do
			candyCane(scene, Vector3.new(i * 44 + 6, 0, sz * (HZ + 4.5)), 0.7)
		end
	end
	local ix, iz = HX - CR, HZ - CR
	for k, sx in { -1, 1 } do
		for j, sz in { -1, 1 } do
			lollipop(scene, Vector3.new(sx * (ix + (CR + 5) * 0.7071), 0, sz * (iz + (CR + 5) * 0.7071)), 1.1, CANDY[k * 2 + j - 2])
		end
	end
	rinkBillboards(scene, { "CANDY LAND", "SWEET SHOTS ONLY", "SUGAR RUSH" }, "PHYSHOCKEY", rgb(255, 110, 170), rgb(255, 255, 255), rgb(255, 255, 255))
	candyExtras(scene, rng, lowGraphics)
	candyForest(scene, Random.new(37), lowGraphics)
	-- Gumdrops, cupcakes and giant lollipops out on the green, candy hills beyond.
	aroundRink(rng, if lowGraphics then 40 else 80, 1.15, 2.6, function(at: Vector3, i: number)
		local color = CANDY[i % #CANDY + 1]
		local pick = i % 4
		if pick == 0 then
			lollipop(scene, at, rng:NextNumber(1.2, 2), color)
		elseif pick == 1 then
			cupcake(scene, at, rng:NextNumber(1, 1.8), color)
		else
			local s = rng:NextNumber(5, 10)
			ball(scene, "Gumdrop", Vector3.new(s, s * 0.9, s), CFrame.new(at), color)
		end
	end)
	for i, spot in { Vector3.new(-520, 0, -380), Vector3.new(-80, 0, -540), Vector3.new(340, 0, -480), Vector3.new(580, 0, 160), Vector3.new(-560, 0, 260), Vector3.new(120, 0, 560) } do
		candyHill(scene, spot, 220 + (i % 3) * 60, CANDY[i % #CANDY + 1])
	end
	if not lowGraphics then
		drift(scene, 60, false, 40, ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(255, 120, 180)), ColorSequenceKeypoint.new(0.5, rgb(120, 220, 255)), ColorSequenceKeypoint.new(1, rgb(255, 230, 90)) }), 0.35, 0.2)
	end
end

-- Tropical Beach -----------------------------------------------------------------------------
local SAND = rgb(238, 216, 164)
local PALM_TRUNK = rgb(150, 108, 66)
local PALM_LEAF = rgb(54, 168, 82)

local function palm(parent: Instance, pos: Vector3, s: number, lean: number)
	-- A bent trunk in short ringed segments, fronds drooping from the top, coconuts under them.
	local prev = pos
	local dir = Vector3.new(math.cos(lean), 0, math.sin(lean))
	for i = 1, 7 do
		local nxt = pos + dir * (i * i * 0.12 * s) + Vector3.new(0, i * 3 * s, 0)
		rod(parent, "Trunk", prev, nxt, (1.8 - i * 0.1) * s, if i % 2 == 0 then PALM_TRUNK else PALM_TRUNK:Lerp(rgb(0, 0, 0), 0.15))
		prev = nxt
	end
	for k = 1, 8 do
		local a = k / 8 * math.pi * 2
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local mid = prev + out * 4 * s + Vector3.new(0, 0.6 * s, 0)
		local tip = prev + out * 8 * s - Vector3.new(0, 2.6 * s, 0)
		local leaf = part(parent, "Frond", Vector3.new(2.6 * s, 0.3 * s, (mid - prev).Magnitude + 0.5), CFrame.lookAt((prev + mid) / 2, mid), PALM_LEAF)
		leaf.CastShadow = false
		part(parent, "Frond", Vector3.new(2 * s, 0.3 * s, (tip - mid).Magnitude + 0.5), CFrame.lookAt((mid + tip) / 2, tip), PALM_LEAF:Lerp(rgb(0, 0, 0), 0.12))
	end
	for k = 1, 3 do
		local a = k * 2.1
		ball(parent, "Coconut", Vector3.new(1.3 * s, 1.3 * s, 1.3 * s), CFrame.new(prev + Vector3.new(math.cos(a) * 0.9 * s, -1 * s, math.sin(a) * 0.9 * s)), rgb(96, 64, 40))
	end
end

local function umbrella(parent: Instance, pos: Vector3, color: Color3)
	part(parent, "UmbrellaPole", Vector3.new(0.4, 9, 0.4), CFrame.new(pos + Vector3.new(0, 4.5, 0)), rgb(250, 250, 250))
	disc(parent, "Umbrella", 11, 0.6, CFrame.new(pos + Vector3.new(0, 8.6, 0)), color)
	disc(parent, "Umbrella", 6, 0.62, CFrame.new(pos + Vector3.new(0, 8.9, 0)), rgb(255, 255, 255))
	ball(parent, "UmbrellaTop", Vector3.new(0.9, 0.9, 0.9), CFrame.new(pos + Vector3.new(0, 9.3, 0)), color)
	part(parent, "Towel", Vector3.new(3.4, 0.12, 6.5), CFrame.new(pos + Vector3.new(3.5, -0.24, 1)) * CFrame.Angles(0, 0.4, 0), color:Lerp(rgb(255, 255, 255), 0.3))
end

local function surfboard(parent: Instance, pos: Vector3, color: Color3, yaw: number)
	ball(parent, "Surfboard", Vector3.new(2.2, 10, 0.5), CFrame.new(pos + Vector3.new(0, 3.6, 0)) * CFrame.Angles(0, yaw, 0.12), color)
	part(parent, "Stripe", Vector3.new(0.4, 8, 0.56), CFrame.new(pos + Vector3.new(0, 3.6, 0)) * CFrame.Angles(0, yaw, 0.12), rgb(255, 255, 255))
end

local function tikiTorch(parent: Instance, pos: Vector3)
	part(parent, "TikiPole", Vector3.new(0.7, 9, 0.7), CFrame.new(pos + Vector3.new(0, 4.5, 0)), rgb(120, 84, 50))
	part(parent, "TikiCup", Vector3.new(1.4, 1.4, 1.4), CFrame.new(pos + Vector3.new(0, 9.4, 0)), rgb(90, 60, 36))
	local flame = ball(parent, "Flame", Vector3.new(1, 1.8, 1), CFrame.new(pos + Vector3.new(0, 10.6, 0)), rgb(255, 150, 40), Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 170, 90)
	light.Range = 12
	light.Brightness = 0.7
	light.Shadows = false
	light.Parent = flame
end

-- Build 35 Tropical Beach extras --------------------------------------------------------------
local function lifeguardTower(parent: Instance, pos: Vector3, yaw: number)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	for _, x in { -2.6, 2.6 } do
		for _, z in { -2.6, 2.6 } do
			part(parent, "TowerLeg", Vector3.new(0.7, 9, 0.7), cf * CFrame.new(x, 4.5, z), rgb(250, 250, 250))
		end
	end
	part(parent, "TowerDeck", Vector3.new(7, 0.6, 7), cf * CFrame.new(0, 9.2, 0), rgb(190, 140, 84), Enum.Material.WoodPlanks)
	part(parent, "TowerHut", Vector3.new(6, 4.4, 5), cf * CFrame.new(0, 11.7, 0.6), rgb(230, 60, 50))
	part(parent, "TowerRoof", Vector3.new(7.6, 0.6, 7.2), cf * CFrame.new(0, 14.2, 0.2), rgb(250, 250, 250))
	part(parent, "TowerWindow", Vector3.new(4.4, 1.8, 0.3), cf * CFrame.new(0, 12.4, -1.95), rgb(120, 210, 240), Enum.Material.Glass)
	for k = 0, 5 do
		part(parent, "Rung", Vector3.new(2.6, 0.3, 0.3), cf * CFrame.new(0, 1 + k * 1.4, -4.4 + k * 0.25), rgb(190, 140, 84))
	end
	part(parent, "FlagPole", Vector3.new(0.25, 6, 0.25), cf * CFrame.new(3, 17, 2), rgb(250, 250, 250))
	part(parent, "Flag", Vector3.new(0.12, 1.6, 2.6), cf * CFrame.new(3, 19, 0.6), rgb(240, 40, 40))
end

local function tikiBar(parent: Instance, pos: Vector3, yaw: number)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	for _, x in { -6, 6 } do
		for _, z in { -4, 4 } do
			part(parent, "BarPost", Vector3.new(0.9, 9, 0.9), cf * CFrame.new(x, 4.5, z), PALM_TRUNK)
		end
	end
	ball(parent, "Thatch", Vector3.new(18, 5, 13), cf * CFrame.new(0, 10, 0), rgb(214, 178, 100), Enum.Material.Grass)
	ball(parent, "Thatch", Vector3.new(10, 4.4, 8), cf * CFrame.new(0, 12.2, 0), rgb(196, 160, 86), Enum.Material.Grass)
	part(parent, "Counter", Vector3.new(12, 3.6, 2), cf * CFrame.new(0, 1.8, -3.2), rgb(150, 108, 66), Enum.Material.Wood)
	part(parent, "CounterTop", Vector3.new(12.6, 0.4, 2.6), cf * CFrame.new(0, 3.8, -3.2), rgb(120, 84, 50), Enum.Material.Wood)
	for k = -1, 1 do
		disc(parent, "Stool", 1.6, 2.6, cf * CFrame.new(k * 3.6, 1.3, -5.6), rgb(150, 108, 66))
		disc(parent, "Coconut", 0.9, 0.9, cf * CFrame.new(k * 3.6 + 0.8, 4.4, -3.2), rgb(96, 64, 40))
	end
	local sign = part(parent, "BarSign", Vector3.new(8, 2, 0.4), cf * CFrame.new(0, 7.4, -4.4), rgb(40, 150, 160))
	textSign(sign, Enum.NormalId.Front, "TIKI BAR", rgb(255, 244, 210), nil, nil, 24)
	part(parent, "Lantern", Vector3.new(0.8, 1, 0.8), cf * CFrame.new(-4, 7, -4), rgb(255, 180, 80), Enum.Material.Neon)
	part(parent, "Lantern", Vector3.new(0.8, 1, 0.8), cf * CFrame.new(4, 7, -4), rgb(255, 120, 160), Enum.Material.Neon)
end

local function sandcastle(parent: Instance, pos: Vector3, s: number)
	local WET = SAND:Lerp(rgb(160, 130, 90), 0.35)
	part(parent, "CastleBase", Vector3.new(9, 2.4, 9) * s, CFrame.new(pos + Vector3.new(0, 1.2, 0) * s), WET, Enum.Material.Sand)
	for _, x in { -3.6, 3.6 } do
		for _, z in { -3.6, 3.6 } do
			disc(parent, "CastleTower", 2.6 * s, 5 * s, CFrame.new(pos + Vector3.new(x, 2.5, z) * s), WET, Enum.Material.Sand)
			ball(parent, "CastleTop", Vector3.new(2.6, 2, 2.6) * s, CFrame.new(pos + Vector3.new(x, 5.2, z) * s), WET, Enum.Material.Sand)
		end
	end
	disc(parent, "CastleKeep", 4 * s, 7 * s, CFrame.new(pos + Vector3.new(0, 3.5, 0) * s), WET, Enum.Material.Sand)
	part(parent, "CastleFlag", Vector3.new(0.1, 1, 1.4) * s, CFrame.new(pos + Vector3.new(0, 8.4, 0.7) * s), rgb(240, 60, 60))
	part(parent, "CastlePole", Vector3.new(0.15, 2.4, 0.15) * s, CFrame.new(pos + Vector3.new(0, 8, 0) * s), rgb(250, 250, 250))
end

local function beachBall(parent: Instance, pos: Vector3, s: number, color: Color3)
	ball(parent, "BeachBall", Vector3.new(3, 3, 3) * s, CFrame.new(pos + Vector3.new(0, 1.5 * s, 0)), rgb(255, 255, 255))
	disc(parent, "BallBand", 3.06 * s, 1 * s, CFrame.new(pos + Vector3.new(0, 1.5 * s, 0)) * CFrame.Angles(0, 0, math.pi / 2), color)
	disc(parent, "BallBand", 3.04 * s, 0.8 * s, CFrame.new(pos + Vector3.new(0, 1.5 * s, 0)) * CFrame.Angles(math.pi / 2, 0, 0), rgb(255, 210, 60))
end

local function sailboat(parent: Instance, pos: Vector3, s: number, sail: Color3, yaw: number)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	ball(parent, "Hull", Vector3.new(4, 3, 14) * s, cf * CFrame.new(0, 0.4 * s, 0), rgb(250, 250, 250))
	part(parent, "Mast", Vector3.new(0.4, 14, 0.4) * s, cf * CFrame.new(0, 8 * s, 0), rgb(150, 108, 66))
	part(parent, "Sail", Vector3.new(0.2, 11, 5.4) * s, cf * CFrame.new(0, 8 * s, 2.8 * s) * CFrame.Angles(-0.12, 0, 0), sail)
	part(parent, "Jib", Vector3.new(0.2, 8, 3.4) * s, cf * CFrame.new(0, 6.4 * s, -2.2 * s) * CFrame.Angles(0.18, 0, 0), rgb(255, 255, 255))
end

local function beachExtras(scene: Instance, rng: Random, lowGraphics: boolean, shore: number)
	local extras = folder(scene, "BeachExtras")
	-- Lifeguard towers along the shoreline, watching the water.
	for _, x in { -220, 0, 220 } do
		lifeguardTower(extras, Vector3.new(x, 0, shore - 22), math.pi)
	end
	-- Tiki bars off the two ends, facing the rink.
	tikiBar(extras, Vector3.new(-205, 0, -40), -math.pi / 2)
	tikiBar(extras, Vector3.new(205, 0, 40), math.pi / 2)
	-- A wooden pier out into the sea, and sailboats past it.
	local pierX = -140
	for k = 0, 15 do
		part(extras, "PierPlank", Vector3.new(10, 0.5, 3.6), CFrame.new(pierX, 2.2, shore - 6 + k * 4), rgb(170, 124, 76), Enum.Material.WoodPlanks)
		if k % 3 == 0 then
			for _, sx in { -1, 1 } do
				part(extras, "PierPost", Vector3.new(0.9, 5, 0.9), CFrame.new(pierX + sx * 4.6, 0.6, shore - 6 + k * 4), rgb(120, 84, 50), Enum.Material.Wood)
			end
		end
	end
	local sails = { rgb(255, 90, 90), rgb(255, 200, 60), rgb(60, 190, 230), rgb(240, 120, 220) }
	for i, spot in { Vector3.new(-60, 0, 300), Vector3.new(260, 0, 260), Vector3.new(-380, 0, 280), Vector3.new(80, 0, 420) } do
		sailboat(extras, spot, 1.6 + (i % 2) * 0.6, sails[i], i * 1.3)
	end
	-- Beach huts in a row near the end of the sand.
	for k = -3, 3 do
		local x = k * 70 + 35
		if math.abs(x - pierX) > 20 then
			local hut = Vector3.new(x, 0, shore - 46)
			part(extras, "Hut", Vector3.new(8, 7, 6), CFrame.new(hut + Vector3.new(0, 3.5, 0)), sails[(k + 4) % #sails + 1])
			part(extras, "HutStripe", Vector3.new(8.1, 1.2, 6.1), CFrame.new(hut + Vector3.new(0, 4.6, 0)), rgb(255, 255, 255))
			part(extras, "HutRoof", Vector3.new(9, 0.6, 7), CFrame.new(hut + Vector3.new(0, 7.3, 0)), rgb(250, 250, 250))
			part(extras, "HutDoor", Vector3.new(2.6, 4.6, 0.3), CFrame.new(hut + Vector3.new(0, 2.3, -3.05)), rgb(150, 108, 66))
		end
	end
	local colors = { rgb(255, 90, 90), rgb(60, 190, 230), rgb(120, 220, 120), rgb(240, 120, 220) }
	-- Palm groves, dunes and umbrellas on the land side (behind the south stand and off the ends).
	for i, spot in { Vector3.new(-170, 0, -150), Vector3.new(-40, 0, -175), Vector3.new(110, 0, -160), Vector3.new(230, 0, -120), Vector3.new(-250, 0, -60), Vector3.new(260, 0, 10) } do
		for k = 0, 2 do
			local a = i * 1.3 + k * 2.1
			palm(extras, spot + Vector3.new(math.cos(a) * 9, 0, math.sin(a) * 9), 1.4 + k * 0.25, a + math.pi)
		end
		ball(extras, "Dune", Vector3.new(60, 10, 34), CFrame.new(spot + Vector3.new(0, -2, -30)) * CFrame.Angles(0, i, 0), SAND:Lerp(rgb(255, 255, 255), 0.08), Enum.Material.Sand)
		umbrella(extras, spot + Vector3.new(16, 0, 14), colors[i % #colors + 1])
	end
	aroundRink(rng, if lowGraphics then 20 else 50, 1.2, 2.2, function(at: Vector3, i: number)
		if at.Z > shore - 60 and at.Z < shore + 4 and math.abs(at.X) < 260 then
			return -- keep the huts and towers clear
		end
		if at.Z > shore - 10 then
			return
		end
		local pick = i % 3
		if pick == 0 then
			sandcastle(extras, at, rng:NextNumber(0.9, 1.5))
		elseif pick == 1 then
			beachBall(extras, at, rng:NextNumber(0.9, 1.4), colors[i % #colors + 1])
		else
			umbrella(extras, at, colors[(i + 1) % #colors + 1])
		end
	end)
end

local function buildTropicalBeach(scene: Instance, crowd: Instance, fans: { Fan }, theme: Theme, lowGraphics: boolean)
	local rng = Random.new(808)
	groundAndApron(scene, SAND, Enum.Material.Sand, rgb(214, 186, 140), Enum.Material.WoodPlanks)
	paintedBleachers(scene, crowd, fans, rng, theme, lowGraphics, rgb(250, 240, 220), rgb(40, 170, 180))
	-- The sea past the north stand: shallows, a line of surf, then deep blue to the horizon.
	local shore = HZ + 120
	part(scene, "Shallows", Vector3.new(1400, 1, 40), CFrame.new(0, -0.62, shore + 20), rgb(90, 214, 220), Enum.Material.SmoothPlastic, 0.1)
	part(scene, "Surf", Vector3.new(1400, 1, 3), CFrame.new(0, -0.58, shore + 1.5), rgb(255, 255, 255))
	part(scene, "Sea", Vector3.new(1400, 1, 700), CFrame.new(0, -0.6, shore + 390), rgb(26, 130, 196), Enum.Material.Glass, 0.05)
	-- Tiki torches round the boards; palms, umbrellas and surfboards on the sand.
	for _, sz in { -1, 1 } do
		for i = -2, 2 do
			tikiTorch(scene, Vector3.new(i * 44 + 6, 0, sz * (HZ + 4.5)))
		end
	end
	local ix, iz = HX - CR, HZ - CR
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			palm(scene, Vector3.new(sx * (ix + (CR + 6) * 0.7071), 0, sz * (iz + (CR + 6) * 0.7071)), 1.2, math.atan2(sz, sx))
		end
	end
	rinkBillboards(scene, { "TROPICAL BEACH", "SURF'S UP", "HANG TEN" }, "PHYSHOCKEY", rgb(30, 150, 170), rgb(255, 244, 210), rgb(150, 108, 66), Enum.Material.Wood)
	beachExtras(scene, rng, lowGraphics, shore)
	local colors = { rgb(255, 90, 90), rgb(255, 200, 60), rgb(60, 190, 230), rgb(120, 220, 120), rgb(240, 120, 220) }
	aroundRink(rng, if lowGraphics then 30 else 60, 1.15, 2.4, function(at: Vector3, i: number)
		if at.Z > shore - 10 then
			return -- not in the sea
		end
		local pick = i % 3
		if pick == 0 then
			umbrella(scene, at, colors[i % #colors + 1])
		elseif pick == 1 then
			surfboard(scene, at, colors[(i + 2) % #colors + 1], rng:NextNumber(0, math.pi))
		else
			palm(scene, at, rng:NextNumber(1.2, 1.8), rng:NextNumber(0, math.pi * 2))
		end
	end)
	-- Build 37: big sand dunes all round the land side (the sea side stays open), so the far
	-- edge of the beach isn't a flat line against the sky.
	local dunes = folder(scene, "Dunes")
	local duneRng = Random.new(37)
	for i = 1, 30 do
		local a = i / 30 * math.pi * 2
		local at = ellipseSpot(a, 410 + duneRng:NextNumber(-20, 40), 340 + duneRng:NextNumber(-20, 40))
		if at.Z < shore - 30 then
			local w = duneRng:NextNumber(150, 230)
			ball(dunes, "Dune", Vector3.new(w, duneRng:NextNumber(70, 120), w * 0.55), CFrame.new(at) * CFrame.Angles(0, -a + math.pi / 2, 0), SAND:Lerp(rgb(255, 236, 196), duneRng:NextNumber(0, 0.5)), Enum.Material.Sand)
		end
	end
	-- And a second, lower row in front, with a few palms on top of it.
	for i = 1, 22 do
		local a = (i + 0.5) / 22 * math.pi * 2
		local at = ellipseSpot(a, 340, 285)
		if at.Z < shore - 40 then
			local w = duneRng:NextNumber(110, 160)
			ball(dunes, "Dune", Vector3.new(w, duneRng:NextNumber(40, 64), w * 0.6), CFrame.new(at) * CFrame.Angles(0, -a + math.pi / 2, 0), SAND:Lerp(rgb(214, 186, 130), duneRng:NextNumber(0, 0.4)), Enum.Material.Sand)
			if i % 3 == 0 then
				palm(dunes, at + Vector3.new(0, 14, 0), 1.6, a)
			end
		end
	end
	-- Palm-topped islands out at sea.
	for i, spot in { Vector3.new(-300, 0, 420), Vector3.new(160, 0, 520), Vector3.new(460, 0, 380) } do
		ball(scene, "Island", Vector3.new(90 + i * 20, 20, 60), CFrame.new(spot), SAND)
		palm(scene, spot + Vector3.new(-10, 6, 0), 2.5, 0.5)
		palm(scene, spot + Vector3.new(14, 5, 6), 2.2, 2.5)
	end
end

-- Volcano ------------------------------------------------------------------------------------
local BASALT = rgb(52, 44, 44)
local LAVA = rgb(255, 92, 20)

local function brazier(parent: Instance, pos: Vector3)
	part(parent, "Pillar", Vector3.new(2.2, 8, 2.2), CFrame.new(pos + Vector3.new(0, 4, 0)), rgb(70, 60, 58), Enum.Material.Slate)
	disc(parent, "Bowl", 3.6, 1.2, CFrame.new(pos + Vector3.new(0, 8.4, 0)), rgb(40, 34, 34), Enum.Material.Metal)
	local flame = ball(parent, "Flame", Vector3.new(2.2, 3, 2.2), CFrame.new(pos + Vector3.new(0, 10, 0)), LAVA, Enum.Material.Neon)
	local fire = Instance.new("Fire")
	fire.Size = 4
	fire.Heat = 6
	fire.Color = rgb(255, 120, 40)
	fire.SecondaryColor = rgb(255, 40, 10)
	fire.Parent = flame
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 120, 60)
	light.Range = 16
	light.Brightness = 1
	light.Shadows = false
	light.Parent = flame
end

local function volcanoCone(parent: Instance, pos: Vector3, size: number, smoke: boolean)
	-- A straight-sided cone from thin tiers (thick ones read as a stepped cake from the rink).
	local height = size * 0.6
	local function radius(y: number): number
		return size * 0.5 * (1 - 0.7 * y / height)
	end
	local TIERS = 16
	local h = height / TIERS
	for i = 0, TIERS - 1 do
		local mid = h * (i + 0.5)
		disc(parent, "Volcano", radius(mid) * 2, h, CFrame.new(pos + Vector3.new(0, mid, 0)), BASALT:Lerp(rgb(90, 70, 64), i / (TIERS * 1.3)), Enum.Material.Basalt)
	end
	local top = pos + Vector3.new(0, height, 0)
	disc(parent, "Crater", size * 0.22, 1, CFrame.new(top + Vector3.new(0, 0.2, 0)), LAVA, Enum.Material.Neon)
	-- Lava running down the face toward the rink, lying on the slope and wandering a little.
	local face = (-pos * Vector3.new(1, 0, 1)).Unit
	local side = Vector3.new(-face.Z, 0, face.X)
	local SEGS = 7
	local prev: Vector3? = nil
	for k = 0, SEGS do
		local y = height * (1 - k / SEGS)
		local wander = math.sin(k * 1.7) * size * 0.03 * (k / SEGS)
		local at = pos + face * radius(y) + side * wander + Vector3.new(0, y, 0)
		if prev then
			local len = (at - prev).Magnitude
			local w = size * (0.03 + 0.025 * k / SEGS)
			part(parent, "LavaFlow", Vector3.new(w, size * 0.02, len + w * 0.5), CFrame.lookAt((prev + at) / 2, at), LAVA, Enum.Material.Neon)
		end
		prev = at
	end
	if smoke then
		local vent = part(parent, "Vent", Vector3.new(size * 0.15, 1, size * 0.15), CFrame.new(top + Vector3.new(0, 2, 0)), rgb(0, 0, 0), nil, 1)
		local e = Instance.new("ParticleEmitter")
		e.Rate = 6
		e.Lifetime = NumberRange.new(14, 18)
		e.Speed = NumberRange.new(10, 16)
		e.SpreadAngle = Vector2.new(12, 12)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.08), NumberSequenceKeypoint.new(1, size * 0.3) })
		e.Color = ColorSequence.new(rgb(70, 60, 60), rgb(40, 36, 40))
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		e.RotSpeed = NumberRange.new(-10, 10)
		e.Parent = vent
	end
end

-- Build 35 Volcano extras ---------------------------------------------------------------------
local OBSIDIAN = rgb(34, 26, 40)

local function obsidianSpire(parent: Instance, pos: Vector3, s: number, rng: Random)
	local h = 0
	for k = 0, 3 do
		local w = (5 - k * 1.1) * s
		local tall = (6 - k) * s
		local p = part(parent, "Spire", Vector3.new(w, tall, w), CFrame.new(pos + Vector3.new(rng:NextNumber(-0.4, 0.4) * s, h + tall / 2, rng:NextNumber(-0.4, 0.4) * s)) * CFrame.Angles(rng:NextNumber(-0.08, 0.08), rng:NextNumber(0, 1.5), rng:NextNumber(-0.08, 0.08)), OBSIDIAN, Enum.Material.Slate)
		p.Reflectance = 0.15
		h += tall * 0.85
	end
	-- A glowing seam up one face.
	part(parent, "Seam", Vector3.new(0.4 * s, h * 0.7, 0.4 * s), CFrame.new(pos + Vector3.new(2.4 * s, h * 0.38, 0)), LAVA, Enum.Material.Neon)
end

local function crystalCluster(parent: Instance, pos: Vector3, s: number, color: Color3, rng: Random)
	for k = 1, 5 do
		local tall = rng:NextNumber(4, 9) * s
		local tilt = CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 6), rng:NextNumber(-0.5, 0.5))
		local p = part(parent, "Crystal", Vector3.new(1.4 * s, tall, 1.4 * s), CFrame.new(pos) * tilt * CFrame.new(0, tall * 0.4, 0), color, Enum.Material.Neon)
		p.CastShadow = false
	end
end

local function charredTree(parent: Instance, pos: Vector3, s: number, rng: Random)
	local top = pos + Vector3.new(rng:NextNumber(-1, 1) * s, 14 * s, rng:NextNumber(-1, 1) * s)
	rod(parent, "CharredTrunk", pos + Vector3.new(0, -0.5, 0), top, 1.6 * s, rgb(36, 30, 30))
	for k = 1, 4 do
		local a = k * 1.7 + rng:NextNumber(0, 0.6)
		local from = pos:Lerp(top, 0.45 + k * 0.12)
		local tip = from + Vector3.new(math.cos(a) * 5 * s, (2.5 + k * 0.4) * s, math.sin(a) * 5 * s)
		rod(parent, "CharredBranch", from, tip, 0.6 * s, rgb(42, 34, 34))
		ball(parent, "Ember", Vector3.new(0.7, 0.7, 0.7) * s, CFrame.new(tip), rgb(255, 120, 40), Enum.Material.Neon)
	end
end

local function lavaPool(parent: Instance, pos: Vector3, d: number, lit: boolean)
	disc(parent, "PoolRim", d + 4, 1.2, CFrame.new(pos + Vector3.new(0, -0.1, 0)), rgb(60, 50, 50), Enum.Material.Basalt)
	local pool = disc(parent, "LavaPool", d, 1.2, CFrame.new(pos + Vector3.new(0, 0.05, 0)), LAVA, Enum.Material.Neon)
	if lit then
		local light = Instance.new("PointLight")
		light.Color = rgb(255, 110, 40)
		light.Range = math.min(40, d * 1.4)
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = pool
	end
end

local function steamVent(parent: Instance, pos: Vector3)
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		ball(parent, "VentRock", Vector3.new(3, 2, 3), CFrame.new(pos + Vector3.new(math.cos(a) * 2.6, 0.6, math.sin(a) * 2.6)), rgb(70, 60, 58), Enum.Material.Basalt)
	end
	local vent = part(parent, "SteamVent", Vector3.new(2.4, 0.4, 2.4), CFrame.new(pos + Vector3.new(0, 0.4, 0)), rgb(255, 130, 40), Enum.Material.Neon)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 5
	e.Lifetime = NumberRange.new(4, 6)
	e.Speed = NumberRange.new(6, 9)
	e.SpreadAngle = Vector2.new(10, 10)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 9) })
	e.Color = ColorSequence.new(rgb(140, 120, 120), rgb(70, 64, 66))
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	e.RotSpeed = NumberRange.new(-20, 20)
	e.Parent = vent
end

local function skullRock(parent: Instance, pos: Vector3, s: number)
	local face = CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0))
	ball(parent, "SkullRock", Vector3.new(26, 22, 24) * s, face * CFrame.new(0, 10 * s, 0), rgb(84, 74, 72), Enum.Material.Basalt)
	part(parent, "SkullJaw", Vector3.new(16, 7, 16) * s, face * CFrame.new(0, 2.5 * s, -2 * s), rgb(76, 66, 64), Enum.Material.Basalt)
	for _, x in { -5, 5 } do
		ball(parent, "SkullEye", Vector3.new(6.4, 6, 3) * s, face * CFrame.new(x * s, 12 * s, -10.6 * s), rgb(14, 10, 12))
		ball(parent, "SkullGlow", Vector3.new(2, 2, 1) * s, face * CFrame.new(x * s, 12 * s, -11.6 * s), LAVA, Enum.Material.Neon)
	end
	ball(parent, "SkullNose", Vector3.new(3, 4, 2) * s, face * CFrame.new(0, 7 * s, -11.4 * s), rgb(14, 10, 12))
	for k = -2, 2 do
		part(parent, "SkullTooth", Vector3.new(2, 2.4, 1) * s, face * CFrame.new(k * 2.6 * s, 4.6 * s, -9.6 * s), rgb(150, 140, 132), Enum.Material.Slate)
	end
end

-- Build 36: the Volcano rink is a jungle in daylight with the volcanoes behind it.
local JUNGLE_LEAF = { rgb(52, 140, 60), rgb(70, 160, 54), rgb(40, 116, 58), rgb(96, 170, 60) }

local function jungleTree(parent: Instance, pos: Vector3, s: number, rng: Random)
	-- A tall trunk with root flares and a layered canopy of leaf clumps.
	local top = pos + Vector3.new(rng:NextNumber(-1.5, 1.5) * s, 22 * s, rng:NextNumber(-1.5, 1.5) * s)
	rod(parent, "JungleTrunk", pos + Vector3.new(0, -0.5, 0), top, 2.2 * s, rgb(96, 70, 50), Enum.Material.Wood)
	for k = 0, 3 do
		local a = k * math.pi / 2 + 0.4
		rod(parent, "JungleRoot", pos + Vector3.new(0, 3 * s, 0), pos + Vector3.new(math.cos(a) * 3.4 * s, -0.3, math.sin(a) * 3.4 * s), 1 * s, rgb(86, 62, 44), Enum.Material.Wood)
	end
	for k = 1, 6 do
		local a = k / 6 * math.pi * 2 + rng:NextNumber(0, 0.5)
		local r = if k % 2 == 0 then 5 else 3.4
		local d = rng:NextNumber(8, 11) * s
		local clump = ball(parent, "JungleLeaves", Vector3.new(d, d * 0.62, d), CFrame.new(top + Vector3.new(math.cos(a) * r * s, rng:NextNumber(-1.5, 1.5) * s, math.sin(a) * r * s)), JUNGLE_LEAF[(k + math.floor(s * 10)) % #JUNGLE_LEAF + 1], Enum.Material.Grass)
		clump.CastShadow = k % 2 == 0
	end
	ball(parent, "JungleLeaves", Vector3.new(10, 7, 10) * s, CFrame.new(top + Vector3.new(0, 2.6 * s, 0)), JUNGLE_LEAF[1], Enum.Material.Grass)
end

local function fern(parent: Instance, pos: Vector3, s: number, rng: Random)
	-- Fronds fanned out round the middle, arching up then out.
	local n = 7
	for k = 1, n do
		local a = k / n * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local mid = pos + out * 2.2 * s + Vector3.new(0, 2.4 * s, 0)
		local tip = pos + out * 4.6 * s + Vector3.new(0, 1.2 * s, 0)
		local c = JUNGLE_LEAF[k % #JUNGLE_LEAF + 1]
		local f1 = part(parent, "Fern", Vector3.new(1.4 * s, 0.2 * s, (mid - pos).Magnitude + 0.3), CFrame.lookAt((pos + mid) / 2, mid), c)
		local f2 = part(parent, "Fern", Vector3.new(1.1 * s, 0.2 * s, (tip - mid).Magnitude + 0.3), CFrame.lookAt((mid + tip) / 2, tip), c:Lerp(rgb(0, 0, 0), 0.1))
		f1.CastShadow = false
		f2.CastShadow = false
	end
end

local function jungleBush(parent: Instance, pos: Vector3, s: number, rng: Random)
	for k = 1, 4 do
		local d = rng:NextNumber(4, 7) * s
		ball(parent, "Bush", Vector3.new(d, d * 0.75, d), CFrame.new(pos + Vector3.new(rng:NextNumber(-2.5, 2.5) * s, d * 0.3, rng:NextNumber(-2.5, 2.5) * s)), JUNGLE_LEAF[k], Enum.Material.Grass).CastShadow = false
	end
	-- A few bright flowers.
	for k = 1, 3 do
		ball(parent, "Flower", Vector3.new(1, 1, 1) * s, CFrame.new(pos + Vector3.new(rng:NextNumber(-3, 3) * s, rng:NextNumber(3, 4.5) * s, rng:NextNumber(-3, 3) * s)), if k == 2 then rgb(255, 210, 60) else rgb(255, 70, 110), Enum.Material.Neon).CastShadow = false
	end
end

local function volcanoExtras(scene: Instance, rng: Random, lowGraphics: boolean)
	local extras = folder(scene, "VolcanoExtras")
	-- Stone bridges over both lava rivers, in line with the rink.
	for _, x in { -193, 160 } do
		for k = -2, 2 do
			part(extras, "Bridge", Vector3.new(9, 1.4, 12), CFrame.new(x + k * 8.6, 1.4 - math.abs(k) * 0.5, 0) * CFrame.Angles(0, 0, k * 0.06), rgb(90, 78, 74), Enum.Material.Slate)
		end
		for _, z in { -6.5, 6.5 } do
			for k = -2, 2 do
				part(extras, "BridgePost", Vector3.new(1.2, 3, 1.2), CFrame.new(x + k * 8.6, 3.2 - math.abs(k) * 0.5, z), rgb(60, 50, 50), Enum.Material.Slate)
			end
		end
	end
	skullRock(extras, Vector3.new(-330, 0, 200), 1.6)
	skullRock(extras, Vector3.new(300, 0, -230), 1.3)
	-- Build 36: mostly jungle (trees, palms, ferns, flowering bushes), with the odd obsidian spire,
	-- lava pool and steam vent so it still reads as a volcano island.
	aroundRink(rng, if lowGraphics then 30 else 80, 1.2, 2.6, function(at: Vector3, i: number)
		local pick = i % 8
		if pick == 0 or pick == 4 then
			jungleTree(extras, at, rng:NextNumber(0.9, 1.4), rng)
		elseif pick == 1 then
			palm(extras, at, rng:NextNumber(1, 1.4), rng:NextNumber(0, 6))
		elseif pick == 2 or pick == 6 then
			fern(extras, at, rng:NextNumber(1, 1.6), rng)
		elseif pick == 3 then
			jungleBush(extras, at, rng:NextNumber(1, 1.5), rng)
		elseif pick == 5 then
			if i % 3 == 0 then
				obsidianSpire(extras, at, rng:NextNumber(1, 1.8), rng)
			else
				lavaPool(extras, at, rng:NextNumber(10, 18), false)
			end
		elseif not lowGraphics then
			steamVent(extras, at)
		end
	end)
	-- A row of trees just behind each side stand, so jungle frames the rink from the match camera
	-- (the ends stay open for the billboards and the big volcano).
	local step = if lowGraphics then 50 else 25
	for _, sz in { -1, 1 } do
		for x = -150, 150, step do
			local at = Vector3.new(x + rng:NextNumber(-6, 6), 0, sz * (HZ + 46 + rng:NextNumber(0, 8)))
			if (x // step) % 3 == 0 then
				palm(extras, at, 1.2, if sz > 0 then -math.pi / 2 else math.pi / 2)
			else
				jungleTree(extras, at, rng:NextNumber(1.1, 1.5), rng)
			end
		end
	end
end

local function buildVolcano(scene: Instance, crowd: Instance, fans: { Fan }, theme: Theme, lowGraphics: boolean)
	local rng = Random.new(666)
	-- Build 36: jungle grass (was bare basalt) round a stone apron.
	groundAndApron(scene, rgb(78, 132, 54), Enum.Material.Grass, rgb(96, 90, 82), Enum.Material.Slate)
	paintedBleachers(scene, crowd, fans, rng, theme, lowGraphics, rgb(70, 62, 62), rgb(40, 34, 34), Enum.Material.Slate)
	for _, sz in { -1, 1 } do
		for i = -2, 2 do
			brazier(scene, Vector3.new(i * 44 + 6, 0, sz * (HZ + 4.5)))
		end
	end
	-- Lava rivers winding across the rock, well outside the stands.
	for _, river in { { Vector3.new(-HX - 70, 0, -260), Vector3.new(-HX - 60, 0, 260) }, { Vector3.new(HX + 50, 0, -300), Vector3.new(HX + 70, 0, 300) } } do
		local a, b = river[1], river[2]
		local prev = a
		for k = 1, 14 do
			local t = k / 14
			local p = a:Lerp(b, t) + Vector3.new(math.sin(t * 9) * 14, 0, 0)
			local mid = (prev + p) / 2
			part(scene, "Lava", Vector3.new(7, 1, (p - prev).Magnitude + 3), CFrame.lookAt(mid, p) + Vector3.new(0, -0.66, 0), LAVA, Enum.Material.Neon)
			prev = p
		end
	end
	rinkBillboards(scene, { "VOLCANO", "HOT SHOTS", "LAVA LEAGUE" }, "PHYSHOCKEY", rgb(60, 26, 20), rgb(255, 170, 60), rgb(70, 60, 58), Enum.Material.Slate)
	volcanoExtras(scene, rng, lowGraphics)
	-- Boulders, mossy in the jungle, some cracked with glowing lava.
	aroundRink(rng, if lowGraphics then 24 else 50, 1.15, 2.6, function(at: Vector3, i: number)
		local s = rng:NextNumber(5, 14)
		local rock = ball(scene, "Boulder", Vector3.new(s, s * 0.7, s * 0.9), CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), rgb(72, 66, 64), Enum.Material.Basalt)
		if i % 4 ~= 0 then
			ball(scene, "Moss", Vector3.new(s * 0.8, s * 0.3, s * 0.72), CFrame.new(at + Vector3.new(0, s * 0.26, 0)), rgb(70, 130, 50), Enum.Material.Grass)
		end
		if i % 4 == 0 then
			rock.Material = Enum.Material.CrackedLava
			rock.Color = rgb(255, 110, 40)
		end
	end)
	volcanoCone(scene, Vector3.new(-560, 0, -120), 420, not lowGraphics)
	volcanoCone(scene, Vector3.new(420, 0, -520), 260, false)
	volcanoCone(scene, Vector3.new(380, 0, 480), 220, false)
	-- Build 35: a big one straight down the rink from the default camera, smoking.
	-- (Close enough to show through the rink's thick haze; the bridge leads toward it.)
	volcanoCone(scene, Vector3.new(340, 0, 20), 300, not lowGraphics)
	-- Build 37: green jungle mountains all round, so the island never ends in a bare horizon.
	peakRing(folder(scene, "JungleMountains"), Random.new(37), if lowGraphics then 9 else 13, rgb(64, 128, 56), rgb(40, 92, 44), Enum.Material.Grass, rgb(104, 160, 76))
	if not lowGraphics then
		-- A few embers still drift up from the lava (fewer in daylight).
		drift(scene, 0.5, true, 12, ColorSequence.new(rgb(255, 150, 60), rgb(255, 60, 20)), 0.3, 1)
	end
end

-- Moon Base ----------------------------------------------------------------------------------
local REGOLITH = rgb(158, 158, 166)

local function crater(parent: Instance, pos: Vector3, d: number)
	disc(parent, "CraterRim", d * 1.25, 1, CFrame.new(pos + Vector3.new(0, -0.55, 0)), rgb(182, 182, 190), Enum.Material.Sand)
	disc(parent, "Crater", d, 1, CFrame.new(pos + Vector3.new(0, -0.5, 0)), rgb(116, 116, 124), Enum.Material.Sand)
end

local function dome(parent: Instance, pos: Vector3, d: number)
	disc(parent, "DomeRing", d + 2, 2, CFrame.new(pos + Vector3.new(0, 0.6, 0)), rgb(200, 204, 214), Enum.Material.DiamondPlate)
	local glass = ball(parent, "Dome", Vector3.new(d, d, d), CFrame.new(pos), rgb(150, 210, 255), Enum.Material.Glass)
	glass.Transparency = 0.45
	ball(parent, "DomeGlow", Vector3.new(d * 0.3, d * 0.3, d * 0.3), CFrame.new(pos + Vector3.new(0, d * 0.12, 0)), rgb(140, 255, 200), Enum.Material.Neon)
	for k = 0, 3 do
		local a = k * math.pi / 2
		part(parent, "DomeRib", Vector3.new(0.6, d * 0.52, 0.6), CFrame.new(pos + Vector3.new(math.cos(a) * d * 0.36, d * 0.26, math.sin(a) * d * 0.36)) * CFrame.Angles(math.sin(a) * 0.8, 0, -math.cos(a) * 0.8), rgb(220, 224, 232), Enum.Material.Metal)
	end
end

local function dish(parent: Instance, pos: Vector3, s: number)
	part(parent, "DishMast", Vector3.new(1 * s, 10 * s, 1 * s), CFrame.new(pos + Vector3.new(0, 5 * s, 0)), rgb(200, 204, 214), Enum.Material.Metal)
	local face = CFrame.new(pos + Vector3.new(0, 11 * s, 0)) * CFrame.Angles(0, 0.6, 0) * CFrame.Angles(0, 0, 0.7)
	local p = part(parent, "Dish", Vector3.new(1 * s, 10 * s, 10 * s), face, rgb(236, 238, 244))
	p.Shape = Enum.PartType.Cylinder
	part(parent, "DishArm", Vector3.new(4 * s, 0.4 * s, 0.4 * s), face * CFrame.new(2 * s, 0, 0), rgb(120, 128, 146), Enum.Material.Metal)
	ball(parent, "DishTip", Vector3.new(0.9 * s, 0.9 * s, 0.9 * s), face * CFrame.new(4 * s, 0, 0), rgb(255, 60, 60), Enum.Material.Neon)
end

local function rocket(parent: Instance, pos: Vector3, s: number)
	disc(parent, "Pad", 18 * s, 1.2 * s, CFrame.new(pos + Vector3.new(0, 0.6 * s, 0)), rgb(90, 96, 110), Enum.Material.DiamondPlate)
	for i, c in { rgb(240, 240, 246), rgb(230, 60, 60), rgb(240, 240, 246), rgb(240, 240, 246) } do
		disc(parent, "Rocket", 5 * s, 5 * s + 0.02, CFrame.new(pos + Vector3.new(0, (1.2 + (i - 0.5) * 5) * s, 0)), c, Enum.Material.SmoothPlastic)
	end
	ball(parent, "Nose", Vector3.new(5 * s, 7 * s, 5 * s), CFrame.new(pos + Vector3.new(0, 21.2 * s, 0)), rgb(230, 60, 60))
	ball(parent, "Window", Vector3.new(1.8 * s, 1.8 * s, 1.8 * s), CFrame.new(pos + Vector3.new(0, 15 * s, 2.3 * s)), rgb(120, 200, 255), Enum.Material.Neon)
	for k = 0, 2 do
		local a = k * math.pi * 2 / 3
		part(parent, "Fin", Vector3.new(0.6 * s, 6 * s, 4 * s), CFrame.new(pos + Vector3.new(math.cos(a) * 3.2 * s, 4.4 * s, math.sin(a) * 3.2 * s)) * CFrame.Angles(0, -a, 0), rgb(230, 60, 60))
	end
end

local function floodlight(parent: Instance, pos: Vector3)
	part(parent, "FloodMast", Vector3.new(1, 16, 1), CFrame.new(pos + Vector3.new(0, 8, 0)), rgb(120, 128, 146), Enum.Material.Metal)
	local lamp = part(parent, "FloodLamp", Vector3.new(4, 2.2, 0.6), CFrame.lookAt(pos + Vector3.new(0, 16.4, 0), Vector3.new(0, 0, 0)), rgb(235, 245, 255), Enum.Material.Neon)
	local light = Instance.new("SpotLight")
	light.Color = rgb(220, 235, 255)
	light.Range = 40
	light.Angle = 70
	light.Brightness = 1.2
	light.Shadows = false
	light.Face = Enum.NormalId.Front
	light.Parent = lamp
end

-- Build 35 Moon Base extras -------------------------------------------------------------------
local HULL = rgb(232, 234, 240)

local function rover(parent: Instance, pos: Vector3, yaw: number)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	part(parent, "RoverBody", Vector3.new(6, 2.2, 9), cf * CFrame.new(0, 2.6, 0), HULL)
	part(parent, "RoverPanel", Vector3.new(6.8, 0.25, 6), cf * CFrame.new(0, 3.85, 0.8), rgb(40, 70, 170), Enum.Material.Glass)
	for _, x in { -3.4, 3.4 } do
		for _, z in { -3.2, 0, 3.2 } do
			local w = part(parent, "RoverWheel", Vector3.new(1, 2.4, 2.4), cf * CFrame.new(x, 1.2, z), rgb(60, 62, 70))
			w.Shape = Enum.PartType.Cylinder
		end
	end
	part(parent, "RoverMast", Vector3.new(0.3, 3.4, 0.3), cf * CFrame.new(0, 5.4, -3.4), rgb(200, 204, 214), Enum.Material.Metal)
	part(parent, "RoverCam", Vector3.new(1.6, 1, 1), cf * CFrame.new(0, 7.4, -3.4), rgb(80, 86, 100))
	ball(parent, "RoverEye", Vector3.new(0.6, 0.6, 0.6), cf * CFrame.new(0.4, 7.4, -3.95), rgb(120, 220, 255), Enum.Material.Neon)
	ball(parent, "RoverEye", Vector3.new(0.6, 0.6, 0.6), cf * CFrame.new(-0.4, 7.4, -3.95), rgb(120, 220, 255), Enum.Material.Neon)
end

local function moonFlag(parent: Instance, pos: Vector3)
	part(parent, "FlagPole", Vector3.new(0.35, 14, 0.35), CFrame.new(pos + Vector3.new(0, 7, 0)), rgb(220, 224, 232), Enum.Material.Metal)
	part(parent, "FlagBar", Vector3.new(0.25, 0.25, 7), CFrame.new(pos + Vector3.new(0, 13.8, 3.5)), rgb(220, 224, 232), Enum.Material.Metal)
	local flag = part(parent, "Flag", Vector3.new(0.12, 4.4, 7), CFrame.new(pos + Vector3.new(0, 11.6, 3.5)), rgb(30, 60, 160))
	part(parent, "FlagStripe", Vector3.new(0.14, 1, 7), CFrame.new(pos + Vector3.new(0, 10.4, 3.5)), rgb(255, 255, 255))
	textSign(flag, Enum.NormalId.Right, "PH", rgb(255, 220, 90), nil, nil, 20)
	textSign(flag, Enum.NormalId.Left, "PH", rgb(255, 220, 90), nil, nil, 20)
end

local function solarArray(parent: Instance, pos: Vector3, yaw: number)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	part(parent, "SolarPost", Vector3.new(0.8, 5, 0.8), cf * CFrame.new(0, 2.5, 0), rgb(160, 166, 180), Enum.Material.Metal)
	for _, x in { -5.4, 0, 5.4 } do
		local tilt = cf * CFrame.new(x, 5.4, 0) * CFrame.Angles(-0.5, 0, 0)
		part(parent, "SolarPanel", Vector3.new(5, 0.3, 7), tilt, rgb(36, 60, 150), Enum.Material.Glass)
		part(parent, "SolarGrid", Vector3.new(5.04, 0.32, 0.2), tilt, rgb(150, 180, 230))
		part(parent, "SolarGrid", Vector3.new(0.2, 0.32, 7.04), tilt, rgb(150, 180, 230))
	end
	part(parent, "SolarBeam", Vector3.new(16.4, 0.4, 0.4), cf * CFrame.new(0, 5.2, 0), rgb(160, 166, 180), Enum.Material.Metal)
end

local function lander(parent: Instance, pos: Vector3, s: number)
	part(parent, "LanderBody", Vector3.new(7, 4, 7) * s, CFrame.new(pos + Vector3.new(0, 6, 0) * s) * CFrame.Angles(0, math.pi / 4, 0), rgb(214, 170, 60), Enum.Material.Foil)
	part(parent, "LanderCabin", Vector3.new(5, 4, 5) * s, CFrame.new(pos + Vector3.new(0, 10, 0) * s), HULL)
	part(parent, "LanderHatch", Vector3.new(1.8, 2, 0.3) * s, CFrame.new(pos + Vector3.new(0, 10, -2.6) * s), rgb(80, 86, 100))
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		local top = pos + Vector3.new(math.cos(a) * 3, 5.4, math.sin(a) * 3) * s
		local foot = pos + Vector3.new(math.cos(a) * 7, 0.4, math.sin(a) * 7) * s
		rod(parent, "LanderLeg", top, foot, 0.5 * s, rgb(200, 204, 214), Enum.Material.Metal)
		disc(parent, "LanderFoot", 2 * s, 0.4 * s, CFrame.new(foot), rgb(160, 166, 180), Enum.Material.Metal)
	end
end

local function moonExtras(scene: Instance, rng: Random, lowGraphics: boolean)
	local extras = folder(scene, "MoonExtras")
	-- A glass walkway tube joining the two big domes, and a landing pad's guide lights.
	rod(extras, "HabTube", Vector3.new(-HX - 74, 5, -38), Vector3.new(-HX - 88, 5, 36), 6, rgb(150, 210, 255), Enum.Material.Glass).Transparency = 0.4
	for k = 0, 9 do
		part(extras, "GuideLight", Vector3.new(1.4, 0.4, 1.4), CFrame.new(HX + 58, 0.2, -90 + k * 9), rgb(90, 200, 255), Enum.Material.Neon)
	end
	lander(extras, Vector3.new(-240, 0, -140), 1.6)
	moonFlag(extras, Vector3.new(-205, 0, -110))
	for i, spot in { Vector3.new(200, 0, 130), Vector3.new(-220, 0, 140), Vector3.new(260, 0, -150) } do
		rover(extras, spot, i * 1.9)
	end
	for k = 0, 3 do
		solarArray(extras, Vector3.new(-120 + k * 22, 0, -(HZ + 110)), 0)
		solarArray(extras, Vector3.new(60 + k * 22, 0, HZ + 110), math.pi)
	end
	-- A ringed planet and a satellite in the black sky.
	-- Low over the far end of the rink (a planet-rise, so the steep match camera still sees it).
	-- Under 470 studs from every match camera spot: graphics quality 1 (low-end phones, and
	-- Studio here) stops drawing parts at about 500.
	local planet = Vector3.new(290, 92, -80)
	ball(extras, "Planet", Vector3.new(64, 64, 64), CFrame.new(planet), rgb(230, 150, 90), Enum.Material.Neon)
	ball(extras, "PlanetBand", Vector3.new(65.2, 13, 65.2), CFrame.new(planet + Vector3.new(0, 7, 0)), rgb(250, 200, 140), Enum.Material.Neon)
	-- Two thin hoops, not a filled disc (from the ice a disc hid the planet behind it).
	local tilt = CFrame.new(planet) * CFrame.Angles(0.35, 0, 0.25)
	for _, r in { 46, 56 } do
		for k = 0, 31 do
			local a0, a1 = k / 32 * math.pi * 2, (k + 1) / 32 * math.pi * 2
			local p0 = (tilt * CFrame.new(math.cos(a0) * r, 0, math.sin(a0) * r)).Position
			local p1 = (tilt * CFrame.new(math.cos(a1) * r, 0, math.sin(a1) * r)).Position
			rod(extras, "PlanetRing", p0, p1, 4, if r == 46 then rgb(240, 220, 180) else rgb(220, 180, 140), Enum.Material.Neon)
		end
	end
	local sat = Vector3.new(-160, 140, 260)
	part(extras, "Satellite", Vector3.new(4, 4, 6), CFrame.new(sat) * CFrame.Angles(0.3, 0.5, 0), HULL)
	for _, sx in { -1, 1 } do
		part(extras, "SatPanel", Vector3.new(12, 0.3, 4), CFrame.new(sat) * CFrame.Angles(0.3, 0.5, 0) * CFrame.new(sx * 8.2, 0, 0), rgb(36, 60, 150), Enum.Material.Glass)
	end
	aroundRink(rng, if lowGraphics then 10 else 22, 1.25, 2.4, function(at: Vector3, i: number)
		if i % 3 == 0 then
			rover(extras, at, rng:NextNumber(0, 6))
		elseif i % 3 == 1 then
			solarArray(extras, at, rng:NextNumber(0, 6))
		else
			local s = rng:NextNumber(6, 14)
			ball(extras, "Boulder", Vector3.new(s, s * 0.65, s * 0.85), CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), rgb(120, 120, 128), Enum.Material.Slate)
		end
	end)
end

local function buildMoonBase(scene: Instance, crowd: Instance, fans: { Fan }, theme: Theme, lowGraphics: boolean)
	local rng = Random.new(1969)
	groundAndApron(scene, REGOLITH, Enum.Material.Sand, rgb(110, 116, 130), Enum.Material.DiamondPlate)
	paintedBleachers(scene, crowd, fans, rng, theme, lowGraphics, rgb(214, 218, 228), rgb(80, 88, 104), Enum.Material.Metal)
	-- Build 37: the crowd is green and purple aliens.
	alienCrowd(crowd, fans, Random.new(51))
	for _, sz in { -1, 1 } do
		for i = -2, 2 do
			floodlight(scene, Vector3.new(i * 44 + 6, 0, sz * (HZ + 4.5)))
		end
	end
	-- Build 37: grey moon mountains far out all round, and stars in the black sky.
	peakRing(folder(scene, "MoonMountains"), Random.new(37), if lowGraphics then 9 else 13, rgb(132, 132, 142), rgb(88, 88, 98), Enum.Material.Slate, rgb(196, 196, 204))
	starDome(scene, Random.new(1969), if lowGraphics then 140 else 320)
	rinkBillboards(scene, { "MOON BASE", "ZERO-G ZONE", "SHOOT FOR THE MOON" }, "PHYSHOCKEY", rgb(30, 40, 80), rgb(150, 220, 255), rgb(120, 128, 146), Enum.Material.Metal)
	moonExtras(scene, rng, lowGraphics)
	dome(scene, Vector3.new(-HX - 70, 0, -60), 46)
	dome(scene, Vector3.new(-HX - 90, 0, 50), 30)
	rocket(scene, Vector3.new(HX + 80, 0, -50), 2.2)
	dish(scene, Vector3.new(HX + 70, 0, 70), 2)
	aroundRink(rng, if lowGraphics then 30 else 70, 1.2, 2.8, function(at: Vector3, i: number)
		if i % 9 == 0 then
			dome(scene, at, rng:NextNumber(16, 26))
		elseif i % 9 == 4 then
			dish(scene, at, rng:NextNumber(1, 1.6))
		elseif i % 2 == 0 then
			crater(scene, at, rng:NextNumber(10, 40))
		else
			local s = rng:NextNumber(3, 8)
			ball(scene, "MoonRock", Vector3.new(s, s * 0.6, s * 0.8), CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), rgb(130, 130, 138), Enum.Material.Slate)
		end
	end)
	-- Grey hills on the horizon and the Earth hanging in the black sky.
	for i, spot in { Vector3.new(-520, 0, -420), Vector3.new(-80, 0, -580), Vector3.new(360, 0, -500), Vector3.new(600, 0, 200), Vector3.new(-600, 0, 220) } do
		for k = 0, 2 do
			local d = (240 + (i % 3) * 60) * (1 - k * 0.3)
			disc(scene, "MoonHill", d, 24, CFrame.new(spot + Vector3.new(0, 12 + k * 24, 0)), rgb(140, 140, 150):Lerp(rgb(180, 180, 188), k / 3), Enum.Material.Sand)
		end
	end
	local earth = Vector3.new(-500, 360, -900)
	ball(scene, "Earth", Vector3.new(150, 150, 150), CFrame.new(earth), rgb(40, 110, 220), Enum.Material.Neon)
	for k, off in { Vector3.new(-20, 30, 50), Vector3.new(35, -10, 55), Vector3.new(-40, -35, 40), Vector3.new(10, 50, 35) } do
		ball(scene, "Land", Vector3.new(50 - k * 5, 34, 40), CFrame.new(earth + off), rgb(60, 170, 80), Enum.Material.Neon)
	end
	ball(scene, "Clouds", Vector3.new(156, 30, 120), CFrame.new(earth + Vector3.new(0, 20, 30)), rgb(240, 245, 255), Enum.Material.Neon).Transparency = 0.5
end

-- Neon Arcade (indoor) -----------------------------------------------------------------------
local NEON_PINK = rgb(255, 60, 180)
local NEON_BLUE = rgb(40, 220, 255)

-- A ring of neon tubes, flat, at height y.
local function neonRing(parent: Instance, y: number, radius: number, color: Color3, count: number)
	for k = 0, count - 1 do
		local a0, a1 = k / count * math.pi * 2, (k + 1) / count * math.pi * 2
		rod(parent, "NeonRing", Vector3.new(math.cos(a0) * radius, y, math.sin(a0) * radius), Vector3.new(math.cos(a1) * radius, y, math.sin(a1) * radius), 1.2, color, Enum.Material.Neon)
	end
end

local function buildNeonArcade(arena: Instance, theme: Theme)
	local scene = folder(arena, "NeonArcade")
	-- The stands' light bands, re-lit in pink and blue.
	local stands = arena:FindFirstChild("Stands")
	if stands then
		local n = 0
		for _, p in stands:GetChildren() do
			if p:IsA("BasePart") and p.Name == "Band" then
				n += 1
				p.Color = if n % 2 == 0 then NEON_PINK else NEON_BLUE
			elseif p:IsA("BasePart") and p.Name == "Aisle" then
				p.Color = rgb(120, 50, 200)
				p.Material = Enum.Material.Neon
			end
		end
	end
	local topY = BOARD_H + theme.rows * 1.75
	-- Neon hoops over centre ice, and tubes along the concourse edge facing the ice.
	neonRing(scene, topY + 32, 34, NEON_PINK, 40)
	neonRing(scene, topY + 36, 24, NEON_BLUE, 32)
	neonRing(scene, topY + 40, 14, rgb(255, 220, 60), 24)
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		rod(scene, "Hanger", Vector3.new(math.cos(a) * 34, topY + 32, math.sin(a) * 34), Vector3.new(math.cos(a) * 34, topY + 52, math.sin(a) * 34), 0.3, rgb(20, 20, 30))
	end
	local walk = 7
	for _, sz in { -1, 1 } do
		part(scene, "EdgeTube", Vector3.new((HX + walk) * 2, 0.5, 0.5), CFrame.new(0, BOARD_H - 0.1, sz * (HZ + walk + 0.3)), if sz > 0 then NEON_PINK else NEON_BLUE, Enum.Material.Neon)
	end
	for _, sx in { -1, 1 } do
		part(scene, "EdgeTube", Vector3.new(0.5, 0.5, (HZ + walk) * 2), CFrame.new(sx * (HX + walk + 0.3), BOARD_H - 0.1, 0), if sx > 0 then NEON_PINK else NEON_BLUE, Enum.Material.Neon)
	end
	-- Lit floor tiles under the top of the stands' back wall: an arcade light chase.
	local outX, outZ = HX + walk + theme.rows * 3.1, HZ + walk + theme.rows * 3.1
	for i = -10, 10 do
		local c = if i % 3 == 0 then NEON_PINK elseif i % 3 == 1 then NEON_BLUE else rgb(255, 220, 60)
		for _, sz in { -1, 1 } do
			part(scene, "Chase", Vector3.new(4, 4, 0.4), CFrame.new(i * (outX / 10.5), topY + 9, sz * (outZ - 0.2)), c, Enum.Material.Neon)
		end
	end
end

-- Builds the world round one of the shop rinks. Returns the fans for the crowd animation.
local function buildShopScenery(arena: Instance, theme: Theme, lowGraphics: boolean): { Fan }
	if theme.scenery == "neon" then
		buildNeonArcade(arena, theme)
		return {}
	end
	local scene = folder(arena, theme.name)
	local crowd = folder(arena, "Crowd")
	local fans: { Fan } = {}
	if theme.scenery == "candy" then
		buildCandyLand(scene, crowd, fans, theme, lowGraphics)
	elseif theme.scenery == "beach" then
		buildTropicalBeach(scene, crowd, fans, theme, lowGraphics)
	elseif theme.scenery == "volcano" then
		buildVolcano(scene, crowd, fans, theme, lowGraphics)
	elseif theme.scenery == "moon" then
		buildMoonBase(scene, crowd, fans, theme, lowGraphics)
	end
	return fans
end

function ArenaBuilder.theme(name: string): Theme
	return THEMES[name] or THEMES.Arena
end

-- Builds one rink theme into a fresh model (not parented until it is complete).
function ArenaBuilder.build(themeName: string, lowGraphics: boolean): Built
	local theme = ArenaBuilder.theme(themeName)
	local arena = Instance.new("Model")
	arena.Name = `Rink_{theme.name}`
	buildIce(folder(arena, "Ice"), theme)
	buildBoards(folder(arena, "Boards"), theme)
	local goals = folder(arena, "Goals")
	buildGoal(goals, -1)
	buildGoal(goals, 1)
	local bottles = { buildBottle(goals, -1), buildBottle(goals, 1) }
	-- The pond's big rink is just a rink on the lake: no stands, no bleachers.
	local fans = if theme.indoor then buildStands(arena, theme, lowGraphics) else {}
	local penguins: { Penguin } = {}
	if theme.scenery == "forest" then
		fans = buildTimberline(arena, theme, lowGraphics)
	elseif theme.scenery and theme.scenery ~= "lake" then
		-- Build 34: the shop rinks.
		local more = buildShopScenery(arena, theme, lowGraphics)
		for _, f in more do
			table.insert(fans, f)
		end
	elseif theme.scenery == "lake" then
		fans = buildFrozenLake(arena, theme, penguins, lowGraphics)
	elseif not theme.indoor then
		buildPondWorld(arena, theme, penguins)
	end
	return { model = arena, fans = fans, penguins = penguins, theme = theme, bottles = bottles }
end

-- Waddles the pond penguins in place.
function ArenaBuilder.animatePenguins(list: { Penguin }, t: number)
	for _, p in list do
		local phase = t * 3 + p.phase
		local root = CFrame.new(p.home + Vector3.new(0, math.abs(math.sin(phase)) * 0.3, 0)) * CFrame.Angles(0, math.sin(t * 0.4 + p.phase) * 0.8, math.sin(phase) * 0.12)
		local cfs = table.create(#p.parts)
		for i, offset in p.offsets do
			cfs[i] = root * offset
		end
		workspace:BulkMoveTo(p.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- The lobby: a warm locker room far from the rink. Returns where the player's skater stands
-- and where the menu camera sits.
ArenaBuilder.LOBBY_ORIGIN = Vector3.new(0, 0, 3000)

export type Lobby = { model: Model, stand: CFrame, camera: CFrame, panelCamera: CFrame, statsCamera: CFrame, focus: Vector3 }

function ArenaBuilder.buildLobby(): Lobby
	local o = ArenaBuilder.LOBBY_ORIGIN
	local model = Instance.new("Model")
	model.Name = "LockerRoom"
	local WOOD = Color3.fromRGB(176, 132, 88)
	local WOOD_DARK = Color3.fromRGB(146, 106, 68)
	local LOCKER = Color3.fromRGB(214, 176, 124)
	local CUBBY = Color3.fromRGB(110, 78, 50)
	local TRIM = Color3.fromRGB(242, 238, 230)
	local CARPET = Color3.fromRGB(78, 80, 88)
	local RED = Color3.fromRGB(206, 50, 56)
	local BLUE = Color3.fromRGB(40, 92, 190)
	local INK = Color3.fromRGB(26, 26, 32)
	local standPos = o + Vector3.new(0, 0, -5)

	-- Shell: carpeted floor, slatted wooden walls, a pale trim band and a low ceiling.
	part(model, "Floor", Vector3.new(64, 1, 64), CFrame.new(o + Vector3.new(0, -0.5, 8)), CARPET, Enum.Material.Fabric)
	-- Team logo worked into the carpet under the skater: a darker disc and ring.
	disc(model, "FloorLogo", 17, 0.06, CFrame.new(standPos + Vector3.new(0, 0.03, 0)), Color3.fromRGB(70, 72, 80), Enum.Material.Fabric)
	disc(model, "FloorRing", 12, 0.07, CFrame.new(standPos + Vector3.new(0, 0.035, 0)), Color3.fromRGB(86, 88, 97), Enum.Material.Fabric)
	disc(model, "FloorCore", 10.6, 0.08, CFrame.new(standPos + Vector3.new(0, 0.04, 0)), Color3.fromRGB(72, 74, 82), Enum.Material.Fabric)
	-- Walls as in the reference: cream plaster above a slatted wood wainscot.
	local PLASTER = Color3.fromRGB(232, 226, 214)
	part(model, "BackWall", Vector3.new(64, 22, 0.6), CFrame.new(o + Vector3.new(0, 11, -20.6)), PLASTER, Enum.Material.SmoothPlastic)
	for i = 0, 47 do
		local x = -31.5 + i * 1.34
		part(model, "Slat", Vector3.new(1.3, 4.4, 0.4), CFrame.new(o + Vector3.new(x, 2.2, -20.15)), if i % 2 == 0 then WOOD else WOOD_DARK, Enum.Material.Wood)
	end
	part(model, "WainscotCap", Vector3.new(64, 0.4, 0.7), CFrame.new(o + Vector3.new(0, 4.6, -20.05)), WOOD_DARK, Enum.Material.Wood)
	part(model, "LeftWall", Vector3.new(1, 22, 64), CFrame.new(o + Vector3.new(-32, 11, 8)), PLASTER, Enum.Material.SmoothPlastic)
	part(model, "RightWall", Vector3.new(1, 22, 64), CFrame.new(o + Vector3.new(32, 11, 8)), PLASTER, Enum.Material.SmoothPlastic)
	part(model, "FrontWall", Vector3.new(64, 22, 1), CFrame.new(o + Vector3.new(0, 11, 40)), PLASTER, Enum.Material.SmoothPlastic)
	-- Warm LED strip along the locker tops (a glowing strip only: it casts no light).
	local strip = part(model, "LedStrip", Vector3.new(29.4, 0.2, 0.3), CFrame.new(o + Vector3.new(-16, 14.35, -15.5)), Color3.fromRGB(255, 226, 170), Enum.Material.Neon)
	strip.CastShadow = false
	part(model, "TopTrim", Vector3.new(64, 1.6, 0.4), CFrame.new(o + Vector3.new(0, 20.6, -19.8)), TRIM)
	part(model, "Ceiling", Vector3.new(64, 1, 64), CFrame.new(o + Vector3.new(0, 22, 8)), Color3.fromRGB(226, 224, 220))
	-- Rows of small round ceiling lights, like a broadcast locker room.
	for row = 0, 3 do
		for i = -7, 7 do
			local p = disc(model, "Downlight", 0.9, 0.1, CFrame.new(o + Vector3.new(i * 4 + (row % 2) * 2, 21.45, -16 + row * 6)), Color3.fromRGB(255, 250, 236), Enum.Material.Neon)
			p.CastShadow = false
		end
	end

	-- Lockers: open cubbies with a top shelf, a hanging jersey, a helmet, a stick and a bench.
	local function locker(x: number, index: number)
		local base = o + Vector3.new(x, 0, -17.4)
		part(model, "LockerBack", Vector3.new(5.6, 14, 0.4), CFrame.new(base + Vector3.new(0, 7, -1.6)), CUBBY, Enum.Material.Wood)
		for _, side in { -1, 1 } do
			part(model, "LockerSide", Vector3.new(0.35, 14, 3.6), CFrame.new(base + Vector3.new(side * 2.8, 7, 0)), LOCKER, Enum.Material.Wood)
		end
		part(model, "LockerTop", Vector3.new(6, 0.5, 3.8), CFrame.new(base + Vector3.new(0, 14, 0)), LOCKER, Enum.Material.Wood)
		part(model, "LockerShelf", Vector3.new(5.3, 0.3, 3.4), CFrame.new(base + Vector3.new(0, 10.4, 0)), LOCKER, Enum.Material.Wood)
		part(model, "Bench", Vector3.new(5.6, 0.5, 3.0), CFrame.new(base + Vector3.new(0, 2.6, 1.0)), LOCKER, Enum.Material.Wood)
		part(model, "BenchBase", Vector3.new(5.2, 2.4, 2.6), CFrame.new(base + Vector3.new(0, 1.2, 0.8)), Color3.fromRGB(196, 158, 110), Enum.Material.Wood)
		-- A jersey on a hanger: body, angled sleeves with stripes, collar, hem stripe and number.
		local jersey = if index % 3 == 0 then RED elseif index % 3 == 1 then Color3.fromRGB(246, 246, 248) else BLUE
		local stripe = if jersey == RED then Color3.fromRGB(246, 246, 248) else RED
		local jc = base + Vector3.new(0, 7.0, -0.7)
		local metal = Color3.fromRGB(200, 200, 206)
		part(model, "Hanger", Vector3.new(2.7, 0.12, 0.12), CFrame.new(jc + Vector3.new(0, 2.1, 0)), metal, Enum.Material.Metal)
		part(model, "HangerHook", Vector3.new(0.12, 0.7, 0.12), CFrame.new(jc + Vector3.new(0, 2.5, 0)), metal, Enum.Material.Metal)
		part(model, "JerseyBody", Vector3.new(2.9, 4.0, 0.5), CFrame.new(jc), jersey, Enum.Material.Fabric)
		for _, side in { -1, 1 } do
			local sleeve = CFrame.new(jc + Vector3.new(side * 1.72, 0.95, 0)) * CFrame.Angles(0, 0, side * 0.55)
			part(model, "JerseySleeve", Vector3.new(1.3, 2.2, 0.48), sleeve, jersey, Enum.Material.Fabric)
			part(model, "SleeveStripe", Vector3.new(1.32, 0.3, 0.5), sleeve * CFrame.new(0, -0.6, 0), stripe, Enum.Material.Fabric)
		end
		part(model, "JerseyStripe", Vector3.new(2.92, 0.35, 0.52), CFrame.new(jc + Vector3.new(0, -1.25, 0)), stripe, Enum.Material.Fabric)
		part(model, "JerseyCollar", Vector3.new(1.1, 0.28, 0.54), CFrame.new(jc + Vector3.new(0, 1.9, 0)), stripe, Enum.Material.Fabric)
		local number = part(model, "JerseyNumber", Vector3.new(1.8, 1.5, 0.05), CFrame.new(jc + Vector3.new(0, 0.3, 0.27)), jersey, nil, 1)
		textSign(number, Enum.NormalId.Back, tostring(7 + index * 4), stripe, nil, Enum.Font.GothamBlack, 30)
		-- The team's own hockey helmet on the shelf (the modelled one), facing the room.
		local helmetColor = if index % 2 == 0 then INK else BLUE
		local shelfHelmet = Looks.headwearProp(model, "Helmet", helmetColor, RED, CFrame.new(base + Vector3.new(0, 11.45, -0.2)) * CFrame.Angles(0, math.pi + (index % 2 - 0.5) * 0.6, 0), 0.62)
		if #shelfHelmet == 0 then
			ball(model, "Helmet", Vector3.new(2.4, 1.7, 2.4), CFrame.new(base + Vector3.new(0, 11.4, -0.2)), helmetColor)
		end
		-- A pair of skates in front of every other bench.
		if index % 2 == 1 then
			for _, side in { -1, 1 } do
				local at = CFrame.new(base + Vector3.new(side * 0.75 - 0.6, 0, 3.0)) * CFrame.Angles(0, 0.25 * side, 0)
				part(model, "SkateBoot", Vector3.new(0.75, 1.0, 1.5), at * CFrame.new(0, 0.85, 0.1), INK)
				part(model, "SkateTongue", Vector3.new(0.6, 0.5, 0.3), at * CFrame.new(0, 1.45, -0.45), Color3.fromRGB(60, 62, 70))
				part(model, "SkateBlade", Vector3.new(0.1, 0.3, 1.8), at * CFrame.new(0, 0.2, 0), metal, Enum.Material.Metal)
			end
		end
		local stick = part(model, "Stick", Vector3.new(0.3, 9.5, 0.3), CFrame.new(base + Vector3.new(2.1, 5.2, 0.9)) * CFrame.Angles(0, 0, 0.1), INK)
		part(model, "StickBlade", Vector3.new(1.6, 0.6, 0.25), stick.CFrame * CFrame.new(-0.6, -4.6, 0), Color3.fromRGB(246, 246, 248))
		local plate = part(model, "Plate", Vector3.new(4, 0.9, 0.2), CFrame.new(base + Vector3.new(0, 13.2, 1.95)), Color3.fromRGB(246, 246, 248))
		textSign(plate, Enum.NormalId.Back, tostring(7 + index * 4), INK, nil, Enum.Font.GothamBlack, 24)
	end
	local index = 0
	for _, x in { -27.6, -21.8, -16, -10.2, -4.4 } do
		index += 1
		locker(x, index)
	end

	-- Hanging banners above the left lockers: rod, cloth and a notched tail.
	local banners = {
		{ -24.7, BLUE, "ICE\nCUP" },
		{ -18.9, RED, "PUCK\nLEAGUE" },
		{ -13.1, INK, "SLAP\nCLASSIC" },
		{ -7.3, Color3.fromRGB(240, 150, 40), "JUNIOR\nSERIES" },
	}
	for _, b in banners do
		local x, color, text = b[1], b[2], b[3]
		local at = o + Vector3.new(x, 0, -19.6)
		part(model, "BannerRod", Vector3.new(5.6, 0.25, 0.25), CFrame.new(at + Vector3.new(0, 19.4, 0.3)), Color3.fromRGB(200, 200, 206), Enum.Material.Metal)
		-- Hung high enough that both words clear the locker tops from the lobby camera.
		local cloth = part(model, "Banner", Vector3.new(5, 4.0, 0.15), CFrame.new(at + Vector3.new(0, 17.3, 0.3)), color, Enum.Material.Fabric)
		textSign(cloth, Enum.NormalId.Back, text, Color3.fromRGB(255, 255, 255), nil, Enum.Font.GothamBlack, 22)
		for _, side in { -1, 1 } do
			part(model, "BannerTail", Vector3.new(2.8, 1.6, 0.15), CFrame.new(at + Vector3.new(side * 1.25, 14.9, 0.3)) * CFrame.Angles(0, 0, side * 0.35), color, Enum.Material.Fabric)
		end
		part(model, "BannerTrim", Vector3.new(5, 0.35, 0.18), CFrame.new(at + Vector3.new(0, 15.45, 0.31)), Color3.fromRGB(255, 206, 60))
	end

	-- Centre alcove: a pale arch with a glowing team crest and a framed poster.
	part(model, "AlcoveBack", Vector3.new(13, 16, 0.5), CFrame.new(o + Vector3.new(10, 8, -19.8)), Color3.fromRGB(196, 188, 174))
	disc(model, "AlcoveArch", 13, 0.5, CFrame.new(o + Vector3.new(10, 16, -19.8)) * CFrame.Angles(math.pi / 2, 0, 0), Color3.fromRGB(196, 188, 174))
	for _, side in { -1, 1 } do
		part(model, "AlcovePillar", Vector3.new(0.8, 16, 1.2), CFrame.new(o + Vector3.new(10 + side * 6.6, 8, -19.4)), Color3.fromRGB(226, 220, 210))
	end
	local crestAt = CFrame.new(o + Vector3.new(10, 17, -19.3)) * CFrame.Angles(math.pi / 2, 0, 0)
	disc(model, "CrestGlow", 5.6, 0.12, crestAt, Color3.fromRGB(120, 230, 255), Enum.Material.Neon)
	disc(model, "CrestRing", 5.0, 0.16, crestAt * CFrame.new(0, -0.02, 0), Color3.fromRGB(30, 60, 110))
	local crest = part(model, "Crest", Vector3.new(3.6, 3.6, 0.1), CFrame.new(o + Vector3.new(10, 17, -19.15)), Color3.fromRGB(30, 60, 110))
	crest.Transparency = 1
	textSign(crest, Enum.NormalId.Back, "PP", Color3.fromRGB(150, 236, 255), nil, Enum.Font.FredokaOne, 40)
	for _, side in { -1, 1 } do
		part(model, "CrestStick", Vector3.new(0.25, 5.4, 0.15), CFrame.new(o + Vector3.new(10 + side * 1.4, 17.4, -19.12)) * CFrame.Angles(0, 0, side * 0.6), Color3.fromRGB(150, 236, 255), Enum.Material.Neon)
	end
	part(model, "PosterGlow", Vector3.new(6.6, 8.6, 0.12), CFrame.new(o + Vector3.new(10, 8.6, -19.45)), Color3.fromRGB(110, 220, 255), Enum.Material.Neon)
	local poster = part(model, "Poster", Vector3.new(6, 8, 0.2), CFrame.new(o + Vector3.new(10, 8.6, -19.35)), Color3.fromRGB(20, 22, 30))
	keyArtPoster(poster)

	-- Big wall screen on the right, playing the highlight reel.
	part(model, "ScreenFrame", Vector3.new(12, 7.6, 0.5), CFrame.new(o + Vector3.new(24.6, 10, -19.7)), Color3.fromRGB(196, 158, 110), Enum.Material.Wood)
	local screen = part(model, "Screen", Vector3.new(11, 6.8, 0.2), CFrame.new(o + Vector3.new(24.6, 10, -19.4)), Color3.fromRGB(28, 30, 34))
	screen.Reflectance = 0.08
	highlightScreen(screen, model)

	-- Two framed action posters above the screen.
	for i, shot in { ACTION_SHOTS[1], ACTION_SHOTS[2] } do
		local x = if i == 1 then 21.3 else 27.9
		part(model, "ActionFrame", Vector3.new(5.4, 3.6, 0.4), CFrame.new(o + Vector3.new(x, 16.9, -19.75)), Color3.fromRGB(196, 158, 110), Enum.Material.Wood)
		local printPart = part(model, "ActionPoster", Vector3.new(5.0, 3.2, 0.1), CFrame.new(o + Vector3.new(x, 16.9, -19.5)), Color3.fromRGB(20, 22, 30))
		actionPrint(printPart, shot)
	end

	-- Trophy case under the screen: a glass-fronted cabinet with the season cups on top.
	local gold = Color3.fromRGB(240, 190, 60)
	local silver = Color3.fromRGB(214, 220, 230)
	local caseAt = o + Vector3.new(25.4, 0, -18.6)
	part(model, "TrophyCase", Vector3.new(6.4, 3.0, 2.2), CFrame.new(caseAt + Vector3.new(0, 1.5, 0)), Color3.fromRGB(150, 112, 74), Enum.Material.Wood)
	part(model, "TrophyCaseTop", Vector3.new(6.8, 0.25, 2.5), CFrame.new(caseAt + Vector3.new(0, 3.12, 0)), Color3.fromRGB(196, 158, 110), Enum.Material.Wood)
	part(model, "TrophyGlass", Vector3.new(5.6, 2.2, 0.1), CFrame.new(caseAt + Vector3.new(0, 1.55, 1.12)), Color3.fromRGB(170, 220, 240), Enum.Material.Glass, 0.45)
	for i = -1, 1 do
		-- Medals and a puck on the inside shelf, seen through the glass.
		disc(model, "Medal", 0.7, 0.12, CFrame.new(caseAt + Vector3.new(i * 1.7, 1.6, 0.9)) * CFrame.Angles(math.pi / 2, 0, 0), if i == 0 then gold else silver, Enum.Material.Metal)
	end
	disc(model, "CasePuck", 1.0, 0.4, CFrame.new(caseAt + Vector3.new(0.85, 0.75, 0.6)), INK)
	-- Big cup in the middle, a small one either side.
	local function cup(at: Vector3, s: number, color: Color3)
		disc(model, "TrophyBase", 1.3 * s, 0.5 * s, CFrame.new(at + Vector3.new(0, 0.25 * s, 0)), INK)
		part(model, "TrophyStem", Vector3.new(0.28, 0.8, 0.28) * s, CFrame.new(at + Vector3.new(0, 0.9 * s, 0)), color, Enum.Material.Metal)
		ball(model, "TrophyCup", Vector3.new(1.5, 1.2, 1.5) * s, CFrame.new(at + Vector3.new(0, 1.75 * s, 0)), color, Enum.Material.Metal)
		disc(model, "TrophyRim", 1.55 * s, 0.14 * s, CFrame.new(at + Vector3.new(0, 2.2 * s, 0)), color, Enum.Material.Metal)
		for _, side in { -1, 1 } do
			disc(model, "TrophyHandle", 0.7 * s, 0.14 * s, CFrame.new(at + Vector3.new(side * 0.85 * s, 1.85 * s, 0)) * CFrame.Angles(math.pi / 2, 0, 0), color, Enum.Material.Metal)
		end
	end
	cup(caseAt + Vector3.new(0, 3.25, 0), 1.1, gold)
	cup(caseAt + Vector3.new(-2.2, 3.25, 0.1), 0.75, silver)
	cup(caseAt + Vector3.new(2.2, 3.25, 0.1), 0.75, Color3.fromRGB(205, 128, 72))

	-- Floor props: puck bucket, gear bags, a drinks cooler and a first-aid box.
	disc(model, "Bucket", 3.2, 2.4, CFrame.new(o + Vector3.new(-8, 1.2, -13)), Color3.fromRGB(70, 180, 80))
	disc(model, "BucketRim", 3.4, 0.3, CFrame.new(o + Vector3.new(-8, 2.4, -13)), Color3.fromRGB(56, 150, 66))
	for i = 0, 5 do
		disc(model, "Puck", 1.4, 0.5, CFrame.new(o + Vector3.new(-8 + (i % 3 - 1) * 0.75, 2.6 + math.floor(i / 3) * 0.45, -13 + (i % 2) * 0.5)), INK)
	end
	local function bag(at: Vector3, yaw: number, color: Color3)
		local cf = CFrame.new(at) * CFrame.Angles(0, yaw, 0)
		part(model, "Bag", Vector3.new(6, 2.6, 2.8), cf * CFrame.new(0, 1.4, 0), color, Enum.Material.Fabric)
		for _, side in { -1, 1 } do
			disc(model, "BagEnd", 2.8, 0.6, cf * CFrame.new(side * 3, 1.4, 0) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Fabric)
		end
		part(model, "BagStripe", Vector3.new(6.05, 0.5, 2.85), cf * CFrame.new(0, 1.0, 0), Color3.fromRGB(60, 62, 70), Enum.Material.Fabric)
		part(model, "BagHandle", Vector3.new(2.2, 0.3, 0.4), cf * CFrame.new(0, 2.85, 0), INK)
	end
	bag(o + Vector3.new(17, 0, -9), 0.2, Color3.fromRGB(70, 72, 80))
	bag(o + Vector3.new(24.5, 0, -6), -0.35, RED)
	-- Drinks cooler against the right wall, glass facing the room (clear of the trophy case).
	local coolerAt = CFrame.new(o + Vector3.new(29.9, 0, -12.5)) * CFrame.Angles(0, -math.pi / 2, 0)
	part(model, "Cooler", Vector3.new(4, 5, 3), coolerAt * CFrame.new(0, 2.5, 0), RED)
	part(model, "CoolerGlass", Vector3.new(3.2, 3.6, 0.1), coolerAt * CFrame.new(0, 2.8, 1.55), Color3.fromRGB(170, 220, 240), Enum.Material.Glass, 0.3)
	for i = 0, 5 do
		disc(model, "Can", 0.5, 0.9, coolerAt * CFrame.new((i % 3 - 1) * 0.9, 1.9 + math.floor(i / 3) * 1.4, 1.2), if i % 2 == 0 then RED else BLUE)
	end
	part(model, "FirstAid", Vector3.new(2.4, 1.8, 1.4), CFrame.new(o + Vector3.new(-3.5, 0.9, -15.5)), RED)
	part(model, "FirstAidCross", Vector3.new(0.4, 1.1, 1.45), CFrame.new(o + Vector3.new(-3.5, 0.9, -15.5)), Color3.fromRGB(255, 255, 255))
	part(model, "FirstAidCross2", Vector3.new(1.1, 0.4, 1.45), CFrame.new(o + Vector3.new(-3.5, 0.9, -15.5)), Color3.fromRGB(255, 255, 255))

	-- No lamps in here on purpose: Roblox switches local lights on a few seconds after load, so
	-- lamps made the room jump from normal to glaring. The room is lit only by the steady
	-- ambient light in the lobby lighting recipe, so it looks the same from the first frame.

	-- The skater faces the camera with the blade out on the screen's left, as in the reference.
	local stand = CFrame.lookAt(standPos, standPos + Vector3.new(0, 0, 1))
	local focus = standPos + Vector3.new(0, 4.4, 0)
	local camPos = standPos + Vector3.new(0, 6.8, 21)
	-- With a right-side panel open, slide the view so the skater sits left of centre.
	local panelFocus = focus + Vector3.new(6.5, 0, 0)
	local panelCamPos = camPos + Vector3.new(6.5, 0, 0)
	-- Build 36: CAREER STATS zooms in close, a little low and from the right, with the skater
	-- filling the left third and the stats panel on the right.
	local statsFocus = standPos + Vector3.new(3.6, 3.6, 0)
	local statsCamPos = standPos + Vector3.new(6.4, 4.7, 14.5)
	return {
		model = model,
		stand = stand,
		camera = CFrame.lookAt(camPos, focus),
		panelCamera = CFrame.lookAt(panelCamPos, panelFocus),
		statsCamera = CFrame.lookAt(statsCamPos, statsFocus),
		focus = focus,
	}
end

-- Lighting recipes as data (vault: "Stylized Lighting Recipes", bright cartoon recipe, tuned
-- for a white ice sheet). Contrast lives in the ambient tint and the warm key-light shift, not
-- only in shadows, so the look still reads on phones at low quality. Bloom's threshold sits
-- above 1 so the white boards and ice never glow. One function owns Lighting.
local RECIPES = {
	indoor = {
		ClockTime = 13.5,
		Brightness = 1.3,
		Ambient = Color3.fromRGB(118, 124, 142),
		OutdoorAmbient = Color3.fromRGB(128, 134, 152),
		ColorShift_Top = Color3.fromRGB(255, 236, 210),
		ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
		EnvironmentDiffuseScale = 0.35,
		EnvironmentSpecularScale = 0.15,
		ExposureCompensation = -0.25,
		ShadowSoftness = 0.35,
		atmosphere = { Density = 0.12, Offset = 0.1, Color = Color3.fromRGB(200, 222, 250), Decay = Color3.fromRGB(120, 160, 210), Glare = 0, Haze = 0.2 },
		bloom = { Intensity = 0.35, Size = 24, Threshold = 1.6 },
		grade = { Brightness = 0, Contrast = 0.12, Saturation = 0.12, TintColor = Color3.fromRGB(255, 252, 248) },
	},
	outdoor = {
		ClockTime = 14,
		Brightness = 1.6,
		Ambient = Color3.fromRGB(110, 115, 135),
		OutdoorAmbient = Color3.fromRGB(150, 158, 176),
		ColorShift_Top = Color3.fromRGB(255, 236, 205),
		ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
		EnvironmentDiffuseScale = 0.3,
		EnvironmentSpecularScale = 0,
		ExposureCompensation = -0.3,
		ShadowSoftness = 0.3,
		atmosphere = { Density = 0.3, Offset = 0.15, Color = Color3.fromRGB(205, 225, 250), Decay = Color3.fromRGB(130, 165, 215), Glare = 0, Haze = 0.8 },
		bloom = { Intensity = 0.35, Size = 24, Threshold = 1.6 },
		grade = { Brightness = 0.02, Contrast = 0.08, Saturation = 0.18, TintColor = Color3.fromRGB(255, 255, 255) },
	},
}

-- Dusk on the frozen lake: low orange sun, violet sky haze, the lamps and string lights glowing.
RECIPES.dusk = {
	ClockTime = 17.7,
	Brightness = 1.3,
	Ambient = Color3.fromRGB(92, 88, 118),
	OutdoorAmbient = Color3.fromRGB(128, 116, 146),
	ColorShift_Top = Color3.fromRGB(255, 176, 116),
	ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
	EnvironmentDiffuseScale = 0.3,
	EnvironmentSpecularScale = 0,
	ExposureCompensation = -0.1,
	ShadowSoftness = 0.4,
	atmosphere = { Density = 0.34, Offset = 0.1, Color = Color3.fromRGB(255, 190, 150), Decay = Color3.fromRGB(120, 96, 160), Glare = 0.4, Haze = 1.4 },
	bloom = { Intensity = 0.7, Size = 26, Threshold = 1.15 },
	grade = { Brightness = 0.02, Contrast = 0.1, Saturation = 0.16, TintColor = Color3.fromRGB(255, 242, 232) },
}

local function effect(lighting: Lighting, class: string, name: string): any
	local found = lighting:FindFirstChild(name)
	if found and found.ClassName == class then
		return found
	end
	local made = Instance.new(class)
	made.Name = name
	made.Parent = lighting
	return made
end

-- The locker room: a closed, ceiling-lit room, so the look comes from its own lamps, with soft
-- neutral ambient (no orange cast on the wood) and gentle contrast.
RECIPES.lobby = {
	ClockTime = 13.5,
	Brightness = 0.6,
	Ambient = Color3.fromRGB(104, 104, 110),
	OutdoorAmbient = Color3.fromRGB(104, 104, 110),
	ColorShift_Top = Color3.fromRGB(255, 244, 228),
	ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
	EnvironmentDiffuseScale = 0.5,
	EnvironmentSpecularScale = 0.3,
	ExposureCompensation = 0,
	ShadowSoftness = 0.6,
	atmosphere = { Density = 0, Offset = 0, Color = Color3.fromRGB(200, 200, 200), Decay = Color3.fromRGB(200, 200, 200), Glare = 0, Haze = 0 },
	bloom = { Intensity = 0.5, Size = 24, Threshold = 1.4 },
	grade = { Brightness = 0, Contrast = 0.1, Saturation = -0.04, TintColor = Color3.fromRGB(255, 252, 248) },
}

-- Build 34: the shop rinks' lighting, each built from the outdoor or indoor recipe.
local function recipeFrom(base: any, over: any): any
	local r = table.clone(base)
	for k, v in over do
		if type(v) == "table" then
			local t = table.clone(base[k])
			for kk, vv in v do
				t[kk] = vv
			end
			r[k] = t
		else
			r[k] = v
		end
	end
	return r
end
RECIPES.NeonArcade = recipeFrom(RECIPES.indoor, {
	Brightness = 0.9,
	Ambient = Color3.fromRGB(110, 100, 150),
	OutdoorAmbient = Color3.fromRGB(110, 100, 150),
	ColorShift_Top = Color3.fromRGB(220, 200, 255),
	ExposureCompensation = 0,
	atmosphere = { Density = 0.2, Color = Color3.fromRGB(150, 110, 220), Decay = Color3.fromRGB(90, 60, 160), Haze = 0.6 },
	bloom = { Intensity = 0.8, Size = 30, Threshold = 1.2 },
	grade = { Contrast = 0.14, Saturation = 0.25, TintColor = Color3.fromRGB(246, 240, 255) },
})
RECIPES.CandyLand = recipeFrom(RECIPES.outdoor, {
	Brightness = 1.8,
	Ambient = Color3.fromRGB(140, 120, 150),
	OutdoorAmbient = Color3.fromRGB(190, 170, 200),
	ColorShift_Top = Color3.fromRGB(255, 220, 236),
	atmosphere = { Density = 0.28, Color = Color3.fromRGB(255, 210, 236), Decay = Color3.fromRGB(200, 160, 230), Haze = 0.9 },
	grade = { Saturation = 0.3, TintColor = Color3.fromRGB(255, 250, 252) },
})
RECIPES.TropicalBeach = recipeFrom(RECIPES.outdoor, {
	ClockTime = 15.2,
	Brightness = 2,
	Ambient = Color3.fromRGB(120, 120, 130),
	OutdoorAmbient = Color3.fromRGB(170, 166, 170),
	ColorShift_Top = Color3.fromRGB(255, 226, 180),
	atmosphere = { Density = 0.26, Color = Color3.fromRGB(200, 236, 255), Decay = Color3.fromRGB(110, 190, 230), Haze = 0.7 },
	grade = { Saturation = 0.28, TintColor = Color3.fromRGB(255, 252, 244) },
})
-- Build 36: a bright jungle afternoon (was a smoky red dusk that made the ice hard to read), with
-- a light warm-green haze so the volcanoes still sit back in the distance.
RECIPES.Volcano = recipeFrom(RECIPES.outdoor, {
	ClockTime = 14.2,
	Brightness = 2.1,
	Ambient = Color3.fromRGB(120, 124, 110),
	OutdoorAmbient = Color3.fromRGB(160, 166, 146),
	ColorShift_Top = Color3.fromRGB(255, 240, 210),
	ExposureCompensation = 0,
	atmosphere = { Density = 0.3, Offset = 0.05, Color = Color3.fromRGB(214, 228, 200), Decay = Color3.fromRGB(130, 160, 120), Glare = 0.1, Haze = 0.9 },
	bloom = { Intensity = 0.6, Size = 24, Threshold = 1.3 },
	grade = { Contrast = 0.1, Saturation = 0.25, TintColor = Color3.fromRGB(255, 252, 240) },
})
-- Build 39: Frozen Lake by day (it was RECIPES.dusk): high winter sun, a clear cold-blue sky,
-- bright snow kept just under blowing out, and a light haze over the pines.
RECIPES.FrozenLake = recipeFrom(RECIPES.outdoor, {
	ClockTime = 13,
	Brightness = 2,
	Ambient = Color3.fromRGB(118, 126, 146),
	OutdoorAmbient = Color3.fromRGB(156, 166, 188),
	ColorShift_Top = Color3.fromRGB(255, 244, 226),
	ExposureCompensation = -0.35,
	atmosphere = { Density = 0.28, Offset = 0.12, Color = Color3.fromRGB(214, 230, 250), Decay = Color3.fromRGB(140, 176, 222), Glare = 0.15, Haze = 0.7 },
	bloom = { Intensity = 0.3, Size = 24, Threshold = 1.7 },
	grade = { Brightness = 0.02, Contrast = 0.1, Saturation = 0.14, TintColor = Color3.fromRGB(250, 252, 255) },
})
RECIPES.MoonBase = recipeFrom(RECIPES.outdoor, {
	ClockTime = 0.5,
	Brightness = 2.2,
	Ambient = Color3.fromRGB(150, 156, 180),
	OutdoorAmbient = Color3.fromRGB(150, 156, 180),
	ColorShift_Top = Color3.fromRGB(220, 230, 255),
	ExposureCompensation = 0.1,
	atmosphere = { Density = 0, Offset = 0, Haze = 0, Glare = 0 },
	bloom = { Intensity = 0.6, Size = 26, Threshold = 1.3 },
	grade = { Contrast = 0.12, Saturation = -0.05, TintColor = Color3.fromRGB(240, 246, 255) },
})

function ArenaBuilder.applyLighting(lighting: Lighting, themeName: string)
	local theme = if themeName == "Lobby" then { name = "Lobby", indoor = true } else ArenaBuilder.theme(themeName)
	local recipe: any = if themeName == "Lobby" then RECIPES.lobby
		elseif (RECIPES :: any)[themeName] then (RECIPES :: any)[themeName]
		elseif theme.indoor then RECIPES.indoor
		else RECIPES.outdoor
	lighting.GeographicLatitude = 30
	lighting.GlobalShadows = true
	for key, value in recipe do
		if type(value) ~= "table" then
			(lighting :: any)[key] = value
		end
	end
	if theme.name == "Night" then
		lighting.ExposureCompensation = 0
	end
	for key, value in recipe.atmosphere do
		effect(lighting, "Atmosphere", "Atmosphere")[key] = value
	end
	for key, value in recipe.bloom do
		effect(lighting, "BloomEffect", "Bloom")[key] = value
	end
	for key, value in recipe.grade do
		effect(lighting, "ColorCorrectionEffect", "Grade")[key] = value
	end
end

return ArenaBuilder
