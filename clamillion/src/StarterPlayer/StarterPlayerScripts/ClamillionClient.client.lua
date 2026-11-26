-- Clamillion client: UI, input and presentation only. All game decisions are made by the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local root = ReplicatedStorage:WaitForChild("Clamillion")
local Remotes = root:WaitForChild("Remotes")
local UI = require(root:WaitForChild("Shared"):WaitForChild("UIConstants"))
local C = UI.Colors
local studio = workspace:WaitForChild("ClamillionStudio")

local Lighting=game:GetService("Lighting")
-- the lobby always uses the same bright, even lighting (show arenas set their own)
-- GlobalShadows off: the lobby is indoors under a ceiling, so with shadows on (higher graphics
-- levels) the sun is blocked and the hall goes dim. Off = the same bright look on every device.
local NORMAL_LOBBY_LIGHT = { Ambient = Color3.fromRGB(128, 136, 160), OutdoorAmbient = Color3.fromRGB(150, 158, 178), Brightness = 2, ExposureCompensation = 0.1, ClockTime = 14, EnvironmentDiffuseScale = 1, EnvironmentSpecularScale = 1, GlobalShadows = false }
-- HALLOWEEN EVENT lobby: a spooky night-time look (only while the event is on; see Shared.Events)
local HALLOWEEN_LOBBY_LIGHT = { Ambient = Color3.fromRGB(110, 85, 140), OutdoorAmbient = Color3.fromRGB(95, 70, 125), Brightness = 1.4, ExposureCompensation = 0, ClockTime = 14, EnvironmentDiffuseScale = 1, EnvironmentSpecularScale = 1, GlobalShadows = false }
local Events = require(ReplicatedStorage:WaitForChild("Clamillion"):WaitForChild("Shared"):WaitForChild("Events"))
local LOBBY_LIGHT = NORMAL_LOBBY_LIGHT
local function lobbyLighting(on)
 LOBBY_LIGHT = Events.isActive("halloween") and HALLOWEEN_LOBBY_LIGHT or NORMAL_LOBBY_LIGHT
 local tint = Lighting:FindFirstChild("HalloweenLobbyTint")
 if on and LOBBY_LIGHT == HALLOWEEN_LOBBY_LIGHT then
  if not tint then
   tint = Instance.new("ColorCorrectionEffect"); tint.Name = "HalloweenLobbyTint"
   tint.TintColor = Color3.fromRGB(255, 225, 205); tint.Saturation = 0.2; tint.Contrast = 0.12; tint.Parent = Lighting
  end
 elseif tint then tint:Destroy() end
 if on then
  for k, v in pairs(LOBBY_LIGHT) do Lighting[k] = v end
  -- clear any leftover show/arena screen tints
  for _, e in ipairs(Lighting:GetChildren()) do
   if e.Name == "ClamillionAmbience" or e.Name == "ClamillionUnderwater" or e.Name == "ClamillionUnderwaterHaze" then e:Destroy() end
  end
 else
  Lighting.Ambient=Color3.fromRGB(83,88,113)
  Lighting.OutdoorAmbient=Color3.fromRGB(40,40,60)
  Lighting.Brightness=2
  Lighting.ExposureCompensation=0
  Lighting.ClockTime=14
  Lighting.GlobalShadows=true -- shows keep their dramatic stage shadows
 end
end
lobbyLighting(true)
local Settings = { captions = true, reducedMotion = false, effects = true, audio = true }

---------------------------------------------------------------- helpers
local function make(class, props, children)
	local inst = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then parent = v else inst[k] = v end
	end
	for _, child in ipairs(children or {}) do child.Parent = inst end
	if parent then inst.Parent = parent end
	return inst
end
local function corner(r) return make("UICorner", { CornerRadius = UDim.new(0, r or 12) }) end
local function stroke(color, t) return make("UIStroke", { Color = color or C.Gold, Thickness = t or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) end
local function pad(p) return make("UIPadding", { PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p), PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p) }) end
local function maxText(max, min) return make("UITextSizeConstraint", { MaxTextSize = max, MinTextSize = min or 9 }) end
local function maxSize(x, y) return make("UISizeConstraint", { MaxSize = Vector2.new(x or math.huge, y or math.huge) }) end

-- Kid-friendly style: chunky rounded shapes, thick outlines, candy gradients and a bit of bounce.
local function textStroke(color, t) return make("UIStroke", { Color = color or C.Outline, Thickness = t or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }) end

local function label(props, max)
	local p = { BackgroundTransparency = 1, TextColor3 = C.White, Font = UI.Font, TextScaled = true, TextWrapped = true, Text = "" }
	for k, v in pairs(props) do p[k] = v end
	local l = make("TextLabel", p, { maxText(max or 28) })
	-- dark outline on light text keeps it readable on every bright background
	if (p.TextColor3 == C.White or p.TextColor3 == C.Gold or p.TextColor3 == C.Muted) then textStroke(C.Outline, (max or 28) >= 30 and 3 or 1.6).Parent = l end
	return l
end

local BUTTON_STYLES = {
	gold = { C.Gold, Color3.fromRGB(255, 160, 20), C.Ink },
	dark = { Color3.fromRGB(150, 90, 255), Color3.fromRGB(96, 46, 210), C.White },
	pink = { C.PanelPink, Color3.fromRGB(230, 50, 140), C.White },
	green = { C.Good, Color3.fromRGB(30, 180, 90), C.Ink },
}
local function button(props, style, max)
	local s = BUTTON_STYLES[style or "gold"] or BUTTON_STYLES.gold
	local p = {
		BackgroundColor3 = Color3.new(1, 1, 1), TextColor3 = s[3],
		Font = UI.FontBlack, TextScaled = true, AutoButtonColor = false, Text = "",
	}
	for k, v in pairs(props) do p[k] = v end
	local b = make("TextButton", p, { corner(18), maxText(max or 24), stroke(C.Outline, 3), pad(8) })
	make("UIGradient", { Name = "Candy", Rotation = 90, Color = ColorSequence.new(s[1], s[2]), Parent = b })
	if s[3] == C.White then textStroke(C.Outline, 2).Parent = b end
	local scale = make("UIScale", { Parent = b })
	local base = b.Rotation
	b.MouseEnter:Connect(function()
		if Settings.reducedMotion then return end
		TweenService:Create(scale, TweenInfo.new(.18, Enum.EasingStyle.Back), { Scale = 1.08 }):Play()
		TweenService:Create(b, TweenInfo.new(.18, Enum.EasingStyle.Back), { Rotation = base + 2 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(.15), { Scale = 1 }):Play()
		TweenService:Create(b, TweenInfo.new(.15), { Rotation = base }):Play()
	end)
	b.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(.08), { Scale = 0.92 }):Play() end)
	b.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(.2, Enum.EasingStyle.Back), { Scale = 1 }):Play() end)
	return b
end

-- Big friendly menu buttons: glossy candy gradient, white rim, a round
-- icon bubble that wiggles, a shine that sweeps across every few seconds, bouncy hover / press.
-- colors = { top, bottom, lip }; wide = icon on the left and the label on the right.
local function menuButton(props, icon, text, colors, wide)
	local p = { BackgroundColor3 = Color3.new(1, 1, 1), Text = "", AutoButtonColor = false, BorderSizePixel = 0 }
	for k, v in pairs(props) do p[k] = v end
	local z = p.ZIndex or 1
	local b = make("TextButton", p, { corner(22), make("UIStroke", { Color = C.White, Thickness = 3.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) })
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(colors[1], colors[2]), Parent = b })
	-- glossy top highlight
	local gloss = make("Frame", { Name = "Gloss", Position = UDim2.new(0, 4, 0, 3), Size = UDim2.new(1, -8, 0.42, 0), BackgroundColor3 = C.White, BorderSizePixel = 0, ZIndex = z, Parent = b }, { corner(18) })
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }), Parent = gloss })
	-- the shine that sweeps across
	local shine = make("Frame", { Name = "Shine", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.White, BorderSizePixel = 0, ZIndex = z + 2, Parent = b }, { corner(22) })
	local shineGrad = make("UIGradient", { Rotation = 25, Offset = Vector2.new(-1, 0), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1), NumberSequenceKeypoint.new(0.5, 0.45), NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1) }), Parent = shine })
	-- round icon bubble
	local bubbleSize = wide and 42 or 50
	local bubble = make("Frame", { Name = "IconBubble", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C.White, BorderSizePixel = 0, Size = UDim2.fromOffset(bubbleSize, bubbleSize), ZIndex = z + 1, Parent = b },
		{ make("UICorner", { CornerRadius = UDim.new(1, 0) }), make("UIStroke", { Color = colors[3], Thickness = 2.5 }) })
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.White, Color3.fromRGB(255, 236, 250)), Parent = bubble })
	local glyph = make("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.86, 0.86), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Text = icon, TextScaled = true, Font = UI.FontBlack, ZIndex = z + 1, Parent = bubble })
	local words = make("TextLabel", { Name = "Label", BackgroundTransparency = 1, Text = text, TextScaled = true, TextWrapped = true, Font = UI.FontBlack, TextColor3 = C.White, ZIndex = z + 1, Parent = b }, { maxText(wide and 24 or 15), textStroke(colors[3], 2.2) })
	if wide then
		bubble.Position = UDim2.new(0, 8 + bubbleSize / 2, 0.5, -2)
		words.Position = UDim2.new(0, bubbleSize + 14, 0, 6); words.Size = UDim2.new(1, -bubbleSize - 22, 1, -16)
	else
		bubble.Position = UDim2.new(0.5, 0, 0, 8 + bubbleSize / 2)
		words.Position = UDim2.new(0, 4, 0, bubbleSize + 12); words.Size = UDim2.new(1, -8, 1, -bubbleSize - 20)
	end
	-- motion: wiggling icon, a shine now and then, bouncy hover and press
	local scale = make("UIScale", { Parent = b })
	local base = b.Rotation
	local phase = math.random() * 10
	task.spawn(function()
		while b.Parent do
			if not Settings.reducedMotion and b.Visible then
				local t = os.clock() + phase
				glyph.Rotation = math.sin(t * 2.2) * 8
				bubble.Size = UDim2.fromOffset(bubbleSize + math.sin(t * 3) * 1.5, bubbleSize + math.sin(t * 3) * 1.5)
			end
			RunService.Heartbeat:Wait()
		end
	end)
	task.spawn(function()
		task.wait(phase % 3)
		while b.Parent do
			if not Settings.reducedMotion and b.Visible then
				shineGrad.Offset = Vector2.new(-1, 0)
				TweenService:Create(shineGrad, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Offset = Vector2.new(1, 0) }):Play()
			end
			task.wait(4 + math.random() * 2)
		end
	end)
	b.MouseEnter:Connect(function()
		if Settings.reducedMotion then return end
		TweenService:Create(scale, TweenInfo.new(.2, Enum.EasingStyle.Back), { Scale = 1.1 }):Play()
		TweenService:Create(b, TweenInfo.new(.2, Enum.EasingStyle.Back), { Rotation = base + (base >= 0 and 3 or -3) }):Play()
		shineGrad.Offset = Vector2.new(-1, 0)
		TweenService:Create(shineGrad, TweenInfo.new(0.6), { Offset = Vector2.new(1, 0) }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(.15), { Scale = 1 }):Play()
		TweenService:Create(b, TweenInfo.new(.15), { Rotation = base }):Play()
	end)
	b.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(.08), { Scale = 0.9 }):Play() end)
	b.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(.25, Enum.EasingStyle.Back), { Scale = 1 }):Play() end)
	return b
end
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local MENU_COLORS = {
	stuff = { rgb(255, 120, 200), rgb(220, 50, 150), rgb(150, 20, 100) },
	how = { rgb(90, 235, 150), rgb(20, 175, 110), rgb(10, 110, 70) },
	settings = { rgb(170, 140, 255), rgb(110, 70, 230), rgb(65, 35, 160) },
	emote = { rgb(255, 160, 80), rgb(255, 70, 140), rgb(170, 30, 90) },
	shop = { rgb(255, 225, 80), rgb(255, 150, 20), rgb(185, 85, 0) },
}

local function panel(props)
	local p = { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }
	for k, v in pairs(props) do p[k] = v end
	local f = make("Frame", p, { corner(22), stroke(C.White, 4) })
	make("UIGradient", { Name = "Candy", Rotation = 120, Color = ColorSequence.new(C.Panel, Color3.fromRGB(190, 70, 220)), Parent = f })
	return f
end

local function tween(obj, t, goal)
	if Settings.reducedMotion then
		for k, v in pairs(goal) do obj[k] = v end
		return
	end
	TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
end

local function pop(frame)
	if Settings.reducedMotion then return end
	local scale = frame:FindFirstChildOfClass("UIScale") or make("UIScale", { Parent = frame })
	scale.Scale = 0.9
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local SoundService=game:GetService("SoundService")
local ContentProvider=game:GetService("ContentProvider")
local music=make("Sound",{Name="ClamillionShowMusic",SoundId="rbxassetid://1842174239",Volume=0.42,Parent=SoundService})
local cheers=make("Sound",{Name="ClamillionCrowd",SoundId="rbxassetid://117750774203463",Volume=0.55,Parent=SoundService})
local inLobby=true
local lobbyMusic=make("Sound",{Name="ClamillionLobbyMusic",SoundId="rbxassetid://1842174239",Looped=true,Volume=.13,Parent=SoundService})
lobbyMusic:Play()
local reactions={
 applause=make("Sound",{Name="PoliteApplause",SoundId="rbxassetid://84899279237788",Volume=.25,Parent=SoundService}),
 wow=make("Sound",{Name="CrowdWow",SoundId="rbxassetid://88495424108255",Volume=.65,Parent=SoundService}),
 aww=make("Sound",{Name="CrowdAww",SoundId="rbxassetid://9114010229",Volume=.42,Parent=SoundService})
}
local reactionUntil=0
local onReaction -- set once the crowd/effects are defined below
local setHype, jumbo, collectFx, buildCrowd -- crowd + arena effects, defined further down
-- One crowd-cheer sound for every accepted answer; rarity only changes how loud and how long
-- the crowd cheers (Common = polite, Extremely Rare = the place goes wild).
local CHEER = {
 common = { volume = 0.16, seconds = 1.6 },
 too_clever = { volume = 0.22, seconds = 1.8 },
 uncommon = { volume = 0.3, seconds = 2.0 },
 rare = { volume = 0.5, seconds = 2.5 },
 very_rare = { volume = 0.75, seconds = 3.1 },
 extremely_rare = { volume = 1.0, seconds = 4.0 },
}
local cheerToken = 0
local function crowdCheer(volume, seconds)
 if not Settings.audio then return end
 cheerToken += 1
 local token = cheerToken
 cheers:Stop()
 cheers.Volume = volume; cheers.TimePosition = 0; cheers:Play()
 task.delay(seconds, function()
  if token == cheerToken and cheers.IsPlaying then TweenService:Create(cheers, TweenInfo.new(0.6), { Volume = 0 }):Play() end
 end)
end
local function react(result)
 if onReaction then onReaction(result) end
 if not Settings.audio then return end
 for _,sound in pairs(reactions) do sound:Stop() end
 if result.kind~="correct" then
  cheerToken += 1; cheers:Stop()
  local aww=reactions.aww; aww.Volume=.3; aww.TimePosition=0; aww:Play() -- gentle "aww" when nothing was accepted
  return
 end
 local c = CHEER[result.tier] or CHEER.common
 reactionUntil=os.clock()+c.seconds
 crowdCheer(c.volume, c.seconds)
end
local voice
pcall(function()
 voice=Instance.new("AudioTextToSpeech");voice.Name="ClamillionHostVoice";voice.VoiceId="11";voice.Speed=1.0;voice.Pitch=0;voice.Volume=1.6;voice.Parent=SoundService -- Roblox's "Host voice" (female, its most natural voice), natural speed (keep in sync with Config.Pacing)
 local output=Instance.new("AudioDeviceOutput");output.Parent=voice
 local wire=Instance.new("Wire");wire.SourceInstance=voice;wire.TargetInstance=output;wire.Parent=voice
end)
task.spawn(function() pcall(function() ContentProvider:PreloadAsync({music,cheers,lobbyMusic,reactions.applause,reactions.wow,reactions.aww}) end) end)
local hushHost
local function stopIntroAudio()
 music:Stop();cheers:Stop()
 for _,s in pairs(reactions) do s:Stop() end
 if hushHost then hushHost() elseif voice then pcall(function() voice:Pause() end) end
end
-- Host voice: lines play back-to-back. If a new line arrives while she's still talking it waits
-- for her to finish (plus a short breath) instead of cutting him off mid-sentence.
local HOST_BEAT = 0.25
local speechQueue, speaking, speechGen = {}, false, 0
local function speechLength(text) return #text * 0.08 + 0.2 end -- fallback; real length is read from the voice once loaded
local function speak(text)
 if not Settings.audio or not voice then return end
 table.insert(speechQueue, text)
 if speaking then return end
 speaking = true
 local gen = speechGen
 task.spawn(function()
  while #speechQueue > 0 and gen == speechGen do
   local line = table.remove(speechQueue, 1)
   local length = speechLength(line)
   pcall(function()
    voice:Pause(); voice.Text = line; voice.TimePosition = 0
    voice:Play()
    if voice.TimeLength and voice.TimeLength > 0 then length = voice.TimeLength end
   end)
   local started = os.clock()
   while gen == speechGen and os.clock() - started < length + HOST_BEAT do
    task.wait(0.05)
    local ok, len = pcall(function() return voice.TimeLength end)
    if ok and len and len > 0 then length = len end
   end
  end
  if gen == speechGen then speaking = false end
 end)
end
hushHost = function()
 speechGen += 1
 table.clear(speechQueue)
 speaking = false
 if voice then pcall(function() voice:Pause() end) end
end

---------------------------------------------------------------- root gui
local gui = make("ScreenGui", {
	Name = "ClamillionGui", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui"),
})

---------------------------------------------------------------- lobby
-- Welcome banner shown whenever you're in the lobby: big bouncy logo, the three modes
-- colour-matched to their pads, and a live status line.
local lobby = panel({ Name = "Lobby", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.new(0.8, 0, 0, 102), Parent = gui })
maxSize(430).Parent = lobby
pad(6).Parent = lobby
lobby.Candy.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 92, 182)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(140, 70, 240)), ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 150, 255)) })
lobby.Candy.Rotation = 0
local logo = label({ Text = "CLAMILLION!", Font = UI.FontBlack, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -2), Size = UDim2.new(1, 0, 0, 30), Parent = lobby }, 30)
logo:FindFirstChildOfClass("UIStroke").Thickness = 3
make("UIGradient", { Name = "Shine", Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 250, 180), Color3.fromRGB(255, 190, 30)), Parent = logo })
local chips = make("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 29), Size = UDim2.new(1, 0, 0, 30), Parent = lobby })
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = chips })
for i, key in ipairs({ "Solo", "Duel", "Triple" }) do
	local m = UI.Modes[key]
	local chip = make("Frame", { Name = "Mode" .. key, LayoutOrder = i, BackgroundColor3 = m.color, Size = UDim2.new(0.31, 0, 1, 0), Rotation = (i - 2) * 2, Parent = chips }, { corner(10), stroke(C.Outline, 2) })
	label({ Text = m.icon .. " " .. m.label, Font = UI.FontBlack, Size = UDim2.new(1, 0, 0.6, 0), Parent = chip }, 16)
	local players = label({ Text = m.players, Font = UI.FontBody, TextColor3 = C.Ink, Position = UDim2.new(0, 0, 0.56, 0), Size = UDim2.new(1, 0, 0.42, 0), Parent = chip }, 11)
	-- tap a mode to be taken to an open pad for it
	local go = make("TextButton", { Name = "Go" .. key, Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, AutoButtonColor = false, Parent = chip })
	go.MouseEnter:Connect(function() players.Text = "TAP TO GO ➜"; chip.Rotation = 0 end)
	go.MouseLeave:Connect(function() players.Text = m.players; chip.Rotation = (i - 2) * 2 end)
	go.Activated:Connect(function()
		Remotes.QueueRequest:FireServer({ goTo = key })
		players.Text = "GOING! ✨"
		-- once we've arrived, swing the camera in behind us so the pad is right in front
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			local from = root.Position
			task.spawn(function()
				local t0 = os.clock()
				repeat task.wait(0.05) until (root.Position - from).Magnitude > 4 or os.clock() - t0 > 1.5
				local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
				if look.Magnitude < 0.1 then return end
				look = look.Unit
				workspace.CurrentCamera.CFrame = CFrame.lookAt(root.Position - look * 15 + Vector3.new(0, 6, 0), root.Position + look * 12)
			end)
		end
		task.delay(1.2, function() players.Text = m.players end)
	end)
end
local queueLabel = label({ Text = "Hop on a numbered pad to play!", Font = UI.FontBody, TextColor3 = C.White, Position = UDim2.new(0, 0, 0, 62), Size = UDim2.new(1, 0, 0, 16), Parent = lobby }, 15)
local cancelQueue=button({Text="LEAVE PAD",AnchorPoint=Vector2.new(0.5,0),Position=UDim2.new(0.5,0,0,73),Size=UDim2.new(0.4,0,0,20),Visible=false,Parent=lobby},"pink",12)
do local p=cancelQueue:FindFirstChildOfClass("UIPadding"); if p then p.PaddingTop=UDim.new(0,2);p.PaddingBottom=UDim.new(0,2) end end
-- little tip that cycles under the status line
local tips = { "Tap SOLO, 1V1 or 1V1V1 up here to go to its pads!", "Rare answers = BIG points!", "Spin the Daily Wheel for a free title!", "Beat the Mini Obby while you wait!", "Fill a pad with friends to start a show!" }
local tipLabel = label({ Text = tips[1], Font = UI.FontBody, TextColor3 = C.Gold, Position = UDim2.new(0, 0, 0, 77), Size = UDim2.new(1, 0, 0, 14), Parent = lobby }, 12)
-- chunky side buttons (left), shop stays on the right
local invBtn = menuButton({ Name = "InventoryButton", AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 14, .5, -108), Size = UDim2.fromOffset(92, 98), Rotation = -3, Parent = gui }, "🎒", "MY STUFF", MENU_COLORS.stuff)
local howBtn = menuButton({ Name = "HowToPlayButton", AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 14, .5, 0), Size = UDim2.fromOffset(92, 98), Rotation = 3, Parent = gui }, "📖", "HOW TO PLAY", MENU_COLORS.how)
local settingsBtn = menuButton({ Name = "SettingsButton", AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 14, .5, 108), Size = UDim2.fromOffset(92, 98), Rotation = -3, Parent = gui }, "⚙️", "SETTINGS", MENU_COLORS.settings)
task.spawn(function()
	local i, t = 1, 0
	while true do
		local dt = RunService.RenderStepped:Wait()
		t += dt
		if lobby.Visible and not Settings.reducedMotion then
			logo.Rotation = math.sin(t * 2.2) * 2.5
			logo.Shine.Offset = Vector2.new(0, math.sin(t * 1.5) * 0.15)
		else
			logo.Rotation = 0
		end
		if t > 5 then t = 0; i = i % #tips + 1; tipLabel.Text = tips[i] end
	end
end)

---------------------------------------------------------------- modals
-- When a button under the mouse is hidden or rebuilt, Roblox can leave the "pointing hand"
-- cursor stuck on screen. Nudging the mouse icon forces the normal arrow back.
local function resetCursor()
	local UIS = game:GetService("UserInputService")
	UIS.MouseIcon = "rbxasset://textures/Cursors/KeyboardMouse/ArrowFarCursor.png"
	task.delay(0.05, function() UIS.MouseIcon = "" end)
end
local function modal(name, title, height)
	-- the dim backdrop is a plain Frame (not a button) so the whole screen doesn't show a pointing-hand cursor
	local shade = make("Frame", { Name = name, Active = true, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20, Parent = gui })
	shade:GetPropertyChangedSignal("Visible"):Connect(function() if not shade.Visible then resetCursor() end end)
	-- centred card that also fits small phone screens (shrinks to 90% of the screen height)
	local box = panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.9, 0, 0.9, 0), ZIndex = 21, Parent = shade })
	maxSize(520, height).Parent = box
	pad(18).Parent = box
	local titleLabel = label({ Name = "Title", Text = title, Font = UI.FontBlack, TextColor3 = C.Gold, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -2), Size = UDim2.new(1, -100, 0, 38), ZIndex = 22, Parent = box }, 32)
	titleLabel:FindFirstChildOfClass("UIStroke").Thickness = 3
	local close = button({ Text = "X", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 4, 0, -4), Size = UDim2.new(0, 42, 0, 42), ZIndex = 22, Parent = box }, "pink", 20)
	close.Activated:Connect(function() shade.Visible = false end)
	-- clicking the dim area outside the card closes it
	shade.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local p, a, sz = input.Position, box.AbsolutePosition, box.AbsoluteSize
		if p.X < a.X or p.X > a.X + sz.X or p.Y < a.Y or p.Y > a.Y + sz.Y then shade.Visible = false end
	end)
	local body = make("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 46), Size = UDim2.new(1, 0, 1, -46), ZIndex = 22, Parent = box })
	return shade, body
end

-- How to Play: a tidy, centred card with one step per row and colour-coded rarity points.
local howModal, howBody = modal("HowToPlay", "★ How to Play ★", 520)
make("UIListLayout", { Padding = UDim.new(0.018, 0), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = howBody })
local howSteps = {
	{ "🎯", "Hop on a pad: SOLO, 1V1 or 1V1V1", Color3.fromRGB(255, 200, 40) },
	{ "⏱", "3 rounds × 5 questions • 30 seconds each", Color3.fromRGB(60, 170, 255) },
	{ "⌨", "Type your answer, then hit LOCK IT IN!", Color3.fromRGB(80, 230, 140) },
	{ "🔁", "Wrong? No worries — try again!", Color3.fromRGB(255, 120, 190) },
	{ "🏆", "Rarer answers = MORE points. Most points wins!", Color3.fromRGB(255, 150, 40) },
}
for i, step in ipairs(howSteps) do
	local row = make("Frame", { LayoutOrder = i, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.82, Size = UDim2.new(1, 0, 0.125, 0), ZIndex = 22, Parent = howBody }, { corner(16) })
	local badge = make("Frame", { BackgroundColor3 = step[3], AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0), Size = UDim2.new(1, 0, 0.82, 0), SizeConstraint = Enum.SizeConstraint.RelativeYY, ZIndex = 23, Parent = row }, { corner(100), stroke(C.Outline, 2.5) })
	label({ Text = step[1], Size = UDim2.fromScale(1, 1), ZIndex = 24, Parent = badge }, 24)
	label({ Text = step[2], Font = UI.FontBody, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0.15, 0, 0.12, 0), Size = UDim2.new(0.83, 0, 0.76, 0), ZIndex = 23, Parent = row }, 21)
end
local chips = make("Frame", { LayoutOrder = 10, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.13, 0), ZIndex = 22, Parent = howBody })
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0.012, 0), Parent = chips })
for i, key in ipairs({ "common", "too_clever", "uncommon", "rare", "very_rare", "extremely_rare" }) do
	local points = ({ 10, 15, 30, 60, 85, 100 })[i]
	local chip = make("Frame", { LayoutOrder = i, BackgroundColor3 = UI.Rarity[key].color, Size = UDim2.new(0.155, 0, 1, 0), ZIndex = 23, Parent = chips }, { corner(12), stroke(C.Outline, 2.5) })
	label({ Text = "+" .. points, Font = UI.FontBlack, TextColor3 = C.Ink, Size = UDim2.new(1, 0, 0.58, 0), ZIndex = 24, Parent = chip }, 22)
	label({ Text = UI.Rarity[key].label, Font = UI.FontBody, TextColor3 = C.Ink, Position = UDim2.new(0, 0, 0.55, 0), Size = UDim2.new(1, 0, 0.4, 0), ZIndex = 24, Parent = chip }, 11)
end
local gotIt = button({ LayoutOrder = 20, Text = "GOT IT!", Size = UDim2.new(0.55, 0, 0.12, 0), ZIndex = 23, Parent = howBody }, "gold", 26)
gotIt.Activated:Connect(function() howModal.Visible = false end)

local settingsModal, settingsBody = modal("Settings", "Settings", 350)
make("UIListLayout", { Padding = UDim.new(0, 10), Parent = settingsBody })
local function toggleRow(text, key)
	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), ZIndex = 22, Parent = settingsBody })
	label({ Text = text, Font = UI.FontBody, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0.7, 0, 1, 0), ZIndex = 22, Parent = row }, 20)
	local b = button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.28, 0, 1, 0), ZIndex = 22, Parent = row }, "gold", 18)
	local function refresh()
		b.Text = Settings[key] and "ON" or "OFF"
		b.BackgroundColor3 = Settings[key] and C.Gold or C.PanelDark
		b.TextColor3 = Settings[key] and C.Ink or C.White
	end
	b.Activated:Connect(function() Settings[key] = not Settings[key]; if key=="audio" then if not Settings.audio then stopIntroAudio();lobbyMusic:Stop() elseif inLobby then lobbyMusic:Play() end end; refresh() end)
	refresh()
end
toggleRow("Host captions", "captions")
toggleRow("Reduced motion", "reducedMotion")
toggleRow("Visual effects", "effects")
toggleRow("Music / crowd / host voice", "audio")
label({ Text = "Lobby music, show music and audience reactions.", Font = UI.FontBody, TextColor3 = C.Muted, Size = UDim2.new(1, 0, 0, 22), ZIndex = 22, Parent = settingsBody }, 15)

howBtn.Activated:Connect(function() howModal.Visible = true end)
settingsBtn.Activated:Connect(function() settingsModal.Visible = true end)

---------------------------------------------------------------- match HUD
local hud = make("Frame", { Name = "Match", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = gui })

local progress = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.new(0.5, 0, 0, 34),
	BackgroundTransparency = 0.1, BackgroundColor3 = C.PanelDark, TextColor3 = C.Gold, Font = UI.FontBlack, Text = "", Parent = hud }, 20)
corner(17).Parent = progress
pad(6).Parent = progress
maxSize(420).Parent = progress

-- In-match buttons live in the bottom corners so they never cover Roblox's own top-bar buttons.
local gear = button({ Name = "SettingsButton", Text = "⚙", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), Size = UDim2.new(0, 46, 0, 46), Parent = hud }, "dark", 24)
gear.Activated:Connect(function() settingsModal.Visible = true end)

-- standings (bottom right)
local standingsFrame = panel({ Name = "Standings", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -12), Size = UDim2.new(0, 236, 0, 122), BackgroundTransparency = 0.08, Parent = hud })
local layoutHud -- defined once the answer box / reveal card exist
pad(8).Parent = standingsFrame
make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = standingsFrame })
local rows = {}
local function buildStandings(contestants)
	standingsFrame.Size=UDim2.fromOffset(236,16+36*#contestants)
	if layoutHud then task.defer(layoutHud) end
	for _, r in pairs(rows) do r.frame:Destroy() end
	rows = {}
	for _, c in ipairs(contestants) do
		local seat = UI.Seats[c.seat]
		local f = make("Frame", { BackgroundColor3 = C.PanelDark, BackgroundTransparency = 0.2, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = c.seat, Parent = standingsFrame }, { corner(8) })
		make("Frame", { BackgroundColor3 = seat.color, BorderSizePixel = 0, Size = UDim2.new(0, 5, 1, 0) }, { corner(3) }).Parent = f
		local nameL = label({ Text = seat.icon .. " " .. c.name, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(0.55, -12, 1, 0), Font = UI.Font, Parent = f }, 16)
		if c.seat == player:GetAttribute("ClamillionSeat") then nameL.TextColor3 = C.Gold end
		local statusL = label({ Text = "", Position = UDim2.new(0.55, 0, 0, 0), Size = UDim2.new(0.12, 0, 1, 0), Parent = f }, 16)
		local scoreL = label({ Text = UI.formatNumber(c.score), TextXAlignment = Enum.TextXAlignment.Right, Font = UI.FontBlack, TextColor3 = C.Gold, Position = UDim2.new(0.67, 0, 0, 0), Size = UDim2.new(0.33, -6, 1, 0), Parent = f }, 18)
		rows[c.seat] = { frame = f, name = nameL, status = statusL, score = scoreL, value = c.score, displayName = c.name }
	end
end
local statusIcons = { Thinking = "💭", Locked = "🔒", TimeUp = "⏱", Withdrawn = "✖", Out = "—", Winner = "🏆", Waiting = "" }
local function setRowStatus(seat, key)
	local r = rows[seat]
	if r then r.status.Text = statusIcons[key] or "" end
end
local function setRowScore(seat, value)
	local r = rows[seat]
	if r then r.value = value; r.score.Text = UI.formatNumber(value) end
end

-- centre card (question / banner / reveal share this slot)
local function centreCard(name)
	local f = panel({ Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.43), Size = UDim2.new(0.9, 0, 0.36, 0), Visible = false, Parent = hud })
	make("UISizeConstraint", { MaxSize = Vector2.new(860, 320), MinSize = Vector2.new(0, 190), Parent = f })
	f.Candy.Rotation = 90
	f.Candy.Color = ColorSequence.new(Color3.fromRGB(70, 150, 255), Color3.fromRGB(120, 60, 235))
	pad(16).Parent = f
	return f
end

local qCard = centreCard("Question")
local badge=label({Text="★",TextColor3=C.Gold,Position=UDim2.new(0,-8,0,-28),Size=UDim2.fromOffset(44,44),Rotation=-12,Parent=qCard},38)
local qCategory = label({ Text = "", Font = UI.FontBlack, TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0.16, 0), Parent = qCard }, 22)
local qPrompt = label({ Text = "", Font = UI.Font, Position = UDim2.new(0, 0, 0.19, 0), Size = UDim2.new(1, 0, 0.56, 0), Parent = qCard }, 42)
local timerText = label({ Text = "30", Font = UI.FontBlack, Position = UDim2.new(0, 0, 0.8, 0), Size = UDim2.new(0.12, 0, 0.2, 0), Parent = qCard }, 30)
local timerBack = make("Frame", { BackgroundColor3 = C.PanelDark, Position = UDim2.new(0.14, 0, 0.86, 0), Size = UDim2.new(0.86, 0, 0.08, 0), Parent = qCard }, { corner(6) })
local timerFill = make("Frame", { BackgroundColor3 = C.Gold, Size = UDim2.fromScale(1, 1), Parent = timerBack }, { corner(6) })

local banner = centreCard("Banner")
local bannerTitle = label({ Text = "", Font = UI.FontBlack, TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0.42, 0), Parent = banner }, 56)
local bannerSub = label({ Text = "", Font = UI.FontBody, Position = UDim2.new(0, 0, 0.48, 0), Size = UDim2.new(1, 0, 0.52, 0), Parent = banner }, 24)

local reveal = centreCard("Reveal")
reveal.AnchorPoint = Vector2.new(0.5, 1)
reveal.Position = UDim2.new(0.5, 0, 1, -16)
reveal.Size = UDim2.new(0.9, 0, 0.32, 0)
reveal:FindFirstChildOfClass("UISizeConstraint").MaxSize = Vector2.new(760, 240)
reveal:FindFirstChildOfClass("UISizeConstraint").MinSize = Vector2.new(0, 170)
local revealBand = make("Frame", { BackgroundColor3 = C.Gold, BorderSizePixel = 0, Position = UDim2.new(0, -16, 0, -16), Size = UDim2.new(1, 32, 0, 8), Parent = reveal })
local revealName = label({ Text = "", Font = UI.FontBlack, Size = UDim2.new(1, 0, 0.18, 0), Parent = reveal }, 26)
local revealAnswer = label({ Text = "", Font = UI.FontBlack, Position = UDim2.new(0, 0, 0.21, 0), Size = UDim2.new(1, 0, 0.3, 0), Parent = reveal }, 46)
local revealTier = label({ Text = "", Font = UI.FontBlack, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.55, 0), Size = UDim2.new(0.6, 0, 0.15, 0), BackgroundTransparency = 0, BackgroundColor3 = C.PanelDark, Parent = reveal }, 22)
corner(10).Parent = revealTier
local revealPoints = label({ Text = "", Font = UI.FontBlack, TextColor3 = C.Gold, Position = UDim2.new(0, 0, 0.74, 0), Size = UDim2.new(0.5, 0, 0.24, 0), Parent = reveal }, 34)
local revealScore = label({ Text = "", Font = UI.Font, TextColor3 = C.Muted, Position = UDim2.new(0.5, 0, 0.74, 0), Size = UDim2.new(0.5, 0, 0.24, 0), Parent = reveal }, 26)
local revealStroke = reveal:FindFirstChildOfClass("UIStroke")

local recap = centreCard("Recap")
local recapTitle = label({ Text = "RESULTS", Font = UI.FontBlack, TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0.14, 0), Parent = recap }, 22)
local recapCols = make("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0.17, 0), Size = UDim2.new(1, 0, 0.64, 0), Parent = recap })
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0.02, 0), HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = recapCols })
local recapNote = label({ Text = "", Font = UI.FontBody, TextColor3 = C.Muted, Position = UDim2.new(0, 0, 0.84, 0), Size = UDim2.new(1, 0, 0.16, 0), Parent = recap }, 18)

-- host caption
local caption = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.45, 0, 0, 56), Size = UDim2.new(0.55, 0, 0, 40),
	BackgroundTransparency = 0.2, BackgroundColor3 = C.PanelDark, Font = UI.FontBody, Visible = false, Parent = hud }, 20)
corner(10).Parent = caption
pad(8).Parent = caption
maxSize(520).Parent = caption

-- answer area (bottom centre)
local answerArea = panel({ Name="AnswerArea", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.new(0.92, 0, 0, 96), Visible = false, Parent = hud })
maxSize(680).Parent = answerArea
pad(12).Parent = answerArea
local answerBox = make("TextBox", {
	Name="AnswerBox", PlaceholderText = "Got a rare answer? Type here!", Text = "", ClearTextOnFocus = false, TextScaled = true,
	Font = UI.Font, TextColor3 = C.Ink, PlaceholderColor3 = Color3.fromRGB(120, 130, 160), BackgroundColor3 = C.White,
	Position = UDim2.new(0.17, 4, 0, 0), Size = UDim2.new(0.51, -8, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = answerArea,
}, { corner(10), maxText(26), pad(10) })
local lockBtn = button({ Name="LockButton", Text = "LOCK IT IN!", Position = UDim2.new(0.68, 4, 0, 0), Size = UDim2.new(0.32, -4, 1, 0), Parent = answerArea }, "gold", 26)
-- HINT ? button (left of the answer box): 50 R$ for a Very Rare (85-point) answer to this question
local hintUI = {}
hintUI.btn = button({ Name = "HintButton", Text = "HINT ?", TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(0.17, -4, 1, 0), Parent = answerArea }, "pink", 24)
hintUI.price = label({ Name = "Price", Text = "R$ 50", Font = UI.FontBlack, TextColor3 = C.Gold, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 4), Size = UDim2.new(1, 0, 0.4, 0), Parent = hintUI.btn }, 18)
hintUI.banner = label({ Name = "HintBanner", Text = "", Font = UI.FontBlack, TextColor3 = C.Ink, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 0, -52), Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 0, BackgroundColor3 = C.Gold, Visible = false, ZIndex = 4, Parent = answerArea }, 20)
corner(8).Parent = hintUI.banner
-- EMOTE button (bottom left, always there): play any emote you own, any time; everyone sees it
local emoteUI = { cool = 0 }
emoteUI.btn = menuButton({ Name = "EmoteButton", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -68), Size = UDim2.fromOffset(156, 60), Rotation = -2, ZIndex = 8, Parent = gui }, "💃", "EMOTE", MENU_COLORS.emote, true)
emoteUI.picker = make("Frame", { Name = "EmotePicker", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -138), Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, BackgroundColor3 = C.PanelDark, BackgroundTransparency = 0.1, Visible = false, ZIndex = 8, Parent = gui }, { corner(16), stroke(C.Gold, 3), pad(8) })
make("UIGridLayout", { CellSize = UDim2.fromOffset(88, 62), CellPadding = UDim2.fromOffset(8, 8), FillDirectionMaxCells = 5, SortOrder = Enum.SortOrder.LayoutOrder, Parent = emoteUI.picker })
local lockedLabel = label({ Name="LockedOverlay", Text = "", Font = UI.FontBlack, TextColor3 = C.Gold, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = C.Panel, Visible = false, ZIndex = 3, Parent = answerArea }, 26)

local retryFeedback=label({Name="RetryFeedback",Text="Incorrect answer, try again",TextColor3=Color3.fromRGB(255,120,105),AnchorPoint=Vector2.new(0,1),Position=UDim2.new(0,0,0,-16),Size=UDim2.new(1,0,0,30),BackgroundTransparency=.08,BackgroundColor3=C.PanelDark,Visible=false,Parent=answerArea},20)
corner(8).Parent=retryFeedback

-- Kid-safe answer box: the box SHOWS bad words starred out (Shared.Profanity) while the real
-- text the player typed is kept in answerReal and is what gets submitted. Starring keeps the
-- length the same, so every edit in the box maps 1:1 onto the real text.
local Profanity = require(root.Shared.Profanity)
local answerReal = ""
local answerShown = ""
local answerSetting = false
local function setAnswerText(t)
	answerReal = t or ""
	answerShown = Profanity.mask(answerReal)
	answerSetting = true
	answerBox.Text = answerShown
	answerSetting = false
end

local shakeToken=0
local function retryAnswer()
 setAnswerText("")
 retryFeedback.Text="Incorrect answer, try again"
 retryFeedback.TextColor3=C.Danger
 lockedLabel.Visible=false
 lockBtn.Text="LOCK IT IN!"
 answerBox.TextEditable=true
 retryFeedback.Visible=true
 shakeToken+=1
 local token=shakeToken
 local original=UDim2.new(0.17,4,0,0)
 answerBox.BackgroundColor3=Color3.fromRGB(255,225,220)
 if not Settings.reducedMotion then
  task.spawn(function()
   for _,x in ipairs({-7,7,-5,5,-2,2,0}) do
    if token~=shakeToken then return end
    answerBox.Position=original+UDim2.fromOffset(x,0)
    task.wait(.035)
   end
   answerBox.Position=original
  end)
 end
 task.delay(.5,function()if token==shakeToken then answerBox.BackgroundColor3=C.White end end)
 -- Do not call CaptureFocus here: focus changes can re-trigger submission.
end

-- results
local results = panel({ Name = "Results", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.9, 0, 0, 380), Visible = false, ZIndex = 10, Parent = gui })
maxSize(560).Parent = results
pad(18).Parent = results
local resultsTitle = label({ Text = "🏆 WINNER", Font = UI.FontBlack, TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 34), ZIndex = 11, Parent = results }, 30)
local resultsWinner = label({ Text = "", Font = UI.FontBlack, Position = UDim2.new(0, 0, 0, 38), Size = UDim2.new(1, 0, 0, 48), ZIndex = 11, Parent = results }, 40)
local resultsList = make("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 96), Size = UDim2.new(1, 0, 0, 150), ZIndex = 11, Parent = results })
make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = resultsList })
local againBtn = button({ Text = "PLAY AGAIN", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(0.5, -6, 0, 52), ZIndex = 11, Parent = results }, "gold", 22)
local lobbyBtn = button({ Text = "RETURN TO LOBBY", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.new(0.5, -6, 0, 52), ZIndex = 11, Parent = results }, "dark", 20)

---------------------------------------------------------------- state
local state = {
	inMatch = false, seat = nil, participating = false, locked = false,
	deadline = 0, duration = 30, questionActive = false, maxLength = 60, finalSent = false,
}
local revealToken = 0
local suggestion=nil

local function hideCentre()
	qCard.Visible = false; banner.Visible = false; reveal.Visible = false; recap.Visible = false
end

local function showBanner(title, sub)
	hideCentre()
	bannerTitle.Text = title
	bannerSub.Text = sub or ""
	banner.Visible = true
	pop(banner)
end

local captionToken = 0
local function showCaption(text)
	captionToken += 1
	local token = captionToken
	caption.Text = "🎤  " .. text
	caption.Visible = state.inMatch and (Settings.captions or state.inIntro)
	task.delay(6, function() if token == captionToken then caption.Visible = false end end)
end

local function showLobby(visible)
 inLobby=visible
 if visible and Settings.audio then if not lobbyMusic.IsPlaying then lobbyMusic:Play() end else lobbyMusic:Stop() end
	-- the top lobby card stays hidden while you're on a mini obby run
	lobby.Visible = visible and player:GetAttribute("ObbyCP") == nil
	howBtn.Visible = visible
	settingsBtn.Visible = visible
	invBtn.Visible = visible
	if visible then pop(lobby) end
	local icon=gui:FindFirstChild("ShopIcon");if icon then icon.Visible=visible end
end
player:GetAttributeChangedSignal("ObbyCP"):Connect(function()
	local show = inLobby and player:GetAttribute("ObbyCP") == nil
	if show and not lobby.Visible then lobby.Visible = true; pop(lobby)
	elseif not show then lobby.Visible = false end
end)

---------------------------------------------------------------- camera
local camera = workspace.CurrentCamera
local shots = studio:WaitForChild("CameraShots")
local camTween
local currentShot = nil
local function shotCFrame(name)
	local champSeat = tonumber(string.match(name, "^Champion(%d)$"))
	if champSeat then
		-- the victory shot: the champion and their trophy, a little wider than the podium shot
		local podium = studio.Podiums["Podium" .. champSeat]
		local stand = podium.StandPoint.Position
		local toAudience = podium.Body.CFrame.LookVector
		local right = toAudience:Cross(Vector3.yAxis).Unit
		-- looking down a little, so the winner and trophy sit in the upper half (the dance picker is below)
		local focus = stand + right * 1.6 + Vector3.new(0, -1.2, 0)
		return CFrame.lookAt(stand + right * 1.6 + toAudience * 19 + Vector3.new(0, 8, 0), focus)
	end
	if name == "Player" then
		-- answering: frame YOUR contestant low in the shot, under the question card
		local podium = state.seat and studio.Podiums:FindFirstChild("Podium" .. state.seat)
		if podium then
			local stand = podium.StandPoint.CFrame
			local toAudience = podium.Body.CFrame.LookVector
			local head = stand.Position + Vector3.new(0, 1.6, 0)
			local camPos = head + toAudience * 16 + Vector3.new(0, 2.5, 0)
			return CFrame.lookAt(camPos, head + Vector3.new(0, 3.8, 0))
		end
		name = "Question"
	end
	local seat = tonumber(string.match(name, "^Podium(%d)$"))
	if seat then
		-- tall portrait podium: frame the contestant on their pedestal plus the podium display
		local podium = studio.Podiums["Podium" .. seat]
		local stand = podium.StandPoint.CFrame
		local toAudience = podium.Body.CFrame.LookVector
		local head = stand.Position + Vector3.new(0, 1.6, 0)
		local focus = head + Vector3.new(0, -3.4, 0) + toAudience * 3
		local camPos = focus + toAudience * 19 + Vector3.new(0, 1.5, 0)
		return CFrame.lookAt(camPos, focus)
	end
	local p = shots:FindFirstChild(name)
	return p and p.CFrame
end
local function cut(name)
	-- Reduced motion uses static cuts, preserving the intended shot.
	local cf = shotCFrame(name)
	if not cf then return end
	currentShot = name
	camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	if camTween then camTween:Cancel() end
	if Settings.reducedMotion then
		camera.CFrame = cf
	else
		camTween = TweenService:Create(camera, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = cf })
		camTween:Play()
	end
end
-- In the lobby, players (and their camera) face the Prize Palace rewards booth. The server turns
-- the character toward it just after spawning / returning; then we swing the camera in behind.
local function faceBooth()
	local char = player.Character
	local root = char and char:WaitForChild("HumanoidRootPart", 5)
	if not root then return end
	local lobbyModel = workspace:FindFirstChild("ShowLobby")
	local booth = lobbyModel and lobbyModel:FindFirstChild("RewardsStand", true)
	local target = booth and booth:GetPivot().Position or Vector3.new(0, 0, 271)
	local function flatDir()
		local d = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
		return d.Magnitude > 0.1 and d.Unit or Vector3.new(0, 0, 1)
	end
	local started = os.clock()
	repeat task.wait(0.1)
	until os.clock() - started > 2 or (not root.Anchored and (root.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit:Dot(flatDir()) > 0.9)
	if state.inMatch or root.Anchored or not root.Parent then return end
	local dir = flatDir()
	local cam = workspace.CurrentCamera
	cam.CFrame = CFrame.lookAt(root.Position - dir * 14 + Vector3.new(0, 5, 0), root.Position + dir * 30 + Vector3.new(0, 2, 0))
end
player.CharacterAdded:Connect(function() task.spawn(faceBooth) end)
if player.Character then task.spawn(faceBooth) end
local function restoreCamera()
	task.spawn(faceBooth)
	currentShot = nil
	if camTween then camTween:Cancel() end
	camera = workspace.CurrentCamera
	camera.FieldOfView=70
	camera.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then camera.CameraSubject = hum end
end
-- Roblox's default camera can reset CameraType (e.g. when a character loads). Re-assert the shot.
RunService:BindToRenderStep("ClamillionCamera", Enum.RenderPriority.Camera.Value + 1, function()
	if not (state.inMatch and currentShot) then return end
	local cam = workspace.CurrentCamera
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
		local cf = shotCFrame(currentShot)
		if cf then cam.CFrame = cf end
	end
end)

---------------------------------------------------------------- effects
local function burst(seat, colors, count)
	if not Settings.effects then return end
	local podium = studio.Podiums:FindFirstChild("Podium" .. tostring(seat))
	if not podium then return end
	local att = make("Attachment", { Position = Vector3.new(0, 3, 0), Parent = podium.Body })
	local pe = make("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(colors[1], colors[2] or colors[1]), LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) }),
		Speed = NumberRange.new(12, 22), SpreadAngle = Vector2.new(35, 35), Lifetime = NumberRange.new(0.8, 1.5),
		Acceleration = Vector3.new(0, -18, 0), Rate = 0, Parent = att,
	})
	pe:Emit(count or 60)
	Debris:AddItem(att, 3)
end

---------------------------------------------------------------- answering
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function setAnswerMode(mode, text)
	local errorText=answerArea:FindFirstChild("RetryFeedback");if errorText then errorText.Visible=false end
	-- mode: "answer" | "locked" | "spectate" | "hidden"
	answerArea.Visible = mode ~= "hidden"
	lockedLabel.Visible = mode == "locked" or mode == "spectate"
	answerBox.TextEditable = mode == "answer"
	lockBtn.Text = "LOCK IT IN!"
	hintUI.btn.Visible = mode == "answer"
	if mode ~= "answer" then hintUI.banner.Visible = false end
	if mode == "locked" then lockedLabel.Text = "🔒 LOCKED IN: " .. (text or "") end
	if mode == "spectate" then lockedLabel.Text = text or "Watching this one" end
end

local draftQueued = false
local function sendDraft()
	if state.questionActive and state.participating and not state.locked then
		Remotes.SubmitAnswer:FireServer(answerReal, state.questionToken)
	end
end
answerBox:GetPropertyChangedSignal("Text"):Connect(function()
	local t = answerBox.Text
	-- our own writes (clearing, starring, hints) also fire this, a frame later: only real edits count
	if answerSetting or t == answerShown then return end
	do
		-- the player edited the box: apply the same edit to the real text
		local old = answerShown
		local p = 0
		while p < #old and p < #t and string.byte(old, p + 1) == string.byte(t, p + 1) do p += 1 end
		local s = 0
		while s < #old - p and s < #t - p and string.byte(old, #old - s) == string.byte(t, #t - s) do s += 1 end
		local real = string.sub(answerReal, 1, p) .. string.sub(t, p + 1, #t - s) .. string.sub(answerReal, #answerReal - s + 1)
		local len = utf8.len(real)
		if len and len > state.maxLength then real = string.sub(real, 1, utf8.offset(real, state.maxLength + 1) - 1) end
		answerReal = real
		answerShown = Profanity.mask(real)
		if answerShown ~= t then
			-- star out (or un-star) as they type, keeping the cursor where it was
			local cursor = answerBox.CursorPosition
			answerSetting = true
			answerBox.Text = answerShown
			answerSetting = false
			if cursor > 0 then answerBox.CursorPosition = math.min(cursor, #answerShown + 1) end
		end
	end
	suggestion=nil
 if state.questionActive and not state.locked then lockedLabel.Visible=false;retryFeedback.Visible=false;lockBtn.Text="LOCK IN" end
	if not draftQueued then
		draftQueued = true
		task.delay(0.25, function() draftQueued = false; sendDraft() end)
	end
end)

local function tryLock()
	if state.submitting then return end
	if not (state.questionActive and state.participating) or state.locked then return end
	local text = suggestion or trim(answerReal)
 if suggestion then local s=suggestion;setAnswerText(s);suggestion=nil;text=s end
	if text == "" then
		lockBtn.Text = "TYPE FIRST"
		task.delay(1, function() if not state.locked then lockBtn.Text = "LOCK IN" end end)
		return
	end
	state.submitting=true
	lockBtn.Text = "…"
	task.delay(2,function()state.submitting=false end)
	Remotes.LockAnswer:FireServer(text, state.questionToken)
end
lockBtn.Activated:Connect(tryLock)

-- emotes
local function openEmotePicker()
	for _, c in ipairs(emoteUI.picker:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
	emoteUI.picker.Visible = true
	local ok, s = pcall(function() return Remotes.ShopRequest:InvokeServer("inventory") end)
	local Catalog = require(root.Shared.ShopCatalog)
	local owned = (ok and type(s) == "table" and s.owned) or {}
	local n = 0
	for _, item in ipairs(Catalog.Emotes) do
		if owned[item.id] then
			n += 1
			local b = button({ LayoutOrder = n, Text = item.icon .. "\n" .. item.name, ZIndex = 9, Parent = emoteUI.picker }, "gold", 15)
			b.Activated:Connect(function()
				emoteUI.picker.Visible = false
				if os.clock() < emoteUI.cool then return end
				emoteUI.cool = os.clock() + 3
				Remotes:WaitForChild("Emote"):FireServer(item.id)
			end)
		end
	end
	if n == 0 then
		label({ Text = "No emotes yet!", Font = UI.FontBody, ZIndex = 9, Parent = emoteUI.picker }, 17)
		label({ Text = "Get some in the 🛍 SHOP", Font = UI.FontBody, TextColor3 = C.Gold, ZIndex = 9, Parent = emoteUI.picker }, 15)
	end
end
emoteUI.btn.Activated:Connect(function()
	if emoteUI.picker.Visible then emoteUI.picker.Visible = false return end
	task.spawn(openEmotePicker)
end)
-- anyone's emote (including yours) plays on their character for everybody
task.spawn(function()
	Remotes:WaitForChild("Emote").OnClientEvent:Connect(function(userId, emoteId)
		local who = Players:GetPlayerByUserId(userId)
		if who and who.Character then pcall(function() require(root.Shared.EmotePlayer).play(who.Character, emoteId) end) end
	end)
end)

-- hints
hintUI.note = function(text)
	hintUI.token = (hintUI.token or 0) + 1
	local token = hintUI.token
	hintUI.banner.Text = text; hintUI.banner.Visible = true
	task.delay(3, function() if hintUI.token == token then hintUI.banner.Visible = false end end)
end
local function refreshHintPrice()
	if state.hinted then return end -- shows USED until the next question
	local free = (player:GetAttribute("HintCredits") or 0) > 0
	hintUI.price.Text = free and "FREE" or "R$ 50"
	hintUI.price.TextColor3 = free and C.Good or C.Gold
end
player:GetAttributeChangedSignal("HintCredits"):Connect(refreshHintPrice)
refreshHintPrice()
hintUI.btn.Activated:Connect(function()
	if hintUI.busy or not (state.questionActive and state.participating) or state.locked or state.hinted then return end
	hintUI.busy = true
	hintUI.btn.Text = "…"
	task.spawn(function()
		local ok, res = pcall(function() return Remotes.ShopRequest:InvokeServer("hint") end)
		hintUI.busy = false
		if not state.hinted then hintUI.btn.Text = "HINT ?" end
		if not ok or type(res) ~= "table" then return end
		if res.reason == "soon" then hintUI.note("💡 Hints are coming soon!")
		elseif res.reason == "closed" then hintUI.note("⏱ Too late for a hint on this one!") end
	end)
end)
answerBox.FocusLost:Connect(function(enter)
	sendDraft()
	if enter then tryLock() end
end)

RunService.RenderStepped:Connect(function()
	if not state.questionActive then return end
	local remaining = math.max(0, state.deadline - workspace:GetServerTimeNow())
	timerText.Text = tostring(math.ceil(remaining))
	timerFill.Size = UDim2.fromScale(remaining / state.duration, 1)
	local urgent = remaining <= 5
	timerText.TextColor3 = urgent and C.Danger or C.White
	timerFill.BackgroundColor3 = urgent and C.Danger or C.Gold
	if remaining < 0.6 and not state.finalSent then
		state.finalSent = true
		sendDraft()
	end
end)

---------------------------------------------------------------- reveal
local function describe(r)
	if r.kind == "correct" then
		local tier = UI.Rarity[r.tier]
		return Profanity.mask(r.answer), tier.label, tier.color
	elseif r.kind == "unrecognized" then
		return "Time’s up — no accepted answer", "TRY AGAIN NEXT QUESTION", C.Muted
	elseif r.kind == "withdrawn" then
		return "Left the show", "—", C.Muted
	end
	return "Time’s up — no answer", "NO POINTS THIS QUESTION", C.Muted
end

local function countUp(lbl, from, to, prefix, seconds)
	if Settings.reducedMotion or from == to then lbl.Text = prefix .. UI.formatNumber(to) return end
	local start = os.clock()
	while true do
		local a = math.min(1, (os.clock() - start) / seconds)
		lbl.Text = prefix .. UI.formatNumber(from + (to - from) * a)
		if a >= 1 then break end
		task.wait()
	end
end

local function playReveal(msg, token)
	state.questionActive = false
	setAnswerMode("hidden")
	hideCentre()
	for _, r in ipairs(msg.results) do
		if token ~= revealToken then return end
		local seat = UI.Seats[r.seat]
  react(r)
		local answer, tierText, tierColor = describe(r)
		revealBand.BackgroundColor3 = seat.color
		revealName.Text = seat.icon .. " " .. seat.label .. "  ·  " .. r.name
		revealAnswer.Text = answer
		revealAnswer.TextColor3 = r.kind == "correct" and C.White or C.Muted
		revealTier.Text = tierText
		revealTier.TextColor3 = tierColor
		revealPoints.Text = r.kind == "correct" and ("+" .. UI.formatNumber(r.points) .. " POINTS") or "+0"
		local before = r.newScore - r.points
		revealScore.Text = (msg.tiebreak and "Tiebreak: " or "Score: ") .. UI.formatNumber(before)
		revealStroke.Color = (r.tier == "rare" or r.tier == "extremely_rare") and tierColor or C.Gold
		revealStroke.Thickness = (r.tier == "extremely_rare") and 5 or 2
		reveal.Visible = true
		pop(reveal)
		cut("Podium" .. r.seat)
		if (r.tier == "very_rare" or r.tier == "extremely_rare") and r.emote and r.userId then
			local who = Players:GetPlayerByUserId(r.userId)
			if who and who.Character then
				task.delay(0.6, function() if token == revealToken then require(root.Shared.EmotePlayer).play(who.Character, r.emote) end end)
			end
		end
		if r.tier == "extremely_rare" then
			burst(r.seat, { C.Gold, Color3.new(1, 1, 1) }, 120)
		elseif r.tier == "rare" or r.tier == "very_rare" then
			burst(r.seat, { UI.Rarity.rare.color, Color3.new(1, 1, 1) }, 60)
		end
		task.wait(msg.perContestant * 0.35)
		if token ~= revealToken then return end
		countUp(revealScore, before, r.newScore, msg.tiebreak and "Tiebreak: " or "Score: ", 0.6)
		if not msg.tiebreak then setRowScore(r.seat, r.newScore) end
		task.wait(math.max(0, msg.perContestant * 0.65 - 0.6))
	end
	if token ~= revealToken then return end
	-- recap
	setHype(0.4)
	reveal.Visible = false
	for _, child in ipairs(recapCols:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	for _, r in ipairs(msg.results) do
		local seat = UI.Seats[r.seat]
		local answer, tierText, tierColor = describe(r)
		local col = make("Frame", { BackgroundColor3 = C.PanelDark, BackgroundTransparency = 0.15, Size = UDim2.new(1 / #msg.results - 0.025, 0, 1, 0), Parent = recapCols }, { corner(10), pad(6) })
		make("Frame", { BackgroundColor3 = seat.color, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 4) }).Parent = col
		label({ Text = seat.icon .. " " .. r.name, Position = UDim2.new(0, 0, 0.06, 0), Size = UDim2.new(1, 0, 0.2, 0), Parent = col }, 16)
		label({ Text = answer, Font = UI.FontBlack, TextColor3 = r.kind == "correct" and C.White or C.Muted, Position = UDim2.new(0, 0, 0.28, 0), Size = UDim2.new(1, 0, 0.28, 0), Parent = col }, 22)
		label({ Text = tierText, TextColor3 = tierColor, Position = UDim2.new(0, 0, 0.58, 0), Size = UDim2.new(1, 0, 0.16, 0), Parent = col }, 14)
		label({ Text = "+" .. UI.formatNumber(r.points), Font = UI.FontBlack, TextColor3 = C.Gold, Position = UDim2.new(0, 0, 0.76, 0), Size = UDim2.new(1, 0, 0.22, 0), Parent = col }, 20)
	end
	local notes = {}
	for _, h in ipairs(msg.highlights or {}) do
		table.insert(notes, Profanity.mask(h.name) .. " (" .. string.lower(UI.Rarity[h.tier].label) .. ")")
	end
	recapNote.Text = #notes > 0 and ("Also accepted: " .. table.concat(notes, ", ")) or ""
	recapTitle.Text = msg.tiebreak and "TIEBREAK RESULTS" or "RESULTS"
	recap.Visible = true
	pop(recap)
	cut("Question")
end

---------------------------------------------------------------- results
-- 1v1 / 1v1v1 victory celebration: the winner alone on stage beside a spinning trophy, confetti
-- raining down, and a picker so the winner can choose one of the dances they own (everyone sees it).
local celebration = { token = 0, hidden = {}, trophies = {} }
do
 local Catalog = require(root.Shared:WaitForChild("ShopCatalog"))
 local ui = make("Frame", { Name = "VictoryDance", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, BackgroundColor3 = C.PanelDark, BackgroundTransparency = 0.1, Visible = false, ZIndex = 12, Parent = gui }, { corner(18), stroke(C.Gold, 3), pad(10) })
 make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8), Parent = ui })
 label({ Text = "🏆 PICK YOUR VICTORY DANCE!", Font = UI.FontBlack, TextColor3 = C.Gold, Size = UDim2.fromOffset(540, 34), LayoutOrder = 0, ZIndex = 13, Parent = ui }, 26)
 local grid = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(540, 140), LayoutOrder = 1, ZIndex = 13, Parent = ui })
 make("UIGridLayout", { CellSize = UDim2.fromOffset(98, 64), CellPadding = UDim2.fromOffset(10, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
 -- only the dances this player has bought
 local function fillDances()
  for _, c in ipairs(grid:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
  local ok, s = pcall(function() return Remotes.ShopRequest:InvokeServer("inventory") end)
  local owned = (ok and type(s) == "table" and s.owned) or {}
  local n = 0
  for _, item in ipairs(Catalog.Emotes) do
   if owned[item.id] then
    n += 1
    local b = button({ LayoutOrder = n, Text = item.icon .. "\n" .. item.name, ZIndex = 14, Parent = grid }, "gold", 15)
    b.Activated:Connect(function() Remotes:WaitForChild("Celebrate"):FireServer(item.id) end)
   end
  end
  grid.Size = UDim2.fromOffset(540, n == 0 and 50 or (66 + (math.ceil(n / 5) - 1) * 72))
  if n == 0 then
   label({ Text = "No dances yet! Get some in the 🛍 SHOP", Font = UI.FontBody, Size = UDim2.fromOffset(520, 44), ZIndex = 14, Parent = grid }, 18)
  end
 end
 celebration.fillDances = fillDances
 local champ = label({ Name = "ChampionBanner", Text = "", Font = UI.FontBlack, TextColor3 = C.Gold, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64), Size = UDim2.new(0.8, 0, 0, 70), Visible = false, ZIndex = 12, Parent = gui }, 60)
 local function hideModel(m)
  for _, d in ipairs(m:GetDescendants()) do
   if d:IsA("BasePart") or d:IsA("Decal") then table.insert(celebration.hidden, { d, "LocalTransparencyModifier", d.LocalTransparencyModifier }); d.LocalTransparencyModifier = 1
   elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") or d:IsA("Light") or d:IsA("ParticleEmitter") then table.insert(celebration.hidden, { d, "Enabled", d.Enabled }); d.Enabled = false end
  end
 end
 local function trophy(at)
  local m = Instance.new("Model"); m.Name = "VictoryTrophy"
  local gold = Color3.fromRGB(255, 200, 40)
  local up = CFrame.Angles(0, 0, math.rad(90))
  local function P(size, cf, col, shape, mat)
   local p = Instance.new("Part"); p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
   p.Size = size; p.CFrame = cf; p.Color = col; p.Material = mat or Enum.Material.Metal; p.Reflectance = 0.2
   if shape then p.Shape = shape end
   p.Parent = m
   return p
  end
  P(Vector3.new(0.7, 2.6, 2.6), at * up, Color3.fromRGB(70, 30, 110), Enum.PartType.Cylinder, Enum.Material.SmoothPlastic)
  m.WorldPivot = at -- upright pivot, so it spins around its own vertical axis
  P(Vector3.new(0.3, 2.0, 2.0), at * CFrame.new(0, 0.5, 0) * up, gold, Enum.PartType.Cylinder)
  P(Vector3.new(1.6, 0.55, 0.55), at * CFrame.new(0, 1.4, 0) * up, gold, Enum.PartType.Cylinder)
  local cup = P(Vector3.new(2.4, 2.4, 2.4), at * CFrame.new(0, 3.0, 0), gold, Enum.PartType.Ball)
  P(Vector3.new(0.3, 2.6, 2.6), at * CFrame.new(0, 3.8, 0) * up, gold, Enum.PartType.Cylinder)
  for _, s in ipairs({ -1, 1 }) do
   P(Vector3.new(0.35, 0.35, 0.35), at * CFrame.new(s * 1.55, 3.5, 0), gold, Enum.PartType.Ball)
   P(Vector3.new(0.3, 1.1, 0.3), at * CFrame.new(s * 1.6, 3.0, 0), gold)
   P(Vector3.new(0.35, 0.35, 0.35), at * CFrame.new(s * 1.45, 2.45, 0), gold, Enum.PartType.Ball)
  end
  P(Vector3.new(0.9, 0.9, 0.2), at * CFrame.new(0, 3.0, -1.15) * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(255, 80, 190), nil, Enum.Material.Neon)
  local light = Instance.new("PointLight"); light.Color = gold; light.Range = 16; light.Brightness = 2.5; light.Parent = cup
  local sp = Instance.new("ParticleEmitter"); sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"; sp.Rate = 14
  sp.Lifetime = NumberRange.new(0.5, 1); sp.Speed = NumberRange.new(1, 3); sp.SpreadAngle = Vector2.new(180, 180)
  sp.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.6), NumberSequenceKeypoint.new(1, 0) })
  sp.LightEmission = 1; sp.Color = ColorSequence.new(Color3.fromRGB(255, 240, 160)); sp.Parent = cup
  m.Parent = workspace
  return m
 end
 function celebration.stop()
  celebration.token += 1
  ui.Visible = false; champ.Visible = false
  for _, h in ipairs(celebration.hidden) do
   local obj, prop, value = h[1], h[2], h[3]
   pcall(function() obj[prop] = value end)
  end
  table.clear(celebration.hidden)
  for _, t in ipairs(celebration.trophies) do t:Destroy() end
  table.clear(celebration.trophies)
 end
 -- returns how many seconds the celebration lasts (0 = no celebration)
 function celebration.start(msg)
  celebration.stop()
  local seconds = msg.celebrate or 0
  if seconds <= 0 or not studio or #(msg.winners or {}) == 0 then return 0 end
  local token = celebration.token
  local winners, names, iWon = {}, {}, false
  for _, s in ipairs(msg.winners) do winners[s] = true; if s == state.seat then iWon = true end end
  -- just the winner on stage: hide everyone else's podium and character (on this screen only)
  for _, p in ipairs(msg.placements) do
   if winners[p.seat] then table.insert(names, string.upper(p.name))
   else
    local pod = studio.Podiums:FindFirstChild("Podium" .. p.seat)
    if pod then hideModel(pod) end
    local who = p.userId and Players:GetPlayerByUserId(p.userId)
    if who and who.Character then hideModel(who.Character) end
    local bot = not p.userId and studio:FindFirstChild(p.name)
    if bot then hideModel(bot) end
   end
  end
  -- a glowing trophy floating beside each winner
  for s in pairs(winners) do
   local pod = studio.Podiums:FindFirstChild("Podium" .. s)
   if pod then
    local stand = pod.StandPoint.Position
    local toAudience = pod.Body.CFrame.LookVector
    local right = toAudience:Cross(Vector3.yAxis).Unit
    local base = stand + right * 3.9 + toAudience * 1.2 - Vector3.new(0, 1.0, 0)
    local t = trophy(CFrame.lookAt(base, base + toAudience * 10))
    t:ScaleTo(1.35)
    table.insert(celebration.trophies, t)
    local home = t:GetPivot()
    task.spawn(function()
     local t0 = os.clock()
     while token == celebration.token and t.Parent do
      local k = os.clock() - t0
      -- hovering: bobbing gently, drifting side to side and rocking back and forth (no spinning)
      t:PivotTo(home * CFrame.new(math.sin(k * 1.3) * 0.45, math.sin(k * 2.1) * 0.35, 0) * CFrame.Angles(math.sin(k * 1.7) * math.rad(7), 0, math.sin(k * 1.3 + 0.6) * math.rad(-9)))
      RunService.RenderStepped:Wait()
     end
    end)
   end
  end
  champ.Text = "🏆 CHAMPION" .. (#names > 1 and "S" or "") .. "! " .. table.concat(names, " & ")
  champ.Visible = true; pop(champ)
  ui.Visible = iWon
  if iWon then task.spawn(celebration.fillDances) end
  cut("Champion" .. msg.winners[1])
  -- confetti raining down the whole time
  task.spawn(function()
   while token == celebration.token do
    for s in pairs(winners) do burst(s, { C.Gold, Color3.fromRGB(255, 110, 190), Color3.fromRGB(90, 220, 255) }, 120) end
    if celebration.confetti then celebration.confetti(90) end
    task.wait(1.4)
   end
  end)
  task.delay(seconds, function() if token == celebration.token then celebration.stop() end end)
  return seconds
 end
end

local function showResults(msg)
	state.questionActive = false
	hideCentre()
	setAnswerMode("hidden")
	for _, child in ipairs(resultsList:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	local winnerNames, iWon = {}, false
	for _, seat in ipairs(msg.winners) do
		for _, p in ipairs(msg.placements) do
			if p.seat == seat then table.insert(winnerNames, p.name) end
		end
		if seat == state.seat then iWon = true end
	end
	resultsTitle.Text = msg.shared and "🏆 SHARED VICTORY" or (msg.tiebreakUsed and "🏆 WINNER · WON THE TIEBREAKER" or "🏆 WINNER")
	resultsWinner.Text = table.concat(winnerNames, " & ")
	local ordinal = { "1st", "2nd", "3rd" }
	for i, p in ipairs(msg.placements) do
		local seat = UI.Seats[p.seat]
		local row = make("Frame", { BackgroundColor3 = C.PanelDark, BackgroundTransparency = 0.15, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = i, ZIndex = 11, Parent = resultsList }, { corner(10) })
		make("Frame", { BackgroundColor3 = seat.color, BorderSizePixel = 0, Size = UDim2.new(0, 6, 1, 0), ZIndex = 11 }).Parent = row
		label({ Text = msg.mode=="Solo" and "★" or p.withdrawn and "—" or ordinal[p.place] or tostring(p.place), Font = UI.FontBlack, TextColor3 = C.Gold, Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(0.15, 0, 1, 0), ZIndex = 11, Parent = row }, 22)
		label({ Text = seat.icon .. " " .. p.name .. (p.withdrawn and " (left)" or ""), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0.2, 0, 0, 0), Size = UDim2.new(0.5, 0, 1, 0), ZIndex = 11, Parent = row }, 20)
		label({ Text = UI.formatNumber(p.score), Font = UI.FontBlack, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(0.7, 0, 0, 0), Size = UDim2.new(0.3, -12, 1, 0), ZIndex = 11, Parent = row }, 22)
	end
	local function reveal()
		results.Visible = true
		pop(results)
		if #msg.winners == 1 then cut("Podium" .. msg.winners[1]) else cut("Wide") end
	end
	local party = celebration.start(msg)
	if party > 0 then
		results.Visible = false
		task.delay(party, function() if state.inMatch then reveal() end end)
	else
		reveal()
	end
	for _, seat in ipairs(msg.winners) do
		burst(seat, { C.Gold, Color3.fromRGB(255, 120, 160) }, 150)
	end
	for _, e in ipairs(msg.emotes or {}) do
		local who = Players:GetPlayerByUserId(e.userId)
		if who and who.Character then
			task.delay(1, function() if state.inMatch and who.Character then require(root.Shared.EmotePlayer).play(who.Character, e.emote) end end)
		end
	end
	if msg.mode=="Solo" then resultsTitle.Text="SOLO COMPLETE";resultsWinner.Text="Your 15-question score";iWon=false end
	if iWon then resultsTitle.Text = resultsTitle.Text .. " — YOU!" end
end

-- Both results buttons take you back to the lobby right away (no waiting for the show to wrap).
local function goToLobby()
	results.Visible = false
	if state.inMatch then
		showBanner("BACK TO THE LOBBY!","See you on the pads!")
		Remotes.LeaveMatch:FireServer()
	else
		showLobby(true)
	end
end
againBtn.Activated:Connect(function() state.replay=true; goToLobby() end)
lobbyBtn.Activated:Connect(function() state.replay=false; goToLobby() end)

-- Leave button (any time during a show), with a friendly "are you sure?"
local leaveBtn = button({ Name = "LeaveButton", Text = "🚪 LEAVE", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 66, 1, -12), Size = UDim2.new(0, 108, 0, 46), Parent = hud }, "pink", 20)

-- Keep the answer box and reveal card clear of the corner buttons/standings: centred between
-- them on wide screens, lifted just above them on narrow (phone) screens.
layoutHud = function()
	local vw = workspace.CurrentCamera.ViewportSize.X
	local side = math.max(12 + 46 + 8 + 108 + 16, standingsFrame.AbsoluteSize.X + 28)
	local middle = vw - side * 2
	local lift = standingsFrame.AbsoluteSize.Y + 24
	local answerMax = answerArea:FindFirstChildOfClass("UISizeConstraint")
	local revealMax = reveal:FindFirstChildOfClass("UISizeConstraint")
	if middle >= 440 then
		answerArea.Position = UDim2.new(0.5, 0, 1, -18)
		answerArea.Size = UDim2.new(0, math.min(680, middle), 0, 96)
		reveal.Position = UDim2.new(0.5, 0, 1, -16)
		reveal.Size = UDim2.new(0, math.min(760, middle), 0.32, 0)
	else
		answerArea.Position = UDim2.new(0.5, 0, 1, -lift)
		answerArea.Size = UDim2.new(0.94, 0, 0, 96)
		reveal.Position = UDim2.new(0.5, 0, 1, -lift)
		reveal.Size = UDim2.new(0.94, 0, 0.3, 0)
	end
	if answerMax then answerMax.MaxSize = Vector2.new(680, math.huge) end
	if revealMax then revealMax.MaxSize = Vector2.new(760, 240) end
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutHud)
standingsFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutHud)
layoutHud()
local leaveModal, leaveBody = modal("LeaveShow", "Leave the show?", 230)
label({ Text = "You'll go back to the lobby. Your score for this show won't count.", Font = UI.FontBody, Size = UDim2.new(1, 0, 0, 56), ZIndex = 23, Parent = leaveBody }, 20)
local leaveYes = button({ Text = "YES, LEAVE", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(0.48, 0, 0, 54), ZIndex = 23, Parent = leaveBody }, "pink", 22)
local leaveNo = button({ Text = "KEEP PLAYING!", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.new(0.48, 0, 0, 54), ZIndex = 23, Parent = leaveBody }, "green", 22)
leaveBtn.Activated:Connect(function() if state.inMatch then leaveModal.Visible = true end end)
leaveNo.Activated:Connect(function() leaveModal.Visible = false end)
leaveYes.Activated:Connect(function()
	leaveModal.Visible = false
	if state.inMatch then
		state.replay = false
		showBanner("BACK TO THE LOBBY!", "See you on the pads!")
		Remotes.LeaveMatch:FireServer()
	end
end)

---------------------------------------------------------------- lobby queue
local queued=false
cancelQueue.Activated:Connect(function() Remotes.QueueRequest:FireServer(false) end)

---------------------------------------------------------------- server messages
local handlers = {}

handlers.Queue = function(msg)
 queued=msg.inQueue
 cancelQueue.Visible=queued

 local m=msg.mode and UI.Modes[msg.mode]
 if msg.idle and not state.inMatch then
  queueLabel.Text="💤 You went AFK, so you're out of line. Move to hop back in!"
  queueLabel.TextColor3=C.Gold
  tipLabel.Visible=false
  return
 end
 if queued and m then
  if msg.needed<=1 then queueLabel.Text=("%s %s pad #%d — starting your show!"):format(m.icon,m.label,msg.pad or 1)
  else queueLabel.Text=("%s %s pad #%d — %d / %d ready! Waiting for %d more…"):format(m.icon,m.label,msg.pad or 1,msg.count,msg.needed,msg.needed-msg.count) end
  queueLabel.TextColor3=m.color
 elseif not state.inMatch then queueLabel.Text="Hop on a numbered pad to play!";queueLabel.TextColor3=C.White end
 tipLabel.Visible=not queued
end
handlers.QueueError=function(msg) queueLabel.Text=msg.text end
handlers.MatchLoading=function(msg)
 lobbyLighting(false)
 state.inMatch=true
 state.mode=nil
 showLobby(false);hud.Visible=true;setAnswerMode("hidden")
 showBanner("ENTERING THE STUDIO","Preparing your arena…")
 local arena=workspace:WaitForChild(msg.arena,15)
 if not arena then return end
 studio=arena;shots=studio:WaitForChild("CameraShots")
 -- arenas are cosmetic and client-side: dress this stage in MY equipped arena (others see theirs)
 local themeId=player:GetAttribute("ArenaTheme")
 if themeId then pcall(function() require(root.Shared.ArenaThemes).apply(arena,themeId) end) end
 setHype(0.5)
 collectFx(arena)
 -- the host's big showbiz smile (face expressions are set on each client; they don't replicate)
 task.spawn(function()
  local host=arena:WaitForChild("Host",15)
  local head=host and host:WaitForChild("Head",5)
  local fc=head and head:WaitForChild("FaceControls",5)
  if not fc then return end
  for k,v in pairs({LeftLipCornerPuller=1,RightLipCornerPuller=1,LeftCheekRaiser=0.5,RightCheekRaiser=0.5,JawDrop=0.15,LowerLipDepressor=0.25,LeftUpperLipRaiser=0.3,RightUpperLipRaiser=0.3,LeftInnerBrowRaiser=0.3,RightInnerBrowRaiser=0.3}) do pcall(function() fc[k]=v end) end
 end)
 jumbo("CLAMILLION!","GET READY!")
 buildCrowd(arena)
 Remotes.IntroReady:FireServer(msg.matchId,"loaded")
end

local introToken=0
local skipIntro=button({Name="SkipIntroButton",Text="SKIP CAMERA",AnchorPoint=Vector2.new(0.5,1),Position=UDim2.new(0.5,0,1,-20),Size=UDim2.fromOffset(155,42),Visible=false,Parent=gui},"dark",18)
local skipped=false
-- skip the rules intro and jump straight to the questions
local function skipIntroNow()
 introToken+=1
 skipped=true;skipIntro.Visible=false
 hushHost()
 TweenService:Create(music,TweenInfo.new(.4),{Volume=0}):Play()
 TweenService:Create(cheers,TweenInfo.new(.4),{Volume=0}):Play()
 cut("Question");workspace.CurrentCamera.FieldOfView=70
 showBanner("LET'S GO!","Skipping straight to the questions…")
end
skipIntro.Activated:Connect(function()
 if not state.matchId then return end
 if state.mode=="Solo" then
  -- Solo: instant
  skipIntroNow()
  Remotes.IntroReady:FireServer(state.matchId,"skip")
  return
 end
 -- 1v1 / 1v1v1: a vote — the intro is skipped once every contestant has tapped it
 if skipIntro:GetAttribute("Voted") then return end
 skipIntro:SetAttribute("Voted",true)
 skipIntro.Text="SKIP ✓ WAITING…"
 Remotes.IntroReady:FireServer(state.matchId,"skip")
end)
handlers.SkipVotes=function(msg)
 if skipped or not skipIntro.Visible then return end
 skipIntro.Text=(skipIntro:GetAttribute("Voted") and "SKIP ✓ " or "SKIP INTRO ")..("(%d/%d)"):format(msg.votes,msg.needed)
end
handlers.IntroSkipped=function() if not skipped then skipIntroNow() end end
do -- crowd, arena effects and show handlers (own scope)
---------------------------------------------------------------- the crowd
-- Each contestant's client builds the audience in its own arena (CrowdBuilder) and animates
-- it locally: fans stand, jump, wave, clap, whistle and wave their signs, and the room noise
-- follows how excited they are ("hype").
local CrowdBuilder = require(root.Shared:WaitForChild("CrowdBuilder"))
local BONES = { Body = 1, ArmL = 2, ArmR = 3, LegL = 4, LegR = 5 }
local crowd = { fans = {}, parts = {}, rels = {}, owner = {}, bone = {}, cframes = {}, arena = nil, token = 0 }
local hype = { base = 0.4, peak = 0, untilT = 0 }
setHype = function(level, seconds)
 if seconds then hype.peak = level; hype.untilT = os.clock() + seconds else hype.base = level end
end
local function hypeNow() return os.clock() < hype.untilT and math.max(hype.peak, hype.base) or hype.base end

local crowdNoise = make("Sound", { Name = "CrowdNoise", SoundId = "rbxassetid://9119562311", Looped = true, Volume = 0, Parent = SoundService })
local whistle = make("Sound", { Name = "CrowdWhistle", SoundId = "rbxassetid://9125997043", Volume = 0.35, Parent = SoundService })
task.spawn(function() pcall(function() ContentProvider:PreloadAsync({ crowdNoise, whistle }) end) end)
local lastWhistle = 0
local function playWhistle()
 if not Settings.audio or os.clock() - lastWhistle < 0.8 then return end
 lastWhistle = os.clock()
 whistle.PlaybackSpeed = 0.9 + math.random() * 0.25
 whistle.Volume = 0.18 + hypeNow() * 0.25
 whistle.TimePosition = 0; whistle:Play()
end
local function cheerBurst(volume) crowdCheer(volume or 0.8, 4.5) end -- the same crowd cheer, used for the winner

local function resetCrowd()
 crowd.token += 1
 crowd.fans, crowd.parts, crowd.rels, crowd.owner, crowd.bone, crowd.cframes = {}, {}, {}, {}, {}, {}
 crowd.arena = nil
 crowdNoise:Stop()
end

local function rigFan(model)
 local base = model:GetAttribute("Base")
 if typeof(base) ~= "CFrame" then return end
 local J = CrowdBuilder.Joints
 local rest = {
  base,
  base * CFrame.new(J.ArmL),
  base * CFrame.new(J.ArmR) * CFrame.Angles(model:GetAttribute("ArmRRest") or 0, 0, 0),
  base * CFrame.new(J.LegL) * CFrame.Angles(CrowdBuilder.SEATED_LEG, 0, 0),
  base * CFrame.new(J.LegR) * CFrame.Angles(CrowdBuilder.SEATED_LEG, 0, 0),
 }
 local rng = Random.new(model:GetAttribute("Seed") or 1)
 local fan = {
  base = base, joints = { base, base, base, base, base },
  phase = rng:NextNumber() * 10, energy = 0.65 + rng:NextNumber() * 0.6,
  prop = model:GetAttribute("Prop") or "none", whistler = model:GetAttribute("Whistler") == true,
  action = "sit", nextPick = 0, stand = 0, mouthOpen = false,
  speed = 0.85 + rng:NextNumber() * 0.4,
 }
 local index = #crowd.fans + 1
 for _, p in ipairs(model:GetChildren()) do
  if p:IsA("BasePart") then
   local b = BONES[p:GetAttribute("Bone")] or 1
   table.insert(crowd.parts, p)
   table.insert(crowd.rels, rest[b]:ToObjectSpace(p.CFrame))
   table.insert(crowd.owner, index)
   table.insert(crowd.bone, b)
   if p.Name == "MouthOpen" then fan.open = p elseif p.Name == "MouthSmile" then fan.smile = p end
  end
 end
 crowd.fans[index] = fan
end

buildCrowd = function(arena)
 resetCrowd()
 local token = crowd.token
 crowd.arena = arena
 task.spawn(function()
  local ok, err = pcall(function() CrowdBuilder.build(arena, 20) end)
  if not ok then warn("[Clamillion] crowd build failed: " .. tostring(err)) return end
  if token ~= crowd.token or not arena.Parent then return end
  for _, model in ipairs(arena.Crowd:GetChildren()) do rigFan(model) end
  if Settings.audio then crowdNoise.Volume = 0; crowdNoise:Play() end
 end)
end
local function prepareCrowd() setHype(1, 26) end

local TIER_HYPE = { common = 0.5, too_clever = 0.55, uncommon = 0.62, rare = 0.8, very_rare = 0.92, extremely_rare = 1 }
local TIER_SHOUT = { common = "NICE!", uncommon = "OOOH!", rare = "RARE!!", very_rare = "SUPER RARE!!", extremely_rare = "LEGENDARY!!!" }

-- pick what a fan is doing for the next couple of seconds, based on how hyped the room is
local function pickAction(fan, level, t)
 local r = math.random()
 local e = level * fan.energy
 local action
 if e < 0.22 then action = r < 0.8 and "sit" or "clap"
 elseif e < 0.5 then action = r < 0.35 and "clap" or (r < 0.6 and "wave" or (r < 0.75 and "cheer" or "sit"))
 else
  if r < 0.38 then action = "jump" elseif r < 0.58 then action = "wave" elseif r < 0.76 then action = "clap" elseif r < 0.9 and fan.whistler then action = "whistle" else action = "cheer" end
 end
 if fan.prop == "sign" or fan.prop == "finger" or fan.prop == "glow" then
  if action == "clap" then action = e > 0.5 and "jump" or "wave" end
 end
 if action == "whistle" and not state.inIntro then playWhistle() end
 fan.action = action
 fan.nextPick = t + (1.6 + math.random() * 2.4) / math.max(0.6, fan.speed)
end

local SEATED = CrowdBuilder.SEATED_LEG
local crowdClock = 0
RunService.RenderStepped:Connect(function(dt)
 if not state.inMatch or #crowd.fans == 0 then return end
 local level = hypeNow()
 -- room noise follows the hype
 if Settings.audio and crowdNoise.IsPlaying then
  -- quieter while the host is explaining the rules, so you can hear him
  local target = state.inIntro and (0.02 + level * 0.12) or (0.04 + level * 0.36)
  crowdNoise.Volume += (target - crowdNoise.Volume) * math.min(1, dt * 3)
 end
 crowdClock += dt
 if crowdClock < 1 / 30 then return end
 local step = crowdClock; crowdClock = 0
 local t = os.clock()
 local still = Settings.reducedMotion
 for _, fan in ipairs(crowd.fans) do
  if t >= fan.nextPick then pickAction(fan, level, t) end
  local a, ph, sp = fan.action, fan.phase, fan.speed
  local standing = (a == "jump" or a == "whistle" or (a == "cheer" and level > 0.45) or (a == "wave" and level > 0.7)) and not still
  fan.stand += ((standing and 1 or 0) - fan.stand) * math.min(1, step * 6)
  local s = fan.stand
  local lift = s * 1.45
  local sway = math.sin(t * 1.6 * sp + ph) * 0.05
  local lean = -0.05
  local lx, lz, rx, rz = 0.25, -0.08, 0.25, 0.08 -- arms resting
  if not still then
   if a == "jump" then
    lift += math.abs(math.sin(t * 5.2 * sp + ph)) * 1.5
    local w = math.sin(t * 9 * sp + ph) * 0.35
    lx, lz, rx, rz = 2.85, -0.45 - w, 2.85, 0.45 + w
   elseif a == "wave" then
    rx, rz = 2.7, 0.35 + math.sin(t * 9 * sp + ph) * 0.45
    sway += math.sin(t * 4.5 * sp + ph) * 0.06
   elseif a == "clap" then
    local c = math.abs(math.sin(t * 7.5 * sp + ph))
    lx, rx = 1.25, 1.25
    lz, rz = 0.18 + c * 0.32, -0.18 - c * 0.32
    lean = -0.12
   elseif a == "whistle" then
    rx, rz = 2.35, -0.62 -- fingers to the mouth
    lx, lz = 2.8, -0.5 - math.sin(t * 8 + ph) * 0.4
    lift += math.abs(math.sin(t * 3 + ph)) * 0.4
   elseif a == "cheer" then
    local pump = math.sin(t * 6 * sp + ph)
    rx, rz = 2.4 + pump * 0.45, 0.2
    lx, lz = 1.0 + pump * 0.3, -0.3
    lift += math.max(0, pump) * 0.3
   else -- sit
    sway += math.sin(t * 0.9 + ph) * 0.03
   end
   -- prop holders always keep the prop up, pumping it when excited
   if fan.prop == "sign" or fan.prop == "finger" or fan.prop == "glow" then
    if a ~= "whistle" then rx = 2.75 + math.sin(t * (3 + level * 5) + ph) * (0.1 + level * 0.25); rz = 0.15 + math.sin(t * 2.3 + ph) * 0.2 end
   end
  end
  local body = fan.base * CFrame.new(0, lift, 0) * CFrame.Angles(lean, 0, sway)
  local J = CrowdBuilder.Joints
  local leg = SEATED * (1 - s) + 0.05
  fan.joints[1] = body
  fan.joints[2] = body * CFrame.new(J.ArmL) * CFrame.Angles(lx, 0, lz)
  fan.joints[3] = body * CFrame.new(J.ArmR) * CFrame.Angles(rx, 0, rz)
  fan.joints[4] = body * CFrame.new(J.LegL) * CFrame.Angles(leg, 0, 0)
  fan.joints[5] = body * CFrame.new(J.LegR) * CFrame.Angles(leg, 0, 0)
  local open = not still and (a == "jump" or a == "whistle" or a == "cheer" or (a == "wave" and level > 0.5))
  if open ~= fan.mouthOpen and fan.open and fan.smile then
   fan.mouthOpen = open
   fan.open.Transparency = open and 0 or 1
   fan.smile.Transparency = open and 1 or 0
  end
 end
 local parts, rels, owner, bone, cfs, fans = crowd.parts, crowd.rels, crowd.owner, crowd.bone, crowd.cframes, crowd.fans
 for i = 1, #parts do cfs[i] = fans[owner[i]].joints[bone[i]] * rels[i] end
 workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end)

---------------------------------------------------------------- arena show effects
local RAINBOW = { Color3.fromRGB(255,72,92), Color3.fromRGB(255,146,40), Color3.fromRGB(255,214,40), Color3.fromRGB(84,214,90), Color3.fromRGB(40,200,210), Color3.fromRGB(60,128,255), Color3.fromRGB(150,86,255), Color3.fromRGB(255,96,200) }
local fx = { chase = {}, sweeps = {}, pyro = {}, confetti = {}, jumbos = {}, swimmers = {}, origin = CFrame.identity }
-- Halloween arena: chase lights run orange / purple / slime green instead of the rainbow
local SPOOKY = { Color3.fromRGB(255, 120, 20), Color3.fromRGB(150, 60, 255), Color3.fromRGB(110, 255, 90), Color3.fromRGB(255, 170, 40), Color3.fromRGB(110, 40, 190) }

-- Underwater arena: blue-green tint while you're in it
local underwater
local ambience
local function setAmbience(themeId)
 if ambience then ambience:Destroy(); ambience = nil end
 local look = themeId and require(root.Shared.ArenaThemes).Ambience[themeId]
 if not look then return end
 ambience = make("ColorCorrectionEffect", { Name = "ClamillionAmbience", TintColor = look.tint, Saturation = look.saturation, Contrast = look.contrast, Parent = Lighting })
 Lighting.Ambient = look.ambient
 Lighting.OutdoorAmbient = look.outdoor
 Lighting.ExposureCompensation = look.exposure or 0
end
local function setUnderwater(on)
 if not on then setAmbience(nil) end
 if on and not underwater then
  underwater = {
   make("ColorCorrectionEffect", { Name = "ClamillionUnderwater", TintColor = Color3.fromRGB(190, 235, 255), Saturation = 0.15, Contrast = 0.05, Parent = Lighting }),
   make("BlurEffect", { Name = "ClamillionUnderwaterHaze", Size = 2, Parent = Lighting }),
  }
  Lighting.Ambient = Color3.fromRGB(70, 130, 170)
  Lighting.OutdoorAmbient = Color3.fromRGB(60, 120, 170)
 elseif not on and underwater then
  for _, e in ipairs(underwater) do e:Destroy() end
  underwater = nil
 end
end

collectFx = function(arena)
 fx.chase, fx.sweeps, fx.pyro, fx.confetti, fx.jumbos, fx.swimmers = {}, {}, {}, {}, {}, {}
 fx.origin = arena:GetPivot()
 fx.spooky = arena:GetAttribute("Theme") == "Halloween"
 setUnderwater(arena:GetAttribute("Theme") == "Aquarium")
 setAmbience(arena:GetAttribute("Theme"))
 for _, m in ipairs(arena:GetDescendants()) do
  if m:IsA("Model") and m:GetAttribute("Swim") and m.PrimaryPart then
   local head = m.PrimaryPart
   table.insert(fx.swimmers, { model = m, kind = m:GetAttribute("Swim"), home = m:GetPivot(),
    radius = m:GetAttribute("Radius") or 20, speed = m:GetAttribute("Speed") or 0.2, phase = m:GetAttribute("Phase") or 0,
    range = m:GetAttribute("Range") or 20, amp = m:GetAttribute("Amp") or 2,
    spin = m:GetAttribute("SpinSpeed"), swing = math.rad(m:GetAttribute("SwingDeg") or 12),
    dir = m:GetAttribute("Dir"), dist = m:GetAttribute("Dist") or 80, dur = m:GetAttribute("Dur") or 1.2, gap = m:GetAttribute("Gap") or 4,
    head = head, trail = head and head:FindFirstChildOfClass("Trail") })
  end
 end
 for _, d in ipairs(arena:GetDescendants()) do
  if d:IsA("BasePart") then
   if d:GetAttribute("Chase") then table.insert(fx.chase, { part = d, i = d:GetAttribute("Chase"), group = d:GetAttribute("ChaseGroup") }) end
   if d:GetAttribute("Sweep") then table.insert(fx.sweeps, { part = d, i = d:GetAttribute("Sweep"), home = d.Position }) end
   if d.Name == "PyroJet" then table.insert(fx.pyro, d) end
   if d.Name == "ConfettiCannon" then table.insert(fx.confetti, d) end
   if d.Name == "Jumbotron" then table.insert(fx.jumbos, d) end
  end
 end
end
jumbo = function(headline, sub)
 for _, j in ipairs(fx.jumbos) do
  local bg = j:FindFirstChild("Screen") and j.Screen:FindFirstChild("BG")
  if bg then bg.Headline.Text = headline or ""; bg.Sub.Text = sub or "" end
 end
end
local function pyro(power)
 if not Settings.effects then return end
 for i, jet in ipairs(fx.pyro) do
  task.delay((i - 1) * 0.06, function()
   local nozzle = jet:FindFirstChild("Nozzle")
   if not nozzle then return end
   nozzle.Flame:Emit(math.floor(30 * (power or 1)))
   nozzle.Sparks:Emit(math.floor(40 * (power or 1)))
   local glow = jet:FindFirstChild("Glow")
   if glow then glow.Brightness = 6; TweenService:Create(glow, TweenInfo.new(0.8), { Brightness = 0 }):Play() end
  end)
 end
end
local confetti
confetti = function(amount)
 if not Settings.effects then return end
 for _, c in ipairs(fx.confetti) do
  local att = c:FindFirstChildOfClass("Attachment")
  if att then
   for _, pe in ipairs(att:GetChildren()) do if pe:IsA("ParticleEmitter") then pe:Emit(amount or 120) end end
  end
 end
end
celebration.confetti = confetti
onReaction = function(r)
 if r.kind ~= "correct" then
  setHype(0.3, 2.2); jumbo("AWWW!", "NEXT ONE!")
  return
 end
 setHype(TIER_HYPE[r.tier] or 0.5, 2.6)
 jumbo(TIER_SHOUT[r.tier] or "NICE!", (r.answer and string.upper(Profanity.mask(r.answer)) or ""))
 if r.tier == "extremely_rare" then pyro(1.4); confetti(160)
 elseif r.tier == "very_rare" then pyro(1); confetti(60)
 elseif r.tier == "rare" then pyro(0.7) end
end
local fxClock = 0
RunService.RenderStepped:Connect(function(dt)
 if not state.inMatch or #fx.chase == 0 then return end
 fxClock += dt
 if fxClock < 1 / 15 then return end
 fxClock = 0
 local t = os.clock()
 local level = hypeNow()
 local moving = Settings.effects and not Settings.reducedMotion
 local speed = moving and (2 + level * 7) or 0
 local step = math.floor(t * speed)
 for _, c in ipairs(fx.chase) do
  local g = c.group
  if g == "Crown" or g == "Aisles" then
   c.part.Color = fx.spooky and SPOOKY[((c.i + step) % #SPOOKY) + 1] or RAINBOW[((c.i + step) % #RAINBOW) + 1]
  else
   local on = ((c.i + step) % 3) ~= 0
   if fx.spooky then c.part.Color = on and Color3.fromRGB(255, 140, 30) or Color3.fromRGB(150, 60, 255)
   else c.part.Color = on and Color3.fromRGB(255, 236, 160) or Color3.fromRGB(255, 80, 180) end
  end
 end
 for _, s in ipairs(fx.sweeps) do
  local k = s.i
  local w = t * (0.25 + level * 0.5) + k * 1.3
  local x = (moving and math.sin(w) or 0) * 70
  local z = 10 + (moving and math.cos(w * 0.8 + k) or 0) * 45
  s.part.Position = fx.origin.Position + Vector3.new(x, 66, z)
 end
 for _, j in ipairs(fx.jumbos) do
  local g = j:FindFirstChild("Screen") and j.Screen.BG:FindFirstChild("Gradient")
  if g and moving then g.Rotation = (t * 25) % 360 end
 end
end)

-- sea creatures in the aquarium arena: circle (whale, turtle, fish schools), line (tank fish), bob (jellyfish)
local swimClock = 0
RunService.RenderStepped:Connect(function(dt)
 if not state.inMatch or #fx.swimmers == 0 or Settings.reducedMotion then return end
 swimClock += dt
 local full = swimClock >= 1 / 30
 if full then swimClock = 0 end
 local t = workspace:GetServerTimeNow()
 for _, s in ipairs(fx.swimmers) do
  if s.model.Parent and (full or s.kind == "shoot") then
   local c = s.home.Position
   local cf
   if s.kind == "circle" then
    local a = t * s.speed + s.phase
    local pos = c + Vector3.new(math.cos(a) * s.radius, math.sin(a * 2.3) * 1.5, math.sin(a) * s.radius)
    local dir = Vector3.new(-math.sin(a), 0, math.cos(a)) * (s.speed >= 0 and 1 or -1)
    cf = CFrame.lookAt(pos, pos + dir)
   elseif s.kind == "line" then
    local a = t * s.speed + s.phase
    local pos = c + Vector3.new(0, math.sin(a * 1.7) * 1.2, math.sin(a) * s.range)
    local dir = Vector3.new(0, 0, math.cos(a) >= 0 and 1 or -1)
    cf = CFrame.lookAt(pos, pos + dir)
   elseif s.kind == "swing" then
    cf = s.home * CFrame.Angles(0, 0, math.sin(t * s.speed + s.phase) * s.swing)
   elseif s.kind == "shoot" then
    -- a dash across the sky, then a pause; each pass starts somewhere a little different
    local cycle = s.dur + s.gap
    local k = (t + s.phase) % cycle
    if k <= s.dur and s.dir then
     local pass = math.floor((t + s.phase) / cycle)
     local fresh = s.pass ~= pass
     if fresh then
      s.pass = pass
      s.offset = Vector3.new((pass * 37) % 40 - 20, (pass * 13) % 8 - 4, (pass * 23) % 30 - 15)
      if s.trail then s.trail.Enabled = false end
     elseif s.trail then s.trail.Enabled = Settings.effects end
     if s.head then s.head.Transparency = 0 end
     local pos = c + s.offset + s.dir * s.dist * (k / s.dur)
     cf = CFrame.lookAt(pos, pos + s.dir)
    else
     if s.trail then s.trail.Enabled = false end
     if s.head then s.head.Transparency = 1 end
    end
   else -- bob
    cf = s.home + Vector3.new(0, math.sin(t * s.speed + s.phase) * s.amp, 0)
   end
   if cf and s.spin then cf = cf * CFrame.Angles(0, (t * s.spin) % (math.pi * 2), 0) end
   if cf then s.model:PivotTo(cf) end
  end
 end
end)
local function cinematic(msg)
 introToken+=1;local token=introToken
 skipped=false;skipIntro.Visible=true
 skipIntro:SetAttribute("Voted",nil)
 skipIntro.Text=msg.mode=="Solo" and "SKIP INTRO ⏩" or ("SKIP INTRO (0/"..#msg.contestants..")")
 skipIntro.Size=UDim2.fromOffset(msg.mode=="Solo" and 190 or 220,56)
 hideCentre();prepareCrowd()
 camera=workspace.CurrentCamera
 if camTween then camTween:Cancel() end
 camera.CameraType=Enum.CameraType.Scriptable
 currentShot="IntroCameraStart"
 local start=shots.IntroCameraStart.CFrame
 local finish=shots.HostIntroCamera.CFrame
 camera.CFrame=start;camera.FieldOfView=75
 if Settings.audio then music.TimePosition=0;cheers.TimePosition=0;music.Volume=.42;cheers.Volume=.55;music:Play();cheers:Play() end
 jumbo("WELCOME!","MAKE SOME NOISE!")
 task.delay(.4,function() if token==introToken then pyro(1.2);confetti(140) end end)
 cheers.Looped=true -- keep the cheer going (no abrupt end) until it has faded away
 task.delay(math.max(0,(msg.flightSeconds or 9)-2.5),function()
  if token~=introToken then return end
  local fade=TweenService:Create(cheers,TweenInfo.new(5.4,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{Volume=0})
  fade.Completed:Connect(function() cheers.Looped=false end)
  fade:Play()
 end)
 local p0=start.Position
 local p3=finish.Position
 local offset=p0-Vector3.new(8,27,82)
 local p1=Vector3.new(8,23,60)+offset
 local p2=Vector3.new(8,10,18)+offset
 local duration=msg.flightSeconds or 9
 while true do
  if token~=introToken or not state.inMatch then return end
  local u=math.clamp((workspace:GetServerTimeNow()-msg.startedAt)/duration,0,1)
  local t=u*u*(3-2*u)
  if not skipped then
   if Settings.reducedMotion then
    camera.CFrame=u<.5 and start or finish
   else
    local inv=1-t
    local position=inv^3*p0+3*inv^2*t*p1+3*inv*t*t*p2+t^3*p3
    local target=(p0+start.LookVector*65):Lerp(p3+finish.LookVector*18,t)
    camera.CFrame=CFrame.lookAt(position,target)
   end
   camera.FieldOfView=75-25*t
  end
  if u>=1 then break end
  RunService.RenderStepped:Wait()
 end
 currentShot=skipped and "Question" or "HostIntroCamera"
 if not skipped then camera.CFrame=finish end
 TweenService:Create(music,TweenInfo.new(.5),{Volume=.05}):Play()
 while workspace:GetServerTimeNow()-msg.startedAt<(msg.contestantAt or 24.2) do
  if token~=introToken or not state.inMatch then return end
  task.wait(.05)
 end
 for _,v in ipairs(msg.contestants) do
  if token~=introToken then return end
  if not skipped then cut("Podium"..v.seat) end
  progress.Text=v.name.." — READY"
  task.wait(2 / #msg.contestants)
 end
 cut("HostIntroCamera");camera.FieldOfView=70
 while workspace:GetServerTimeNow()-msg.startedAt<msg.introSeconds do task.wait(.05) end
 if token~=introToken or not state.inMatch then return end
 skipIntro.Visible=false
 Remotes.IntroReady:FireServer(msg.matchId,"done")
end

handlers.MatchIntro = function(msg)
	state.inIntro=true
	for _,name in ipairs({"Shop","DailyWheel"}) do local modalGui=gui:FindFirstChild(name);if modalGui then modalGui.Visible=false end end
	revealToken += 1
	state.inMatch = true
	state.mode=msg.mode
	state.matchId=msg.matchId
	state.seat = msg.yourSeat
	state.maxLength = msg.maxLength or 60
	player:SetAttribute("ClamillionSeat", msg.yourSeat)
	results.Visible = false
	howModal.Visible = false
	showLobby(false)
	hud.Visible = true
	buildStandings(msg.contestants)
	progress.Text = "WELCOME TO CLAMILLION"
	local names = {}
	for _, c in ipairs(msg.contestants) do table.insert(names, UI.Seats[c.seat].icon .. " " .. c.name) end
	showBanner("CLAMILLION", "Tonight's contestants:\n" .. table.concat(names, "    "))
	setAnswerMode("hidden")
	task.spawn(cinematic,msg)
end

-- the host's words show in the speech bubble by her head on stage (no extra caption at the top)
handlers.Host = function(msg) if state.inIntro then speak(msg.text) end end

handlers.RoundIntro = function(msg)
	state.inIntro=false
	stopIntroAudio()
	revealToken += 1
	progress.Text = ("ROUND %d OF %d"):format(msg.round, msg.rounds)
	setHype(0.4); setHype(0.85, 3)
	jumbo(string.upper(msg.name) .. "!", "LET'S GOOO!")
	if msg.round > 1 then pyro(0.8) end
	showBanner(string.upper(msg.name), "Common +10 · Uncommon +30 · Rare +60\nVery Rare +85 · Extremely Rare +100")
	setAnswerMode("hidden")
	cut("HostIntroCamera") -- the host is talking: keep the camera on the host
end

handlers.Question = function(msg)
	revealToken += 1
	hideCentre()
	progress.Text = msg.label
	setHype(0.12); hype.untilT = 0
	jumbo("SHHH... THINKING!", string.upper(msg.category))
	qCategory.Text = string.upper(msg.category) .. "  ·  RARITY POINTS"
	qPrompt.Text = msg.prompt
	qCard.Visible = true
	pop(qCard)
	state.submitting=false
 suggestion=nil
	state.questionToken=msg.token
	state.deadline = msg.deadline
	state.duration = msg.duration
	state.locked = false
	state.finalSent = false
	state.hinted = false
	hintUI.token = (hintUI.token or 0) + 1
	hintUI.banner.Visible = false
	hintUI.btn.Text = "HINT ?"; hintUI.btn.TextTransparency = 0
	refreshHintPrice()
	state.participating = table.find(msg.participants, state.seat) ~= nil
	for seat in pairs(rows) do setRowStatus(seat, table.find(msg.participants, seat) and "Thinking" or "Out") end
	setAnswerText("")
	state.questionActive = true
	if state.participating then
		setAnswerMode("answer")
		task.defer(function() answerBox:CaptureFocus() end)
	else
		setAnswerMode("spectate", "You're watching this tiebreaker")
	end
	cut(state.participating and "Player" or "Question")
end

handlers.Status = function(msg)
	setRowStatus(msg.seat, msg.status)
	if msg.seat == state.seat and msg.status == "TimeUp" and state.participating then
		state.locked = true
		local t = Profanity.mask(trim(answerReal))
		setAnswerMode("locked", t ~= "" and t or "(no answer)")
		lockedLabel.Text = "⏱ TIME UP" .. (t ~= "" and (": " .. t) or "")
	end
end

handlers.LockAck = function(msg)
	if msg.token~=state.questionToken or not state.questionActive then return end
 state.submitting=false
	if msg.ok then
		state.locked = true
		answerBox:ReleaseFocus()
		setAnswerMode("locked", Profanity.mask(trim(answerReal)))
	else
		if msg.reason=="suggestion" and type(msg.suggestion)=="string" then
   suggestion=msg.suggestion
   lockedLabel.Visible=false;answerBox.TextEditable=true
   retryFeedback.Text='Did you mean "'..Profanity.mask(suggestion)..'"? Press Enter or tap CONFIRM.'
   retryFeedback.TextColor3=C.Gold;retryFeedback.Visible=true
   lockBtn.Text="CONFIRM"
   task.defer(function()if state.questionActive and not state.locked then answerBox:CaptureFocus() end end)
  elseif msg.reason=="unrecognized" or msg.reason=="blank" then
   suggestion=nil
   retryAnswer()
   task.defer(function()
    if state.questionActive and not state.locked and not settingsModal.Visible and not answerBox:IsFocused() then answerBox:CaptureFocus() end
   end)
  elseif msg.reason=="late" then lockBtn.Text="TIME UP"
  else lockBtn.Text="LOCK IN" end
	end
end

handlers.Hint = function(msg)
	if msg.token ~= state.questionToken or not state.questionActive or state.locked then return end
	state.hinted = true
	hintUI.btn.Text = "HINT ✓"; hintUI.btn.TextTransparency = 0.35
	hintUI.price.Text = "USED"; hintUI.price.TextColor3 = C.Muted
	hintUI.token = (hintUI.token or 0) + 1 -- keep the hint up until the answer is locked
	setAnswerText(msg.answer)
	hintUI.banner.Text = ("💡 HINT: %s  •  %s, %d points! Lock it in!"):format(Profanity.mask(msg.answer), msg.label or "Very Rare", msg.points or 85)
	hintUI.banner.Visible = true
	task.defer(function() if state.questionActive and not state.locked then answerBox:CaptureFocus() end end)
end
handlers.Celebrate = function(msg)
	local who = Players:GetPlayerByUserId(msg.userId)
	if who and who.Character then pcall(function() require(root.Shared.EmotePlayer).play(who.Character, msg.emote) end) end
end
handlers.HintSaved = function()
	-- the purchase finished after time ran out: it's banked, and the HINT button now says FREE
	hintUI.note("💡 Time ran out, so your hint is saved. Your next HINT is FREE!")
end

handlers.Reveal = function(msg)
	revealToken += 1
	local token = revealToken
	if msg.tiebreak then progress.Text = "TIEBREAKER · REVEAL" end
	playReveal(msg, token)
end

handlers.RoundTransition = function(msg)
	revealToken += 1
	local lines = {}
	table.sort(msg.standings, function(a, b) return a.score > b.score end)
	for _, s in ipairs(msg.standings) do
		setRowScore(s.seat, s.score)
		table.insert(lines, UI.Seats[s.seat].icon .. " " .. s.name .. "  " .. UI.formatNumber(s.score))
	end
	showBanner("END OF ROUND " .. msg.finished, table.concat(lines, "\n"))
	setHype(0.9, 4); pyro(1); jumbo("ROUND " .. msg.finished .. " DONE!", "WHAT A SHOW!")
	setAnswerMode("hidden")
	cut("HostIntroCamera") -- the host is talking: keep the camera on the host
end

handlers.Tiebreak = function(msg)
	revealToken += 1
	progress.Text = "TIEBREAKER"
	showBanner("TIEBREAKER", table.concat(msg.names, "  vs  ") .. "\nMost points on one fresh question wins.")
	setHype(0.9, 3); jumbo("TIEBREAKER!", "WHO WILL WIN?!")
	setAnswerMode("hidden")
	cut("HostIntroCamera") -- the host is talking: keep the camera on the host
end

handlers.Withdrawn = function(msg)
	setRowStatus(msg.seat, "Withdrawn")
	local r = rows[msg.seat]
	if r then r.name.TextTransparency = 0.5 end
end

-- Ask once per session, after a finished show, whether the player wants Clamillion notifications
-- (Roblox's own prompt; it never shows for under-13s, players who already said yes, or anyone
-- who saw it in the last 30 days).
local notifyAsked = false
local function askForNotifications(delaySeconds)
	if notifyAsked then return end
	notifyAsked = true
	task.delay(delaySeconds, function()
		local ENS = game:GetService("ExperienceNotificationService")
		local ok, can = pcall(function() return ENS:CanPromptOptInAsync() end)
		if ok and can then pcall(function() ENS:PromptOptIn() end) end
	end)
end

handlers.Results = function(msg)
	revealToken += 1
	askForNotifications((msg.celebrate or 0) + 14)
	progress.Text = "FINAL RESULTS"
	setHype(1, 12); pyro(1.5); confetti(220); cheerBurst(0.6)
	do
		local names = {}
		for _, seat in ipairs(msg.winners or {}) do for _, p in ipairs(msg.placements) do if p.seat == seat then table.insert(names, string.upper(p.name)) end end end
		jumbo(msg.mode == "Solo" and "SHOW COMPLETE!" or "WINNER!", table.concat(names, " & "))
		task.delay(2.5, function() if state.inMatch then pyro(1.2); confetti(160) end end)
	end
	for _, p in ipairs(msg.placements) do setRowScore(p.seat, p.score) end
	showResults(msg)
end

handlers.MatchEnded = function(msg)
 emoteUI.picker.Visible = false
 celebration.stop()
 stopIntroAudio()
 setUnderwater(false)
 inLobby=true;if Settings.audio then lobbyMusic:Play() end
	lobbyLighting(true)
	resetCrowd()
	state.inIntro=false
	introToken+=1;skipIntro.Visible=false
	revealToken += 1
	state.inMatch = false
	state.questionActive = false
	player:SetAttribute("ClamillionSeat", nil)
	hud.Visible = false
	caption.Visible = false
	restoreCamera()
	leaveModal.Visible = false
	if msg.left then results.Visible = false end
	if msg.cancelled then results.Visible = false;queueLabel.Text="Match canceled. Choose a mode to try again." end
	if not results.Visible then showLobby(true) end
	if state.replay then state.replay=false;showLobby(true) end
end


end
-- Shop icon on the right; everything else in the lobby lives in the world.
-- SHOP and MYSTERY BOX (MysteryBoxClient) sit as a pair centred on the right edge
local shopButton=menuButton({Name="ShopIcon",AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-14,.5,-62),Size=UDim2.fromOffset(96,104),Rotation=-4,Parent=gui},"🛍️","SHOP",MENU_COLORS.shop)
-- the shop floats gently and has a little sparkle badge, to draw the eye
do
 local badge=make("TextLabel",{Name="Sparkle",AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.new(1,-6,0,6),Size=UDim2.fromOffset(30,30),BackgroundColor3=Color3.fromRGB(255,60,140),Text="✨",TextScaled=true,Font=UI.FontBlack,ZIndex=4,Parent=shopButton},{make("UICorner",{CornerRadius=UDim.new(1,0)}),make("UIStroke",{Color=C.White,Thickness=2.5})})
 task.spawn(function()
  while shopButton.Parent do
   if not Settings.reducedMotion and shopButton.Visible then
    local t=os.clock()
    shopButton.Position=UDim2.new(1,-14,.5,-62+math.sin(t*1.8)*5)
    badge.Rotation=math.sin(t*3)*15
    badge.Size=UDim2.fromOffset(30+math.sin(t*4)*3,30+math.sin(t*4)*3)
   end
   RunService.Heartbeat:Wait()
  end
 end)
end
;(function() -- shop, wheel, cosmetics, obby and rewards UI (own function: Luau allows only 200 locals per function)
---------------------------------------------------------------- the show shop
-- Tabs for podium themes (with live 3D previews), arenas and titles. Buy / Equip / Equipped.
local Catalog = require(root.Shared:WaitForChild("ShopCatalog"))
local PodiumThemes = require(root.Shared:WaitForChild("PodiumThemes"))
local shopModal, shopBody = modal("Shop", "★ THE SHOW SHOP ★", 620)
shopModal:FindFirstChildWhichIsA("Frame"):FindFirstChildOfClass("UISizeConstraint").MaxSize = Vector2.new(780, 620)
local shopState = { owned = {}, equipped = {}, tab = "Podium", mode = "shop" }
-- emote TRY button: 3 tries per emote, tracked only on this device (emote id -> tries used)
local EMOTE_TRIES = 3
local emoteTriesUsed = {}
local shopTitle = shopModal:FindFirstChildWhichIsA("Frame"):FindFirstChild("Title")
local tabs = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), ZIndex = 22, Parent = shopBody })
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8), Parent = tabs })
local shopNote = label({ Text = "", Font = UI.FontBody, TextColor3 = C.Gold, Position = UDim2.new(0, 0, 0, 50), Size = UDim2.new(1, 0, 0, 22), ZIndex = 22, Parent = shopBody }, 16)
local grid = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.new(0, 0, 0, 78), Size = UDim2.new(1, 0, 1, -78), ScrollBarThickness = 8,
	ScrollBarImageColor3 = C.Gold, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 22, Parent = shopBody })
local gridLayout = make("UIGridLayout", { CellPadding = UDim2.fromOffset(10, 10), CellSize = UDim2.fromOffset(170, 236), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8), Parent = grid })

local function noteFor(text, color) shopNote.Text = text; shopNote.TextColor3 = color or C.Gold end
local function defaultNote()
	if shopState.studioUnlock then noteFor("Studio test mode: everything is unlocked so you can try it all on!", C.Mint)
	elseif shopState.mode == "inventory" then noteFor("Tap EQUIP to use it. It shows up in your next show!", C.Gold)
	elseif shopState.tab == "Arena" then noteFor("🏟 Your arena is just for YOU — in a 1v1 or 1v1v1 everyone sees their own! 500 R$", C.Gold)
	elseif shopState.tab == "Emote" then noteFor("💃 Tap EMOTE (bottom left) to bust a move any time! Your equipped one plays when you WIN. 50 R$", C.Gold)
	else noteFor("Podiums 200 R$ • Arenas 500 R$ • Titles 50 R$ • Emotes 50 R$", C.Gold) end
end

-- a little 3D model of the podium in its theme
local function podiumPreview(parent, theme)
	local vp = make("ViewportFrame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), ZIndex = 24, Ambient = Color3.fromRGB(200, 200, 220), LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-1, -1, -1), Parent = parent })
	local template = studio:FindFirstChild("Podiums") and studio.Podiums:FindFirstChild("Podium2") or workspace.ClamillionStudio.Podiums:FindFirstChild("Podium2")
	if not template then return vp end
	local model = template:Clone()
	model:PivotTo(CFrame.new())
	pcall(PodiumThemes.apply, model, theme)
	model.Parent = vp
	local cam = make("Camera", { FieldOfView = 42, Parent = vp })
	-- the podium faces -Z once pivoted to the origin; look at its front (display side)
	cam.CFrame = CFrame.lookAt(Vector3.new(-9, 8.5, -19), Vector3.new(0, 3.4, 1.0))
	vp.CurrentCamera = cam
	return vp
end

-- a still shot of the arena from above the crowd (Shared.ArenaShots); emoji if images aren't allowed
local ArenaShotImage = require(root.Shared:WaitForChild("ArenaShotImage"))
local function arenaPreview(parent, item)
	local ok, img = pcall(ArenaShotImage.get, item.theme or "Classic")
	if ok and img then
		local pic = make("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Crop, ZIndex = 24, Parent = parent }, { corner(12) })
		pic.ImageContent = Content.fromObject(img)
	else
		label({ Text = item.icon, Size = UDim2.fromScale(1, 1), ZIndex = 24, Parent = parent }, 70)
	end
end

-- Emote preview that only YOU see: a local copy of your avatar does the emote while your real
-- avatar is hidden on your screen and held still. Nothing here replicates to other players.
local function previewEmote(char, emoteId)
	local wasArchivable = char.Archivable
	char.Archivable = true
	local ok, clone = pcall(function() return char:Clone() end)
	char.Archivable = wasArchivable
	if not ok or not clone then return 0 end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("ForceField") or d:IsA("Sound") then d:Destroy() end
	end
	clone.Name = "EmotePreview"
	local cloneRoot = clone:FindFirstChild("HumanoidRootPart")
	if cloneRoot then cloneRoot.Anchored = true end
	local cloneHum = clone:FindFirstChildOfClass("Humanoid")
	if cloneHum then cloneHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
	clone:PivotTo(char:GetPivot())
	clone.Parent = workspace
	local saved = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then table.insert(saved, { d, "Transparency", d.Transparency }); d.Transparency = 1
		elseif d:IsA("BillboardGui") then table.insert(saved, { d, "Enabled", d.Enabled }); d.Enabled = false end
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local walk, jump = hum and hum.WalkSpeed, hum and hum.JumpHeight
	if hum then hum.WalkSpeed = 0; hum.JumpHeight = 0 end
	local dur = require(root.Shared.EmotePlayer).play(clone, emoteId)
	task.delay(dur + 0.2, function()
		clone:Destroy()
		for _, s in ipairs(saved) do
			local obj, prop, value = s[1], s[2], s[3]
			if obj.Parent then obj[prop] = value end
		end
		if hum and hum.Parent then hum.WalkSpeed = walk; hum.JumpHeight = jump end
	end)
	return dur
end

local function itemButton(item)
	local owned = shopState.owned[item.id]
	local equipped = shopState.equipped[item.kind] == item.id or (item.source == "free" and not shopState.equipped[item.kind])
	if equipped then return "EQUIPPED ✓", "green" end
	if owned then return "EQUIP", "gold" end
	if item.source == "wheel" then return "WIN ON WHEEL", "dark" end
	if item.source == "shop" and item.price then return "R$ " .. item.price, "pink" end
	return "COMING SOON", "dark"
end

local tabButtons = {}
local renderShop
local function onItemPressed(item)
	local equipped = shopState.equipped[item.kind] == item.id
	local result
	if equipped then
		result = Remotes.ShopRequest:InvokeServer("unequip", item.kind)
		noteFor(item.name .. " taken off.", C.Muted)
	elseif shopState.owned[item.id] then
		result = Remotes.ShopRequest:InvokeServer("equip", item.id)
		noteFor("✨ " .. item.name .. " equipped!", C.Mint)
	else
		result = Remotes.ShopRequest:InvokeServer("buy", item.id)
		if result and result.reason == "soon" then noteFor("⏳ Purchases open soon! " .. item.name .. " will be " .. (item.price or "?") .. " R$.", C.Gold)
		elseif result and result.reason == "wheel" then noteFor("🎡 Win this title on the Daily Wheel!", C.Gold) end
	end
	if result and result.state then shopState.owned, shopState.equipped = result.state.owned, result.state.equipped end
	renderShop()
end

renderShop = function()
	for _, c in ipairs(grid:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
	resetCursor()
	local kind = shopState.tab
	gridLayout.CellSize = kind == "Title" and UDim2.fromOffset(170, 112) or (kind == "Arena" and UDim2.fromOffset(346, 318)) or UDim2.fromOffset(170, 236)
	local ph = kind == "Arena" and 186 or 116 -- picture height (arena pictures are 16:9 still shots)
	for k, b in pairs(tabButtons) do b.Candy.Color = k == kind and ColorSequence.new(C.Gold, Color3.fromRGB(255, 160, 20)) or ColorSequence.new(Color3.fromRGB(150, 90, 255), Color3.fromRGB(96, 46, 210)) end
	local shown = 0
	for i, item in ipairs(Catalog.Kinds[kind]) do
		if shopState.mode == "inventory" and not shopState.owned[item.id] then continue end
		if shopState.mode == "shop" and item.source == "reward" then continue end -- earned at the Rewards stand
		shown += 1
		local card = make("Frame", { LayoutOrder = i, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 23, Parent = grid }, { corner(18), stroke(C.White, 3) })
		make("UIGradient", { Rotation = 90, Color = ColorSequence.new(item.colors and item.colors[1] or Color3.fromRGB(150, 90, 255), item.colors and item.colors[2] or Color3.fromRGB(90, 40, 200)), Parent = card })
		local text, style = itemButton(item)
		if kind == "Title" then
			label({ Text = item.icon, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 0, 6), ZIndex = 24, Parent = card }, 30)
			local nameLabel = label({ Text = item.name, Font = UI.FontBlack, Position = UDim2.new(0, 8, 0, 38), Size = UDim2.new(1, -16, 0, 26), ZIndex = 24, Parent = card }, 20)
			if item.anim then nameLabel:SetAttribute("Anim", item.anim); game:GetService("CollectionService"):AddTag(nameLabel, "AnimatedTitle") end
			local b = button({ Text = text, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -16, 0, 34), ZIndex = 24, Parent = card }, style, 15)
			b.Activated:Connect(function() onItemPressed(item) end)
		else
			local preview = make("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.75, Position = UDim2.new(0, 8, 0, 8), Size = UDim2.new(1, -16, 0, ph), ZIndex = 23, Parent = card }, { corner(12) })
			if kind == "Podium" then podiumPreview(preview, item.theme)
			elseif kind == "Emote" then
				local icon = label({ Text = item.icon, Size = UDim2.fromScale(1, 1), ZIndex = 24, Parent = preview }, 70)
				icon:SetAttribute("Anim", "pulse"); game:GetService("CollectionService"):AddTag(icon, "AnimatedTitle")
				-- try it on your own avatar: 3 tries PER EMOTE, counted on this device only (no server
				-- involved) and only YOU see the preview. Counts start fresh each time you join.
				local left = math.max(0, EMOTE_TRIES - (emoteTriesUsed[item.id] or 0))
				local try = button({ Text = left > 0 and ("▶ TRY (" .. left .. ")") or "TRIED", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.new(0, 92, 0, 30), ZIndex = 25, Parent = preview }, left > 0 and "gold" or "dark", 14)
				try.Activated:Connect(function()
					local char = player.Character
					if state.inMatch or not char or shopState.trying then return end
					local used = emoteTriesUsed[item.id] or 0
					if used >= EMOTE_TRIES then
						noteFor(("You've used all %d tries of %s! Get it to use it anytime."):format(EMOTE_TRIES, item.name), C.Gold)
						return
					end
					emoteTriesUsed[item.id] = used + 1
					local remaining = EMOTE_TRIES - used - 1
					shopState.trying = true
					shopModal.Visible = false
					local dur = previewEmote(char, item.id)
					task.delay(dur + 0.4, function()
						shopState.trying = false
						if not state.inMatch and not shopModal.Visible then
							shopModal.Visible = true; renderShop()
							noteFor(("👀 Only you saw that! %d %s left for %s"):format(remaining, remaining == 1 and "try" or "tries", item.name), C.Mint)
						end
					end)
				end)
			elseif kind == "Arena" then arenaPreview(preview, item)
			else label({ Text = item.icon, Size = UDim2.fromScale(1, 1), ZIndex = 24, Parent = preview }, 70) end
			label({ Text = item.icon .. " " .. item.name, Font = UI.FontBlack, Position = UDim2.new(0, 8, 0, ph + 12), Size = UDim2.new(1, -16, 0, 24), ZIndex = 24, Parent = card }, kind == "Arena" and 22 or 19)
			label({ Text = item.blurb or "", Font = UI.FontBody, Position = UDim2.new(0, 8, 0, ph + 36), Size = UDim2.new(1, -16, 0, 36), ZIndex = 24, Parent = card }, kind == "Arena" and 15 or 13)
			local b = button({ Text = text, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -16, 0, 36), ZIndex = 24, Parent = card }, style, 16)
			b.Activated:Connect(function() onItemPressed(item) end)
		end
	end
	if shown == 0 then
		gridLayout.CellSize = UDim2.new(1, -20, 0, 120)
		local empty = make("Frame", { BackgroundTransparency = 1, ZIndex = 23, Parent = grid })
		label({ Text = "Nothing here yet!\nGet some in the 🛍 Shop" .. (kind == "Title" and " or win one on the 🎡 Daily Wheel!" or "!"), Font = UI.FontBody, Size = UDim2.fromScale(1, 1), ZIndex = 24, Parent = empty }, 22)
	end
end

for i, t in ipairs({ { "Podium", "🎤 PODIUMS" }, { "Arena", "🏟 ARENAS" }, { "Title", "🏷 TITLES" }, { "Emote", "💃 EMOTES" } }) do
	local b = button({ LayoutOrder = i, Text = t[2], Size = UDim2.new(0.235, 0, 1, 0), ZIndex = 23, Parent = tabs }, "dark", 18)
	tabButtons[t[1]] = b
	b.Activated:Connect(function() shopState.tab = t[1]; defaultNote(); renderShop() end)
end

local shopListeners = {} -- other menus (Rewards) that redraw when ownership changes
local function applyShopState(s)
	if type(s) ~= "table" then return end
	shopState.owned, shopState.equipped, shopState.studioUnlock = s.owned or {}, s.equipped or {}, s.studioUnlock
	if s.tries then shopState.tries = s.tries end
	if shopModal.Visible then renderShop() end
	for _, fn in ipairs(shopListeners) do task.spawn(fn) end
end
Remotes.ShopUpdate.OnClientEvent:Connect(function(s, extra)
	applyShopState(s)
	if extra and extra.purchased then
		local item = Catalog.get(extra.purchased)
		if item then noteFor("🎉 You got " .. item.name .. "! It's equipped.", C.Mint) end
	end
end)
local function openStore(mode)
	if state.inMatch then return end
	shopState.mode = mode
	if shopTitle then shopTitle.Text = mode == "inventory" and "🎒 MY STUFF" or "★ THE SHOW SHOP ★" end
	shopModal.Visible = true
	defaultNote()
	task.spawn(function()
		local ok, s = pcall(function() return Remotes.ShopRequest:InvokeServer("inventory") end)
		if ok then applyShopState(s) end
		defaultNote()
		renderShop()
	end)
	renderShop()
end
local function openShop() openStore("shop") end
shopButton.Activated:Connect(openShop)
invBtn.Activated:Connect(function() openStore("inventory") end)
-- shared helpers; the sections below are wrapped in do-blocks to stay under Luau's 200-local limit
local showWheelResult, animateLabel, showToast
do
---------------------------------------------------------------- daily wheel
-- The server decides the prize and where the wheel stops; every client animates the spin
-- smoothly from the SpinFrom/SpinTo attributes so it looks the same for everyone watching.
local wheelModal,wheelBody=modal("DailyWheel","★ DAILY WHEEL ★",300)
local wheelPrize=label({Text="",Font=UI.FontBlack,TextColor3=C.Gold,Size=UDim2.new(1,0,0,70),Parent=wheelBody,ZIndex=23},44)
local wheelNote=label({Text="",Font=UI.FontBody,Position=UDim2.new(0,0,0,78),Size=UDim2.new(1,0,0,60),Parent=wheelBody,ZIndex=23},20)
local wheelCountdown=label({Text="",Font=UI.FontBody,TextColor3=C.Mint,Position=UDim2.new(0,0,0,140),Size=UDim2.new(1,0,0,26),Parent=wheelBody,ZIndex=23},18)
local function fmtCountdown(sec)
 sec=math.max(0,math.floor(sec))
 return ("%d:%02d:%02d"):format(math.floor(sec/3600),math.floor(sec/60)%60,sec%60)
end
local wheelOk=button({Text="AWESOME!",AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,0),Size=UDim2.new(.6,0,0,52),ZIndex=23,Parent=wheelBody},"gold",24)
wheelOk.Activated:Connect(function() wheelModal.Visible=false end)
local wheelTick=make("Sound",{Name="WheelTick",SoundId="rbxasset://sounds/clickfast.wav",Volume=.35,Parent=SoundService})
task.spawn(function()
 local wheel=workspace:WaitForChild("ShowLobby"):WaitForChild("Activities"):WaitForChild("DailyWheel",30)
 if not wheel then return end
 local rotor=wheel:WaitForChild("Rotor")
 local spinToken=0
 local function animate()
  spinToken+=1
  local token=spinToken
  local rest=wheel:GetAttribute("RestPivot")
  local a0,a1=wheel:GetAttribute("SpinFrom"),wheel:GetAttribute("SpinTo")
  local start,dur=wheel:GetAttribute("SpinStart"),wheel:GetAttribute("SpinDuration")
  if typeof(rest)~="CFrame" or not (a0 and a1 and start and dur) then return end
  local bulbs={}
  for _,b in ipairs(rotor:GetChildren()) do if b:GetAttribute("Bulb") then table.insert(bulbs,b) end end
  local lastSlot
  while token==spinToken do
   local u=math.clamp((workspace:GetServerTimeNow()-start)/dur,0,1)
   local e=1-(1-u)^4
   local angle=a0+(a1-a0)*e
   rotor:PivotTo(rest*CFrame.Angles(angle,0,0))
   local slot=math.floor(angle/(math.pi/(wheel:GetAttribute("Slices") or 8)))
   if slot~=lastSlot then
    lastSlot=slot
    if Settings.audio and not state.inMatch then wheelTick.PlaybackSpeed=1+(1-u)*.3;wheelTick:Play() end
    for i,b in ipairs(bulbs) do b.Color=((i+slot)%2==0) and Color3.fromRGB(255,255,200) or Color3.fromRGB(255,80,190) end
   end
   if u>=1 then break end
   RunService.RenderStepped:Wait()
  end
  -- landed: confetti burst over the wheel (everyone nearby sees it)
  if token==spinToken and Settings.effects then
   local point=wheel:FindFirstChild("ConfettiPoint")
   local att=point and point:FindFirstChildOfClass("Attachment")
   if att then for _,pe in ipairs(att:GetChildren()) do if pe:IsA("ParticleEmitter") then pe:Emit(90) end end end
  end
 end
 wheel:GetAttributeChangedSignal("SpinId"):Connect(animate)
 -- personal countdown above the spin pad: "SPIN READY!" or time left until the 10 AM reset
 local interact=wheel:WaitForChild("Interact",10)
 if not interact then return end
 local bb=make("BillboardGui",{Name="WheelCountdown",Adornee=interact,Size=UDim2.fromOffset(240,56),StudsOffset=Vector3.new(0,5,0),MaxDistance=70,AlwaysOnTop=true,LightInfluence=0,Parent=gui.Parent})
 local card=make("Frame",{Size=UDim2.fromScale(1,1),BackgroundColor3=C.PanelPink,Parent=bb},{corner(18),stroke(C.White,3)})
 local cdText=label({Text="",Font=UI.FontBlack,Size=UDim2.fromScale(1,1),Parent=card},26)
 pad(6).Parent=card
 while true do
  local nextSpin=player:GetAttribute("NextWheelSpin")
  local left=nextSpin and nextSpin-workspace:GetServerTimeNow() or 0
  if left>0 then
   cdText.Text="⏰ NEXT SPIN "..fmtCountdown(left)
   card.BackgroundColor3=Color3.fromRGB(120,70,230)
  else
   cdText.Text="✨ SPIN READY!"
   card.BackgroundColor3=C.PanelPink
  end
  bb.Enabled=not state.inMatch
  if wheelModal.Visible and left>0 then wheelCountdown.Text="Next spin in "..fmtCountdown(left).." (resets at 10 AM)" end
  task.wait(0.5)
 end
end)
showWheelResult = function(msg)
 if state.inMatch then return end
 local left=msg.nextSpin and msg.nextSpin-workspace:GetServerTimeNow() or 0
 wheelCountdown.Text=left>0 and ("Next spin in "..fmtCountdown(left).." (resets at 10 AM)") or ""
 if msg.error then
  wheelPrize.Text="⏰ NOT YET!";wheelPrize.TextColor3=C.Muted
  wheelNote.Text=msg.text or "Come back later for another spin."
  wheelOk.Text="OK!"
 else
  wheelPrize.Text="★ "..string.upper(msg.title or "").." ★";wheelPrize.TextColor3=C.Gold
  wheelNote.Text="Added to your 🎒 Inventory! Open it to put this title on your podium."
  wheelOk.Text="AWESOME!"
 end
 wheelModal.Visible=true
 pop(wheelModal:FindFirstChildWhichIsA("Frame"))
end
end
do
---------------------------------------------------------------- animated cosmetics
-- Anything tagged "RainbowCycle" (animated podium parts) cycles through the rainbow, and any
-- TextLabel tagged "AnimatedTitle" (with an Anim attribute) animates. Works on podiums in shows,
-- overhead titles in the lobby, and the previews in the shop / inventory / rewards menus.
local CollectionService = game:GetService("CollectionService")
local function kp(t, c) return ColorSequenceKeypoint.new(t, c) end
local TITLE_ANIMS = {
	gold = ColorSequence.new({ kp(0, Color3.fromRGB(255, 190, 40)), kp(0.42, Color3.fromRGB(255, 205, 60)), kp(0.5, Color3.new(1, 1, 1)), kp(0.58, Color3.fromRGB(255, 205, 60)), kp(1, Color3.fromRGB(255, 190, 40)) }),
	sparkle = ColorSequence.new({ kp(0, Color3.fromRGB(110, 220, 255)), kp(0.42, Color3.fromRGB(150, 230, 255)), kp(0.5, Color3.new(1, 1, 1)), kp(0.58, Color3.fromRGB(150, 230, 255)), kp(1, Color3.fromRGB(110, 220, 255)) }),
	candy = ColorSequence.new({ kp(0, Color3.fromRGB(255, 120, 200)), kp(0.5, Color3.fromRGB(130, 210, 255)), kp(1, Color3.fromRGB(200, 150, 255)) }),
	pulse = ColorSequence.new({ kp(0, Color3.fromRGB(255, 150, 50)), kp(1, Color3.fromRGB(255, 230, 80)) }),
	-- Halloween: pumpkin orange -> witchy purple -> slime green, oozing back and forth
	spooky = ColorSequence.new({ kp(0, Color3.fromRGB(255, 120, 20)), kp(0.35, Color3.fromRGB(255, 170, 40)), kp(0.6, Color3.fromRGB(170, 80, 255)), kp(1, Color3.fromRGB(110, 255, 90)) }),
}
local function rainbowSequence(shift)
	local keys = {}
	for i = 0, 6 do keys[i + 1] = kp(i / 6, Color3.fromHSV((shift + i / 6) % 1, 0.7, 1)) end
	return ColorSequence.new(keys)
end
local function titleGradient(l)
	local g = l:FindFirstChild("AnimGradient")
	if not g then
		g = make("UIGradient", { Name = "AnimGradient", Color = TITLE_ANIMS[l:GetAttribute("Anim")] or rainbowSequence(0), Parent = l })
		l.TextColor3 = Color3.new(1, 1, 1)
	end
	return g
end
-- tag a UI label so it animates like the real title (used by the menus)
animateLabel = function(l, anim)
	if not anim then return end
	l:SetAttribute("Anim", anim)
	CollectionService:AddTag(l, "AnimatedTitle")
end
local cosmeticClock = 0
RunService.RenderStepped:Connect(function(dt)
	cosmeticClock += dt
	if cosmeticClock < 1 / 30 then return end
	cosmeticClock = 0
	local t = os.clock()
	local still = Settings.reducedMotion
	for _, p in ipairs(CollectionService:GetTagged("RainbowCycle")) do
		if p:IsA("BasePart") then p.Color = Color3.fromHSV(((still and 0 or t * 0.25) + (p:GetAttribute("RainbowOffset") or 0)) % 1, 0.75, 1) end
	end
	for _, l in ipairs(CollectionService:GetTagged("AnimatedTitle")) do
		if l:IsA("TextLabel") and l.Parent then
			local anim = l:GetAttribute("Anim")
			local g = titleGradient(l)
			if still then continue end
			if anim == "rainbow" then
				g.Color = rainbowSequence(t * 0.35)
			elseif anim == "gold" or anim == "sparkle" then
				-- a shine that sweeps across, then pauses
				local phase = (t * (anim == "sparkle" and 0.9 or 0.6)) % 1.6
				g.Offset = Vector2.new(math.clamp(phase * 1.4 - 1.1, -1, 1), 0)
			elseif anim == "candy" then
				g.Offset = Vector2.new(math.sin(t * 1.6) * 0.5, 0)
			elseif anim == "spooky" then
				g.Offset = Vector2.new(math.sin(t * 1.3) * 0.55, 0)
				l.Rotation = math.sin(t * 2.2) * 2.5
			elseif anim == "pulse" then
				g.Offset = Vector2.new(0, math.sin(t * 4) * 0.5)
				l.Rotation = math.sin(t * 3.2) * 3
			end
		end
	end
end)

end
---------------------------------------------------------------- lobby title board
-- chasing marquee bulbs + spinning starbursts on the big CLAMILLION board
task.spawn(function()
 local marquee=workspace:WaitForChild("ShowLobby"):WaitForChild("TitleMarquee",30)
 if not marquee then return end
 local bulbs,stars={},{}
 for _,d in ipairs(marquee:GetDescendants()) do
  if d:IsA("BasePart") and d:GetAttribute("LobbyChase") then table.insert(bulbs,{part=d,i=d:GetAttribute("LobbyChase")}) end
  if d:IsA("Model") and d:GetAttribute("Spin") and d.PrimaryPart then table.insert(stars,{model=d,home=d:GetPivot(),speed=d:GetAttribute("Spin")}) end
 end
 local warm,pink=Color3.fromRGB(255,240,180),Color3.fromRGB(255,90,200)
 local spookyA,spookyB=Color3.fromRGB(255,130,25),Color3.fromRGB(150,60,255) -- Halloween event: orange + purple
 local acc=0
 RunService.RenderStepped:Connect(function(dt)
  if state.inMatch then return end
  acc+=dt
  if acc<1/12 then return end
  acc=0
  local t=os.clock()
  local moving=Settings.effects and not Settings.reducedMotion
  local step=moving and math.floor(t*8) or 0
  local spooky=Events.isActive("halloween")
  local a,b2=spooky and spookyA or warm,spooky and spookyB or pink
  for _,b in ipairs(bulbs) do b.part.Color=((b.i+step)%4==0) and b2 or a end
  if moving then for _,s in ipairs(stars) do s.model:PivotTo(s.home*CFrame.Angles(0,0,t*s.speed)) end end
 end)
end)

do
---------------------------------------------------------------- mini obby
-- Timer + checkpoint toasts, and the spinning bar (animated here, hits reported to the server).
local obbyHud = panel({ Name = "ObbyHud", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.new(0, 330, 0, 56), Visible = false, Parent = gui })
obbyHud.Candy.Color = ColorSequence.new(Color3.fromRGB(255, 120, 40), Color3.fromRGB(255, 60, 140))
local obbyTime = label({ Text = "⏱ 0:00.00", Font = UI.FontBlack, Position = UDim2.new(0, 12, 0, 4), Size = UDim2.new(0.5, -12, 1, -8), TextXAlignment = Enum.TextXAlignment.Left, Parent = obbyHud }, 28)
local obbyCP = label({ Text = "START", Font = UI.FontBody, Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.new(0.27, 0, 1, -8), Parent = obbyHud }, 18)
local obbyQuit = button({ Text = "QUIT", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0.21, 0, 0, 40), Parent = obbyHud }, "dark", 18)
local toast = label({ Name = "ObbyToast", Text = "", Font = UI.FontBlack, TextColor3 = C.Gold, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.new(0.8, 0, 0, 70), Visible = false, Parent = gui }, 54)
toast:FindFirstChildOfClass("UIStroke").Thickness = 4
local toastToken = 0
showToast = function(text, color, seconds)
 toastToken += 1
 local token = toastToken
 toast.Text = text; toast.TextColor3 = color or C.Gold; toast.Visible = true
 pop(toast)
 task.delay(seconds or 1.8, function() if token == toastToken then toast.Visible = false end end)
end
local function fmtTime(t) return ("%d:%05.2f"):format(math.floor(t / 60), t % 60) end
obbyQuit.Activated:Connect(function() Remotes.ObbyAction:FireServer("quit") end)
Remotes.ObbyAction.OnClientEvent:Connect(function(msg)
 if state.inMatch then return end
 if msg.type == "Start" then showToast("GO GO GO!", C.Good, 1.2)
 elseif msg.type == "Checkpoint" then showToast("🚩 CHECKPOINT " .. msg.checkpoint .. "!", C.Gold, 1.6)
 elseif msg.type == "Respawn" then showToast("OOPS! Try again!", C.Danger, 1.2)
 elseif msg.type == "Finish" then
  showToast((msg.newBest and "🏆 NEW BEST! " or "🏆 FINISHED! ") .. fmtTime(msg.time), C.Gold, 4)
  if Settings.audio then cheers.Volume = 0.6; cheers.TimePosition = 0; cheers:Play() task.delay(2.5, function() TweenService:Create(cheers, TweenInfo.new(0.6), { Volume = 0 }):Play() end) end
 end
end)
task.spawn(function()
 local obby = workspace:WaitForChild("ShowLobby"):WaitForChild("Obby", 30)
 if not obby then return end
 local bar = obby:WaitForChild("Kill"):WaitForChild("SpinnerBar", 10)
 local lastHit = 0
 RunService.RenderStepped:Connect(function()
  -- timer HUD
  local cp = player:GetAttribute("ObbyCP")
  local started = player:GetAttribute("ObbyStart")
  obbyHud.Visible = cp ~= nil and started ~= nil and not state.inMatch
  if obbyHud.Visible then
   obbyTime.Text = "⏱ " .. fmtTime(workspace:GetServerTimeNow() - started)
   obbyCP.Text = cp == 0 and "START" or ("🚩 " .. cp .. " / " .. (obby:GetAttribute("Checkpoints") or 6))
  end
  -- spinning bar
  if bar then
   local center = bar:GetAttribute("Center") or bar.Position
   local angle = workspace:GetServerTimeNow() * (bar:GetAttribute("Speed") or 2)
   bar.CFrame = CFrame.new(center) * CFrame.Angles(0, angle, 0)
   local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
   local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
   if r and hum and cp ~= nil and os.clock() - lastHit > 1 then
    local rel = r.Position - center
    local flat = Vector3.new(rel.X, 0, rel.Z)
    if flat.Magnitude < bar.Size.X / 2 + 1 then
     local dir = bar.CFrame.RightVector
     local along = flat:Dot(dir)
     local off = (flat - dir * along).Magnitude
     local feet = r.Position.Y - (hum.HipHeight + r.Size.Y / 2)
     if off < 1.6 and feet < center.Y + bar.Size.Y / 2 - 0.05 and feet > center.Y - 3 then
      lastHit = os.clock()
      Remotes.ObbyAction:FireServer("hit")
     end
    end
   end
  end
 end)
end)

end
do
---------------------------------------------------------------- rewards stand
-- Free rewards for playing: animated titles (playtime) and podiums (total score).
local rewardsModal, rewardsBody = modal("Rewards", "🍭 REWARDS 🍭", 600)
rewardsModal:FindFirstChildWhichIsA("Frame"):FindFirstChildOfClass("UISizeConstraint").MaxSize = Vector2.new(640, 600)
rewardsModal:FindFirstChildWhichIsA("Frame").Candy.Color = ColorSequence.new(Color3.fromRGB(255, 130, 200), Color3.fromRGB(130, 170, 255))
local rewardsTab = "playtime"
local rTabs = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), ZIndex = 22, Parent = rewardsBody })
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10), Parent = rTabs })
local statCard = make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.8, Position = UDim2.new(0, 0, 0, 54), Size = UDim2.new(1, 0, 0, 58), ZIndex = 22, Parent = rewardsBody }, { corner(16) })
local statBig = label({ Text = "", Font = UI.FontBlack, Position = UDim2.new(0, 10, 0, 2), Size = UDim2.new(1, -20, 0, 32), ZIndex = 23, Parent = statCard }, 26)
local statSmall = label({ Text = "", Font = UI.FontBody, TextColor3 = C.Gold, Position = UDim2.new(0, 10, 0, 34), Size = UDim2.new(1, -20, 0, 20), ZIndex = 23, Parent = statCard }, 15)
local rList = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.new(0, 0, 0, 120), Size = UDim2.new(1, 0, 1, -120), ScrollBarThickness = 8,
	ScrollBarImageColor3 = C.Gold, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 22, Parent = rewardsBody })
make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = rList })
make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8), PaddingRight = UDim.new(0, 10), Parent = rList })

local function fmtPlay(sec)
	sec = math.floor(sec or 0)
	local h, m = math.floor(sec / 3600), math.floor(sec / 60) % 60
	if h > 0 then return ("%dh %02dm"):format(h, m) end
	return ("%d min"):format(m)
end
local function commas(n) local s = tostring(math.floor(n or 0)):reverse():gsub("(%d%d%d)", "%1,"):reverse() return (s:gsub("^,", "")) end
local function reqText(item)
	if item.event then
		if item.req <= 0 then return "FREE during Halloween — yours forever!" end
		return ("Play %d minutes during Halloween"):format(item.req / 60)
	end
	if item.req <= 0 then return "Welcome gift — free!" end
	if item.stat == "playtime" then
		local h = item.req / 3600
		if h < 1 then return ("Play for %d minutes"):format(item.req / 60) end
		return ("Play for %d hour%s"):format(h, h == 1 and "" or "s")
	end
	return "Reach " .. commas(item.req) .. " total score"
end
local STAT_ATTR = { playtime = "Playtime", totalScore = "TotalScore", halloween = "HalloweenPlaytime" }
local function statValue(stat) return player:GetAttribute(STAT_ATTR[stat] or "TotalScore") or 0 end
-- event rewards (Halloween) can only be claimed while the event is on
local function eventOpen(item) return not item.event or Events.isActive(item.event) end
local function claimableCount()
	local n = 0
	for stat, list in pairs(Catalog.Rewards) do
		for _, item in ipairs(list) do if not shopState.owned[item.id] and eventOpen(item) and statValue(stat) >= item.req then n += 1 end end
	end
	return n
end
local function fmtLeft(sec)
	sec = math.max(0, math.floor(sec))
	local d, h, m = math.floor(sec / 86400), math.floor(sec / 3600) % 24, math.floor(sec / 60) % 60
	if d > 0 then return ("%dd %dh %02dm"):format(d, h, m) end
	if h > 0 then return ("%dh %02dm"):format(h, m) end
	return ("%dm %02ds"):format(m, sec % 60)
end

local rTabButtons = {}
local renderRewards
local function claimReward(item)
	local ok, result = pcall(function() return Remotes.ShopRequest:InvokeServer("claim", item.id) end)
	if ok and result then
		if result.state then applyShopState(result.state) end
		if result.ok then
			showToast("🎉 YOU GOT " .. string.upper(item.name) .. "!", C.Gold, 2.5)
			if Settings.audio then
				local ding = SoundService:FindFirstChild("TaskDing") or make("Sound", { Name = "TaskDing", SoundId = "rbxassetid://71587723216424", Volume = 0.6, Parent = SoundService })
				ding.TimePosition = 0; ding:Play() -- quick "task complete" ching
			end
			local stand = workspace.ShowLobby.Activities:FindFirstChild("RewardsStand")
			local sp = stand and stand:FindFirstChild("Sparkles")
			local pe = sp and sp:FindFirstChildOfClass("ParticleEmitter")
			if pe and Settings.effects then pe:Emit(60) end
		end
	end
	renderRewards()
end

local rewardsTitle = rewardsModal:FindFirstChildWhichIsA("Frame"):FindFirstChild("Title")
local function layoutRewardTabs()
	-- the HALLOWEEN tab only shows while the event is on
	local spooky = Events.isActive("halloween")
	if not spooky and rewardsTab == "halloween" then rewardsTab = "playtime" end
	local hb = rTabButtons.halloween
	if hb then hb.Visible = spooky end
	for _, b in pairs(rTabButtons) do b.Size = UDim2.new(spooky and 0.31 or 0.46, 0, 1, 0) end
	if rewardsTitle and rewardsTitle:IsA("TextLabel") then rewardsTitle.Text = spooky and "🎃 REWARDS 🎃" or "🍭 REWARDS 🍭" end
	rewardsModal:FindFirstChildWhichIsA("Frame").Candy.Color = spooky and ColorSequence.new(Color3.fromRGB(255, 130, 30), Color3.fromRGB(110, 40, 190)) or ColorSequence.new(Color3.fromRGB(255, 130, 200), Color3.fromRGB(130, 170, 255))
end
renderRewards = function()
	if not rewardsModal.Visible then return end
	layoutRewardTabs()
	for _, c in ipairs(rList:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
	resetCursor()
	for k, b in pairs(rTabButtons) do b.Candy.Color = k == rewardsTab and ColorSequence.new(C.Gold, Color3.fromRGB(255, 160, 20)) or (k == "halloween" and ColorSequence.new(Color3.fromRGB(255, 120, 20), Color3.fromRGB(120, 40, 200)) or ColorSequence.new(Color3.fromRGB(150, 90, 255), Color3.fromRGB(96, 46, 210))) end
	local value = statValue(rewardsTab)
	if rewardsTab == "halloween" then
		statBig.Text = "🎃 HALLOWEEN EVENT — ends in " .. fmtLeft(Events.secondsLeft("halloween"))
		statSmall.Text = "Claim these FREE before " .. Events.List.halloween.endsText .. ". You keep them forever!"
	elseif rewardsTab == "playtime" then
		statBig.Text = "⏱ You've played " .. fmtPlay(value)
		statSmall.Text = "Keep playing to unlock ANIMATED titles! (AFK time doesn't count)"
	else
		statBig.Text = "🏆 Your total score: " .. commas(value)
		statSmall.Text = "Every point you score in a show counts toward a new podium!"
	end
	for i, item in ipairs(Catalog.Rewards[rewardsTab]) do
		local owned = shopState.owned[item.id]
		local ready = not owned and eventOpen(item) and value >= item.req
		local row = make("Frame", { LayoutOrder = i, BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, -4, 0, 96), ZIndex = 23, Parent = rList }, { corner(18), stroke(ready and C.Gold or C.White, ready and 4 or 3) })
		make("UIGradient", { Rotation = 0, Color = ColorSequence.new(item.colors and item.colors[1] or Color3.fromRGB(255, 120, 200), item.colors and item.colors[2] or Color3.fromRGB(140, 90, 240)), Parent = row })
		local preview = make("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.7, Position = UDim2.new(0, 8, 0, 8), Size = UDim2.new(0, 80, 0, 80), ZIndex = 24, Parent = row }, { corner(14) })
		if item.kind == "Podium" then
			podiumPreview(preview, item.theme)
		elseif item.kind == "Arena" or item.kind == "Emote" then
			local icon = label({ Text = item.icon, Size = UDim2.fromScale(1, 1), ZIndex = 25, Parent = preview }, 44)
			animateLabel(icon, "pulse")
		else
			animateLabel(label({ Text = item.icon, Size = UDim2.fromScale(1, 1), ZIndex = 25, Parent = preview }, 44), item.anim)
		end
		local nameLabel = label({ Text = item.kind == "Title" and (item.icon .. " " .. item.name) or item.name, Font = UI.FontBlack, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0, 98, 0, 8), Size = UDim2.new(1, -250, 0, 28), ZIndex = 24, Parent = row }, 24)
		animateLabel(nameLabel, item.anim)
		local kindTag = item.event and ({ Arena = "ARENA • ", Podium = "PODIUM • ", Emote = "EMOTE • ", Title = "TITLE • " })[item.kind] or ""
		label({ Text = kindTag .. reqText(item) .. (item.animated and " • ANIMATED!" or (item.anim and " • animated title" or "")), Font = UI.FontBody, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0, 98, 0, 38), Size = UDim2.new(1, -250, 0, 20), ZIndex = 24, Parent = row }, 15)
		-- progress bar
		local barBg = make("Frame", { BackgroundColor3 = Color3.fromRGB(40, 20, 80), BackgroundTransparency = 0.3, Position = UDim2.new(0, 98, 0, 64), Size = UDim2.new(1, -250, 0, 20), ZIndex = 24, Parent = row }, { corner(10) })
		local frac = item.req <= 0 and 1 or math.clamp(value / item.req, 0, 1)
		make("Frame", { BackgroundColor3 = (owned or ready) and C.Good or C.Gold, Size = UDim2.new(frac, 0, 1, 0), ZIndex = 25, Parent = barBg }, { corner(10) })
		local progressText = item.req <= 0 and "FREE!" or (item.stat == "playtime" or item.stat == "halloween") and (fmtPlay(math.min(value, item.req)) .. " / " .. fmtPlay(item.req)) or (commas(math.min(value, item.req)) .. " / " .. commas(item.req))
		label({ Text = progressText, Font = UI.FontBody, Size = UDim2.fromScale(1, 1), ZIndex = 26, Parent = barBg }, 13)
		-- button
		local text, style
		if owned then
			if shopState.equipped[item.kind] == item.id then text, style = "EQUIPPED ✓", "green" else text, style = "EQUIP", "gold" end
		elseif ready then text, style = "CLAIM! 🎁", "green"
		else text, style = "🔒 LOCKED", "dark" end
		local b = button({ Text = text, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.new(0, 132, 0, 50), ZIndex = 24, Parent = row }, style, 18)
		if ready and not Settings.reducedMotion then
			local sc = b:FindFirstChildOfClass("UIScale")
			TweenService:Create(sc, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.08 }):Play()
		end
		b.Activated:Connect(function()
			if ready then claimReward(item)
			elseif owned then
				local action = shopState.equipped[item.kind] == item.id and "unequip" or "equip"
				local ok, result = pcall(function() return Remotes.ShopRequest:InvokeServer(action, action == "unequip" and item.kind or item.id) end)
				if ok and result and result.state then applyShopState(result.state) end
				renderRewards()
			end
		end)
	end
end
for i, t in ipairs({ { "halloween", "🎃 HALLOWEEN" }, { "playtime", "⏱ PLAYTIME" }, { "totalScore", "🏆 TOTAL SCORE" } }) do
	local b = button({ LayoutOrder = i, Text = t[2], Size = UDim2.new(0.46, 0, 1, 0), ZIndex = 23, Parent = rTabs }, "dark", 20)
	rTabButtons[t[1]] = b
	b.Activated:Connect(function() rewardsTab = t[1]; renderRewards() end)
end
rTabButtons.halloween.Visible = false
-- while the event is on, the Rewards stand opens on the HALLOWEEN tab
Events.watch("halloween", function(on)
	if on then rewardsTab = "halloween" elseif rewardsTab == "halloween" then rewardsTab = "playtime" end
	renderRewards()
end)
-- keep the event countdown ticking while the menu is open
task.spawn(function()
	while true do
		task.wait(1)
		if rewardsModal.Visible and rewardsTab == "halloween" then
			statBig.Text = "🎃 HALLOWEEN EVENT — ends in " .. fmtLeft(Events.secondsLeft("halloween"))
		end
	end
end)
local function openRewards()
	if state.inMatch then return end
	rewardsModal.Visible = true
	pop(rewardsModal:FindFirstChildWhichIsA("Frame"))
	renderRewards()
	task.spawn(function()
		local ok, s = pcall(function() return Remotes.ShopRequest:InvokeServer("inventory") end)
		if ok then applyShopState(s) end
	end)
end
-- redraw when stats / ownership change; a "reward ready" bubble floats over the stand
local rewardBubble
task.spawn(function()
	local stand = workspace:WaitForChild("ShowLobby"):WaitForChild("Activities"):WaitForChild("RewardsStand", 30)
	if not stand then return end
	-- "new reward" sign: sized in studs so it floats over the booth like a real sign, bobbing gently
	rewardBubble = make("BillboardGui", { Name = "RewardsReady", Adornee = stand:WaitForChild("Sign", 20), Size = UDim2.new(42, 0, 9.5, 0), StudsOffset = Vector3.new(0, 10, 0), StudsOffsetWorldSpace = Vector3.new(0, 0, -9), MaxDistance = 300, AlwaysOnTop = false, LightInfluence = 0, Enabled = false, Parent = gui.Parent })
	local card = make("Frame", { Size = UDim2.fromScale(1, 0.72), BackgroundColor3 = C.Good, Parent = rewardBubble }, { corner(24), stroke(C.White, 4) })
	make("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(90, 235, 140), Color3.fromRGB(40, 190, 255)), Rotation = 90, Parent = card })
	local txt = make("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(0.94, 0, 0.8, 0), Position = UDim2.fromScale(0.03, 0.1), Font = UI.FontBlack, TextScaled = true, TextColor3 = C.Ink, Text = "", Parent = card })
	local arrow = make("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0.3), Position = UDim2.fromScale(0, 0.7), Font = UI.FontBlack, TextScaled = true, TextColor3 = C.Gold, TextStrokeTransparency = 0, Text = "▼", Parent = rewardBubble })
	RunService.RenderStepped:Connect(function()
		if rewardBubble.Enabled and not Settings.reducedMotion then
			local t = os.clock()
			rewardBubble.StudsOffset = Vector3.new(0, 10 + math.sin(t * 2.4) * 1.3, 0)
			arrow.Position = UDim2.fromScale(0, 0.7 + math.abs(math.sin(t * 4)) * 0.06)
		end
	end)
	while true do
		local n = claimableCount()
		if not rewardBubble.Adornee then rewardBubble.Adornee = stand:FindFirstChild("Sign") end
		rewardBubble.Enabled = n > 0 and not state.inMatch
		txt.Text = n == 1 and "🎁 You have a new reward!" or ("🎁 You have " .. n .. " new rewards!")
		task.wait(0.25)
	end
end)
-- the Rewards booth comes alive: spinning stars + prize carousel, bobbing gifts and balloons, chasing bulbs
task.spawn(function()
	local stand = workspace:WaitForChild("ShowLobby"):WaitForChild("Activities"):WaitForChild("RewardsStand", 30)
	if not stand then return end
	-- The prize host behind the counter: a gentle idle, a wave hello when you come close,
	-- and a little speech bubble
	task.spawn(function()
		local penny = stand:WaitForChild("Attendant", 20)
		local hum = penny and penny:FindFirstChildOfClass("Humanoid")
		local head = penny and penny:FindFirstChild("Head")
		if not (hum and head) then return end
		local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
		local function anim(id) local a = Instance.new("Animation"); a.AnimationId = "rbxassetid://" .. id; return animator:LoadAnimation(a) end
		local ok1, idle = pcall(anim, 507766388) -- Roblox's standard idle
		local ok2, wave = pcall(anim, 507770239)
		if ok1 then idle.Looped = true; idle.Priority = Enum.AnimationPriority.Idle; idle:Play() end
		if ok2 then wave.Priority = Enum.AnimationPriority.Action end
		local bubble = make("BillboardGui", { Name = "PennySays", Adornee = head, Size = UDim2.new(11, 0, 2.6, 0), StudsOffset = Vector3.new(0, 6.6, 0), MaxDistance = 60, LightInfluence = 0, Enabled = false, Parent = gui.Parent })
		local card = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.White, Parent = bubble }, { corner(18), stroke(C.Outline, 3) })
		local says = make("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(0.92, 0, 0.8, 0), Position = UDim2.fromScale(0.04, 0.1), Font = UI.FontBlack, TextScaled = true, TextColor3 = C.Ink, Text = "", Parent = card })
		local lines = { "Welcome, welcome! 👋", "Free prizes for playing! 🎁", "Step right up and claim your rewards! ✨", "You're doing amazing! 🌟" }
		local lastWave, lineIndex = 0, 0
		while penny.Parent do
			local char = player.Character
			local r = char and char:FindFirstChild("HumanoidRootPart")
			local near = r and not state.inMatch and (r.Position - head.Position).Magnitude < 42
			if near and os.clock() - lastWave > 8 then
				lastWave = os.clock()
				if ok2 and Settings.effects then wave:Play(0.2) end
				lineIndex = lineIndex % #lines + 1
				says.Text = lines[lineIndex]
				bubble.Enabled = true
				task.delay(4, function() bubble.Enabled = false end)
			end
			if not near then bubble.Enabled = false end
			task.wait(0.5)
		end
	end)
	local movers, bulbs = {}, {}
	for _, d in ipairs(stand:GetDescendants()) do
		if d:IsA("Model") and (d:GetAttribute("Spin") or d:GetAttribute("Bob")) then
			table.insert(movers, { model = d, home = d:GetPivot(), spin = d:GetAttribute("Spin") or 0, bob = d:GetAttribute("Bob") or 0, speed = d:GetAttribute("BobSpeed") or 1.5, phase = d:GetAttribute("BobPhase") or 0 })
		elseif d:IsA("BasePart") and d:GetAttribute("BoothChase") then
			table.insert(bulbs, { part = d, i = d:GetAttribute("BoothChase") })
		end
	end
	local warm, hot = Color3.fromRGB(255, 240, 180), Color3.fromRGB(80, 230, 255)
	local spookyWarm, spookyHot = Color3.fromRGB(255, 130, 25), Color3.fromRGB(120, 255, 90) -- Halloween event
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		if state.inMatch or not Settings.effects then return end
		local t = os.clock()
		if not Settings.reducedMotion then
			for _, m in ipairs(movers) do
				m.model:PivotTo(m.home * CFrame.new(0, math.sin(t * m.speed + m.phase) * m.bob, 0) * CFrame.Angles(0, t * m.spin, 0))
			end
		end
		acc += dt
		if acc >= 1 / 10 then
			acc = 0
			local step = math.floor(t * 10)
			local spooky = Events.isActive("halloween")
			local w, h = spooky and spookyWarm or warm, spooky and spookyHot or hot
			for _, b in ipairs(bulbs) do b.part.Color = ((b.i + step) % 3 == 0) and h or w end
		end
	end)
end)
player:GetAttributeChangedSignal("Playtime"):Connect(function() renderRewards() end)
player:GetAttributeChangedSignal("HalloweenPlaytime"):Connect(function() renderRewards() end)
player:GetAttributeChangedSignal("TotalScore"):Connect(function() renderRewards() end)
table.insert(shopListeners, function() renderRewards() end)

Remotes.LobbyReply.OnClientEvent:Connect(function(msg)
 if msg.type=="OpenRewards" and not state.inMatch then openRewards() end
 if msg.type=="OpenShop" and not state.inMatch then openShop() end
 if msg.type=="OpenSettings" and not state.inMatch then settingsModal.Visible=true end
 if msg.type=="Wheel" then showWheelResult(msg) end
end)
end
end)()

Remotes.MatchState.OnClientEvent:Connect(function(msg)
	if typeof(msg) ~= "table" then return end
	local h = handlers[msg.type]
	if h then task.spawn(h, msg) end
end)

Remotes.QueueRequest:FireServer(nil) -- ask for current status
-- lobby lighting watchdog: if anything left the lobby dim (a show's tint, a missed reset), fix it
task.spawn(function()
 while true do
  task.wait(1)
  if not state.inMatch then
   local off = false
   for k, v in pairs(LOBBY_LIGHT) do
    local cur = Lighting[k]
    if typeof(v) == "Color3" then
     if math.abs(cur.R - v.R) + math.abs(cur.G - v.G) + math.abs(cur.B - v.B) > 0.01 then off = true end
    elseif typeof(v) == "boolean" then
     if cur ~= v then off = true end
    elseif math.abs(cur - v) > 0.01 then off = true end
   end
   local wantHalloween = Events.isActive("halloween")
   if wantHalloween ~= (LOBBY_LIGHT == HALLOWEEN_LOBBY_LIGHT) or wantHalloween ~= (Lighting:FindFirstChild("HalloweenLobbyTint") ~= nil) then off = true end
   if off or Lighting:FindFirstChild("ClamillionAmbience") or Lighting:FindFirstChild("ClamillionUnderwater") then lobbyLighting(true) end
  end
 end
end)

-- AFK guard: after a minute without touching the controls the server stops counting you
-- for any pad, so nobody gets pulled into a show while they're away. Any input brings you back.
do
 local UserInputService=game:GetService("UserInputService")
 local AFK_SECONDS=60
 local lastInput=os.clock()
 local isIdle=false
 local function activity()
  lastInput=os.clock()
  if isIdle then isIdle=false;Remotes.QueueRequest:FireServer("active") end
 end
 UserInputService.InputBegan:Connect(activity)
 UserInputService.TouchStarted:Connect(activity)
 UserInputService.InputChanged:Connect(function(input)
  if input.UserInputType==Enum.UserInputType.Gamepad1 and input.Position.Magnitude>0.2 then activity() end
 end)
 task.spawn(function()
  while true do
   task.wait(2)
   if not isIdle and not state.inMatch and os.clock()-lastInput>AFK_SECONDS then
    isIdle=true;Remotes.QueueRequest:FireServer("idle")
   end
  end
 end)
end


-- Local light sweeps: bounded update rate, no replicated per-frame traffic or flashing.
local sweeps={}
local function collectSweeps(container)
 for _,p in ipairs(container:GetDescendants()) do
  if p:IsA("BasePart") and p:GetAttribute("SweepPhase") then
   sweeps[p]={base=p.Position,phase=p:GetAttribute("SweepPhase")}
  end
 end
end
task.spawn(function() collectSweeps(workspace:WaitForChild("ShowLobby")) end)
local sweepClock=0
RunService.RenderStepped:Connect(function(dt)
 sweepClock+=dt;if sweepClock<1/20 then return end;sweepClock=0
 local t=os.clock()
 for p,data in pairs(sweeps) do
  if not p.Parent then sweeps[p]=nil
  elseif not Settings.reducedMotion and Settings.effects then
   p.Position=data.base+Vector3.new(math.sin(t*.32+data.phase)*22,0,math.cos(t*.23+data.phase)*12)
  else p.Position=data.base end
 end
end)
workspace.ChildAdded:Connect(function(child)
 if child:IsA("Model") and child.Name:sub(1,6)=="Match_" then task.defer(collectSweeps,child) end
end)
