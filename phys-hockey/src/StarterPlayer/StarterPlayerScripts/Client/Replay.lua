--!strict
-- Goal replay, TV style. The client keeps the last few seconds of the match exactly as it drew
-- them (every skater's render state and the puck), so the replay is what you saw, with no extra
-- network traffic. After a goal: the horn and spotlight celebration plays first, then a white
-- slash cuts across the screen, two team-coloured panels slam together along it with REPLAY on
-- the seam, split apart onto the replay (a slow-motion broadcast shot from the side, then a cut
-- to the net cam behind the goal), and the same wipe takes you back to the live rink.
--
-- Camera ownership follows the vault's cutscene rules ("Cameras and Cutscenes"): remember every
-- ScreenGui that was on and hide them while the replay draws, restore exactly those, and restore
-- on every exit path (the replay ending, a skip, the phase moving on, leaving the match, and a
-- watchdog). Letterbox bars use ScreenInsets None and no safe-area clipping ("Camera Shake and
-- Camera FX", the letterbox fix). Left click (A, a tap) votes to skip; the server skips it for everyone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("GameConfig"))
local Protocol = require(Shared:WaitForChild("Protocol"))

local Replay = {}

local SLOTS = Protocol.SLOTS
local GOAL_X = Config.Goal.X
local HALF_MOUTH = Config.Goal.Width / 2
local HALF_WIDTH = Config.Arena.Width / 2

-- Timeline, in seconds of real time after the goal event (Config.Match.GoalFreeze holds the
-- whole thing: celebration, wipe, replay, wipe back, then the face-off).
Replay.CELEBRATE = 3.2 -- lights down, horn, spotlight on the scorer (Build 39: 3.2, was 2.2: a beat longer before the replay)
local KEEP_RECORDING = 0.7 -- keep filming this long after the goal event (the puck in the net)
local BEFORE_GOAL = 2.0 -- recorded seconds shown before the puck crosses the line
local AFTER_GOAL = 0.6 -- and after
local NET_CAM_LEAD = 0.5 -- the cut to the net cam comes this long (recorded time) before the goal
local SIDE_RATE = 0.85 -- playback speed for the broadcast shot
local NET_RATE = 0.5 -- and for the net cam, slower for the finish

-- The ring buffer: about 4.5 s at up to 60 frames a second, every table made up front.
local CAPACITY = 300
local MIN_GAP = 1 / 75 -- frames closer than this are skipped (high refresh screens)

type SkaterFrame = {
	visible: boolean,
	x: number,
	z: number,
	vx: number,
	vz: number,
	yaw: number,
	radius: number,
	charging: boolean,
	active: boolean,
	charge: number,
	lifted: boolean,
	lofting: boolean,
	sprinting: boolean,
	stunned: boolean,
}
type RecFrame = { t: number, s: { SkaterFrame }, px: number, py: number, pz: number, pvx: number, pvz: number }

local function newSkaterFrame(): SkaterFrame
	return {
		visible = false, x = 0, z = 0, vx = 0, vz = 0, yaw = 0, radius = 0.7,
		charging = false, active = false, charge = 0, lifted = false, lofting = false, sprinting = false, stunned = false,
	}
end

local ring: { RecFrame } = table.create(CAPACITY)
for i = 1, CAPACITY do
	local s = table.create(SLOTS)
	for slot = 1, SLOTS do
		s[slot] = newSkaterFrame()
	end
	ring[i] = { t = -math.huge, s = s, px = 0, py = 0, pz = 0, pvx = 0, pvz = 0 }
end
local head = 0 -- index of the newest frame
local count = 0
local frozen = false

-- What the replay draws this frame (filled by sampling the buffer).
local out: { SkaterFrame } = table.create(SLOTS)
for slot = 1, SLOTS do
	out[slot] = newSkaterFrame()
end

-- State machine: "idle" -> "waiting" (celebration) -> "wipeIn" -> "playing" -> "wipeOut" -> "idle".
local phase = "idle"
local phaseAt = 0
local drawing = false
local info: any = nil
local seenGoals: { [number]: boolean } = {}
local replayStart, replayGoal, replayEnd = 0, 0, 0 -- recorded times
local cursor = 0 -- the recorded time being shown
local netSide = 1
local netZ = 1 -- which side of the net the reverse angle sits on
local camX = 0
local lastShot = 0
local watchdogAt = 0
local hidden: { ScreenGui } = {}

-- GUI -------------------------------------------------------------------------------------

local gui: ScreenGui
local panelA: Frame
local panelB: Frame
local stripeA: Frame
local stripeB: Frame
local slash: Frame
local flash: Frame
local seamText: TextLabel
local seamScale: UIScale
local topBar: Frame
local bottomBar: Frame
local bug: Frame
local bugDot: Frame
local lowerThird: Frame
local lowerTitle: TextLabel
local lowerSub: TextLabel
local progress: Frame
local skipHint: TextLabel
local shades: { UIGradient } = {}
local lowerAccent: Frame
local bugStroke: UIStroke

-- Lightning: a pool of jagged bolts (each a chain of thin rotated frames: a white core over a
-- wide electric-blue glow), sparks that burst off the seam, and two tinted copies of the seam
-- word that shake apart from it (an RGB split). Re-struck every few hundredths of a second.
local VOLT = Color3.fromRGB(110, 190, 255)
local VOLT_DEEP = Color3.fromRGB(12, 40, 110)
local BOLTS, BOLT_SEGS, SPARKS = 16, 12, 40
local CYAN = Color3.fromRGB(60, 230, 255)
local MAGENTA = Color3.fromRGB(255, 70, 200)
local VIOLET = Color3.fromRGB(170, 120, 255)
local TINTS = { VOLT, CYAN, MAGENTA, VIOLET }
local boltTint: { Color3 } = {}
-- An electric glow round the screen edges that pulses and flares with the lightning.
local edges: { Frame } = {}
local jolt = Vector2.zero -- screen shake applied to the wipe panels
local boltCore: { { Frame } } = {}
local boltGlow: { { Frame } } = {}
local boltPoints: { { Vector2 } } = {}
local boltRoll = -1
local sparks: { Frame } = {}
local sparkDir: { Vector2 } = {}
local splitA: TextLabel
local splitB: TextLabel
local splitScales: { UIScale } = {}
local textShine: UIGradient
local crackleUntil = 0
local nextCrackle = 0
local rng = Random.new()

-- The game's display face (Ui.SportItalic): the clock, the score bug and the menus use it.
local SPORT = Font.fromName("Sarpanch", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local SEAM_ANGLE = -14 -- degrees: the slash runs up to the right, like a broadcast wipe
local INK = Color3.fromRGB(20, 22, 32)
local WHITE = Color3.fromRGB(255, 255, 255)

local function frame(parent: Instance, name: string, color: Color3): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function label(parent: Instance, name: string, text: string, font: Enum.Font, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = font
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	l.Parent = parent
	return l
end

local function build(playerGui: Instance)
	gui = Instance.new("ScreenGui")
	gui.Name = "GoalReplay"
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
	gui.ClipToDeviceSafeArea = false
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 90
	gui.Enabled = false
	gui:SetAttribute("SkipAutoScale", true)
	gui.Parent = playerGui

	-- Letterbox, replay bug, lower third and progress line (only while the replay draws).
	topBar = frame(gui, "TopBar", Color3.new(0, 0, 0))
	topBar.AnchorPoint = Vector2.new(0, 0)
	topBar.Size = UDim2.fromScale(1, 0)
	bottomBar = frame(gui, "BottomBar", Color3.new(0, 0, 0))
	bottomBar.AnchorPoint = Vector2.new(0, 1)
	bottomBar.Position = UDim2.fromScale(0, 1)
	bottomBar.Size = UDim2.fromScale(1, 0)

	bug = frame(gui, "ReplayBug", INK)
	bug.AnchorPoint = Vector2.new(0, 0.5)
	bug.Position = UDim2.new(0, 28, 0.045, 0)
	bug.Size = UDim2.fromOffset(170, 40)
	bug.Visible = false
	local bugCorner = Instance.new("UICorner")
	bugCorner.CornerRadius = UDim.new(0, 8)
	bugCorner.Parent = bug
	bugStroke = Instance.new("UIStroke")
	bugStroke.Color = WHITE
	bugStroke.Thickness = 2
	bugStroke.Parent = bug
	bugDot = frame(bug, "Dot", Color3.fromRGB(235, 48, 56))
	bugDot.AnchorPoint = Vector2.new(0, 0.5)
	bugDot.Position = UDim2.new(0, 12, 0.5, 0)
	bugDot.Size = UDim2.fromOffset(14, 14)
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = bugDot
	local bugText = label(bug, "Text", "REPLAY", Enum.Font.GothamBlack, WHITE)
	bugText.Position = UDim2.new(0, 34, 0.18, 0)
	bugText.Size = UDim2.new(1, -44, 0.64, 0)
	bugText.TextXAlignment = Enum.TextXAlignment.Left

	lowerThird = frame(gui, "LowerThird", INK)
	lowerThird.AnchorPoint = Vector2.new(0, 1)
	lowerThird.Position = UDim2.new(0, 28, 1, -24)
	lowerThird.Size = UDim2.fromOffset(460, 70)
	lowerThird.Visible = false
	local ltCorner = Instance.new("UICorner")
	ltCorner.CornerRadius = UDim.new(0, 8)
	ltCorner.Parent = lowerThird
	local accent = frame(lowerThird, "Accent", WHITE)
	lowerAccent = accent
	accent.Size = UDim2.new(0, 10, 1, 0)
	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(0, 8)
	accentCorner.Parent = accent
	lowerTitle = label(lowerThird, "Title", "", Enum.Font.GothamBlack, WHITE)
	lowerTitle.Position = UDim2.new(0, 24, 0, 8)
	lowerTitle.Size = UDim2.new(1, -36, 0, 32)
	lowerTitle.TextXAlignment = Enum.TextXAlignment.Left
	lowerSub = label(lowerThird, "Sub", "", Enum.Font.GothamBold, Color3.fromRGB(205, 212, 228))
	lowerSub.Position = UDim2.new(0, 24, 0, 42)
	lowerSub.Size = UDim2.new(1, -36, 0, 20)
	lowerSub.TextXAlignment = Enum.TextXAlignment.Left

	progress = frame(gui, "Progress", WHITE)
	progress.AnchorPoint = Vector2.new(0, 1)
	progress.Position = UDim2.fromScale(0, 1)
	progress.Size = UDim2.new(0, 0, 0, 4)
	progress.Visible = false

	skipHint = label(gui, "SkipHint", "LEFT CLICK TO VOTE SKIP", Enum.Font.GothamBold, Color3.fromRGB(220, 226, 238))
	skipHint.AnchorPoint = Vector2.new(1, 0.5)
	skipHint.Position = UDim2.new(1, -28, 0.045, 0)
	skipHint.Size = UDim2.fromOffset(340, 18)
	skipHint.TextXAlignment = Enum.TextXAlignment.Right
	skipHint.Visible = false

	-- Edge glow: four gradient strips, solid at the screen edge and clear inward.
	for i, spec in {
		{ Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.16), 90 },
		{ Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromScale(1, 0.16), -90 },
		{ Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(0.12, 1), 0 },
		{ Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.fromScale(0.12, 1), 180 },
	} do
		local e = frame(gui, "EdgeGlow", VOLT)
		e.AnchorPoint, e.Position, e.Size = spec[1], spec[2], spec[3]
		e.BackgroundTransparency = 1
		e.ZIndex = 4
		local g = Instance.new("UIGradient")
		g.Rotation = spec[4]
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.35, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = e
		edges[i] = e
	end

	-- The wipe: two huge rotated panels that meet along the slash. They are squares far bigger
	-- than the screen, so their rotated corners never show; each one's edge is the seam.
	local function panel(name: string): (Frame, Frame)
		local p = frame(gui, name, Color3.new(1, 1, 1))
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.Rotation = SEAM_ANGLE
		p.Visible = false
		p.ZIndex = 5
		local gradient = Instance.new("UIGradient")
		gradient.Name = "Shade"
		gradient.Rotation = 90
		gradient.Parent = p
		table.insert(shades, gradient)
		local stripe = frame(p, "Stripe", WHITE)
		stripe.ZIndex = 6
		return p, stripe
	end
	panelA, stripeA = panel("PanelA")
	panelB, stripeB = panel("PanelB")
	-- A dark accent line inside each white stripe.
	for _, s in { stripeA, stripeB } do
		local line = frame(s, "Line", INK)
		line.AnchorPoint = Vector2.new(0, 0.5)
		line.Position = UDim2.fromScale(0, 0.5)
		line.Size = UDim2.new(1, 0, 0.28, 0)
		line.ZIndex = 7
	end

	slash = frame(gui, "Slash", WHITE)
	slash.AnchorPoint = Vector2.new(0.5, 0.5)
	slash.Rotation = SEAM_ANGLE
	slash.ZIndex = 9
	slash.Visible = false
	local glow = Instance.new("UIGradient")
	glow.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0),
		NumberSequenceKeypoint.new(0.85, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	glow.Parent = slash

	-- Lightning bolts sit over the panels and under the word.
	for b = 1, BOLTS do
		boltCore[b], boltGlow[b], boltPoints[b] = {}, {}, {}
		for k = 1, BOLT_SEGS do
			local g = frame(gui, "BoltGlow", VOLT)
			g.AnchorPoint = Vector2.new(0.5, 0.5)
			g.ZIndex = 8
			g.Visible = false
			local c = frame(gui, "Bolt", WHITE)
			c.AnchorPoint = Vector2.new(0.5, 0.5)
			c.ZIndex = 9
			c.Visible = false
			-- Round ends, so thick segments join into one smooth bolt instead of a row of bricks.
			for _, part in { g, c } do
				local round = Instance.new("UICorner")
				round.CornerRadius = UDim.new(0.5, 0)
				round.Parent = part
			end
			boltGlow[b][k], boltCore[b][k] = g, c
		end
	end
	-- The RGB split: a cyan and a magenta copy of the word, behind it.
	local function splitCopy(name: string, color: Color3): TextLabel
		local l = label(gui, name, "REPLAY", Enum.Font.GothamBlack, color)
		l.FontFace = SPORT
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromScale(0.5, 0.5)
		l.Size = UDim2.fromScale(0.5, 0.13)
		l.Rotation = SEAM_ANGLE
		l.ZIndex = 10
		l.Visible = false
		local sc = Instance.new("UIScale")
		sc.Parent = l
		table.insert(splitScales, sc)
		return l
	end
	splitA = splitCopy("SplitCyan", Color3.fromRGB(60, 230, 255))
	splitB = splitCopy("SplitMagenta", Color3.fromRGB(255, 70, 200))

	seamText = label(gui, "SeamText", "REPLAY", Enum.Font.GothamBlack, WHITE)
	seamText.FontFace = SPORT
	seamText.AnchorPoint = Vector2.new(0.5, 0.5)
	seamText.Position = UDim2.fromScale(0.5, 0.5)
	seamText.Size = UDim2.fromScale(0.5, 0.13)
	seamText.Rotation = SEAM_ANGLE
	seamText.ZIndex = 11
	seamText.Visible = false
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = VOLT_DEEP
	textStroke.Thickness = 5
	textStroke.Parent = seamText
	seamScale = Instance.new("UIScale")
	seamScale.Parent = seamText
	-- A bright electric band sweeps across the word as it lands.
	textShine = Instance.new("UIGradient")
	textShine.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.42, WHITE),
		ColorSequenceKeypoint.new(0.5, VOLT),
		ColorSequenceKeypoint.new(0.58, WHITE),
		ColorSequenceKeypoint.new(1, WHITE),
	})
	textShine.Rotation = 20
	textShine.Parent = seamText

	for i = 1, SPARKS do
		local p = frame(gui, "Spark", WHITE)
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.ZIndex = 12
		p.Visible = false
		sparks[i] = p
		sparkDir[i] = Vector2.new(1, 0)
	end

	flash = frame(gui, "Flash", WHITE)
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundTransparency = 1
	flash.ZIndex = 20
end

-- Positions the wipe at progress `closeA` / `closeB` (0 = off screen, 1 = closed on the seam).
-- `fromSides` true slides the panels in along the seam (from the left and the right); false
-- moves them apart across it (the split).
-- A jagged path between two screen points for bolt b: the middle wanders most, the ends are pinned.
local function rollBolt(b: number, from: Vector2, to: Vector2, jag: number)
	local pts = boltPoints[b]
	local d = to - from
	local n = if d.Magnitude > 1e-3 then Vector2.new(-d.Y, d.X).Unit else Vector2.new(0, 1)
	pts[1] = from
	for k = 1, BOLT_SEGS - 1 do
		local u = k / BOLT_SEGS
		pts[k + 1] = from + d * u + n * (rng:NextNumber(-1, 1) * jag * math.sin(u * math.pi))
	end
	pts[BOLT_SEGS + 1] = to
end

-- Draws bolt b (fade 0 = solid, 1 = gone) with a core this many pixels wide.
local function showBolt(b: number, fade: number, width: number)
	local pts = boltPoints[b]
	local on = fade < 1 and pts[BOLT_SEGS + 1] ~= nil
	for k = 1, BOLT_SEGS do
		local c, g = boltCore[b][k], boltGlow[b][k]
		c.Visible, g.Visible = on, on
		if on then
			local p, q = pts[k], pts[k + 1]
			local mid, seg = (p + q) / 2, q - p
			-- Thicker toward the middle of the bolt, tapering at the tip.
			local w = width * (0.6 + 0.4 * math.sin((k - 0.5) / BOLT_SEGS * math.pi))
			local len = seg.Magnitude + w
			local rot = math.deg(math.atan2(seg.Y, seg.X))
			c.Position, g.Position = UDim2.fromOffset(mid.X, mid.Y), UDim2.fromOffset(mid.X, mid.Y)
			c.Rotation, g.Rotation = rot, rot
			c.Size = UDim2.fromOffset(len, w)
			g.Size = UDim2.fromOffset(len + w * 1.6, w * 2.8)
			c.BackgroundTransparency = fade
			g.BackgroundColor3 = boltTint[b] or VOLT
			g.BackgroundTransparency = 0.3 + fade * 0.7
		end
	end
end

local function hideBolts()
	for b = 1, BOLTS do
		showBolt(b, 1, 1)
	end
end

-- Bolt b forks off a random point of bolt `parent`, this long, at an angle to it.
local function rollBranch(b: number, parent: number, length: number, jag: number)
	local pts = boltPoints[parent]
	if pts[BOLT_SEGS + 1] == nil then
		boltPoints[b][BOLT_SEGS + 1] = nil
		return
	end
	local k = rng:NextInteger(3, BOLT_SEGS - 1)
	local d = pts[k + 1] - pts[k]
	local ang = math.atan2(d.Y, d.X) + (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(0.45, 1.1)
	rollBolt(b, pts[k], pts[k] + Vector2.new(math.cos(ang), math.sin(ang)) * length, jag)
end

local function setEdges(intensity: number, color: Color3)
	for _, e in edges do
		e.BackgroundColor3 = color
		e.BackgroundTransparency = 1 - math.clamp(intensity, 0, 1) * 0.8
	end
end

local function retint()
	for b = 1, BOLTS do
		boltTint[b] = TINTS[rng:NextInteger(1, #TINTS)]
	end
end

local function hideEffects()
	hideBolts()
	for _, p in sparks do
		p.Visible = false
	end
	splitA.Visible = false
	splitB.Visible = false
	seamText.Position = UDim2.fromScale(0.5, 0.5)
	bugStroke.Color = WHITE
	crackleUntil = 0
	setEdges(0, VOLT)
	jolt = Vector2.zero
end

local function placePanels(closeA: number, closeB: number, fromSides: boolean)
	local size = gui.AbsoluteSize
	local diag = math.sqrt(size.X * size.X + size.Y * size.Y)
	local L = diag * 2.2
	local a = math.rad(SEAM_ANGLE)
	local tx, ty = math.cos(a), math.sin(a) -- along the seam
	local nx, ny = math.sin(a), -math.cos(a) -- across it, toward panel A's side
	local cx, cy = size.X / 2, size.Y / 2
	local function put(p: Frame, side: number, close: number)
		local away = (1 - close)
		local ox, oy
		if fromSides then
			-- A comes in from the left, B from the right.
			ox, oy = -side * tx * diag * 1.3 * away, -side * ty * diag * 1.3 * away
		else
			ox, oy = side * nx * diag * 0.9 * away, side * ny * diag * 0.9 * away
		end
		p.Size = UDim2.fromOffset(L, L)
		p.Position = UDim2.fromOffset(cx + side * nx * L / 2 + ox + jolt.X, cy + side * ny * L / 2 + oy + jolt.Y)
		p.Visible = close > 0.001
	end
	put(panelA, 1, closeA)
	put(panelB, -1, closeB)
	-- Stripes along each panel's seam edge (A's bottom, B's top).
	local stripeH = math.max(10, size.Y * 0.022)
	stripeA.AnchorPoint = Vector2.new(0, 1)
	stripeA.Position = UDim2.fromScale(0, 1)
	stripeA.Size = UDim2.new(1, 0, 0, stripeH)
	stripeB.AnchorPoint = Vector2.new(0, 0)
	stripeB.Position = UDim2.fromScale(0, 0)
	stripeB.Size = UDim2.new(1, 0, 0, stripeH)
end

local function ease(u: number, style: Enum.EasingStyle, dir: Enum.EasingDirection): number
	return TweenService:GetValue(math.clamp(u, 0, 1), style, dir)
end

-- Draws the wipe at `t` seconds into it. `closing` is the half that covers the screen; the
-- caller swaps what is underneath once it is covered (at WIPE_COVER).
local WIPE_COVER = 0.36
local WIPE_TOTAL = 0.74
local STROBES = { 0.12, 0.2, 0.28, 0.46, 0.54 }
local function drawWipe(t: number)
	local size = gui.AbsoluteSize
	local diag = math.sqrt(size.X * size.X + size.Y * size.Y)
	-- The panels slam shut with a jolt: the screen shakes hardest as they meet.
	local quake = math.max(0, 1 - math.abs(t - 0.3) / 0.26)
	jolt = Vector2.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * 18 * quake
	-- 0.00 - 0.12: the slash streaks across the screen along the seam.
	local s = ease(t / 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	slash.Visible = t < 0.5
	-- A frame rotates about its centre, so the streak is placed by its centre: it starts off
	-- screen on the seam and grows along it.
	local len = diag * 1.2 * s
	slash.Size = UDim2.fromOffset(len, math.max(4, size.Y * 0.008))
	local a = math.rad(SEAM_ANGLE)
	local along = len / 2 - diag * 0.6
	slash.Position = UDim2.fromOffset(size.X / 2 + math.cos(a) * along, size.Y / 2 + math.sin(a) * along)
	slash.BackgroundTransparency = if t < 0.3 then 0 else math.clamp((t - 0.3) / 0.2, 0, 1)
	-- 0.06 - 0.30: the panels slam in from either side, A a beat ahead of B.
	if t < WIPE_COVER + 0.08 then
		local ca = ease((t - 0.06) / 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		local cb = ease((t - 0.1) / 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		placePanels(ca, cb, true)
	else
		-- 0.44 - 0.74: they split apart across the seam onto what is now underneath.
		local u = ease((t - (WIPE_COVER + 0.08)) / 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		placePanels(1 - u, 1 - u, false)
	end
	-- Lightning crackles along the seam while it is shut: two bolts run out from the middle along
	-- it and the rest fork off it, all re-struck every 0.045 s, flickering, then fading out.
	local centre = size / 2
	local alongV = Vector2.new(math.cos(a), math.sin(a))
	local acrossV = Vector2.new(-alongV.Y, alongV.X)
	-- Lightning storm: two bolts run out along the seam from the middle, six strike down onto it
	-- from the top and bottom of the screen, and the rest fork off them. All are re-struck every
	-- 0.04 s in shifting electric colours, flickering, then fading out after the cover.
	if t > 0.05 and t < WIPE_COVER + 0.3 then
		local roll = math.floor(t / 0.06)
		if roll ~= boltRoll then
			boltRoll = roll
			retint()
			local reach = diag * 0.6
			rollBolt(1, centre, centre + alongV * reach + acrossV * rng:NextNumber(-40, 40), 70)
			rollBolt(2, centre, centre - alongV * reach + acrossV * rng:NextNumber(-40, 40), 70)
			for b = 3, 8 do
				local hit = centre + alongV * (rng:NextNumber(-1, 1) * reach * 0.75)
				local fromY = if b % 2 == 0 then -20 else size.Y + 20
				local from = Vector2.new(hit.X + rng:NextNumber(-size.X * 0.25, size.X * 0.25), fromY)
				rollBolt(b, from, hit, 90)
			end
			for b = 9, BOLTS do
				rollBranch(b, rng:NextInteger(1, 8), rng:NextNumber(60, size.Y * 0.22), 22)
			end
			for _, s in { stripeA, stripeB } do
				s.BackgroundColor3 = if rng:NextNumber() < 0.5 then WHITE else boltTint[1]
			end
		end
		local fade = math.clamp((t - (WIPE_COVER + 0.14)) / 0.16, 0, 1)
		for b = 1, BOLTS do
			-- Thick, heavy bolts sized to the screen (about 18 / 12 / 6 px at 1080p), flickering less.
			local flicker = if b > 2 and rng:NextNumber() < 0.12 then 1 else 0
			local px = math.max(0.6, size.Y / 1080)
			showBolt(b, math.min(1, fade + flicker), px * (if b <= 2 then 18 elseif b <= 8 then 12 else 6))
		end
		setEdges((1 - fade) * (0.75 + 0.25 * rng:NextNumber()), boltTint[1] or VOLT)
	else
		hideBolts()
		setEdges(0, VOLT)
		stripeA.BackgroundColor3, stripeB.BackgroundColor3 = WHITE, WHITE
	end
	-- Sparks burst off the seam as the word lands.
	if t < 0.16 then
		for i = 1, SPARKS do
			local ang = a + (if i % 2 == 0 then math.pi / 2 else -math.pi / 2) + rng:NextNumber(-1.2, 1.2)
			sparkDir[i] = Vector2.new(math.cos(ang), math.sin(ang)) * rng:NextNumber(0.6, 1.3)
		end
	end
	local sparkAge = t - 0.18
	for i, p in sparks do
		local life = 0.55
		local on = sparkAge > 0 and sparkAge < life
		p.Visible = on
		if on then
			local dir = sparkDir[i]
			local pos = centre + alongV * ((i - SPARKS / 2) * size.X * 0.018) + dir * (size.Y * 1.1 * sparkAge)
			p.Position = UDim2.fromOffset(pos.X, pos.Y)
			p.Rotation = math.deg(math.atan2(dir.Y, dir.X))
			p.Size = UDim2.fromOffset(26 * (1 - sparkAge / life) + 4, 3)
			p.BackgroundColor3 = TINTS[i % #TINTS + 1]:Lerp(WHITE, if i % 2 == 0 then 0.6 else 0)
			p.BackgroundTransparency = sparkAge / life
		end
	end
	-- The word on the seam punches in while the panels are shut, shaking with an RGB split and a
	-- bright band sweeping across it.
	local shown = t > 0.16 and t < WIPE_COVER + 0.2
	seamText.Visible = shown
	splitA.Visible = shown
	splitB.Visible = shown
	if shown then
		local k = ease((t - 0.16) / 0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		seamScale.Scale = 1.5 - 0.5 * k
		seamText.TextTransparency = 1 - math.clamp((t - 0.16) / 0.06, 0, 1)
		local shake = math.max(0, 1 - (t - 0.16) / 0.3)
		local jx, jy = rng:NextNumber(-1, 1) * 6 * shake, rng:NextNumber(-1, 1) * 4 * shake
		local spread = 4 + 6 * shake
		seamText.Position = UDim2.new(0.5, jx * 0.4, 0.5, jy * 0.4)
		splitA.Position = UDim2.new(0.5, -spread + jx, 0.5, jy)
		splitB.Position = UDim2.new(0.5, spread - jx, 0.5, -jy)
		for _, l in { splitA, splitB } do
			l.Text = seamText.Text
			l.TextTransparency = 0.35 + 0.65 * seamText.TextTransparency
		end
		for _, sc in splitScales do
			sc.Scale = seamScale.Scale
		end
		textShine.Offset = Vector2.new(-1 + 2 * math.clamp((t - 0.2) / 0.3, 0, 1), 0)
	end
	-- A lightning strobe: coloured strikes in a stutter round the white pop at the cover.
	local f = math.abs(t - WIPE_COVER)
	local beat, gap = 0, 1
	for i, at in STROBES do
		if math.abs(t - at) < gap then
			beat, gap = i, math.abs(t - at)
		end
	end
	if f < 0.05 then
		flash.BackgroundColor3 = WHITE
		flash.BackgroundTransparency = 0.3 + f * 10
	elseif gap < 0.025 then
		flash.BackgroundColor3 = TINTS[(beat - 1) % #TINTS + 1]
		flash.BackgroundTransparency = 0.5 + gap * 14
	else
		flash.BackgroundTransparency = 1
	end
end

-- While the replay plays there is no lightning (that is only on the REPLAY and LIVE wipes); the
-- border of the REPLAY bug just hums between white and electric blue.
local function drawPlayingFx(now: number)
	bugStroke.Color = WHITE:Lerp(VOLT, 0.5 + 0.5 * math.sin(now * 14))
end

local voted = false
local skipPending = false
local voteFn: (() -> ())? = nil
local function setVoteText(votes: number, need: number)
	if skipHint then
		skipHint.Text = if voted then `VOTED TO SKIP  {votes}/{need}` else `LEFT CLICK TO VOTE SKIP  {votes}/{need}`
		if not voted then
			skipHint.TextColor3 = Color3.fromRGB(220, 226, 238)
		end
	end
end

local function setDressing(on: boolean)
	local h = if on then 0.085 else 0
	topBar.Size = UDim2.fromScale(1, h)
	bottomBar.Size = UDim2.fromScale(1, h)
	bug.Visible = on
	lowerThird.Visible = on
	progress.Visible = on
	skipHint.Visible = on
end

local function colorPanels(color: Color3)
	-- Build 35: the fill carries the colour and the gradient only shades it. The fill used to be
	-- white with all the colour in the gradient, and where a gradient didn't draw on these huge
	-- rotated panels (seen live) half the screen went solid white.
	panelA.BackgroundColor3 = color
	panelB.BackgroundColor3 = color
	for _, shade in shades do
		shade.Color = ColorSequence.new(WHITE, Color3.fromRGB(150, 150, 160))
	end
	lowerAccent.BackgroundColor3 = color
end

-- Build 36: the broadcast shot looks down over the near (-Z) boards, so their glass filled the
-- bottom half of the picture (Glass renders frosted white at normal graphics quality; Studio's
-- quality 1 hid it). That glass is see-through for this player while the replay is up.
local hiddenGlass: { BasePart } = {}
local function hideNearGlass()
	table.clear(hiddenGlass)
	for _, rink in workspace:GetChildren() do
		if rink:IsA("Model") and string.sub(rink.Name, 1, 5) == "Rink_" then
			local boards = rink:FindFirstChild("Boards")
			if boards then
				for _, p in boards:GetDescendants() do
					if p:IsA("BasePart") and p.Material == Enum.Material.Glass and p.Position.Z < -HALF_WIDTH * 0.6 then
						p.LocalTransparencyModifier = 1
						table.insert(hiddenGlass, p)
					end
				end
			end
		end
	end
end

-- Hide / restore the rest of the UI (only what was on).
local function hideOthers()
	table.clear(hidden)
	hideNearGlass()
	local playerGui = gui.Parent
	if not playerGui then
		return
	end
	for _, g in playerGui:GetChildren() do
		if g:IsA("ScreenGui") and g ~= gui and g.Enabled then
			g.Enabled = false
			table.insert(hidden, g)
		end
	end
end

local function restoreOthers()
	for _, g in hidden do
		if g.Parent then
			g.Enabled = true
		end
	end
	table.clear(hidden)
	for _, p in hiddenGlass do
		p.LocalTransparencyModifier = 0
	end
	table.clear(hiddenGlass)
end

-- Buffer -----------------------------------------------------------------------------------

local function at(i: number): RecFrame
	return ring[(i - 1) % CAPACITY + 1]
end

-- Copies the frame you just saw into the buffer.
function Replay.record(now: number, states: { any }, px: number, py: number, pz: number, pvx: number, pvz: number)
	if frozen then
		return
	end
	if count > 0 and now - at(head).t < MIN_GAP then
		return
	end
	head = head % CAPACITY + 1
	count = math.min(CAPACITY, count + 1)
	local f = ring[head]
	f.t = now
	f.px, f.py, f.pz, f.pvx, f.pvz = px, py, pz, pvx, pvz
	for slot = 1, SLOTS do
		local src, dst = states[slot], f.s[slot]
		dst.visible = src.visible == true
		dst.x, dst.z, dst.vx, dst.vz = src.x, src.z, src.vx, src.vz
		dst.yaw, dst.radius = src.yaw, src.radius
		dst.charging, dst.active, dst.charge = src.charging == true, src.active == true, src.charge or 0
		dst.lifted, dst.lofting = src.lifted == true, src.lofting == true
		dst.sprinting, dst.stunned = src.sprinting == true, src.stunned == true
	end
end

-- Forget everything (a new match, leaving the match).
function Replay.clear()
	count = 0
	head = 0
	frozen = false
end

local function lerpAngle(a: number, b: number, u: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * u
end

-- Fills `out` and returns the puck at recorded time t.
local function sample(t: number): (number, number, number, number, number)
	-- Newest first: find the two frames around t.
	local newer: RecFrame? = nil
	local older: RecFrame? = nil
	for k = 0, count - 1 do
		local f = at(head - k)
		if f.t <= t then
			older = f
			break
		end
		newer = f
	end
	local a = older or newer
	local b = newer or older
	if not a or not b then
		return 0, -5, 0, 0, 0
	end
	local u = if b.t > a.t then math.clamp((t - a.t) / (b.t - a.t), 0, 1) else 0
	for slot = 1, SLOTS do
		local sa, sb, o = a.s[slot], b.s[slot], out[slot]
		local near = if u < 0.5 then sa else sb
		o.visible = sa.visible and sb.visible
		o.x = sa.x + (sb.x - sa.x) * u
		o.z = sa.z + (sb.z - sa.z) * u
		o.vx = sa.vx + (sb.vx - sa.vx) * u
		o.vz = sa.vz + (sb.vz - sa.vz) * u
		o.yaw = lerpAngle(sa.yaw, sb.yaw, u)
		o.radius = sa.radius + (sb.radius - sa.radius) * u
		o.charge = sa.charge + (sb.charge - sa.charge) * u
		o.charging, o.active, o.lifted, o.lofting = near.charging, near.active, near.lifted, near.lofting
		o.sprinting, o.stunned = near.sprinting, near.stunned
	end
	return a.px + (b.px - a.px) * u, a.py + (b.py - a.py) * u, a.pz + (b.pz - a.pz) * u, a.pvx + (b.pvx - a.pvx) * u, a.pvz + (b.pvz - a.pvz) * u
end

-- The recorded moment the puck crossed into the net (or the goal event, if it can't be found).
local function findGoalTime(fallback: number): number
	local crossed: number? = nil
	for k = count - 1, 0, -1 do
		local f = at(head - k)
		if math.abs(f.px) >= GOAL_X and math.abs(f.pz) <= HALF_MOUTH + 1 and f.py < 6 then
			crossed = f.t
			break
		end
	end
	return crossed or fallback
end

-- Timeline -----------------------------------------------------------------------------------

local function enter(name: string, now: number)
	phase = name
	phaseAt = now
end

local function finish()
	-- Every exit comes through here.
	if drawing then
		restoreOthers()
	end
	drawing = false
	setDressing(false)
	placePanels(0, 0, true)
	slash.Visible = false
	seamText.Visible = false
	hideEffects()
	flash.BackgroundTransparency = 1
	gui.Enabled = false
	frozen = false
	phase = "idle"
	info = nil
end

-- A goal was scored. goal: { goalId, color, title, sub, speedText }.
function Replay.goal(goal: any)
	local id = tonumber(goal.goalId)
	if id and seenGoals[id] then
		return
	end
	if id then
		seenGoals[id] = true
	end
	if phase ~= "idle" then
		finish()
	end
	if count < 30 then
		return -- not enough recorded to show anything
	end
	info = goal
	voted, skipPending = false, false
	setVoteText(0, tonumber(goal.skipNeed) or 1)
	netSide = if (tonumber(goal.x) or 0) >= 0 then 1 else -1
	enter("waiting", os.clock())
	watchdogAt = os.clock() + Replay.CELEBRATE + 12
end

-- The match moved on (face-off, final, leaving): drop the replay and give everything back.
function Replay.stop()
	if phase ~= "idle" then
		finish()
	end
end

function Replay.drawing(): boolean
	return drawing
end

function Replay.busy(): boolean
	return phase ~= "idle"
end

local function skip()
	if phase == "playing" then
		enter("wipeOut", os.clock())
	elseif phase == "waiting" or phase == "wipeIn" then
		skipPending = true -- the vote passed early: wipe straight back out once the replay is up
	end
end

-- Skipping is a vote: left click (or A / a tap) votes, and the server skips the replay for
-- everyone once enough players on the ice have voted.
function Replay.onVote(fn: () -> ())
	voteFn = fn
end

function Replay.votes(votes: number, need: number, skipNow: boolean)
	setVoteText(votes, need)
	if skipNow then
		skip()
	end
end

-- Recorded seconds per real second at a recorded time.
local function rateAt(t: number): number
	local cut = replayGoal - NET_CAM_LEAD
	if t < cut - 0.25 then
		return SIDE_RATE
	elseif t < cut then
		local u = (t - (cut - 0.25)) / 0.25
		return SIDE_RATE + (NET_RATE - SIDE_RATE) * u
	end
	return NET_RATE
end

-- How long the replay runs in real time (for the progress line).
local function realLength(): number
	local total, t, step = 0, replayStart, 1 / 120
	while t < replayEnd do
		t += rateAt(t) * step
		total += step
	end
	return total
end
local playLength = 1

local function update(dt: number)
	if phase == "idle" then
		return
	end
	local now = os.clock()
	if now > watchdogAt then
		finish()
		return
	end
	local age = now - phaseAt
	if phase == "waiting" then
		if not frozen and age >= KEEP_RECORDING then
			frozen = true
		end
		if age >= Replay.CELEBRATE then
			frozen = true
			local newest = at(head).t
			replayGoal = findGoalTime(newest - KEEP_RECORDING)
			local oldest = at(head - (count - 1)).t
			replayStart = math.max(oldest, replayGoal - BEFORE_GOAL)
			replayEnd = math.min(newest, replayGoal + AFTER_GOAL)
			if replayEnd - replayStart < 0.6 then
				finish()
				return
			end
			playLength = realLength()
			colorPanels(info.color or INK)
			lowerTitle.Text = info.title or "GOAL!"
			lowerSub.Text = info.sub or ""
			seamText.Text = "REPLAY"
			gui.Enabled = true
			enter("wipeIn", now)
		end
	elseif phase == "wipeIn" then
		drawWipe(age)
		if not drawing and age >= WIPE_COVER then
			drawing = true
			hideOthers()
			setDressing(true)
			cursor = replayStart
			camX = 0
			lastShot = 0
		end
		if age >= WIPE_TOTAL then
			placePanels(0, 0, true)
			enter("playing", now)
			if skipPending then
				skipPending = false
				enter("wipeOut", now)
			end
		end
	elseif phase == "playing" then
		cursor += rateAt(cursor) * dt
		progress.Size = UDim2.new(math.clamp((cursor - replayStart) / math.max(0.01, replayEnd - replayStart), 0, 1), 0, 0, 4)
		bugDot.BackgroundTransparency = if (now * 2) % 1 < 0.5 then 0 else 0.7
		drawPlayingFx(now)
		if cursor >= replayEnd then
			cursor = replayEnd
			enter("wipeOut", now)
		end
	elseif phase == "wipeOut" then
		seamText.Text = info and info.outText or "LIVE"
		drawWipe(age)
		if drawing and age >= WIPE_COVER then
			drawing = false
			restoreOthers()
			setDressing(false)
		end
		if age >= WIPE_TOTAL then
			finish()
		end
	end
end

-- The replay's picture for this frame: skater states, puck, and the camera.
function Replay.frame(): ({ SkaterFrame }, number, number, number, number, number, CFrame, number)
	local px, py, pz, pvx, pvz = sample(cursor)
	local puck = Vector3.new(px, math.max(0.3, py), pz)
	local fov: number
	local cf: CFrame
	if cursor < replayGoal - NET_CAM_LEAD then
		-- Broadcast shot: high in the stands on the long side, tracking the puck down the ice.
		if lastShot ~= 1 then
			lastShot = 1
			camX = px
		end
		camX += (px - camX) * 0.08
		local eye = Vector3.new(camX * 0.85, 26, -(HALF_WIDTH + 34))
		local u = math.clamp((cursor - replayStart) / math.max(0.01, replayGoal - replayStart), 0, 1)
		fov = 40 - u * 6 -- a slow push in toward the finish
		cf = CFrame.lookAt(eye, Vector3.new(px * 0.92 + camX * 0.08, 1, pz * 0.6))
	else
		-- Reverse angle: high off the back corner of the net that was scored on, on the shooter's
		-- side, looking back up the ice past the frame (straight behind it, the top bar of the
		-- net would cut across the middle of the picture).
		if lastShot ~= 2 then
			lastShot = 2
			netZ = if pz >= 0 then 1 else -1
			flash.BackgroundTransparency = 0.2
			TweenService:Create(flash, TweenInfo.new(0.18), { BackgroundTransparency = 1 }):Play()
		end
		local eye = Vector3.new(netSide * (GOAL_X + 7), 9, netZ * 16)
		fov = 52
		cf = CFrame.lookAt(eye, puck:Lerp(Vector3.new(netSide * (GOAL_X - 6), 1, 0), 0.5))
	end
	return out, px, py, pz, pvx, pvz, cf, fov
end

function Replay.init(playerGui: Instance)
	build(playerGui)
	RunService.RenderStepped:Connect(update)
	UserInputService.InputBegan:Connect(function(input: InputObject, _processed: boolean)
		if phase ~= "playing" or voted then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch or (t == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.ButtonA) then
			voted = true
			skipHint.TextColor3 = Color3.fromRGB(255, 214, 90)
			if voteFn then
				voteFn()
			end
		end
	end)
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		Replay.stop()
	end)
end

return Replay
