-- Builds the studio audience: colourful, individually dressed fans in the theatre seats.
-- Fans are plain anchored parts grouped into bones (Body, ArmL, ArmR, LegL, LegR) so the
-- client can animate hundreds of them cheaply with workspace:BulkMoveTo.
-- The same seed always produces the same fan, so the Studio template and every player's
-- arena show the same crowd.
local CrowdBuilder = {}

CrowdBuilder.FILL = 0.86 -- share of seats with a fan in them
CrowdBuilder.HIP_Y = 0.42
CrowdBuilder.SEATED_LEG = math.rad(80)
CrowdBuilder.Joints = {
	ArmL = Vector3.new(-1.32, 1.72, 0), ArmR = Vector3.new(1.32, 1.72, 0),
	LegL = Vector3.new(-0.45, 0, 0), LegR = Vector3.new(0.45, 0, 0),
}

local SKIN = {
	Color3.fromRGB(255, 224, 196), Color3.fromRGB(241, 194, 160), Color3.fromRGB(224, 172, 130),
	Color3.fromRGB(198, 134, 92), Color3.fromRGB(160, 102, 66), Color3.fromRGB(116, 72, 46), Color3.fromRGB(86, 54, 36),
}
local SHIRTS = {
	Color3.fromRGB(255, 72, 92), Color3.fromRGB(255, 146, 40), Color3.fromRGB(255, 214, 40), Color3.fromRGB(84, 214, 90),
	Color3.fromRGB(40, 200, 210), Color3.fromRGB(60, 128, 255), Color3.fromRGB(150, 86, 255), Color3.fromRGB(255, 96, 200),
	Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 120, 120), Color3.fromRGB(120, 230, 255), Color3.fromRGB(190, 255, 120),
}
local PANTS = { Color3.fromRGB(52, 78, 140), Color3.fromRGB(35, 40, 60), Color3.fromRGB(200, 170, 120), Color3.fromRGB(90, 60, 140), Color3.fromRGB(40, 110, 90), Color3.fromRGB(70, 70, 75) }
local HAIR = { Color3.fromRGB(30, 22, 18), Color3.fromRGB(70, 44, 26), Color3.fromRGB(140, 90, 50), Color3.fromRGB(230, 190, 110), Color3.fromRGB(190, 70, 40), Color3.fromRGB(255, 110, 190), Color3.fromRGB(80, 160, 255), Color3.fromRGB(150, 100, 255), Color3.fromRGB(225, 225, 230) }
local SIGNS = { "GO GO GO!", "WOW!!", "♥ CLAMILLION", "RARE!!", "HI MOM!", "#1 FAN", "BIG BRAIN!", "YOU GOT THIS", "★ ★ ★", "LOCK IT IN!" }
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)

local function pick(rng, list) return list[rng:NextInteger(1, #list)] end

local function newPart(bone, name, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.CFrame = cf; p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then p.Shape = shape end
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("Bone", bone)
	return p
end

local function textFace(part, face, text, color)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face; sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud; sg.PixelsPerStud = 40; sg.LightInfluence = 0.3
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1; t.Size = UDim2.fromScale(1, 1); t.FontFace = FONT; t.TextScaled = true
	t.Text = text; t.TextColor3 = color; t.Parent = sg
	sg.Parent = part
end

-- Builds one fan sitting on `seatTop` (a CFrame on the seat surface facing the stage).
function CrowdBuilder.fan(seatTop, seed)
	local rng = Random.new(seed)
	local model = Instance.new("Model")
	model.Name = "Fan"
	local base = seatTop * CFrame.new(0, CrowdBuilder.HIP_Y, 0.35)
	local skin, shirt, pants = pick(rng, SKIN), pick(rng, SHIRTS), pick(rng, PANTS)
	local accent = pick(rng, SHIRTS)
	local hair = pick(rng, HAIR)
	local parts = {}
	local function add(p) p.Parent = model; table.insert(parts, p); return p end

	-- body ------------------------------------------------------------------
	add(newPart("Body", "Torso", Vector3.new(1.8, 1.8, 0.9), base * CFrame.new(0, 0.9, 0), shirt))
	local style = rng:NextNumber()
	if style < 0.35 then
		add(newPart("Body", "Stripe", Vector3.new(1.84, 0.36, 0.94), base * CFrame.new(0, 1.05, 0), accent))
	elseif style < 0.55 then
		add(newPart("Body", "Star", Vector3.new(0.55, 0.55, 0.06), base * CFrame.new(0, 1.15, -0.47) * CFrame.Angles(0, 0, math.rad(45)), accent, Enum.Material.Neon))
	end
	if rng:NextNumber() < 0.3 then -- jersey number on the back (what the camera mostly sees)
		local back = add(newPart("Body", "Jersey", Vector3.new(1.3, 1.1, 0.05), base * CFrame.new(0, 0.95, 0.47), shirt))
		back.Transparency = 1
		textFace(back, Enum.NormalId.Back, tostring(rng:NextInteger(1, 99)), accent)
	end
	local head = add(newPart("Body", "Head", Vector3.new(1.15, 1.15, 1.15), base * CFrame.new(0, 2.38, 0), skin))
	local mesh = Instance.new("SpecialMesh"); mesh.MeshType = Enum.MeshType.Head; mesh.Scale = Vector3.new(1.15, 1.15, 1.15); mesh.Parent = head
	local h = base * CFrame.new(0, 2.38, 0)
	for _, x in ipairs({ -0.21, 0.21 }) do
		add(newPart("Body", "Eye", Vector3.new(0.2, 0.24, 0.2), h * CFrame.new(x, 0.12, -0.55), Color3.fromRGB(25, 20, 30), nil, Enum.PartType.Ball))
	end
	if rng:NextNumber() < 0.5 then
		for _, x in ipairs({ -0.36, 0.36 }) do
			add(newPart("Body", "Blush", Vector3.new(0.2, 0.1, 0.04), h * CFrame.new(x, -0.08, -0.57), Color3.fromRGB(255, 140, 150)))
		end
	end
	add(newPart("Body", "MouthSmile", Vector3.new(0.38, 0.08, 0.05), h * CFrame.new(0, -0.24, -0.57), Color3.fromRGB(110, 30, 40)))
	local open = add(newPart("Body", "MouthOpen", Vector3.new(0.3, 0.3, 0.05), h * CFrame.new(0, -0.24, -0.57), Color3.fromRGB(110, 30, 40)))
	open.Transparency = 1

	-- hair / hats --------------------------------------------------------------
	local hat = rng:NextInteger(1, 7)
	if hat == 1 or hat == 2 then -- short or long hair
		add(newPart("Body", "Hair", Vector3.new(1.2, 0.4, 1.2), h * CFrame.new(0, 0.45, 0.04), hair))
		add(newPart("Body", "Hair", Vector3.new(1.2, hat == 2 and 1.5 or 0.75, 0.32), h * CFrame.new(0, hat == 2 and -0.22 or 0.1, 0.46), hair))
		if hat == 2 and rng:NextNumber() < 0.5 then
			local bow = pick(rng, SHIRTS)
			add(newPart("Body", "Bow", Vector3.new(0.35, 0.3, 0.12), h * CFrame.new(-0.2, 0.62, 0.3) * CFrame.Angles(0, 0, 0.5), bow))
			add(newPart("Body", "Bow", Vector3.new(0.35, 0.3, 0.12), h * CFrame.new(0.2, 0.62, 0.3) * CFrame.Angles(0, 0, -0.5), bow))
		end
	elseif hat == 3 then -- baseball cap
		local cap = pick(rng, SHIRTS)
		add(newPart("Body", "Cap", Vector3.new(1.22, 0.42, 1.22), h * CFrame.new(0, 0.48, 0), cap))
		add(newPart("Body", "Brim", Vector3.new(1.0, 0.08, 0.55), h * CFrame.new(0, 0.3, -0.78), cap))
	elseif hat == 4 then -- beanie with pom-pom
		local c = pick(rng, SHIRTS)
		add(newPart("Body", "Beanie", Vector3.new(1.22, 0.55, 1.22), h * CFrame.new(0, 0.42, 0), c))
		add(newPart("Body", "Pom", Vector3.new(0.42, 0.42, 0.42), h * CFrame.new(0, 0.82, 0), Color3.new(1, 1, 1), nil, Enum.PartType.Ball))
	elseif hat == 5 then -- space puffs
		add(newPart("Body", "Hair", Vector3.new(1.2, 0.35, 1.2), h * CFrame.new(0, 0.46, 0.04), hair))
		for _, x in ipairs({ -0.55, 0.55 }) do
			add(newPart("Body", "Puff", Vector3.new(0.62, 0.62, 0.62), h * CFrame.new(x, 0.55, 0.05), hair, nil, Enum.PartType.Ball))
		end
	elseif hat == 6 then -- light-up headband antennae
		add(newPart("Body", "Hair", Vector3.new(1.2, 0.4, 1.2), h * CFrame.new(0, 0.45, 0.04), hair))
		local glow = pick(rng, SHIRTS)
		for _, x in ipairs({ -0.35, 0.35 }) do
			add(newPart("Body", "Antenna", Vector3.new(0.08, 0.6, 0.08), h * CFrame.new(x, 0.9, 0), Color3.fromRGB(40, 40, 50)))
			add(newPart("Body", "Glow", Vector3.new(0.3, 0.3, 0.3), h * CFrame.new(x, 1.22, 0), glow, Enum.Material.Neon, Enum.PartType.Ball))
		end
	end -- hat 7: buzz cut / bald

	-- arms ---------------------------------------------------------------------
	-- Fans holding a sign, foam finger or glow stick are built with that arm raised.
	local roll = rng:NextNumber()
	local armRRest = (roll < 0.36) and math.rad(165) or 0
	local jacket = rng:NextNumber() < 0.35
	local joint = {
		ArmL = base * CFrame.new(CrowdBuilder.Joints.ArmL),
		ArmR = base * CFrame.new(CrowdBuilder.Joints.ArmR) * CFrame.Angles(armRRest, 0, 0),
	}
	for _, side in ipairs({ "ArmL", "ArmR" }) do
		local j = joint[side]
		add(newPart(side, "Sleeve", Vector3.new(0.85, 0.8, 0.85), j * CFrame.new(0, -0.32, 0), shirt))
		add(newPart(side, "Forearm", Vector3.new(0.8, 1.05, 0.8), j * CFrame.new(0, -1.22, 0), jacket and shirt or skin))
		if jacket then add(newPart(side, "Hand", Vector3.new(0.7, 0.3, 0.7), j * CFrame.new(0, -1.86, 0), skin)) end
	end

	-- legs (built seated: rotated forward at the hip) ------------------------------
	for _, side in ipairs({ "LegL", "LegR" }) do
		local j = base * CFrame.new(CrowdBuilder.Joints[side]) * CFrame.Angles(CrowdBuilder.SEATED_LEG, 0, 0)
		add(newPart(side, "Leg", Vector3.new(0.86, 1.8, 0.86), j * CFrame.new(0, -0.9, 0), pants))
		add(newPart(side, "Shoe", Vector3.new(0.9, 0.35, 0.95), j * CFrame.new(0, -1.8, -0.06), rng:NextNumber() < 0.5 and Color3.new(1, 1, 1) or pick(rng, SHIRTS)))
	end

	-- props -------------------------------------------------------------------
	local prop = "none"
	local hand = joint.ArmR * CFrame.new(0, -1.85, 0)
	if roll < 0.12 then
		prop = "finger"
		local c = pick(rng, { Color3.fromRGB(255, 214, 40), Color3.fromRGB(60, 160, 255), Color3.fromRGB(255, 80, 140) })
		add(newPart("ArmR", "FoamHand", Vector3.new(1.0, 1.0, 0.45), hand * CFrame.new(0, -0.35, 0), c))
		add(newPart("ArmR", "FoamFinger", Vector3.new(0.35, 1.3, 0.35), hand * CFrame.new(0.15, -1.4, 0), c))
	elseif roll < 0.24 then
		prop = "sign"
		add(newPart("ArmR", "SignStick", Vector3.new(0.15, 2.2, 0.15), hand * CFrame.new(0, -0.9, 0), Color3.fromRGB(160, 110, 60)))
		local board = add(newPart("ArmR", "SignBoard", Vector3.new(3.4, 1.8, 0.12), hand * CFrame.new(-0.6, -2.4, 0) * CFrame.Angles(0, 0, math.pi), Color3.new(1, 1, 1)))
		local text = pick(rng, SIGNS)
		local col = pick(rng, { Color3.fromRGB(255, 60, 110), Color3.fromRGB(60, 110, 255), Color3.fromRGB(150, 60, 220), Color3.fromRGB(255, 120, 0) })
		textFace(board, Enum.NormalId.Front, text, col)
		textFace(board, Enum.NormalId.Back, text, col)
	elseif roll < 0.36 then
		prop = "glow"
		add(newPart("ArmR", "GlowStick", Vector3.new(0.22, 1.5, 0.22), hand * CFrame.new(0, -0.6, 0), pick(rng, SHIRTS), Enum.Material.Neon))
	elseif roll < 0.44 then
		prop = "pompom"
		local c = pick(rng, SHIRTS)
		for _, side in ipairs({ "ArmL", "ArmR" }) do
			local hj = joint[side] * CFrame.new(0, -2.0, 0)
			add(newPart(side, "PomPom", Vector3.new(1.1, 1.1, 1.1), hj, c, Enum.Material.Glass, Enum.PartType.Ball))
		end
	end

	model:SetAttribute("Base", base)
	model:SetAttribute("Seed", seed)
	model:SetAttribute("Prop", prop)
	model:SetAttribute("ArmRRest", armRRest)
	model:SetAttribute("Whistler", rng:NextNumber() < 0.25)
	return model
end

-- Fill every theatre seat in `arena.Audience` (deterministically) and return the Crowd folder.
-- `yieldEvery` lets the client spread construction over several frames.
function CrowdBuilder.build(arena, yieldEvery)
	local crowd = arena:FindFirstChild("Crowd")
	if not crowd then crowd = Instance.new("Folder"); crowd.Name = "Crowd"; crowd.Parent = arena end
	crowd:ClearAllChildren()
	local seats = {}
	for _, tier in ipairs(arena.Audience:GetChildren()) do
		for _, m in ipairs(tier:GetChildren()) do
			local seat = m:IsA("Model") and m:FindFirstChild("Seat")
			if seat then table.insert(seats, { model = m, seat = seat }) end
		end
	end
	-- stable order regardless of where the arena was cloned to
	local origin = arena:GetPivot()
	table.sort(seats, function(a, b)
		local pa, pb = origin:PointToObjectSpace(a.seat.Position), origin:PointToObjectSpace(b.seat.Position)
		if math.abs(pa.Z - pb.Z) > 0.5 then return pa.Z < pb.Z end
		return pa.X < pb.X
	end)
	local pending = Instance.new("Folder")
	local built = 0
	for i, s in ipairs(seats) do
		local rng = Random.new(i * 7919)
		if rng:NextNumber() < CrowdBuilder.FILL then
			local look = s.model:GetPivot().LookVector
			local top = s.seat.Position + Vector3.new(0, s.seat.Size.Y / 2, 0)
			local fan = CrowdBuilder.fan(CFrame.lookAt(top, top + Vector3.new(look.X, 0, look.Z)), i * 104729)
			fan.Name = "Fan" .. i
			fan.Parent = pending
			built += 1
			if yieldEvery and built % yieldEvery == 0 then
				for _, f in ipairs(pending:GetChildren()) do f.Parent = crowd end
				task.wait()
			end
		end
	end
	for _, f in ipairs(pending:GetChildren()) do f.Parent = crowd end
	pending:Destroy()
	return crowd, built
end

return CrowdBuilder
