-- Plays a victory emote on a character, on THIS client. Every client plays the same emote for
-- contestants on stage, so everyone watching sees it. Emotes mix Roblox's built-in emote
-- animations with procedural hops and spins on the character's root joint.
local RunService = game:GetService("RunService")
local Catalog = require(script.Parent.ShopCatalog)

local EmotePlayer = {}

-- Roblox's default emote animations (public, usable in any experience)
local ANIMS = {
	R15 = { wave = 507770239, point = 507770453, dance = 507771019, dance2 = 507776043, dance3 = 507777268, laugh = 507770818, cheer = 507770677 },
	R6 = { wave = 128777973, point = 128853357, dance = 182435998, dance2 = 182436842, dance3 = 182436935, laugh = 129423131, cheer = 129423030 },
}

local TAU = math.pi * 2
local function ease(u) return u < 0.5 and 2 * u * u or 1 - (-2 * u + 2) ^ 2 / 2 end
local function hop(t, count, dur, height)
	if t > dur then return 0 end
	return math.abs(math.sin(t / dur * math.pi * count)) * height
end

-- time = seconds, anim = built-in animation, motion(t) -> lift (studs), spin (radians), tilt (radians)
local STYLES = {
	jump = { time = 2.2, anim = "cheer", motion = function(t) return hop(t, 2, 1.6, 2.4), 0, 0 end },
	twirl = { time = 1.8, motion = function(t) local u = math.clamp(t / 1.5, 0, 1) return math.sin(u * math.pi) * 0.8, ease(u) * TAU * 2, 0 end },
	fistpump = { time = 2.4, anim = "cheer", speed = 1.4, motion = function(t) return math.abs(math.sin(t * 6)) * 0.45, 0, 0 end },
	dance = { time = 3.2, anim = "dance" },
	disco = { time = 3.2, anim = "dance2" },
	robot = { time = 3.2, anim = "dance3" },
	wave = { time = 2.4, anim = "wave", motion = function(t) return hop(t, 1, 0.6, 1.2), 0, 0 end },
	point = { time = 2.8, anim = "point", animDelay = 1.0, motion = function(t) local u = math.clamp(t, 0, 1) return math.sin(u * math.pi), ease(u) * TAU, 0 end },
	giggle = { time = 2.6, anim = "laugh", motion = function(t) return math.abs(math.sin(t * 7)) * 0.25, 0, math.sin(t * 9) * math.rad(8) end },
	rocket = { time = 2.8, anim = "cheer", animDelay = 1.3, motion = function(t) local u = math.clamp(t / 1.3, 0, 1) return math.sin(u * math.pi) * 3.6, ease(u) * TAU * 2, 0 end },
	-- Halloween: hop on a witch's broom and ride it like a bucking bull, one arm in the air.
	-- Rides a little loop (radius 1.6 studs) while bucking up and down and rocking nose-to-tail.
	-- the arm in the air is Roblox's wave animation, looped (newer avatar joints limit how far a
	-- script can swing the shoulder, but animations can always raise it)
	broom = { time = 4.2, broom = true, anim = "wave", loop = true, speed = 1.3,
		motion = function(t)
			local fade = math.clamp(t / 0.35, 0, 1) * math.clamp((4.2 - t) / 0.35, 0, 1)
			local buck = math.abs(math.sin(t * 7)) -- bounces like a rodeo bull
			local lift = (1.4 + buck * 0.9) * fade
			local a = t * 1.9 -- one loop every ~3.3 s
			local x, z = math.sin(a) * 1.6 * fade, (1 - math.cos(a)) * -1.6 * fade
			local yaw = -a * fade -- nose follows the loop
			local pitch = math.sin(t * 7) * math.rad(14) * fade -- rear up, then nose down
			local roll = math.sin(t * 3.5) * math.rad(6) * fade
			return lift, yaw, roll, x, z, pitch
		end },
}
EmotePlayer.Styles = STYLES

-- The joint between the root part and the body. Returns (object, property) to offset:
-- classic Motor6D joints use C0; newer AnimationConstraint joints use their root-side attachment.
local function rootJoint(char)
	local lt = char:FindFirstChild("LowerTorso")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local j = (lt and lt:FindFirstChild("Root")) or (hrp and hrp:FindFirstChild("RootJoint"))
	if not j then return nil end
	if j:IsA("Motor6D") then return j, "C0" end
	if j:IsA("AnimationConstraint") and j.Attachment0 then return j.Attachment0, "CFrame" end
	return nil
end

local playing = setmetatable({}, { __mode = "k" }) -- character -> token of the emote now playing

---------------------------------------------------------------- witch's broom (Broom Rodeo)
-- A little broom welded under the hips, a riding pose (legs astride, one arm whipping in the air)
-- made by nudging the limb joints, and a sparkly purple trail. Everything is local and removed
-- when the emote ends.
-- returns (object, property) to rotate: classic Motor6D joints use C0, newer AnimationConstraint
-- joints use their parent-side attachment (same idea as rootJoint below)
local function jointOf(char, names)
	for _, n in ipairs(names) do
		local partName, jointName = n[1], n[2]
		local part = char:FindFirstChild(partName)
		local j = part and part:FindFirstChild(jointName)
		if j and j:IsA("Motor6D") then return j, "C0" end
		if j and j:IsA("AnimationConstraint") and j.Attachment0 then return j.Attachment0, "CFrame" end
	end
	return nil
end
local function broomProp(char)
	local hips = char:FindFirstChild("LowerTorso") or char:FindFirstChild("Torso")
	if not hips then return nil end
	local r15 = hips.Name == "LowerTorso"
	local model = Instance.new("Model"); model.Name = "BroomRide"
	local function part(name, size, offset, color, mat, shape)
		local p = Instance.new("Part")
		p.Name = name; p.Size = size; p.Color = color; p.Material = mat or Enum.Material.SmoothPlastic
		if shape then p.Shape = shape end
		p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.Massless = true; p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
		p.CFrame = hips.CFrame * offset
		local w = Instance.new("Weld"); w.Part0 = hips; w.Part1 = p; w.C0 = offset; w.Parent = p
		p.Parent = model
		return p
	end
	local y = r15 and -0.75 or -1.25 -- just under the seat
	local ALONG = CFrame.Angles(0, math.rad(90), 0) -- cylinders lie along the body's front-back axis
	local handle = part("Handle", Vector3.new(6.4, 0.32, 0.32), CFrame.new(0, y, -0.6) * ALONG, Color3.fromRGB(120, 78, 40), Enum.Material.Wood, Enum.PartType.Cylinder)
	part("Knob", Vector3.one * 0.45, CFrame.new(0, y, -3.8), Color3.fromRGB(95, 60, 30), Enum.Material.Wood, Enum.PartType.Ball)
	part("Binding", Vector3.new(0.35, 0.62, 0.62), CFrame.new(0, y, 2.55) * ALONG, Color3.fromRGB(150, 60, 220), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	for i, d in ipairs({ 1.15, 1.35, 1.25, 0.95 }) do -- the bushy bristles fan out at the back
		part("Bristles", Vector3.new(0.6, d, d), CFrame.new(0, y, 2.8 + i * 0.42) * ALONG, i % 2 == 0 and Color3.fromRGB(230, 170, 70) or Color3.fromRGB(205, 145, 55), Enum.Material.Fabric, Enum.PartType.Cylinder)
	end
	-- magic sparkles + a purple trail streaming off the bristles
	local tail = part("Magic", Vector3.one * 0.2, CFrame.new(0, y, 4.6), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	tail.Transparency = 1
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 0.4, 0); a0.Parent = tail
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -0.4, 0); a1.Parent = tail
	local trail = Instance.new("Trail"); trail.Attachment0 = a0; trail.Attachment1 = a1; trail.Lifetime = 0.45; trail.LightEmission = 1; trail.FaceCamera = true
	trail.Color = ColorSequence.new(Color3.fromRGB(190, 90, 255), Color3.fromRGB(255, 140, 40)); trail.Transparency = NumberSequence.new(0.2, 1); trail.WidthScale = NumberSequence.new(1, 0); trail.Parent = tail
	local pe = Instance.new("ParticleEmitter"); pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"; pe.Rate = 30; pe.Lifetime = NumberRange.new(0.5, 1)
	pe.Speed = NumberRange.new(1, 3); pe.SpreadAngle = Vector2.new(60, 60); pe.Size = NumberSequence.new(0.45, 0); pe.LightEmission = 1
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 160, 50), Color3.fromRGB(170, 90, 255)); pe.Parent = a0
	model.PrimaryPart = handle
	model.Parent = char
	return model
end
-- limb joints to pose: { joint candidates (R15 first, then R6), extra rotation (applied to C0) }
local RIDE_POSE = {
	leftLeg = { { { "LeftUpperLeg", "LeftHip" }, { "Torso", "Left Hip" } }, function(t) return CFrame.Angles(math.rad(70), 0, math.rad(-22)) end },
	rightLeg = { { { "RightUpperLeg", "RightHip" }, { "Torso", "Right Hip" } }, function(t) return CFrame.Angles(math.rad(70), 0, math.rad(22)) end },
	leftKnee = { { { "LeftLowerLeg", "LeftKnee" } }, function(t) return CFrame.Angles(math.rad(-55), 0, 0) end },
	rightKnee = { { { "RightLowerLeg", "RightKnee" } }, function(t) return CFrame.Angles(math.rad(-55), 0, 0) end },
}

-- Returns how long the emote lasts (0 if it couldn't play).
function EmotePlayer.play(char, emoteId)
	local item = Catalog.get(emoteId or "")
	local style = item and item.kind == "Emote" and STYLES[item.style]
	if not (char and style) then return 0 end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return 0 end
	local token = {}
	playing[char] = token

	local track
	if style.anim then
		local animator = hum:FindFirstChildOfClass("Animator")
		local ids = ANIMS[hum.RigType == Enum.HumanoidRigType.R6 and "R6" or "R15"]
		if animator and ids[style.anim] then
			local anim = Instance.new("Animation")
			anim.AnimationId = "rbxassetid://" .. ids[style.anim]
			local ok, t = pcall(function() return animator:LoadAnimation(anim) end)
			if ok and t then
				track = t
				track.Priority = Enum.AnimationPriority.Action
				track.Looped = style.loop == true
				pcall(function() track.Priority = Enum.AnimationPriority.Action4 end)
				task.delay(style.animDelay or 0, function()
					if playing[char] == token then track:Play(0.15, 1, style.speed or 1) end
				end)
			end
		end
	end

	local joint, prop
	if style.motion then joint, prop = rootJoint(char) end
	local base
	if joint then
		base = joint:GetAttribute("EmoteBase") or joint[prop]
		joint:SetAttribute("EmoteBase", base)
	end
	-- the broom ride: a broom prop and a riding pose on the limb joints
	local prop_, pose = nil, {}
	if style.broom then
		local old = char:FindFirstChild("BroomRide")
		if old then old:Destroy() end
		prop_ = broomProp(char)
		for _, spec in pairs(RIDE_POSE) do
			local j, jp = jointOf(char, spec[1])
			if j then
				local b = j:GetAttribute("EmoteBase") or j[jp]
				j:SetAttribute("EmoteBase", b)
				table.insert(pose, { joint = j, prop = jp, base = b, rot = spec[2] })
			end
		end
	end
	local function endPose()
		for _, p in ipairs(pose) do
			if p.joint.Parent then p.joint[p.prop] = p.base; p.joint:SetAttribute("EmoteBase", nil) end
		end
		if prop_ then prop_:Destroy() end
	end
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		local mine = playing[char] == token
		if not mine or t >= style.time or not char.Parent then
			conn:Disconnect()
			if track then track:Stop(0.3) end
			if mine then
				playing[char] = nil
				if joint then joint[prop] = base; joint:SetAttribute("EmoteBase", nil) end
			end
			if mine or style.broom then endPose() end
			return
		end
		if joint then
			local lift, spin, tilt, x, z, pitch = style.motion(t)
			joint[prop] = CFrame.new(x or 0, lift, z or 0) * CFrame.Angles(0, spin, 0) * CFrame.Angles(pitch or 0, 0, tilt) * base
		end
		for _, p in ipairs(pose) do
			if p.joint.Parent then p.joint[p.prop] = p.base * p.rot(t) end
		end
	end)
	return style.time
end

return EmotePlayer
