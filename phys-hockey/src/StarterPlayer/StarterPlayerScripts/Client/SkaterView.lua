--!strict
-- Draws one skater slot from simulation state. The body comes from Looks (the cartoon rig);
-- this module only animates it: glide bob, lean into turns, stick wind-up and follow-through.
-- Purely visual, so cosmetics can never change a hitbox.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("GameConfig"))
local Sim = require(Shared:WaitForChild("Sim"))
local Looks = require(Shared:WaitForChild("Looks"))

local SkaterView = {}
SkaterView.__index = SkaterView

local FOLLOW_TIME = 0.28 -- the drawn follow-through after a shot

export type RenderState = {
	x: number,
	z: number,
	vx: number,
	vz: number,
	yaw: number,
	radius: number,
	charging: boolean,
	active: boolean,
	charge: number,
	stunned: boolean,
	sprinting: boolean,
	visible: boolean,
	lifted: boolean?,
	lofting: boolean?,
}

local function lookKey(look: any): string
	if type(look) ~= "table" then
		return "default"
	end
	return `{look.hat}|{look.hair}|{look.face}|{look.stick}|{look.skin}|{look.hairColor}`
end

-- Build 39: the tag's billboard, bigger (was 150 x 22) to fit the bigger match name.
local TAG_W, TAG_H = 190, 30

local function makeTag(): (BillboardGui, TextLabel, UIStroke, Frame)
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(TAG_W, TAG_H)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
	tag.AlwaysOnTop = true
	tag.LightInfluence = 0
	tag.MaxDistance = 500
	tag.ResetOnSpawn = false
	local box = Instance.new("Frame")
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.AutomaticSize = Enum.AutomaticSize.X
	box.Size = UDim2.fromOffset(0, 18)
	box.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	box.BackgroundTransparency = 0.2
	box.BorderSizePixel = 0
	box.Parent = tag
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = box
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = box
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = box
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 12
	label.Parent = box
	-- Build 35: the quiet match tag's thin outline (off for the boxed practice tag).
	local outline = Instance.new("UIStroke")
	outline.Name = "Outline"
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	outline.Color = Color3.new(0, 0, 0)
	outline.Transparency = 0.2 -- Build 39: a firm dark edge (was 0.65 at 1 px) so it reads over ice and crowd
	outline.Thickness = 1.6
	outline.Enabled = false
	outline.Parent = label
	return tag, label, stroke, box
end

-- Build 35: in matches the tag is just the name in the house font (Sarpanch, as everywhere
-- else), small and see-through, so it is there without getting in the way.
local BOXED_FONT = Font.fromEnum(Enum.Font.GothamBlack)
local QUIET_FONT = Font.fromName("Sarpanch", Enum.FontWeight.Bold)
-- Build 39: bigger and bolder (was 11 at 35% see-through; the user found it hard to spot).
local QUIET_SIZE = 16

function SkaterView.new(parent: Instance, slot: number): any
	local tag, label, stroke, box = makeTag()
	local self = setmetatable({
		slot = slot,
		parent = parent,
		rig = nil :: Looks.Rig?,
		key = "",
		team = -1,
		heading = if slot <= 3 then 0 else math.pi,
		stride = 0,
		lean = 0,
		sideLean = 0,
		swing = 0,
		swingYaw = 0, -- the drawn swing's turn of the stick: back on the wind-up, through on the follow-through
		follow = 0, -- seconds of follow-through left after a shot
		wasActive = false,
		liftBlend = 0,
		loftBlend = 0,
		isLocal = false,
		shaftLength = 0,
		parts = {} :: { BasePart },
		cframes = {} :: { CFrame },
		isVisible = false,
		tag = tag,
		tagLabel = label,
		tagStroke = stroke,
		tagBox = box,
	}, SkaterView)
	self:setIdentity(`Player {slot}`, if slot <= 3 then 1 else 2, false, nil)
	return self
end

function SkaterView:_rebuild(look: any, team: number)
	if self.rig then
		-- The tag lives inside the old model; lift it out before the model is destroyed.
		self.tag.Parent = nil
		self.rig.model:Destroy()
	end
	local rig = Looks.build(nil, look, team, Looks.PLAY_SCALE)
	rig.model.Name = `Skater_{self.slot}`
	self.rig = rig
	self.parts = Looks.movingParts(rig)
	self.cframes = {}
	for i = 1, #self.parts do
		self.cframes[i] = CFrame.identity
	end
	self.shaftLength = 0
	self.ringShown = nil
	self.tag.Adornee = rig.head
	self.tag.Parent = rig.model
	if self.isVisible then
		rig.model.Parent = self.parent
	end
end

function SkaterView:setIdentity(name: string, team: number, isLocal: boolean, look: any)
	local key = lookKey(look)
	if key ~= self.key or team ~= self.team or not self.rig then
		self.key = key
		self.team = team
		self:_rebuild(look, team)
	end
	self.isLocal = isLocal
	local kit = Looks.kit(team)
	self.tagLabel.Text = string.upper(name)
	self.tagKit = kit.tag
	self:_styleTag()
end

-- Build 35: the boxed practice tag, or the quiet match one (no box, see-through, house font).
function SkaterView:setTagQuiet(on: boolean)
	if self.tagQuiet == on then
		return
	end
	self.tagQuiet = on
	self.tagScaleShown = nil
	self:_styleTag()
	self:_applyDisplay()
end

function SkaterView:_styleTag()
	local quiet = self.tagQuiet == true
	local kit: Color3 = self.tagKit or Color3.new(1, 1, 1)
	local label = self.tagLabel
	label.FontFace = if quiet then QUIET_FONT else BOXED_FONT
	label.TextColor3 = if quiet then Color3.new(1, 1, 1):Lerp(kit, 0.4) else kit
	label.TextTransparency = if quiet then 0.05 else 0
	-- lihfolk-ignore: findfirstchild-chain (a type cast, checked for nil on the next line)
	local outline = label:FindFirstChild("Outline") :: UIStroke?
	if outline then
		outline.Enabled = quiet
	end
	self.tagStroke.Enabled = not quiet
	self.tagStroke.Color = kit
	self.tagStroke.Thickness = if self.isLocal then 2 else 1.5
	self.tagBox.BackgroundTransparency = if quiet then 1 elseif self.isLocal then 0.05 else 0.25
	self.tag.AlwaysOnTop = not quiet
	self.tag.StudsOffsetWorldSpace = Vector3.new(0, if quiet then 3.6 else 3.4, 0)
end

-- Display settings shared by every skater view (Settings: Social and Visuals).
SkaterView.config = {
	tags = true, -- name tags over other skaters
	ownTag = true, -- your own name tag
	rings = true, -- team rings under other skaters
	ownRing = true, -- the ring under your own skater
	tagScale = 1,
}

-- Hidden by the caller (practice hides the bot tags); the settings above still apply on top.
function SkaterView:setTagVisible(on: boolean)
	self.tagAllowed = on
	self:_applyDisplay()
end

function SkaterView:_applyDisplay()
	local cfg = SkaterView.config
	local tagOn = self.tagAllowed ~= false and cfg.tags and (cfg.ownTag or not self.isLocal)
	if self.tag.Enabled ~= tagOn then
		self.tag.Enabled = tagOn
	end
	if self.tagScaleShown ~= cfg.tagScale then
		self.tagScaleShown = cfg.tagScale
		self.tag.Size = UDim2.fromOffset(TAG_W * cfg.tagScale, TAG_H * cfg.tagScale)
		self.tagBox.Size = UDim2.fromOffset(0, 18 * cfg.tagScale)
		self.tagLabel.TextSize = math.round((if self.tagQuiet then QUIET_SIZE else 12) * cfg.tagScale)
	end
	local ringOn = if self.isLocal then cfg.ownRing else cfg.rings
	local rig = self.rig
	if rig and self.ringShown ~= ringOn then
		self.ringShown = ringOn
		for _, p in rig.ring do
			p.LocalTransparencyModifier = if ringOn then 0 else 1
		end
	end
end

function SkaterView:setVisible(visible: boolean)
	if self.isVisible ~= visible then
		self.isVisible = visible
		if self.rig then
			self.rig.model.Parent = if visible then self.parent else nil
		end
	end
end

function SkaterView:update(state: RenderState, dt: number)
	self:setVisible(state.visible)
	self:_applyDisplay()
	local rig = self.rig
	if not state.visible or not rig then
		return
	end

	-- The mouse turns the whole skater: the body always faces along the stick, whichever way
	-- the skater is gliding (forwards, backwards or sideways), so a spin spins the skater.
	local delta = (state.yaw - self.heading + math.pi) % (2 * math.pi) - math.pi
	self.heading += delta * (1 - math.exp(-32 * dt))
	-- No bobbing, rocking, wobbling or leaning: the body keeps one steady posture whatever the
	-- skating does. (Build 30: the slight forward/back lean with skating direction is gone, it
	-- read as the skater tipping every time they changed direction.)
	self.sideLean = 0
	self.lean = 0

	local origin = Vector3.new(state.x, 0, state.z)
	-- Rotation about Y by this angle points local -Z along (cos heading, sin heading).
	local root = CFrame.new(origin) * CFrame.Angles(0, -self.heading - math.pi / 2, 0)
	local bob = 0
	local body = root * CFrame.Angles(-self.lean, 0, 0)

	local cframes = self.cframes
	local n = 0
	for i in rig.body do
		n += 1
		cframes[n] = body * rig.offsets[i]
	end
	-- Build 40: spinning, bobbing and pulsing pieces (the Nova set), if this skater wears any.
	Looks.animate(rig, body, cframes, os.clock())
	for i in rig.ring do
		n += 1
		cframes[n] = CFrame.new(origin) * rig.ringOffsets[i]
	end

	-- The wind-up raises the blade (a bot winding up has its stick lifted, so it touches nothing);
	-- it never turns the drawn stick away from where the physics has it, so the blade on screen
	-- is always the blade the puck meets.
	-- A real swing, not a stamp: the wind-up draws the stick back and up on the forehand side, the
	-- release sweeps it forward through the puck (landing on the physics blade as the shot fires),
	-- and a short follow-through carries it on past and up before it settles.
	if self.wasActive and not state.active then
		self.follow = FOLLOW_TIME
	end
	self.wasActive = state.active
	self.follow = math.max(0, self.follow - dt)
	-- The wind-up is a whip round the body, not a lift: the stick stays low and swings back
	-- round behind the skater (further the longer the charge), then sweeps through the puck on
	-- release and on past it. (It used to rise up to 3 studs and drop, which read as a stamp.)
	local swingTarget = if state.charging then 0.06 + state.charge * 0.1 else 0
	local yawTarget = if state.charging then -(0.7 + state.charge * 1.6) else 0
	if self.follow > 0 then
		local k = self.follow / FOLLOW_TIME
		swingTarget = 0.12 * k
		yawTarget = 0.9 * math.sin(k * math.pi * 0.5)
	end
	-- Build 30: the back-swing comes round quicker (was 16), so even a bot's short wind-up is
	-- seen to draw the stick back before it sweeps through.
	local rate = if state.active then 60 elseif self.follow > 0 then 30 elseif state.charging then 26 else 16
	self.swing += (swingTarget - self.swing) * (1 - math.exp(-rate * dt))
	self.swingYaw += (yawTarget - self.swingYaw) * (1 - math.exp(-rate * dt))
	local yaw = state.yaw + self.swingYaw
	-- Stick lift hovers the blade just over the puck; puck lift opens the blade face.
	-- Build 30: not while winding up. A bot lifts its stick for the wind-up (so turning it onto
	-- the line can't knock the puck), and drawing that lift and then the drop on release read as
	-- a chop at the puck rather than a swing; the wind-up already draws the stick back off it.
	local liftTarget = if state.lifted and not state.charging and not state.active then 1 else 0
	self.liftBlend += (liftTarget - self.liftBlend) * (1 - math.exp(-28 * dt))
	self.loftBlend += ((if state.lofting then 1 else 0) - self.loftBlend) * (1 - math.exp(-14 * dt))
	local raise = math.max(0, self.swing) * 3.2 + self.liftBlend * Config.Stick.LiftHeight
	local bladeFlat = Sim.bladeAt(origin, yaw, state.radius)
	-- Hands ride on the left of the body; the stick crosses to the blade like a real grip.
	-- Puck lift leans the blade back toward the viewer: for your own skater that is toward your
	-- camera; for everyone else, back toward the goal they defend.
	local back: Vector3
	if self.isLocal or self.team == 0 then
		local look = workspace.CurrentCamera.CFrame.LookVector
		back = Vector3.new(-look.X, 0, -look.Z)
	else
		back = Vector3.new(if self.team == 1 then -1 else 1, 0, 0)
	end
	local f = Looks.stickFrames(origin, yaw, bladeFlat, raise, bob, -1, self.loftBlend, back, rig.scale)
	if math.abs(f.shaftLength - self.shaftLength) > 0.04 then
		self.shaftLength = f.shaftLength
		Looks.sizeStick(rig, f.shaftLength)
	end
	Looks.placeStick(rig, f, cframes, Looks.placeHands(rig, f, cframes, n))

	workspace:BulkMoveTo(self.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

function SkaterView:destroy()
	if self.rig then
		self.rig.model:Destroy()
	end
	self.tag:Destroy()
end

return SkaterView
