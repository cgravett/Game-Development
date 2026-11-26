-- Custom podium themes. PodiumThemes.apply(podium, themeId) recolours a contestant podium and adds
-- themed decorations around it. Used by the server for real shows and by the client for the
-- 3D previews in the shop, so what kids see in the shop is exactly what they get on stage.
local PodiumThemes = {}

local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
local M = Enum.Material
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local RAINBOW = { rgb(255,72,92), rgb(255,146,40), rgb(255,214,40), rgb(84,214,90), rgb(60,128,255), rgb(150,86,255) }

-- podium-local space: origin on the stage under the podium, -Z faces the audience.
-- Body spans x ±1.9, y 0.4..8.0, z ±1.3. The contestant pedestal is behind it (z 1.5..5.5, top y 5.2).
local function builder(podium)
	local body = podium:FindFirstChild("Body")
	local base = body.CFrame * CFrame.new(0, -4.2, 0)
	local deco = podium:FindFirstChild("ThemeDeco")
	if deco then deco:Destroy() end
	deco = Instance.new("Folder")
	deco.Name = "ThemeDeco"
	deco.Parent = podium
	local function P(name, size, cf, color, material, shape, props)
		local p = Instance.new(props and props.ClassName or "Part")
		p.Name = name; p.Size = size; p.CFrame = base * cf; p.Color = color
		p.Material = material or M.SmoothPlastic
		if shape then p.Shape = shape end
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
		if props then for k, v in pairs(props) do if k ~= "ClassName" then p[k] = v end end end
		p.Parent = deco
		return p
	end
	local function ball(name, d, pos, color, material, props) return P(name, Vector3.new(d, d, d), CFrame.new(pos), color, material, Enum.PartType.Ball, props) end
	local function cyl(name, length, d, cf, color, material) return P(name, Vector3.new(length, d, d), cf, color, material, Enum.PartType.Cylinder) end
	local function sparkles(part, color, rate, texture)
		local a = Instance.new("Attachment"); a.Parent = part
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = texture or "rbxasset://textures/particles/sparkles_main.dds"
		pe.Color = ColorSequence.new(color); pe.LightEmission = 1; pe.Rate = rate or 6
		pe.Size = NumberSequence.new(0.35, 0); pe.Lifetime = NumberRange.new(1, 2); pe.Speed = NumberRange.new(0.5, 2)
		pe.SpreadAngle = Vector2.new(180, 180); pe.Parent = a
		return pe
	end
	local function sign(part, face, text, color)
		local sg = Instance.new("SurfaceGui"); sg.Face = face; sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud; sg.PixelsPerStud = 50; sg.LightInfluence = 0; sg.Parent = part
		local t = Instance.new("TextLabel"); t.BackgroundTransparency = 1; t.Size = UDim2.fromScale(1, 1); t.FontFace = FONT; t.TextScaled = true; t.Text = text; t.TextColor3 = color; t.Parent = sg
	end
	return P, ball, cyl, sparkles, sign, base
end

-- recolour the existing podium parts
local function paint(podium, t)
	local map = {
		Body = { t.body, t.bodyMaterial },
		Top = { t.top or t.body, t.bodyMaterial },
		TopTrim = { t.trim, t.trimMaterial or M.Metal },
		Plinth = { t.trim, t.trimMaterial or M.Metal },
		PedestalTrim = { t.trim, t.trimMaterial or M.Metal },
		Pedestal = { t.pedestal, t.pedestalMaterial },
		PedestalStep = { t.pedestal, t.pedestalMaterial },
		Edge = { t.glow, M.Neon }, TopEdge = { t.glow, M.Neon }, BaseGlow = { t.glow, M.Neon }, PedestalGlow = { t.glow, M.Neon },
	}
	for _, p in ipairs(podium:GetChildren()) do
		local m = map[p.Name]
		if m and p:IsA("BasePart") then
			if m[1] then p.Color = m[1] end
			if m[2] then p.Material = m[2] end
			local light = p:FindFirstChildOfClass("PointLight")
			if light and t.glow then light.Color = t.glow end
		end
	end
	local bg = podium.Body:FindFirstChild("Display") and podium.Body.Display:FindFirstChild("BG")
	if bg and t.screen then
		bg.BackgroundColor3 = t.screen
		local star = bg:FindFirstChild("Star")
		if star and t.stars then star.Text = t.stars end
	end
end

local THEMES = {}

THEMES.aquarium = {
	body = rgb(20, 80, 150), trim = rgb(235, 215, 160), glow = rgb(60, 230, 255), pedestal = rgb(214, 190, 130), pedestalMaterial = M.Sand, screen = rgb(10, 60, 120), stars = "🐠 🐟 🐡",
	decorate = function(P, ball, cyl, sparkles, sign)
		for _, x in ipairs({ -2.55, 2.55 }) do -- glass fish tanks on each side
			P("Tank", Vector3.new(1.1, 5.6, 2.4), CFrame.new(x, 3.6, 0), rgb(120, 210, 255), M.Glass, nil, { Transparency = 0.55 })
			P("TankSand", Vector3.new(1.0, 0.5, 2.3), CFrame.new(x, 1.05, 0), rgb(235, 210, 150), M.Sand)
			P("TankLid", Vector3.new(1.25, 0.25, 2.55), CFrame.new(x, 6.5, 0), rgb(235, 215, 160), M.Metal)
			for i, c in ipairs({ rgb(255, 140, 40), rgb(255, 220, 60), rgb(80, 160, 255) }) do
				local y, z = 2 + i * 1.2, -0.6 + (i % 2) * 1.0
				ball("Fish", 0.55, Vector3.new(x, y, z), c)
				P("FishTail", Vector3.new(0.1, 0.4, 0.35), CFrame.new(x, y, z + 0.4), c, nil, nil, { ClassName = "WedgePart" })
			end
			P("Seaweed", Vector3.new(0.18, 2.4, 0.18), CFrame.new(x, 2.4, 0.7) * CFrame.Angles(0.15, 0, 0), rgb(60, 200, 90))
			sparkles(P("Bubbles", Vector3.new(0.6, 0.2, 0.6), CFrame.new(x, 1.5, -0.5), rgb(200, 240, 255), M.Glass, nil, { Transparency = 1 }), rgb(220, 250, 255), 4, "rbxasset://textures/particles/smoke_main.dds")
		end
		ball("Coral", 1.1, Vector3.new(-1.5, 8.7, -0.6), rgb(255, 110, 150))
		ball("Coral", 0.8, Vector3.new(-1.0, 8.6, -0.9), rgb(255, 160, 80))
		ball("Coral", 0.9, Vector3.new(1.5, 8.7, -0.6), rgb(190, 110, 255))
		ball("Shell", 0.7, Vector3.new(1.6, 5.4, 4.8), rgb(255, 200, 210))
		ball("Starfish", 0.6, Vector3.new(-1.7, 5.35, 4.6), rgb(255, 120, 60))
	end,
}

THEMES.sports = {
	body = rgb(245, 245, 250), trim = rgb(220, 40, 50), trimMaterial = M.SmoothPlastic, glow = rgb(255, 214, 40), pedestal = rgb(70, 170, 70), pedestalMaterial = M.Grass, screen = rgb(25, 30, 60), stars = "⚽ 🏀 🏈",
	decorate = function(P, ball, cyl, sparkles, sign)
		for _, x in ipairs({ -1.45, 1.45 }) do P("JerseyStripe", Vector3.new(0.35, 7.6, 2.64), CFrame.new(x, 4.2, 0), rgb(220, 40, 50)) end
		local b = ball("Basketball", 1.3, Vector3.new(-1.35, 9.3, -0.5), rgb(240, 120, 30))
		P("BallLine", Vector3.new(1.32, 0.08, 0.08), CFrame.new(-1.35, 9.3, -0.5), rgb(30, 20, 20))
		ball("SoccerBall", 1.2, Vector3.new(1.35, 9.25, -0.5), rgb(255, 255, 255))
		ball("SoccerPatch", 0.5, Vector3.new(1.35, 9.3, -1.0), rgb(20, 20, 25))
		for _, z in ipairs({ 2.2, 3.5, 4.8 }) do P("FieldLine", Vector3.new(4.42, 0.06, 0.12), CFrame.new(0, 5.07, z), rgb(255, 255, 255)) end
		-- little trophy on the pedestal
		cyl("TrophyBase", 0.3, 0.9, CFrame.new(1.7, 5.4, 5.1) * CFrame.Angles(0, 0, math.rad(90)), rgb(255, 200, 40), M.Metal)
		ball("TrophyCup", 0.8, Vector3.new(1.7, 6.0, 5.1), rgb(255, 210, 60), M.Metal)
		local back = P("JerseyNumber", Vector3.new(2.6, 2.6, 0.05), CFrame.new(0, 4.6, -1.33), rgb(255, 255, 255), nil, nil, { Transparency = 1 })
	end,
}

THEMES.unicorn = {
	body = rgb(255, 196, 232), trim = rgb(200, 160, 255), trimMaterial = M.SmoothPlastic, glow = rgb(255, 255, 255), pedestal = rgb(250, 250, 255), screen = rgb(170, 90, 200), stars = "🦄 ✨ 🦄",
	decorate = function(P, ball, cyl, sparkles, sign)
		-- golden horn sprouting from the top front
		local sizes = { 0.75, 0.6, 0.45, 0.3, 0.16 }
		for i, d in ipairs(sizes) do
			local cf = CFrame.new(0, 8.4, -1.25) * CFrame.Angles(math.rad(-35), 0, 0) * CFrame.new(0, (i - 1) * 0.42, 0)
			P("Horn", Vector3.new(d, 0.5, d), cf, i % 2 == 0 and rgb(255, 240, 170) or rgb(255, 205, 60), M.Neon)
		end
		-- rainbow mane down both sides
		local mane = { rgb(255, 120, 180), rgb(255, 180, 120), rgb(255, 240, 140), rgb(150, 230, 190), rgb(140, 190, 255), rgb(200, 150, 255) }
		for i, c in ipairs(mane) do
			for _, x in ipairs({ -2.05, 2.05 }) do P("Mane", Vector3.new(0.45, 1.05, 1.0), CFrame.new(x, 8.0 - i * 1.1, 0.75), c) end
		end
		-- little wings
		for _, s in ipairs({ -1, 1 }) do
			P("Wing", Vector3.new(0.2, 2.6, 2.2), CFrame.new(s * 2.2, 6.2, 0.6) * CFrame.Angles(0, 0, s * math.rad(-25)), rgb(255, 255, 255), nil, nil, { ClassName = "WedgePart" })
		end
		-- fluffy cloud around the pedestal
		for i = 0, 9 do
			local a = i / 10 * math.pi * 2
			ball("Cloud", 1.6, Vector3.new(math.cos(a) * 2.4, 0.6, 3.5 + math.sin(a) * 2.2), rgb(255, 255, 255))
		end
		sparkles(P("Glitter", Vector3.new(3.8, 0.2, 2.6), CFrame.new(0, 8.6, 0), rgb(255, 255, 255), nil, nil, { Transparency = 1 }), rgb(255, 200, 250), 10)
	end,
}

THEMES.rainbow = {
	body = rgb(255, 255, 255), trim = rgb(255, 214, 40), glow = rgb(255, 90, 180), pedestal = rgb(250, 250, 255), screen = rgb(110, 60, 220), stars = "🌈 🌈 🌈",
	decorate = function(P, ball, cyl, sparkles, sign)
		for i, c in ipairs(RAINBOW) do -- stripes on both sides
			for _, x in ipairs({ -1.93, 1.93 }) do P("Stripe", Vector3.new(0.06, 1.2, 2.62), CFrame.new(x, 0.9 + i * 1.15, 0), c) end
		end
		-- rainbow arch over the contestant
		for band, c in ipairs(RAINBOW) do
			local r = 6.2 - (band - 1) * 0.45
			for k = 0, 15 do
				local a0 = k / 16 * math.pi
				local a = a0 + math.pi / 32
				local pos = Vector3.new(math.cos(a) * r, 5.2 + math.sin(a) * r, 4.6)
				local seg = 2 * r * math.sin(math.pi / 32) + 0.06
				P("Arch", Vector3.new(seg, 0.45, 0.6), CFrame.new(pos) * CFrame.Angles(0, 0, a + math.pi / 2), c, M.Neon)
			end
		end
		for _, x in ipairs({ -5.9, 5.9 }) do
			for i = 0, 4 do ball("Cloud", 1.8 - i * 0.15, Vector3.new(x + (i - 2) * 0.6, 5.4 + (i % 2) * 0.5, 4.6 + (i - 2) * 0.3), rgb(255, 255, 255)) end
		end
	end,
}

THEMES.galaxy = {
	body = rgb(40, 20, 85), trim = rgb(170, 140, 255), glow = rgb(180, 90, 255), pedestal = rgb(25, 15, 60), screen = rgb(15, 5, 40), stars = "🪐 ⭐ 🚀",
	decorate = function(P, ball, cyl, sparkles, sign)
		local rng = Random.new(42)
		for i = 1, 18 do
			local x = rng:NextInteger(0, 1) == 0 and -1.92 or 1.92
			ball("Star", rng:NextNumber(0.15, 0.3), Vector3.new(x, rng:NextNumber(1, 7.6), rng:NextNumber(-1.1, 1.1)), rgb(255, 255, 220), M.Neon)
		end
		ball("Planet", 1.4, Vector3.new(-1.4, 9.5, -0.4), rgb(255, 150, 80))
		P("PlanetRing", Vector3.new(0.12, 2.3, 2.3), CFrame.new(-1.4, 9.5, -0.4) * CFrame.Angles(0, 0, math.rad(90 - 20)), rgb(255, 220, 160), M.Neon, Enum.PartType.Cylinder, { Transparency = 0.2 })
		-- tiny rocket
		cyl("Rocket", 1.6, 0.6, CFrame.new(1.4, 9.4, -0.4) * CFrame.Angles(0, 0, math.rad(90)), rgb(240, 240, 250))
		ball("RocketNose", 0.6, Vector3.new(1.4, 10.25, -0.4), rgb(255, 60, 80))
		sparkles(P("RocketFlame", Vector3.new(0.3, 0.3, 0.3), CFrame.new(1.4, 8.55, -0.4), rgb(255, 160, 40), M.Neon), rgb(255, 170, 60), 12, "rbxasset://textures/particles/fire_main.dds")
		sparkles(P("Twinkle", Vector3.new(4.4, 0.2, 4), CFrame.new(0, 5.4, 3.5), rgb(255, 255, 255), nil, nil, { Transparency = 1 }), rgb(220, 220, 255), 8)
	end,
}

THEMES.candy = {
	body = rgb(255, 150, 200), trim = rgb(150, 240, 205), trimMaterial = M.SmoothPlastic, glow = rgb(255, 255, 255), pedestal = rgb(140, 90, 60), screen = rgb(200, 60, 140), stars = "🍭 🍬 🧁",
	decorate = function(P, ball, cyl, sparkles, sign)
		-- candy-cane corners
		for _, x in ipairs({ -1.95, 1.95 }) do
			for i = 0, 9 do P("CandyCane", Vector3.new(0.32, 0.76, 0.32), CFrame.new(x, 0.78 + i * 0.76, -1.32), i % 2 == 0 and rgb(255, 40, 60) or rgb(255, 255, 255), M.Neon) end
		end
		-- frosting drips along the top
		for i = 0, 6 do P("Frosting", Vector3.new(0.6, 0.4 + (i % 3) * 0.35, 0.2), CFrame.new(-1.7 + i * 0.57, 7.75 - (i % 3) * 0.17, -1.38), rgb(255, 255, 255)) end
		-- lollipops
		for _, s in ipairs({ { -1.4, rgb(255, 90, 160) }, { 1.4, rgb(90, 200, 255) } }) do
			P("LolliStick", Vector3.new(0.15, 1.6, 0.15), CFrame.new(s[1], 9.4, -0.6), rgb(255, 255, 255))
			cyl("Lollipop", 0.25, 1.5, CFrame.new(s[1], 10.4, -0.6) * CFrame.Angles(0, math.rad(90), 0), s[2], M.Neon)
		end
		-- gumdrops on the pedestal (it's chocolate!)
		local gums = { rgb(255, 80, 80), rgb(255, 200, 40), rgb(80, 220, 120), rgb(120, 140, 255) }
		for i, c in ipairs(gums) do ball("Gumdrop", 0.7, Vector3.new(-1.8 + (i - 1) * 1.2, 5.45, 5.2), c, M.Glass) end
	end,
}

THEMES.dino = {
	body = rgb(90, 175, 75), trim = rgb(120, 80, 45), trimMaterial = M.Wood, glow = rgb(190, 255, 80), pedestal = rgb(150, 120, 80), pedestalMaterial = M.Ground, screen = rgb(30, 70, 30), stars = "🦖 🥚 🦕",
	decorate = function(P, ball, cyl, sparkles, sign)
		for i = 0, 4 do -- spikes along the top
			P("Spike", Vector3.new(0.3, 0.9, 0.9), CFrame.new(-1.6 + i * 0.8, 8.75, 0.2) * CFrame.Angles(0, math.rad(90), 0), rgb(255, 150, 40), nil, nil, { ClassName = "WedgePart" })
		end
		local rng = Random.new(7)
		for i = 1, 10 do
			local x = rng:NextInteger(0, 1) == 0 and -1.9 or 1.9
			ball("Spot", rng:NextNumber(0.4, 0.8), Vector3.new(x, rng:NextNumber(1.2, 7.4), rng:NextNumber(-0.9, 0.9)), rgb(60, 130, 50))
		end
		P("Egg", Vector3.new(1.1, 1.5, 1.1), CFrame.new(1.6, 5.95, 5.0), rgb(245, 240, 220), nil, Enum.PartType.Ball)
		ball("EggSpot", 0.3, Vector3.new(1.6, 6.2, 4.5), rgb(120, 170, 90))
		for i = 0, 2 do P("Footprint", Vector3.new(0.7, 0.05, 0.9), CFrame.new(-1.2 + (i % 2) * 0.8, 5.08, 2.2 + i * 1.2), rgb(90, 70, 45)) end
		P("Fern", Vector3.new(0.2, 2.2, 1.2), CFrame.new(-2.5, 1.1, -0.5) * CFrame.Angles(0, 0, math.rad(15)), rgb(50, 160, 60), nil, nil, { ClassName = "WedgePart" })
	end,
}

THEMES.space_cat = {
	body = rgb(255, 170, 70), trim = rgb(255, 255, 255), trimMaterial = M.SmoothPlastic, glow = rgb(255, 120, 200), pedestal = rgb(255, 230, 200), screen = rgb(90, 50, 140), stars = "🐱 🐾 🐱",
	decorate = function(P, ball, cyl, sparkles, sign)
		for _, x in ipairs({ -1.35, 1.35 }) do -- kitty ears on top
			P("Ear", Vector3.new(0.4, 1.3, 1.2), CFrame.new(x, 9.0, -0.4) * CFrame.Angles(0, math.rad(90), 0), rgb(255, 170, 70), nil, nil, { ClassName = "WedgePart" })
			P("EarInner", Vector3.new(0.42, 0.8, 0.7), CFrame.new(x, 8.85, -0.62) * CFrame.Angles(0, math.rad(90), 0), rgb(255, 160, 190), nil, nil, { ClassName = "WedgePart" })
		end
		for _, x in ipairs({ -1.93, 1.93 }) do for i = 0, 2 do P("TigerStripe", Vector3.new(0.06, 0.35, 2.0), CFrame.new(x, 2.5 + i * 1.8, 0) * CFrame.Angles(0.3, 0, 0), rgb(200, 100, 30)) end end
		-- curly tail behind
		for i = 0, 6 do
			local a = i / 6 * math.pi * 1.2
			ball("Tail", 0.55, Vector3.new(2.3 + math.sin(a) * 0.6, 2 + i * 0.75, 1.0 + math.cos(a) * 0.4), rgb(255, 170, 70))
		end
		for i = 0, 3 do ball("Paw", 0.55, Vector3.new(-1.4 + i * 0.95, 5.25, 2.2 + (i % 2) * 1.4), rgb(255, 150, 190)) end
		ball("Yarn", 1.0, Vector3.new(1.7, 5.7, 5.1), rgb(150, 110, 255))
	end,
}

THEMES.gamer = {
	body = rgb(25, 25, 35), trim = rgb(45, 45, 60), glow = rgb(0, 255, 140), pedestal = rgb(30, 30, 45), screen = rgb(5, 15, 10), stars = "🎮 GG 🎮",
	decorate = function(P, ball, cyl, sparkles, sign)
		local rgbStrip = { rgb(255, 50, 80), rgb(255, 180, 0), rgb(0, 255, 140), rgb(0, 160, 255), rgb(200, 60, 255) }
		for i, c in ipairs(rgbStrip) do for _, x in ipairs({ -1.93, 1.93 }) do P("RGB", Vector3.new(0.08, 1.4, 0.2), CFrame.new(x, 0.9 + i * 1.4, -1.1), c, M.Neon) end end
		-- giant controller on top
		P("Controller", Vector3.new(2.6, 0.5, 1.2), CFrame.new(0, 9.0, -0.4), rgb(60, 60, 80))
		for _, x in ipairs({ -1.25, 1.25 }) do ball("Grip", 0.9, Vector3.new(x, 8.95, -0.2), rgb(60, 60, 80)) end
		P("DPad", Vector3.new(0.6, 0.1, 0.2), CFrame.new(-0.7, 9.3, -0.5), rgb(20, 20, 25))
		P("DPad", Vector3.new(0.2, 0.1, 0.6), CFrame.new(-0.7, 9.3, -0.5), rgb(20, 20, 25))
		for i, c in ipairs({ rgb(255, 60, 60), rgb(60, 220, 90), rgb(60, 140, 255), rgb(255, 210, 40) }) do
			local a = i / 4 * math.pi * 2
			ball("Button", 0.22, Vector3.new(0.7 + math.cos(a) * 0.22, 9.3, -0.5 + math.sin(a) * 0.22), c, M.Neon)
		end
		for i = 0, 3 do P("PedestalRGB", Vector3.new(4.45, 0.12, 0.12), CFrame.new(0, 1 + i * 1.1, 1.48), rgbStrip[i + 1], M.Neon) end
	end,
}

THEMES.superhero = {
	body = rgb(40, 80, 220), trim = rgb(255, 214, 40), glow = rgb(255, 60, 60), pedestal = rgb(200, 30, 40), screen = rgb(15, 30, 100), stars = "⚡ 🦸 ⚡",
	decorate = function(P, ball, cyl, sparkles, sign)
		-- flowing red cape behind the contestant
		for i = 0, 4 do
			P("Cape", Vector3.new(3.2 - i * 0.1, 1.0, 0.15), CFrame.new(0, 8.6 - i * 1.0, 5.6 + i * 0.12) * CFrame.Angles(math.rad(8), 0, 0), rgb(220, 30, 40))
		end
		-- lightning bolts on the sides
		for _, x in ipairs({ -1.94, 1.94 }) do
			P("Bolt", Vector3.new(0.06, 2.2, 0.4), CFrame.new(x, 5.6, -0.2) * CFrame.Angles(math.rad(25), 0, 0), rgb(255, 230, 40), M.Neon)
			P("Bolt", Vector3.new(0.06, 2.2, 0.4), CFrame.new(x, 3.8, 0.2) * CFrame.Angles(math.rad(-25), 0, 0), rgb(255, 230, 40), M.Neon)
		end
		local emblem = P("Emblem", Vector3.new(1.4, 1.4, 0.1), CFrame.new(0, 9.3, -0.6) * CFrame.Angles(0, 0, math.rad(45)), rgb(255, 214, 40), M.Neon)
		for _, x in ipairs({ -1.5, 1.5 }) do ball("Star", 0.5, Vector3.new(x, 9.0, -0.6), rgb(255, 255, 255), M.Neon) end
		sparkles(emblem, rgb(255, 240, 120), 6)
	end,
}

-- reward podiums (Rewards stand, unlocked by total score) -------------------------------------
-- A medal hung on BOTH side faces of the podium (nothing on top, so the contestant stays in view).
-- Returns the parts it made so a theme can restyle them (e.g. the rainbow podium).
local function medalSides(P, ball, cyl, sparkles, metal, ribbon, material)
	local made = {}
	local inner = metal:Lerp(Color3.new(1, 1, 1), 0.25)
	for _, s in ipairs({ -1, 1 }) do
		local x = s * 1.9
		-- V-shaped ribbon above the medal
		for _, z in ipairs({ -0.3, 0.3 }) do
			table.insert(made, P("Ribbon", Vector3.new(0.08, 1.5, 0.5), CFrame.new(x + s * 0.05, 7.05, z - 0.15) * CFrame.Angles(math.rad(z > 0 and -16 or 16), 0, 0), ribbon))
		end
		-- the medal: a disc facing outwards (cylinder axis = local X)
		table.insert(made, cyl("Medal", 0.24, 2.1, CFrame.new(x + s * 0.12, 5.55, -0.15), metal, material or M.Metal))
		table.insert(made, cyl("MedalInner", 0.26, 1.45, CFrame.new(x + s * 0.14, 5.55, -0.15), inner, material or M.Metal))
		table.insert(made, ball("MedalStar", 0.55, Vector3.new(x + s * 0.28, 5.55, -0.15), metal:Lerp(Color3.new(1, 1, 1), 0.55), M.Neon))
		-- studs down the front edge, below the medal
		for i = 0, 1 do ball("Stud", 0.3, Vector3.new(x - s * 0.03, 1.6 + i * 1.6, -0.9), metal:Lerp(Color3.new(1, 1, 1), 0.4), M.Metal) end
	end
	return made
end

THEMES.bronze = {
	body = rgb(170, 100, 45), bodyMaterial = M.Metal, top = rgb(150, 85, 35), trim = rgb(120, 65, 25), glow = rgb(255, 170, 90), pedestal = rgb(130, 80, 40), pedestalMaterial = M.Metal, screen = rgb(60, 30, 10), stars = "🥉 ★ 🥉",
	decorate = function(P, ball, cyl, sparkles, sign) medalSides(P, ball, cyl, sparkles, rgb(205, 127, 50), rgb(200, 40, 50)) end,
}
THEMES.silver = {
	body = rgb(195, 200, 212), bodyMaterial = M.Metal, top = rgb(170, 176, 190), trim = rgb(140, 148, 165), glow = rgb(200, 235, 255), pedestal = rgb(160, 166, 180), pedestalMaterial = M.Metal, screen = rgb(25, 35, 60), stars = "🥈 ★ 🥈",
	decorate = function(P, ball, cyl, sparkles, sign)
		medalSides(P, ball, cyl, sparkles, rgb(215, 220, 230), rgb(60, 110, 230))
		sparkles(P("Shine", Vector3.new(3.8, 0.2, 2.6), CFrame.new(0, 8.6, 0), rgb(255, 255, 255), nil, nil, { Transparency = 1 }), rgb(230, 245, 255), 5)
	end,
}
THEMES.gold = {
	body = rgb(245, 195, 50), bodyMaterial = M.Metal, top = rgb(230, 175, 30), trim = rgb(200, 140, 15), glow = rgb(255, 245, 160), pedestal = rgb(220, 165, 30), pedestalMaterial = M.Metal, screen = rgb(70, 40, 0), stars = "🥇 🏆 🥇",
	decorate = function(P, ball, cyl, sparkles, sign)
		-- gold medals on both sides (no trophy on top: it blocked the contestant)
		medalSides(P, ball, cyl, sparkles, rgb(255, 205, 50), rgb(200, 30, 45))
		-- golden laurel arcs on the front
		for i = 0, 6 do
			local a = math.rad(200 + i * 22)
			for _, s in ipairs({ -1, 1 }) do ball("Laurel", 0.45, Vector3.new(s * (0.8 + math.cos(a) * -0.9 * s * s), 6.9 + math.sin(a) * 1.1, -1.38), rgb(255, 230, 110), M.Neon) end
		end
		sparkles(P("GoldShine", Vector3.new(4.4, 0.2, 4), CFrame.new(0, 9, 1.5), rgb(255, 255, 255), nil, nil, { Transparency = 1 }), rgb(255, 225, 120), 10)
	end,
}
THEMES.prism = {
	body = rgb(250, 250, 255), trim = rgb(255, 255, 255), glow = rgb(255, 90, 160), pedestal = rgb(245, 245, 255), screen = rgb(40, 20, 90), stars = "🌈 ✨ 🌈",
	animated = true,
	decorate = function(P, ball, cyl, sparkles, sign)
		local CS = game:GetService("CollectionService")
		local function cycle(part, offset) part:SetAttribute("RainbowOffset", offset); CS:AddTag(part, "RainbowCycle"); return part end
		-- glowing bands that ripple through the rainbow
		for i = 0, 6 do
			cycle(P("Band", Vector3.new(3.86, 0.35, 2.66), CFrame.new(0, 1.0 + i * 1.08, 0), RAINBOW[(i % 6) + 1], M.Neon), i * 0.08)
		end
		for i = 0, 5 do cycle(P("PedestalBand", Vector3.new(4.46, 0.3, 4.06), CFrame.new(0, 0.6 + i * 0.8, 3.5), RAINBOW[(i % 6) + 1], M.Neon), 0.5 + i * 0.08) end
		-- halo ring floating over the contestant
		for k = 0, 15 do
			local a = k / 16 * math.pi * 2
			cycle(P("Halo", Vector3.new(0.9, 0.25, 0.4), CFrame.new(math.cos(a) * 1.6, 11.6, 3.5 + math.sin(a) * 1.6) * CFrame.Angles(0, -a, 0), RAINBOW[(k % 6) + 1], M.Neon), k / 16)
		end
		-- rainbow medals on both sides (no crystal crown on top: it blocked the contestant)
		for i, part in ipairs(medalSides(P, ball, cyl, sparkles, RAINBOW[5], RAINBOW[1], M.Neon)) do
			cycle(part, i * 0.11)
		end
		sparkles(P("PrismSparkles", Vector3.new(4.4, 0.2, 4), CFrame.new(0, 9, 1.5), rgb(255, 255, 255), nil, nil, { Transparency = 1 }), rgb(255, 255, 255), 14)
	end,
}

-- HALLOWEEN event podium (free during the Halloween event) -------------------------------------
-- Haunted pumpkin: jack-o'-lanterns glowing on the front corners, bats circling, cobwebs, a mini
-- graveyard on the pedestal and spooky purple fog. Nothing tall on top, so the contestant shows.
THEMES.halloween = {
	body = rgb(40, 18, 60), top = rgb(28, 12, 42), trim = rgb(255, 110, 15), trimMaterial = M.SmoothPlastic, glow = rgb(255, 95, 10),
	pedestal = rgb(55, 45, 50), pedestalMaterial = M.Slate, screen = rgb(25, 8, 40), stars = "🎃 👻 🦇",
	decorate = function(P, ball, cyl, sparkles, sign)
		local ORANGE, DARK, GLOW = rgb(255, 120, 20), rgb(30, 15, 10), rgb(255, 210, 80)
		local function pumpkin(pos, d, face)
			ball("Pumpkin", d, pos, ORANGE)
			for k = 0, 3 do -- ribs
				P("PumpkinRib", Vector3.new(d * 0.98, d * 0.98, d * 0.22), CFrame.new(pos) * CFrame.Angles(0, math.rad(k * 45), 0), rgb(235, 100, 15), nil, Enum.PartType.Ball)
			end
			P("Stem", Vector3.new(0.18 * d, 0.32 * d, 0.18 * d), CFrame.new(pos + Vector3.new(0, d * 0.55, 0)) * CFrame.Angles(0, 0, math.rad(12)), rgb(70, 120, 40))
			if face then -- glowing carved face looking at the audience (-Z)
				local f = CFrame.new(pos + Vector3.new(0, 0, -d * 0.47))
				for _, s in ipairs({ -1, 1 }) do
					P("Eye", Vector3.new(0.22 * d, 0.2 * d, 0.06), f * CFrame.new(s * 0.2 * d, 0.12 * d, 0) * CFrame.Angles(0, 0, math.rad(45)), GLOW, M.Neon)
				end
				P("Mouth", Vector3.new(0.5 * d, 0.1 * d, 0.06), f * CFrame.new(0, -0.17 * d, 0), GLOW, M.Neon)
				for i = -1, 1 do P("Tooth", Vector3.new(0.08 * d, 0.08 * d, 0.07), f * CFrame.new(i * 0.14 * d, -0.13 * d, -0.01), ORANGE) end
				local l = Instance.new("PointLight"); l.Color = rgb(255, 150, 40); l.Range = 7; l.Brightness = 1.6
				l.Parent = P("Candle", Vector3.one * 0.3, CFrame.new(pos), GLOW, M.Neon)
			end
		end
		-- jack-o'-lanterns sitting on the front top corners
		pumpkin(Vector3.new(-1.55, 8.65, -0.55), 1.3, true)
		pumpkin(Vector3.new(1.55, 8.65, -0.55), 1.3, true)
		-- orange & purple stripes down both sides
		for i = 0, 4 do
			for _, x in ipairs({ -1.93, 1.93 }) do
				P("Stripe", Vector3.new(0.06, 0.5, 2.62), CFrame.new(x, 1.2 + i * 1.45, 0), i % 2 == 0 and ORANGE or rgb(140, 60, 220), M.Neon)
			end
		end
		-- cobwebs in the top corners (thin white strands in a fan)
		for _, s in ipairs({ -1, 1 }) do
			for k = 0, 3 do
				P("Cobweb", Vector3.new(0.05, 1.5, 0.05), CFrame.new(s * 1.94, 7.4, -1.0) * CFrame.Angles(math.rad(-20 + k * 25), 0, 0) * CFrame.new(0, 0.6, 0), rgb(235, 235, 245), M.Neon, nil, { Transparency = 0.25 })
			end
			for r = 1, 2 do
				P("CobwebRing", Vector3.new(0.05, 0.05, 0.45 * r), CFrame.new(s * 1.94, 7.85 - r * 0.32, -1.05 + r * 0.25), rgb(235, 235, 245), M.Neon, nil, { Transparency = 0.3 })
			end
			-- a little spider dangling on a thread
			P("Thread", Vector3.new(0.04, 1.6, 0.04), CFrame.new(s * 2.15, 6.6, -0.9), rgb(235, 235, 245), M.Neon)
			ball("Spider", 0.42, Vector3.new(s * 2.15, 5.75, -0.9), rgb(20, 15, 20))
			for l = -1, 1, 2 do P("SpiderLeg", Vector3.new(0.6, 0.06, 0.06), CFrame.new(s * 2.15 + l * 0.25, 5.75, -0.9) * CFrame.Angles(0, 0, math.rad(l * 30)), rgb(20, 15, 20)) end
		end
		-- mini graveyard on the pedestal: tombstones + a cauldron of green bubbles
		for _, x in ipairs({ -1.65, 1.65 }) do
			P("Tombstone", Vector3.new(0.75, 1.1, 0.25), CFrame.new(x, 5.75, 5.15), rgb(140, 140, 150), M.Slate)
			cyl("TombTop", 0.25, 0.75, CFrame.new(x, 6.3, 5.15) * CFrame.Angles(0, math.rad(90), 0), rgb(140, 140, 150), M.Slate)
			P("RIP", Vector3.new(0.4, 0.08, 0.04), CFrame.new(x, 5.9, 5.02), rgb(60, 60, 70))
		end
		ball("Cauldron", 1.0, Vector3.new(1.75, 5.75, 3.0), rgb(25, 25, 30), M.Metal)
		cyl("Brew", 0.12, 0.8, CFrame.new(1.75, 6.15, 3.0) * CFrame.Angles(0, 0, math.rad(90)), rgb(110, 255, 90), M.Neon)
		sparkles(P("Bubbles", Vector3.new(0.6, 0.1, 0.6), CFrame.new(1.75, 6.2, 3.0), rgb(110, 255, 90), nil, nil, { Transparency = 1 }), rgb(140, 255, 110), 8, "rbxasset://textures/particles/smoke_main.dds")
		pumpkin(Vector3.new(-1.8, 5.55, 2.6), 0.8, false)
		-- bats flapping round the sides
		for i, at in ipairs({ Vector3.new(-2.9, 7.2, 0.4), Vector3.new(2.9, 6.4, 0.8), Vector3.new(-2.7, 4.6, 1.2) }) do
			ball("BatBody", 0.42, at, rgb(25, 15, 30))
			for _, s in ipairs({ -1, 1 }) do
				P("BatWing", Vector3.new(0.05, 0.45, 0.75), CFrame.new(at + Vector3.new(0, 0.05, s * 0.45)) * CFrame.Angles(math.rad(s * 25), 0, 0), rgb(40, 20, 50), nil, nil, { ClassName = "WedgePart" })
			end
			ball("BatEye", 0.09, at + Vector3.new(0.18, 0.08, -0.1), rgb(255, 60, 40), M.Neon)
		end
		-- purple witchy fog rolling off the base
		local fog = P("Fog", Vector3.new(4.4, 0.2, 7), CFrame.new(0, 0.3, 2.2), rgb(255, 255, 255), nil, nil, { Transparency = 1 })
		local a = Instance.new("Attachment"); a.Parent = fog
		local pe = Instance.new("ParticleEmitter"); pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
		pe.Color = ColorSequence.new(rgb(170, 110, 255), rgb(90, 255, 140)); pe.Rate = 6; pe.Lifetime = NumberRange.new(2, 3); pe.Speed = NumberRange.new(0.3, 0.8)
		pe.Size = NumberSequence.new(1.2, 2.4); pe.Transparency = NumberSequence.new(0.7, 1); pe.SpreadAngle = Vector2.new(80, 80); pe.LightEmission = 0.4; pe.Parent = a
		sparkles(P("SpookySparkles", Vector3.new(4.4, 0.2, 4), CFrame.new(0, 9, 1.5), rgb(255, 255, 255), nil, nil, { Transparency = 1 }), rgb(255, 150, 40), 6)
	end,
}

PodiumThemes.Themes = THEMES

-- Apply a theme (nil / "classic" leaves the standard podium untouched).
function PodiumThemes.apply(podium, themeId)
	local t = themeId and THEMES[themeId]
	if not t or not podium or not podium:FindFirstChild("Body") then return false end
	paint(podium, t)
	local P, ball, cyl, sparkles, sign = builder(podium)
	t.decorate(P, ball, cyl, sparkles, sign)
	if t.animated then
		-- the podium's own glowing edges cycle colours too
		local CS = game:GetService("CollectionService")
		for i, p in ipairs(podium:GetChildren()) do
			if p:IsA("BasePart") and (p.Name == "Edge" or p.Name == "TopEdge" or p.Name == "BaseGlow" or p.Name == "PedestalGlow") then
				p:SetAttribute("RainbowOffset", i * 0.05); CS:AddTag(p, "RainbowCycle")
			end
		end
	end
	podium:SetAttribute("Theme", themeId)
	return true
end

return PodiumThemes
