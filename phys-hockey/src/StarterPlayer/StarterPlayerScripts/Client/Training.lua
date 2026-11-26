--!strict
-- Training rink: a local World on the same Sim, isolated from the server match. The tutorial
-- is seven short drills (skate, dash, swing, dribble, pass, shoot, beat the goalie); each one
-- finishes by doing the thing, never by reading. Prompts name the player's own controls
-- (InputHints), a tip appears if a drill takes a while, and a lost puck comes back to the
-- player. Finishing pays the reward (the server checks and pays; see Config.Tutorial). Then
-- the player has free practice. Vault: "First-Time User Experience and Onboarding", "Tutorial
-- Step Design Patterns - Teach by Doing", "Onboarding Accessibility and Cross-Device Prompts".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("GameConfig"))
local Sim = require(Shared:WaitForChild("Sim"))
local BotBrain = require(Shared:WaitForChild("BotBrain"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Looks = require(Shared:WaitForChild("Looks"))
local Hud = require(script.Parent.Hud)
local Fx = require(script.Parent.Fx)
local InputHints = require(script.Parent.InputHints)

local Training = {}

local World = Sim.World
local TICK = Config.Tick
local PLAYER_START = Vector3.new(-34, 0, 0)
local PUCK_START = Vector3.new(0, 0, 0) -- Build 36: centre ice (was -16, on the far side from the goalie)
local COACH_SPOT = Vector3.new(56, 0, -18)
local GOAL_AT = Vector3.new(Config.Goal.X, 0, 0)
local GOAL2_AT = Vector3.new(-Config.Goal.X, 0, 0) -- Build 36: free practice's second goalie's net
local RING_RADIUS = 5
local TIP_AFTER = 20 -- seconds on one drill before its tip shows
local LOST_AFTER = 10 -- seconds a drill's puck sits untouched and far away before it comes back

local REWARD = Catalog.ById[Config.Tutorial.RewardItem]
local REWARD_NAME = string.upper(if REWARD then REWARD.name else "reward")

local world: Sim.World? = nil
local player: Sim.Skater
local goalie: Sim.Skater
local coach: Sim.Skater
local goalie2: Sim.Skater -- Build 36: free practice has a goalie in both nets
local goalieBrain = BotBrain.newState()
goalieBrain.easy = true -- practice is always you alone against the bot goalie
local goalie2Brain = BotBrain.newState()
goalie2Brain.easy = true
goalie2Brain.practice = true
-- Build 36: the drink bottles in practice: back on a random spot across each net top on a puck
-- reset (R), or 15 seconds after one is knocked off.
local bottleRng = Random.new()
local bottleBackAt: { [number]: number } = {}
local function freshBottle(w: Sim.World, side: number)
	local z = bottleRng:NextNumber(-4.2, 4.2)
	w.bottlesDown[side] = nil
	w.bottleZ[side] = z
	bottleBackAt[side] = nil
	Fx.placeBottle(side, z)
end
local marker: Part? = nil

-- Build 35: a glowing chevron on the ice at the player's feet, pointing at the ring to reach.
-- The camera turns with the skater, so an overshot ring ends up behind them with nothing on
-- screen to say where it went (vault "Tutorial Step Design Patterns - Teach by Doing": one
-- pointer at a time, for a target off screen). It sits by the feet, so it is always in view;
-- far enough out (and big enough) that the skater and stick never cover it from the camera.
local arrowTarget: Vector3? = nil
local arrowBars: { Part } = {}
local ARROW_COLOR = Color3.fromRGB(255, 142, 44)
local ARROW_HIDE = 9 -- closer than this to the ring's centre, the ring itself is the guide

local function makeArrow(parent: Instance)
	for _, side in { -1, 1 } do
		local bar = Instance.new("Part")
		bar.Name = "TrainingArrow"
		bar.Anchored = true
		bar.CanCollide = false
		bar.CanTouch = false
		bar.CanQuery = false
		bar.CastShadow = false
		bar.Material = Enum.Material.Neon
		bar.Color = ARROW_COLOR
		bar.Size = Vector3.new(0.7, 0.08, 3.2)
		bar.Transparency = 1
		bar:SetAttribute("Side", side)
		bar.Parent = parent
		table.insert(arrowBars, bar)
	end
end

local function placeArrow(at: Vector3)
	local target = arrowTarget
	local flat = if target then Vector3.new(target.X - at.X, 0, target.Z - at.Z) else Vector3.zero
	local show = target ~= nil and flat.Magnitude > ARROW_HIDE
	for _, bar in arrowBars do
		bar.Transparency = if show then 0.15 else 1
	end
	if not show then
		return
	end
	local dir = flat.Unit
	-- A gentle push toward the target, so it reads as "go this way".
	local pulse = 0.5 + 0.5 * math.sin(os.clock() * 7)
	local tip = Vector3.new(at.X, 0.1, at.Z) + dir * (7.5 + pulse * 1.0)
	local facing = CFrame.lookAt(tip, tip + dir)
	for _, bar in arrowBars do
		local side = bar:GetAttribute("Side") :: number
		-- Each bar runs back from the tip at 40 degrees: together a ">" pointing at the target.
		bar.CFrame = facing * CFrame.Angles(0, side * math.rad(40), 0) * CFrame.new(0, 0, 1.5)
	end
end

local function clearArrow()
	for _, bar in arrowBars do
		bar:Destroy()
	end
	table.clear(arrowBars)
	arrowTarget = nil
end
local step = 1
local swept = 0
local lastYaw = 0
local resetAt = 0
local saveUntil = 0 -- while > 0, a shot on target is on its way (world time it runs out)
local pondMode = false
local tutorialMode = false
local prevPos = Vector3.zero
local prevPuck = Vector3.zero
local drillTime = 0 -- seconds on the current drill
local tipShown = false
local touchedThisDrill = false
local drillStartPuck: Vector3? = nil -- where this drill put its puck (a reset puts it back there)
local missHinted = false
local sinceTouch = 0
local onDone: (() -> ())? = nil
local rewardClaimed = false -- a replay of the drills: no reward talk

-- Extra pucks (practice): each is its own little World sharing the same skaters, stepped
-- puck-only after the main one, so every stick and body plays all of them exactly the same way.
local MAX_EXTRA = 9
type Extra = { world: Sim.World, prev: Vector3, part: Part, resetAt: number }
local extras: { Extra } = {}
local extraFolder: Folder? = nil
local spawnCount = 0

type Drill = {
	title: string,
	text: () -> string,
	tip: () -> string,
	ring: Vector3?, -- the glowing ring to reach (or push the puck into)
	coach: boolean?, -- Coach Gus stands on the ice
	goalie: boolean?,
	-- Where the drill's puck starts (a reset puts it back there): "ahead" of the player toward the
	-- ring, "pass" a few strides toward Coach Gus, "shot" in the slot in front of the net, or
	-- "breakaway" on the blue line with the player set back behind it. Each is far enough away
	-- that a stick still swinging from the last drill can't knock it off (Build 29).
	puck: string?,
}

local function cap(s: string): string
	return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

-- How to bring the puck back on this device ("Press R", "Press X", "Tap PUCK").
local function resetHint(): string
	if InputHints.device() == "touch" then
		return "Tap PUCK"
	end
	return cap(InputHints.press("reset"))
end

local DRILLS: { Drill } = {
	{
		title = "SKATE",
		text = function()
			return `Skate into the glowing ring. Use {InputHints.move()}.`
		end,
		tip = function()
			return "Tip: you keep sliding on the ice, so start turning a little early."
		end,
		ring = Vector3.new(-12, 0, 18),
	},
	{
		title = "DASH",
		text = function()
			return `{cap(InputHints.hold("dash"))} to dash, and race into the next ring.`
		end,
		tip = function()
			return "Tip: dashing uses energy (the green bar). It fills back up on its own."
		end,
		ring = Vector3.new(22, 0, -16),
	},
	{
		title = "SWING",
		text = function()
			return `Swing your stick all the way round you with {InputHints.swing()}.`
		end,
		tip = function()
			local device = InputHints.device()
			return if device == "pad" then "Tip: roll the right stick round in a circle."
				elseif device == "touch" then "Tip: drag your right thumb round in a circle."
				else "Tip: keep moving the mouse the same way, left or right."
		end,
	},
	{
		title = "DRIBBLE",
		text = function()
			return "Dribble the puck into the ring. Keep it close to your stick as you skate."
		end,
		tip = function()
			return "Tip: skate slowly behind the puck and nudge it along with little swings."
		end,
		ring = Vector3.new(40, 0, 12),
		puck = "ahead",
	},
	{
		title = "PASS",
		text = function()
			return `Pass to Coach Gus on the ring. Swing through the puck toward him. Missed? {resetHint()} puts the puck back to try again.`
		end,
		tip = function()
			return "Tip: the faster you swing through the puck, the harder it goes."
		end,
		coach = true,
		puck = "pass",
	},
	{
		title = "SHOOT",
		text = function()
			return "Shoot! Get to the puck and swing hard through it at the empty net."
		end,
		tip = function()
			return "Tip: get close, face the net, then swing fast across the puck."
		end,
		puck = "shot",
	},
	{
		title = "BEAT THE GOALIE",
		text = function()
			return "Last one! Score on the goalie. Aim for the corners of the net."
		end,
		tip = function()
			return "Tip: skate to one side first, then shoot at the far corner."
		end,
		goalie = true,
		puck = "breakaway",
	},
}

local function showDrill()
	local drill = if tutorialMode then DRILLS[step] else nil
	if pondMode then
		local keys = if InputHints.device() == "touch" then "Tap PUCK to bring the puck back, or MENU to leave."
			else `{cap(InputHints.press("reset"))} to bring the puck back, or MENU to leave.`
		Hud.setObjective("THE POND", `Free skate on the outdoor rink. Score on either net, say hi to the penguins. {keys}`)
	elseif drill then
		local text = drill.text()
		if tipShown then
			text ..= "\n" .. drill.tip()
		end
		local reward = if rewardClaimed then "" else `   ·   REWARD: {REWARD_NAME}`
		Hud.setObjective(`STEP {step} OF {#DRILLS}: {drill.title}{reward}`, text)
	else
		local text = if InputHints.device() == "touch" then "Tap + PUCK for more pucks, GOALIE to bring a goalie in or out, PUCK to reset. MENU to leave."
			else `{cap(InputHints.press("addPuck"))} adds a puck, {InputHints.press("goalie")} brings a goalie in or out, {InputHints.press("reset")} resets the puck. MENU to leave.`
		Hud.setObjective("FREE PRACTICE", text)
	end
	local m = marker
	arrowTarget = if drill and drill.ring then drill.ring elseif drill and drill.coach then COACH_SPOT else nil
	if m then
		local spot = arrowTarget
		m.Transparency = if spot then 0.25 else 1
		if spot then
			m.CFrame = CFrame.new(spot + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		end
	end
end

InputHints.onChanged(function()
	if world then
		showDrill()
	end
end)

-- Free practice (after the drills, not the pond): a goal is quiet. No horn, light show or banner,
-- and the puck stays in the net for you to fish out and go again.
local function freePractice(): boolean
	return not pondMode and (not tutorialMode or DRILLS[step] == nil)
end

-- Once a quiet goal's puck is back out of the net, the next one can count again.
local function unlatchWhenOut(w: Sim.World)
	if w.goalLatched then
		local p = w.puck.pos
		local depthIn, across = Sim.netFrame(p.X, p.Z)
		local r = Config.Puck.Radius
		local inNet = depthIn > -r and depthIn < Config.Goal.Depth + r and Sim.insideNet(math.clamp(depthIn, 0, Config.Goal.Depth), across)
		if not inNet then
			w.goalLatched = false
		end
	end
end

local function placePuck(w: Sim.World, at: Vector3)
	World.placePuck(w, at)
	w.goalLatched = false
	w.touch1 = nil
	w.touch2 = nil
	table.clear(w.touchHistory)
end

local function placePuckAhead(w: Sim.World)
	placePuck(w, PUCK_START)
end

-- A spot a few studs from the player toward `target`, kept inside the rink.
local function nearPlayer(target: Vector3, ahead: number): Vector3
	local d = target - player.pos
	d = Vector3.new(d.X, 0, d.Z)
	local dir = if d.Magnitude > 0.1 then d.Unit else Vector3.new(1, 0, 0)
	local spot = player.pos + dir * ahead
	if not Sim.insideRink(spot.X, spot.Z, 4) then
		spot = player.pos * 0.8
	end
	return Vector3.new(spot.X, 0, spot.Z)
end

local SLOT_SPOT = Vector3.new(Config.Goal.X - 24, 0, 0) -- the shooting drill's puck, in front of the net
local BREAKAWAY_SPOT = Vector3.new(Config.Arena.BlueLineX, 0, 0) -- the goalie drill's puck, on the blue line
local BREAKAWAY_BACK = 14 -- the player starts this far behind it
local PASS_DISTANCE = 42 -- the pass drill's puck starts at least this far from Coach Gus
local PASS_MAX = 60 -- and no further than this (a player far off skates to it first)
local SHOT_AHEAD = 16 -- the shooting drill's puck sits this far from the player, toward the net

-- Where the current drill puts its puck when it starts.
local function firstPuckSpot(drill: Drill): Vector3
	if drill.puck == "pass" then
		-- Build 30: a real pass, PASS_DISTANCE from Coach Gus (10 studs off the player toward him
		-- was often only a short tap away after the dribble drill, which ends near him).
		local fromCoach = Vector3.new(player.pos.X - COACH_SPOT.X, 0, player.pos.Z - COACH_SPOT.Z)
		local dir = if fromCoach.Magnitude > 1 then fromCoach.Unit else Vector3.new(-1, 0, 0)
		local spot = COACH_SPOT + dir * math.clamp(fromCoach.Magnitude - 10, PASS_DISTANCE, PASS_MAX)
		if not Sim.insideRink(spot.X, spot.Z, 6) then
			spot = COACH_SPOT + Vector3.new(-PASS_DISTANCE, 0, 0)
		end
		return Vector3.new(spot.X, 0, spot.Z)
	elseif drill.puck == "shot" then
		-- A few strides from the player, straight toward the net; never closer to the net than the
		-- slot (and off the slot if the player is already standing on it).
		if (GOAL_AT - player.pos).Magnitude > SHOT_AHEAD + 24 then
			return nearPlayer(GOAL_AT, SHOT_AHEAD)
		end
		return if (SLOT_SPOT - player.pos).Magnitude > 8 then SLOT_SPOT else nearPlayer(GOAL_AT, 10)
	elseif drill.puck == "breakaway" then
		return BREAKAWAY_SPOT
	end
	return nearPlayer(drill.ring or GOAL_AT, 10)
end

-- Where a reset puts the drill's puck: back where the drill put it.
local function drillPuckSpot(drill: Drill): Vector3
	return drillStartPuck or firstPuckSpot(drill)
end

-- The second skater on the ice: Coach Gus (the pass drill), the goalie, or nobody. Both live at
-- index 2 of the skater list (never together), so the list never has a gap: the Sim walks it by
-- length, and a gap made it skip, or trip over, a skater (Build 27: the stick stopped touching
-- the puck in the pass drill).
local function setSecond(w: Sim.World, who: Sim.Skater?)
	if who == coach then
		coach.pos = COACH_SPOT
		coach.vel = Vector3.zero
	elseif who == goalie then
		goalie.pos = Vector3.new(Config.Goal.X - Config.Bots.GoalieArc, 0, 0)
		goalie.vel = Vector3.zero
	end
	if who ~= goalie then
		w.skaters[3] = nil
	end
	w.skaters[2] = who
end

local function setGoalie(w: Sim.World, on: boolean)
	setSecond(w, if on then goalie else nil)
	-- Build 36: free practice puts a goalie in the other net too.
	if on and freePractice() then
		goalie2.pos = Vector3.new(-(Config.Goal.X - Config.Bots.GoalieArc), 0, 0)
		goalie2.vel = Vector3.zero
		w.skaters[3] = goalie2
	end
end

local function finishTutorial(w: Sim.World)
	setGoalie(w, true)
	Hud.banner("TUTORIAL COMPLETE!", if rewardClaimed then "YOU KNOW THE BASICS. TIME FOR A MATCH!" else `YOU EARNED THE {REWARD_NAME}`, Color3.fromRGB(255, 194, 26), 3)
	Fx.goal(-math.floor(w.time * 60), 1, Config.Goal.X, 0)
	local done = onDone
	if done then
		task.spawn(done)
	end
end

local function startDrill(w: Sim.World)
	local drill = DRILLS[step]
	drillTime, tipShown, touchedThisDrill, sinceTouch = 0, false, false, 0
	drillStartPuck, missHinted = nil, false
	if drill == nil then
		finishTutorial(w)
		showDrill()
		return
	end
	setSecond(w, if drill.coach then coach elseif drill.goalie then goalie else nil)
	if drill.puck then
		local spot = firstPuckSpot(drill)
		if drill.puck == "breakaway" then
			-- A clean start: the player stands still behind the puck with room to skate onto it.
			World.placeSkater(player, spot - Vector3.new(BREAKAWAY_BACK, 0, 0))
			player.vel = Vector3.zero
			prevPos = player.pos
		end
		drillStartPuck = spot
		placePuck(w, spot)
		prevPuck = w.puck.pos
	end
	showDrill()
end

local function advance(w: Sim.World)
	step += 1
	if DRILLS[step] then
		Hud.banner("NICE!", `STEP {step - 1} OF {#DRILLS} DONE`, Color3.fromRGB(96, 224, 140), 1.1)
	end
	startDrill(w)
end

-- `pond`: the outdoor free skate. `tutorial`: the guided drills; otherwise free practice on
-- the normal rink (no goalie until you bring one in).
function Training.start(parent: Instance, pond: boolean?, tutorial: boolean?)
	pondMode = pond == true
	tutorialMode = tutorial == true and not pondMode
	local w = World.new()
	world = w
	w.controlsEnabled = true
	w.stickHits = true
	w.goalsEnabled = true
	player = Sim.newSkater(1, 1)
	goalie = Sim.newSkater(2, 2)
	goalie.goalie = true
	coach = Sim.newSkater(2, 1) -- shares slot 2 with the goalie; never on the ice together
	goalie2 = Sim.newSkater(3, 1) -- Build 36: the -X net's goalie (free practice)
	goalie2.goalie = true
	World.placeSkater(player, PLAYER_START)
	World.placeSkater(goalie, Vector3.new(Config.Goal.X - Config.Bots.GoalieArc, 0, 0))
	World.placeSkater(goalie2, Vector3.new(-(Config.Goal.X - Config.Bots.GoalieArc), 0, 0))
	World.placeSkater(coach, COACH_SPOT)
	w.skaters[1] = player
	placePuckAhead(w)
	step = if tutorialMode then 1 else #DRILLS + 1
	swept = 0
	lastYaw = player.aimYaw
	resetAt = 0
	prevPos = player.pos
	prevPuck = w.puck.pos

	local ring = Instance.new("Part")
	ring.Name = "TrainingMarker"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 142, 44)
	ring.Size = Vector3.new(0.1, RING_RADIUS * 2, RING_RADIUS * 2)
	ring.Transparency = 1
	ring.Parent = parent
	marker = ring
	clearArrow()
	makeArrow(parent)
	table.clear(bottleBackAt)
	if not pondMode and not tutorialMode then
		freshBottle(w, -1)
		freshBottle(w, 1)
	end

	Hud.setMatchWidgets(false)
	if tutorialMode then
		startDrill(w)
		-- The reward up front, so the player knows what the drills are for.
		local sub = if rewardClaimed then `{#DRILLS} QUICK STEPS. YOU KNOW THESE!` else `FINISH {#DRILLS} QUICK STEPS TO WIN THE {REWARD_NAME} STICK + {Config.Tutorial.RewardCoins} COINS`
		Hud.banner(`WELCOME TO {Config.GameName}!`, sub, Color3.fromRGB(236, 112, 18), 6)
	else
		showDrill()
	end
end

-- Studio tests only (the caller checks): jump the running tutorial to drill n.
function Training.devJump(n: number)
	local w = world
	if not w or not tutorialMode then
		return
	end
	step = math.clamp(math.floor(n), 1, #DRILLS)
	startDrill(w)
end

-- Runs once when the last drill is done (the caller asks the server for the reward).
function Training.onTutorialDone(fn: () -> ())
	onDone = fn
end

-- True once this player has the reward (replays of the drills don't promise it again).
function Training.setRewardClaimed(claimed: boolean)
	rewardClaimed = claimed
end

function Training.inTutorial(): boolean
	return world ~= nil and tutorialMode and DRILLS[step] ~= nil
end

local function clearExtras()
	for _, e in extras do
		e.part:Destroy()
	end
	table.clear(extras)
end

function Training.stop()
	world = nil
	clearExtras()
	Fx.resetBottles() -- Build 36: back to the middle of the nets for a match
	table.clear(bottleBackAt)
	if extraFolder then
		extraFolder:Destroy()
		extraFolder = nil
	end
	if marker then
		marker:Destroy()
		marker = nil
	end
	clearArrow()
	Hud.setObjective(nil, nil)
	Hud.setMatchWidgets(true)
end

function Training.isActive(): boolean
	return world ~= nil
end

function Training.input(): Sim.Input
	return player.input
end

function Training.aimYaw(): number
	return player.aimYaw
end

function Training.playerPosition(): Vector3
	return player.pos
end

function Training.resetPuck()
	local w = world
	if w then
		local drill = if tutorialMode then DRILLS[step] else nil
		if drill and drill.puck then
			placePuck(w, drillPuckSpot(drill))
			touchedThisDrill = false -- a fresh try: no "Missed!" until it is played again
		else
			placePuckAhead(w)
			if freePractice() then
				-- Build 36: R also puts the drink bottles back up (somewhere new on each net).
				freshBottle(w, -1)
				freshBottle(w, 1)
			end
		end
	end
end

-- Somewhere for a new puck: just ahead of the skater, spread so they don't stack.
local function spawnSpot(): Vector3
	spawnCount += 1
	local ahead = Vector3.new(math.cos(player.aimYaw), 0, math.sin(player.aimYaw))
	local side = Vector3.new(-ahead.Z, 0, ahead.X)
	local spot = player.pos + ahead * 7 + side * (((spawnCount % 5) - 2) * 2.2)
	if not Sim.insideRink(spot.X, spot.Z, 3) then
		spot = PUCK_START + Vector3.new(0, 0, ((spawnCount % 5) - 2) * 2.2)
	end
	return spot
end

local function placeExtra(e: Extra, at: Vector3)
	World.placePuck(e.world, at)
	e.world.goalLatched = false
	e.prev = e.world.puck.pos
	e.resetAt = 0
end

-- Adds a puck in front of you; past the limit, clears the extras instead.
function Training.addPuck()
	local w = world
	if not w or Training.inTutorial() then
		return
	end
	if #extras >= MAX_EXTRA then
		clearExtras()
		Hud.banner("PUCKS CLEARED", nil, Color3.fromRGB(120, 200, 255), 0.9)
		return
	end
	if not extraFolder then
		local folder = Instance.new("Folder")
		folder.Name = "PracticePucks"
		folder.Parent = workspace
		extraFolder = folder
	end
	local ew = World.new()
	ew.time = w.time -- Build 40: on the main world's clock (see Training.step)
	ew.skaters = w.skaters -- the same skaters, so the goalie and you play every puck
	ew.bottlesDown = w.bottlesDown -- Build 36: and the same drink bottles
	ew.bottleZ = w.bottleZ
	ew.controlsEnabled = true
	ew.stickHits = true
	ew.goalsEnabled = true
	local main = Fx.puck()
	local part = Instance.new("Part")
	part.Name = "ExtraPuck"
	part.Shape = Enum.PartType.Cylinder
	part.Size = main.Size
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	-- Build 37: every extra puck wears your equipped puck style (the plain puck on the pond).
	Looks.dressPuck(part, if pondMode then nil else Fx.puckStyle(), Fx.plainPuckColor())
	part.Parent = extraFolder
	local e: Extra = { world = ew, prev = Vector3.zero, part = part, resetAt = 0 }
	placeExtra(e, spawnSpot())
	table.insert(extras, e)
	Hud.banner(`{#extras + 1} PUCKS`, nil, Color3.fromRGB(120, 200, 255), 0.6)
end

-- Brings the goalie in, or sends it off (practice only, not the pond or the drills).
function Training.toggleGoalie()
	local w = world
	if not w or pondMode or Training.inTutorial() then
		return
	end
	if w.skaters[2] == goalie then
		setGoalie(w, false)
		Hud.banner("GOALIE OFF", nil, Color3.fromRGB(200, 200, 210), 0.8)
	else
		setGoalie(w, true)
		Hud.banner("GOALIE IN", nil, Color3.fromRGB(96, 224, 140), 0.8)
	end
end

local function near(a: Vector3, b: Vector3, r: number): boolean
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude < r
end

-- After a shot: if the puck is heading inside the posts and under the bar of the +X net, the
-- world time by which a save would have to happen; otherwise 0 (the server's match rule).
-- Build 36: either net (free practice has a goalie in both).
local function shotOnTarget(w: Sim.World): number
	local puck = w.puck
	for _, side in { 1, -1 } do
		if puck.vel.X * side > 5 then
			local t = (side * Config.Goal.X - puck.pos.X) / puck.vel.X
			local z = puck.pos.Z + puck.vel.Z * t
			local y = math.max(0, puck.pos.Y + puck.vel.Y * t - 0.5 * Config.Puck.Gravity * t * t)
			local inside = math.abs(z) < Config.Goal.Width / 2 - Config.Puck.Radius * 0.5
			local under = y < Config.Goal.CrossbarHeight - Config.Puck.Thickness
			if t > 0 and t < 2.5 and inside and under then
				return w.time + t + 0.3
			end
		end
	end
	return 0
end

-- Build 40: which puck a goalie plays when there are several (+ PUCK). A shot already on its way
-- into this goalie's net comes first (the one arriving soonest); otherwise the puck closest to
-- the player, so the goalie squares up to whichever puck you are about to shoot. It used to be the
-- puck closest to its own net, which flicked between pucks lying about the crease.
local lastWatch: { [any]: Sim.World } = {}
local function goalieWatch(w: Sim.World, net: Vector3, brain: BotBrain.BotState): Sim.World
	local side = if net.X > 0 then 1 else -1
	local best, bestGap = w, math.huge
	local shot, shotIn = nil :: Sim.World?, math.huge
	local me = Vector3.new(player.pos.X, 0, player.pos.Z)
	for i = 0, #extras do
		local ww = if i == 0 then w else extras[i].world
		local p = ww.puck
		if p.vel.X * side > 10 then
			local t = (net.X - p.pos.X) / p.vel.X
			if t > 0 and t < 1.5 and math.abs(p.pos.Z + p.vel.Z * t) < Config.Goal.Width / 2 + 2 and t < shotIn then
				shot, shotIn = ww, t
			end
		end
		local gap = (Vector3.new(p.pos.X, 0, p.pos.Z) - me).Magnitude
		if gap < bestGap then
			best, bestGap = ww, gap
		end
	end
	local watch = shot or best
	if lastWatch[brain] ~= watch then
		-- A different puck: forget the last one's shot read, so it reads this one fresh.
		lastWatch[brain] = watch
		brain.incomingSince = nil
		brain.dived = nil
	end
	return watch
end

function Training.step()
	local w = world
	if not w then
		return
	end
	prevPos = player.pos
	prevPuck = w.puck.pos

	if w.skaters[2] == goalie then
		goalieBrain.practice = freePractice() -- Build 36: stays home and reacts (not in the drills)
		BotBrain.think(goalieWatch(w, GOAL_AT, goalieBrain), goalie, "Goalie", goalieBrain, TICK)
	end
	if w.skaters[3] == goalie2 then
		BotBrain.think(goalieWatch(w, GOAL2_AT, goalie2Brain), goalie2, "Goalie", goalie2Brain, TICK)
	end
	-- Build 36: a knocked-off bottle goes back up after 15 seconds.
	for side, at in bottleBackAt do
		if os.clock() >= at then
			freshBottle(w, side)
		end
	end
	if w.skaters[2] == coach then
		-- Coach Gus holds his spot, stick turned toward the player to take the pass.
		coach.input.moveX, coach.input.moveZ = 0, 0
		local toPlayer = player.pos - coach.pos
		if toPlayer.Magnitude > 0.1 then
			coach.input.aimX, coach.input.aimZ = toPlayer.Unit.X, toPlayer.Unit.Z
		end
	end
	player.input.lift = Sim.holdLift(player, w.puck.pos, player.input.lift)
	World.step(w, TICK)

	if resetAt > 0 and w.time >= resetAt then
		resetAt = 0
		Training.resetPuck()
	end

	local scored = false
	for _, event in World.drainEvents(w) do
		if event.kind == "Shot" and event.slot == 1 then
			saveUntil = shotOnTarget(w)
		end
		if event.kind == "Goal" then
			saveUntil = 0
			if event.team == 1 then
				scored = true
			end
			if not freePractice() then
				Fx.goal(-math.floor(w.time * 60), if event.team == 1 then 1 else -1, event.x, event.z)
				Hud.banner("GOAL!", nil, Color3.fromRGB(222, 52, 56), 1.4, `SHOT SPEED: {math.round((event.strength or 0) * 10) / 10} KPH`)
				resetAt = w.time + 1.5
			end
		elseif event.kind == "Stuck" then
			Training.resetPuck()
		else
			if event.kind == "Bottle" and freePractice() then
				bottleBackAt[if event.x > 0 then 1 else -1] = os.clock() + 15
			end
			Fx.cue(event.kind, event.x, event.z, event.strength)
		end
	end
	-- Build 30: a shot on target the goalie gets a piece of is a save, as in a match: the crowd
	-- goes "ohh" and the goalie grunts.
	if saveUntil > 0 then
		if (w.skaters[2] == goalie and w.touch1 == 2) or (w.skaters[3] == goalie2 and w.touch1 == 3) then
			saveUntil = 0
			Fx.cue("Save", w.puck.pos.X, w.puck.pos.Z, 1)
		elseif w.time > saveUntil then
			saveUntil = 0
		end
	end
	local touched = w.touch1 == 1
	if freePractice() then
		unlatchWhenOut(w)
		for _, e in extras do
			unlatchWhenOut(e.world)
		end
	end

	-- Build 31: the main puck and the extras knock into each other instead of passing through.
	if #extras > 0 then
		for _, e in extras do
			local ew = e.world
			e.prev = ew.puck.pos
			ew.tick += 1
			-- Build 40: an extra puck keeps the main world's clock. It used to start its own at 0,
			-- so a goalie that began a swing on one puck and then switched to another waited on
			-- the other clock for its release, stuck mid-swing (the goalie "bugging out").
			ew.time = w.time
			ew.idle += TICK
			World.stepPuck(ew, TICK)
		end
		local all = { w }
		for _, e in extras do
			table.insert(all, e.world)
		end
		local hit, hx, hz = World.collidePucks(all)
		if hit > 8 then
			Fx.cue("Hit", hx, hz, math.min(hit, 60))
		end
	end
	for _, e in extras do
		local ew = e.world
		if e.resetAt > 0 and ew.time >= e.resetAt then
			placeExtra(e, spawnSpot())
		end
		for _, event in World.drainEvents(ew) do
			if event.kind == "Goal" then
				if not freePractice() then
					Fx.goal(-math.floor(ew.time * 60), if event.team == 1 then 1 else -1, event.x, event.z)
					Hud.banner("GOAL!", nil, Color3.fromRGB(222, 52, 56), 1.4, `SHOT SPEED: {math.round((event.strength or 0) * 10) / 10} KPH`)
					e.resetAt = ew.time + 1.5
				end
			elseif event.kind == "Stuck" then
				placeExtra(e, spawnSpot())
			else
				if event.kind == "Bottle" and freePractice() then
					bottleBackAt[if event.x > 0 then 1 else -1] = os.clock() + 15
				end
				Fx.cue(event.kind, event.x, event.z, event.strength)
			end
		end
		-- A puck resting in a net or forgotten for a while comes back out.
		local p = ew.puck.pos
		if ew.idle >= Config.Puck.IdleResetSeconds or (Sim.insideNet(math.abs(p.X) - Config.Goal.X - Config.Puck.Radius, p.Z) and p.Y < Sim.netRoofAt(math.abs(p.X) - Config.Goal.X) and not ew.goalLatched and ew.idle >= 2) then
			ew.idle = 0
			placeExtra(e, spawnSpot())
		end
	end

	local delta = (player.aimYaw - lastYaw + math.pi) % (2 * math.pi) - math.pi
	swept += math.abs(delta)
	lastYaw = player.aimYaw

	local drill = if tutorialMode then DRILLS[step] else nil
	if not drill then
		return
	end
	drillTime += TICK
	if not tipShown and drillTime >= TIP_AFTER then
		tipShown = true
		showDrill()
	end
	if touched then
		touchedThisDrill = true
		sinceTouch = 0
	else
		sinceTouch += TICK
	end
	-- A drill puck left far away for a while comes back in front of the player.
	if drill.puck and resetAt == 0 and sinceTouch >= LOST_AFTER and not near(w.puck.pos, player.pos, 14) then
		sinceTouch = 0
		placePuck(w, drillPuckSpot(drill))
		Hud.toast("Here's the puck back!", true)
	end

	local title = drill.title
	if title == "SKATE" or title == "DASH" then
		if drill.ring and near(player.pos, drill.ring, RING_RADIUS) then
			advance(w)
		end
	elseif title == "SWING" then
		if drillTime < 0.1 then
			swept = 0
		end
		if swept > 1.5 * math.pi then
			advance(w)
		end
	elseif title == "DRIBBLE" then
		if drill.ring and near(w.puck.pos, drill.ring, RING_RADIUS + 1) then
			advance(w)
		end
	elseif title == "PASS" then
		-- The puck reaches Coach Gus after the player has played it.
		if touchedThisDrill and near(w.puck.pos, coach.pos, 6) then
			Hud.toast("Great pass! Coach Gus sends it back.", true)
			advance(w)
		elseif w.idle < 0.1 then
			missHinted = false -- just played it again
		elseif touchedThisDrill and not missHinted and w.idle > 0.8 and w.puck.vel.Magnitude < 1.5 and not near(w.puck.pos, coach.pos, 8) and not near(w.puck.pos, player.pos, 6) then
			-- The pass stopped short or slid past him: say how to have another go.
			missHinted = true
			Hud.toast(`Missed! {resetHint()} puts the puck back. Try again.`, false, 4)
		end
	elseif title == "SHOOT" or title == "BEAT THE GOALIE" then
		if scored then
			advance(w)
		end
	end
end

function Training.fill(alpha: number, states: { any }, dt: number): (number, number, number, number, number)
	local w = world :: Sim.World
	local pos = prevPos:Lerp(player.pos, alpha)
	local function write(state: any, s: Sim.Skater, at: Vector3)
		state.x, state.z = at.X, at.Z
		state.vx, state.vz = s.vel.X, s.vel.Z
		-- Interpolated between ticks exactly like the puck, so the drawn stick and puck agree.
		local turn = (s.aimYaw - s.aimYawPrev + math.pi) % (2 * math.pi) - math.pi
		state.yaw, state.radius = s.aimYawPrev + turn * alpha, s.aimRadius
		state.charging = s.stickState == Sim.WINDING
		state.active = s.stickState == Sim.ACTIVE
		state.charge = s.charge
		state.lifted = s.lifted
		state.lofting = s.lofting
		state.stunned = s.stun > 0
		state.sprinting = s.sprinting
		state.visible = true
	end
	for slot = 1, 6 do
		states[slot].visible = false
	end
	write(states[1], player, pos)
	placeArrow(pos)
	if w.skaters[2] == goalie then
		write(states[6], goalie, goalie.pos)
	end
	if w.skaters[3] == goalie2 then
		write(states[3], goalie2, goalie2.pos)
	end
	if w.skaters[2] == coach then
		write(states[2], coach, coach.pos)
	end
	for _, e in extras do
		e.part.CFrame = CFrame.new(e.prev:Lerp(e.world.puck.pos, alpha)) * CFrame.Angles(0, 0, math.pi / 2)
		e.part.Color = Fx.puck().Color
	end
	local puck = prevPuck:Lerp(w.puck.pos, alpha)
	return puck.X, puck.Y, puck.Z, w.puck.vel.X, w.puck.vel.Z
end

-- Build 40: the extra pucks' parts, for the x-ray.
local extraParts: { BasePart } = {}
function Training.extraPucks(): { BasePart }
	table.clear(extraParts)
	for _, e in extras do
		table.insert(extraParts, e.part)
	end
	return extraParts
end

function Training.meters(): (number, number, boolean)
	return player.spin, player.stamina, player.spinLock > 0
end

return Training
