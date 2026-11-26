--!strict
-- Client entry. Samples input on a fixed step, predicts the local skater, draws everything
-- else from buffered server snapshots, and never decides a goal, score, purchase or reward.
-- Modes: Menu (locker-room lobby), Match (server 3v3), Training (practice and drills), Pond
-- (the shared open world on the lake, run by the server).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("GameConfig"))
local Protocol = require(Shared:WaitForChild("Protocol"))
local Sim = require(Shared:WaitForChild("Sim"))
local ArenaBuilder = require(Shared:WaitForChild("ArenaBuilder"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Looks = require(Shared:WaitForChild("Looks"))
local SettingsDef = require(Shared:WaitForChild("Settings"))

local Client = script.Parent:WaitForChild("Client")
local CameraRig = require(Client:WaitForChild("CameraRig"))
local Controls = require(Client:WaitForChild("Controls"))
local Fx = require(Client:WaitForChild("Fx"))
local Hud = require(Client:WaitForChild("Hud"))
local Menu = require(Client:WaitForChild("Menu"))
local Prefs = require(Client:WaitForChild("Prefs"))
local Prediction = require(Client:WaitForChild("Prediction"))
local Results = require(Client:WaitForChild("Results"))
local SkaterView = require(Client:WaitForChild("SkaterView"))
local Training = require(Client:WaitForChild("Training"))
local Xray = require(Client:WaitForChild("Xray"))
local GameMenu = require(Client:WaitForChild("GameMenu"))
local DailyRewards = require(Client:WaitForChild("DailyRewards"))
local Pond = require(Client:WaitForChild("Pond"))
local Replay = require(Client:WaitForChild("Replay"))
local InputHints = require(Client:WaitForChild("InputHints"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local TICK = Config.Tick
local SEND_EVERY = math.max(1, math.round(1 / (TICK * Config.InputSendRate)))
local RING_SIZE = 16
local STALE_SECONDS = 2
local MAX_STEPS_PER_FRAME = 5

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local InputRemote: any = Remotes:WaitForChild(Protocol.Remotes.Input)
local SnapshotRemote: any = Remotes:WaitForChild(Protocol.Remotes.Snapshot)
local CueRemote: any = Remotes:WaitForChild(Protocol.Remotes.Cue)
local StateRemote: any = Remotes:WaitForChild(Protocol.Remotes.State)
local GoalRemote: any = Remotes:WaitForChild(Protocol.Remotes.Goal)
local ActionRemote: any = Remotes:WaitForChild(Protocol.Remotes.Action)
local ProfileRemote: any = Remotes:WaitForChild(Protocol.Remotes.Profile)
local ShopRemote: any = Remotes:WaitForChild(Protocol.Remotes.Shop)
local RewardRemote: any = Remotes:WaitForChild(Protocol.Remotes.Reward)
local NoticeRemote: any = Remotes:WaitForChild(Protocol.Remotes.Notice)
local RankingsRemote: any = Remotes:WaitForChild(Protocol.Remotes.Rankings)
local PondSnapshotRemote: any = Remotes:WaitForChild(Protocol.Remotes.PondSnapshot)
local PondCueRemote: any = Remotes:WaitForChild(Protocol.Remotes.PondCue)
local PondEventRemote: any = Remotes:WaitForChild(Protocol.Remotes.PondEvent)
local IdleRemote: any = Remotes:WaitForChild(Protocol.Remotes.Idle)

local mode = "Menu" -- "Menu", "Match", "Training" or "Pond"
local matchState: any = nil
local mySlot: number? = nil
local screenForward = 1
-- E / RB flips the camera to look the other way down the rink (1 or -1). Movement keys and
-- the minimap follow the view, so W always skates up the screen.
local cameraFlip = 1
local lowGraphics = false
local nameTags = true
local debugOn = false
local lastPhaseId = -1
local lastMatchId = -1
local clockValue = Config.Match.LengthSeconds
local clockReceivedAt = 0
local lastSnapshotClock = os.clock()
local profile: any = nil
local scoreboardHeld = false
local lobbyPanelOpen = false
local lobbyStatsOpen = false -- Build 36: CAREER STATS is open (the camera zooms in on the skater)
-- Remotes can fire before the screens exist; until then only the data is kept.
local uiReady = false
-- First-time players go straight into the tutorial (set once the screens exist, below).
local startTutorialIfNew: (() -> ())? = nil
local lastUiInput = 0 -- os.clock() of the last key, button, touch or mouse move
local showTutorialReward: (any) -> ()
local refreshTouchExtras: () -> ()
local enterMatchRef: () -> ()
local enterMenuRef: () -> ()
local enterPondRef: () -> ()

for _, kind in { Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.EmotesMenu } do
	pcall(function()
		StarterGui:SetCoreGuiEnabled(kind, false)
	end)
end

---------------------------------------------------------------------------------------------
-- Scene: the lobby plus one rink at a time (rinks are cached once built).
---------------------------------------------------------------------------------------------

local lobby = ArenaBuilder.buildLobby()
lobby.model.Parent = workspace
-- Light the lobby the moment it exists. Waiting until the rink below has finished building
-- showed the room under the place's default lighting first, then a sudden jump in brightness.
ArenaBuilder.applyLighting(Lighting, "Lobby")
local lobbyRig = Looks.build(workspace, Catalog.DefaultLook, 0)
local lobbyLookKey = ""
local function lookKey(look: any): string
	-- Every slot, so equipping an outfit, skin, body or back bling redraws the lobby skater too.
	local key = `{look.skin}|{look.hairColor}`
	for _, kind in Catalog.Kinds do
		key ..= "|" .. tostring(look[kind])
	end
	return key
end
local function setLobbyLook(look: any)
	local clean = Catalog.sanitizeLook(look)
	local key = lookKey(clean)
	if key == lobbyLookKey then
		return
	end
	lobbyLookKey = key
	lobbyRig.model:Destroy()
	lobbyRig = Looks.build(workspace, clean, 0)
	lobbyRig.model.Name = "LobbySkater"
	-- Straight onto the lobby mat: a rig is built at the world origin, which is centre ice, and
	-- the menu loop only poses it in the menu (Build 29: a look change in practice, like the
	-- tutorial's prize stick, left a half-drawn skater standing on the ice).
	Looks.pose(lobbyRig, lobby.stand)
end
setLobbyLook(Catalog.DefaultLook)

-- Click (or touch) and hold on the lobby skater and swipe to turn it round, to see an item from
-- every side. It stays where you leave it until you swipe again.
local lobbyYaw = 0
local lobbyDragX: number? = nil
local function lobbySkaterUnder(screen: Vector2): boolean
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	-- The rig's parts don't take queries (no raycasts), so test the ray against their boxes.
	for _, p in lobbyRig.model:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local rel = p.CFrame:PointToObjectSpace(ray.Origin)
			local dir = p.CFrame:VectorToObjectSpace(ray.Direction)
			local half = p.Size / 2 + Vector3.new(0.4, 0.4, 0.4)
			local t0, t1 = 0, math.huge
			local hit = true
			for _, axis in { "X", "Y", "Z" } do
				local o, d, h = (rel :: any)[axis], (dir :: any)[axis], (half :: any)[axis]
				if math.abs(d) < 1e-6 then
					if math.abs(o) > h then
						hit = false
						break
					end
				else
					local a, b = (-h - o) / d, (h - o) / d
					t0, t1 = math.max(t0, math.min(a, b)), math.min(t1, math.max(a, b))
					if t0 > t1 then
						hit = false
						break
					end
				end
			end
			if hit then
				return true
			end
		end
	end
	return false
end
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or mode ~= "Menu" then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		local at = Vector2.new(input.Position.X, input.Position.Y)
		if lobbySkaterUnder(at) then
			lobbyDragX = at.X
		end
	end
end)
UserInputService.InputChanged:Connect(function(input: InputObject)
	local from = lobbyDragX
	if from and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		lobbyYaw += (input.Position.X - from) * 0.012
		lobbyDragX = input.Position.X
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		lobbyDragX = nil
	end
end)

local rinks: { [string]: ArenaBuilder.Built } = {}
local building: { [string]: boolean } = {}
local shownTheme = ""
local wantedTheme = "Arena"
local penguins: { ArenaBuilder.Penguin } = {}

local function showRink(themeName: string)
	wantedTheme = themeName
	-- A white puck on dark (black) ice, the black one everywhere else.
	Fx.setIceColor(ArenaBuilder.theme(themeName).ice)
	local built = rinks[themeName]
	if not built then
		if not building[themeName] then
			building[themeName] = true
			task.spawn(function()
				local ok, result = pcall(ArenaBuilder.build, themeName, lowGraphics)
				building[themeName] = nil
				if not ok then
					warn("[PuckPals] rink build failed:", themeName, result)
					return
				end
				rinks[themeName] = result
				if wantedTheme == themeName then
					showRink(themeName)
				end
			end)
		end
		return
	end
	if shownTheme == themeName and built.model.Parent == workspace then
		return
	end
	for name, other in rinks do
		other.model.Parent = if name == themeName then workspace else nil
	end
	shownTheme = themeName
	Fx.setRink(themeName, built.model) -- Build 37: which goal celebration plays
	Fx.setFans(built.fans)
	Fx.setBottles(built.bottles)
	penguins = built.penguins
end

-- Video settings sit on top of whichever lighting recipe is showing.
local function applyVideo()
	Lighting.GlobalShadows = Prefs.get("shadows") ~= false
	local bloom = Lighting:FindFirstChild("Bloom")
	if bloom then
		(bloom :: BloomEffect).Enabled = Prefs.get("bloom") ~= false
	end
	local grade = Lighting:FindFirstChild("Grade")
	if grade then
		(grade :: ColorCorrectionEffect).Enabled = Prefs.get("grade") ~= false
	end
end

local function applyArenaLighting(theme: string)
	ArenaBuilder.applyLighting(Lighting, theme)
	applyVideo()
	Fx.setAmbience(theme)
end

-- Settings, Arenas: show matches in the player's chosen arena (looks only; every rink plays
-- the same).
local function matchArena(map: string): string
	-- An equipped rink (season pass) beats the Settings pick.
	local rinkItem = profile and profile.look and Catalog.ById[profile.look.rink]
	local rinkStyle = rinkItem and rinkItem.style
	if rinkStyle and ArenaBuilder.Themes[rinkStyle] then
		return rinkStyle
	end
	local pick = SettingsDef.Arenas[Prefs.get("arena") or 1]
	if pick and pick ~= SettingsDef.Arenas[1] then
		return pick
	end
	return map
end

local function rebuildRinks()
	for _, built in rinks do
		built.model:Destroy()
	end
	table.clear(rinks)
	shownTheme = ""
	showRink(wantedTheme)
end

local activeSkaters = Instance.new("Folder")
activeSkaters.Name = "ActiveSkaters"
activeSkaters.Parent = workspace

Fx.init(workspace)
-- Build 37: the build number is no longer on screen; it shows in the F9 console instead.
print(`[PuckPals] client build {Config.Build}`)
Xray.init(workspace)
local occluders: { { x: number, z: number } } = {}
local views = table.create(Protocol.SLOTS)
local renderStates = table.create(Protocol.SLOTS)
for slot = 1, Protocol.SLOTS do
	views[slot] = SkaterView.new(activeSkaters, slot)
	renderStates[slot] = {
		x = 0, z = 0, vx = 0, vz = 0, yaw = 0, radius = 0.7,
		charging = false, active = false, charge = 0,
		stunned = false, sprinting = false, visible = false, lifted = false, lofting = false,
	}
end

-- Snapshot ring buffer: decoded into reused tables, newest at ringHead.
local ring = table.create(RING_SIZE)
for i = 1, RING_SIZE do
	ring[i] = Protocol.newSnapshot()
end
local ringHead = 0
local ringCount = 0
local newestTick = -1

local function teamOfSlot(slot: number): number
	return if slot <= 3 then 1 else 2
end

local function refreshIdentities()
	if mode == "Training" or not matchState then
		return
	end
	for slot = 1, Protocol.SLOTS do
		local entry = matchState.roster[slot]
		views[slot]:setIdentity(entry.name, teamOfSlot(slot), slot == mySlot, entry.look)
		-- Build 35: in a match everyone else wears a quiet name tag (Settings can turn them
		-- off); the pond's view of a match through the boards shows none.
		views[slot]:setTagQuiet(true)
		views[slot]:setTagVisible(mode == "Match" and nameTags and slot ~= mySlot)
	end
end

local function isPlayingPhase(phase: string): boolean
	return phase == "Live" or phase == "Overtime"
end

-- Skaters also move through the goal celebration and the few seconds after the final horn.
local function canSkate(phase: string): boolean
	return isPlayingPhase(phase) or phase == "GoalFrozen" or phase == "Buzzer"
end

-- End of the game: call out 30 and 10 seconds left, then count 3, 2, 1 under the score bug.
local function timeCallFor(state: any, clock: number): (string?, boolean?)
	if state.phase == "Buzzer" then
		return "FINAL HORN", true
	end
	if state.phase ~= "Live" or state.overtime then
		return nil, nil
	end
	if clock > 0 and clock <= 3 then
		return tostring(math.ceil(clock)), true
	elseif clock > 7 and clock <= 10 then
		return "10 SECONDS LEFT", true
	elseif clock > 26 and clock <= 30 then
		return "30 SECONDS LEFT", false
	end
	return nil, nil
end

-- The scorer the celebration spotlight follows.
local celebrateSlot: number? = nil

local function nameOf(slot: number?): string?
	if slot and matchState and matchState.roster[slot] then
		return matchState.roster[slot].name
	end
	return nil
end

local INK = Color3.fromRGB(30, 34, 48)

local function onPhaseChanged(state: any)
	local phase = state.phase
	-- On the pond, prediction belongs to your pond skater; someone else's match leaves it alone.
	if mode ~= "Pond" then
		Prediction.reset()
		Prediction.setPredicting(mySlot ~= nil and canSkate(phase))
	end
	if phase ~= "GoalFrozen" then
		Fx.endCelebration()
		celebrateSlot = nil
		-- The replay only lives inside the goal freeze; whatever comes next takes the screen back.
		Replay.stop()
	end
	if phase ~= "Final" then
		Results.hide()
		CameraRig.releaseFixed()
	end
	-- The post-game screen needs the mouse, to get back to the menu.
	Controls.holdCursor("results", mode == "Match" and phase == "Final")
	if mode ~= "Match" then
		return
	end
	if phase == "Countdown" then
		local team = if mySlot then teamOfSlot(mySlot) else nil
		Hud.banner(
			"GET READY",
			if team then `YOU'RE ON THE {string.upper(Config.Teams[team].Name)} TEAM` else "SPECTATING: THE ICE IS FULL",
			if team == 1 then Hud.AWAY elseif team == 2 then Hud.HOME else INK,
			Config.Match.CountdownSeconds
		)
	elseif phase == "Faceoff" then
		-- The referee whistles everyone in to the dot; the 3-2-1 count is drawn by the HUD while
		-- the puck hangs over it. The drink bottles are back on the nets.
		Fx.refereeWhistle()
		Fx.resetBottles()
		Hud.banner(if state.overtime then "OVERTIME" else "", if state.overtime then "NEXT GOAL WINS" else nil, INK, 1.4)
	elseif phase == "Buzzer" then
		Fx.finalHorn()
		Hud.banner("TIME!", nil, INK, 1.6)
	elseif phase == "Live" or phase == "Overtime" then
		Fx.whistle()
		Hud.banner("GO!", nil, Color3.fromRGB(46, 170, 80), 0.7)
	elseif phase == "Final" then
		local title = "DRAW!"
		local color = INK
		if state.winner ~= 0 then
			title = `{string.upper(Config.Teams[state.winner].Name)} TEAM WON!`
			color = if state.winner == 1 then Hud.AWAY else Hud.HOME
		end
		Hud.banner(title, nil, color, 2.5)
		Results.show(state, mySlot)
		Results.setProfile(profile)
	end
end

StateRemote.OnClientEvent:Connect(function(state: any)
	if matchState and state.matchId == matchState.matchId and state.revision < matchState.revision then
		return
	end
	matchState = state
	clockValue = state.clock
	clockReceivedAt = os.clock()

	local slot: number? = nil
	for i, entry in state.roster do
		if entry.userId == localPlayer.UserId then
			slot = i
		end
	end
	local slotChanged = slot ~= mySlot
	mySlot = slot
	if not uiReady then
		return
	end
	if mode == "Match" then
		-- Only a change of team re-aims the camera; the player's own E flip stays put through
		-- goals, faceoffs and clock updates.
		local forward = if slot and slot > 3 then -1 else 1
		if slotChanged or forward ~= screenForward then
			screenForward = forward
			cameraFlip = 1
		end
		local map = matchArena(state.map or "Arena")
		showRink(map)
		applyArenaLighting(map)
	end
	refreshIdentities()
	Hud.setScores(state.scores[1], state.scores[2])
	if state.phaseId ~= lastPhaseId or state.matchId ~= lastMatchId or slotChanged then
		lastPhaseId = state.phaseId
		lastMatchId = state.matchId
		onPhaseChanged(state)
	end
end)

-- The other skaters from the newest snapshot, in tables reused every snapshot.
local otherBodies: { any } = {}

SnapshotRemote.OnClientEvent:Connect(function(packet: any)
	if typeof(packet) ~= "buffer" then
		return
	end
	local nextHead = ringHead % RING_SIZE + 1
	if not Protocol.readSnapshot(packet, ring[nextHead]) then
		return
	end
	local snap = ring[nextHead]
	if snap.tick <= newestTick then
		return
	end
	newestTick = snap.tick
	ringHead = nextHead
	ringCount = math.min(ringCount + 1, RING_SIZE)
	lastSnapshotClock = os.clock()
	if mode == "Match" and mySlot then
		local n = 0
		for slot, other in snap.skaters do
			if slot ~= mySlot then
				n += 1
				local body = otherBodies[n]
				if not body then
					body = {}
					otherBodies[n] = body
				end
				body.slot = slot
				body.x, body.z = other.x, other.z
				body.vx, body.vz = other.vx, other.vz
				body.yaw = other.yaw
				body.lifted = other.lifted
			end
		end
		for i = n + 1, #otherBodies do
			otherBodies[i] = nil
		end
		Prediction.setOthers(otherBodies)
		Prediction.reconcile(snap.skaters[mySlot])
		Prediction.settleOthers()
		Prediction.reconcilePuck(snap.puckX, snap.puckY, snap.puckZ, snap.puckVx, snap.puckVy, snap.puckVz)
	end
end)

local CUE_NAMES = {}
for name, id in Protocol.CueKinds do
	CUE_NAMES[id] = name
end
CueRemote.OnClientEvent:Connect(function(kind: any, x: any, z: any, strength: any)
	local name = CUE_NAMES[kind]
	if name and mode == "Match" then
		Fx.cue(name, x, z, strength)
	end
end)

GoalRemote.OnClientEvent:Connect(function(goal: any)
	if mode ~= "Match" or type(goal) ~= "table" then
		return
	end
	if goal.kind == "SkipVote" then
		Replay.votes(tonumber(goal.votes) or 0, tonumber(goal.need) or 1, goal.skip == true)
		return
	end
	-- Lights down and a spotlight on the scorer; the third goal by one skater brings the caps.
	local scorerSlot: number? = if type(goal.scorer) == "number" and renderStates[goal.scorer] then goal.scorer else nil
	local goals = tonumber(goal.scorerGoals) or 0
	local hatTrick = scorerSlot ~= nil and goal.ownGoal ~= true and goals >= 3 and goals % 3 == 0
	celebrateSlot = scorerSlot
	local sx: number, sz: number = goal.x, goal.z
	if scorerSlot then
		sx, sz = renderStates[scorerSlot].x, renderStates[scorerSlot].z
	end
	-- The scorer's goal sound (an own goal gets the arena horn).
	local entry = scorerSlot and matchState and matchState.roster and matchState.roster[scorerSlot]
	local soundItem = entry and goal.ownGoal ~= true and entry.look and Catalog.ById[entry.look.goal]
	local sound = soundItem and soundItem.style
	-- The celebration has the first part of the goal freeze; the TV replay plays after it.
	Fx.goal(goal.goalId, if goal.team == 1 then 1 else -1, goal.x, goal.z, Replay.CELEBRATE, hatTrick, sx, sz, sound)
	local color = if goal.team == 1 then Hud.AWAY else Hud.HOME
	local scorer = nameOf(goal.scorer)
	local assist = nameOf(goal.assist)
	local title: string
	local sub: string? = nil
	if goal.ownGoal then
		title = if scorer then `OWN GOAL BY {string.upper(scorer)}!` else "OWN GOAL!"
	elseif scorer then
		title = `{string.upper(scorer)} SCORED!`
		sub = if assist then `ASSISTED BY {string.upper(assist)}` else nil
	else
		title = `{string.upper(Config.Teams[goal.team].Name)} TEAM SCORED!`
	end
	local speed = tonumber(goal.speed) or 0
	if hatTrick then
		sub = "HAT TRICK!"
	end
	local speedText = `SHOT SPEED: {math.round(speed * 10) / 10} KPH`
	Hud.banner(title, sub, color, Replay.CELEBRATE, speedText)
	Replay.goal({
		goalId = goal.goalId,
		skipNeed = tonumber(goal.skipNeed) or 1,
		x = goal.x,
		color = color,
		title = title,
		sub = if sub then `{sub}  ·  {speedText}` else speedText,
	})
end)

ProfileRemote.OnClientEvent:Connect(function(p: any)
	if type(p) ~= "table" then
		return
	end
	local oldRink = profile and profile.look and profile.look.rink
	profile = p
	Prefs.loadFromProfile(p.settings)
	-- Your puck, in every game you play.
	local puckItem = p.look and Catalog.ById[p.look.puck]
	Fx.setPuckStyle(puckItem and puckItem.style)
	-- A newly equipped rink shows straight away.
	if p.look and p.look.rink ~= oldRink and mode == "Match" and matchState then
		local map = matchArena(matchState.map or "Arena")
		showRink(map)
		applyArenaLighting(map)
	end
	if not uiReady then
		return
	end
	Menu.setProfile(p)
	Results.setProfile(p)
	DailyRewards.setState(p.login)
	if not dailyShown and mode == "Menu" and p.status == "ready" and DailyRewards.available() then
		dailyShown = true
		task.delay(1.2, function()
			if mode == "Menu" then
				DailyRewards.open()
			end
		end)
	end
	Training.setRewardClaimed(p.tutorialDone == true)
	local start = startTutorialIfNew
	if start then
		task.defer(start)
	end
	if mode == "Training" then
		views[1]:setIdentity(localPlayer.DisplayName, 1, true, p.look)
	end
end)

-- The tutorial prize: its own screen with the stick, the coins and what to do next.
function showTutorialReward(reward: any)
	local item = Catalog.ById[reward.item]
	local name = if item then item.name else "new"
	local coins = tonumber(reward.coins) or 0
	if mode ~= "Training" or not uiReady then
		Hud.toast(`You earned the {name} stick and {coins} coins!`, true)
		return
	end
	Controls.holdCursor("reward", true)
	Hud.showReward({
		itemName = name,
		coins = coins,
		preview = Menu.previewFor(reward.item),
		onPlay = function()
			Controls.holdCursor("reward", false)
			enterMatchRef()
		end,
		onPractice = function()
			Controls.holdCursor("reward", false)
		end,
		onMenu = function()
			Controls.holdCursor("reward", false)
			enterMenuRef()
		end,
	})
end

RewardRemote.OnClientEvent:Connect(function(reward: any)
	if type(reward) == "table" and reward.login == true then
		local coins, day = tonumber(reward.coins) or 0, tonumber(reward.day) or 0
		DailyRewards.claimed(reward.ok == true, coins, day)
		if reward.ok == true then
			Hud.toast(`+{coins} COINS: DAY {day} LOGIN REWARD!`, true, 3)
		elseif type(reward.reason) == "string" then
			Hud.toast(reward.reason, false)
		end
	elseif type(reward) == "table" and reward.tutorial == true then
		showTutorialReward(reward)
	elseif type(reward) == "table" and reward.box == true then
		-- Build 34: a Mystery Box was bought and saved: show what came out.
		Menu.boxReveal(if type(reward.item) == "string" then reward.item else nil, tonumber(reward.coins) or 0)
		Fx.goalSound("BoxPop", 1)
	elseif type(reward) == "table" and reward.coinPack == true then
		-- Build 35: a coin pack was bought and saved.
		Hud.toast(`+{tonumber(reward.coins) or 0} COINS! THANKS FOR YOUR SUPPORT!`, true, 3)
		Fx.goalSound("BoxPop", 1)
	elseif type(reward) == "table" and reward.challenge == true then
		Menu.challengeClaimed(reward.id, reward.ok == true, tonumber(reward.amount) or 0, if type(reward.unit) == "string" then reward.unit else "COINS")
	elseif type(reward) == "table" then
		Results.setReward(reward)
		if reward.leveled then
			Hud.toast("LEVEL UP!", true)
		end
		-- Build 40: a first whole match won the Nova set (already owned and worn); the reveal
		-- opens when the menu next shows.
		if type(reward.firstGame) == "table" and #reward.firstGame > 0 then
			local ids = {}
			for _, id in reward.firstGame do
				if type(id) == "string" and Catalog.ById[id] then
					table.insert(ids, id)
				end
			end
			if #ids > 0 then
				Hud.toast("NOVA SET UNLOCKED! IT'S IN YOUR LOCKER", true, 4)
				Menu.queueFirstGame(ids)
			end
		end
	end
end)

RankingsRemote.OnClientEvent:Connect(function(data: any)
	Menu.setRankings(data)
end)

NoticeRemote.OnClientEvent:Connect(function(text: any, ok: any, where: any)
	if type(text) == "string" and where == "corner" then
		Hud.cornerToast(text, 7)
	elseif type(text) == "string" then
		Hud.toast(text, ok == true)
	end
end)

-- Snapshot interpolation: render slightly in the past, between two known server states.
local function lerpAngle(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

-- The render clock: server time advanced by exactly each frame's dt, nudged gently toward
-- GetServerTimeNow. Reading the server clock straight each frame picks up its small
-- corrections and the wobble of when the frame runs, which shows as judder on every skater.
local renderClock = 0
local function advanceRenderClock(dt: number)
	local now = workspace:GetServerTimeNow()
	local drift = now - renderClock
	if math.abs(drift) > 0.25 then
		renderClock = now
	else
		renderClock += dt + drift * math.min(1, 2 * dt)
	end
end

-- Fills every render state from the snapshots, interpolated a moment in the past. While the
-- local player is predicting, the other skaters' positions and sticks are then replaced by
-- Prediction.renderOthers, which draws them at the predicted puck's time.
local function sampleSnapshots(): (number, number, number, number, number)
	if ringCount == 0 then
		return 0, 0.3, 0, 0, 0
	end
	local target = renderClock - Config.InterpDelay
	local newer = ring[ringHead]
	local older = newer
	for back = 1, ringCount - 1 do
		local index = (ringHead - back - 1) % RING_SIZE + 1
		local candidate = ring[index]
		older = candidate
		if candidate.time <= target then
			break
		end
		newer = candidate
	end
	local span = newer.time - older.time
	local t = if span > 1e-4 then math.clamp((target - older.time) / span, 0, 1) else 1

	for slot = 1, Protocol.SLOTS do
		local a, b = older.skaters[slot], newer.skaters[slot]
		local state = renderStates[slot]
		state.x = a.x + (b.x - a.x) * t
		state.z = a.z + (b.z - a.z) * t
		state.vx = a.vx + (b.vx - a.vx) * t
		state.vz = a.vz + (b.vz - a.vz) * t
		state.yaw = lerpAngle(a.yaw, b.yaw, t)
		state.radius = a.radius + (b.radius - a.radius) * t
		state.charging = b.charging
		state.active = b.active
		state.charge = b.charge
		state.stunned = b.stunned
		state.lifted = b.lifted
		state.lofting = b.lofting
		state.sprinting = b.sprinting
		state.visible = true
	end
	return older.puckX + (newer.puckX - older.puckX) * t,
		older.puckY + (newer.puckY - older.puckY) * t,
		older.puckZ + (newer.puckZ - older.puckZ) * t,
		newer.puckVx,
		newer.puckVz
end

-- End-of-match line-up: the winning team (or yours on a draw) stands at centre ice facing a
-- close camera, with everyone else out of shot.
local PODIUM_CAMERA = CFrame.lookAt(Vector3.new(-17, 6.5, 0), Vector3.new(0, 3.6, 0))
local function applyPodium(): boolean
	if not (mode == "Match" and matchState and matchState.phase == "Final") then
		return false
	end
	local team = matchState.winner
	if team == 0 then
		team = if mySlot then teamOfSlot(mySlot) else 1
	end
	for slot = 1, Protocol.SLOTS do
		local state = renderStates[slot]
		if teamOfSlot(slot) == team then
			local i = (slot - 1) % 3
			state.x, state.z = 0, (i - 1) * 5.5
			state.vx, state.vz = 0, 0
			state.yaw = math.pi + (i - 1) * 0.35
			state.radius = 0.55
			state.charging, state.active, state.stunned, state.sprinting = false, false, false, false
			state.visible = true
		else
			state.visible = false
		end
	end
	return true
end

-- Fixed-step input and prediction.
local matchInput = Sim.newInput()
local accumulator = 0
local stepCount = 0
local localFocus = Vector3.zero
-- Stick lift per slot last frame, for the tap as a blade leaves the ice or comes back down.
local wasLifted: { boolean } = table.create(Protocol.SLOTS, false)

local function isLocalMode(): boolean
	return mode == "Training"
end

-- Settings, Gameplay: "Controls match camera" makes up on the keys follow the E camera flip.
local function moveFlip(): number
	return if Prefs.get("matchCamera") == false then 1 else cameraFlip
end

local function fixedStep(camera: Camera)
	if isLocalMode() and Training.isActive() then
		Controls.sample(Training.input(), moveFlip(), camera, localFocus)
		Training.step()
		Controls.syncAim(Training.aimYaw())
	elseif mode == "Pond" then
		Pond.fixedStep(camera, moveFlip(), localFocus)
	elseif mode == "Match" and mySlot and matchState then
		Controls.sample(matchInput, screenForward * moveFlip(), camera, localFocus)
		Prediction.step(matchInput)
		Controls.syncAim(Prediction.skater().aimYaw)
		stepCount += 1
		if stepCount % SEND_EVERY == 0 then
			local packet = Prediction.pack(matchState.phaseId)
			if packet then
				InputRemote:FireServer(packet)
			end
		end
	end
end

-- Screens.
local screen = Instance.new("ScreenGui")
screen.Name = "PuckPalsUI"
screen.IgnoreGuiInset = true
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local uiScale = Instance.new("UIScale")
uiScale.Parent = screen

local function updateUiScale()
	local camera = workspace.CurrentCamera
	if camera then
		local size = camera.ViewportSize
		-- Automatic fit times the player's UI size setting (vault: "UI Scale HUD Hide and Compact Mode").
		local fit = math.clamp(math.min(size.X / 1100, size.Y / 640), 0.55, 1.5)
		uiScale.Scale = fit * (Prefs.get("uiScale") or 1)
	end
end

local function leaveCurrentMode()
	if isLocalMode() then
		Training.stop()
	elseif mode == "Pond" then
		Pond.stop()
		CameraRig.setClamped(true)
	elseif mode == "Match" then
		ActionRemote:FireServer("Leave")
	end
	Results.hide()
	Results.hideBoard()
	Controls.holdCursor("results", false)
	Controls.holdCursor("reward", false)
	Controls.setTouchExtras(nil)
	Hud.hideReward()
	Hud.idleWarning(nil)
	Hud.setTimeCall(nil)
	GameMenu.close()
	Hud.banner("", nil)
	Hud.setCount(nil)
	Fx.endCelebration(true)
	celebrateSlot = nil
	Replay.stop()
	Replay.clear()
	CameraRig.releaseFixed()
	Prediction.setPredicting(false)
	for slot = 1, Protocol.SLOTS do
		renderStates[slot].visible = false
	end
end

local function enterMenu()
	leaveCurrentMode()
	mode = "Menu"
	Controls.setEnabled(false)
	Hud.setVisible(false)
	applyArenaLighting("Lobby")
	Menu.show()
end

local function enterMatch(action: string?)
	if mode == "Match" then
		-- PLAY AGAIN on the post-game screen: the next match starts once everyone on the ice
		-- has picked it.
		if matchState and matchState.phase == "Final" then
			ActionRemote:FireServer("Again")
			Hud.banner("GET READY", "NEXT MATCH STARTING", INK, 2)
		end
		Results.hide()
		return
	end
	leaveCurrentMode()
	mode = "Match"
	Fx.setCrowdReacts(true) -- Build 40: the stands "ooh" at saves and posts in a match only
	Menu.hide()
	Hud.setVisible(true)
	Hud.setMatchWidgets(true)
	Hud.setObjective(nil, nil)
	Controls.setEnabled(true)
	lastPhaseId = -1
	local map = matchArena(if matchState then matchState.map or "Arena" else "Arena")
	showRink(map)
	applyArenaLighting(map)
	ActionRemote:FireServer(action or "Play")
end

-- The pond: everyone on the server who chose it, skating one shared lake.
local function enterPond()
	leaveCurrentMode()
	mode = "Pond"
	Fx.setCrowdReacts(false)
	Menu.hide()
	Hud.setVisible(true)
	Controls.setEnabled(true)
	screenForward = 1
	cameraFlip = 1
	showRink("Pond")
	applyArenaLighting("Pond")
	-- The match skaters seen through the big rink's boards carry no name tags.
	for slot = 1, Protocol.SLOTS do
		views[slot]:setTagVisible(false)
	end
	refreshIdentities()
	CameraRig.setClamped(false)
	Pond.start()
	refreshTouchExtras()
end

local function enterLocal(pond: boolean, tutorial: boolean?)
	leaveCurrentMode()
	mode = if pond then "Pond" else "Training"
	Fx.setCrowdReacts(false) -- Build 40: no crowd "ooh" in practice or the drills
	Menu.hide()
	Hud.setVisible(true)
	Controls.setEnabled(true)
	screenForward = 1
	cameraFlip = 1
	local theme = if pond then "Pond" else "Arena"
	showRink(theme)
	applyArenaLighting(theme)
	Training.setRewardClaimed(profile ~= nil and profile.tutorialDone == true)
	Training.start(workspace, pond, tutorial)
	if tutorial then
		ActionRemote:FireServer("TutorialStart")
	end
	local look = if profile then profile.look else nil
	for slot = 1, Protocol.SLOTS do
		if slot == 1 then
			views[slot]:setIdentity(localPlayer.DisplayName, if pond then 0 else 1, true, look)
		elseif slot == 2 then
			-- Coach Gus, on your team, takes the pass in the tutorial.
			views[slot]:setIdentity("Coach Gus", 1, false, Catalog.botLook(9))
		else
			views[slot]:setIdentity("Goalie", 2, false, Catalog.botLook(4))
		end
		views[slot]:setTagVisible(nameTags)
	end
	refreshTouchExtras()
end

-- Tap buttons for practice on touch screens: PUCK (bring it back) during the drills, plus
-- + PUCK and GOALIE in free practice; PUCK in the pond.
function refreshTouchExtras()
	if isLocalMode() then
		local list = { { text = "PUCK", run = Training.resetPuck } }
		if not Training.inTutorial() then
			table.insert(list, { text = "+ PUCK", run = Training.addPuck })
			table.insert(list, { text = "GOALIE", run = Training.toggleGoalie })
		end
		Controls.setTouchExtras(list)
	elseif mode == "Pond" then
		Controls.setTouchExtras({ { text = "PUCK", run = function()
			Pond.addPuck()
		end } })
	else
		Controls.setTouchExtras(nil)
	end
end

Training.onTutorialDone(function()
	ActionRemote:FireServer("TutorialDone")
	refreshTouchExtras()
end)

function enterMatchRef()
	enterMatch()
end

function enterMenuRef()
	enterMenu()
end

function enterPondRef()
	enterPond()
	Hud.toast("Back on the pond.", true)
end

-- Brand-new players (no tutorial, no matches) start in the tutorial instead of the menu, once
-- per session; MENU leaves it at any time (vault: "First-Time User Experience and Onboarding").
local autoTutorialChecked = false
startTutorialIfNew = function()
	if autoTutorialChecked or not uiReady or mode ~= "Menu" or not profile then
		return
	end
	if profile.status == "loading" or profile.status == "temporary" then
		return -- wait for the real save before deciding
	end
	autoTutorialChecked = true
	local matches = (profile.stats and profile.stats.matches) or 0
	if profile.tutorialDone ~= true and matches == 0 then
		enterLocal(false, true)
	end
end

-- Idle kick (the server counts; this only shows it): a countdown from 10, then the lobby.
IdleRemote.OnClientEvent:Connect(function(n: any)
	if type(n) ~= "number" then
		return
	end
	if n > 0 then
		if mode == "Match" then
			Hud.idleWarning(n)
		end
	elseif n == 0 then
		Hud.idleWarning(nil)
		if mode == "Match" then
			enterMenu()
			Hud.toast("You were sent back to the lobby for being idle.", false, 5)
		end
	else
		Hud.idleWarning(nil)
	end
end)

-- Reading the in-game menu or the scoreboard isn't being idle, as long as the player is
-- actually touching something.
task.spawn(function()
	while true do
		task.wait(4)
		if mode == "Match" and (GameMenu.isOpen() or scoreboardHeld) and os.clock() - lastUiInput < 5 then
			ActionRemote:FireServer("StillHere")
		end
	end
end)

-- The in-game menu: MENU on the HUD or the held scoreboard, or Select on a gamepad.
local function openGameMenu()
	if mode ~= "Menu" then
		-- A match on the pond rink also offers the way back out onto the pond (LEAVE MATCH goes
		-- all the way to the lobby).
		local extra = nil
		if mode == "Match" and matchState and matchState.map == "Pond" then
			extra = { text = "LEAVE POND GAME", run = function()
				enterPondRef()
			end }
		end
		-- Build 37: mid-match, leaving is a loss (the server's forfeit rule), so the menu asks first.
		local phase = matchState and matchState.phase
		local underWay = mode == "Match" and mySlot ~= nil and phase ~= nil
			and phase ~= "Waiting" and phase ~= "Countdown" and phase ~= "Final" and phase ~= "Cleanup"
		GameMenu.open(if mode == "Match" then "LEAVE MATCH" else "BACK TO MENU", extra, underWay)
	end
end
Hud.init(screen, openGameMenu)
Replay.init(playerGui)
Replay.onVote(function()
	ActionRemote:FireServer("SkipReplay")
end)
Results.init(screen, {
	onQuickPlay = enterMatch,
	onPractice = function()
		enterLocal(false)
	end,
	onPond = function()
		enterPond()
	end,
	onMenu = enterMenu,
	onBoardMenu = openGameMenu,
	onBoardSettings = function()
		if mode ~= "Menu" then
			openGameMenu()
			GameMenu.openSettings()
		end
	end,
})
Controls.setupTouch(screen)

-- Settings apply the moment they change (and once for the saved copy).
local function applySetting(name: string, value: any)
	if name == "shake" then
		CameraRig.setShakeEnabled(value)
	elseif name == "reduceParticles" then
		Fx.setReduceParticles(value)
	elseif name == "highContrast" then
		Fx.setHighContrast(value)
	elseif name == "nameTags" then
		nameTags = value
		SkaterView.config.tags = value
		if mode == "Match" then
			refreshIdentities()
		else
			for slot = 1, Protocol.SLOTS do
				views[slot]:setTagVisible(value)
			end
		end
	elseif name == "lowGraphics" then
		if lowGraphics ~= value then
			lowGraphics = value
			rebuildRinks()
		end
	elseif name == "volume" then
		Fx.setVolume(value)
	elseif name == "zoom" then
		CameraRig.setZoom(value)
	elseif name == "fov" then
		CameraRig.setFov(value)
	elseif name == "follow" then
		CameraRig.setFollow(value)
	elseif name == "flipTime" then
		CameraRig.setFlipTime(value)
	elseif name == "zoomStep" then
		CameraRig.setZoomStep(value)
	elseif name == "camHeight" or name == "camBack" or name == "camAhead" then
		CameraRig.setFrame(Prefs.get("camHeight"), Prefs.get("camBack"), Prefs.get("camAhead"))
	elseif name == "camSmooth" then
		CameraRig.setSmooth(value)
	elseif name == "stickColor" or name == "puckColor" then
		local function color(i: number): Color3
			return (SettingsDef.Colors[i] or SettingsDef.Colors[1])[2]
		end
		Xray.setColors(color(Prefs.get("stickColor")), color(Prefs.get("puckColor")))
	elseif name == "puckOutline" then
		Xray.setPuckAlways(value)
	elseif name == "trailGround" or name == "trailAir" then
		local function color(i: number): Color3
			return (SettingsDef.Colors[i] or SettingsDef.Colors[1])[2]
		end
		Fx.setTrailColors(color(Prefs.get("trailGround")), color(Prefs.get("trailAir")))
	elseif name == "ownName" then
		SkaterView.config.ownTag = value
	elseif name == "teamRings" then
		SkaterView.config.rings = value
	elseif name == "ownRing" then
		SkaterView.config.ownRing = value
	elseif name == "nameSize" then
		SkaterView.config.tagScale = value
	elseif name == "minimap" then
		Hud.setShown("minimap", value)
	elseif name == "scoreBug" then
		Hud.setShown("scoreBug", value)
	elseif name == "showPing" then
		Hud.setShown("ping", value)
	elseif name == "showFps" then
		Hud.setShown("fps", value)
	elseif name == "minimapScale" then
		Hud.setMinimapScale(value)
	elseif name == "meterScale" or name == "meterOpacity" then
		Hud.setMeterLook(Prefs.get("meterScale"), Prefs.get("meterOpacity"))
	elseif name == "shadows" or name == "bloom" or name == "grade" then
		applyVideo()
	elseif name == "arena" then
		if mode == "Match" and matchState then
			local map = matchArena(matchState.map or "Arena")
			showRink(map)
			applyArenaLighting(map)
		end
	elseif name == "sfxVolume" then
		Fx.setBus("sfx", value)
	elseif name == "crowdVolume" then
		Fx.setBus("crowd", value)
	elseif name == "hornVolume" then
		Fx.setBus("horn", value)
	end
end
Prefs.onChanged(function(name: string, value: any)
	if name == "*" then
		for key, v in value do
			if key ~= "binds" then
				applySetting(key, v)
			end
		end
	else
		applySetting(name, value)
	end
end)

-- Daily login rewards: opens by itself once a session when today's coins are waiting (in the
-- menu), and from the promo card any time.
local dailyShown = false
DailyRewards.init(screen, {
	onClaim = function()
		ActionRemote:FireServer("ClaimLogin")
	end,
	onTutorial = function()
		enterLocal(false, true)
	end,
	onOpenChanged = function(open: boolean)
		Controls.holdCursor("daily", open)
	end,
})

Menu.init(screen, {
	onPlay = enterMatch,
	onDaily = function()
		DailyRewards.open()
	end,
	onPractice = function()
		enterLocal(false)
	end,
	onTutorial = function()
		enterLocal(false, true)
	end,
	onPond = function()
		enterPond()
	end,
	onPreviewLook = setLobbyLook,
	onEquip = function(kind: string, value: any)
		ShopRemote:FireServer("Equip", kind, value)
		-- Picking a goal sound plays it.
		local item = Catalog.ById[value]
		if kind == "goal" and item then
			Fx.goalSound(item.style, 1)
		end
	end,
	onBuy = function(id: string)
		ShopRemote:FireServer("Buy", id)
	end,
	-- Build 34: the Mystery Box (the server checks everything, then opens the Robux prompt).
	onBuyCoins = function(key: string)
		ShopRemote:FireServer("BuyCoins", key)
	end,
	onStayTuned = function()
		-- Build 36: the 1v1 teaser's STAY TUNED. Our own line first (Roblox's opt-in box has fixed
		-- text), then Roblox's notification opt-in. Roblox shows it at most once a month per game,
		-- never to under-13s and not if alerts are already on; then the toast is all they see.
		-- Vault: "Experience Notifications and Return Prompts" (player-chosen moment, context first).
		task.spawn(function()
			local ENS = game:GetService("ExperienceNotificationService")
			local ok, can = pcall(function()
				return ENS:CanPromptOptInAsync()
			end)
			if ok and can == true then
				Hud.toast("TURN ON NOTIFICATIONS TO HEAR THE MOMENT 1V1 SHOOTOUT DROPS!", true, 4)
				task.wait(0.6)
				pcall(function()
					ENS:PromptOptIn()
				end)
			else
				Hud.toast("1V1 SHOOTOUT IS ON ITS WAY. WE'LL ANNOUNCE IT RIGHT HERE!", true, 3)
			end
		end)
	end,
	onOpenBox = function()
		ShopRemote:FireServer("OpenBox")
	end,
	onPreviewGoal = function(style: string?)
		Fx.goalSound(style, 1)
	end,
	onClaimChallenge = function(id: string)
		ShopRemote:FireServer("ClaimChallenge", id)
	end,
	onPanel = function(name: string?)
		lobbyPanelOpen = name == "Locker" or name == "Shop"
		lobbyStatsOpen = name == "Stats"
	end,
})

Pond.init({
	inputRemote = InputRemote,
	actionRemote = ActionRemote,
	snapshotRemote = PondSnapshotRemote,
	cueRemote = PondCueRemote,
	eventRemote = PondEventRemote,
	parent = workspace,
	onQueue = function()
		enterMatch("PlayPond")
	end,
	scene = function(): Instance?
		local built = rinks.Pond
		return if built then built.model else nil
	end,
})

GameMenu.init(screen, {
	onSettings = function(parent: Instance, onClose: () -> ())
		Menu.openSettingsOverlay(parent, onClose)
	end,
	onLeave = enterMenu,
	onOpenChanged = function(open: boolean)
		Controls.holdCursor("menu", open)
	end,
	onClosing = function()
		Menu.closeSettingsOverlay()
	end,
})

local function refreshNotice()
	local notice = localPlayer:GetAttribute("DataNotice")
	Hud.setNotice(if type(notice) == "string" then notice else nil)
end
localPlayer:GetAttributeChangedSignal("DataNotice"):Connect(refreshNotice)

local Pad = InputHints.Pad
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	lastUiInput = os.clock()
	-- Controller in the menus: B goes back a step, LB / RB walk the top tabs.
	if input.KeyCode == Enum.KeyCode.ButtonB then
		if DailyRewards.isOpen() then
			DailyRewards.close()
			return
		end
		if GameMenu.isOpen() then
			if not Menu.padBack() then
				GameMenu.close()
			end
			return
		elseif mode == "Menu" and Menu.padBack() then
			return
		end
	end
	if mode == "Menu" and (input.KeyCode == Enum.KeyCode.ButtonL1 or input.KeyCode == Enum.KeyCode.ButtonR1) then
		Menu.cycleTab(if input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1)
		return
	end
	if (Prefs.matches("board", input) or input.KeyCode == Pad.board) and mode ~= "Menu" then
		-- Holding the scoreboard key frees the cursor so MENU / SETTINGS can be clicked.
		Controls.holdCursor("board", true)
		if mode == "Match" then
			scoreboardHeld = true
			Results.showBoard(matchState, mySlot)
		end
		return
	end
	if input.KeyCode == Enum.KeyCode.ButtonSelect and mode ~= "Menu" then
		if GameMenu.isOpen() then
			GameMenu.close()
		else
			openGameMenu()
		end
		return
	end
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.F2 then
		debugOn = not debugOn
		if not debugOn then
			Hud.setDebug(nil)
		end
	elseif (Prefs.matches("flip", input) or input.KeyCode == Enum.KeyCode.ButtonR1) and (mode == "Match" or mode == "Pond" or isLocalMode()) then
		cameraFlip = -cameraFlip
	elseif (Prefs.matches("reset", input) or input.KeyCode == Pad.reset) and isLocalMode() then
		Training.resetPuck()
	elseif (Prefs.matches("addPuck", input) or input.KeyCode == Pad.addPuck) and isLocalMode() then
		Training.addPuck()
	elseif (Prefs.matches("addPuck", input) or Prefs.matches("reset", input) or input.KeyCode == Pad.reset or input.KeyCode == Pad.addPuck) and mode == "Pond" then
		Pond.addPuck()
	elseif (Prefs.matches("goalie", input) or input.KeyCode == Pad.goalie) and mode == "Training" then
		Training.toggleGoalie()
	elseif Prefs.matches("hud", input) then
		Hud.toggleHidden()
	elseif input.KeyCode == Enum.KeyCode.DPadUp and mode ~= "Menu" then
		Prefs.set("zoom", CameraRig.zoomBy(-1))
	elseif input.KeyCode == Enum.KeyCode.DPadDown and mode ~= "Menu" then
		Prefs.set("zoom", CameraRig.zoomBy(1))
	end
end)
-- Wheel up zooms in, wheel down zooms out.
UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
	-- A real hand on the controls (not a phone's tilt sensor or a resting thumbstick).
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseWheel
		or (kind == Enum.UserInputType.Gamepad1 and input.Position.Magnitude > 0.3) then
		lastUiInput = os.clock()
	end
	if not processed and input.UserInputType == Enum.UserInputType.MouseWheel and input.Position.Z ~= 0 then
		if mode ~= "Menu" then
			Prefs.set("zoom", CameraRig.zoomBy(if input.Position.Z > 0 then -1 else 1))
		end
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if Prefs.matches("board", input) or input.KeyCode == Enum.KeyCode.Tab or input.KeyCode == Pad.board then
		Controls.holdCursor("board", false)
		if scoreboardHeld then
			scoreboardHeld = false
			Results.hideBoard()
		end
	end
end)

-- Studio-only test hook: the server sets the DevEnter attribute to drive screens in tests.
if RunService:IsStudio() then
	localPlayer:GetAttributeChangedSignal("DevEnter"):Connect(function()
		local what = localPlayer:GetAttribute("DevEnter")
		if what == "Match" then
			enterMatch()
		elseif what == "Practice" then
			enterLocal(false)
		elseif what == "Tutorial" then
			enterLocal(false, true)
		elseif what == "Pond" then
			enterPond()
		elseif what == "Menu" then
			enterMenu()
		elseif type(what) == "string" and string.sub(what, 1, 5) == "Open:" then
			Menu.open(string.sub(what, 6))
		elseif type(what) == "string" and string.sub(what, 1, 6) == "Drill:" then
			Training.devJump(tonumber(string.sub(what, 7)) or 1)
		end
	end)
end

uiReady = true
if profile then
	Menu.setProfile(profile)
end
if matchState then
	Hud.setScores(matchState.scores[1], matchState.scores[2])
	refreshIdentities()
end
ActionRemote:FireServer("Hello")
showRink("Arena")
applyArenaLighting("Lobby")
Menu.show()
updateUiScale()
refreshNotice()
task.defer(function()
	local start = startTutorialIfNew
	if start then
		start()
	end
end)

local clock = 0
local penguinFrame = 0
local netDebugAt = 0
RunService.PreRender:Connect(function(dt: number)
	-- Studio only: publish the prediction error totals once a second for tuning.
	if RunService:IsStudio() and os.clock() >= netDebugAt then
		netDebugAt = os.clock() + 1
		local reset = localPlayer:GetAttribute("NetDebugReset") == true
		if reset then
			localPlayer:SetAttribute("NetDebugReset", nil)
		end
		localPlayer:SetAttribute("NetDebug", Prediction.stats(reset))
	end
	Controls.pollMouse(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	clock += dt
	updateUiScale()
	-- Build 32: the penguins waddle at 30 fps (every other frame at 60), not every frame.
	penguinFrame += 1
	if #penguins > 0 and shownTheme == "Pond" and penguinFrame % 2 == 0 then
		ArenaBuilder.animatePenguins(penguins, clock)
	end

	if mode == "Menu" then
		-- Lobby: the player's skater idles on the mat.
		local bob = math.sin(clock * 2) * 0.06
		Looks.pose(lobbyRig, lobby.stand * CFrame.new(0, bob, 0) * CFrame.Angles(0, lobbyYaw + math.sin(clock * 0.6) * 0.08, 0))
		-- Build 36: CAREER STATS swoops in close on the skater (narrower lens too, for the zoom).
		CameraRig.fixed(camera, dt, if lobbyStatsOpen then lobby.statsCamera elseif lobbyPanelOpen then lobby.panelCamera else lobby.camera, if lobbyStatsOpen then 40 else 46)
		for slot = 1, Protocol.SLOTS do
			views[slot]:setVisible(false)
		end
		Xray.hide()
		return
	end

	accumulator = math.min(accumulator + dt, TICK * MAX_STEPS_PER_FRAME)
	while accumulator >= TICK do
		accumulator -= TICK
		fixedStep(camera)
	end
	local alpha = accumulator / TICK

	advanceRenderClock(dt)
	if mode == "Pond" then
		-- A match going on in the big rink shows through its boards.
		local watching = false
		if matchState and (matchState.phase == "Countdown" or matchState.phase == "Faceoff" or canSkate(matchState.phase)) then
			for _, entry in matchState.roster do
				if not entry.bot then
					watching = true
				end
			end
		end
		if watching and ringCount > 0 then
			local mx, my, mz = sampleSnapshots()
			Pond.setMatchPuck(mx, my, mz)
		else
			Pond.setMatchPuck(nil)
			for slot = 1, Protocol.SLOTS do
				renderStates[slot].visible = false
			end
		end
		for slot = 1, Protocol.SLOTS do
			views[slot]:update(renderStates[slot], dt)
		end
		local focus, velocity, ppx, ppy, ppz, ppvx, ppvz = Pond.render(alpha, dt, renderClock)
		Fx.update(ppx, ppy, ppz, ppvx, ppvz)
		table.clear(occluders)
		Pond.occluders(occluders)
		for slot = 1, Protocol.SLOTS do
			if renderStates[slot].visible then
				table.insert(occluders, renderStates[slot])
			end
		end
		Xray.update(camera, dt, Pond.rig(), occluders, if ppy > -1 then Fx.puck() else nil)
		localFocus = focus
		CameraRig.follow(camera, dt, focus, velocity, Vector3.new(ppx, 0, ppz), screenForward * cameraFlip)
		Hud.setPing()
		Hud.tickFps(dt)
		local spin, stamina, spunOut = Pond.meters()
		Hud.setMeters(spin, stamina, Pond.ready(), spunOut)
		Hud.setCount(nil)
		return
	end
	local px, py, pz, pvx, pvz
	if isLocalMode() and Training.isActive() then
		px, py, pz, pvx, pvz = Training.fill(alpha, renderStates, dt)
	else
		px, py, pz, pvx, pvz = sampleSnapshots()
		if mode == "Match" and mySlot and Prediction.puckReady() and ringCount > 0 then
			-- With a predicted puck, the other skaters are drawn at the puck's time and their
			-- sticks exactly where the puck's physics has them.
			Prediction.renderOthers(alpha, dt, renderStates)
		end
	end

	local focusSlot = if mode == "Match" then mySlot else 1
	if mode == "Match" and mySlot and Prediction.isPredicting() then
		local pos = Prediction.renderPosition(alpha, dt)
		local s = Prediction.skater()
		local state = renderStates[mySlot]
		state.x, state.z = pos.X, pos.Z
		state.vx, state.vz = s.vel.X, s.vel.Z
		state.yaw, state.radius = s.aimYaw, s.aimRadius
		state.charging = s.stickState == Sim.WINDING
		state.active = s.stickState == Sim.ACTIVE
		state.charge = s.charge
		state.lifted = s.lifted
		state.lofting = s.lofting
		state.sprinting = s.sprinting
	end

	-- The local stick is drawn where the simulation has it (interpolated between ticks, like the
	-- puck), so what you see touching the puck is exactly what the physics touched.
	if mode == "Match" and mySlot and Prediction.isPredicting() then
		renderStates[mySlot].yaw = Prediction.renderYaw(alpha)
		if Prediction.puckReady() then
			-- The puck always comes from local prediction, which now collides with every stick
			-- and body (the others drawn on the same timeline), so no blade is ever seen to pass
			-- through it. The server corrects it with every snapshot, eased away in Prediction.
			local predicted, predictedVel = Prediction.renderPuck(alpha, dt)
			px, py, pz = predicted.X, predicted.Y, predicted.Z
			pvx, pvz = predictedVel.X, predictedVel.Z
		end
	end

	-- Goal replay: draw the recorded moment instead of the live one. The follow camera still
	-- runs underneath so it is already on your skater when the replay hands back.
	if mode == "Match" and Replay.drawing() then
		if mySlot then
			local state = renderStates[mySlot]
			CameraRig.follow(camera, dt, Vector3.new(state.x, 0, state.z), Vector3.new(state.vx, 0, state.vz), Vector3.new(px, 0, pz), screenForward * cameraFlip)
		end
		local states, rpx, rpy, rpz, rpvx, rpvz, cf, fov = Replay.frame()
		for slot = 1, Protocol.SLOTS do
			views[slot]:update(states[slot], dt)
		end
		Fx.update(rpx, rpy, rpz, rpvx, rpvz)
		Xray.hide()
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = cf
		camera.FieldOfView = fov
		Hud.setCount(nil)
		return
	end
	-- Film what you see, for the replay (it stops filming on its own shortly after a goal).
	if mode == "Match" then
		Replay.record(os.clock(), renderStates, px, py, pz, pvx, pvz)
	end

	local podium = applyPodium()
	for slot = 1, Protocol.SLOTS do
		local state = renderStates[slot]
		views[slot]:update(state, dt)
		-- Stick lift: a tick as the blade leaves the ice, a tap as it lands again.
		local lifted = state.visible and state.lifted == true
		if lifted ~= wasLifted[slot] then
			wasLifted[slot] = lifted
			-- Build 32: also in the seconds before a drop (sticks tap while everyone waits).
			local tapPhase = matchState and (canSkate(matchState.phase) or matchState.phase == "Faceoff" or matchState.phase == "Countdown")
			if state.visible and not podium and (mode ~= "Match" or tapPhase) then
				local blade = Sim.bladeAt(Vector3.new(state.x, 0, state.z), state.yaw, 1)
				Fx.stickTap(blade.X, blade.Z, not lifted, slot == (if mode == "Match" then mySlot else 1))
			end
		end
	end
	if celebrateSlot and renderStates[celebrateSlot].visible then
		Fx.setSpot(renderStates[celebrateSlot].x, renderStates[celebrateSlot].z)
	end
	if podium then
		-- Park the puck under the ice so it doesn't sit in the line-up shot.
		Fx.update(0, -5, 0, 0, 0)
		Xray.hide()
		CameraRig.fixed(camera, dt, PODIUM_CAMERA, 40)
		Hud.setMeters(0, 0, false)
		Hud.setCount(nil)
		Hud.setTimeCall(nil)
		return
	end
	Fx.update(px, py, pz, pvx, pvz)

	-- Yellow see-through outlines for your stick and the puck when something blocks them.
	table.clear(occluders)
	for slot = 1, Protocol.SLOTS do
		local state = renderStates[slot]
		if state.visible then
			table.insert(occluders, state)
		end
	end
	local outlineSlot = if mode == "Match" then mySlot elseif isLocalMode() then 1 else nil
	local outlineRig = if outlineSlot and renderStates[outlineSlot].visible then views[outlineSlot].rig else nil
	-- Build 40: practice's extra pucks glow through too.
	Xray.update(camera, dt, outlineRig, occluders, Fx.puck(), if isLocalMode() and Training.isActive() then Training.extraPucks() else nil)

	local puck = Vector3.new(px, 0, pz)
	local focus = puck
	local velocity = Vector3.zero
	if focusSlot then
		local state = renderStates[focusSlot]
		focus = Vector3.new(state.x, 0, state.z)
		velocity = Vector3.new(state.vx, 0, state.vz)
		localFocus = focus
	end
	CameraRig.follow(camera, dt, focus, velocity, puck, screenForward * cameraFlip)

	Hud.setPing()
	Hud.tickFps(dt)
	if isLocalMode() then
		local spin, stamina, spunOut = Training.meters()
		Hud.setMeters(spin, stamina, true, spunOut)
		Hud.setCount(nil)
		return
	end

	Hud.setDegraded(os.clock() - lastSnapshotClock > STALE_SECONDS)
	if mySlot then
		local s = Prediction.skater()
		Hud.setMeters(s.spin, s.stamina, true, s.spinLock > 0)
	else
		Hud.setMeters(0, 0, false)
	end
	-- Face-off: 3, 2, 1 while the puck hangs over the dot.
	if matchState and matchState.phase == "Faceoff" and (matchState.endsAt or 0) > 0 then
		local left = matchState.endsAt - workspace:GetServerTimeNow()
		Hud.setCount(if left > 0 then math.clamp(math.ceil(left), 1, 3) else nil)
	else
		Hud.setCount(nil)
	end
	if matchState then
		local running = matchState.phase == "Live"
		local clockNow = if running then clockValue - (os.clock() - clockReceivedAt) else clockValue
		Hud.setClock(clockNow, matchState.overtime, matchState.phase)
		Hud.setTimeCall(timeCallFor(matchState, clockNow))
		if scoreboardHeld then
			Results.showBoard(matchState, mySlot)
		end
	end
	for slot = 1, Protocol.SLOTS do
		local state = renderStates[slot]
		Hud.setMapSkater(slot, state.x, state.z, screenForward * cameraFlip, true, slot == mySlot)
	end
	Hud.setMapPuck(px, pz, screenForward * cameraFlip)

	if debugOn then
		Hud.setDebug(
			`tick {newestTick}  phase {if matchState then matchState.phase else "?"} #{lastPhaseId}\n`
				.. `slot {mySlot or 0}  pending frames {Prediction.pendingFrames()}\n`
				.. `last correction {math.round(Prediction.lastCorrection() * 100) / 100} studs  lead {math.round(Prediction.leadSeconds() * 1000)} ms\n`
				.. `predicting {Prediction.isPredicting()}`
		)
	end
end)
