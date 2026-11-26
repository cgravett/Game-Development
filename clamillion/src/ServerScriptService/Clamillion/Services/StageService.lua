-- Everything the server shows on the physical set: podiums, the big screen, the host,
-- and contestant placement. Only public, already-revealed information is written here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UI = require(ReplicatedStorage.Clamillion.Shared.UIConstants)
local PodiumThemes = require(ReplicatedStorage.Clamillion.Shared.PodiumThemes)

local Factory = {}
local slots = {}
function Factory.new(arena)
local StageService = {}
local studio, podiums, screen, hostModel, hostCaption
local botModels = {}

local IDLE_TEXT = "Hop on a SOLO, 1V1 or 1V1V1 pad in the lobby!"

local function display(seat)
	return podiums["Podium" .. seat].Body.Display.BG
end

function StageService.init()
	studio = arena or workspace:WaitForChild("ClamillionStudio")
	podiums = studio:WaitForChild("Podiums")
	screen = studio.QuestionScreen.Screen.SurfaceGui.BG
	StageService.resetStage()
	task.spawn(StageService.spawnHost)
end

function StageService.lobbyCFrame()
	local spawn = workspace.ShowLobby.LobbySpawn
	local pos = spawn.Position + Vector3.new(math.random(-5, 5), 3.5, math.random(-5, 5))
	-- everyone arrives facing the Prize Palace (rewards booth) at the far end of the hall
	local booth = workspace.ShowLobby:FindFirstChild("RewardsStand", true)
	local target = booth and booth:GetPivot().Position or (pos + Vector3.new(0, 0, 100))
	return CFrame.lookAt(pos, Vector3.new(target.X, pos.Y, target.Z))
end

-- Podiums ---------------------------------------------------------------
function StageService.setName(seat, name)
	display(seat).PlayerName.Text = name
end

function StageService.setScore(seat, score)
	display(seat).Score.Text = UI.formatNumber(score)
end

function StageService.setStatus(seat, key)
	display(seat).Status.Text = UI.Status[key] or ""
end

-- shop cosmetics: a contestant's equipped podium theme and title
function StageService.applyPodium(seat, themeId)
	local podium = podiums:FindFirstChild("Podium" .. seat)
	if podium and themeId then PodiumThemes.apply(podium, themeId) end
end

function StageService.setTitle(seat, text, anim)
	local tag = display(seat):FindFirstChild("TitleTag")
	if not tag then return end
	tag.Text = text or ""
	local CS = game:GetService("CollectionService")
	if anim then
		tag:SetAttribute("Anim", anim); CS:AddTag(tag, "AnimatedTitle")
	else
		tag:SetAttribute("Anim", nil); CS:RemoveTag(tag, "AnimatedTitle")
	end
end

function StageService.resetStage()
	for seat = 1, 3 do
		StageService.setTitle(seat, nil)
		StageService.setName(seat, "Open Seat")
		StageService.setScore(seat, 0)
		StageService.setStatus(seat, "Waiting")
	end
	StageService.showMessage("CLAMILLION", "", IDLE_TEXT)
	StageService.setTimer(nil)
end

-- Big screen --------------------------------------------------------------
function StageService.showMessage(header, category, body)
	screen.Header.Text = header or ""
	screen.Category.Text = category or ""
	screen.Prompt.Text = body or ""
end

function StageService.showQuestion(label, category, prompt)
	StageService.showMessage(label, string.upper(category), prompt)
end

function StageService.setTimer(seconds)
	screen.Timer.Text = seconds and tostring(seconds) or ""
	screen.Timer.TextColor3 = (seconds and seconds <= 5) and UI.Colors.Danger or UI.Colors.Gold
end

-- Contestant placement -----------------------------------------------------
local function standCFrame(seat)
	return podiums["Podium" .. seat].StandPoint.CFrame
end

function StageService.placePlayer(player, seat)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and root) then return end
	hum.WalkSpeed = 0
	hum.UseJumpPower = false
	hum.JumpHeight = 0
	char:PivotTo(standCFrame(seat))
	root.Anchored = true
	-- on stage the title lives on the podium, so tuck the overhead one away
	player:SetAttribute("OnStage", true)
	local head = char:FindFirstChild("Head")
	local overhead = head and head:FindFirstChild("DailyTitle")
	if overhead then overhead.Enabled = false end
end

function StageService.releasePlayer(player)
	player:SetAttribute("OnStage", nil)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	local overhead = head and head:FindFirstChild("DailyTitle")
	if overhead then overhead.Enabled = true end -- back in the lobby: title above the head again
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and root) then return end
	root.Anchored = false
	hum.WalkSpeed = 22
	hum.JumpHeight = 7.2
	char:PivotTo(StageService.lobbyCFrame())
end

local function makeRig(desc, name)
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok then
		warn("[Clamillion] Could not create rig: " .. tostring(model))
		return nil
	end
	model.Name = name
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then hum.DisplayName = name end
	return model
end

function StageService.spawnBot(seat, name)
	local desc = Instance.new("HumanoidDescription")
	local palette = { Color3.fromRGB(240, 200, 160), Color3.fromRGB(198, 140, 100), Color3.fromRGB(130, 90, 60), Color3.fromRGB(255, 220, 190) }
	local skin = palette[math.random(#palette)]
	desc.HeadColor = skin; desc.LeftArmColor = skin; desc.RightArmColor = skin
	desc.TorsoColor = UI.Seats[seat].color
	desc.LeftLegColor = Color3.fromRGB(40, 44, 60); desc.RightLegColor = Color3.fromRGB(40, 44, 60)
	local model = makeRig(desc, name)
	if not model then return end
	model.Parent = studio
	model:PivotTo(standCFrame(seat))
	model.HumanoidRootPart.Anchored = true
	botModels[seat] = model
end

function StageService.clearBots()
	for seat, model in pairs(botModels) do
		model:Destroy()
		botModels[seat] = nil
	end
end

-- Host -------------------------------------------------------------------
local function weld(a, b)
	local w = Instance.new("WeldConstraint"); w.Part0 = a; w.Part1 = b; w.Parent = a
end

function StageService.spawnHost()
	if hostModel then return end
	-- the hostess: sparkling silver one-shoulder gown, glossy blonde waves, gold earrings
	local desc = Instance.new("HumanoidDescription")
	local skin = Color3.fromRGB(236, 190, 156)
	desc.Head = 10725626210; desc.MoodAnimation = 10725638029 -- Roblox "Woman" face
	desc.Torso = 86499666; desc.RightArm = 86499698; desc.LeftArm = 86499716; desc.LeftLeg = 86499753; desc.RightLeg = 86499793
	desc.HeadColor = skin; desc.TorsoColor = skin; desc.LeftArmColor = skin; desc.RightArmColor = skin; desc.LeftLegColor = skin; desc.RightLegColor = skin
	pcall(function() desc:SetAccessories({
		{ AssetId = 7193445686, AccessoryType = Enum.AccessoryType.Hair, IsLayered = false },
		{ AssetId = 9425088568, AccessoryType = Enum.AccessoryType.DressSkirt, IsLayered = true, Order = 3 },
	}, true) end)
	local model = makeRig(desc, "Host")
	if not model then return end
	model.Parent = studio
	model:PivotTo(studio.HostMark.CFrame)
	model.HumanoidRootPart.Anchored = true
	local hum = model:FindFirstChildOfClass("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	local torso = model:FindFirstChild("UpperTorso")
	local head = model:FindFirstChild("Head")
	local hand = model:FindFirstChild("RightHand")
	local function deco(size, color, cf, material, shape)
		local p = Instance.new("Part")
		p.Size = size; p.Color = color; p.Material = material or Enum.Material.SmoothPlastic
		p.CanCollide = false; p.Massless = true; p.CastShadow = false
		if shape then p.Shape = shape end
		p.CFrame = cf; p.Parent = model
		return p
	end
	local gold = Color3.fromRGB(255, 205, 60)
	if head then
		-- gold drop earrings
		for _, s in ipairs({ -1, 1 }) do
			weld(head, deco(Vector3.new(0.22, 0.22, 0.22), gold, head.CFrame * CFrame.new(s * 0.62, -0.32, 0), Enum.Material.Neon, Enum.PartType.Ball))
		end
	end
	if torso then
		-- a little sparkle twinkling off the gown
		local sp = Instance.new("ParticleEmitter")
		sp.Name = "GownSparkle"; sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"; sp.Rate = 4
		sp.Lifetime = NumberRange.new(0.4, 0.8); sp.Speed = NumberRange.new(0.2, 0.6); sp.SpreadAngle = Vector2.new(180, 180)
		sp.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.35), NumberSequenceKeypoint.new(1, 0) })
		sp.LightEmission = 1; sp.Color = ColorSequence.new(Color3.fromRGB(255, 250, 230)); sp.Parent = torso
	end
	-- raise the mic arm a little
	local upperArm = model:FindFirstChild("RightUpperArm")
	local shoulder = upperArm and upperArm:FindFirstChild("RightShoulder")
	if shoulder then
  if shoulder:IsA("Motor6D") then shoulder.C0*=CFrame.Angles(math.rad(65),0,0)
  elseif shoulder:IsA("AnimationConstraint") and shoulder.Attachment0 then shoulder.Attachment0.CFrame*=CFrame.Angles(math.rad(65),0,0) end
 end
	task.wait()
	if hand then
		local handle = deco(Vector3.new(0.25, 1.1, 0.25), Color3.fromRGB(30, 30, 30), hand.CFrame * CFrame.new(0, 0.4, -0.1) * CFrame.Angles(math.rad(-25), 0, 0), Enum.Material.Metal)
		local grille = deco(Vector3.new(0.5, 0.5, 0.5), Color3.fromRGB(170, 170, 180), handle.CFrame * CFrame.new(0, 0.75, 0), Enum.Material.Metal, Enum.PartType.Ball)
		weld(hand, handle); weld(handle, grille)
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = "Caption"; bb.Size = UDim2.fromOffset(320, 90); bb.StudsOffset = Vector3.new(0, 4.2, 0)
	bb.MaxDistance = 120; bb.AlwaysOnTop = false; bb.Adornee = head; bb.Parent = model
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1); t.BackgroundColor3 = UI.Colors.PanelDark; t.BackgroundTransparency = 0.15
	t.TextColor3 = UI.Colors.White; t.Font = UI.Font; t.TextScaled = true; t.TextWrapped = true; t.Text = ""; t.Visible = false
	t.Parent = bb
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = t
	local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0, 10); p.PaddingRight = UDim.new(0, 10); p.PaddingTop = UDim.new(0, 6); p.PaddingBottom = UDim.new(0, 6); p.Parent = t
	hostCaption = t
	hostModel = model
end

local captionToken = 0
function StageService.hostSay(text, seconds)
	if not hostCaption then return end
	captionToken += 1
	local token = captionToken
	hostCaption.Text = text
	hostCaption.Visible = true
	task.delay(seconds or 5, function()
		if token == captionToken then hostCaption.Visible = false end
	end)
end

function StageService.prepare(count)
 local active = count == 1 and {2} or (count == 2 and {1,3} or {1,2,3})
 for seat=1,3 do
  local used = table.find(active,seat) ~= nil
  local model=podiums["Podium"..seat]
  for _,obj in model:GetDescendants() do
   if obj:IsA("BasePart") and obj.Name ~= "StandPoint" then obj.Transparency=used and 0 or 1 end
   if obj:IsA("SurfaceGui") or obj:IsA("Light") then obj.Enabled=used end
  end
 end
 return active
end
function StageService.welcome()
 if not hostModel then return end
 local arm=hostModel:FindFirstChild("LeftUpperArm")
 local joint=arm and arm:FindFirstChild("LeftShoulder")
 if not joint then return end
 local target=joint:IsA("Motor6D") and joint or joint.Attachment0
 if not target then return end
 local property=joint:IsA("Motor6D") and "C0" or "CFrame"
 local base=target[property]
 task.spawn(function()
  local ts=game:GetService("TweenService")
  for i=1,2 do
   local t=ts:Create(target,TweenInfo.new(0.6),{[property]=base*CFrame.Angles(0,0,math.rad(-65))})
   t:Play(); t.Completed:Wait()
   local back=ts:Create(target,TweenInfo.new(0.6),{[property]=base}); back:Play(); back.Completed:Wait()
  end
 end)
end
function StageService.destroy()
 if arena then slots[arena:GetAttribute("ArenaSlot")]=nil; arena:Destroy() end
end
return StageService
end
function Factory.create(id, arenaTheme)
 local slot=1 while slots[slot] do slot+=1 end
 slots[slot]=true
 -- themed arenas (from the shop) live in ServerStorage.ClamillionArenas; default is the classic studio
 local themed=arenaTheme and game:GetService("ServerStorage"):FindFirstChild("ClamillionArenas")
 local source=themed and themed:FindFirstChild(arenaTheme) or workspace.ClamillionStudio
 local arena=source:Clone()
 arena.Name="Match_"..id
 arena:SetAttribute("ArenaSlot",slot)
 arena:SetAttribute("Theme",source~=workspace.ClamillionStudio and arenaTheme or "Classic")
 arena:PivotTo(workspace.ClamillionStudio:GetPivot())
 arena.ModelStreamingMode=Enum.ModelStreamingMode.Persistent
 local oldHost=arena:FindFirstChild("Host") if oldHost then oldHost:Destroy() end
 -- Fans are built and animated locally by each contestant's client (CrowdBuilder),
 -- so the clone ships with empty seats and nothing extra to replicate.
 local crowd=arena:FindFirstChild("Crowd") if crowd then crowd:ClearAllChildren() end
 for _,v in arena:GetDescendants() do
  if v:IsA("SpawnLocation") then v.Enabled=false end
 end
 arena:PivotTo(arena:GetPivot()+Vector3.new(slot*400,0,0))
 arena.Parent=workspace
 local stage=Factory.new(arena)
 stage.init()
 return stage,arena
end
local lobbyStage=Factory.new()
function Factory.init()
 -- The template's preview crowd is only for editing in Studio; clients build their own.
 local crowd=workspace.ClamillionStudio:FindFirstChild("Crowd")
 if crowd then crowd:ClearAllChildren() end
 lobbyStage.init()
end
function Factory.releasePlayer(p) lobbyStage.releasePlayer(p) end
return Factory

