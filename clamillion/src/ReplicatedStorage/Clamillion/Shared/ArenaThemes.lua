-- Shop arenas are cosmetic and CLIENT-SIDE. The server always builds the classic stage; each
-- player's own client dresses it in the arena they equipped: it recolours the set, flags and
-- seats, and adds that theme's decorations. Podiums, titles and emotes are NOT touched here,
-- so everyone still sees each other's podiums, titles and emotes.
local RS = game:GetService("ReplicatedStorage")

local ArenaThemes = {}

-- the classic studio sits here; decorations are authored relative to it
local CLASSIC_PIVOT = CFrame.new(0, 36, 10)
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylinders stand up
local N, METAL, GLASS = Enum.Material.Neon, Enum.Material.Metal, Enum.Material.Glass
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

---------------------------------------------------------------- building helpers
local function P(parent, name, size, cf, color, mat, shape, transparency)
	local p = Instance.new("Part")
	p.Name = name; p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Size = size; p.CFrame = cf; p.Color = color; p.Material = mat or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	if transparency then p.Transparency = transparency end
	p.Parent = parent
	return p
end
local function W(parent, name, size, cf, color, mat)
	local w = Instance.new("WedgePart")
	w.Name = name; w.Anchored = true; w.CanCollide = false; w.CanQuery = false; w.CanTouch = false; w.CastShadow = false
	w.Size = size; w.CFrame = cf; w.Color = color; w.Material = mat or Enum.Material.SmoothPlastic
	w.Parent = parent
	return w
end
-- a model the arena's existing animator moves: Swim = "circle" | "line" | "bob"
local function mover(parent, name, kind, attrs)
	local m = Instance.new("Model")
	m.Name = name; m:SetAttribute("Swim", kind)
	for k, v in pairs(attrs or {}) do m:SetAttribute(k, v) end
	m.Parent = parent
	return m
end

---------------------------------------------------------------- SPACE
local function buildSpace(root)
	local rnd = Random.new(7)
	local starCols = { rgb(255, 255, 255), rgb(200, 225, 255), rgb(255, 240, 200), rgb(220, 200, 255) }
	local function star(pos) P(root, "Star", Vector3.one * rnd:NextNumber(0.35, 0.85), CFrame.new(pos), starCols[rnd:NextInteger(1, 4)], N, Enum.PartType.Ball) end
	for _ = 1, 50 do star(Vector3.new(-123.4, rnd:NextNumber(22, 70), rnd:NextNumber(-62, 82))) end
	for _ = 1, 50 do star(Vector3.new(123.4, rnd:NextNumber(22, 70), rnd:NextNumber(-62, 82))) end
	for _ = 1, 40 do star(Vector3.new(rnd:NextNumber(-120, 120), rnd:NextNumber(22, 70), 83.4)) end
	for _ = 1, 30 do star(Vector3.new(rnd:NextNumber(-120, 120), rnd:NextNumber(55, 70), -63.4)) end
	for _ = 1, 60 do star(Vector3.new(rnd:NextNumber(-120, 120), 71.2, rnd:NextNumber(-60, 80))) end
	-- ringed planet
	local p1 = mover(root, "RingedPlanet", "bob", { Speed = 0.5, Amp = 1.5, Phase = 0 })
	local body = P(p1, "Planet", Vector3.one * 16, CFrame.new(-78, 54, -26), rgb(225, 160, 95), nil, Enum.PartType.Ball)
	P(p1, "Band", Vector3.new(16.2, 2.5, 16.2), CFrame.new(-78, 55.5, -26), rgb(190, 110, 70), nil, Enum.PartType.Ball)
	P(p1, "Ring", Vector3.new(0.3, 27, 27), CFrame.new(-78, 54, -26) * CFrame.Angles(math.rad(18), 0, 0) * UPRIGHT, rgb(245, 215, 165), nil, Enum.PartType.Cylinder, 0.25)
	p1.PrimaryPart = body
	-- earth-like planet
	local p2 = mover(root, "BluePlanet", "bob", { Speed = 0.6, Amp = 1.2, Phase = 2 })
	local e = P(p2, "Planet", Vector3.one * 12, CFrame.new(80, 55, 26), rgb(60, 130, 255), nil, Enum.PartType.Ball)
	for i = 1, 5 do P(p2, "Land", Vector3.one * rnd:NextNumber(4, 6), CFrame.new(80, 55, 26) * CFrame.Angles(rnd:NextNumber(0, 6), rnd:NextNumber(0, 6), 0) * CFrame.new(0, 0, 4.2), rgb(80, 200, 110), nil, Enum.PartType.Ball) end
	p2.PrimaryPart = e
	-- red planet + moon
	local p3 = mover(root, "RedPlanet", "bob", { Speed = 0.7, Amp = 1, Phase = 4 })
	p3.PrimaryPart = P(p3, "Planet", Vector3.one * 9, CFrame.new(98, 47, -38), rgb(230, 95, 60), nil, Enum.PartType.Ball)
	local p4 = mover(root, "Moon", "bob", { Speed = 0.45, Amp = 1.4, Phase = 1 })
	p4.PrimaryPart = P(p4, "Moon", Vector3.one * 11, CFrame.new(-96, 52, 48), rgb(205, 205, 215), Enum.Material.Slate, Enum.PartType.Ball)
	for i = 1, 6 do P(p4, "Crater", Vector3.one * rnd:NextNumber(1.5, 3), CFrame.new(-96, 52, 48) * CFrame.Angles(rnd:NextNumber(0, 6), rnd:NextNumber(0, 6), 0) * CFrame.new(0, 0, 4.9), rgb(150, 150, 165), Enum.Material.Slate, Enum.PartType.Ball) end
	-- satellite circling overhead
	local sat = mover(root, "Satellite", "circle", { Radius = 36, Speed = 0.22, Phase = 0 })
	local c = CFrame.new(0, 60, 18)
	sat.PrimaryPart = P(sat, "SatBody", Vector3.new(3, 3, 4), c, rgb(210, 210, 220), METAL)
	for _, s in ipairs({ -1, 1 }) do P(sat, "SolarPanel", Vector3.new(8, 0.2, 3), c * CFrame.new(s * 5.8, 0, 0), rgb(60, 120, 255), N) end
	P(sat, "Dish", Vector3.new(0.4, 3, 3), c * CFrame.new(0, 2, 0) * UPRIGHT, rgb(240, 240, 250), METAL, Enum.PartType.Cylinder)
	-- rockets in the stage wings
	for _, sx in ipairs({ -1, 1 }) do
		local x, z = sx * 104, -22
		P(root, "RocketBody", Vector3.new(22, 5, 5), CFrame.new(x, 12, z) * UPRIGHT, rgb(245, 245, 250), METAL, Enum.PartType.Cylinder)
		for i, d in ipairs({ 4.2, 3.2, 2, 0.9 }) do P(root, "RocketNose", Vector3.new(1.4, d, d), CFrame.new(x, 23.6 + i * 1.3, z) * UPRIGHT, rgb(255, 70, 90), nil, Enum.PartType.Cylinder) end
		P(root, "RocketWindow", Vector3.one * 2, CFrame.new(x, 17, z) * CFrame.lookAt(Vector3.zero, Vector3.new(-sx, 0, 1)) * CFrame.new(0, 0, -2.3), rgb(90, 220, 255), N, Enum.PartType.Ball)
		for a = 0, 2 do W(root, "RocketFin", Vector3.new(0.5, 6, 4), CFrame.new(x, 4, z) * CFrame.Angles(0, math.rad(a * 120), 0) * CFrame.new(0, 0, -3.8) * CFrame.Angles(0, math.rad(180), 0), rgb(255, 70, 90)) end
		local flame = P(root, "RocketFlame", Vector3.new(2.4, 3.6, 3.6), CFrame.new(x, 0.6, z) * UPRIGHT, rgb(255, 160, 40), N, Enum.PartType.Cylinder)
		local f = Instance.new("Fire"); f.Size = 6; f.Heat = 8; f.Color = rgb(255, 140, 40); f.SecondaryColor = rgb(255, 230, 120); f.Parent = flame
	end
end

---------------------------------------------------------------- CANDY
local function buildCandy(root)
	local rnd = Random.new(11)
	local bright = { rgb(255, 90, 170), rgb(120, 210, 255), rgb(255, 220, 90), rgb(140, 235, 170), rgb(190, 140, 255), rgb(255, 150, 90) }
	-- giant lollipops along both side walls
	for _, sx in ipairs({ -1, 1 }) do
		for i, z in ipairs({ -40, -4, 32, 68 }) do
			local x = sx * 118.5
			P(root, "LolliStick", Vector3.new(34, 1.4, 1.4), CFrame.new(x, 17, z) * UPRIGHT, rgb(255, 255, 255), nil, Enum.PartType.Cylinder)
			local face = CFrame.new(x, 38, z)
			P(root, "LolliDisc", Vector3.new(1.2, 14, 14), face, bright[(i + (sx > 0 and 2 or 0)) % #bright + 1], nil, Enum.PartType.Cylinder)
			P(root, "LolliSwirl", Vector3.new(1.3, 9, 9), face, rgb(255, 255, 255), nil, Enum.PartType.Cylinder)
			P(root, "LolliCore", Vector3.new(1.4, 4.5, 4.5), face, bright[(i + 3) % #bright + 1], nil, Enum.PartType.Cylinder)
		end
	end
	-- candy canes in the back corners
	for _, sx in ipairs({ -1, 1 }) do
		local x, z = sx * 116, -55
		for i = 0, 14 do P(root, "Cane", Vector3.new(2, 2.2, 2.2), CFrame.new(x, 1 + i * 2, z) * UPRIGHT, i % 2 == 0 and rgb(240, 40, 60) or rgb(255, 255, 255), nil, Enum.PartType.Cylinder) end
		for i = 0, 7 do
			local th = math.rad(i * 180 / 7)
			P(root, "CaneHook", Vector3.one * 2.4, CFrame.new(x + sx * 3 - sx * 3 * math.cos(th), 30 + 3 * math.sin(th), z), i % 2 == 0 and rgb(240, 40, 60) or rgb(255, 255, 255), nil, Enum.PartType.Ball)
		end
	end
	-- gumdrops and giant cupcakes in the stage wings
	for _, sx in ipairs({ -1, 1 }) do
		for i = 1, 5 do
			local d = rnd:NextNumber(4, 6.5)
			P(root, "Gumdrop", Vector3.new(d, d * 0.9, d), CFrame.new(sx * rnd:NextNumber(90, 116), d * 0.25, rnd:NextNumber(-32, -6)), bright[rnd:NextInteger(1, #bright)], GLASS, Enum.PartType.Ball, 0.1)
		end
		local x, z = sx * 98, -14
		P(root, "CupcakeCup", Vector3.new(7, 9, 9), CFrame.new(x, 3.5, z) * UPRIGHT, rgb(255, 140, 190), nil, Enum.PartType.Cylinder)
		for a = 0, 11 do P(root, "CupRidge", Vector3.new(7.1, 0.6, 0.6), CFrame.new(x, 3.5, z) * CFrame.Angles(0, math.rad(a * 30), 0) * CFrame.new(0, 0, 4.5) * UPRIGHT, rgb(255, 255, 255)) end
		for k, s in ipairs({ 10, 8, 5.5 }) do P(root, "Frosting", Vector3.new(s, s * 0.6, s), CFrame.new(x, 7 + k * 2, z), rgb(255, 245, 250), nil, Enum.PartType.Ball) end
		P(root, "Cherry", Vector3.one * 2, CFrame.new(x, 14.6, z), rgb(230, 30, 60), nil, Enum.PartType.Ball)
	end
	-- wrapped sweets floating overhead
	for i = 1, 10 do
		local pos = Vector3.new((i % 2 == 0 and 1 or -1) * rnd:NextNumber(40, 105), rnd:NextNumber(48, 58), rnd:NextNumber(-40, 72))
		local m = mover(root, "Sweet", "bob", { Speed = rnd:NextNumber(0.6, 1.1), Amp = 1.6, Phase = i })
		local col = bright[(i % #bright) + 1]
		m.PrimaryPart = P(m, "Candy", Vector3.new(4, 3, 3), CFrame.new(pos), col, nil, Enum.PartType.Ball)
		for _, s in ipairs({ -1, 1 }) do W(m, "Wrapper", Vector3.new(0.3, 3, 2.4), CFrame.new(pos + Vector3.new(s * 2.8, 0, 0)) * CFrame.Angles(0, math.rad(s > 0 and 90 or -90), 0), col) end
	end
end

---------------------------------------------------------------- JUNGLE
local function palm(root, x, z, h, lean)
	local base = CFrame.new(x, 0, z)
	local segs = math.floor(h / 3)
	for i = 0, segs do
		local cf = base * CFrame.Angles(0, 0, math.rad(lean * i / segs)) * CFrame.new(0, i * 3 + 1.5, 0)
		P(root, "Trunk", Vector3.new(3.2, 2.6 - i * 0.05, 2.6 - i * 0.05), cf * UPRIGHT, i % 2 == 0 and rgb(120, 85, 50) or rgb(100, 70, 40), Enum.Material.Wood, Enum.PartType.Cylinder)
	end
	local top = (base * CFrame.Angles(0, 0, math.rad(lean)) * CFrame.new(0, segs * 3 + 3, 0)).Position
	for a = 0, 6 do
		P(root, "PalmLeaf", Vector3.new(11, 0.3, 2.6), CFrame.new(top) * CFrame.Angles(0, math.rad(a * 51), 0) * CFrame.Angles(0, 0, math.rad(-28)) * CFrame.new(5, 0, 0), a % 2 == 0 and rgb(60, 170, 70) or rgb(40, 140, 60), Enum.Material.Grass)
	end
	for a = 0, 2 do P(root, "Coconut", Vector3.one * 1.4, CFrame.new(top) * CFrame.Angles(0, math.rad(a * 120), 0) * CFrame.new(0.9, -0.8, 0), rgb(110, 75, 40), nil, Enum.PartType.Ball) end
end
local function buildJungle(root)
	local rnd = Random.new(5)
	for _, sx in ipairs({ -1, 1 }) do
		for i, z in ipairs({ -48, -12, 26, 64 }) do palm(root, sx * 117, z, rnd:NextNumber(28, 36), -sx * rnd:NextNumber(6, 12)) end
		palm(root, sx * 100, -26, 24, -sx * 8)
		-- rocks + bushes in the wings
		for i = 1, 4 do P(root, "Rock", Vector3.new(rnd:NextNumber(4, 7), rnd:NextNumber(3, 5), rnd:NextNumber(4, 7)), CFrame.new(sx * rnd:NextNumber(86, 116), 1, rnd:NextNumber(-34, -4)), rgb(120, 120, 115), Enum.Material.Slate, Enum.PartType.Ball) end
		for i = 1, 5 do P(root, "Bush", Vector3.one * rnd:NextNumber(4, 6), CFrame.new(sx * rnd:NextNumber(84, 118), 1.5, rnd:NextNumber(-34, -2)), rgb(50, 150, 60), Enum.Material.Grass, Enum.PartType.Ball) end
		-- waterfall in the back corner
		local x = sx * 116
		local fall = P(root, "Waterfall", Vector3.new(9, 52, 0.6), CFrame.new(x, 26, -62.6), rgb(120, 210, 255), N, nil, 0.35)
		local mist = Instance.new("ParticleEmitter"); mist.Rate = 18; mist.Lifetime = NumberRange.new(1.5, 2.5); mist.Speed = NumberRange.new(2, 5); mist.SpreadAngle = Vector2.new(40, 40)
		mist.Size = NumberSequence.new(1.5, 4); mist.Transparency = NumberSequence.new(0.5, 1); mist.Color = ColorSequence.new(rgb(220, 245, 255)); mist.EmissionDirection = Enum.NormalId.Front
		local mp = P(root, "Mist", Vector3.new(9, 1, 1), CFrame.new(x, 1, -61), rgb(255, 255, 255), nil, nil, 1); mist.Parent = mp
		for i = 1, 5 do P(root, "FallRock", Vector3.one * rnd:NextNumber(3, 5), CFrame.new(x + rnd:NextNumber(-6, 6), 1, -60 + rnd:NextNumber(-1, 3)), rgb(100, 100, 100), Enum.Material.Slate, Enum.PartType.Ball) end
	end
	-- vines hanging from the ceiling
	for i = 1, 28 do
		local x = (i % 2 == 0 and 1 or -1) * rnd:NextNumber(30, 120)
		local z = rnd:NextNumber(-60, 80)
		local len = rnd:NextNumber(8, 20)
		P(root, "Vine", Vector3.new(0.5, len, 0.5), CFrame.new(x, 71.5 - len / 2, z), rgb(50, 130, 55), Enum.Material.Grass)
		for k = 1, 3 do P(root, "VineLeaf", Vector3.new(1.6, 0.2, 1), CFrame.new(x, 71.5 - len * k / 3.5, z) * CFrame.Angles(0, rnd:NextNumber(0, 6), math.rad(20)), rgb(70, 180, 70), Enum.Material.Grass) end
	end
	-- parrots flying circles overhead
	local birdCols = { { rgb(230, 40, 50), rgb(255, 210, 40) }, { rgb(40, 120, 255), rgb(255, 230, 80) }, { rgb(60, 200, 90), rgb(255, 80, 60) }, { rgb(255, 140, 30), rgb(60, 180, 255) } }
	for i, c in ipairs({ Vector3.new(-62, 50, 18), Vector3.new(64, 54, 6), Vector3.new(-40, 58, -20), Vector3.new(44, 47, 40) }) do
		local m = mover(root, "Parrot", "circle", { Radius = 16 + i * 3, Speed = (i % 2 == 0 and 0.45 or -0.4), Phase = i * 1.5 })
		m.PrimaryPart = P(m, "Body", Vector3.new(1.6, 1.6, 3.4), CFrame.new(c), birdCols[i][1], nil, Enum.PartType.Ball)
		P(m, "Head", Vector3.one * 1.3, CFrame.new(c + Vector3.new(0, 0.6, -1.6)), birdCols[i][1], nil, Enum.PartType.Ball)
		W(m, "Beak", Vector3.new(0.4, 0.6, 0.7), CFrame.new(c + Vector3.new(0, 0.4, -2.4)), rgb(255, 200, 60))
		for _, s in ipairs({ -1, 1 }) do P(m, "Wing", Vector3.new(3, 0.25, 1.6), CFrame.new(c + Vector3.new(s * 1.9, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(s * 15)), birdCols[i][2]) end
		P(m, "Tail", Vector3.new(0.8, 0.2, 2.6), CFrame.new(c + Vector3.new(0, 0, 2.6)), birdCols[i][2])
	end
end

---------------------------------------------------------------- WINTER
local function pine(root, x, z, h)
	P(root, "PineTrunk", Vector3.new(4, 2, 2), CFrame.new(x, 2, z) * UPRIGHT, rgb(110, 75, 45), Enum.Material.Wood, Enum.PartType.Cylinder)
	local tiers = 5
	for i = 0, tiers - 1 do
		local d = (h * 0.55) * (1 - i / tiers) + 2
		local y = 4 + i * (h - 4) / tiers
		P(root, "PineTier", Vector3.new((h - 4) / tiers + 0.8, d, d), CFrame.new(x, y + 1.5, z) * UPRIGHT, rgb(30, 110, 70), nil, Enum.PartType.Cylinder)
		P(root, "PineSnow", Vector3.new(0.6, d * 0.8, d * 0.8), CFrame.new(x, y + 1.5 + (h - 4) / tiers / 2 + 0.6, z) * UPRIGHT, rgb(250, 252, 255), Enum.Material.Snow, Enum.PartType.Cylinder)
	end
	P(root, "PineStar", Vector3.one * 1.6, CFrame.new(x, h + 3, z), rgb(255, 230, 90), N, Enum.PartType.Ball)
end
local function buildWinter(root)
	local rnd = Random.new(3)
	-- falling snow over the whole studio
	local cloud = P(root, "SnowCloud", Vector3.new(236, 1, 146), CFrame.new(0, 70.5, 10), rgb(255, 255, 255), nil, nil, 1)
	local snow = Instance.new("ParticleEmitter")
	snow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	snow.Rate = 90; snow.Lifetime = NumberRange.new(12, 15); snow.Speed = NumberRange.new(4, 6)
	snow.EmissionDirection = Enum.NormalId.Bottom; snow.SpreadAngle = Vector2.new(12, 12)
	snow.Size = NumberSequence.new(0.45); snow.Color = ColorSequence.new(rgb(255, 255, 255)); snow.LightEmission = 0.4
	snow.RotSpeed = NumberRange.new(-60, 60); snow.Parent = cloud
	-- snowy pines along the side walls and in the wings
	for _, sx in ipairs({ -1, 1 }) do
		for i, z in ipairs({ -50, -12, 28, 68 }) do pine(root, sx * 117, z, rnd:NextNumber(26, 34)) end
		pine(root, sx * 110, -30, 22)
		-- snowman in the wings
		local x, z = sx * 96, -18
		local look = CFrame.lookAt(Vector3.new(x, 0, z), Vector3.new(0, 0, 30))
		for k, d in ipairs({ { 7, 3.2 }, { 5.2, 8.4 }, { 3.8, 12.4 } }) do P(root, "SnowBall", Vector3.one * d[1], CFrame.new(x, d[2], z), rgb(250, 252, 255), Enum.Material.Snow, Enum.PartType.Ball) end
		local face = look * CFrame.new(0, 12.6, -1.8)
		for _, s in ipairs({ -0.7, 0.7 }) do P(root, "Coal", Vector3.one * 0.6, face * CFrame.new(s, 0.4, 0), rgb(30, 30, 30), nil, Enum.PartType.Ball) end
		P(root, "Carrot", Vector3.new(2, 0.5, 0.5), face * CFrame.new(0, -0.2, -0.8) * CFrame.Angles(0, math.rad(90), 0), rgb(255, 130, 30), nil, Enum.PartType.Cylinder)
		P(root, "Scarf", Vector3.new(1.2, 5, 5), CFrame.new(x, 10.6, z) * UPRIGHT, rgb(230, 40, 60), nil, Enum.PartType.Cylinder)
		P(root, "HatBrim", Vector3.new(0.4, 4.4, 4.4), CFrame.new(x, 14.3, z) * UPRIGHT, rgb(25, 25, 30), nil, Enum.PartType.Cylinder)
		P(root, "HatTop", Vector3.new(3, 3, 3), CFrame.new(x, 15.9, z) * UPRIGHT, rgb(25, 25, 30), nil, Enum.PartType.Cylinder)
	end
	-- icicles along the top of the side walls
	for _, sx in ipairs({ -1, 1 }) do
		for z = -60, 82, 5 do
			local len = rnd:NextNumber(2.5, 5)
			W(root, "Icicle", Vector3.new(0.8, len, 1.2), CFrame.new(sx * 123.2, 71 - len / 2, z) * CFrame.Angles(math.rad(180), 0, 0), rgb(200, 235, 255), GLASS).Transparency = 0.3
		end
	end
	-- giant snowflakes floating overhead
	for i = 1, 10 do
		local pos = Vector3.new((i % 2 == 0 and 1 or -1) * rnd:NextNumber(38, 105), rnd:NextNumber(46, 58), rnd:NextNumber(-40, 72))
		local m = mover(root, "Snowflake", "bob", { Speed = rnd:NextNumber(0.5, 0.9), Amp = 1.8, Phase = i })
		m.PrimaryPart = P(m, "FlakeCore", Vector3.one * 1.6, CFrame.new(pos), rgb(220, 245, 255), N, Enum.PartType.Ball)
		for a = 0, 2 do
			local arm = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(a * 60))
			P(m, "FlakeArm", Vector3.new(7, 0.4, 0.4), arm, rgb(200, 240, 255), N)
			for _, s in ipairs({ -1, 1 }) do P(m, "FlakeTip", Vector3.new(1.8, 0.3, 0.3), arm * CFrame.new(s * 2.6, 0, 0) * CFrame.Angles(0, 0, math.rad(45)), rgb(200, 240, 255), N) end
		end
	end
end

---------------------------------------------------------------- extra life for each world
-- More decorations, creatures and weather on top of the basic theme. New mover kinds the
-- client animates: "swing" (pendulum from the model's pivot), "shoot" (shooting star dash),
-- and any mover can also turn on its own axis with a SpinSpeed attribute.
local function E(parent, name, size, cf, color, mat, transparency) -- ellipsoid
	local p = P(parent, name, size, cf, color, mat, nil, transparency)
	local m = Instance.new("SpecialMesh"); m.MeshType = Enum.MeshType.Sphere; m.Parent = p
	return p
end
local function emitter(parent, name, size, cf, props)
	local holder = P(parent, name, size, cf, rgb(255, 255, 255), nil, nil, 1)
	local pe = Instance.new("ParticleEmitter")
	pe.Shape = Enum.ParticleEmitterShape.Box; pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	for k, v in pairs(props) do pe[k] = v end
	pe.Parent = holder
	return pe
end
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local function ns(a, b) return NumberSequence.new(a, b or a) end

-- JUNGLE ----------------------------------------------------------------
local function monkey(parent, hand, fur, face)
	-- hangs by its right hand from `hand` (a CFrame), facing the audience (+Z)
	P(parent, "Arm", Vector3.new(2.6, 0.7, 0.7), hand * CFrame.new(0.6, -1.3, 0) * UPRIGHT, fur, nil, Enum.PartType.Cylinder)
	P(parent, "Hand", Vector3.one * 0.8, hand * CFrame.new(0.6, 0, 0), face, nil, Enum.PartType.Ball)
	local body = hand * CFrame.new(0.5, -4.3, 0)
	E(parent, "Body", Vector3.new(2.6, 3.3, 2.2), body, fur)
	E(parent, "Belly", Vector3.new(1.7, 2.3, 0.6), body * CFrame.new(0, -0.2, 1.0), face)
	local head = hand * CFrame.new(-0.6, -2.3, 0.2)
	P(parent, "Head", Vector3.one * 2.4, head, fur, nil, Enum.PartType.Ball)
	E(parent, "Face", Vector3.new(1.8, 1.5, 0.7), head * CFrame.new(0, -0.2, 1.0), face)
	for _, s in ipairs({ -1, 1 }) do
		P(parent, "Eye", Vector3.one * 0.38, head * CFrame.new(s * 0.42, 0.25, 1.25), rgb(25, 20, 20), nil, Enum.PartType.Ball)
		P(parent, "Ear", Vector3.one * 0.95, head * CFrame.new(s * 1.25, 0.2, 0), face, nil, Enum.PartType.Ball)
	end
	E(parent, "Smile", Vector3.new(0.8, 0.22, 0.2), head * CFrame.new(0, -0.55, 1.33), rgb(150, 60, 60))
	P(parent, "OtherArm", Vector3.new(2.6, 0.7, 0.7), body * CFrame.new(-1.7, 0.7, 0) * CFrame.Angles(0, 0, math.rad(-35)), fur, nil, Enum.PartType.Cylinder)
	for _, s in ipairs({ -1, 1 }) do
		P(parent, "Leg", Vector3.new(2.2, 0.75, 0.75), body * CFrame.new(s * 0.7, -2.4, 0.2) * CFrame.Angles(0, 0, math.rad(90 + s * 20)), fur, nil, Enum.PartType.Cylinder)
		P(parent, "Foot", Vector3.new(1, 0.6, 1.2), body * CFrame.new(s * 1.1, -3.4, 0.4), face, nil, Enum.PartType.Ball)
	end
	for i = 0, 7 do -- curly tail
		local a = i * 0.8
		P(parent, "Tail", Vector3.one * 0.55, body * CFrame.new(0.9 + math.sin(a) * 0.9, -1.4 - i * 0.35, -1.0 - math.cos(a) * 0.5), fur, nil, Enum.PartType.Ball)
	end
end
local function jungleExtras(root)
	local rnd = Random.new(21)
	local leafCols = { rgb(40, 140, 55), rgb(60, 170, 70), rgb(30, 115, 50), rgb(80, 185, 80) }
	-- leafy canopy hanging under the ceiling
	for i = 1, 70 do
		local x, z
		if i <= 50 then
			local side = i % 2 == 0 and 1 or -1
			x, z = side * rnd:NextNumber(70, 122), rnd:NextNumber(-62, 82)
		else
			x, z = rnd:NextNumber(-120, 120), rnd:NextNumber(-62, -40)
		end
		E(root, "Canopy", Vector3.new(rnd:NextNumber(10, 18), rnd:NextNumber(3, 6), rnd:NextNumber(8, 15)), CFrame.new(x, rnd:NextNumber(67.5, 70.5), z) * CFrame.Angles(0, rnd:NextNumber(0, 6), 0), leafCols[rnd:NextInteger(1, 4)], Enum.Material.Grass)
	end
	-- thick curtains of vines down the side walls and behind the stage
	local function vine(x, z, top, len)
		P(root, "Vine", Vector3.new(0.45, len, 0.45), CFrame.new(x, top - len / 2, z), rgb(45, 120, 50), Enum.Material.Grass)
		for y = top - 2, top - len, -3.5 do
			E(root, "VineLeaf", Vector3.new(1.8, 0.3, 1.1), CFrame.new(x, y, z) * CFrame.Angles(0, rnd:NextNumber(0, 6), math.rad(rnd:NextNumber(-30, 30))), leafCols[rnd:NextInteger(1, 4)], Enum.Material.Grass)
		end
	end
	for z = -60, 82, 4.5 do
		vine(-122, z + rnd:NextNumber(-1, 1), 71, rnd:NextNumber(10, 34))
		vine(122, z + rnd:NextNumber(-1, 1), 71, rnd:NextNumber(10, 34))
	end
	for x = -118, 118, 6 do vine(x + rnd:NextNumber(-2, 2), -61.5, 71, rnd:NextNumber(8, 26)) end
	-- monkeys swinging from vines over the audience and stage wings
	local furs = { { rgb(120, 75, 40), rgb(235, 195, 145) }, { rgb(95, 60, 35), rgb(225, 180, 130) }, { rgb(140, 90, 50), rgb(245, 210, 160) } }
	local spots = { Vector3.new(-48, 71, 30), Vector3.new(50, 71, 46), Vector3.new(-22, 71, 64), Vector3.new(26, 71, 18), Vector3.new(-92, 71, -18), Vector3.new(94, 71, -8), Vector3.new(-70, 71, 56), Vector3.new(74, 71, 70) }
	for i, top in ipairs(spots) do
		local len = rnd:NextNumber(11, 16)
		local m = mover(root, "Monkey", "swing", { SwingDeg = rnd:NextNumber(10, 18), Speed = rnd:NextNumber(1.0, 1.5), Phase = i * 1.3 })
		m.PrimaryPart = P(m, "Anchor", Vector3.one * 0.5, CFrame.new(top), rgb(45, 120, 50), nil, nil, 1)
		P(m, "Vine", Vector3.new(0.5, len, 0.5), CFrame.new(top - Vector3.new(0, len / 2, 0)), rgb(45, 120, 50), Enum.Material.Grass)
		for k = 1, 3 do E(m, "VineLeaf", Vector3.new(1.8, 0.3, 1.1), CFrame.new(top - Vector3.new(0, len * k / 4, 0)) * CFrame.Angles(0, k, math.rad(20)), leafCols[k], Enum.Material.Grass) end
		local f = furs[(i % #furs) + 1]
		monkey(m, CFrame.new(top - Vector3.new(0, len, 0)) * CFrame.Angles(0, (i % 2 == 0) and math.rad(-15) or math.rad(15), 0), f[1], f[2])
	end
	-- snakes coiled around a few vines
	for i, at in ipairs({ Vector3.new(-36, 71, 50), Vector3.new(38, 71, 32), Vector3.new(-100, 71, 30), Vector3.new(102, 71, 50) }) do
		local len = 20
		P(root, "Vine", Vector3.new(0.6, len, 0.6), CFrame.new(at - Vector3.new(0, len / 2, 0)), rgb(45, 120, 50), Enum.Material.Grass)
		local col1, col2 = (i % 2 == 0) and rgb(60, 200, 80) or rgb(240, 200, 40), rgb(30, 110, 40)
		local last
		for k = 0, 22 do
			local a = k * 0.75
			local pos = at + Vector3.new(math.cos(a) * 0.9, -4 - k * 0.5, math.sin(a) * 0.9)
			P(root, "Snake", Vector3.one * 0.95, CFrame.new(pos), k % 3 == 0 and col2 or col1, nil, Enum.PartType.Ball)
			last = pos
		end
		local head = CFrame.lookAt(last + Vector3.new(0.4, -0.6, 0.9), last + Vector3.new(0.4, -0.6, 4))
		E(root, "SnakeHead", Vector3.new(1.3, 0.9, 1.8), head, col1)
		for _, s in ipairs({ -1, 1 }) do P(root, "SnakeEye", Vector3.one * 0.3, head * CFrame.new(s * 0.45, 0.35, -0.5), rgb(20, 20, 20), nil, Enum.PartType.Ball) end
		W(root, "Tongue", Vector3.new(0.12, 0.12, 1.0), head * CFrame.new(0, -0.1, -1.3), rgb(230, 40, 60))
	end
	-- a lazy sloth hanging under a branch in each wing, with toucans perched on top
	for _, sx in ipairs({ -1, 1 }) do
		local b = CFrame.new(sx * 92, 64, -28)
		P(root, "Branch", Vector3.new(34, 2.2, 2.2), b, rgb(105, 72, 42), Enum.Material.Wood, Enum.PartType.Cylinder)
		for k = 1, 4 do E(root, "BranchLeaves", Vector3.new(7, 3, 5), b * CFrame.new(-14 + k * 6, 1.6, rnd:NextNumber(-1, 1)), leafCols[k], Enum.Material.Grass) end
		local sloth = mover(root, "Sloth", "bob", { Speed = 0.35, Amp = 0.5, Phase = sx })
		local body = b * CFrame.new(sx * -4, -4.2, 0)
		sloth.PrimaryPart = E(sloth, "Body", Vector3.new(4.6, 3.2, 3), body, rgb(150, 125, 95))
		for _, s in ipairs({ -1.6, 1.6 }) do for _, t in ipairs({ -0.8, 0.8 }) do P(sloth, "Limb", Vector3.new(4, 0.8, 0.8), body * CFrame.new(s, 2.1, t) * UPRIGHT, rgb(140, 115, 85), nil, Enum.PartType.Cylinder) end end
		local head = body * CFrame.new(sx * -2.8, -0.4, 0.4)
		P(sloth, "Head", Vector3.one * 2.4, head, rgb(150, 125, 95), nil, Enum.PartType.Ball)
		E(sloth, "Mask", Vector3.new(1.9, 1.4, 0.6), head * CFrame.new(0, 0, 1.0), rgb(235, 220, 190))
		for _, s in ipairs({ -1, 1 }) do
			E(sloth, "EyePatch", Vector3.new(0.7, 0.45, 0.2), head * CFrame.new(s * 0.45, 0.1, 1.3) * CFrame.Angles(0, 0, math.rad(s * -20)), rgb(70, 50, 35))
			P(sloth, "Eye", Vector3.one * 0.22, head * CFrame.new(s * 0.45, 0.1, 1.42), rgb(10, 10, 10), nil, Enum.PartType.Ball)
		end
		for k, x in ipairs({ -10, 9 }) do
			local perch = b * CFrame.new(x, 2.9, 0) * CFrame.Angles(0, math.rad(sx * 70), 0)
			E(root, "ToucanBody", Vector3.new(1.6, 2.2, 1.6), perch, rgb(20, 20, 25))
			E(root, "ToucanChest", Vector3.new(1.1, 1.1, 0.5), perch * CFrame.new(0, 0.4, -0.7), rgb(255, 230, 90))
			P(root, "ToucanHead", Vector3.one * 1.2, perch * CFrame.new(0, 1.3, -0.1), rgb(20, 20, 25), nil, Enum.PartType.Ball)
			E(root, "ToucanBeak", Vector3.new(0.6, 0.65, 2.2), perch * CFrame.new(0, 1.2, -1.4), rgb(255, 140, 30))
			E(root, "BeakTip", Vector3.new(0.4, 0.45, 0.6), perch * CFrame.new(0, 1.15, -2.4), rgb(230, 40, 50))
		end
	end
	-- butterflies fluttering over the seats
	local wingCols = { rgb(255, 120, 40), rgb(80, 160, 255), rgb(255, 80, 180), rgb(255, 220, 60), rgb(150, 90, 255) }
	for i = 1, 12 do
		local c = Vector3.new(rnd:NextNumber(-90, 90), rnd:NextNumber(24, 44), rnd:NextNumber(-20, 72))
		local m = mover(root, "Butterfly", "circle", { Radius = rnd:NextNumber(4, 9), Speed = rnd:NextNumber(0.7, 1.3) * (i % 2 == 0 and 1 or -1), Phase = i })
		m.PrimaryPart = P(m, "Body", Vector3.new(0.3, 0.3, 1.4), CFrame.new(c), rgb(40, 30, 30))
		local col = wingCols[(i % #wingCols) + 1]
		for _, s in ipairs({ -1, 1 }) do
			E(m, "Wing", Vector3.new(1.8, 0.1, 1.5), CFrame.new(c + Vector3.new(s * 0.9, 0.3, -0.2)) * CFrame.Angles(0, 0, math.rad(s * 30)), col, N)
			E(m, "Wing", Vector3.new(1.2, 0.1, 1.0), CFrame.new(c + Vector3.new(s * 0.7, 0.2, 0.7)) * CFrame.Angles(0, 0, math.rad(s * 30)), col)
		end
	end
	-- tropical flowers and big leaves in the wings and along the walls
	local petal = { rgb(255, 70, 90), rgb(255, 120, 180), rgb(255, 160, 40), rgb(230, 60, 200) }
	for i = 1, 26 do
		local side = i % 2 == 0 and 1 or -1
		local pos = (i <= 12) and Vector3.new(side * rnd:NextNumber(84, 116), 1, rnd:NextNumber(-36, -2)) or Vector3.new(side * rnd:NextNumber(110, 121), 1, rnd:NextNumber(-50, 80))
		local col = petal[rnd:NextInteger(1, #petal)]
		E(root, "BigLeaf", Vector3.new(6, 0.4, 3), CFrame.new(pos + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, rnd:NextNumber(0, 6), math.rad(25)), leafCols[rnd:NextInteger(1, 4)], Enum.Material.Grass)
		for a = 0, 4 do E(root, "Petal", Vector3.new(1.6, 0.3, 1.0), CFrame.new(pos + Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, math.rad(a * 72), 0) * CFrame.new(0.8, 0, 0) * CFrame.Angles(0, 0, math.rad(20)), col) end
		P(root, "FlowerHeart", Vector3.one * 0.7, CFrame.new(pos + Vector3.new(0, 2.8, 0)), rgb(255, 230, 80), N, Enum.PartType.Ball)
	end
	-- soft light shafts through the canopy
	for i = 1, 6 do
		P(root, "LightShaft", Vector3.new(9, 74, 0.3), CFrame.new(-75 + i * 22, 34, rnd:NextNumber(-40, 40)) * CFrame.Angles(math.rad(14), math.rad(rnd:NextNumber(-20, 20)), math.rad(-18)), rgb(255, 245, 190), N, nil, 0.93)
	end
	-- fireflies everywhere + low mist rolling over the stage
	emitter(root, "Fireflies", Vector3.new(220, 40, 130), CFrame.new(0, 26, 12), { Texture = SPARK, Rate = 40, Lifetime = NumberRange.new(4, 7), Speed = NumberRange.new(0.3, 1.2), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.45), NumberSequenceKeypoint.new(0.5, 0.15), NumberSequenceKeypoint.new(0.8, 0.45), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(rgb(220, 255, 120)), LightEmission = 1, Acceleration = Vector3.new(0, 0.2, 0) })
	emitter(root, "Mist", Vector3.new(200, 1, 70), CFrame.new(0, 1, -20), { Texture = SMOKE, Rate = 14, Lifetime = NumberRange.new(6, 9), Speed = NumberRange.new(0.3, 0.8), SpreadAngle = Vector2.new(60, 60),
		Size = ns(9, 14), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.82), NumberSequenceKeypoint.new(1, 1) }), Color = ColorSequence.new(rgb(225, 245, 225)), EmissionDirection = Enum.NormalId.Top })
end

-- SPACE -----------------------------------------------------------------
local function spaceExtras(root)
	local rnd = Random.new(31)
	-- the planets turn slowly
	for _, m in ipairs(root:GetChildren()) do
		if m:IsA("Model") and (m.Name == "RingedPlanet" or m.Name == "BluePlanet" or m.Name == "RedPlanet" or m.Name == "Moon") then
			m:SetAttribute("SpinSpeed", rnd:NextNumber(0.15, 0.35))
		end
	end
	-- a giant striped gas planet looming behind the stage, with its own moon in orbit
	local gp = mover(root, "GasGiant", "bob", { Speed = 0.25, Amp = 1, Phase = 1, SpinSpeed = 0.08 })
	local gc = CFrame.new(-60, 52, -55)
	gp.PrimaryPart = P(gp, "Planet", Vector3.one * 22, gc, rgb(250, 180, 120), nil, Enum.PartType.Ball)
	for k, c in ipairs({ rgb(230, 130, 90), rgb(255, 215, 160), rgb(210, 110, 80) }) do P(gp, "Stripe", Vector3.new(22.2, 2.2, 22.2), gc * CFrame.new(0, -6 + k * 3.4, 0), c, nil, Enum.PartType.Ball) end
	local gm = mover(root, "GiantMoon", "circle", { Radius = 17, Speed = 0.5, Phase = 0, SpinSpeed = 0.4 })
	gm.PrimaryPart = P(gm, "Moon", Vector3.one * 4, gc, rgb(200, 200, 215), Enum.Material.Slate, Enum.PartType.Ball)
	local bm = mover(root, "LittleMoon", "circle", { Radius = 11, Speed = -0.7, Phase = 2 })
	bm.PrimaryPart = P(bm, "Moon", Vector3.one * 2.6, CFrame.new(80, 55, 26), rgb(230, 230, 240), Enum.Material.Slate, Enum.PartType.Ball)
	-- an asteroid belt drifting round overhead
	for i = 1, 26 do
		local a = mover(root, "Asteroid", "circle", { Radius = rnd:NextNumber(52, 64), Speed = 0.05, Phase = i / 26 * math.pi * 2, SpinSpeed = rnd:NextNumber(-0.8, 0.8) })
		local c = CFrame.new(0, rnd:NextNumber(60, 66), 12)
		a.PrimaryPart = P(a, "Rock", Vector3.new(rnd:NextNumber(1.5, 3.5), rnd:NextNumber(1.2, 2.8), rnd:NextNumber(1.5, 3.5)), c * CFrame.Angles(rnd:NextNumber(0, 6), rnd:NextNumber(0, 6), 0), rgb(110, 100, 120), Enum.Material.Slate, Enum.PartType.Ball)
		if i % 3 == 0 then P(a, "Lump", Vector3.one * 1.4, c * CFrame.new(1, 0.4, 0), rgb(95, 85, 105), Enum.Material.Slate, Enum.PartType.Ball) end
	end
	-- a UFO buzzing round the studio
	local ufo = mover(root, "UFO", "circle", { Radius = 42, Speed = 0.32, Phase = 1 })
	local uc = CFrame.new(0, 56, 20)
	ufo.PrimaryPart = E(ufo, "Saucer", Vector3.new(11, 2.2, 11), uc, rgb(180, 185, 200), METAL)
	P(ufo, "Dome", Vector3.one * 4.6, uc * CFrame.new(0, 1.2, 0), rgb(120, 255, 220), GLASS, Enum.PartType.Ball, 0.3)
	E(ufo, "Alien", Vector3.new(1.4, 1.8, 1.4), uc * CFrame.new(0, 1.4, 0), rgb(110, 230, 90))
	for k = 0, 9 do
		local a = k / 10 * math.pi * 2
		P(ufo, "RimLight", Vector3.one * 0.7, uc * CFrame.new(math.cos(a) * 5.1, -0.1, math.sin(a) * 5.1), k % 2 == 0 and rgb(255, 230, 90) or rgb(90, 220, 255), N, Enum.PartType.Ball)
	end
	P(ufo, "TractorBeam", Vector3.new(12, 6, 6), uc * CFrame.new(0, -7, 0) * UPRIGHT, rgb(150, 255, 200), N, Enum.PartType.Cylinder, 0.85)
	-- a little astronaut floating and tumbling above the seats
	local astro = mover(root, "Astronaut", "bob", { Speed = 0.5, Amp = 2.5, Phase = 0, SpinSpeed = 0.25 })
	local ac = CFrame.new(-88, 44, 40)
	astro.PrimaryPart = P(astro, "Suit", Vector3.new(2.4, 2.8, 1.6), ac, rgb(240, 240, 245))
	P(astro, "Helmet", Vector3.one * 2.4, ac * CFrame.new(0, 2.4, 0), rgb(245, 245, 250), nil, Enum.PartType.Ball)
	E(astro, "Visor", Vector3.new(1.8, 1.3, 0.5), ac * CFrame.new(0, 2.4, -0.95), rgb(255, 190, 60), N)
	P(astro, "Pack", Vector3.new(2, 2.4, 1), ac * CFrame.new(0, 0.2, 1.2), rgb(170, 170, 185))
	for _, s in ipairs({ -1, 1 }) do
		P(astro, "Arm", Vector3.new(2.6, 0.9, 0.9), ac * CFrame.new(s * 1.8, 0.6, 0) * CFrame.Angles(0, 0, math.rad(s * 35)), rgb(240, 240, 245), nil, Enum.PartType.Cylinder)
		P(astro, "Leg", Vector3.new(2.6, 1, 1), ac * CFrame.new(s * 0.6, -2.4, 0) * CFrame.Angles(0, 0, math.rad(90 + s * 15)), rgb(240, 240, 245), nil, Enum.PartType.Cylinder)
	end
	P(astro, "Badge", Vector3.new(0.8, 0.5, 0.1), ac * CFrame.new(0.5, 0.6, -0.85), rgb(255, 80, 120), N)
	-- glowing nebula clouds on the walls and ceiling
	local neb = { rgb(255, 90, 200), rgb(140, 80, 255), rgb(60, 140, 255), rgb(90, 230, 255) }
	for i = 1, 6 do E(root, "Nebula", Vector3.new(2, rnd:NextNumber(22, 34), rnd:NextNumber(40, 70)), CFrame.new(-122.5, rnd:NextNumber(40, 56), -40 + i * 18), neb[(i % 4) + 1], N, 0.86) end
	for i = 1, 6 do E(root, "Nebula", Vector3.new(2, rnd:NextNumber(22, 34), rnd:NextNumber(40, 70)), CFrame.new(122.5, rnd:NextNumber(40, 56), -40 + i * 18), neb[((i + 1) % 4) + 1], N, 0.86) end
	for i = 1, 4 do E(root, "Nebula", Vector3.new(rnd:NextNumber(50, 80), rnd:NextNumber(24, 34), 2), CFrame.new(-90 + i * 36, 52, -62), neb[((i + 2) % 4) + 1], N, 0.86) end
	-- shooting stars dashing across the sky every few seconds
	for i = 1, 10 do
		local side = i % 2 == 0 and 1 or -1
		local start = Vector3.new(-side * rnd:NextNumber(70, 110), rnd:NextNumber(58, 69), rnd:NextNumber(-45, 70))
		local dir = Vector3.new(side, -rnd:NextNumber(0.15, 0.4), rnd:NextNumber(-0.3, 0.3)).Unit
		local m = mover(root, "ShootingStar", "shoot", { Dir = dir, Dist = rnd:NextNumber(80, 120), Dur = rnd:NextNumber(0.9, 1.5), Gap = rnd:NextNumber(2.5, 7), Phase = rnd:NextNumber(0, 10) })
		local head = P(m, "Head", Vector3.one * 1.1, CFrame.lookAt(start, start + dir), rgb(255, 255, 230), N, Enum.PartType.Ball)
		m.PrimaryPart = head
		local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 0.8, 0); a0.Parent = head
		local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -0.8, 0); a1.Parent = head
		local tr = Instance.new("Trail"); tr.Name = "Streak"; tr.Attachment0 = a0; tr.Attachment1 = a1; tr.Lifetime = 0.5; tr.FaceCamera = true; tr.LightEmission = 1
		tr.WidthScale = NumberSequence.new(1, 0); tr.Transparency = NumberSequence.new(0, 1)
		tr.Color = ColorSequence.new(rgb(255, 255, 255), (i % 3 == 0) and rgb(255, 160, 230) or rgb(140, 200, 255)); tr.Enabled = false; tr.Parent = head
	end
	-- twinkling star dust drifting down
	emitter(root, "StarDust", Vector3.new(230, 4, 140), CFrame.new(0, 66, 10), { Texture = SPARK, Rate = 30, Lifetime = NumberRange.new(8, 12), Speed = NumberRange.new(0.5, 1.5), EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(30, 30),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(0.6, 0.1), NumberSequenceKeypoint.new(1, 0.3) }),
		Color = ColorSequence.new(rgb(220, 230, 255), rgb(255, 200, 255)), LightEmission = 1 })
end

-- WINTER ----------------------------------------------------------------
local function winterExtras(root)
	local rnd = Random.new(41)
	-- a LOT more snow: heavier fall, big lazy flakes, and flurries swirling in the air
	local cloud = root:FindFirstChild("SnowCloud")
	local main = cloud and cloud:FindFirstChildOfClass("ParticleEmitter")
	if main then
		main.Rate = 450; main.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75, 0.25), NumberSequenceKeypoint.new(1, 0.75, 0.25) })
		main.LightInfluence = 0; main.LightEmission = 0 -- stay snow-white under the coloured stage lights
		main.SpreadAngle = Vector2.new(25, 25); main.Acceleration = Vector3.new(1.2, 0, 0.4)
		local big = main:Clone(); big.Name = "BigFlakes"; big.Rate = 45; big.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1, 0.35), NumberSequenceKeypoint.new(1, 1.1, 0.35) })
		big.Speed = NumberRange.new(2.4, 3.4); big.Lifetime = NumberRange.new(18, 24); big.Parent = cloud
	end
	emitter(root, "Flurries", Vector3.new(220, 50, 130), CFrame.new(0, 30, 12), { Texture = SPARK, Rate = 300, LightInfluence = 0, Lifetime = NumberRange.new(3, 5), Speed = NumberRange.new(0.5, 2.5), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.15, 0.75, 0.2), NumberSequenceKeypoint.new(0.85, 0.75, 0.2), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(rgb(255, 255, 255)), LightEmission = 0, Acceleration = Vector3.new(0.8, -1.5, 0), RotSpeed = NumberRange.new(-90, 90) })
	-- snow drifts piled up along the walls, in the wings and in front of the stage
	for i = 1, 46 do
		local side = i % 2 == 0 and 1 or -1
		local pos
		if i <= 24 then pos = Vector3.new(side * rnd:NextNumber(112, 121), 0.4, rnd:NextNumber(-60, 82))
		elseif i <= 38 then pos = Vector3.new(side * rnd:NextNumber(82, 118), 0.4, rnd:NextNumber(-40, -2))
		else pos = Vector3.new(rnd:NextNumber(-118, 118), 0.4, rnd:NextNumber(-62, -50)) end
		E(root, "SnowDrift", Vector3.new(rnd:NextNumber(8, 18), rnd:NextNumber(2.5, 5), rnd:NextNumber(6, 11)), CFrame.new(pos) * CFrame.Angles(0, rnd:NextNumber(0, 6), 0), rgb(250, 252, 255), Enum.Material.Snow)
	end
	for _, sx in ipairs({ -1, 1 }) do P(root, "WallSnow", Vector3.new(3, 1.6, 146), CFrame.new(sx * 122, 70.2, 10), rgb(250, 252, 255), Enum.Material.Snow) end
	-- northern lights: glowing ribbons that wave across the night-sky ceiling
	local aur = { { rgb(90, 255, 170), rgb(70, 220, 255) }, { rgb(70, 230, 255), rgb(160, 110, 255) }, { rgb(120, 255, 140), rgb(90, 255, 220) }, { rgb(170, 120, 255), rgb(90, 255, 180) } }
	for k = 1, 4 do
		local rib = mover(root, "Aurora", "bob", { Speed = 0.25 + k * 0.05, Amp = 1.5, Phase = k })
		local z = -36 + k * 24
		local holder = P(rib, "AuroraAnchor", Vector3.one, CFrame.new(0, 64.5 + (k % 2) * 1.5, z), rgb(255, 255, 255), nil, nil, 1)
		rib.PrimaryPart = holder
		local atts = {}
		for i, x in ipairs({ -112, -37, 37, 112 }) do
			local at = Instance.new("Attachment"); at.Position = Vector3.new(x, (i % 2) * 2, 0); at.Axis = Vector3.new(0, 0, 1); at.SecondaryAxis = Vector3.new(0, 1, 0); at.Parent = holder
			atts[i] = at
		end
		for i = 1, 3 do
			local beam = Instance.new("Beam"); beam.Name = "Aurora"
			beam.Attachment0 = atts[i]; beam.Attachment1 = atts[i + 1]
			beam.Width0 = 11; beam.Width1 = 11; beam.Segments = 40; beam.FaceCamera = false; beam.LightEmission = 1; beam.LightInfluence = 0
			beam.CurveSize0 = (i % 2 == 0) and 18 or -18; beam.CurveSize1 = (i % 2 == 0) and 18 or -18
			beam.Color = ColorSequence.new(aur[k][1], aur[k][2])
			beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.5, 0.48), NumberSequenceKeypoint.new(1, 0.7) })
			beam.Parent = holder
		end
	end
	-- penguins waddling about the stage wings
	for i, at in ipairs({ Vector3.new(-96, 2.1, -24), Vector3.new(-104, 2.1, -10), Vector3.new(98, 2.1, -20), Vector3.new(106, 2.1, -6) }) do
		local m = mover(root, "Penguin", "line", { Range = rnd:NextNumber(6, 10), Speed = rnd:NextNumber(0.4, 0.7), Phase = i * 1.7 })
		local c = CFrame.new(at)
		m.PrimaryPart = E(m, "Body", Vector3.new(2.4, 3.6, 2.3), c, rgb(25, 25, 35))
		E(m, "Belly", Vector3.new(1.8, 2.8, 0.6), c * CFrame.new(0, -0.2, -1.0), rgb(250, 250, 255))
		P(m, "Head", Vector3.one * 1.9, c * CFrame.new(0, 2.2, -0.1), rgb(25, 25, 35), nil, Enum.PartType.Ball)
		for _, s in ipairs({ -1, 1 }) do
			P(m, "Eye", Vector3.one * 0.32, c * CFrame.new(s * 0.4, 2.45, -0.85), rgb(255, 255, 255), N, Enum.PartType.Ball)
			E(m, "Flipper", Vector3.new(0.4, 2, 1), c * CFrame.new(s * 1.3, 0, 0) * CFrame.Angles(0, 0, math.rad(s * 15)), rgb(25, 25, 35))
			E(m, "Foot", Vector3.new(0.7, 0.3, 1.1), c * CFrame.new(s * 0.5, -1.8, -0.4), rgb(255, 150, 40))
		end
		E(m, "Beak", Vector3.new(0.5, 0.4, 1), c * CFrame.new(0, 2.1, -1.05), rgb(255, 150, 40))
		P(m, "Scarf", Vector3.new(0.6, 2.2, 2.2), c * CFrame.new(0, 1.3, 0) * UPRIGHT, (i % 2 == 0) and rgb(230, 40, 60) or rgb(60, 140, 255), nil, Enum.PartType.Cylinder)
	end
	-- glowing lamp posts and presents
	for i, at in ipairs({ Vector3.new(-112, 0, 76), Vector3.new(112, 0, 76), Vector3.new(-114, 0, -44), Vector3.new(114, 0, -44), Vector3.new(-86, 0, -2), Vector3.new(86, 0, -2) }) do
		for k = 0, 6 do P(root, "LampPost", Vector3.new(2, 0.9, 0.9), CFrame.new(at + Vector3.new(0, 1 + k * 2, 0)) * UPRIGHT, k % 2 == 0 and rgb(230, 40, 60) or rgb(255, 255, 255), nil, Enum.PartType.Cylinder) end
		local lamp = P(root, "Lantern", Vector3.new(1.8, 2.2, 1.8), CFrame.new(at + Vector3.new(0, 15.2, 0)), rgb(255, 225, 150), N)
		local pl = Instance.new("PointLight"); pl.Color = rgb(255, 210, 140); pl.Range = 18; pl.Brightness = 1.5; pl.Parent = lamp
		P(root, "LampCap", Vector3.new(0.6, 2.6, 2.6), CFrame.new(at + Vector3.new(0, 16.6, 0)) * UPRIGHT, rgb(40, 40, 50), nil, Enum.PartType.Cylinder)
		P(root, "LampSnow", Vector3.new(0.5, 2.4, 2.4), CFrame.new(at + Vector3.new(0, 17.1, 0)) * UPRIGHT, rgb(250, 252, 255), Enum.Material.Snow, Enum.PartType.Cylinder)
	end
	local giftCols = { rgb(230, 40, 60), rgb(60, 140, 255), rgb(80, 200, 110), rgb(255, 200, 50), rgb(190, 110, 255) }
	for i = 1, 14 do
		local side = i % 2 == 0 and 1 or -1
		local s = rnd:NextNumber(2, 3.6)
		local cf = CFrame.new(side * rnd:NextNumber(100, 118), s / 2, rnd:NextNumber(-40, -14)) * CFrame.Angles(0, rnd:NextNumber(0, 6), 0)
		P(root, "Gift", Vector3.one * s, cf, giftCols[(i % #giftCols) + 1])
		P(root, "Ribbon", Vector3.new(s + 0.05, s + 0.05, 0.5), cf, rgb(255, 245, 200))
		P(root, "Ribbon", Vector3.new(0.5, s + 0.05, s + 0.05), cf, rgb(255, 245, 200))
	end
	-- a snowman family at the back corners
	for _, sx in ipairs({ -1, 1 }) do
		for k, sc in ipairs({ 1, 0.65 }) do
			local x, z = sx * (116 - (k - 1) * 0) , 70 - (k - 1) * 9
			local balls = { { 6 * sc, 2.8 * sc }, { 4.4 * sc, 7.2 * sc }, { 3.2 * sc, 10.6 * sc } }
			for _, d in ipairs(balls) do P(root, "SnowBall", Vector3.one * d[1], CFrame.new(x, d[2], z), rgb(250, 252, 255), Enum.Material.Snow, Enum.PartType.Ball) end
			local face = CFrame.lookAt(Vector3.new(x, 10.6 * sc, z), Vector3.new(0, 10.6 * sc, 30)) * CFrame.new(0, 0, -1.5 * sc)
			for _, s in ipairs({ -0.55, 0.55 }) do P(root, "Coal", Vector3.one * 0.5 * sc, face * CFrame.new(s * sc, 0.35 * sc, 0), rgb(30, 30, 30), nil, Enum.PartType.Ball) end
			P(root, "Carrot", Vector3.new(1.8 * sc, 0.45 * sc, 0.45 * sc), face * CFrame.new(0, -0.1, -0.7 * sc) * CFrame.Angles(0, math.rad(90), 0), rgb(255, 130, 30), nil, Enum.PartType.Cylinder)
			P(root, "Scarf", Vector3.new(1, 4.2 * sc, 4.2 * sc), CFrame.new(x, 9.1 * sc, z) * UPRIGHT, giftCols[k + 1], nil, Enum.PartType.Cylinder)
		end
	end
end

-- CANDY -----------------------------------------------------------------
local function candyExtras(root)
	local rnd = Random.new(51)
	local fluff = { rgb(255, 170, 215), rgb(170, 220, 255), rgb(255, 230, 245) }
	for i = 1, 16 do
		local m = mover(root, "CottonCloud", "bob", { Speed = rnd:NextNumber(0.3, 0.6), Amp = 1.2, Phase = i })
		local c = Vector3.new((i % 2 == 0 and 1 or -1) * rnd:NextNumber(30, 112), rnd:NextNumber(60, 68), rnd:NextNumber(-55, 78))
		local col = fluff[(i % 3) + 1]
		m.PrimaryPart = P(m, "Puff", Vector3.one * rnd:NextNumber(6, 9), CFrame.new(c), col, nil, Enum.PartType.Ball)
		for k = 1, 3 do P(m, "Puff", Vector3.one * rnd:NextNumber(4, 7), CFrame.new(c + Vector3.new(rnd:NextNumber(-5, 5), rnd:NextNumber(-1, 1.5), rnd:NextNumber(-4, 4))), col, nil, Enum.PartType.Ball) end
	end
	emitter(root, "Sprinkles", Vector3.new(220, 40, 130), CFrame.new(0, 34, 12), { Texture = SPARK, Rate = 50, Lifetime = NumberRange.new(4, 6), Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.4), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(255, 120, 200)), ColorSequenceKeypoint.new(0.5, rgb(140, 220, 255)), ColorSequenceKeypoint.new(1, rgb(255, 240, 120)) }), LightEmission = 0.8 })
end

-- HALLOWEEN -------------------------------------------------------------
-- The limited-time Halloween arena: a haunted studio with witches flying laps overhead on their
-- brooms, giant glowing jack-o'-lanterns, dancing skeletons, floating ghosts, bat swarms, dangling
-- spiders, a full moon, a graveyard with spooky trees, bubbling cauldrons and rolling fog.
local ORANGE, PURPLE, LIME, BONE = rgb(255, 120, 20), rgb(130, 50, 210), rgb(110, 255, 90), rgb(240, 235, 215)
local function jackOLantern(root, pos, d, facing, glow)
	-- facing: the direction the carved face looks
	local cf = CFrame.lookAt(pos, pos + facing)
	E(root, "Pumpkin", Vector3.new(d * 1.15, d * 0.9, d), cf, ORANGE)
	for k = 0, 3 do E(root, "PumpkinRib", Vector3.new(d * 0.32, d * 0.92, d * 1.02), cf * CFrame.Angles(0, math.rad(k * 45), 0), rgb(230, 98, 12)) end
	P(root, "Stem", Vector3.new(d * 0.12, d * 0.28, d * 0.12), cf * CFrame.new(0, d * 0.52, 0) * CFrame.Angles(0, 0, math.rad(14)), rgb(80, 120, 40), Enum.Material.Wood)
	local face = cf * CFrame.new(0, 0, -d * 0.48)
	local lit = glow or rgb(255, 210, 70)
	for _, s in ipairs({ -1, 1 }) do W(root, "Eye", Vector3.new(0.3, d * 0.18, d * 0.2), face * CFrame.new(s * d * 0.2, d * 0.12, 0) * CFrame.Angles(0, math.rad(90), 0), lit, N) end
	W(root, "Nose", Vector3.new(0.3, d * 0.1, d * 0.1), face * CFrame.new(0, -d * 0.02, 0) * CFrame.Angles(0, math.rad(90), 0), lit, N)
	P(root, "Grin", Vector3.new(d * 0.55, d * 0.1, 0.3), face * CFrame.new(0, -d * 0.18, 0), lit, N)
	for i = -2, 2, 2 do P(root, "GrinTooth", Vector3.new(d * 0.08, d * 0.07, 0.35), face * CFrame.new(i * d * 0.09, -d * 0.15, 0), ORANGE) end
	local core = P(root, "PumpkinGlow", Vector3.one * d * 0.3, cf, lit, N, Enum.PartType.Ball, 0.4)
	local l = Instance.new("PointLight"); l.Color = rgb(255, 140, 40); l.Range = d * 2.2; l.Brightness = 2.2; l.Parent = core
	return cf
end
local function skeleton(parent, feet, facing)
	-- a cheerful cartoon skeleton standing at `feet`, facing `facing`
	local cf = CFrame.lookAt(feet, feet + facing)
	local function at(x, y, z) return cf * CFrame.new(x, y, z) end
	for _, s in ipairs({ -0.55, 0.55 }) do
		P(parent, "Shin", Vector3.new(0.35, 2.4, 0.35), at(s, 1.3, 0), BONE)
		P(parent, "Thigh", Vector3.new(0.4, 2.2, 0.4), at(s, 3.6, 0), BONE)
		E(parent, "Foot", Vector3.new(0.7, 0.35, 1.1), at(s, 0.2, -0.25), BONE)
	end
	E(parent, "Pelvis", Vector3.new(1.9, 0.8, 0.8), at(0, 4.9, 0), BONE)
	P(parent, "Spine", Vector3.new(0.35, 3.2, 0.35), at(0, 6.6, 0.1), BONE)
	for i = 0, 3 do E(parent, "Rib", Vector3.new(2.1 - i * 0.25, 0.28, 1.1), at(0, 7.6 - i * 0.55, -0.05), BONE) end
	E(parent, "Shoulders", Vector3.new(2.6, 0.4, 0.6), at(0, 8.2, 0), BONE)
	for _, s in ipairs({ -1, 1 }) do -- arms up, waving to the crowd
		P(parent, "UpperArm", Vector3.new(0.3, 1.9, 0.3), at(s * 1.65, 8.9, 0) * CFrame.Angles(0, 0, math.rad(-s * 35)), BONE)
		P(parent, "Forearm", Vector3.new(0.28, 1.8, 0.28), at(s * 2.3, 10.4, 0) * CFrame.Angles(0, 0, math.rad(-s * 10)), BONE)
		P(parent, "Hand", Vector3.one * 0.55, at(s * 2.45, 11.4, 0), BONE, nil, Enum.PartType.Ball)
	end
	local head = at(0, 9.6, 0)
	P(parent, "Skull", Vector3.one * 2.0, head, BONE, nil, Enum.PartType.Ball)
	E(parent, "Jaw", Vector3.new(1.3, 0.6, 1.2), head * CFrame.new(0, -0.85, -0.25), BONE)
	for _, s in ipairs({ -1, 1 }) do E(parent, "EyeSocket", Vector3.new(0.55, 0.65, 0.3), head * CFrame.new(s * 0.42, 0.12, -0.88), rgb(20, 15, 25)) end
	for _, s in ipairs({ -1, 1 }) do P(parent, "EyeGlow", Vector3.one * 0.18, head * CFrame.new(s * 0.42, 0.12, -1.0), LIME, N, Enum.PartType.Ball) end
	W(parent, "NoseHole", Vector3.new(0.2, 0.25, 0.2), head * CFrame.new(0, -0.3, -0.98), rgb(20, 15, 25))
	for i = -1, 1 do P(parent, "Tooth", Vector3.new(0.15, 0.2, 0.1), head * CFrame.new(i * 0.2, -0.65, -0.95), rgb(255, 255, 255)) end
end
local function witch(parent, center, robe)
	-- a witch on her broom, built facing -Z (the way the circle mover flies her)
	local c = CFrame.new(center)
	local ALONG = CFrame.Angles(0, math.rad(90), 0)
	P(parent, "Broom", Vector3.new(7, 0.35, 0.35), c * CFrame.new(0, -0.4, 0.3) * ALONG, rgb(120, 78, 40), Enum.Material.Wood, Enum.PartType.Cylinder)
	for i, d in ipairs({ 1.2, 1.5, 1.3 }) do P(parent, "Bristles", Vector3.new(0.6, d, d), c * CFrame.new(0, -0.4, 3.6 + i * 0.45) * ALONG, rgb(220, 160, 60), Enum.Material.Fabric, Enum.PartType.Cylinder) end
	E(parent, "Dress", Vector3.new(2, 2.6, 2.2), c * CFrame.new(0, 0.7, 0.4), robe)
	for _, s in ipairs({ -1, 1 }) do -- legs astride the broom with striped stockings
		P(parent, "Leg", Vector3.new(0.4, 1.6, 0.4), c * CFrame.new(s * 0.6, -0.9, 0) * CFrame.Angles(math.rad(-30), 0, 0), s > 0 and rgb(30, 20, 30) or ORANGE)
		E(parent, "Boot", Vector3.new(0.5, 0.4, 0.9), c * CFrame.new(s * 0.6, -1.6, -0.6), rgb(25, 20, 25))
	end
	-- cape streaming behind her
	for i = 0, 3 do P(parent, "Cape", Vector3.new(2.2 - i * 0.2, 0.2, 1.1), c * CFrame.new(0, 1.5 - i * 0.2, 1.3 + i * 0.9) * CFrame.Angles(math.rad(-12), 0, 0), rgb(35, 15, 45)) end
	local head = c * CFrame.new(0, 2.5, 0.2)
	P(parent, "Head", Vector3.one * 1.5, head, rgb(150, 220, 120), nil, Enum.PartType.Ball)
	W(parent, "Nose", Vector3.new(0.25, 0.35, 0.6), head * CFrame.new(0, -0.05, -0.85), rgb(130, 200, 100))
	for _, s in ipairs({ -1, 1 }) do P(parent, "Eye", Vector3.one * 0.22, head * CFrame.new(s * 0.32, 0.2, -0.68), rgb(255, 230, 60), N, Enum.PartType.Ball) end
	E(parent, "Hair", Vector3.new(1.8, 1.6, 1.6), head * CFrame.new(0, -0.1, 0.45), rgb(140, 40, 180))
	P(parent, "HatBrim", Vector3.new(0.2, 3, 3), head * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(25, 15, 35), nil, Enum.PartType.Cylinder)
	for i, d in ipairs({ 1.5, 1.15, 0.8, 0.45, 0.2 }) do
		P(parent, "HatCone", Vector3.new(0.6, d, d), head * CFrame.new(0, 0.9 + i * 0.5, 0.15 * i) * CFrame.Angles(math.rad(-10 * i), 0, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(25, 15, 35), nil, Enum.PartType.Cylinder)
	end
	P(parent, "HatBand", Vector3.new(0.25, 1.55, 1.55), head * CFrame.new(0, 1.0, 0.05) * CFrame.Angles(0, 0, math.rad(90)), ORANGE, N, Enum.PartType.Cylinder)
	for _, s in ipairs({ -1, 1 }) do P(parent, "Arm", Vector3.new(0.35, 1.5, 0.35), c * CFrame.new(s * 0.75, 1.0, -0.6) * CFrame.Angles(math.rad(70), 0, 0), robe) end
	-- magic sparkles + a glowing trail behind the broom
	local tail = P(parent, "Magic", Vector3.one * 0.3, c * CFrame.new(0, -0.4, 5.2), rgb(255, 255, 255), nil, nil, 1)
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 0.6, 0); a0.Parent = tail
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -0.6, 0); a1.Parent = tail
	local tr = Instance.new("Trail"); tr.Attachment0 = a0; tr.Attachment1 = a1; tr.Lifetime = 0.8; tr.LightEmission = 1; tr.FaceCamera = true
	tr.Color = ColorSequence.new(rgb(190, 90, 255), ORANGE); tr.Transparency = NumberSequence.new(0.25, 1); tr.WidthScale = NumberSequence.new(1, 0); tr.Parent = tail
	local pe = Instance.new("ParticleEmitter"); pe.Texture = SPARK; pe.Rate = 20; pe.Lifetime = NumberRange.new(0.6, 1.2); pe.Speed = NumberRange.new(0.5, 2)
	pe.SpreadAngle = Vector2.new(180, 180); pe.Size = NumberSequence.new(0.6, 0); pe.LightEmission = 1; pe.Color = ColorSequence.new(rgb(255, 170, 60), rgb(180, 100, 255)); pe.Parent = a0
end
local function bat(parent, c, size)
	size = size or 1
	local body = E(parent, "BatBody", Vector3.new(0.9, 1.0, 1.3) * size, CFrame.new(c), rgb(25, 15, 30))
	P(parent, "BatHead", Vector3.one * 0.75 * size, CFrame.new(c + Vector3.new(0, 0.35, -0.65) * size), rgb(25, 15, 30), nil, Enum.PartType.Ball)
	for _, s in ipairs({ -1, 1 }) do
		W(parent, "BatEar", Vector3.new(0.1, 0.4, 0.3) * size, CFrame.new(c + Vector3.new(s * 0.22, 0.85, -0.65) * size), rgb(25, 15, 30))
		P(parent, "BatEye", Vector3.one * 0.14 * size, CFrame.new(c + Vector3.new(s * 0.17, 0.45, -1.0) * size), rgb(255, 60, 40), N, Enum.PartType.Ball)
		for k = 0, 1 do
			W(parent, "BatWing", Vector3.new(0.08, 0.9, 1.6) * size, CFrame.new(c + Vector3.new(s * (0.9 + k * 0.9), 0.15 - k * 0.15, 0) * size) * CFrame.Angles(0, math.rad(s * 90), math.rad(s * (10 + k * 15))), rgb(45, 25, 60))
		end
	end
	return body
end
local function ghost(parent, c, size)
	local body = E(parent, "Ghost", Vector3.new(3.2, 3.6, 3.2) * size, CFrame.new(c), rgb(245, 245, 255), nil, 0.25)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		E(parent, "GhostTail", Vector3.new(1.1, 1.8, 1.1) * size, CFrame.new(c + Vector3.new(math.cos(a) * 1.1, -1.9, math.sin(a) * 1.1) * size), rgb(245, 245, 255), nil, 0.3)
	end
	for _, s in ipairs({ -1, 1 }) do E(parent, "GhostEye", Vector3.new(0.45, 0.7, 0.2) * size, CFrame.new(c + Vector3.new(s * 0.55, 0.45, -1.5) * size), rgb(30, 20, 40)) end
	E(parent, "GhostMouth", Vector3.new(0.6, 0.75, 0.2) * size, CFrame.new(c + Vector3.new(0, -0.45, -1.55) * size), rgb(30, 20, 40))
	local l = Instance.new("PointLight"); l.Color = rgb(200, 220, 255); l.Range = 8; l.Brightness = 0.8; l.Parent = body
	return body
end
local function spookyTree(root, x, z, h, lean)
	local bark = rgb(45, 32, 40)
	local base = CFrame.new(x, 0, z) * CFrame.Angles(0, 0, math.rad(lean))
	for i = 0, math.floor(h / 3) do
		P(root, "DeadTrunk", Vector3.new(3.4, 2.8 - i * 0.12, 2.8 - i * 0.12), base * CFrame.new(math.sin(i * 0.7) * 0.6, i * 3 + 1.5, 0) * UPRIGHT, bark, Enum.Material.Wood, Enum.PartType.Cylinder)
	end
	local rnd = Random.new(x * 7 + z)
	for k = 1, 6 do
		local y = h * rnd:NextNumber(0.5, 0.95)
		local yaw = rnd:NextNumber(0, math.pi * 2)
		local len = rnd:NextNumber(6, 11)
		local branch = base * CFrame.new(0, y, 0) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, math.rad(rnd:NextNumber(30, 60))) * CFrame.new(0, len / 2, 0)
		P(root, "DeadBranch", Vector3.new(0.7, len, 0.7), branch, bark, Enum.Material.Wood)
		P(root, "Twig", Vector3.new(0.35, len * 0.45, 0.35), branch * CFrame.new(0, len * 0.4, 0) * CFrame.Angles(math.rad(35), 0, 0) * CFrame.new(0, len * 0.2, 0), bark, Enum.Material.Wood)
	end
end
local function tombstone(root, pos, yaw, s)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	local stone = rgb(120, 118, 130)
	P(root, "Tombstone", Vector3.new(3 * s, 3.4 * s, 0.8 * s), cf * CFrame.new(0, 1.7 * s, 0), stone, Enum.Material.Slate)
	P(root, "TombTop", Vector3.new(0.8 * s, 3 * s, 3 * s), cf * CFrame.new(0, 3.4 * s, 0) * CFrame.Angles(0, math.rad(90), 0) * UPRIGHT, stone, Enum.Material.Slate, Enum.PartType.Cylinder)
	P(root, "RIP", Vector3.new(1.8 * s, 0.4 * s, 0.1), cf * CFrame.new(0, 2.7 * s, -0.42 * s), rgb(60, 58, 70))
	P(root, "Grave", Vector3.new(3.2 * s, 0.5 * s, 4.5 * s), cf * CFrame.new(0, 0.25 * s, 2.6 * s), rgb(60, 45, 40), Enum.Material.Ground)
end
local function cauldron(root, pos)
	P(root, "Cauldron", Vector3.one * 6, CFrame.new(pos + Vector3.new(0, 2.6, 0)), rgb(25, 25, 30), METAL, Enum.PartType.Ball)
	P(root, "CauldronRim", Vector3.new(0.6, 5.2, 5.2), CFrame.new(pos + Vector3.new(0, 5.3, 0)) * UPRIGHT, rgb(40, 40, 48), METAL, Enum.PartType.Cylinder)
	local brew = P(root, "Brew", Vector3.new(0.4, 4.6, 4.6), CFrame.new(pos + Vector3.new(0, 5.3, 0)) * UPRIGHT, LIME, N, Enum.PartType.Cylinder)
	for _, a in ipairs({ 0, 2.1, 4.2 }) do P(root, "CauldronLeg", Vector3.new(0.6, 1.6, 0.6), CFrame.new(pos + Vector3.new(math.cos(a) * 2, 0.6, math.sin(a) * 2)), rgb(25, 25, 30), METAL) end
	local l = Instance.new("PointLight"); l.Color = LIME; l.Range = 16; l.Brightness = 2; l.Parent = brew
	local pe = Instance.new("ParticleEmitter"); pe.Texture = SMOKE; pe.Rate = 10; pe.Lifetime = NumberRange.new(1.5, 2.5); pe.Speed = NumberRange.new(2, 4)
	pe.Size = NumberSequence.new(1, 3.5); pe.Transparency = NumberSequence.new(0.4, 1); pe.Color = ColorSequence.new(LIME, rgb(170, 110, 255)); pe.LightEmission = 0.6; pe.EmissionDirection = Enum.NormalId.Right; pe.Parent = brew
	local bub = Instance.new("ParticleEmitter"); bub.Texture = SPARK; bub.Rate = 14; bub.Lifetime = NumberRange.new(0.6, 1); bub.Speed = NumberRange.new(1, 3)
	bub.Size = NumberSequence.new(0.6, 0); bub.Color = ColorSequence.new(LIME); bub.LightEmission = 1; bub.EmissionDirection = Enum.NormalId.Right; bub.Parent = brew
end
local function buildHalloween(root)
	local rnd = Random.new(1031)
	-- a huge full moon on the back wall, with a witch silhouette crossing it
	local moon = P(root, "Moon", Vector3.new(1, 30, 30), CFrame.new(-82, 50, -62.4) * CFrame.Angles(0, math.rad(90), 0) * UPRIGHT, rgb(255, 245, 200), N, Enum.PartType.Cylinder)
	for i = 1, 5 do P(root, "MoonCrater", Vector3.new(1.2, rnd:NextNumber(3, 6), rnd:NextNumber(3, 6)), CFrame.new(-82 + rnd:NextNumber(-9, 9), 50 + rnd:NextNumber(-9, 9), -62.1) * CFrame.Angles(0, math.rad(90), 0) * UPRIGHT, rgb(235, 220, 170), nil, Enum.PartType.Cylinder) end
	P(root, "MoonHalo", Vector3.new(0.5, 40, 40), CFrame.new(-82, 50, -62.8) * CFrame.Angles(0, math.rad(90), 0) * UPRIGHT, rgb(255, 220, 140), N, Enum.PartType.Cylinder, 0.8)
	-- giant jack-o'-lanterns along both side walls, faces turned to the audience
	for _, sx in ipairs({ -1, 1 }) do
		for i, z in ipairs({ -40, -4, 32, 68 }) do
			local d = 11 + (i % 2) * 2
			jackOLantern(root, Vector3.new(sx * 114, d * 0.45, z), d, Vector3.new(-sx, 0, 0.35))
			-- little ones piled around the big one
			jackOLantern(root, Vector3.new(sx * 110, 2.2, z - 7), 4.6, Vector3.new(-sx, 0, 0.6))
			jackOLantern(root, Vector3.new(sx * 117, 1.7, z + 8), 3.6, Vector3.new(-sx, 0, 0.2), rgb(150, 255, 110))
		end
	end
	-- spooky dead trees + a graveyard in each stage wing
	for _, sx in ipairs({ -1, 1 }) do
		spookyTree(root, sx * 112, -54, 30, -sx * 6)
		spookyTree(root, sx * 98, -36, 24, sx * 5)
		for i = 1, 6 do
			tombstone(root, Vector3.new(sx * rnd:NextNumber(86, 118), 0, rnd:NextNumber(-34, -8)), rnd:NextNumber(-0.4, 0.4) + (sx > 0 and math.rad(-90) or math.rad(90)) * 0.3, rnd:NextNumber(0.8, 1.2))
		end
		-- spiky iron fence along the front of the wing
		for k = 0, 14 do
			local x = sx * (84 + k * 2.4)
			P(root, "FencePost", Vector3.new(0.35, 5, 0.35), CFrame.new(x, 2.5, -2), rgb(25, 20, 30), METAL)
			W(root, "FenceSpike", Vector3.new(0.35, 0.8, 0.5), CFrame.new(x, 5.4, -2), rgb(25, 20, 30), METAL)
		end
		for _, y in ipairs({ 1.2, 4 }) do P(root, "FenceRail", Vector3.new(36, 0.3, 0.3), CFrame.new(sx * 101, y, -2), rgb(25, 20, 30), METAL) end
		cauldron(root, Vector3.new(sx * 92, 0, -20))
	end
	-- skeletons dancing in the wings and at the back corners (they rock from side to side)
	for i, at in ipairs({ Vector3.new(-104, 0, -24), Vector3.new(104, 0, -24), Vector3.new(-90, 0, -44), Vector3.new(90, 0, -44), Vector3.new(-116, 0, 76), Vector3.new(116, 0, 76) }) do
		local m = mover(root, "Skeleton", "swing", { SwingDeg = rnd:NextNumber(8, 14), Speed = rnd:NextNumber(3, 4.2), Phase = i * 0.9 })
		m.PrimaryPart = P(m, "Anchor", Vector3.one * 0.5, CFrame.new(at), rgb(255, 255, 255), nil, nil, 1)
		skeleton(m, at, Vector3.new(-at.X, 0, 40 - at.Z).Unit)
	end
	-- witches racing laps over the audience on their brooms
	local robes = { rgb(120, 40, 190), rgb(40, 140, 80), rgb(200, 60, 40), rgb(60, 60, 160), rgb(160, 40, 140) }
	for i, spec in ipairs({ { 0, 56, 20, 42, 0.32 }, { 0, 50, 10, 30, -0.4 }, { -40, 60, 40, 20, 0.5 }, { 40, 58, 0, 22, -0.45 }, { 0, 62, 30, 58, 0.22 } }) do
		local m = mover(root, "Witch", "circle", { Radius = spec[4], Speed = spec[5], Phase = i * 1.3 })
		local c = Vector3.new(spec[1], spec[2], spec[3])
		m.PrimaryPart = P(m, "Anchor", Vector3.one * 0.5, CFrame.new(c), rgb(255, 255, 255), nil, nil, 1)
		witch(m, c, robes[i])
	end
	-- swarms of bats flapping round in tight circles
	for i = 1, 18 do
		local c = Vector3.new(rnd:NextNumber(-100, 100), rnd:NextNumber(44, 64), rnd:NextNumber(-50, 76))
		local m = mover(root, "Bat", "circle", { Radius = rnd:NextNumber(4, 10), Speed = rnd:NextNumber(0.9, 1.6) * (i % 2 == 0 and 1 or -1), Phase = rnd:NextNumber(0, 6) })
		m.PrimaryPart = bat(m, c, rnd:NextNumber(0.9, 1.6))
	end
	-- friendly ghosts floating over the seats
	for i = 1, 8 do
		local c = Vector3.new((i % 2 == 0 and 1 or -1) * rnd:NextNumber(25, 100), rnd:NextNumber(36, 50), rnd:NextNumber(0, 76))
		local m = mover(root, "Ghost", "bob", { Speed = rnd:NextNumber(0.6, 1), Amp = 2.2, Phase = i, SpinSpeed = rnd:NextNumber(-0.3, 0.3) })
		m.PrimaryPart = ghost(m, c, rnd:NextNumber(0.9, 1.3))
	end
	-- big spiders dangling from the ceiling on silk threads
	for i = 1, 10 do
		local x, z = (i % 2 == 0 and 1 or -1) * rnd:NextNumber(30, 118), rnd:NextNumber(-55, 80)
		local len = rnd:NextNumber(8, 18)
		local m = mover(root, "Spider", "bob", { Speed = rnd:NextNumber(0.5, 0.9), Amp = 2.5, Phase = i })
		local c = Vector3.new(x, 71 - len, z)
		m.PrimaryPart = P(m, "SpiderBody", Vector3.one * 2.2, CFrame.new(c), rgb(25, 18, 28), nil, Enum.PartType.Ball)
		P(m, "SpiderHead", Vector3.one * 1.3, CFrame.new(c + Vector3.new(0, -1.2, 0)), rgb(25, 18, 28), nil, Enum.PartType.Ball)
		for _, s in ipairs({ -1, 1 }) do P(m, "SpiderEye", Vector3.one * 0.3, CFrame.new(c + Vector3.new(s * 0.3, -1.4, -0.5)), rgb(255, 60, 40), N, Enum.PartType.Ball) end
		for k = 0, 3 do for _, s in ipairs({ -1, 1 }) do
			P(m, "SpiderLeg", Vector3.new(2.6, 0.22, 0.22), CFrame.new(c + Vector3.new(s * 1.6, -0.2, -0.9 + k * 0.6)) * CFrame.Angles(0, 0, math.rad(s * -30)), rgb(25, 18, 28))
		end end
		P(m, "Silk", Vector3.new(0.12, len + 4, 0.12), CFrame.new(c + Vector3.new(0, (len + 4) / 2, 0)), rgb(235, 235, 245), N, nil, 0.4)
	end
	-- cobwebs stretched across the ceiling corners
	for _, sx in ipairs({ -1, 1 }) do for _, z in ipairs({ -62, 82 }) do
		local corner = Vector3.new(sx * 122.5, 70.5, z)
		for k = 0, 5 do
			local a = math.rad(k * 18)
			local dir = Vector3.new(-sx * math.cos(a), -math.sin(a) * 0.9, (z < 0 and 1 or -1) * math.cos(a) * 0.6).Unit
			P(root, "Cobweb", Vector3.new(0.12, 0.12, 16), CFrame.lookAt(corner + dir * 8, corner + dir * 16), rgb(235, 235, 245), N, nil, 0.35)
		end
		for r = 1, 3 do
			for k = 0, 4 do
				local a0, a1 = math.rad(k * 18), math.rad((k + 1) * 18)
				local function pt(a) return corner + Vector3.new(-sx * math.cos(a), -math.sin(a) * 0.9, (z < 0 and 1 or -1) * math.cos(a) * 0.6).Unit * (r * 4.5) end
				local p0, p1 = pt(a0), pt(a1)
				P(root, "CobwebRing", Vector3.new(0.1, 0.1, (p1 - p0).Magnitude), CFrame.lookAt((p0 + p1) / 2, p1), rgb(235, 235, 245), N, nil, 0.4)
			end
		end
	end end
	-- strings of orange & purple lanterns zig-zagging under the ceiling
	for row = 0, 4 do
		local z = -40 + row * 28
		for k = 0, 22 do
			local x = -110 + k * 10
			local y = 66 - math.abs(math.sin(k * 0.6)) * 4
			local col = (k + row) % 2 == 0 and ORANGE or PURPLE
			P(root, "Lantern", Vector3.new(1.6, 2, 1.6), CFrame.new(x, y, z), col, N, Enum.PartType.Ball)
			if k < 22 then P(root, "LanternWire", Vector3.new(10.4, 0.1, 0.1), CFrame.new(x + 5, y + 1, z), rgb(30, 20, 30)) end
		end
	end
	-- floating candy corn
	for i = 1, 12 do
		local pos = Vector3.new((i % 2 == 0 and 1 or -1) * rnd:NextNumber(35, 108), rnd:NextNumber(30, 44), rnd:NextNumber(-30, 76))
		local m = mover(root, "CandyCorn", "bob", { Speed = rnd:NextNumber(0.6, 1.1), Amp = 1.4, Phase = i, SpinSpeed = rnd:NextNumber(0.4, 0.9) })
		m.PrimaryPart = P(m, "CornBase", Vector3.new(1, 2.6, 2.6), CFrame.new(pos) * UPRIGHT, rgb(255, 210, 40), nil, Enum.PartType.Cylinder)
		P(m, "CornMid", Vector3.new(1, 2.0, 2.0), CFrame.new(pos + Vector3.new(0, 1, 0)) * UPRIGHT, ORANGE, nil, Enum.PartType.Cylinder)
		P(m, "CornTip", Vector3.new(1.2, 1.2, 1.2), CFrame.new(pos + Vector3.new(0, 1.9, 0)), rgb(255, 255, 245), nil, Enum.PartType.Ball)
	end
	-- graveyard fog rolling over the floor + glowing embers drifting up
	emitter(root, "Fog", Vector3.new(230, 1, 140), CFrame.new(0, 1, 10), { Texture = SMOKE, Rate = 30, Lifetime = NumberRange.new(6, 10), Speed = NumberRange.new(0.3, 1), SpreadAngle = Vector2.new(70, 70),
		Size = ns(10, 16), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.75), NumberSequenceKeypoint.new(1, 1) }), Color = ColorSequence.new(rgb(170, 120, 230), rgb(120, 230, 150)), EmissionDirection = Enum.NormalId.Top })
	emitter(root, "Embers", Vector3.new(220, 30, 130), CFrame.new(0, 20, 12), { Texture = SPARK, Rate = 35, Lifetime = NumberRange.new(4, 7), Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.45), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(ORANGE, rgb(190, 110, 255)), LightEmission = 1, Acceleration = Vector3.new(0, 0.6, 0) })
end

-- how each world LOOKS: lighting tint for the whole screen while you're in it (the client applies it)
ArenaThemes.Ambience = {
	Space = { tint = rgb(215, 205, 255), saturation = 0.12, contrast = 0.06, ambient = rgb(60, 50, 110), outdoor = rgb(28, 22, 64), exposure = -0.05 },
	Jungle = { tint = rgb(228, 255, 220), saturation = 0.15, contrast = 0.04, ambient = rgb(90, 125, 80), outdoor = rgb(60, 100, 60), exposure = 0 },
	Winter = { tint = rgb(235, 245, 255), saturation = -0.05, contrast = 0.03, ambient = rgb(175, 190, 220), outdoor = rgb(160, 180, 215), exposure = 0.12 },
	Candy = { tint = rgb(255, 238, 248), saturation = 0.2, contrast = 0.02, ambient = rgb(160, 120, 150), outdoor = rgb(150, 120, 150), exposure = 0.05 },
	Halloween = { tint = rgb(235, 215, 255), saturation = 0.18, contrast = 0.1, ambient = rgb(80, 50, 110), outdoor = rgb(55, 35, 80), exposure = -0.08 },
}

---------------------------------------------------------------- theme table
local NEON = N
ArenaThemes.Themes = {
	Aquarium = {
		decor = "Aquarium",
		flags = { rgb(255, 140, 120), rgb(90, 240, 255), rgb(120, 255, 190), rgb(255, 230, 120) },
		parts = {
			RearWall = { rgb(10, 45, 95) }, BackstageWall = { rgb(10, 45, 95) }, SideWall = { rgb(10, 45, 95) }, Ceiling = { rgb(30, 110, 170) },
			TheatreFloor = { rgb(222, 198, 140), Enum.Material.Sand }, MainStage = { rgb(40, 150, 190), Enum.Material.Marble }, Runway = { rgb(250, 140, 120) },
			RunwayEdge = { rgb(90, 240, 255), NEON }, StepLight = { rgb(90, 240, 255), NEON }, ProsceniumPillar = { rgb(90, 240, 255), NEON }, ProsceniumCrown = { rgb(90, 240, 255), NEON },
			JumboFrame = { rgb(90, 240, 255), NEON }, SapphirePanel = { rgb(20, 90, 150) }, Marquee = { rgb(30, 160, 220) },
			Seat = { rgb(255, 120, 110) }, Back = { rgb(255, 120, 110) }, Riser = { rgb(30, 90, 140) },
		},
	},
	Space = {
		build = function(root) buildSpace(root); spaceExtras(root) end,
		flags = { rgb(120, 90, 255), rgb(90, 220, 255), rgb(255, 120, 220), rgb(255, 230, 120) },
		parts = {
			RearWall = { rgb(14, 10, 38) }, BackstageWall = { rgb(14, 10, 38) }, SideWall = { rgb(14, 10, 38) }, Ceiling = { rgb(6, 5, 18) },
			TheatreFloor = { rgb(30, 24, 66), Enum.Material.Slate }, MainStage = { rgb(55, 38, 120), Enum.Material.Marble }, Runway = { rgb(95, 50, 195) },
			RunwayEdge = { rgb(90, 220, 255), NEON }, StepLight = { rgb(90, 220, 255), NEON }, ProsceniumPillar = { rgb(150, 110, 255), NEON }, ProsceniumCrown = { rgb(90, 220, 255), NEON },
			JumboFrame = { rgb(90, 220, 255), NEON }, SapphirePanel = { rgb(60, 30, 140) }, Marquee = { rgb(95, 50, 195) },
			Seat = { rgb(85, 72, 175) }, Back = { rgb(85, 72, 175) }, Riser = { rgb(25, 20, 60) },
		},
	},
	Candy = {
		build = function(root) buildCandy(root); candyExtras(root) end,
		flags = { rgb(255, 110, 180), rgb(130, 220, 255), rgb(255, 230, 120), rgb(150, 240, 180), rgb(200, 150, 255) },
		parts = {
			RearWall = { rgb(255, 178, 216) }, BackstageWall = { rgb(255, 152, 206) }, SideWall = { rgb(255, 178, 216) }, Ceiling = { rgb(255, 228, 242) },
			TheatreFloor = { rgb(168, 236, 208) }, MainStage = { rgb(255, 208, 232), Enum.Material.Marble }, Runway = { rgb(255, 105, 170) },
			RunwayEdge = { rgb(255, 255, 255), NEON }, StepLight = { rgb(255, 255, 255), NEON }, ProsceniumPillar = { rgb(255, 110, 190), NEON }, ProsceniumCrown = { rgb(120, 220, 255), NEON },
			JumboFrame = { rgb(255, 110, 190), NEON }, SapphirePanel = { rgb(130, 215, 255) }, Marquee = { rgb(255, 105, 170) },
			Seat = { rgb(120, 210, 255) }, Back = { rgb(255, 140, 200) }, Riser = { rgb(255, 232, 246) },
		},
	},
	Jungle = {
		build = function(root) buildJungle(root); jungleExtras(root) end,
		flags = { rgb(255, 120, 60), rgb(255, 210, 60), rgb(80, 200, 90), rgb(60, 180, 220) },
		parts = {
			RearWall = { rgb(35, 95, 55) }, BackstageWall = { rgb(28, 75, 42) }, SideWall = { rgb(35, 95, 55) }, Ceiling = { rgb(22, 60, 35) },
			TheatreFloor = { rgb(95, 150, 60), Enum.Material.Grass }, MainStage = { rgb(135, 95, 55), Enum.Material.WoodPlanks }, Runway = { rgb(150, 110, 60), Enum.Material.Wood },
			RunwayEdge = { rgb(255, 210, 80), NEON }, StepLight = { rgb(255, 210, 80), NEON }, ProsceniumPillar = { rgb(120, 230, 90), NEON }, ProsceniumCrown = { rgb(255, 210, 80), NEON },
			JumboFrame = { rgb(255, 170, 50), NEON }, SapphirePanel = { rgb(60, 130, 70) }, Marquee = { rgb(200, 120, 40) },
			Seat = { rgb(205, 145, 65) }, Back = { rgb(205, 145, 65) }, Riser = { rgb(80, 55, 30), Enum.Material.Wood },
		},
	},
	Halloween = {
		build = function(root) buildHalloween(root) end,
		flags = { rgb(255, 120, 20), rgb(130, 50, 210), rgb(110, 255, 90), rgb(30, 20, 35) },
		parts = {
			RearWall = { rgb(28, 14, 42) }, BackstageWall = { rgb(22, 10, 34) }, SideWall = { rgb(28, 14, 42) }, Ceiling = { rgb(12, 6, 22) },
			TheatreFloor = { rgb(40, 32, 38), Enum.Material.Slate }, MainStage = { rgb(55, 25, 75), Enum.Material.Marble }, Runway = { rgb(230, 100, 15) },
			RunwayEdge = { rgb(255, 140, 30), NEON }, StepLight = { rgb(255, 140, 30), NEON }, ProsceniumPillar = { rgb(150, 60, 230), NEON }, ProsceniumCrown = { rgb(255, 130, 25), NEON },
			JumboFrame = { rgb(255, 130, 25), NEON }, SapphirePanel = { rgb(60, 20, 90) }, Marquee = { rgb(230, 100, 15) },
			Seat = { rgb(90, 30, 130) }, Back = { rgb(90, 30, 130) }, Riser = { rgb(30, 18, 40) },
			Balloon = { rgb(255, 120, 20) }, BalloonBase = { rgb(150, 60, 230), NEON }, CrownSeg = { rgb(150, 60, 230), NEON }, StageStep = { rgb(45, 20, 65) },
			AisleLight = { rgb(255, 130, 25), NEON }, PyroRing = { rgb(110, 255, 90), NEON },
		},
	},
	Winter = {
		build = function(root) buildWinter(root); winterExtras(root) end,
		flags = { rgb(255, 255, 255), rgb(140, 210, 255), rgb(255, 90, 110), rgb(120, 230, 200) },
		parts = {
			RearWall = { rgb(175, 212, 240) }, BackstageWall = { rgb(145, 190, 235) }, SideWall = { rgb(175, 212, 240) }, Ceiling = { rgb(28, 42, 88) },
			TheatreFloor = { rgb(240, 246, 255), Enum.Material.Snow }, MainStage = { rgb(205, 232, 255), Enum.Material.Ice }, Runway = { rgb(125, 185, 255), Enum.Material.Ice },
			RunwayEdge = { rgb(190, 240, 255), NEON }, StepLight = { rgb(190, 240, 255), NEON }, ProsceniumPillar = { rgb(255, 255, 255), NEON }, ProsceniumCrown = { rgb(150, 220, 255), NEON },
			JumboFrame = { rgb(190, 240, 255), NEON }, SapphirePanel = { rgb(110, 170, 230) }, Marquee = { rgb(70, 130, 210) },
			Seat = { rgb(60, 120, 200) }, Back = { rgb(60, 120, 200) }, Riser = { rgb(200, 222, 242) },
		},
	},
}

-- Dress a match arena in a theme, on this client only. Safe to call once per arena.
function ArenaThemes.apply(arena, themeId)
	local theme = themeId and ArenaThemes.Themes[themeId]
	if not (arena and theme) or arena:GetAttribute("ThemeApplied") then return false end
	arena:SetAttribute("ThemeApplied", true)
	arena:SetAttribute("Theme", themeId)
	local rules, flags, flagIndex = theme.parts or {}, theme.flags, 0
	for _, folderName in ipairs({ "Set", "Extravaganza", "Audience" }) do
		local folder = arena:FindFirstChild(folderName)
		if folder then
			for _, d in ipairs(folder:GetDescendants()) do
				if d:IsA("BasePart") then
					local r = rules[d.Name]
					if r then d.Color = r[1]; if r[2] then d.Material = r[2] end end
					if d.Name == "Flag" and flags then flagIndex += 1; d.Color = flags[(flagIndex % #flags) + 1] end
				end
			end
		end
	end
	local decor
	if theme.decor then
		local template = RS:FindFirstChild("ClamillionArenaDecor") and RS.ClamillionArenaDecor:FindFirstChild(theme.decor)
		if template then decor = template:Clone() end
	elseif theme.build then
		decor = Instance.new("Model")
		local ok, err = pcall(theme.build, decor)
		if not ok then warn("[Clamillion] arena theme " .. themeId .. ": " .. tostring(err)) end
	end
	if decor then
		decor.Name = "ThemeDecor"
		decor.WorldPivot = CLASSIC_PIVOT
		decor:PivotTo(arena:GetPivot())
		decor.Parent = arena
	end
	return true
end

return ArenaThemes
