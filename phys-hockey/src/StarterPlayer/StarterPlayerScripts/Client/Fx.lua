--!strict
-- Puck visuals, impact sparks, goal confetti, crowd reaction and audio. High-impact effects
-- only follow confirmed server events. Audio ids are deliberately empty until licensed sounds
-- are chosen, and every cue is a safe no-op until then.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local CameraRig = require(script.Parent.CameraRig)
local Looks = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Looks"))

local Fx = {}

-- Licensed Creator Store sounds only (found with the Studio asset search, Nov 2026); never guess
-- an id. Pro Sound Effects clips are licensed by Roblox for use in experiences. The goal horn
-- is a diesel air horn (what arena horns are), pitched down a little.
local SoundCatalog: { [string]: string } = {
	Hit = "rbxassetid://9114814572", -- Hockey Stick Single Hits On Ice Taps 2 (ProSoundEffects)
	-- Build 29: a real slap shot. Hockey Shots Slap Shots Hit Boards Stick Hits 1 (ProSoundEffects),
	-- the stick-on-puck crack only (it starts 0.2 s in; measured with PlaybackLoudness in Studio).
	Shot = "rbxassetid://9125607888",
	-- Hockey Puck Drop Slap On Ice Bounces 1 (ProSoundEffects): a puck coming down on the ice, first hit only.
	Land = "rbxassetid://9114811906",
	-- Build 30: a short male "oof" burst (ProSoundEffects, Male Scream Short Yelling Bursts),
	-- about four times louder than the old grunt (measured peak 174 vs 47).
	Oof = "rbxassetid://9125651373",
	Board = "rbxassetid://9117555258", -- Plastic Impact Hard Dropping Hollow Hits 4 (ProSoundEffects)
	Post = "rbxassetid://9117375064", -- Pipe Bang On Heavy Steel Pipe 2 (ProSoundEffects): a solid clank off the post (the old clip was near silent)
	-- Build 31: other takes of the same pipe bang (ProSoundEffects), each played a little deeper,
	-- so posts and crossbars don't all ring the same.
	Post2 = "rbxassetid://9117375060", -- Pipe Bang On Heavy Steel Pipe 3
	Post3 = "rbxassetid://9117375071", -- Pipe Bang On Heavy Steel Pipe 4
	Post4 = "rbxassetid://9117375689", -- Pipe Bang On Heavy Steel Pipe 4 (second take)
	Post5 = "rbxassetid://9117375375", -- Pipe Bang On Heavy Steel Pipe 2 (second take)
	-- Build 31: the low whack under the shot crack (Body Hits 10, pitched well down).
	ShotThump = "rbxassetid://9113502635",
	Check = "rbxassetid://9113502635", -- Body Hits 10 (ProSoundEffects)
	Whistle = "rbxassetid://9117261163", -- Pealess Whistle Referee Fox 40 4 (ProSoundEffects)
	RefWhistle = "rbxassetid://9118113825", -- Referee Whistle 2, Exterior, Single Blast (ProSoundEffects)
	Horn = "rbxassetid://9114075901", -- Diesel Truck Horn Air Horn Exterior 3 (ProSoundEffects)
	Siren = "rbxassetid://9119661877", -- Submarine Alarm Collision Electronic Siren 3 (ProSoundEffects)
	Body = "rbxassetid://9113502635", -- Body Hits 10, played short and light for a puck off a body
	Tap = "rbxassetid://9114814745", -- Hockey Stick Single Hits On Ice Taps 4 (ProSoundEffects): stick lift coming back down
	Cheer = "rbxassetid://117750774203463", -- crowd-cheering (Live on Roblox)
	ShipHorn = "rbxassetid://9119077419", -- Ship Horn Uss Constellation 2 (ProSoundEffects), 4.7 s
	GoalSiren = "rbxassetid://9114024708", -- Damage Zone Alarm 1 (ProSoundEffects): fast high-low two-tone siren
	Ambience = "rbxassetid://9119562311", -- Stadium Crowd 2 (ProSoundEffects): indoor arena crowd idling, steady walla, 51 s (the old theatre loop measured loudness 4-8: inaudible)
	Bottle = "rbxassetid://9117555258", -- Plastic Impact Hard Dropping Hollow Hits 4 (ProSoundEffects), pitched up: a plastic bottle knocked flying
	-- Build 30: a fuller take of the stadium crowd going "ohh" (ProSoundEffects Crowd Disappointment);
	-- the old one peaked at 17, this one at 47 from about 0.4 s in.
	CrowdOoh = "rbxassetid://9114010229",
	-- Goal sounds from the season pass (Catalog kind "goal").
	AirHorn = "rbxassetid://9113072391", -- Air Horn Various Lengths 12 (ProSoundEffects): stadium blasts, pulsing, 4.3 s
	-- Build 36: the fireworks are licensed Pro Sound Effects clips (the old Creator Store uploads
	-- weren't licensed, and one had people talking in it).
	RocketUp = "rbxassetid://9114447096", -- Fireworks Fast 1 (ProSoundEffects): whistlers going up, 5.9 s
	FireworkBoom = "rbxassetid://9114361763", -- Explosion Oxyacetylene Gas 1 (ProSoundEffects): a mortar-style blast, 6.3 s
	Crackle = "rbxassetid://9112780680", -- Fireworks Hiss 1 (ProSoundEffects): burning, crackling, 61 s loop
	-- Build 34: goal sounds sold in the shop (licensed libraries only).
	Quack = "rbxassetid://1845384542", -- Quack Quack (APM Music)
	Goat = "rbxassetid://9113442867", -- Billy Goat 7 (ProSoundEffects): a close "baaaa", 1.5 s
	PartyHorn = "rbxassetid://9117241038", -- Party Horn 11 (ProSoundEffects): one blast, 1.6 s
	VikingHorn = "rbxassetid://9114822421", -- Horn Blow, Shofar Ram's Horn, Long Bursts 6 (ProSoundEffects): held 0.8-1.5 s
	HornBrass = "rbxassetid://1843027503", -- Epic Depth Brass (APM Music): a deep brass swell, 9.8 s (decays from 3 s)
	-- Build 36: an electric guitar on its own (the Build 35 pick was mostly drums).
	GuitarShred = "rbxassetid://1848258603", -- Own Your Way - Tag1b (APM Music): indie-rock riff, "guitar only", 4 s
	TrainHorn = "rbxassetid://9120247429", -- Train Horn 2, Diesel, Resonant, Singles (ProSoundEffects), 13 s
}
-- These library clips hold several hits in a row; play only the first and fade it out.
local CLIP_SECONDS: { [string]: number } = {
	Bottle = 0.4, Hit = 0.35, Shot = 0.5, Check = 0.5, Board = 0.6, Post = 1.05, Body = 0.28, Tap = 0.2, Land = 0.32,
	Oof = 0.5, -- Build 31: played deeper (slower), so the same burst runs longer. Build 32: 0.5 (was 0.4) with PITCH 0.76
	Post2 = 1.15, Post3 = 1.15, Post4 = 1.15, Post5 = 1.2, ShotThump = 0.3,
}
-- Where in the file each clip starts (seconds), for files with silence or a lead-in first.
-- Build 30: Body's thud sits 0.2-0.3 s into its file (measured), so the old clip played the
-- quiet lead-in only; CrowdOoh skips its first 0.35 s of near silence.
-- Build 31: the post takes' starts measured in Studio (PlaybackLoudness onset against the first take).
local CLIP_START: { [string]: number } = { Quack = 0.45, VikingHorn = 0.6, Shot = 0.17, Land = 0.07, Body = 0.17, CrowdOoh = 0.35, Post3 = 0.04, Post5 = 0.15, ShotThump = 0.17 }
-- Build 30: every gameplay clip is kept loaded. A Sound made for an id nothing else holds took
-- about 0.3 s to load (measured in Studio, more on a live server), so the rare ones (the shot,
-- the post, the oof, the crowd) were faded out by their clip timer before they had started.
local KEEP_LOADED = { "Hit", "Shot", "Land", "Oof", "Board", "Post", "Post2", "Post3", "Post4", "Post5", "Check", "Body", "Tap", "CrowdOoh", "Whistle", "RefWhistle", "Bottle", "Cheer", "Quack", "VikingHorn", "HornBrass", "GuitarShred" }
local POSTS = { "Post", "Post2", "Post3", "Post4", "Post5" }
local lastPost = 0
local lastPostOoh = 0 -- Build 39: the crowd's "ooh" at a post (see Fx.cue)
local POST_OOH_SPEED = 18 -- puck speed off the post that counts as a real chance (a shot leaves at 62+)
-- Build 40: the stands only react ("ooh" at a save or a post) in a real match, not in practice,
-- the drills or the pond (Main sets it as the mode changes).
local crowdReacts = true
local LOAD_WAIT = 0.35 -- a clip still loading after this long is skipped: a late impact is worse than none
-- Post: played about six semitones down (Build 28), so it rings like a thick steel pipe rather
-- than a thin one; its clip time above is stretched to match.
local PITCH: { [string]: number } = {
	Bottle = 1.45, Horn = 0.88, Body = 1.5, Tap = 1.05, Post = 0.7,
	-- Build 31: the extra post takes sit a little lower and heavier than the first.
	Post2 = 0.64, Post3 = 0.6, Post4 = 0.66, Post5 = 0.58,
	Oof = 0.76, -- Build 31: a deep gut-punch "oof" (it read as a higher "poof"). Build 32: 0.76 (was 0.82), a touch slower
	ShotThump = 0.62,
}

local PUCK = Config.Puck
local RIGHT_ANGLE_Z = CFrame.Angles(0, 0, math.pi / 2)

local folder: Folder
local puckPart: Part
local puckRing: Part
local puckShadow: Part
local trail: Trail
local trailGround = Color3.fromRGB(255, 255, 255)
local trailAir = Color3.fromRGB(40, 110, 255)
local trailShown: Color3? = nil
local crowdGroup: SoundGroup
local hornGroup: SoundGroup
local ambience: Sound
local ambienceReverb: ReverbSoundEffect
local busLevels: { [string]: number } = { sfx = 1, crowd = 1, horn = 1 }
local sparkHolder: Part
local sparks: ParticleEmitter
local confetti: { ParticleEmitter } = {}
local reduceParticles = false
local fans: { any } = {}
local cheerUntil = 0
local cheerParts: { BasePart } = {}
local cheerHomes: { CFrame } = {}
local cheerFrames: { CFrame } = {}
local cheerPhases: { number } = {}
local seenGoals: { [number]: boolean } = {}
local effectsVolume = 0.7
local impactsGroup: SoundGroup

local function makePart(name: string, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = folder
	return p
end

-- Build 38: the Blender-made celebration props (assets/props/party_props.py), kept as
-- ReplicatedStorage.PartyMeshes.<Prop>.<Region> MeshParts. Each region's Offset attribute is its
-- place round the prop origin and the folder's RestY the origin's height when it lies on the ice.
-- colors re-tints regions by name. nil when the templates are missing, so callers keep their
-- primitive props. Build 39: scale grows the prop (its parts, their offsets and its rest height).
type MeshProp = { parts: { BasePart }, offsets: { CFrame }, rest: number }
local function meshProp(name: string, parent: Instance, colors: { [string]: Color3 }?, scale: number?): MeshProp?
	local k = scale or 1
	local root = ReplicatedStorage:FindFirstChild("PartyMeshes")
	local template = root and root:FindFirstChild(name)
	if not template then
		return nil
	end
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	for _, src in template:GetChildren() do
		if src:IsA("BasePart") then
			local p = src:Clone()
			local tint = colors and colors[src.Name]
			if tint then
				p.Color = tint
			end
			if k ~= 1 then
				p.Size = src.Size * k
			end
			p.Parent = parent
			table.insert(parts, p)
			local at = src:GetAttribute("Offset")
			table.insert(offsets, if typeof(at) == "Vector3" then CFrame.new(at * k) else CFrame.identity)
		end
	end
	if #parts == 0 then
		return nil
	end
	local rest = template:GetAttribute("RestY")
	return { parts = parts, offsets = offsets, rest = (if type(rest) == "number" then rest else 0.35) * k }
end

local function applyVolumes()
	if not impactsGroup then
		return
	end
	impactsGroup.Volume = effectsVolume * busLevels.sfx
	crowdGroup.Volume = effectsVolume * busLevels.crowd
	hornGroup.Volume = effectsVolume * busLevels.horn
end

function Fx.init(parent: Instance)
	folder = Instance.new("Folder")
	folder.Name = "ActivePuck"
	folder.Parent = parent

	-- Mixer (vault: "Audio Mixer Settings with SoundGroups"): every sound plays through a bus
	-- the Audio settings control; Master scales them all.
	impactsGroup = Instance.new("SoundGroup")
	impactsGroup.Name = "Impacts"
	impactsGroup.Parent = SoundService
	crowdGroup = Instance.new("SoundGroup")
	crowdGroup.Name = "Crowd"
	crowdGroup.Parent = SoundService
	hornGroup = Instance.new("SoundGroup")
	hornGroup.Name = "Horn"
	hornGroup.Parent = SoundService
	-- Build 36: every goal sound plays in a big room: a light reverb and a faint slap-back echo
	-- off the far end, mixed well under the dry sound.
	local room = Instance.new("ReverbSoundEffect")
	room.DecayTime = 1.8
	room.Density = 0.8
	room.Diffusion = 0.85
	room.DryLevel = 0
	room.WetLevel = -11
	room.Priority = 1
	room.Parent = hornGroup
	local slap = Instance.new("EchoSoundEffect")
	slap.Delay = 0.16
	slap.Feedback = 0.12
	slap.DryLevel = 0
	slap.WetLevel = -20
	slap.Priority = 2
	slap.Parent = hornGroup
	applyVolumes()

	-- One silent Sound per gameplay clip holds it in memory, so each play starts at once.
	local keep = Instance.new("Folder")
	keep.Name = "KeepLoaded"
	keep.Parent = SoundService
	local preload: { Instance } = {}
	for _, kind in KEEP_LOADED do
		local keeper = Instance.new("Sound")
		keeper.Name = kind
		keeper.SoundId = SoundCatalog[kind]
		keeper.Volume = 0
		keeper.Parent = keep
		table.insert(preload, keeper)
	end
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(preload)
		end)
	end)

	-- Arena ambience: a few dozen people chatting in a big, mostly empty barn. A quiet crowd
	-- loop on the crowd bus, its highs rolled off (they are far away) and sent through a long
	-- reverb so it echoes round the rafters. Faded in on a rink, out in the menus.
	ambience = Instance.new("Sound")
	ambience.Name = "ArenaAmbience"
	ambience.SoundId = SoundCatalog.Ambience
	ambience.Looped = true
	ambience.Volume = 0
	ambience.PlaybackSpeed = 0.96
	ambience.SoundGroup = crowdGroup
	local eq = Instance.new("EqualizerSoundEffect")
	eq.LowGain, eq.MidGain, eq.HighGain = 1, 0, -5
	eq.Priority = 1
	eq.Parent = ambience
	ambienceReverb = Instance.new("ReverbSoundEffect")
	ambienceReverb.DecayTime = 3.2
	ambienceReverb.Density = 0.9
	ambienceReverb.Diffusion = 0.9
	ambienceReverb.DryLevel = -4
	ambienceReverb.WetLevel = 0
	ambienceReverb.Priority = 2
	ambienceReverb.Parent = ambience
	ambience.Parent = SoundService

	local d = PUCK.Radius * 2
	puckPart = makePart("Puck", Vector3.new(PUCK.Thickness, d, d), Color3.fromRGB(16, 16, 22))
	puckPart.Shape = Enum.PartType.Cylinder
	puckPart.CastShadow = true

	puckRing = makePart("HighContrastRing", Vector3.new(0.05, d + 1.6, d + 1.6), Color3.fromRGB(255, 226, 60))
	puckRing.Shape = Enum.PartType.Cylinder
	puckRing.Material = Enum.Material.Neon
	puckRing.Transparency = 1

	puckShadow = makePart("PuckShadow", Vector3.new(0.03, d + 0.3, d + 0.3), Color3.new(0, 0, 0))
	puckShadow.Shape = Enum.PartType.Cylinder
	puckShadow.Transparency = 0.65

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0, PUCK.Radius * 0.7)
	a0.Parent = puckPart
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 0, -PUCK.Radius * 0.7)
	a1.Parent = puckPart
	trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.18
	trail.Color = ColorSequence.new(Color3.fromRGB(120, 200, 255))
	trail.Transparency = NumberSequence.new(0.45, 1)
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.Enabled = false
	trail.Parent = puckPart

	sparkHolder = makePart("SparkHolder", Vector3.new(1, 1, 1), Color3.new(1, 1, 1))
	sparkHolder.Transparency = 1
	sparks = Instance.new("ParticleEmitter")
	sparks.Enabled = false
	sparks.Rate = 0
	sparks.Lifetime = NumberRange.new(0.2, 0.4)
	sparks.Speed = NumberRange.new(10, 26)
	sparks.SpreadAngle = Vector2.new(70, 70)
	sparks.Size = NumberSequence.new(0.35, 0)
	sparks.Color = ColorSequence.new(Color3.fromRGB(225, 242, 255))
	sparks.LightEmission = 0.4
	sparks.Acceleration = Vector3.new(0, -60, 0)
	sparks.Parent = sparkHolder

	local goalX = Config.Goal.X + 1
	local palette = {
		Color3.fromRGB(255, 142, 44),
		Color3.fromRGB(64, 214, 214),
		Color3.fromRGB(255, 226, 90),
		Color3.fromRGB(240, 90, 120),
	}
	for index, side in { -1, 1 } do
		local holder = makePart("ConfettiHolder", Vector3.new(1, 1, 1), Color3.new(1, 1, 1))
		holder.Transparency = 1
		holder.CFrame = CFrame.new(side * goalX, 7, 0)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Enabled = false
		emitter.Rate = 0
		emitter.Lifetime = NumberRange.new(1, 1.8)
		emitter.Speed = NumberRange.new(26, 52)
		emitter.SpreadAngle = Vector2.new(55, 55)
		emitter.Size = NumberSequence.new(0.5)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-260, 260)
		emitter.Acceleration = Vector3.new(0, -34, 0)
		emitter.Drag = 1.3
		emitter.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, palette[1]),
			ColorSequenceKeypoint.new(0.34, palette[2]),
			ColorSequenceKeypoint.new(0.67, palette[3]),
			ColorSequenceKeypoint.new(1, palette[4]),
		})
		emitter.Parent = holder
		confetti[index] = emitter
	end
end

function Fx.setFans(list: { any })
	fans = list
	table.clear(cheerParts)
	table.clear(cheerHomes)
	table.clear(cheerPhases)
	table.clear(cheerFrames) -- Build 37: a rink change mid-cheer left the old crowd's frames
	-- Only a sparse cluster animates, so one effect can never hurt match input.
	local step = math.max(1, math.floor(#fans / 110))
	for i = 1, #fans, step do
		local fan = fans[i]
		-- All parts of one fan share a phase so the body, head and hair jump together.
		for _, p in { fan.body, fan.head, fan.extra } do
			table.insert(cheerParts, p)
			table.insert(cheerHomes, p.CFrame)
			table.insert(cheerPhases, i * 0.7)
		end
		-- Build 37: and any extra parts (the Moon Base aliens' eyes and antenna stalk).
		for _, p in fan.more or {} do
			table.insert(cheerParts, p)
			table.insert(cheerHomes, p.CFrame)
			table.insert(cheerPhases, i * 0.7)
		end
	end
end

-- The puck is black, but white on dark ice where black would vanish.
local PUCK_BLACK = Color3.fromRGB(16, 16, 22)
local PUCK_WHITE = Color3.fromRGB(240, 242, 248)
local puckColor = PUCK_BLACK
local puckStyle: string? = nil
function Fx.setIceColor(ice: Color3)
	local dark = ice.R * 0.3 + ice.G * 0.59 + ice.B * 0.11 < 0.35
	puckColor = if dark then PUCK_WHITE else PUCK_BLACK
	if puckPart then
		Looks.dressPuck(puckPart, puckStyle, puckColor)
	end
end

-- The puck you see in your own games (your equipped Catalog "puck" item's style, nil = plain).
function Fx.setPuckStyle(style: string?)
	if style == puckStyle then
		return
	end
	puckStyle = style
	if puckPart then
		Looks.dressPuck(puckPart, puckStyle, puckColor)
	end
end

-- Build 37: the plain puck colour for this ice (black, or white on dark ice) and the equipped
-- puck style, so extra pucks can match. A styled puck's own Color is its base under the style
-- (white under the Galaxy decals), which is why copying it made extra pucks white.
function Fx.plainPuckColor(): Color3
	return puckColor
end

function Fx.puckStyle(): string?
	return puckStyle
end

-- Build 40: whether the crowd "oohs" at saves and posts (a real match only).
function Fx.setCrowdReacts(on: boolean)
	crowdReacts = on
end

function Fx.setHighContrast(on: boolean)
	puckRing.Transparency = if on then 0.25 else 1
end

function Fx.setReduceParticles(on: boolean)
	reduceParticles = on
end

-- Ambience for the place on screen: an echoing near-empty arena on every indoor rink, the
-- same chatter drier and further off on the outdoor pond, silence in the lobby.
local AMBIENCE_LEVEL = { Lobby = 0, Pond = 0.14 }
function Fx.setAmbience(map: string)
	if not ambience then
		return
	end
	local level = AMBIENCE_LEVEL[map] or 0.22 -- a loud stadium loop: kept low so it sits under the game
	ambienceReverb.WetLevel = if map == "Pond" then -9 else 0
	ambienceReverb.DecayTime = if map == "Pond" then 1.4 else 3.2
	if level > 0 and not ambience.IsPlaying then
		ambience.TimePosition = math.random() * 30
		ambience:Play()
	end
	local tween = TweenService:Create(ambience, TweenInfo.new(if level > 0 then 2.5 else 1), { Volume = level })
	tween:Play()
	if level == 0 then
		tween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed and ambience.Volume == 0 then
				ambience:Pause()
			end
		end)
	end
end

function Fx.setVolume(volume: number)
	effectsVolume = volume
	applyVolumes()
end

-- Per-bus levels from the Audio settings (0 to 1), multiplied by the master volume.
function Fx.setBus(name: string, level: number)
	busLevels[name] = level
	applyVolumes()
end

-- Puck trail colours: one for a puck sliding on the ice, one for a puck in the air.
function Fx.setTrailColors(ground: Color3, air: Color3)
	trailGround, trailAir = ground, air
end

local BUS_OF: { [string]: string } = {
	Horn = "horn",
	Siren = "horn",
	ShipHorn = "horn",
	GoalSiren = "horn",
	Cheer = "crowd",
	CrowdOoh = "crowd",
	AirHorn = "horn",
	RocketUp = "horn",
	FireworkBoom = "horn",
	Crackle = "horn",
	Quack = "horn",
	Goat = "horn",
	PartyHorn = "horn",
	VikingHorn = "horn",
	HornBrass = "horn",
	GuitarShred = "horn",
	TrainHorn = "horn",
}

-- Plays a clip from its start point once it has loaded, and fades it out at the end of its
-- window. The window is timed from when it really starts, never from when it was asked for.
local function startClip(sound: Sound, kind: string)
	local started = false
	local function go()
		if started or not sound.Parent then
			return
		end
		started = true
		sound.TimePosition = CLIP_START[kind] or 0
		sound:Play()
		local clip = CLIP_SECONDS[kind]
		if clip then
			task.delay(clip, function()
				if sound.Parent then
					TweenService:Create(sound, TweenInfo.new(0.08), { Volume = 0 }):Play()
					task.delay(0.1, function()
						if sound.Parent then
							sound:Destroy()
						end
					end)
				end
			end)
		end
	end
	if sound.IsLoaded then
		go()
		return
	end
	local asked = os.clock()
	sound.Loaded:Once(function()
		if os.clock() - asked <= LOAD_WAIT then
			go()
		elseif sound.Parent then
			sound:Destroy()
		end
	end)
	task.delay(LOAD_WAIT, function()
		if not started and sound.Parent then
			if sound.IsLoaded then
				go()
			else
				sound:Destroy()
			end
		end
	end)
end

local function playAt(kind: string, x: number, z: number, volume: number, pitch: number?): Sound?
	local id = SoundCatalog[kind]
	if not id or id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.RollOffMaxDistance = 220
	local bus = BUS_OF[kind]
	sound.SoundGroup = if bus == "horn" then hornGroup elseif bus == "crowd" then crowdGroup else impactsGroup
	-- Build 30: each sound gets its own spot (it used to share the spark part, so every new
	-- tap dragged a still-ringing post clank across the rink to the stick).
	local spot = Instance.new("Attachment")
	spot.Name = "Sfx"
	spot.Position = Vector3.new(x, 1, z)
	spot.Parent = workspace.Terrain
	sound.Parent = spot
	sound.Destroying:Once(function()
		-- Build 36: deferred; destroying the spot while the sound is mid-destroy threw
		-- "The Parent property of Sfx.Sound is locked" on every sound.
		task.defer(function()
			spot:Destroy()
		end)
	end)
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(6, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	sound.PlaybackSpeed = (PITCH[kind] or 1) * (pitch or 1)
	startClip(sound, kind)
	return sound
end

-- Makes the goal horn electric: a buzzy edge, a wide chorus, a fast pulse and a brighter top.
local function electrify(sound: Sound)
	local eq = Instance.new("EqualizerSoundEffect")
	eq.LowGain, eq.MidGain, eq.HighGain = -3, 1, 5
	eq.Priority = 4
	eq.Parent = sound
	local buzz = Instance.new("DistortionSoundEffect")
	buzz.Level = 0.32
	buzz.Priority = 3
	buzz.Parent = sound
	local chorus = Instance.new("ChorusSoundEffect")
	chorus.Depth, chorus.Mix, chorus.Rate = 0.35, 0.5, 3
	chorus.Priority = 2
	chorus.Parent = sound
	local pulse = Instance.new("TremoloSoundEffect")
	pulse.Depth, pulse.Duty, pulse.Frequency = 0.5, 0.65, 9
	pulse.Priority = 1
	pulse.Parent = sound
end

-- Plays a sound heard the same wherever the camera is (not placed in the world).
local function playFlat(kind: string, volume: number, pitch: number?): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = SoundCatalog[kind]
	sound.Volume = volume
	sound.PlaybackSpeed = (PITCH[kind] or 1) * (pitch or 1)
	local bus = BUS_OF[kind]
	sound.SoundGroup = if bus == "horn" then hornGroup elseif bus == "crowd" then crowdGroup else impactsGroup
	sound.Parent = SoundService
	local start = CLIP_START[kind]
	sound.TimePosition = start or 0
	sound:Play()
	if start and not sound.IsLoaded then
		sound.Loaded:Once(function()
			if sound.Parent then
				sound.TimePosition = start
			end
		end)
	end
	task.delay(8, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	return sound
end

-- Fades a sound out over `fade` seconds, starting `after` seconds from now, then removes it.
local function fadeOut(sound: Sound, after: number, fade: number)
	task.delay(after, function()
		if sound.Parent then
			TweenService:Create(sound, TweenInfo.new(fade), { Volume = 0 }):Play()
			task.delay(fade + 0.05, function()
				if sound.Parent then
					sound:Destroy()
				end
			end)
		end
	end)
end

-- The drink bottles on top of the nets (from the rink on show). A top-shelf shot pops one up
-- off the net; it tumbles down onto the ice and lies there until the next faceoff.
type BottleState = { model: Model, home: CFrame, base: CFrame, conn: RBXScriptConnection?, pops: number }
local bottles: { BottleState } = {}

local function restoreBottle(b: BottleState)
	if b.conn then
		b.conn:Disconnect()
		b.conn = nil
	end
	b.model:PivotTo(b.home)
end

function Fx.setBottles(list: { Model })
	for _, b in bottles do
		restoreBottle(b)
	end
	bottles = {}
	for _, m in list or {} do
		table.insert(bottles, { model = m, home = m:GetPivot(), base = m:GetPivot(), conn = nil, pops = 0 })
	end
end

-- Back on the nets where the rink put them (the middle of each net top).
function Fx.resetBottles()
	for _, b in bottles do
		b.home = b.base
		b.pops += 1
		restoreBottle(b)
	end
end

-- Build 36: practice puts a net's bottle back on top at `z` across it (side: +1 / -1 net).
function Fx.placeBottle(side: number, z: number)
	for _, b in bottles do
		if math.sign(b.base.Position.X) == side then
			b.home = b.base + Vector3.new(0, 0, z)
			b.pops += 1 -- cancels a pending put-back
			restoreBottle(b)
		end
	end
end

local function popBottle(x: number, z: number, strength: number)
	local best, bestDist = nil, 10
	for _, b in bottles do
		local p = b.home.Position
		local d = math.sqrt((p.X - x) ^ 2 + (p.Z - z) ^ 2)
		if d < bestDist then
			best, bestDist = b, d
		end
	end
	if not best then
		return
	end
	local b = best :: BottleState
	restoreBottle(b)
	local rng = Random.new()
	local side = math.sign(b.home.Position.X)
	-- Up and back off the net, spinning end over end.
	local vel = Vector3.new(side * rng:NextNumber(5, 9), rng:NextNumber(24, 30) + math.min(strength, 80) * 0.05, rng:NextNumber(-5, 5))
	local spinAxis = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 0.3), rng:NextNumber(-1, 1)).Unit
	local spinRate = rng:NextNumber(10, 16)
	local pos = b.home.Position
	local rot = b.home - b.home.Position
	local bounced = false
	b.conn = RunService.Heartbeat:Connect(function(dt: number)
		dt = math.min(dt, 1 / 20)
		vel += Vector3.new(0, -70 * dt, 0)
		pos += vel * dt
		rot = CFrame.fromAxisAngle(spinAxis, spinRate * dt) * rot
		if pos.Y <= 0.44 and vel.Y < 0 then
			if not bounced then
				-- One little hop off the ice, then it rolls to a stop on its side.
				bounced = true
				pos = Vector3.new(pos.X, 0.44, pos.Z)
				vel = Vector3.new(vel.X * 0.4, -vel.Y * 0.28, vel.Z * 0.4)
				spinRate *= 0.4
			else
				local yaw = select(2, rot:ToEulerAnglesYXZ())
				-- Lying on its side: the axis (through the pivot) at the body's radius off the ice.
				b.model:PivotTo(CFrame.new(pos.X, 0.44, pos.Z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, math.pi / 2))
				if b.conn then
					b.conn:Disconnect()
					b.conn = nil
				end
				return
			end
		end
		b.model:PivotTo(CFrame.new(pos) * rot)
	end)
	playAt("Bottle", b.home.Position.X, b.home.Position.Z, 0.7)
	-- Practice has no faceoffs: put it back on the net after a while anyway.
	b.pops += 1
	local pop = b.pops
	task.delay(15, function()
		if b.pops == pop and b.model.Parent then
			restoreBottle(b)
		end
	end)
end

-- A skater hit by the puck lets out an "oof", at most one every half second.
local lastOof = 0
local function oof(x: number, z: number, strength: number)
	local now = os.clock()
	if now - lastOof < 0.5 then
		return
	end
	lastOof = now
	-- Build 31: louder (was 0.55-0.9) and deeper (PITCH.Oof), with only a little variation.
	playAt("Oof", x, z, math.clamp(strength / 30, 1.1, 1.6), 0.96 + math.random() * 0.08)
end

-- kind is one of Hit, Shot, Board, Post, Check, Body, Save, Bottle, Land.
function Fx.cue(kind: string, x: number, z: number, strength: number)
	if kind == "Bottle" then
		popBottle(x, z, strength)
		return
	end
	if kind == "Save" then
		-- A shot on net was stopped: the stands go "ohh" so everyone knows there was a chance,
		-- and the goalie grunts as it hits them (unless a body hit already did just now).
		-- Build 30: louder take, well above the arena walla (it was lost under it).
		if crowdReacts then
			local ooh = playFlat("CrowdOoh", 2.2)
			fadeOut(ooh, 1.9, 0.7)
		end
		oof(x, z, 60)
		return
	end
	if kind == "Land" then
		-- A puck dropping back to the ice: a flat smack, louder from higher up. No sparks.
		playAt("Land", x, z, math.clamp(strength / 10, 0.8, 1.8), 0.95 + math.random() * 0.1)
		return
	end
	if kind == "BodyAir" then
		-- Build 31: a puck in the air into a skater: the thud and an "oof". Along the ice (skating
		-- into it to pick it up) it is only the thud.
		oof(x, z, strength)
		kind = "Body"
	end
	if kind == "Shot" then
		-- Build 31: more violent: a low whack under the crack, and the crack itself fuller and grittier.
		playAt("ShotThump", x, z, math.clamp(0.4 + strength / 120, 0.8, 1.3), 0.95 + math.random() * 0.1)
	end
	local soundKind = kind
	if kind == "Post" then
		-- Build 31: one of five takes, never the same one twice in a row.
		local pick = math.random(1, #POSTS - 1)
		if lastPost > 0 and pick >= lastPost then
			pick += 1
		elseif lastPost == 0 then
			pick = math.random(1, #POSTS)
		end
		lastPost = pick
		soundKind = POSTS[pick]
		-- Build 39: a real ring off the iron gets the same crowd "ooh" as a save (once per clang:
		-- a puck rattling between the posts sends several Post cues; a slow nudge sends none).
		local now = os.clock()
		if crowdReacts and strength >= POST_OOH_SPEED and now - lastPostOoh > 1.5 then
			lastPostOoh = now
			local ooh = playFlat("CrowdOoh", 2.2)
			fadeOut(ooh, 1.9, 0.7)
		end
	end
	-- Build 30 levels, set against the stick tap (which stays as it was) from measured clip peaks:
	-- the shot crack is about twice a tap, the post clank rings out well over everything else,
	-- and a puck off a stick (the "dink") is a touch louder than before.
	local volume = if kind == "Shot" then math.clamp(0.7 + strength / 100, 1.25, 1.8)
		elseif kind == "Post" then math.clamp(2.2 + strength / 40, 2.4, 4.5)
		elseif kind == "Hit" then math.clamp(strength / 90, 0.15, 1) * 1.2
		else math.clamp(strength / 90, 0.15, 1)
	local sound = playAt(soundKind, x, z, volume, if kind == "Shot" then 0.94 + math.random() * 0.1 else nil)
	if sound and kind == "Shot" then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain, eq.MidGain, eq.HighGain = 5, 2, 2
		eq.Priority = 2
		eq.Parent = sound
		local grit = Instance.new("DistortionSoundEffect")
		grit.Level = 0.2
		grit.Priority = 1
		grit.Parent = sound
	end
	if sound and kind == "Post" then
		-- Carries across the whole rink instead of fading out with distance from the camera.
		sound.RollOffMinDistance = 40
		sound.RollOffMaxDistance = 400
		-- More body, less ping: lift the lows and soften the bright top of the clank.
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = 5
		eq.MidGain = 1
		eq.HighGain = -7
		eq.Parent = sound
	end
	local count = if kind == "Shot" then 14 elseif kind == "Check" then 16 elseif kind == "Board" or kind == "Post" then 7 else 4
	if reduceParticles then
		count = math.ceil(count / 3)
	end
	sparkHolder.CFrame = CFrame.new(x, 0.4, z)
	sparks:Emit(count)
	-- No shake for body hits (checking or being checked): it read as the camera lurching.
	if kind == "Post" then
		CameraRig.kick(0.25)
	end
end

function Fx.whistle()
	playAt("Whistle", 0, 0, 0.5)
end

-- The referee's whistle as the players line up for a face-off: one sharp blast, heard the same
-- wherever the camera is (not placed in the world), trimmed so its tail doesn't drag on.
function Fx.refereeWhistle()
	local sound = Instance.new("Sound")
	sound.SoundId = SoundCatalog.RefWhistle
	sound.Volume = 0.75
	sound.SoundGroup = impactsGroup
	sound.Parent = SoundService
	sound:Play()
	fadeOut(sound, 1.1, 0.25)
end

-- Stick lift: a faint tick as the blade leaves the ice, a tap as it comes back down.
function Fx.stickTap(x: number, z: number, down: boolean, own: boolean)
	-- A real stick tapping the ice at its own pitch: a solid knock with body, a touch brighter
	-- on top so it cuts through, with only the deepest rumble trimmed.
	local volume = (if down then 0.55 else 0.16) * (if own then 1 else 0.6)
	local sound = playAt("Tap", x, z, volume, if down then 1 else 1.15)
	if sound then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain, eq.MidGain, eq.HighGain = -3, 0, 2
		eq.Parent = sound
	end
end

---------------------------------------------------------------------------------------------
-- Goal celebration: the arena lights drop, a spotlight follows the scorer, and on a hat
-- trick the crowd throws caps onto the ice.
---------------------------------------------------------------------------------------------

local DIM = {
	Brightness = 0,
	Ambient = Color3.fromRGB(92, 100, 146),
	OutdoorAmbient = Color3.fromRGB(92, 100, 146),
	EnvironmentDiffuseScale = 0,
	EnvironmentSpecularScale = 0,
}
local dimBase: { [string]: any }? = nil
local dimLevel = 0
local celebrateUntil = 0
local spotShow = true -- Build 37: false on the shop rinks, which have their own celebration
local spotPart: Part? = nil
local spotLight: SpotLight? = nil
-- The pool of light on the ice: three glowing discs, brightest in the middle, for a soft edge.
local spotDiscs: { Part } = {}
local SPOT_DISCS = { { 16.5, 0.82, 0.05 }, { 13.5, 0.62, 0.06 }, { 10.5, 0.3, 0.07 } } -- diameter, transparency, height
local spotX, spotZ = 0, 0
local lastFxClock = os.clock()

type Cap = { parts: { BasePart }, offsets: { CFrame }, from: Vector3, to: Vector3, start: number, time: number, arc: number, spin: CFrame, rest: CFrame }
local caps: { Cap } = {}
local capParts: { BasePart } = {}
local capFrames: { CFrame } = {}
local capFolder: Folder? = nil
local CAP_COLORS = {
	Color3.fromRGB(214, 48, 52),
	Color3.fromRGB(28, 30, 38),
	Color3.fromRGB(238, 240, 246),
	Color3.fromRGB(40, 104, 214),
	Color3.fromRGB(214, 48, 52),
	Color3.fromRGB(28, 30, 38),
}

local function clearCaps()
	if capFolder then
		capFolder:Destroy()
		capFolder = nil
	end
	table.clear(caps)
	table.clear(capParts)
	table.clear(capFrames)
end

local function throwCaps(aroundX: number, aroundZ: number)
	clearCaps()
	local holder = Instance.new("Folder")
	holder.Name = "HatTrick"
	holder.Parent = folder
	capFolder = holder
	local rng = Random.new()
	local hx, hz = Config.Arena.Length / 2, Config.Arena.Width / 2
	local now = os.clock()
	local count = if reduceParticles then 18 else 46
	for i = 1, count do
		local color = CAP_COLORS[(i - 1) % #CAP_COLORS + 1]
		-- A cap: a squashed dome with a short brim out the front.
		local dome = makePart("Cap", Vector3.new(1.5, 1.5, 1.5), color)
		dome.Shape = Enum.PartType.Ball
		dome.Parent = holder
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(1, 0.62, 1)
		mesh.Parent = dome
		local brim = makePart("Brim", Vector3.new(1.1, 0.12, 0.9), if i % 3 == 0 then Color3.fromRGB(238, 240, 246) else color)
		brim.Parent = holder
		-- Thrown from the stands on either long side, landing scattered around the scorer.
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local from = Vector3.new(math.clamp(aroundX + rng:NextNumber(-55, 55), -hx, hx), rng:NextNumber(10, 20), side * (hz + rng:NextNumber(4, 16)))
		local to = Vector3.new(
			math.clamp(aroundX + rng:NextNumber(-34, 34), -hx + 6, hx - 6),
			0.3,
			math.clamp(aroundZ + rng:NextNumber(-26, 26), -hz + 5, hz - 5)
		)
		local cap: Cap = {
			parts = { dome, brim },
			offsets = { CFrame.identity, CFrame.new(0, -0.22, -0.95) },
			from = from,
			to = to,
			start = now + rng:NextNumber(0.15, 1.5),
			time = rng:NextNumber(0.9, 1.5),
			arc = rng:NextNumber(8, 16),
			spin = CFrame.Angles(rng:NextNumber(-9, 9), rng:NextNumber(-9, 9), rng:NextNumber(-9, 9)),
			rest = CFrame.Angles(rng:NextNumber(-0.12, 0.12), rng:NextNumber(0, 6.28), rng:NextNumber(-0.12, 0.12)),
		}
		table.insert(caps, cap)
		for _, p in cap.parts do
			p.CFrame = CFrame.new(from)
			table.insert(capParts, p)
		end
	end
end

local function stepCaps(now: number)
	if #caps == 0 then
		return
	end
	local n = 0
	for _, cap in caps do
		local t = math.clamp((now - cap.start) / cap.time, 0, 1)
		local at: CFrame
		if t >= 1 then
			at = CFrame.new(cap.to) * cap.rest
		else
			local pos = cap.from:Lerp(cap.to, t) + Vector3.new(0, math.sin(t * math.pi) * cap.arc, 0)
			local rx, ry, rz = cap.spin:ToEulerAnglesXYZ()
			at = CFrame.new(pos) * CFrame.Angles(rx * (1 - t), ry * (1 - t), rz * (1 - t)) * cap.rest
		end
		for i, offset in cap.offsets do
			n += 1
			capFrames[n] = at * offset
		end
	end
	workspace:BulkMoveTo(capParts, capFrames, Enum.BulkMoveMode.FireCFrameChanged)
end

local function stepCelebration(now: number, dt: number)
	local want = if now < celebrateUntil and spotShow then 1 else 0
	if want == 0 and dimLevel <= 0 then
		return
	end
	if not dimBase then
		-- Remember the arena's own lighting the moment the lights start to drop.
		local base = {}
		for key in DIM do
			base[key] = (Lighting :: any)[key]
		end
		dimBase = base
	end
	dimLevel = math.clamp(dimLevel + (if want == 1 then dt / 0.3 else -dt / 0.45), 0, 1)
	local base = dimBase :: { [string]: any }
	local k = dimLevel * dimLevel * (3 - 2 * dimLevel)
	-- Set every frame while dimmed, so a lighting refresh from a match update can't undo it.
	for key, dark in DIM do
		local from = base[key]
		if typeof(from) == "Color3" then
			(Lighting :: any)[key] = (from :: Color3):Lerp(dark, k)
		else
			(Lighting :: any)[key] = from + (dark - from) * k
		end
	end
	if not spotPart then
		local part = makePart("Spotlight", Vector3.new(1, 1, 1), Color3.new(1, 1, 1))
		part.Transparency = 1
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Bottom
		light.Angle = 26
		light.Range = 60
		light.Color = Color3.fromRGB(255, 250, 240)
		light.Shadows = false
		light.Parent = part
		spotPart, spotLight = part, light
		for i, spec in SPOT_DISCS do
			local disc = makePart("SpotPool", Vector3.new(0.02, spec[1], spec[1]), Color3.fromRGB(255, 255, 250))
			disc.Shape = Enum.PartType.Cylinder
			disc.Material = Enum.Material.Neon
			disc.Transparency = 1
			spotDiscs[i] = disc
		end
	end
	(spotPart :: Part).CFrame = CFrame.new(spotX, 26, spotZ)
	local light = spotLight :: SpotLight
	light.Brightness = 3 * k
	light.Enabled = k > 0.02
	for i, disc in spotDiscs do
		local spec = SPOT_DISCS[i]
		disc.CFrame = CFrame.new(spotX, spec[3], spotZ) * RIGHT_ANGLE_Z
		disc.Transparency = 1 - (1 - spec[2]) * k
	end
	if dimLevel <= 0 then
		dimBase = nil
		clearCaps()
	end
end

---------------------------------------------------------------------------------------------
-- Build 37: a goal celebration for each shop rink. The classic rinks keep the lights-down and
-- spotlight; these get their own show instead (the goal sound plays the same everywhere):
--   MoonBase: no lights-down. The floodlights' beams sweep round the ice in circles and flicker
--     on and off fast (the lamps themselves stay put).
--   NeonArcade: a laser party, neon beams in every colour sweeping across the ice.
--   CandyLand: the crowd throws sweets onto the ice (a hat trick still brings the caps).
--   Volcano: the braziers round the boards erupt and lob glowing lava bombs that splash and
--     cool on the ice.
--   TropicalBeach: giant beach balls bounce across the ice under a shower of flower petals.
--   FrozenLake (Build 41): a frost shockwave rings out across the ice from the scorer and a
--     snow squall blows in over both shores.
---------------------------------------------------------------------------------------------
local PARTY_THEMES = { MoonBase = true, NeonArcade = true, CandyLand = true, Volcano = true, TropicalBeach = true, FrozenLake = true }
local rinkTheme = "Arena"
local floodLamps: { BasePart } = {}
local partyFolder: Folder? = nil
local partyTargets: { Attachment } = {}
local partyStep: ((now: number, t: number, dt: number) -> ())? = nil
local partyStart = 0
local partyEnd = 0
local partyHoldsCaps = false -- the thrown things (caps or sweets) go when the party ends
local HALF_L, HALF_W = Config.Arena.Length / 2, Config.Arena.Width / 2

local function clearParty()
	if partyFolder then
		partyFolder:Destroy()
		partyFolder = nil
	end
	for _, a in partyTargets do
		a:Destroy()
	end
	table.clear(partyTargets)
	partyStep = nil
	if partyHoldsCaps then
		partyHoldsCaps = false
		clearCaps()
	end
end

-- The rink on show (Main.client, whenever it changes): which celebration plays, and where the
-- Moon Base floodlights are.
function Fx.setRink(theme: string, model: Instance?)
	clearParty()
	rinkTheme = theme
	table.clear(floodLamps)
	if model and theme == "MoonBase" then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "FloodLamp" then
				table.insert(floodLamps, d)
			end
		end
	end
end

local function partyPart(name: string, size: Vector3, color: Color3): Part
	local p = makePart(name, size, color)
	p.Parent = partyFolder
	return p
end

-- A beam from `from` to an attachment on the terrain the step moves every frame.
local function partyBeam(from: Attachment, color: Color3, w0: number, w1: number, t0: number, t1: number): (Beam, Attachment)
	local target = Instance.new("Attachment")
	target.Name = "PartyTarget"
	target.Parent = workspace.Terrain
	table.insert(partyTargets, target)
	local beam = Instance.new("Beam")
	beam.Attachment0 = from
	beam.Attachment1 = target
	beam.Color = ColorSequence.new(color)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Width0, beam.Width1 = w0, w1
	beam.Transparency = NumberSequence.new(t0, t1)
	beam.Parent = partyFolder
	return beam, target
end

local function source(at: Vector3): (Part, Attachment)
	local src = partyPart("BeamSource", Vector3.new(0.5, 0.5, 0.5), Color3.new(1, 1, 1))
	src.Transparency = 1
	src.CFrame = CFrame.new(at)
	local a = Instance.new("Attachment")
	a.Parent = src
	return src, a
end

local function iceDisc(name: string, diameter: number, color: Color3): Part
	local d = partyPart(name, Vector3.new(0.05, diameter, diameter), color)
	d.Shape = Enum.PartType.Cylinder
	d.Material = Enum.Material.Neon
	d.Transparency = 1
	return d
end

-- Moon Base: one sweeping, flickering beam from every floodlight.
local function moonBeams()
	type B = { beam: Beam, target: Attachment, src: Part, light: SpotLight, pool: Part, home: Vector3, phase: number, dir: number, on: boolean, flip: number }
	local beams: { B } = {}
	for i, lamp in floodLamps do
		local src, a0 = source(lamp.Position)
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Front
		light.Angle = 28
		light.Range = 70
		light.Brightness = 5
		light.Color = Color3.fromRGB(225, 238, 255)
		light.Shadows = false
		light.Parent = src
		local beam, target = partyBeam(a0, Color3.fromRGB(225, 238, 255), 1.8, 17, 0.3, 0.82)
		local side = if lamp.Position.Z > 0 then 1 else -1
		table.insert(beams, {
			beam = beam,
			target = target,
			src = src,
			light = light,
			pool = iceDisc("BeamPool", 17, Color3.fromRGB(235, 244, 255)),
			home = Vector3.new(lamp.Position.X * 0.85, 0, side * HALF_W * 0.38),
			phase = i * 1.37,
			dir = if i % 2 == 0 then 1 else -1,
			on = true,
			flip = 0,
		})
	end
	partyStep = function(now: number, t: number)
		for _, b in beams do
			if now >= b.flip then
				b.on = math.random() < 0.68
				b.flip = now + 0.05 + math.random() * 0.11
			end
			local a = b.phase + t * 3.4 * b.dir
			local at = b.home + Vector3.new(math.cos(a) * 17, 0.06, math.sin(a) * 13)
			b.target.WorldPosition = at
			b.src.CFrame = CFrame.lookAt(b.src.Position, at)
			b.pool.CFrame = CFrame.new(at) * RIGHT_ANGLE_Z
			b.beam.Enabled = b.on
			b.light.Enabled = b.on
			b.pool.Transparency = if b.on then 0.66 else 1
		end
	end
end

-- Neon Arcade: lasers from rigs high over the stands, three beams each, sweeping the ice.
local LASER_COLORS = {
	Color3.fromRGB(255, 50, 180),
	Color3.fromRGB(40, 230, 255),
	Color3.fromRGB(90, 255, 110),
	Color3.fromRGB(255, 230, 60),
	Color3.fromRGB(170, 90, 255),
	Color3.fromRGB(255, 120, 40),
}
local function laserShow()
	type L = { beam: Beam, target: Attachment, dot: Part, phase: number, fx: number, fz: number, color: number }
	local lasers: { L } = {}
	local rigs: { Vector3 } = {}
	for _, x in { -96, -48, 0, 48, 96 } do
		for _, sz in { -1, 1 } do
			table.insert(rigs, Vector3.new(x, 44, sz * (HALF_W + 26)))
		end
	end
	table.insert(rigs, Vector3.new(-(HALF_L + 22), 44, 0))
	table.insert(rigs, Vector3.new(HALF_L + 22, 44, 0))
	local n = 0
	for i, at in rigs do
		local _, a0 = source(at)
		for j = 1, if reduceParticles then 2 else 3 do
			n += 1
			local color = (n - 1) % #LASER_COLORS + 1
			local beam, target = partyBeam(a0, LASER_COLORS[color], 0.32, 0.32, 0.05, 0.15)
			local dot = partyPart("LaserDot", Vector3.new(1, 1, 1), LASER_COLORS[color])
			dot.Shape = Enum.PartType.Ball
			dot.Material = Enum.Material.Neon
			table.insert(lasers, { beam = beam, target = target, dot = dot, phase = i * 0.9 + j * 2.1, fx = 1.3 + j * 0.35, fz = 0.9 + j * 0.3 + i * 0.03, color = color })
		end
	end
	partyStep = function(_now: number, t: number)
		local shift = math.floor(t * 2.5) -- the colours step round the rigs a few times a second
		for _, l in lasers do
			local at = Vector3.new(math.sin(t * l.fx + l.phase) * HALF_L * 0.8, 0.3, math.cos(t * l.fz + l.phase * 1.7) * HALF_W * 0.75)
			l.target.WorldPosition = at
			l.dot.CFrame = CFrame.new(at)
			local c = LASER_COLORS[(l.color + shift - 1) % #LASER_COLORS + 1]
			l.beam.Color = ColorSequence.new(c)
			l.dot.Color = c
		end
	end
end

-- Candy Land: sweets thrown from the stands, landing round the scorer (the caps' flight).
local SWEET_COLORS = {
	Color3.fromRGB(255, 80, 150),
	Color3.fromRGB(110, 200, 255),
	Color3.fromRGB(255, 214, 60),
	Color3.fromRGB(130, 230, 140),
	Color3.fromRGB(190, 120, 255),
	Color3.fromRGB(255, 140, 70),
}
local SWEET_MESHES = { "WrappedSweet", "Lollipop", "Gumdrop", "CandyCane" }
local function throwSweets(aroundX: number, aroundZ: number)
	clearCaps()
	local holder = Instance.new("Folder")
	holder.Name = "Sweets"
	holder.Parent = folder
	capFolder = holder
	local rng = Random.new()
	local now = os.clock()
	local count = if reduceParticles then 22 else 56
	for i = 1, count do
		local color = SWEET_COLORS[(i - 1) % #SWEET_COLORS + 1]
		local parts: { BasePart } = {}
		local offsets: { CFrame } = {}
		local function piece(p: Part, offset: CFrame)
			p.Parent = holder
			table.insert(parts, p)
			table.insert(offsets, offset)
		end
		local kind = i % 4
		local mesh = meshProp(SWEET_MESHES[kind + 1], holder, {
			Body = color,
			Wrapper = color:Lerp(Color3.new(1, 1, 1), 0.45),
			SwirlA = color,
			Gumdrop = color,
		})
		if mesh then
			parts, offsets = mesh.parts, mesh.offsets
		elseif kind == 0 then
			-- A wrapped sweet: a round middle and a twist of wrapper at each end.
			local body = makePart("Sweet", Vector3.new(1.2, 0.8, 0.8), color)
			local m = Instance.new("SpecialMesh")
			m.MeshType = Enum.MeshType.Sphere
			m.Parent = body
			piece(body, CFrame.identity)
			for _, sx in { -1, 1 } do
				local twist = makePart("Wrapper", Vector3.new(0.5, 0.7, 0.7), color:Lerp(Color3.new(1, 1, 1), 0.45))
				local tm = Instance.new("SpecialMesh")
				tm.MeshType = Enum.MeshType.Wedge
				tm.Parent = twist
				piece(twist, CFrame.new(sx * 0.75, 0, 0) * CFrame.Angles(0, if sx > 0 then math.pi / 2 else -math.pi / 2, 0))
			end
		elseif kind == 1 then
			-- A lollipop: a swirl disc on a white stick.
			local pop = makePart("Lolly", Vector3.new(0.3, 1.7, 1.7), color)
			pop.Shape = Enum.PartType.Cylinder
			piece(pop, CFrame.identity)
			local swirl = makePart("Swirl", Vector3.new(0.32, 0.9, 0.9), Color3.new(1, 1, 1))
			swirl.Shape = Enum.PartType.Cylinder
			piece(swirl, CFrame.identity)
			piece(makePart("LollyStick", Vector3.new(0.18, 0.18, 1.6), Color3.fromRGB(250, 250, 250)), CFrame.new(0, 0, 1.5))
		elseif kind == 2 then
			-- A gumdrop.
			local drop = makePart("Gumdrop", Vector3.new(1.1, 0.95, 1.1), color)
			drop.Material = Enum.Material.Glass
			drop.Transparency = 0.1
			local m = Instance.new("SpecialMesh")
			m.MeshType = Enum.MeshType.Sphere
			m.Parent = drop
			piece(drop, CFrame.identity)
		else
			-- A little candy cane: a striped stem with a red hook at the top.
			piece(makePart("CaneStem", Vector3.new(0.3, 1.8, 0.3), Color3.fromRGB(250, 250, 250)), CFrame.identity)
			for k = -1, 1 do
				piece(makePart("CaneStripe", Vector3.new(0.33, 0.22, 0.33), Color3.fromRGB(226, 40, 52)), CFrame.new(0, k * 0.5, 0))
			end
			piece(makePart("CaneHook", Vector3.new(0.3, 0.3, 0.8), Color3.fromRGB(226, 40, 52)), CFrame.new(0, 0.9, -0.25))
		end
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local from = Vector3.new(math.clamp(aroundX + rng:NextNumber(-55, 55), -HALF_L, HALF_L), rng:NextNumber(10, 20), side * (HALF_W + rng:NextNumber(4, 16)))
		local to = Vector3.new(
			math.clamp(aroundX + rng:NextNumber(-36, 36), -HALF_L + 6, HALF_L - 6),
			if mesh then mesh.rest + 0.02 else 0.35,
			math.clamp(aroundZ + rng:NextNumber(-28, 28), -HALF_W + 5, HALF_W - 5)
		)
		local cap: Cap = {
			parts = parts,
			offsets = offsets,
			from = from,
			to = to,
			start = now + rng:NextNumber(0.05, 1.3),
			time = rng:NextNumber(0.8, 1.3),
			arc = rng:NextNumber(8, 16),
			spin = CFrame.Angles(rng:NextNumber(-9, 9), rng:NextNumber(-9, 9), rng:NextNumber(-9, 9)),
			-- Lying on the ice at some heading (the meshes are modelled lying down; the primitive
			-- props are turned on their side about Z).
			rest = CFrame.Angles(0, rng:NextNumber(0, 6.28), 0) * CFrame.Angles(0, 0, if mesh or kind == 2 then 0 else math.pi / 2),
		}
		table.insert(caps, cap)
		for _, p in parts do
			p.CFrame = CFrame.new(from)
			table.insert(capParts, p)
		end
	end
end

-- Volcano: every brazier round the boards bursts into flame and lobs lava bombs onto the ice,
-- where each splashes into a glowing puddle that cools and fades.
local BOMB_SCALE = 1.8 -- Build 39: bigger lava bombs (the user asked for bigger, and more of them)
local function eruption()
	type Bomb = { ball: Part, mesh: MeshProp?, spin: Vector3, from: Vector3, to: Vector3, start: number, time: number, arc: number, splat: Part, landed: boolean }
	local bombs: { Bomb } = {}
	local rng = Random.new()
	local now = os.clock()
	for _, sz in { -1, 1 } do
		for i = -2, 2 do
			local top = Vector3.new(i * 44 + 6, 10.5, sz * (HALF_W + 4.5))
			-- A burst of flame out of the bowl.
			local jet = partyPart("FlameJet", Vector3.new(2, 1, 2), Color3.new(1, 1, 1))
			jet.Transparency = 1
			jet.CFrame = CFrame.new(top)
			local flame = Instance.new("ParticleEmitter")
			flame.Rate = 0
			flame.Lifetime = NumberRange.new(0.5, 0.9)
			flame.Speed = NumberRange.new(18, 30)
			flame.SpreadAngle = Vector2.new(14, 14)
			flame.Acceleration = Vector3.new(0, -10, 0)
			flame.LightEmission = 1
			flame.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0.4) })
			flame.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 60, 10))
			flame.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
			flame.EmissionDirection = Enum.NormalId.Top
			flame.Parent = jet
			flame:Emit(if reduceParticles then 12 else 34)
			local glow = Instance.new("PointLight")
			glow.Color = Color3.fromRGB(255, 120, 40)
			glow.Range = 30
			glow.Brightness = 4
			glow.Parent = jet
			TweenService:Create(glow, TweenInfo.new(1.2), { Brightness = 0 }):Play()
			-- Build 39: twice as many bombs (two volleys' worth), each 1.8x the size.
			for _ = 1, if reduceParticles then 2 else 4 do
				local ball = partyPart("LavaBomb", Vector3.new(2.7, 2.7, 2.7), Color3.fromRGB(255, 120, 30))
				ball.Shape = Enum.PartType.Ball
				ball.Material = Enum.Material.Neon
				ball.CFrame = CFrame.new(top)
				local trail = Instance.new("ParticleEmitter")
				trail.Rate = 40
				trail.Lifetime = NumberRange.new(0.3, 0.6)
				trail.Speed = NumberRange.new(0.5, 2)
				trail.LightEmission = 0.8
				trail.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0.35) })
				trail.Color = ColorSequence.new(Color3.fromRGB(255, 160, 60), Color3.fromRGB(90, 70, 70))
				trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
				trail.Parent = ball
				-- Build 38: a craggy crust with lava glowing through its cracks, tumbling as it flies
				-- (the plain ball stays as the invisible carrier of the smoke trail).
				local mesh = meshProp("LavaBomb", ball.Parent :: Instance, nil, BOMB_SCALE)
				if mesh then
					ball.Transparency = 1
					for k, p in mesh.parts do
						p.CFrame = CFrame.new(top) * mesh.offsets[k]
					end
				end
				-- It flies to sit on the ice (its centre a radius up); the splat goes under it.
				local to = Vector3.new(rng:NextNumber(-HALF_L + 12, HALF_L - 12), 1.3, rng:NextNumber(-HALF_W + 8, HALF_W - 8))
				table.insert(bombs, {
					ball = ball,
					mesh = mesh,
					spin = Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(-9, 9), rng:NextNumber(-9, 9)),
					from = top,
					to = to,
					start = now + rng:NextNumber(0, 1.2),
					time = rng:NextNumber(0.9, 1.3),
					arc = rng:NextNumber(22, 34),
					splat = iceDisc("LavaSplat", rng:NextNumber(5.5, 8), Color3.fromRGB(255, 110, 30)),
					landed = false,
				})
			end
		end
	end
	local boom = playFlat("FireworkBoom", 0.7, 0.55)
	fadeOut(boom, 1.6, 0.8)
	partyStep = function(clock: number)
		for _, b in bombs do
			local t = math.clamp((clock - b.start) / b.time, 0, 1)
			if t < 1 then
				local pos = b.from:Lerp(b.to, t) + Vector3.new(0, math.sin(t * math.pi) * b.arc, 0)
				b.ball.CFrame = CFrame.new(pos)
				local mesh = b.mesh
				if mesh then
					local tt = t * b.time
					local at = CFrame.new(pos) * CFrame.Angles(b.spin.X * tt, b.spin.Y * tt, b.spin.Z * tt)
					for k, p in mesh.parts do
						p.CFrame = at * mesh.offsets[k]
					end
				end
			elseif not b.landed then
				b.landed = true
				b.ball.Transparency = 1
				if b.mesh then
					for _, p in b.mesh.parts do
						p.Transparency = 1
					end
				end
				local trail = b.ball:FindFirstChildOfClass("ParticleEmitter")
				if trail then
					trail.Enabled = false
				end
				b.splat.CFrame = CFrame.new(b.to.X, 0.06, b.to.Z) * RIGHT_ANGLE_Z
				b.splat.Transparency = 0.05
				-- Cools from glowing orange to dark crust, then fades.
				TweenService:Create(b.splat, TweenInfo.new(1.4), { Color = Color3.fromRGB(70, 30, 24) }):Play()
				TweenService:Create(b.splat, TweenInfo.new(0.6, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 1.2), { Transparency = 1 }):Play()
			end
		end
	end
end

-- Tropical Beach: big striped beach balls dropped over the ice, bouncing and rolling, and a
-- shower of hibiscus petals from both sides.
local BALL_BANDS = { Color3.fromRGB(255, 72, 72), Color3.fromRGB(52, 160, 255), Color3.fromRGB(255, 204, 48), Color3.fromRGB(90, 210, 110), Color3.fromRGB(255, 140, 60) }
local function beachParty(aroundX: number, aroundZ: number)
	type BeachBall = { parts: { BasePart }, offsets: { CFrame }, pos: Vector3, vel: Vector3, spin: CFrame, turn: CFrame, start: number }
	local balls: { BeachBall } = {}
	local moved: { BasePart } = {}
	local frames: { CFrame } = {}
	local rng = Random.new()
	local now = os.clock()
	local R = 2.4
	for i = 1, if reduceParticles then 4 else 8 do
		-- Build 38: the Blender beach ball (six inflated gores, three of them coloured, caps and a
		-- valve), its colours rotated ball to ball; the striped Ball part is the fallback.
		local parts: { BasePart }, offsets: { CFrame }
		local mesh = meshProp("BeachBall", partyFolder :: Instance, {
			Panel1 = BALL_BANDS[(i - 1) % #BALL_BANDS + 1],
			Panel2 = BALL_BANDS[i % #BALL_BANDS + 1],
			Panel3 = BALL_BANDS[(i + 1) % #BALL_BANDS + 1],
			Cap = BALL_BANDS[(i + 2) % #BALL_BANDS + 1],
		})
		if mesh then
			parts, offsets = mesh.parts, mesh.offsets
		else
			local shell = partyPart("BeachBall", Vector3.new(R * 2, R * 2, R * 2), Color3.fromRGB(252, 252, 250))
			shell.Shape = Enum.PartType.Ball
			local band1 = partyPart("BallBand", Vector3.new(R * 0.7, R * 2.04, R * 2.04), BALL_BANDS[i % #BALL_BANDS + 1])
			band1.Shape = Enum.PartType.Cylinder
			local band2 = partyPart("BallBand", Vector3.new(R * 0.55, R * 2.03, R * 2.03), BALL_BANDS[(i + 1) % #BALL_BANDS + 1])
			band2.Shape = Enum.PartType.Cylinder
			parts, offsets = { shell, band1, band2 }, { CFrame.identity, CFrame.identity, CFrame.Angles(0, math.pi / 2, 0) }
		end
		local ball: BeachBall = {
			parts = parts,
			offsets = offsets,
			pos = Vector3.new(math.clamp(aroundX + rng:NextNumber(-40, 40), -HALF_L + 10, HALF_L - 10), rng:NextNumber(34, 48), math.clamp(aroundZ + rng:NextNumber(-30, 30), -HALF_W + 8, HALF_W - 8)),
			vel = Vector3.new(rng:NextNumber(-14, 14), 0, rng:NextNumber(-10, 10)),
			spin = CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0),
			turn = CFrame.Angles(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4)),
			start = now + rng:NextNumber(0, 0.7),
		}
		for _, p in ball.parts do
			p.CFrame = CFrame.new(0, -50, 0)
			table.insert(moved, p)
		end
		table.insert(balls, ball)
	end
	-- Petals: two bursts over the side stands, drifting down onto the ice.
	for _, sz in { -1, 1 } do
		local cloud = partyPart("Petals", Vector3.new(HALF_L * 1.4, 1, 10), Color3.new(1, 1, 1))
		cloud.Transparency = 1
		cloud.CFrame = CFrame.new(0, 30, sz * (HALF_W - 6))
		local petals = Instance.new("ParticleEmitter")
		petals.Shape = Enum.ParticleEmitterShape.Box
		petals.Rate = 0
		petals.Lifetime = NumberRange.new(2.4, 3.4)
		petals.Speed = NumberRange.new(4, 10)
		petals.SpreadAngle = Vector2.new(60, 60)
		petals.Acceleration = Vector3.new(0, -5, 0)
		petals.Drag = 1.2
		petals.RotSpeed = NumberRange.new(-180, 180)
		petals.Rotation = NumberRange.new(0, 360)
		petals.Size = NumberSequence.new(0.55)
		petals.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 140)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 220, 80)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
		})
		petals.Parent = cloud
		petals:Emit(if reduceParticles then 50 else 140)
	end
	local last = now
	partyStep = function(clock: number)
		local dt = math.min(0.05, clock - last)
		last = clock
		local n = 0
		for _, b in balls do
			if clock >= b.start then
				b.vel += Vector3.new(0, -55 * dt, 0)
				b.pos += b.vel * dt
				if b.pos.Y < R then
					b.pos = Vector3.new(b.pos.X, R, b.pos.Z)
					b.vel = Vector3.new(b.vel.X * 0.9, math.abs(b.vel.Y) * 0.62, b.vel.Z * 0.9)
				end
				-- Off the boards.
				if math.abs(b.pos.X) > HALF_L - R - 2 then
					b.vel = Vector3.new(-b.vel.X, b.vel.Y, b.vel.Z)
					b.pos = Vector3.new(math.sign(b.pos.X) * (HALF_L - R - 2), b.pos.Y, b.pos.Z)
				end
				if math.abs(b.pos.Z) > HALF_W - R - 2 then
					b.vel = Vector3.new(b.vel.X, b.vel.Y, -b.vel.Z)
					b.pos = Vector3.new(b.pos.X, b.pos.Y, math.sign(b.pos.Z) * (HALF_W - R - 2))
				end
				local rx, ry, rz = b.turn:ToEulerAnglesXYZ()
				b.spin = b.spin * CFrame.Angles(rx * dt, ry * dt, rz * dt)
			end
			local at = CFrame.new(b.pos) * b.spin
			for i, offset in b.offsets do
				n += 1
				moved[n] = b.parts[i]
				frames[n] = at * offset
			end
		end
		workspace:BulkMoveTo(moved, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Frozen Lake (Build 41): two frost rings race out across the ice from the scorer, growing and
-- fading, a burst of ice shards jumps off the ice where they start, and snow blows in over both
-- shores and drifts down onto the rink.
local function frostSquall(aroundX: number, aroundZ: number)
	-- Each ring is a loop of short glowing ice slivers lying on the ice.
	local SEGMENTS = if reduceParticles then 16 else 28
	local rings: { { parts: { BasePart }, start: number } } = {}
	local moved: { BasePart } = {}
	local frames: { CFrame } = {}
	local now = os.clock()
	for i = 0, 1 do
		local ring = { parts = {}, start = now + i * 0.35 }
		for _ = 1, SEGMENTS do
			local sliver = partyPart("FrostRing", Vector3.new(1, 0.12, 0.5), Color3.fromRGB(190, 236, 255))
			sliver.Material = Enum.Material.Neon
			sliver.Transparency = 1
			sliver.CFrame = CFrame.new(0, -50, 0)
			table.insert(ring.parts, sliver)
		end
		table.insert(rings, ring)
	end
	local burst = partyPart("FrostBurst", Vector3.new(1, 1, 1), Color3.new(1, 1, 1))
	burst.Transparency = 1
	burst.CFrame = CFrame.new(aroundX, 0.5, aroundZ)
	local shards = Instance.new("ParticleEmitter")
	shards.Rate = 0
	shards.Lifetime = NumberRange.new(0.6, 1.1)
	shards.Speed = NumberRange.new(14, 26)
	shards.SpreadAngle = Vector2.new(70, 70)
	shards.EmissionDirection = Enum.NormalId.Top
	shards.Acceleration = Vector3.new(0, -40, 0)
	shards.RotSpeed = NumberRange.new(-300, 300)
	shards.Rotation = NumberRange.new(0, 360)
	shards.LightEmission = 0.6
	shards.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0.1) })
	shards.Color = ColorSequence.new(Color3.fromRGB(235, 250, 255), Color3.fromRGB(120, 200, 255))
	shards.Parent = burst
	shards:Emit(if reduceParticles then 20 else 60)
	for _, sz in { -1, 1 } do
		local cloud = partyPart("Squall", Vector3.new(HALF_L * 1.4, 1, 10), Color3.new(1, 1, 1))
		cloud.Transparency = 1
		cloud.CFrame = CFrame.new(0, 28, sz * (HALF_W - 6))
		local snow = Instance.new("ParticleEmitter")
		snow.Shape = Enum.ParticleEmitterShape.Box
		snow.Rate = 0
		snow.Lifetime = NumberRange.new(2.4, 3.4)
		snow.Speed = NumberRange.new(5, 12)
		snow.SpreadAngle = Vector2.new(50, 50)
		snow.Acceleration = Vector3.new(0, -6, -sz * 6)
		snow.Drag = 1
		snow.LightEmission = 0.3
		snow.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.25) })
		snow.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 232, 255))
		snow.Parent = cloud
		snow:Emit(if reduceParticles then 60 else 180)
	end
	partyStep = function(clock: number)
		local n = 0
		for _, ring in rings do
			local t = (clock - ring.start) / 1.4
			local radius = 2 + math.clamp(t, 0, 1) * 55
			local fade = if t < 0 or t > 1 then 1 else 0.15 + 0.85 * t
			local len = 2 * math.pi * radius / SEGMENTS * 0.8
			for k, sliver in ring.parts do
				local a = (k / SEGMENTS) * math.pi * 2
				n += 1
				moved[n] = sliver
				frames[n] = CFrame.new(aroundX + math.cos(a) * radius, 0.1, aroundZ + math.sin(a) * radius) * CFrame.Angles(0, -a + math.pi / 2, 0)
				sliver.Size = Vector3.new(len, 0.12, 0.5)
				sliver.Transparency = fade
			end
		end
		workspace:BulkMoveTo(moved, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function startParty(seconds: number, hatTrick: boolean, x: number, z: number)
	clearParty()
	local holder = Instance.new("Folder")
	holder.Name = "GoalParty"
	holder.Parent = folder
	partyFolder = holder
	partyStart = os.clock()
	partyEnd = partyStart + seconds + 0.5
	if rinkTheme == "MoonBase" then
		moonBeams()
	elseif rinkTheme == "NeonArcade" then
		laserShow()
	elseif rinkTheme == "Volcano" then
		eruption()
	elseif rinkTheme == "TropicalBeach" then
		beachParty(x, z)
	elseif rinkTheme == "FrozenLake" then
		frostSquall(x, z)
	end
	if hatTrick then
		throwCaps(x, z)
		partyHoldsCaps = true
	elseif rinkTheme == "CandyLand" then
		throwSweets(x, z)
		partyHoldsCaps = true
	end
end

local function stepParty(now: number, dt: number)
	if not partyFolder and not partyHoldsCaps then
		return
	end
	if now > partyEnd then
		clearParty()
		return
	end
	local step = partyStep
	if step then
		step(now, now - partyStart, dt)
	end
end

-- Where the spotlight points (the scorer), every frame of the celebration.
function Fx.setSpot(x: number, z: number)
	spotX, spotZ = x, z
end

function Fx.celebrating(): boolean
	return os.clock() < celebrateUntil
end

-- Ends the celebration early (a new phase began). instant: also put the lights straight back
-- (leaving the rink), instead of fading them up.
function Fx.endCelebration(instant: boolean?)
	celebrateUntil = 0
	if instant then
		if dimBase then
			for key, value in dimBase do
				(Lighting :: any)[key] = value
			end
		end
		dimBase = nil
		dimLevel = 0
		if spotLight then
			spotLight.Enabled = false
		end
		for _, disc in spotDiscs do
			disc.Transparency = 1
		end
		clearCaps()
		clearParty()
	end
end

-- Fireworks over a net: rockets streak up from behind it and burst high over the ice.
local function fireworkBurst(at: Vector3, color: Color3)
	local holder = makePart("Firework", Vector3.new(1, 1, 1), Color3.new(1, 1, 1))
	holder.Transparency = 1
	holder.CFrame = CFrame.new(at)
	local burst = Instance.new("ParticleEmitter")
	burst.Rate = 0
	burst.Lifetime = NumberRange.new(0.9, 1.4)
	burst.Speed = NumberRange.new(22, 30)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Drag = 2.2
	burst.Acceleration = Vector3.new(0, -9, 0)
	burst.LightEmission = 1
	burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.7, 0.45), NumberSequenceKeypoint.new(1, 0) })
	burst.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	burst.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.75, 0.2), NumberSequenceKeypoint.new(1, 1) })
	burst.Parent = holder
	local flash = Instance.new("PointLight")
	flash.Color = color
	flash.Range = 60
	flash.Brightness = 6
	flash.Parent = holder
	burst:Emit(if reduceParticles then 40 else 120)
	TweenService:Create(flash, TweenInfo.new(0.8), { Brightness = 0 }):Play()
	task.delay(2, function()
		holder:Destroy()
	end)
end

local function fireworkRocket(from: Vector3, to: Vector3, color: Color3, delay: number)
	task.delay(delay, function()
		local rocket = makePart("Rocket", Vector3.new(0.5, 0.5, 0.5), color)
		rocket.Material = Enum.Material.Neon
		rocket.Shape = Enum.PartType.Ball
		rocket.CFrame = CFrame.new(from)
		local tail = Instance.new("ParticleEmitter")
		tail.Rate = 60
		tail.Lifetime = NumberRange.new(0.3, 0.5)
		tail.Speed = NumberRange.new(0.5, 2)
		tail.SpreadAngle = Vector2.new(20, 20)
		tail.LightEmission = 1
		tail.Size = NumberSequence.new(0.4, 0)
		tail.Color = ColorSequence.new(Color3.fromRGB(255, 230, 160))
		tail.Parent = rocket
		local up = playFlat("RocketUp", 0.55, 0.95 + math.random() * 0.2)
		fadeOut(up, 0.9, 0.25)
		local rise = TweenService:Create(rocket, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(to) })
		rise:Play()
		rise.Completed:Once(function()
			rocket:Destroy()
			fireworkBurst(to, color)
			local boom = playFlat("FireworkBoom", 0.9, 1.05 + math.random() * 0.2)
			fadeOut(boom, 0.9, 0.5)
		end)
	end)
end

-- The goal sound: the scorer's equipped one (Catalog kind "goal"), or the arena horn.
function Fx.goalSound(sound: string?, side: number?)
	if sound == "AirHorn" then
		-- Stadium air horn blasts, with the electric edge the arena horn has.
		local blast = playFlat("AirHorn", 1.1)
		electrify(blast)
		fadeOut(blast, 4.2, 0.4)
	elseif sound == "RubberDucky" then
		-- Build 35: one solid quack. The clip holds two (measured: 0.1-0.35 s and a fuller one at
		-- 0.5-0.85 s), so start at the fuller one and fade before the tail.
		-- Build 36: a deeper duck (played at 0.8 speed, so the same quack lasts 1.25x longer).
		local q = playFlat("Quack", 1.7, 0.8)
		fadeOut(q, 0.48, 0.14)
	elseif sound == "BillyGoat" then
		-- Build 34: a big goat "baaaa", then a deeper one answering it.
		local a = playFlat("Goat", 1.4, 1)
		fadeOut(a, 1.4, 0.3)
		task.delay(0.9, function()
			local b = playFlat("Goat", 1.3, 0.78)
			fadeOut(b, 1.8, 0.4)
		end)
	elseif sound == "PartyPopper" then
		-- Build 35: the item is now "Guitar Shred" (its saved id stays PartyPopper): an electric
		-- hair-metal lick, cut before the band's tail.
		local g = playFlat("GuitarShred", 1.4, 1)
		fadeOut(g, 3.0, 0.6)
	elseif sound == "BoxPop" then
		-- The Mystery Box reveal (Build 34's party blowers, no longer a goal sound).
		for i, pitch in { 1, 1.14, 0.9 } do
			task.delay((i - 1) * 0.28, function()
				local h = playFlat("PartyHorn", 1.2, pitch)
				fadeOut(h, 1.5, 0.3)
			end)
		end
	elseif sound == "VikingHorn" then
		-- Build 35: loud but elegant and deep: a brass swell (the French-horn body) with a
		-- ram's horn under it, pitched down, for the raw Viking edge.
		local brass = playFlat("HornBrass", 1.5, 0.9)
		fadeOut(brass, 3.4, 1.2)
		local horn = playFlat("VikingHorn", 0.8, 0.7)
		fadeOut(horn, 1.3, 0.5)
	elseif sound == "ChooChoo" then
		-- Build 34: a diesel train horn, loud and long.
		local t = playFlat("TrainHorn", 1.5, 1)
		fadeOut(t, 3.4, 0.8)
	elseif sound == "Fireworks" then
		-- Three rockets go up from behind the net and burst over it, then a crackle.
		local s = side or 1
		local gx = s * (Config.Goal.X + 6)
		local colors = { Color3.fromRGB(255, 80, 120), Color3.fromRGB(80, 220, 255), Color3.fromRGB(255, 210, 70) }
		for i, z in { -10, 0, 10 } do
			fireworkRocket(Vector3.new(gx, 2, z * 0.6), Vector3.new(gx - s * 4, 34 + i * 3, z), colors[i], (i - 1) * 0.45)
		end
		task.delay(1.9, function()
			local crackle = playFlat("Crackle", 0.6)
			fadeOut(crackle, 2.2, 1)
		end)
	else
		-- The arena goal horn, loud and heard the same wherever the camera is: a deep ship horn
		-- held for one long blast with the electric air horn on top of it. The horn leads; a fast
		-- two-tone siren (wee-oo, wee-oo) goes off quieter behind it, its top end cut so it sits back.
		local ship = playFlat("ShipHorn", 2.4)
		fadeOut(ship, 3.9, 0.7)
		local horn = playFlat("Horn", 0.85)
		electrify(horn)
		fadeOut(horn, 3.4, 0.6)
		local siren = playFlat("GoalSiren", 0.3)
		local back = Instance.new("EqualizerSoundEffect")
		back.LowGain, back.MidGain, back.HighGain = -4, 0, -10
		back.Parent = siren
		fadeOut(siren, 3.6, 0.8)
	end
end

-- Fires once per authoritative goal id, however many times the event is replayed.
function Fx.goal(goalId: number, side: number, x: number, z: number, seconds: number?, hatTrick: boolean?, spotX0: number?, spotZ0: number?, sound: string?)
	if seenGoals[goalId] then
		return
	end
	seenGoals[goalId] = true
	Fx.goalSound(sound, side)
	playFlat("Cheer", 0.7)
	celebrateUntil = os.clock() + (seconds or 3)
	spotX, spotZ = spotX0 or x, spotZ0 or z
	-- Build 37: the shop rinks have their own show (no lights-down, no spotlight). Build 38: the
	-- Neon Arcade keeps the lights-down and the spotlight on the scorer under its lasers.
	local party = PARTY_THEMES[rinkTheme] == true
	spotShow = not party or rinkTheme == "NeonArcade"
	if party then
		startParty(seconds or 3, hatTrick == true, spotX, spotZ)
	elseif hatTrick then
		throwCaps(spotX, spotZ)
	end
	if hatTrick then
		cheerUntil = os.clock() + (seconds or 3)
	end
	CameraRig.kick(1)
	cheerUntil = os.clock() + 2.4
	local emitter = confetti[if side == 1 then 2 else 1]
	emitter:Emit(if reduceParticles then 24 else 90)
end

-- The pond: a goal horn at the net, no lights down and no confetti (other players are skating
-- all round the lake).
function Fx.horn(x: number, z: number)
	local horn = playAt("Horn", x, z, 0.35)
	if horn then
		electrify(horn)
	end
	playAt("Cheer", x, z, 0.3)
end

-- End of the game: the arena horn held for one long blast, heard the same wherever the camera
-- is (not placed in the world), a second voice a fifth above it, and the crowd behind it.
function Fx.finalHorn()
	fadeOut(playFlat("ShipHorn", 1.4), 2.6, 0.6)
	for _, voice in { { 0.55, 1 }, { 0.24, 1.5 } } do
		local sound = Instance.new("Sound")
		sound.SoundId = SoundCatalog.Horn
		sound.Volume = voice[1]
		sound.PlaybackSpeed = PITCH.Horn * voice[2]
		sound.SoundGroup = hornGroup
		sound.Parent = SoundService
		electrify(sound)
		sound:Play()
		fadeOut(sound, 2.4, 0.6)
	end
	local cheer = Instance.new("Sound")
	cheer.SoundId = SoundCatalog.Cheer
	cheer.Volume = 0.5
	cheer.SoundGroup = crowdGroup
	cheer.Parent = SoundService
	cheer:Play()
	fadeOut(cheer, 3, 1)
end

function Fx.puck(): BasePart
	return puckPart
end

function Fx.update(px: number, py: number, pz: number, vx: number, vz: number)
	local at = CFrame.new(px, py, pz) * RIGHT_ANGLE_Z
	puckPart.CFrame = at
	puckRing.CFrame = CFrame.new(px, 0.04, pz) * RIGHT_ANGLE_Z
	puckShadow.CFrame = CFrame.new(px, 0.035, pz) * RIGHT_ANGLE_Z
	trail.Enabled = not reduceParticles and vx * vx + vz * vz > 2200
	local color = if py > PUCK.Thickness then trailAir else trailGround
	if color ~= trailShown then
		trailShown = color
		trail.Color = ColorSequence.new(color)
	end

	local now = os.clock()
	local fxDt = math.min(0.1, now - lastFxClock)
	lastFxClock = now
	stepCelebration(now, fxDt)
	stepCaps(now)
	stepParty(now, fxDt)
	if now < cheerUntil and #cheerParts > 0 then
		for i, home in cheerHomes do
			local phase = cheerPhases[i]
			cheerFrames[i] = home + Vector3.new(0, math.abs(math.sin(now * 8 + phase)) * 1.1, 0)
		end
		workspace:BulkMoveTo(cheerParts, cheerFrames, Enum.BulkMoveMode.FireCFrameChanged)
	elseif cheerFrames[1] then
		workspace:BulkMoveTo(cheerParts, cheerHomes, Enum.BulkMoveMode.FireCFrameChanged)
		table.clear(cheerFrames)
	end
end

return Fx
