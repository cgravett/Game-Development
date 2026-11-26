--!strict
-- Client prediction and reconciliation (chapter 37). The local skater runs the same Sim code
-- as the server, so corrections only come from things the client cannot know, such as other
-- players' bodies. Goals and puck hits are never predicted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("GameConfig"))
local Sim = require(Shared:WaitForChild("Sim"))
local Protocol = require(Shared:WaitForChild("Protocol"))

local Prediction = {}

-- Running totals of how wrong each snapshot found the prediction (studs / radians), for tuning:
-- the smaller these are, the smoother the game looks. Studio reads them through an attribute.
local stats = { snaps = 0, ownSum = 0, ownMax = 0, puckSum = 0, puckMax = 0, otherSum = 0, otherMax = 0, yawSum = 0, yawMax = 0, leadSum = 0, leadMax = 0 }

local TICK = Config.Tick
local SNAP_DISTANCE = 8
local REDUNDANT_FRAMES = 3
local MAX_HISTORY = 180

local skater = Sim.newSkater(1, 1)
local frames: { Protocol.Frame } = {}

-- Puck prediction: the puck is re-simulated from the newest server state through the frames
-- the server has not processed yet, against this player's own stick. Carrying, dekes and shots
-- then react on the frame they happen instead of a round trip later; the server stays in
-- charge and every snapshot corrects the local copy.
type StickState = {
	pos: Vector3,
	vel: Vector3,
	aimYaw: number,
	aimYawPrev: number,
	blade: Vector3,
	bladePrev: Vector3,
	stickState: number,
	stickTimer: number,
	swingStart: boolean,
	swingSpeed: number,
	swingLift: number,
	lifted: boolean,
	lofting: boolean,
	spin: number,
	spunOut: boolean,
}
local stickHistory: { StickState } = {}
local puckWorld = Sim.World.new()
puckWorld.goalsEnabled = false
puckWorld.stickHits = true
local ghost = Sim.newSkater(1, 1)
puckWorld.skaters = { ghost }
local puckPrev = puckWorld.puck.pos
local puckError = Vector3.zero
local puckReady = false
local PUCK_SNAP = 10
-- Dash timers before each frame ran. The server does not send them, so a replay starts from
-- the value saved with the oldest unacknowledged frame.
local dashBefore: { { number } } = {}
local seq = 0
local prevPos = Vector3.zero
local visualError = Vector3.zero
local predicting = false
local needsSync = true
local lastError = 0

-- The other skaters as of the newest snapshot. The local body bumps into them during
-- prediction (each moved ahead along its velocity), so walking into someone stops on this
-- screen at once instead of sinking in and being pulled back a moment later.
type Body = { slot: number, x: number, z: number, vx: number, vz: number, yaw: number, lifted: boolean }

-- How each other skater is drawn: the newest snapshot moved ahead along its velocity to the
-- predicted puck's time, plus a small error (ex, ez, eyaw) left over from the last snapshot
-- that is eased away, so a new snapshot never makes a skater or stick pop. The puck's
-- stand-ins use these same numbers, so the stick the puck bounces off is exactly the stick on
-- screen.
type Shown = { has: boolean, x: number, z: number, yaw: number, ex: number, ez: number, eyaw: number }
local shown: { [number]: Shown } = {}
local lastAlpha = 0
local function shownOf(slot: number): Shown
	local sh = shown[slot]
	if not sh then
		sh = { has = false, x = 0, z = 0, yaw = 0, ex = 0, ez = 0, eyaw = 0 }
		shown[slot] = sh
	end
	return sh
end
local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end
local others: { Body } = {}
local stand = Sim.newSkater(1, 1)

-- Stand-ins for the other skaters inside the puck world, so the predicted puck meets their
-- sticks and bodies too (moved ahead along their velocity, like the bumps below). Without them
-- the local puck slid straight through anyone else's blade until the server corrected it.
-- They never shoot here: a shot by someone else always arrives from the server.
local standIns: { Sim.Skater } = {}

-- Build 33: a private puck (the pond's mini-game puck) only ever meets its owner on the server,
-- so the prediction leaves the other skaters out of its world too. Otherwise a skater passing
-- by "touched" it here and not there, and the next snapshot yanked it back off your stick.
local puckSolo = false
local function rebuildPuckSkaters()
	local skaters = { ghost }
	if not puckSolo then
		for i = 1, #standIns do
			table.insert(skaters, standIns[i])
		end
	end
	puckWorld.skaters = skaters
end

function Prediction.setOthers(list: { Body })
	others = list
	if #standIns ~= #list then
		table.clear(standIns)
		for i = 1, #list do
			standIns[i] = Sim.newSkater(i + 1, 1)
		end
		rebuildPuckSkaters()
	end
end

function Prediction.setPuckSolo(on: boolean)
	if on ~= puckSolo then
		puckSolo = on
		rebuildPuckSkaters()
	end
end

local function loadStandIns(ahead: number)
	local t = ahead * TICK
	for i, o in others do
		local s = standIns[i]
		if s then
			local sh = shownOf(o.slot)
			local vel = Vector3.new(o.vx, 0, o.vz)
			local pos = Vector3.new(o.x + sh.ex, 0, o.z + sh.ez) + vel * t
			local yaw = o.yaw + sh.eyaw
			s.slot = o.slot
			s.pos, s.vel = pos, vel
			s.aimYaw, s.aimYawPrev = yaw, yaw
			s.bladePrev = Sim.bladeAt(pos - vel * TICK, yaw, 1)
			s.blade = Sim.bladeAt(pos, yaw, 1)
			s.stickState = Sim.IDLE
			s.swingUsed = true
			s.lifted, s.lofting = o.lifted, false
			s.ignoreTimer = 0
			s.cooldown = 1
		end
	end
end

-- Bump the local skater off every other body, as the server will, "ahead" ticks after the
-- snapshot those bodies came from. Only the local skater's half of each contact is kept.
local function bumpOthers(ahead: number)
	local t = ahead * TICK
	for _, o in others do
		stand.pos = Vector3.new(o.x + o.vx * t, 0, o.z + o.vz * t)
		stand.vel = Vector3.new(o.vx, 0, o.vz)
		stand.stun = 0
		Sim.bodyContact(skater, stand, nil)
	end
end

-- Sticks against bodies, as the server does after the sticks have moved: this skater's stick
-- on every other body and every other stick on this body. Without it, leaning a stick on
-- someone was only felt a snapshot later, as a tug backwards.
local BODY_R = Config.Skater.CollisionRadius
local function stickOthers(ahead: number)
	local t = ahead * TICK
	for _, o in others do
		stand.pos = Vector3.new(o.x + o.vx * t, 0, o.z + o.vz * t)
		stand.vel = Vector3.new(o.vx, 0, o.vz)
		stand.stun = 0
		stand.aimYaw, stand.aimYawPrev = o.yaw, o.yaw
		Sim.stickBodyContact(skater, stand, TICK, nil)
		Sim.stickBodyContact(stand, skater, TICK, nil)
		Sim.stickStickContact(skater, stand, TICK)
	end
	local p, v = Sim.resolveBoards(skater.pos, skater.vel, Config.Skater.BoardRadius, Config.Skater.BoardRestitution)
	skater.pos, skater.vel = Sim.resolveNetsForSkater(p, v, BODY_R)
	skater.blade = Sim.bladeAt(skater.pos, skater.aimYaw, skater.aimRadius)
end

-- Call after reconcile() with each snapshot: whatever each skater was last drawn as, minus
-- where the new snapshot puts it for that same moment, becomes the error to ease away.
function Prediction.settleOthers()
	local n = (math.max(0, #stickHistory - 1) + lastAlpha) * TICK
	for _, o in others do
		local sh = shownOf(o.slot)
		if sh.has then
			local ex, ez = sh.x - (o.x + o.vx * n), sh.z - (o.z + o.vz * n)
			if ex * ex + ez * ez > 36 then
				ex, ez = 0, 0 -- a real jump (a face-off reset): go straight there
			end
			sh.ex, sh.ez = ex, ez
			sh.eyaw = wrapAngle(sh.yaw - o.yaw)
			local e = math.sqrt(ex * ex + ez * ez)
			stats.otherSum += e
			stats.otherMax = math.max(stats.otherMax, e)
			stats.yawSum += math.abs(sh.eyaw)
			stats.yawMax = math.max(stats.yawMax, math.abs(sh.eyaw))
		end
	end
end

-- Fills x, z, yaw and velocity of every other skater's render state (indexed by slot).
function Prediction.renderOthers(alpha: number, dt: number, into: { any })
	lastAlpha = alpha
	local n = (math.max(0, #stickHistory - 1) + alpha) * TICK
	local kp, ky = math.exp(-14 * dt), math.exp(-40 * dt)
	for _, o in others do
		local sh = shownOf(o.slot)
		sh.ex *= kp
		sh.ez *= kp
		sh.eyaw *= ky
		sh.x = o.x + o.vx * n + sh.ex
		sh.z = o.z + o.vz * n + sh.ez
		sh.yaw = o.yaw + sh.eyaw
		sh.has = true
		local state = into[o.slot]
		state.x, state.z, state.yaw = sh.x, sh.z, sh.yaw
		state.vx, state.vz = o.vx, o.vz
	end
end

function Prediction.reset()
	for _, sh in shown do
		sh.has = false
		sh.ex, sh.ez, sh.eyaw = 0, 0, 0
	end
	table.clear(frames)
	table.clear(dashBefore)
	table.clear(stickHistory)
	needsSync = true
	puckReady = false
	visualError = Vector3.zero
	puckError = Vector3.zero
end

local function recordStick(wasActive: boolean): StickState
	return {
		pos = skater.pos,
		vel = skater.vel,
		aimYaw = skater.aimYaw,
		aimYawPrev = skater.aimYawPrev,
		blade = skater.blade,
		bladePrev = skater.bladePrev,
		stickState = skater.stickState,
		stickTimer = skater.stickTimer,
		swingStart = skater.stickState == Sim.ACTIVE and not wasActive,
		swingSpeed = skater.swingSpeed,
		swingLift = skater.swingLift,
		lifted = skater.lifted,
		lofting = skater.lofting,
		spin = skater.spin,
		spunOut = skater.spinLock > 0,
	}
end

-- Loads one recorded frame into the ghost skater the puck world collides with. Shot tokens and
-- contact timers live only on the ghost, exactly as the server keeps them on its skater.
local function loadGhost(h: StickState, first: boolean)
	ghost.pos, ghost.vel = h.pos, h.vel
	ghost.aimYaw, ghost.aimYawPrev = h.aimYaw, h.aimYawPrev
	ghost.blade, ghost.bladePrev = h.blade, h.bladePrev
	ghost.stickState = h.stickState
	ghost.stickTimer = h.stickTimer
	ghost.swingSpeed, ghost.swingLift = h.swingSpeed, h.swingLift
	ghost.lifted, ghost.lofting = h.lifted, h.lofting
	if first then
		-- A swing already under way when the server state was taken has been applied there.
		ghost.swingUsed = true
		ghost.cooldown = 0
		ghost.ignoreTimer = 0
	else
		ghost.cooldown = math.max(0, ghost.cooldown - TICK)
		ghost.ignoreTimer = math.max(0, ghost.ignoreTimer - TICK)
	end
	if h.swingStart then
		ghost.swingUsed = false
	elseif h.stickState ~= Sim.ACTIVE then
		ghost.swingUsed = true
	end
end

-- ahead: ticks since the newest snapshot, which places the stand-ins.
local function advancePuck(h: StickState, first: boolean, ahead: number)
	loadGhost(h, first)
	loadStandIns(ahead)
	puckWorld.tick += 1
	Sim.World.stepPuck(puckWorld, TICK)
	table.clear(puckWorld.events)
end

function Prediction.setPredicting(on: boolean)
	predicting = on
end

function Prediction.isPredicting(): boolean
	return predicting and not needsSync
end

function Prediction.skater(): Sim.Skater
	return skater
end

-- How far past the newest snapshot the predicted puck and the stand-ins run, in seconds.
function Prediction.leadSeconds(): number
	return #stickHistory * TICK
end

function Prediction.pendingFrames(): number
	return #frames
end

function Prediction.lastCorrection(): number
	return lastError
end

function Prediction.step(input: Sim.Input)
	seq += 1
	-- Let go of lift over the puck: the stick stays up until the blade is off it (Sim.holdLift).
	local lift = input.lift
	if puckReady and predicting and not needsSync then
		lift = Sim.holdLift(skater, puckWorld.puck.pos, lift)
	end
	local frame: Protocol.Frame = {
		seq = seq,
		-- Rounded exactly as the packet rounds them, so this prediction runs on the very same
		-- numbers the server will.
		moveX = math.clamp(math.round(input.moveX * 127), -127, 127) / 127,
		moveZ = math.clamp(math.round(input.moveZ * 127), -127, 127) / 127,
		aimX = math.clamp(math.round(input.aimX * 32767), -32768, 32767) / 32767,
		aimZ = math.clamp(math.round(input.aimZ * 32767), -32768, 32767) / 32767,
		charge = input.charge,
		sprint = input.sprint,
		lift = lift,
		loft = input.loft,
		brake = input.brake,
	}
	table.insert(frames, frame)
	table.insert(dashBefore, { skater.dashTimer, skater.dashCooldown, if skater.sprintHeld then 1 else 0, skater.dashSpeed, skater.carveSpin, skater.wishX, skater.wishZ, skater.carveAcc })
	prevPos = skater.pos
	if predicting and not needsSync then
		Sim.stepMotion(skater, frame, TICK, true)
		bumpOthers(#frames)
	end
	local wasActive = skater.stickState == Sim.ACTIVE
	Sim.stepStick(skater, frame, TICK)
	if predicting and not needsSync then
		stickOthers(#frames)
	end
	local h = recordStick(wasActive)
	table.insert(stickHistory, h)
	if #frames > MAX_HISTORY then
		table.remove(frames, 1)
		table.remove(dashBefore, 1)
		table.remove(stickHistory, 1)
	end
	puckPrev = puckWorld.puck.pos
	if puckReady then
		advancePuck(h, false, #stickHistory)
	end
end

-- Called with every server snapshot: restart the puck from the server's state and replay it
-- through the frames the server has not seen yet.
function Prediction.reconcilePuck(px: number, py: number, pz: number, vx: number, vy: number, vz: number)
	local before = puckWorld.puck.pos
	puckWorld.puck.pos = Vector3.new(px, py, pz)
	puckWorld.puck.vel = Vector3.new(vx, vy, vz)
	for i, h in stickHistory do
		advancePuck(h, i == 1, i)
	end
	if puckReady then
		local correction = before - puckWorld.puck.pos
		stats.snaps += 1
		stats.leadSum += #stickHistory
		stats.leadMax = math.max(stats.leadMax, #stickHistory)
		stats.puckSum += correction.Magnitude
		stats.puckMax = math.max(stats.puckMax, correction.Magnitude)
		if correction.Magnitude > PUCK_SNAP then
			puckError = Vector3.zero
			puckPrev = puckWorld.puck.pos
		else
			puckError += correction
			puckPrev -= correction
		end
	else
		puckPrev = puckWorld.puck.pos
		puckReady = true
	end
end

-- The pond: the predicted puck runs on the pond's layout (nil = the match rink).
function Prediction.setLayout(layout: any)
	puckWorld.layout = layout
end

-- The pond switches which puck it predicts: forget the old one so the next server state starts
-- the new one fresh instead of being eased across from the old.
function Prediction.resetPuck()
	puckReady = false
	puckError = Vector3.zero
end

function Prediction.puckReady(): boolean
	return puckReady and predicting and not needsSync
end

function Prediction.stats(reset: boolean?): string
	local n = math.max(1, stats.snaps)
	local text = string.format(
		"snaps %d | lead ticks avg %.2f max %d | own avg %.3f max %.2f | puck avg %.3f max %.2f | others avg %.3f max %.2f | yaw avg %.3f max %.2f",
		stats.snaps, stats.leadSum / n, stats.leadMax, stats.ownSum / n, stats.ownMax, stats.puckSum / n, stats.puckMax,
		stats.otherSum / (n * math.max(1, #others)), stats.otherMax, stats.yawSum / (n * math.max(1, #others)), stats.yawMax
	)
	if reset then
		for key in stats do
			stats[key] = 0
		end
	end
	return text
end

-- Size of the corrections still being eased away (studs): own skater, puck. For the debug overlay.
function Prediction.pendingError(): (number, number)
	return visualError.Magnitude, puckError.Magnitude
end

function Prediction.renderPuck(alpha: number, dt: number): (Vector3, Vector3)
	puckError *= math.exp(-14 * dt)
	return puckPrev:Lerp(puckWorld.puck.pos, alpha) + puckError, puckWorld.puck.vel
end

-- The local stick, interpolated between ticks like the puck so the two always line up.
function Prediction.renderYaw(alpha: number): number
	local turn = (skater.aimYaw - skater.aimYawPrev + math.pi) % (2 * math.pi) - math.pi
	return skater.aimYawPrev + turn * alpha
end

-- Newest frames, repeated across packets because the channel is unreliable.
function Prediction.pack(phaseId: number): buffer?
	local last = #frames
	if last == 0 then
		return nil
	end
	return Protocol.encodeInput(phaseId, frames, math.max(1, last - REDUNDANT_FRAMES + 1), last)
end

local function adopt(snap: Protocol.SkaterSnap)
	skater.pos = Vector3.new(snap.x, 0, snap.z)
	skater.vel = Vector3.new(snap.vx, 0, snap.vz)
	skater.stamina = snap.stamina
	skater.stun = if snap.stunned then math.max(skater.stun, 0.05) else 0
end

function Prediction.reconcile(snap: Protocol.SkaterSnap)
	if needsSync then
		adopt(snap)
		skater.aimYaw = snap.yaw
		skater.aimYawPrev = snap.yaw
		skater.aimRadius = snap.radius
		prevPos = skater.pos
		needsSync = false
		return
	end

	local acked = 0
	for _, frame in frames do
		if frame.seq > snap.ack then
			break
		end
		acked += 1
	end
	-- The spin meter runs here on the same rules as the server. If the two ever disagree (a
	-- dropped packet), take the server's word.
	local ackedStick = stickHistory[acked]
	if ackedStick and frames[acked] and frames[acked].seq == snap.ack then
		-- While spun out the bar shows the lock-out running down, so it gives the time left.
		local lockSeconds = Config.Stick.SpinLockSeconds
		local serverLock = if snap.spunOut then (1 - snap.spin) * lockSeconds else 0
		local mineLock = if ackedStick.spunOut then (1 - ackedStick.spin) * lockSeconds else 0
		if math.abs(serverLock - mineLock) > 0.25 then
			skater.spinLock = math.max(0, skater.spinLock + serverLock - mineLock)
			if skater.spinLock <= 0 then
				skater.spin = snap.spin
			end
		elseif not snap.spunOut and not ackedStick.spunOut and math.abs(ackedStick.spin - snap.spin) > 0.1 then
			skater.spin = math.clamp(skater.spin + (snap.spin - ackedStick.spin), 0, 1)
		end
	end
	if acked > 0 then
		table.move(frames, acked + 1, #frames + acked, 1)
		table.move(dashBefore, acked + 1, #dashBefore + acked, 1)
		table.move(stickHistory, acked + 1, #stickHistory + acked, 1)
	end

	if not predicting then
		adopt(snap)
		prevPos = skater.pos
		return
	end

	local old = skater.pos
	adopt(snap)
	local saved = dashBefore[1]
	if saved then
		skater.dashTimer, skater.dashCooldown, skater.sprintHeld = saved[1], saved[2], saved[3] == 1
		skater.dashSpeed, skater.carveSpin = saved[4], saved[5]
		skater.wishX, skater.wishZ = saved[6], saved[7]
		skater.carveAcc = saved[8] or 0
	end
	local liveYaw, liveYawPrev = skater.aimYaw, skater.aimYawPrev
	-- The blade as it was at the server's state: at the corrected position, with the aim the
	-- oldest unprocessed frame started from (not today's aim, which made the first replayed
	-- frame sweep the blade from the wrong place and knock the puck about).
	local firstStick = stickHistory[1]
	local lastBlade = Sim.bladeAt(skater.pos, if firstStick then firstStick.aimYawPrev else skater.aimYaw, 1)
	local lockedBefore = snap.spunOut
	local replayed = false
	for i, frame in frames do
		-- Each frame moved with the aim it had then (the rigid stick pushes off the boards).
		local recorded = stickHistory[i]
		if recorded then
			skater.aimYaw = recorded.aimYawPrev
		end
		Sim.stepMotion(skater, frame, TICK, true)
		bumpOthers(i)
		if recorded then
			-- Turn the stick again from the corrected position. Turning it into the boards levers
			-- the skater off them, and that push has to be replayed like any other movement.
			skater.aimYaw = recorded.aimYawPrev
			Sim.turnAim(skater, frame, TICK, lockedBefore)
			recorded.aimYaw = skater.aimYaw
			lockedBefore = recorded.spunOut
			replayed = true
			stickOthers(i)
		end
		-- Keep the recorded stick on the corrected path, so the puck replay uses it.
		local h = stickHistory[i]
		if h then
			h.pos, h.vel = skater.pos, skater.vel
			h.bladePrev = lastBlade
			h.blade = Sim.bladeAt(skater.pos, h.aimYaw, 1)
			lastBlade = h.blade
		end
	end
	if not replayed then
		skater.aimYaw, skater.aimYawPrev = liveYaw, liveYawPrev
	end
	skater.blade = lastBlade
	local correction = old - skater.pos
	lastError = correction.Magnitude
	stats.ownSum += lastError
	stats.ownMax = math.max(stats.ownMax, lastError)
	if lastError > SNAP_DISTANCE then
		visualError = Vector3.zero
		prevPos = skater.pos
	else
		-- Hide a small correction by blending it away over a few frames.
		visualError += correction
		prevPos -= correction
	end
end

function Prediction.renderPosition(alpha: number, dt: number): Vector3
	visualError *= math.exp(-12 * dt)
	return prevPos:Lerp(skater.pos, alpha) + visualError
end

return Prediction
