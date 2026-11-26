-- HALLOWEEN EVENT lobby effects (client): brings the Halloween lobby decorations to life while
-- they're in the lobby (witches flying laps, bats, bobbing ghosts and spiders, dancing skeletons,
-- flickering jack-o'-lanterns) and keeps the event countdown on the banner ticking.
-- The decorations only exist while the event is on (the server adds workspace.HalloweenLobbyDecor).
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local Events = require(RS:WaitForChild("Clamillion"):WaitForChild("Shared"):WaitForChild("Events"))

local movers, lights, countdowns = {}, {}, {}
local decor = nil

local function collect(model)
	table.clear(movers); table.clear(lights); table.clear(countdowns)
	decor = model
	if not model then return end
	for _, m in ipairs(model:GetDescendants()) do
		if m:IsA("Model") and m:GetAttribute("Swim") and m.PrimaryPart then
			table.insert(movers, { model = m, kind = m:GetAttribute("Swim"), home = m:GetPivot(),
				radius = m:GetAttribute("Radius") or 20, speed = m:GetAttribute("Speed") or 0.2, phase = m:GetAttribute("Phase") or 0,
				amp = m:GetAttribute("Amp") or 2, spin = m:GetAttribute("SpinSpeed"), swing = math.rad(m:GetAttribute("SwingDeg") or 12) })
		elseif m:IsA("PointLight") and m.Parent and m.Parent.Name == "PumpkinGlow" then
			table.insert(lights, { light = m, base = m.Brightness, seed = #lights * 1.7 })
		elseif m:IsA("TextLabel") and m.Name == "Countdown" then
			table.insert(countdowns, m)
		end
	end
end

local function watchDecor()
	local m = workspace:FindFirstChild("HalloweenLobbyDecor")
	if m then task.wait(1); collect(m) end -- give the decorations a moment to stream in
end
workspace.ChildAdded:Connect(function(c) if c.Name == "HalloweenLobbyDecor" then task.wait(1); collect(c) end end)
workspace.ChildRemoved:Connect(function(c) if c == decor then collect(nil) end end)
task.spawn(watchDecor)

local function fmtLeft(sec)
	sec = math.max(0, math.floor(sec))
	local d, h, m = math.floor(sec / 86400), math.floor(sec / 3600) % 24, math.floor(sec / 60) % 60
	if d > 0 then return ("Ends in %dd %dh %02dm"):format(d, h, m) end
	if h > 0 then return ("Ends in %dh %02dm"):format(h, m) end
	return ("Ends in %dm %02ds!"):format(m, sec % 60)
end

local clock = 0
RunService.RenderStepped:Connect(function(dt)
	if not decor or not decor.Parent then return end
	clock += dt
	if clock < 1 / 30 then return end
	clock = 0
	local t = workspace:GetServerTimeNow()
	for _, s in ipairs(movers) do
		if s.model.Parent then
			local c = s.home.Position
			local cf
			if s.kind == "circle" then
				local a = t * s.speed + s.phase
				local pos = c + Vector3.new(math.cos(a) * s.radius, math.sin(a * 2.3) * 1.5, math.sin(a) * s.radius)
				local dir = Vector3.new(-math.sin(a), 0, math.cos(a)) * (s.speed >= 0 and 1 or -1)
				cf = CFrame.lookAt(pos, pos + dir)
			elseif s.kind == "swing" then
				cf = s.home * CFrame.Angles(0, 0, math.sin(t * s.speed + s.phase) * s.swing)
			else -- bob
				cf = s.home + Vector3.new(0, math.sin(t * s.speed + s.phase) * s.amp, 0)
			end
			if s.spin then cf = cf * CFrame.Angles(0, (t * s.spin) % (math.pi * 2), 0) end
			s.model:PivotTo(cf)
		end
	end
	-- jack-o'-lanterns flicker like real candles
	for _, l in ipairs(lights) do
		l.light.Brightness = l.base * (0.75 + 0.25 * math.noise((t % 1000) * 3, l.seed))
	end
end)

-- banner countdown
task.spawn(function()
	while true do
		if #countdowns > 0 then
			local text = fmtLeft(Events.secondsLeft("halloween"))
			for _, l in ipairs(countdowns) do l.Text = "⏳ " .. text .. "  •  Sunday 11:55 PM ET" end
		end
		task.wait(1)
	end
end)
