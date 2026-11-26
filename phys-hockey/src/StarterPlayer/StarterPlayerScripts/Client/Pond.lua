--!strict
-- The Pond on the client: your own skater is predicted (the same Prediction the match uses, on
-- the pond's layout), and so is the puck nearest you, so carrying and shooting react at once.
-- Everyone else and every other puck is drawn from the server's snapshots, a moment in the past.
-- The server decides everything; this only draws it and sends stick and skate intent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("GameConfig"))
local Sim = require(Shared:WaitForChild("Sim"))
local Protocol = require(Shared:WaitForChild("Protocol"))
local PondLayout = require(Shared:WaitForChild("PondLayout"))
local Catalog = require(Shared:WaitForChild("Catalog"))

local Client = script.Parent
local Controls = require(Client:WaitForChild("Controls"))
local Fx = require(Client:WaitForChild("Fx"))
local Hud = require(Client:WaitForChild("Hud"))
local Prediction = require(Client:WaitForChild("Prediction"))
local Prefs = require(Client:WaitForChild("Prefs"))
local SkaterView = require(Client:WaitForChild("SkaterView"))

local Pond = {}

local L = PondLayout.LAYOUT
local TICK = Config.Tick
local RING_SIZE = 20
-- How far behind the newest snapshot everyone else is drawn: two snapshot gaps plus a little,
-- measured as they arrive (60 a second when the pond is quiet, 30 when it is busy).
local INTERP_MIN, INTERP_MAX = 0.045, 0.1
local NEAR_BODIES = 40 -- other skaters this close (to you or your puck) are bumped and drawn on the predicted timeline
local MAX_BODIES = 8
local PREDICT_SWITCH = 12 -- a closer puck within this range takes over the prediction
local PREDICT_KEEP = 18
-- A puck you are predicting stays predicted while it is moving (your shot or pass in flight) or
-- still near: handing it to the snapshots mid-flight drew it a round trip in the past, so it
-- jumped back and hung in the air (Build 27).
local PREDICT_FAR = 170
local MOVING = 6
local TAP_RANGE = 80
-- Build 32 (smoother pond): skaters further than FAR_VIEW from you are re-posed every
-- FAR_EVERY frames (their dt summed, so their stick still swings at the right speed), and a
-- puck that hasn't moved isn't moved again. Both were redone for everyone every frame.
local FAR_VIEW = 90
local FAR_EVERY = 3
local seen: { [number]: boolean } = {}
local used: { [number]: boolean } = {}
local farDt: { [number]: number } = {}
local puckAt: { [number]: Vector3 } = {}
local frameNo = 0
local QUEUE_HOLD = 1.0

local localPlayer = Players.LocalPlayer

type Deps = {
	inputRemote: any,
	actionRemote: any,
	snapshotRemote: any,
	cueRemote: any,
	eventRemote: any,
	parent: Instance,
	onQueue: () -> (),
	scene: () -> Instance?,
}

local deps: Deps
local active = false
local myId: number? = nil
local input = Sim.newInput()
local stepCount = 0

local ring: { Protocol.PondSnapshot } = table.create(RING_SIZE)
local ringHead = 0
local ringCount = 0
local newestTick = -1
local scratch: Protocol.PondSnapshot? = nil -- decoded here first, so a late packet never overwrites the ring
local lastArrival = 0
local gap = 1 / 30 -- smoothed seconds between snapshots
local interpDelay = 0.08

local folder: Folder
local views: { [number]: any } = {}
local states: { [number]: any } = {}
local wasLifted: { [number]: boolean } = {}
local roster: { [number]: { name: string, look: any } } = {}
local puckFolder: Folder
local puckParts: { [number]: Part } = {}
local matchPuck: Part
local predictedId: number? = nil
local featuredId: number? = nil
local bodies: { any } = {}
local queueHeld = 0
local queueFired = false
local records: { [string]: any } = {}

-- The mini game you are playing (HUD only; the server keeps the real state).
type GameHud = { id: string, title: string, text: string, startedAt: number, limit: number, extra: string }
local game: GameHud? = nil

local function newState(): any
	return {
		x = 0, z = 0, vx = 0, vz = 0, yaw = 0, radius = 1,
		charging = false, active = false, charge = 0,
		stunned = false, sprinting = false, visible = false, lifted = false, lofting = false,
	}
end

local function makePuckPart(parent: Instance): Part
	local main = Fx.puck()
	local part = Instance.new("Part")
	part.Name = "PondPuck"
	part.Shape = Enum.PartType.Cylinder
	part.Size = main.Size
	part.Color = Fx.plainPuckColor() -- Build 37: the plain puck on the pond, whatever style you wear
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = parent
	return part
end

local function viewFor(id: number): any
	local view = views[id]
	if not view then
		view = SkaterView.new(folder, id)
		views[id] = view
		states[id] = newState()
		local entry = roster[id]
		view:setIdentity(if entry then entry.name else "Skater", 0, id == myId, if entry then entry.look else Catalog.botLook(id))
	end
	return view
end

local function applyIdentities()
	for id, view in views do
		local entry = roster[id]
		if entry then
			view:setIdentity(entry.name, 0, id == myId, entry.look)
		end
		view:setTagVisible(true)
	end
end

local function defaultObjective()
	Hud.setObjective(
		"THE POND",
		`Open rink to the north, mini games to the south. Stand in the orange ring by the big rink to join a 3v3. {Prefs.label("addPuck")} drops your own puck. MENU to leave.`
	)
end

local function applyRecords()
	local scene = deps.scene()
	if not scene then
		return
	end
	for _, station in PondLayout.STATIONS do
		local label = scene:FindFirstChild(`Record_{station.id}`, true)
		if label and label:IsA("TextLabel") then
			local r = records[station.id]
			if r then
				local value = if station.id == "Speed" then `{r.value} KPH` else `{r.value} s`
				label.Text = `POND RECORD: {string.upper(r.name)} {value}`
			else
				label.Text = "POND RECORD: NONE YET"
			end
		end
	end
end

local function setTargetLit(index: number, lit: boolean)
	local scene = deps.scene()
	local target = scene and scene:FindFirstChild(`Target{index}`, true)
	if target and target:IsA("BasePart") then
		target.Color = if lit then Color3.fromRGB(96, 224, 140) else Color3.fromRGB(240, 70, 70)
	end
end

local function clearTargets()
	for i = 1, 4 do
		setTargetLit(i, false)
	end
end

local GREEN = Color3.fromRGB(96, 224, 140)
local ORANGE = Color3.fromRGB(255, 166, 60)

local function onEvent(msg: any)
	if type(msg) ~= "table" or not active then
		return
	end
	local kind = msg.kind
	if kind == "Welcome" then
		myId = msg.you
		applyIdentities()
	elseif kind == "Roster" then
		table.clear(roster)
		for _, entry in msg.list do
			roster[entry.id] = { name = entry.name, look = entry.look }
		end
		applyIdentities()
	elseif kind == "Records" then
		records = msg.records or {}
		applyRecords()
	elseif kind == "Full" then
		Hud.toast("The pond is full right now. Try again in a moment.", false)
	elseif kind == "Busy" then
		Hud.toast(`{msg.name} is playing {msg.title}. Wait for your turn.`, false)
	elseif kind == "Goal" then
		Fx.horn(msg.x, msg.z)
		if msg.scorer == myId and not msg.game then
			Hud.banner("GOAL!", nil, Color3.fromRGB(222, 52, 56), 1.4, `SHOT SPEED: {math.round((msg.speed or 0) * 10) / 10} KPH`)
		end
	elseif kind == "Game" then
		if msg.phase == "start" then
			game = { id = msg.id, title = msg.title, text = msg.text, startedAt = msg.startedAt or 0, limit = msg.limit or 60, extra = "" }
			clearTargets()
			Hud.banner(msg.title, "GO!", ORANGE, 1.2)
		elseif msg.phase == "progress" and game then
			if msg.startedAt then
				game.startedAt = msg.startedAt
			end
			if msg.reset then
				game.startedAt = 0
				game.extra = ""
				Hud.toast(msg.text or "Again!", false)
			elseif msg.id == "Targets" and msg.target then
				setTargetLit(msg.target, true)
				game.extra = `{msg.count} of 4 targets`
				Hud.banner("TARGET!", `{msg.count} OF 4`, GREEN, 0.8)
			elseif msg.id == "Slalom" and msg.gate then
				game.extra = if msg.gate > 0 then `Gate {msg.gate} of {msg.gates}` else "Go!"
				if msg.gate == msg.gates then
					game.extra = "All gates! Now score."
				end
			elseif msg.id == "Speed" then
				game.extra = `Shot {msg.shots} of 5   best {msg.best} KPH`
				if msg.speed then
					Hud.banner(`{msg.speed} KPH`, if msg.speed >= msg.best then "YOUR BEST" else nil, GREEN, 1)
				elseif msg.miss then
					Hud.banner("MISSED", nil, Color3.fromRGB(200, 200, 210), 0.8)
				end
			elseif msg.text then
				Hud.toast(msg.text, false)
			end
		elseif msg.phase == "end" then
			game = nil
			Hud.banner(msg.title, msg.text, if msg.record then GREEN else ORANGE, 2.6, if msg.record then "NEW POND RECORD!" else nil)
			defaultObjective()
		end
	end
end

local CUE_NAMES = {}
for name, id in Protocol.CueKinds do
	CUE_NAMES[id] = name
end

-- Picks which puck to predict: the one you are playing (the server's touchable pucks only).
local function choosePuck(snap: Protocol.PondSnapshot, me: Protocol.PondSkaterSnap): Protocol.PondPuckSnap?
	local function touchable(p: Protocol.PondPuckSnap): boolean
		return not p.private or p.owner == myId
	end
	local function dist(p: Protocol.PondPuckSnap): number
		local dx, dz = p.x - me.x, p.z - me.z
		return math.sqrt(dx * dx + dz * dz)
	end
	local current = if predictedId then snap.puckById[predictedId] else nil
	if current and not touchable(current) then
		current = nil
	end
	local best, bestD = nil, PREDICT_SWITCH
	for i = 1, snap.puckCount do
		local p = snap.pucks[i]
		if touchable(p) then
			local d = dist(p)
			if d < bestD then
				best, bestD = p, d
			end
		end
	end
	if current then
		local d = dist(current)
		local moving = current.vx * current.vx + current.vz * current.vz + current.vy * current.vy > MOVING * MOVING
		if moving and d < PREDICT_FAR then
			return current -- in flight: keep it on the predicted timeline until it settles
		end
		if best and best ~= current and bestD + 2 < d then
			return best
		end
		if d < PREDICT_KEEP or (d < PREDICT_FAR and not best) then
			return current
		end
	end
	-- Skated away from it (nil): the pucks are all drawn from snapshots until you reach one.
	return best
end

local function onSnapshot(packet: any)
	if not active or typeof(packet) ~= "buffer" then
		return
	end
	local snap = scratch or Protocol.newPondSnapshot()
	scratch = snap
	if not Protocol.readPondSnapshot(packet, snap) or snap.tick <= newestTick then
		return
	end
	-- Keep it: swap the decoded snapshot into the ring and reuse the slot it replaces next time.
	local nextHead = ringHead % RING_SIZE + 1
	scratch = ring[nextHead]
	ring[nextHead] = snap
	newestTick = snap.tick
	ringHead = nextHead
	ringCount = math.min(ringCount + 1, RING_SIZE)
	local now = os.clock()
	if lastArrival > 0 then
		gap += (math.clamp(now - lastArrival, 0, 0.2) - gap) * 0.1
		interpDelay = math.clamp(gap * 2 + 0.012, INTERP_MIN, INTERP_MAX)
	end
	lastArrival = now

	local me = if myId then snap.skaterById[myId] else nil
	if not me then
		return
	end
	-- The skaters near you, and near the puck you are predicting, so it meets their sticks too.
	local held = if predictedId then snap.puckById[predictedId] else nil
	local n = 0
	for i = 1, snap.skaterCount do
		local other = snap.skaters[i]
		if other.id ~= myId and n < MAX_BODIES then
			local dx, dz = other.x - me.x, other.z - me.z
			local near = dx * dx + dz * dz < NEAR_BODIES * NEAR_BODIES
			if not near and held then
				local hx, hz = other.x - held.x, other.z - held.z
				near = hx * hx + hz * hz < NEAR_BODIES * NEAR_BODIES
			end
			if near then
				n += 1
				local body = bodies[n]
				if not body then
					body = {}
					bodies[n] = body
				end
				body.slot = other.id
				body.x, body.z = other.x, other.z
				body.vx, body.vz = other.vx, other.vz
				body.yaw = other.yaw
				body.lifted = other.lifted
			end
		end
	end
	for i = n + 1, #bodies do
		bodies[i] = nil
	end
	Prediction.setOthers(bodies)
	Prediction.reconcile(me)
	Prediction.settleOthers()
	local puck = choosePuck(snap, me)
	if puck then
		if puck.id ~= predictedId then
			predictedId = puck.id
			Prediction.resetPuck()
		end
		Prediction.setPuckSolo(puck.private)
		Prediction.reconcilePuck(puck.x, puck.y, puck.z, puck.vx, puck.vy, puck.vz)
	elseif predictedId then
		predictedId = nil
		Prediction.resetPuck()
	end
end

function Pond.init(d: Deps)
	deps = d
	folder = Instance.new("Folder")
	folder.Name = "PondSkaters"
	folder.Parent = d.parent
	puckFolder = Instance.new("Folder")
	puckFolder.Name = "PondPucks"
	puckFolder.Parent = d.parent
	matchPuck = makePuckPart(puckFolder)
	matchPuck.Name = "MatchPuckThroughBoards"
	matchPuck.Parent = nil
	d.snapshotRemote.OnClientEvent:Connect(onSnapshot)
	d.eventRemote.OnClientEvent:Connect(onEvent)
	d.cueRemote.OnClientEvent:Connect(function(kind: any, x: any, z: any, strength: any)
		local name = CUE_NAMES[kind]
		if active and name and type(x) == "number" and type(z) == "number" then
			Fx.cue(name, x, z, tonumber(strength) or 0)
		end
	end)
end

function Pond.isActive(): boolean
	return active
end

function Pond.start()
	active = true
	myId = nil
	predictedId = nil
	featuredId = nil
	newestTick = -1
	ringHead, ringCount = 0, 0
	lastArrival, gap, interpDelay = 0, 1 / 30, 0.08
	queueHeld, queueFired = 0, false
	game = nil
	Sim.useLayout(L)
	Prediction.setLayout(L)
	Prediction.reset()
	Prediction.setPredicting(true)
	Hud.setMatchWidgets(false)
	defaultObjective()
	applyRecords()
	clearTargets()
	deps.actionRemote:FireServer("Pond")
end

function Pond.stop()
	if not active then
		return
	end
	active = false
	deps.actionRemote:FireServer("LeavePond")
	Prediction.setPredicting(false)
	Prediction.reset()
	Prediction.setPuckSolo(false)
	Prediction.setLayout(nil)
	Sim.useLayout(nil)
	for id, view in views do
		view:destroy()
		views[id] = nil
	end
	table.clear(states)
	table.clear(wasLifted)
	table.clear(farDt)
	table.clear(puckAt)
	for id, part in puckParts do
		part:Destroy()
		puckParts[id] = nil
	end
	matchPuck.Parent = nil
	game = nil
	Hud.setObjective(nil, nil)
	Hud.setMatchWidgets(true)
end

function Pond.addPuck()
	if active then
		deps.actionRemote:FireServer("PondPuck")
	end
end

function Pond.ready(): boolean
	return active and myId ~= nil and Prediction.isPredicting()
end

-- One fixed tick: read the controls, predict your skater, send the frames.
function Pond.fixedStep(camera: Camera, flip: number, focus: Vector3)
	if not active then
		return
	end
	Controls.sample(input, flip, camera, focus)
	if not myId then
		return
	end
	Prediction.step(input)
	Controls.syncAim(Prediction.skater().aimYaw)
	stepCount += 1
	local packet = Prediction.pack(0)
	if packet then
		deps.inputRemote:FireServer(packet)
	end
end

local function lerpAngle(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

-- The two snapshots around `target` and how far between them it is.
local function bracket(target: number): (Protocol.PondSnapshot?, Protocol.PondSnapshot?, number)
	if ringCount == 0 then
		return nil, nil, 0
	end
	local newer = ring[ringHead]
	local older = newer
	for back = 1, ringCount - 1 do
		local candidate = ring[(ringHead - back - 1) % RING_SIZE + 1]
		older = candidate
		if candidate.time <= target then
			break
		end
		newer = candidate
	end
	local span = newer.time - older.time
	return older, newer, if span > 1e-4 then math.clamp((target - older.time) / span, 0, 1) else 1
end

-- The match puck, seen through the match rink's boards (nil hides it).
function Pond.setMatchPuck(x: number?, y: number?, z: number?)
	if x and y and z then
		matchPuck.CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.pi / 2)
		matchPuck.Color = Fx.plainPuckColor() -- Build 37: plain (was the styled puck's base colour)
		matchPuck.Parent = puckFolder
	else
		matchPuck.Parent = nil
	end
end

-- Draws the pond. Returns the camera focus, its velocity and the featured puck (drawn by Fx,
-- with its trail and see-through glow): the one you are predicting, or else the nearest.
function Pond.render(alpha: number, dt: number, renderClock: number): (Vector3, Vector3, number, number, number, number, number)
	local older, newer, t = bracket(renderClock - interpDelay)
	table.clear(seen)
	frameNo += 1
	if older and newer then
		for i = 1, newer.skaterCount do
			local b = newer.skaters[i]
			local a = older.skaterById[b.id] or b
			local id = b.id
			viewFor(id)
			local state = states[id]
			state.x = a.x + (b.x - a.x) * t
			state.z = a.z + (b.z - a.z) * t
			state.vx = a.vx + (b.vx - a.vx) * t
			state.vz = a.vz + (b.vz - a.vz) * t
			state.yaw = lerpAngle(a.yaw, b.yaw, t)
			state.radius = a.radius + (b.radius - a.radius) * t
			state.charging, state.active, state.charge = b.charging, b.active, b.charge
			state.stunned, state.lifted, state.lofting, state.sprinting = b.stunned, b.lifted, b.lofting, b.sprinting
			state.visible = true
			seen[id] = true
		end
	end
	-- Nearby skaters are drawn on the predicted puck's timeline, so their sticks meet it where
	-- the puck's physics has them.
	if Prediction.puckReady() then
		-- (A skater in the newest snapshot may not be in the older pair yet.)
		for _, body in bodies do
			viewFor(body.slot)
			states[body.slot].visible = true
			seen[body.slot] = true
		end
		Prediction.renderOthers(alpha, dt, states)
	end

	local focus = Vector3.zero
	local velocity = Vector3.zero
	if myId and states[myId] and Prediction.isPredicting() then
		local pos = Prediction.renderPosition(alpha, dt)
		local s = Prediction.skater()
		local state = states[myId]
		state.x, state.z = pos.X, pos.Z
		state.vx, state.vz = s.vel.X, s.vel.Z
		state.yaw, state.radius = Prediction.renderYaw(alpha), s.aimRadius
		state.charging = s.stickState == Sim.WINDING
		state.active = s.stickState == Sim.ACTIVE
		state.charge = s.charge
		state.lifted, state.lofting, state.sprinting = s.lifted, s.lofting, s.sprinting
		state.stunned = s.stun > 0
		state.visible = true
		seen[myId] = true
		focus = pos
		velocity = Vector3.new(s.vel.X, 0, s.vel.Z)
	end

	for id, view in views do
		local state = states[id]
		if not seen[id] then
			-- Gone from the pond: drop the rig.
			view:destroy()
			views[id] = nil
			farDt[id] = nil
			states[id] = nil
			wasLifted[id] = nil
		else
			local fx, fz = state.x - focus.X, state.z - focus.Z
			if id ~= myId and fx * fx + fz * fz > FAR_VIEW * FAR_VIEW then
				local acc = (farDt[id] or 0) + dt
				if (frameNo + id) % FAR_EVERY == 0 then
					farDt[id] = 0
					view:update(state, acc)
				else
					farDt[id] = acc
				end
			else
				farDt[id] = 0
				view:update(state, dt)
			end
			local lifted = state.lifted == true
			if lifted ~= (wasLifted[id] or false) then
				wasLifted[id] = lifted
				local dx, dz = state.x - focus.X, state.z - focus.Z
				if dx * dx + dz * dz < TAP_RANGE * TAP_RANGE then
					local blade = Sim.bladeAt(Vector3.new(state.x, 0, state.z), state.yaw, 1)
					Fx.stickTap(blade.X, blade.Z, not lifted, id == myId)
				end
			end
		end
	end

	-- Pucks: the predicted one from prediction, the rest interpolated.
	local px, py, pz, pvx, pvz = focus.X, -5, focus.Z, 0, 0
	local featured: number? = nil
	if predictedId and Prediction.puckReady() then
		local p, v = Prediction.renderPuck(alpha, dt)
		px, py, pz, pvx, pvz = p.X, p.Y, p.Z, v.X, v.Z
		featured = predictedId
	end
	table.clear(used)
	local puckColor = Fx.plainPuckColor() -- Build 37: pond pucks are always the plain puck
	if older and newer then
		local nearest, nearestD = nil, math.huge
		for i = 1, newer.puckCount do
			local b = newer.pucks[i]
			local a = older.puckById[b.id] or b
			local x, y, z = a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t
			if b.id ~= featured then
				local part = puckParts[b.id]
				if not part then
					part = makePuckPart(puckFolder)
					puckParts[b.id] = part
				elseif part.Parent ~= puckFolder then
					part.Parent = puckFolder -- shown again (it was the featured one)
				end
				local at = Vector3.new(x, y, z)
				local last = puckAt[b.id]
				if not last or (last - at).Magnitude > 1e-3 then
					puckAt[b.id] = at
					part.CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.pi / 2)
				end
				if part.Color ~= puckColor then
					part.Color = puckColor
				end
				used[b.id] = true
				local d = (x - focus.X) * (x - focus.X) + (z - focus.Z) * (z - focus.Z)
				if not featured and d < nearestD then
					nearest, nearestD = b.id, d
				end
			end
		end
		if not featured and nearest then
			-- No puck predicted: Fx draws the nearest one (its plain copy is hidden).
			local part = puckParts[nearest]
			px, py, pz = part.Position.X, part.Position.Y, part.Position.Z
			local b = newer.puckById[nearest]
			pvx, pvz = b.vx, b.vz
			-- Build 32: parked, not destroyed (it was rebuilt from scratch every frame).
			part.Parent = nil
			featured = nearest
		end
	end
	featuredId = featured
	for id, part in puckParts do
		if not used[id] then
			part:Destroy()
			puckParts[id] = nil
			puckAt[id] = nil
		end
	end

	-- The match queue: stand in the ring by the big rink for a moment.
	local q = PondLayout.QUEUE
	local inRing = (Vector3.new(focus.X, 0, focus.Z) - q).Magnitude < PondLayout.QUEUE_RADIUS and myId ~= nil
	if inRing and not queueFired then
		queueHeld += dt
		if queueHeld >= QUEUE_HOLD then
			queueFired = true
			Hud.banner("JOINING 3v3", nil, ORANGE, 1.2)
			deps.onQueue()
		end
	elseif not inRing then
		queueHeld = 0
		queueFired = false
	end

	-- Mini-game clock on the objective panel.
	if game then
		local clockText = ""
		if game.startedAt > 0 then
			local left = math.max(0, game.limit - (workspace:GetServerTimeNow() - game.startedAt))
			clockText = `   {math.ceil(left)} s left`
		end
		local line = if game.extra ~= "" then game.extra else game.text
		Hud.setObjective(game.title, line .. clockText)
	end

	return focus, velocity, px, py, pz, pvx, pvz
end

-- Every drawn skater, for the see-through glow.
function Pond.occluders(into: { any })
	for id, state in states do
		if state.visible and views[id] then
			table.insert(into, state)
		end
	end
end

function Pond.rig(): any
	local view = if myId then views[myId] else nil
	return if view and states[myId :: number] and states[myId :: number].visible then view.rig else nil
end

function Pond.meters(): (number, number, boolean)
	local s = Prediction.skater()
	return s.spin, s.stamina, s.spinLock > 0
end

return Pond
