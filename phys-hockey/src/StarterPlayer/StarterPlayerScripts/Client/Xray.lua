--!strict
-- See-through puck and stick: exactly the part of them that something hides is drawn in yellow
-- on top, and nothing else.
--
-- How it draws: a full-screen ViewportFrame whose camera copies the game camera every frame holds
-- yellow pieces. A ViewportFrame draws over the 3D world, so a piece shows through anything, in
-- the right place and in perspective. It is plain GUI rendering, so it works the same in Studio
-- and the live player (Highlight instances drew in Studio but not in the Roblox Player).
--
-- What is hidden is worked out along the line to the camera against every skater (a drum for the
-- body and a ball for the head, solved exactly), the boards and the nets. The stick is cut at
-- the exact points where it goes behind something, so only the blocked stretch is yellow. The
-- puck is cut the same way in thin strips, so a puck half behind a skater is half yellow.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("GameConfig"))
local Sim = require(Shared:WaitForChild("Sim"))
local Looks = require(Shared:WaitForChild("Looks"))

local Xray = {}

local YELLOW = Color3.fromRGB(255, 214, 40)
local PUCK = Config.Puck
local ARENA = Config.Arena
local GOAL = Config.Goal
local GLOW = 0.15 -- how see-through the yellow pieces are (0 = solid)
local GROW = 0.04 -- the pieces are this much fatter than the real thing, so the edge reads as a glow
local SHAFT_SHOWN = 0.7 -- share of the shaft (from the blade up) that can glow; the top stays by the helmet
local SAMPLE = 0.1 -- studs between test points along the stick and across the puck
local REFINE = 8 -- halvings that place each cut (SAMPLE / 256: well under a pixel)
local PUCK_STRIPS = 20 -- a part-hidden puck is drawn as this many strips, each cut where it goes behind
local POOL_MAX = 80

-- Skater occluder: a drum for the body and a ball for the head and helmet.
-- (Sized for the in-match skater, which is drawn at Looks.PLAY_SCALE.)
local K = Looks.PLAY_SCALE
local BODY_R = 1.95 * K
local BODY_R2 = BODY_R * BODY_R
local BODY_TOP = 3.9 * K
local HEAD_Y = (Looks.HEAD_Y + 0.35) * K
local HEAD_R = 2.0 * K -- the helmet shell, a little wider than the head
local HEAD_R2 = HEAD_R * HEAD_R
local BOARD_TOP = ARENA.BoardHeight + 0.6 -- the boards with their cap and rail
local NET_TOP = math.max(GOAL.CrossbarHeight, GOAL.BackHeight)

local gui: ScreenGui? = nil
local view: ViewportFrame
local viewCamera: Camera
local pool: { Part } = {}
local used = 0
local puckCopy: Part
local extraCopies: { Part } = {} -- Build 40: one round copy per extra practice puck
local puckAlways = false
local stickTint = YELLOW
local puckTint = YELLOW

-- Settings: glow colours, and whether the whole puck is lit all the time.
function Xray.setColors(stick: Color3, puck: Color3)
	stickTint, puckTint = stick, puck
	if puckCopy then
		puckCopy.Color = puck
	end
end

function Xray.setPuckAlways(on: boolean)
	puckAlways = on
end

local function copyPart(name: string, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Parent = view
	return p
end

-- The whole-puck glow: a round copy, a little fatter than the puck.
local function newPuckCopy(name: string): Part
	local p = copyPart(name, puckTint)
	p.Shape = Enum.PartType.Cylinder
	local d = PUCK.Radius * 2 + GROW * 2
	p.Size = Vector3.new(PUCK.Thickness + GROW * 2, d, d)
	return p
end

-- `_parent` is kept for the old call (Xray.init(workspace)); everything lives in the PlayerGui.
function Xray.init(_parent: Instance?)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "Xray"
	screen.IgnoreGuiInset = true -- the frame must cover the exact 3D view, under the top bar too
	screen.ScreenInsets = Enum.ScreenInsets.None
	screen.ResetOnSpawn = false
	screen.DisplayOrder = -10 -- under every HUD and menu
	screen:SetAttribute("SkipAutoScale", true)
	gui = screen

	view = Instance.new("ViewportFrame")
	view.Name = "XrayView"
	view.Size = UDim2.fromScale(1, 1)
	view.BackgroundTransparency = 1
	view.ImageTransparency = GLOW
	-- Flat colour: full ambient light and no sun, so each piece is exactly its own colour.
	view.Ambient = Color3.new(1, 1, 1)
	view.LightColor = Color3.new(0, 0, 0)
	view.Parent = screen
	viewCamera = Instance.new("Camera")
	viewCamera.Name = "XrayCamera"
	viewCamera.Parent = view
	view.CurrentCamera = viewCamera

	table.clear(pool)
	table.clear(extraCopies)
	used = 0
	puckCopy = newPuckCopy("Puck")
	screen.Parent = playerGui
end

-- True while the gui is still in the PlayerGui (anything that clears it gets a fresh one).
local function intact(): boolean
	local g = gui
	return g ~= nil and g.Parent ~= nil and view.Parent == g and puckCopy.Parent == view
end

type Skater = { x: number, z: number }

-- True when the straight line from `target` to the camera passes through a skater, the boards
-- or a net. A skater whose body the point is inside (the top of your own stick, at your chest)
-- is left out: it can't tell what is in front of what there.
local function hidden(camera: Vector3, target: Vector3, skaters: { Skater }): boolean
	local ray = camera - target
	local length = ray.Magnitude
	if length < 1e-3 then
		return false
	end
	local dx, dy, dz = ray.X / length, ray.Y / length, ray.Z / length
	if dy <= 1e-3 then
		return false -- the game camera always looks down from above
	end
	local flat = math.sqrt(dx * dx + dz * dz)

	-- Skaters, solved exactly: the ray against an upright drum, then against a ball.
	local a = dx * dx + dz * dz
	for _, s in skaters do
		local ox, oz = target.X - s.x, target.Z - s.z
		local c = ox * ox + oz * oz - BODY_R2
		if c >= 0 then
			local tTop = math.min(length, (BODY_TOP - target.Y) / dy)
			if tTop > 0 and a > 1e-9 then
				local b = 2 * (ox * dx + oz * dz)
				local disc = b * b - 4 * a * c
				if disc > 0 then
					local r = math.sqrt(disc)
					local t0, t1 = (-b - r) / (2 * a), (-b + r) / (2 * a)
					if t1 > 0 and t0 < tTop then
						return true
					end
				end
			end
			local hy = target.Y - HEAD_Y
			local b2 = ox * dx + hy * dy + oz * dz
			local disc2 = b2 * b2 - (ox * ox + hy * hy + oz * oz - HEAD_R2)
			if disc2 > 0 then
				local r = math.sqrt(disc2)
				if -b2 + r > 0 and -b2 - r < length then
					return true
				end
			end
		end
	end

	-- The boards: only near them (everything within reach of the line below the cap is ice).
	local tBoard = math.min(length, (BOARD_TOP - target.Y) / dy)
	if tBoard > 0 and not Sim.insideRink(target.X, target.Z, tBoard * flat + 0.05) then
		local t = 0
		while true do
			local px, pz = target.X + dx * t, target.Z + dz * t
			if not Sim.insideRink(px, pz, 0) then
				return true
			end
			if t >= tBoard then
				break
			end
			t = math.min(tBoard, t + SAMPLE)
		end
	end

	-- The nets: only near one (inside the netting, under its top).
	local tNet = math.min(length, (NET_TOP - target.Y) / dy)
	if tNet > 0.3 then
		local reach = tNet * flat + 0.5
		local depth0 = Sim.netFrame(target.X, target.Z)
		if depth0 > -reach and depth0 < GOAL.Depth + reach then
			local t = 0.3
			while t <= tNet do
				local p = target + Vector3.new(dx, dy, dz) * t
				local depth, across = Sim.netFrame(p.X, p.Z)
				if Sim.insideNet(depth, across) and p.Y < Sim.netRoofAt(depth) then
					return true
				end
				t += SAMPLE
			end
		end
	end
	return false
end

-- The hidden stretches of the straight line a -> b, as fractions along it: fills `out` with
-- start, finish pairs and returns how many. Each cut is placed by halving between two tests.
local runs: { number } = {}
local function hiddenRuns(a: Vector3, b: Vector3, eye: Vector3, skaters: { Skater }): number
	local n = math.clamp(math.ceil((b - a).Magnitude / SAMPLE), 2, 60)
	local prevU, prevH = 0, hidden(eye, a, skaters)
	local start: number? = if prevH then 0 else nil
	local count = 0
	for i = 1, n do
		local u = i / n
		local h = hidden(eye, a:Lerp(b, u), skaters)
		if h ~= prevH then
			local lo, hi = prevU, u
			for _ = 1, REFINE do
				local mid = (lo + hi) / 2
				if hidden(eye, a:Lerp(b, mid), skaters) == prevH then
					lo = mid
				else
					hi = mid
				end
			end
			local edge = (lo + hi) / 2
			if h then
				start = edge
			elseif start then
				count += 1
				runs[2 * count - 1], runs[2 * count] = start, edge
				start = nil
			end
		end
		prevU, prevH = u, h
	end
	if start then
		count += 1
		runs[2 * count - 1], runs[2 * count] = start, 1
	end
	return count
end

-- Next free piece from the pool (nil once the pool is full).
local function take(color: Color3): Part?
	if used >= POOL_MAX then
		return nil
	end
	used += 1
	local p = pool[used]
	if not p then
		p = copyPart("Piece" .. used, color)
		pool[used] = p
	end
	if p.Color ~= color then
		p.Color = color
	end
	p.Transparency = 0
	return p
end

-- Draws the hidden stretches of one straight stick piece from a to b, with the piece's cross-
-- section `w` x `h`. `growA` / `growB` say whether that end is a real end of the stick (it gets
-- the glow margin) or a cut.
local function drawStretch(a: Vector3, b: Vector3, up: Vector3, w: number, h: number, eye: Vector3, skaters: { Skater }, growA: boolean, growB: boolean)
	local along = b - a
	local len = along.Magnitude
	if len < 1e-3 then
		return
	end
	local dir = along / len
	local count = hiddenRuns(a, b, eye, skaters)
	for i = 1, count do
		local u0, u1 = runs[2 * i - 1], runs[2 * i]
		local p0 = a + along * u0
		local p1 = a + along * u1
		if u0 <= 0 and growA then
			p0 -= dir * GROW
		end
		if u1 >= 1 and growB then
			p1 += dir * GROW
		end
		local piece = take(stickTint)
		if not piece then
			return
		end
		local mid = (p0 + p1) / 2
		piece.CFrame = CFrame.lookAt(mid, mid + dir, up)
		piece.Size = Vector3.new(w + GROW * 2, h + GROW * 2, math.max(0.02, (p1 - p0).Magnitude))
	end
end

-- The puck: nothing when it is all in view, the whole round copy when it is all hidden, and
-- otherwise strips cut where they go behind something.
local RIM = 8
local function drawPuck(puck: BasePart, eye: Vector3, skaters: { Skater }, puckCopy: Part)
	local cf = puck.CFrame
	local axis = cf.RightVector -- a cylinder part runs along its X
	if axis.Y < 0 then
		axis = -axis
	end
	local top = cf.Position + axis * (PUCK.Thickness / 2)
	local look = (cf.Position - eye).Unit
	local fwd = look - axis * look:Dot(axis)
	if fwd.Magnitude < 1e-3 then
		fwd = cf.UpVector
	end
	fwd = fwd.Unit
	local across = fwd:Cross(axis).Unit
	local R = PUCK.Radius

	if puckAlways then
		puckCopy.CFrame = cf
		puckCopy.Transparency = 0
		return
	end
	-- Quick look: the middle and points around the rim.
	local anyHidden, allHidden = false, true
	local h = hidden(eye, top, skaters)
	anyHidden, allHidden = h, h
	for i = 1, RIM do
		local ang = (i / RIM) * 2 * math.pi
		local p = top + (across * math.cos(ang) + fwd * math.sin(ang)) * (R * 0.95)
		local hh = hidden(eye, p, skaters)
		anyHidden = anyHidden or hh
		allHidden = allHidden and hh
	end
	if allHidden then
		puckCopy.CFrame = cf
		puckCopy.Transparency = 0
		return
	end
	puckCopy.Transparency = 1
	if not anyHidden then
		return
	end

	local RG = R + GROW
	local w = 2 * RG / PUCK_STRIPS
	local thick = PUCK.Thickness + GROW * 2
	for i = 1, PUCK_STRIPS do
		local x = -RG + (i - 0.5) * w
		local half = math.sqrt(math.max(0, RG * RG - x * x))
		local a = top + across * x - fwd * half
		local b = top + across * x + fwd * half
		local count = hiddenRuns(a, b, eye, skaters)
		for j = 1, count do
			local u0, u1 = runs[2 * j - 1], runs[2 * j]
			local p0, p1 = a:Lerp(b, u0), a:Lerp(b, u1)
			local piece = take(puckTint)
			if not piece then
				return
			end
			local mid = (p0 + p1) / 2 - axis * (PUCK.Thickness / 2)
			piece.CFrame = CFrame.lookAt(mid, mid + fwd, axis)
			piece.Size = Vector3.new(w + 0.01, thick, math.max(0.02, (p1 - p0).Magnitude))
		end
	end
end

local function hideAll()
	for i = 1, #pool do
		pool[i].Transparency = 1
	end
	used = 0
	if puckCopy then
		puckCopy.Transparency = 1
	end
	for _, copy in extraCopies do
		copy.Transparency = 1
	end
end

-- `rig` is the local skater's rig (nil when you aren't on the ice); `skaters` are every visible
-- skater's render state; `puck` is where the puck is drawn (nil when it is hidden); `more` are
-- any other pucks on the ice (practice's extra pucks, Build 40).
function Xray.update(camera: Camera, _dt: number, rig: Looks.Rig?, skaters: { Skater }, puck: BasePart?, more: { BasePart }?)
	if not gui then
		return
	end
	if not intact() then
		if gui then
			gui:Destroy()
		end
		Xray.init()
	end
	local g = gui :: ScreenGui
	g.Enabled = true
	viewCamera.CFrame = camera.CFrame
	viewCamera.FieldOfView = camera.FieldOfView
	local eye = camera.CFrame.Position
	local before = used
	used = 0

	-- Stick: the hidden stretches of the lower shaft and the blade.
	local shaft: BasePart? = nil
	local blade: BasePart? = nil
	local bladeToe: BasePart? = nil
	if rig then
		for _, piece in rig.stick do
			if piece.part.Name == "Shaft" then
				shaft = piece.part
			elseif piece.part.Name == "Blade" then
				blade = piece.part
			elseif piece.part.Name == "BladeToe" then
				bladeToe = piece.part
			end
		end
	end
	if shaft and blade then
		-- The shaft part runs along its own X; +X end is the blade end.
		local cf = shaft.CFrame
		local half = shaft.Size.X / 2
		local low = cf * Vector3.new(half, 0, 0)
		local high = cf * Vector3.new(half - shaft.Size.X * SHAFT_SHOWN, 0, 0)
		drawStretch(low, high, cf.UpVector, shaft.Size.Z, shaft.Size.Y, eye, skaters, true, false)
		-- The blade runs along its LookVector (-Z toward the toe), up is its UpVector. A curved
		-- blade is two boxes (heel half, then the toe half).
		local bcf = blade.CFrame
		local bhalf = blade.Size.Z / 2
		local heel = bcf * Vector3.new(0, 0, bhalf)
		local toe = bcf * Vector3.new(0, 0, -bhalf)
		if bladeToe then
			local tcf = bladeToe.CFrame
			local tip = tcf * Vector3.new(0, 0, -bladeToe.Size.Z / 2)
			drawStretch(heel, toe, bcf.UpVector, blade.Size.X, blade.Size.Y, eye, skaters, true, false)
			drawStretch(toe, tip, tcf.UpVector, bladeToe.Size.X, bladeToe.Size.Y, eye, skaters, false, true)
		else
			drawStretch(heel, toe, bcf.UpVector, blade.Size.X, blade.Size.Y, eye, skaters, true, true)
		end
	end

	-- Puck: only what is hidden (or all of it, with "puck outline" on).
	if puck and puck.Position.Y > -1 then
		drawPuck(puck, eye, skaters, puckCopy)
	else
		puckCopy.Transparency = 1
	end
	-- Build 40: practice's extra pucks (+ PUCK) glow through too, each with its own round copy.
	local n = if more then #more else 0
	for i = 1, n do
		local copy = extraCopies[i]
		if not copy then
			copy = newPuckCopy("ExtraPuck" .. i)
			extraCopies[i] = copy
		end
		if copy.Color ~= puckTint then
			copy.Color = puckTint
		end
		local p = (more :: { BasePart })[i]
		if p.Parent and p.Position.Y > -1 then
			drawPuck(p, eye, skaters, copy)
		else
			copy.Transparency = 1
		end
	end
	for i = n + 1, #extraCopies do
		extraCopies[i].Transparency = 1
	end

	for i = used + 1, math.max(before, used) do
		local p = pool[i]
		if p then
			p.Transparency = 1
		end
	end
end

function Xray.hide()
	if gui then
		hideAll()
		gui.Enabled = false
	end
end

return Xray
