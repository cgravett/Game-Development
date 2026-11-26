--!strict
-- Bots only write the same Input a player sends, so they obey the same aim limits, swing
-- machine and cooldowns. They cannot touch the puck except through their blade. A slow think
-- rate keeps server cost flat: no pathfinding, just target selection.

local Config = require(script.Parent.GameConfig)
local Sim = require(script.Parent.Sim)

local BotBrain = {}

local BOTS = Config.Bots
local STICK = Config.Stick
local GOAL = Config.Goal

export type Role = string -- "Field", "Goalie" or "Dummy"

export type BotState = {
	timer: number,
	releaseAt: number,
	charging: boolean,
	target: Vector3?,
	side: number?,
	shotSpeed: number?,
	incomingSince: number?,
	goalieZ: number?,
	stuck: number?,
	wallTime: number?, -- Build 36: seconds this bot has been working a puck on the boards
	jam: number?,
	escapeUntil: number?,
	escapeDir: Vector3?,
	easy: boolean?, -- a goalie facing a player who is alone against bots: slower to react
	practice: boolean?, -- Build 36: a free-practice goalie: stays home, reads shots sooner, can dash across
	dived: boolean?, -- Build 36: this shot already got its dash
}

local rng = Random.new()

function BotBrain.newState(): BotState
	return { timer = rng:NextNumber() * BOTS.ThinkInterval, releaseAt = 0, charging = false, target = nil }
end

-- Near the puck a fast-turning stick whips it away at blade-tip speed (the sim can turn the
-- stick almost instantly), so a bot that is not mid-swing turns its stick at a controlled rate:
-- gently right at the puck, a little quicker on the way in. turnStep is radians per think.
-- Build 31: about 1.7x quicker (was 0.22 and 0.45): the bots' sticks came round so slowly they
-- could never sweep a full shot.
local GENTLE_STEP = 0.38
local NEAR_STEP = 0.75
local turnStep = math.huge
local function limitYaw(s: Sim.Skater, yaw: number): number
	if turnStep == math.huge then
		return yaw
	end
	local delta = (yaw - s.aimYaw + math.pi) % (2 * math.pi) - math.pi
	return s.aimYaw + math.clamp(delta, -turnStep, turnStep)
end

-- The blade is angled off the stick, so its centre sits this far round from where the stick
-- points. Aiming the stick this much short puts the blade itself on the target.
local CENTRE_TURN = math.atan2(STICK.BladeLength / 2 * math.sin(STICK.BladeAngle), STICK.Reach - STICK.BladeLength / 2 + STICK.BladeLength / 2 * math.cos(STICK.BladeAngle))

local function setAim(input: Sim.Input, s: Sim.Skater, target: Vector3, errorRadians: number)
	local dx, dz = target.X - s.pos.X, target.Z - s.pos.Z
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist < 1e-3 then
		return
	end
	local yaw = limitYaw(s, math.atan2(dz, dx) - CENTRE_TURN + errorRadians)
	local r = math.clamp(dist / STICK.Reach, STICK.MinRadius, 1)
	input.aimX = math.cos(yaw) * r
	input.aimZ = math.sin(yaw) * r
end

-- Point the stick at a far target while keeping the blade at the puck's distance. Extending
-- to full reach would carry the blade past the puck and the swing would miss.
local function setShotAim(input: Sim.Input, s: Sim.Skater, target: Vector3, puckPos: Vector3, errorRadians: number)
	local dx, dz = target.X - s.pos.X, target.Z - s.pos.Z
	if dx * dx + dz * dz < 1e-3 then
		return
	end
	local px, pz = puckPos.X - s.pos.X, puckPos.Z - s.pos.Z
	local yaw = limitYaw(s, math.atan2(dz, dx) + errorRadians)
	local r = math.clamp(math.sqrt(px * px + pz * pz) / STICK.Reach, STICK.MinRadius, 1)
	input.aimX = math.cos(yaw) * r
	input.aimZ = math.sin(yaw) * r
end

local function setMove(input: Sim.Input, s: Sim.Skater, target: Vector3, slowRadius: number)
	local dx, dz = target.X - s.pos.X, target.Z - s.pos.Z
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist < 0.3 then
		input.moveX, input.moveZ = 0, 0
		return
	end
	local scale = math.min(1, dist / slowRadius) / dist
	input.moveX, input.moveZ = dx * scale, dz * scale
end

local function aimError(): number
	return rng:NextNumber(-BOTS.AimErrorRadians, BOTS.AimErrorRadians)
end

-- Roughly how fast the puck leaves after a wind-up this long (the sim's swing curve).
local function swingSpeedFor(seconds: number): number
	if seconds < STICK.QuickThreshold then
		return STICK.QuickShotSpeed
	end
	local charge = math.clamp((seconds - STICK.QuickThreshold) / STICK.ChargeTime, 0, 1)
	return STICK.MinChargedSpeed + (STICK.MaxChargedSpeed - STICK.MinChargedSpeed) * charge ^ 0.8
end

-- The puck leaves along the stick plus a share of the skater's own velocity, so aim off by the
-- sideways part of that share and the shot still runs true to the target.
local function leadTarget(s: Sim.Skater, target: Vector3, speed: number): Vector3
	local d = Vector3.new(target.X - s.pos.X, 0, target.Z - s.pos.Z)
	if d.Magnitude < 1e-3 then
		return target
	end
	local along = d.Unit
	local carry = Vector3.new(s.vel.X, 0, s.vel.Z) * STICK.CarrySpeedShare
	local side = carry - along * carry:Dot(along)
	return s.pos + along * speed - side
end

local function beginSwing(w: Sim.World, st: BotState, input: Sim.Input, seconds: number, target: Vector3?)
	st.charging = true
	st.target = target
	st.releaseAt = w.time + seconds
	st.shotSpeed = swingSpeedFor(seconds)
	input.charge = true
end

-- Every shot: lift the stick, put it on the line in one go (lifted, so the turn cannot knock
-- the puck away) and wind up. The stick comes down on release.
local function takeShot(w: Sim.World, s: Sim.Skater, st: BotState, input: Sim.Input, target: Vector3, puckPos: Vector3, seconds: number)
	turnStep = math.huge
	input.lift = true
	setShotAim(input, s, leadTarget(s, target, swingSpeedFor(seconds)), puckPos, aimError())
	beginSwing(w, st, input, seconds, target)
end

-- The skater (either team, not a goalie) who has the puck on their blade, if anyone does.
local CARRY_GAP = STICK.BladeLength / 2 + Config.Puck.Radius + 1.2
local function carrierOf(w: Sim.World): Sim.Skater?
	local p = Vector3.new(w.puck.pos.X, 0, w.puck.pos.Z)
	if w.puck.pos.Y > 1.5 then
		return nil
	end
	local best, bestGap = nil, CARRY_GAP
	for _, other in w.skaters do
		if not other.goalie then
			local gap = (Vector3.new(other.blade.X, 0, other.blade.Z) - p).Magnitude
			if gap < bestGap then
				best, bestGap = other, gap
			end
		end
	end
	return best
end

-- Build 32: a one-on-one is a carrier coming at the goalie's net with none of the goalie's
-- teammates between them and it.
local function oneOnOne(w: Sim.World, s: Sim.Skater, carrier: Sim.Skater, goal: Vector3): boolean
	local c = Vector3.new(carrier.pos.X, 0, carrier.pos.Z)
	local toGoal = (c - goal).Magnitude
	for _, o in w.skaters do
		if o ~= s and o.team == s.team and not o.goalie then
			local p = Vector3.new(o.pos.X, 0, o.pos.Z)
			if (p - goal).Magnitude < toGoal + 2 then
				-- How far the defender is off the carrier's line to the net.
				local d = goal - c
				local t = math.clamp((p - c):Dot(d) / math.max(1e-3, d:Dot(d)), 0, 1)
				if (c + d * t - p).Magnitude < BOTS.GoalieLaneWidth then
					return false
				end
			end
		end
	end
	return true
end

-- Build 32: the goalie plays the angle (it stands on the line from the middle of its net to
-- the puck) and only reads a shot off a loose puck: a puck being carried in used to look like a
-- shot heading wide, so the goalie slid off to the post and left the net open. On a one-on-one
-- it comes out to meet the carrier and pokes at the puck.
local function thinkGoalie(w: Sim.World, s: Sim.Skater, st: BotState, attack: number)
	local input = s.input
	local puck = w.puck
	local ownX = -attack * GOAL.X
	local goal = Vector3.new(ownX, 0, 0)
	local pp = Vector3.new(puck.pos.X, 0, puck.pos.Z)
	local carrier = carrierOf(w)
	-- Build 36: in practice every skater is a shooter to beat (the -X goalie shares the player's team).
	local function foe(o: Sim.Skater): boolean
		return o.team ~= s.team or st.practice == true
	end
	input.sprint = false
	-- Build 35: a puck pushed ahead on a dash is off the blade, but the skater right behind it
	-- (further from this net than the puck) is still carrying it in.
	-- A puck going faster than a skater can (a shot) is never "carried".
	if not carrier and puck.pos.Y < 1.5 and puck.vel.Magnitude < Config.Skater.DashMaxSpeed + 6 then
		local best = BOTS.GoalieBreakawayGap
		local puckToNet = (pp - goal).Magnitude
		for _, o in w.skaters do
			if foe(o) and not o.goalie then
				local op = Vector3.new(o.pos.X, 0, o.pos.Z)
				local gap = (op - pp).Magnitude
				if gap < best and (op - goal).Magnitude > puckToNet then
					carrier, best = o, gap
				end
			end
		end
	end
	local arc = BOTS.GoalieArc
	local out = (pp.X - ownX) * attack
	local x, z
	if out < 1.5 then
		-- Level with the goal line or behind the net: seal the near post.
		x = ownX + attack * 1.6
		z = (if pp.Z >= 0 then 1 else -1) * (GOAL.Width / 2 - 1)
	else
		x = ownX + attack * arc
		z = math.clamp(pp.Z * arc / out, -GOAL.Width / 2 + 0.5, GOAL.Width / 2 - 0.5)
	end
	local incoming = carrier == nil and puck.vel.X * attack < -10
	if not incoming then
		st.incomingSince = nil
		st.dived = nil
	elseif not st.incomingSince then
		st.incomingSince = w.time
	end
	if incoming then
		-- Build 40: quicker reads (Config.Bots.GoalieReaction; it was a fixed 0.22 here).
		local reaction = if st.practice then BOTS.PracticeGoalieReaction elseif st.easy then BOTS.EasyGoalieReaction else BOTS.GoalieReaction
		if w.time - (st.incomingSince or w.time) < reaction then
			-- Like a person, the goalie needs a moment to read a shot: hold the spot until then.
			z = st.goalieZ or z
		else
			local t = (ownX - puck.pos.X) / puck.vel.X
			if t > 0 and t < 2 then
				local cross = puck.pos.Z + puck.vel.Z * t
				-- Only a shot on net moves it across; one going wide is left to go wide.
				if math.abs(cross) < GOAL.Width / 2 + 0.5 then
					z = math.clamp(cross, -GOAL.Width / 2, GOAL.Width / 2)
					-- Build 36: a practice goalie reads the side and lunges for it: one dash across,
					-- on PracticeGoalieDiveChance of shots aimed well off its body (so a good shot
					-- to a corner still beats it). Build 40: every bot goalie does, at its own chance.
					if st.dived == nil then
						local chance = if st.practice then BOTS.PracticeGoalieDiveChance elseif st.easy then BOTS.EasyGoalieDiveChance else BOTS.GoalieDiveChance
						st.dived = math.abs(z - s.pos.Z) > 2.5 and rng:NextNumber() < chance
						input.sprint = st.dived == true
					end
				end
			end
		end
	end
	st.goalieZ = z
	local charge = false
	if carrier and foe(carrier) then
		local c = Vector3.new(carrier.pos.X, 0, carrier.pos.Z)
		local range = if st.easy then BOTS.EasyGoalieChargeRange else BOTS.GoalieChargeRange
		if (c - goal).Magnitude < range and (c.X - ownX) * attack > 2 and oneOnOne(w, s, carrier, goal) then
			charge = true
			-- Build 35: out along the line to the puck, a share of the way (cutting the angle), and
			-- only right onto the puck once the shooter is close; never past GoalieChargeOut.
			local d = pp - goal
			local reach = d.Magnitude
			local target
			if reach <= BOTS.GoalieChargeOut + 3 then
				target = if reach > BOTS.GoalieChargeOut then goal + d.Unit * BOTS.GoalieChargeOut else pp
			else
				target = goal + d.Unit * math.clamp(reach * BOTS.GoalieComeOut, arc, BOTS.GoalieChargeOut)
			end
			setMove(input, s, target, 1)
		end
	end
	if not charge then
		setMove(input, s, Vector3.new(x, 0, z), if st.practice then 3 elseif st.easy then BOTS.EasyGoalieSlowRadius else 4)
	end

	-- Build 36: a puck already in the net is a goal; leave it there (practice goalies used to
	-- dig every goal back out).
	local inNet = (pp.X - ownX) * attack < -GOAL.LineWidth and math.abs(pp.Z) < GOAL.Width / 2
	local dist = (puck.pos - s.pos).Magnitude
	if dist < STICK.Reach + 1.5 and not incoming and not inNet then
		-- Clear the zone: line the blade up with the puck, then tap it up the ice.
		local bladeGap = (Vector3.new(puck.pos.X, 0, puck.pos.Z) - s.blade).Magnitude
		if bladeGap < 3 and s.stickState == Sim.IDLE and not st.charging then
			setShotAim(input, s, Vector3.new(s.pos.X + attack * 40, 0, s.pos.Z + (if puck.pos.Z < 0 then -18 else 18)), puck.pos, aimError())
			beginSwing(w, st, input, 0.05)
			return
		end
	end
	if not st.charging then
		setAim(input, s, puck.pos, 0)
	end
end

local function closestFieldSkater(w: Sim.World, team: number): Sim.Skater?
	local best, bestDist = nil, math.huge
	for _, other in w.skaters do
		if other.team == team and not other.goalie then
			local d = (other.pos - w.puck.pos).Magnitude
			if d < bestDist then
				best, bestDist = other, d
			end
		end
	end
	return best
end

local function openTeammate(w: Sim.World, s: Sim.Skater, attack: number): Sim.Skater?
	for _, other in w.skaters do
		if other ~= s and other.team == s.team and not other.goalie and (other.pos.X - s.pos.X) * attack > 6 then
			return other
		end
	end
	return nil
end

-- Keeps a target point on the ice so a bot never chases a spot behind the boards.
local INNER_X = Config.Arena.Length / 2 - 2.5
local INNER_Z = Config.Arena.Width / 2 - 2.5
local function insideRink(p: Vector3): Vector3
	return Vector3.new(math.clamp(p.X, -INNER_X, INNER_X), 0, math.clamp(p.Z, -INNER_Z, INNER_Z))
end

-- Where the puck carrier wants the puck to go next: toward the slot in front of the net,
-- round the net when behind a goal line, and always away from the boards when it is near them,
-- so a bot never pins the puck against the wall.
local SLOT_X = GOAL.X - 22
local function carryDirection(p: Vector3, attack: number): Vector3
	local side = if p.Z >= 0 then 1 else -1
	local nearPost = math.abs(p.Z) < GOAL.Width / 2 + 5
	local target
	if attack * p.X > GOAL.X - 2 then
		-- Behind the net we attack: round the post, then out to the slot.
		target = if nearPost then Vector3.new(p.X, 0, side * (GOAL.Width / 2 + 12)) else Vector3.new(attack * (GOAL.X - 16), 0, side * 6)
	elseif -attack * p.X > GOAL.X - 2 and nearPost then
		-- Behind our own net: round it before heading up the ice.
		target = Vector3.new(p.X, 0, side * (GOAL.Width / 2 + 12))
	else
		target = Vector3.new(attack * SLOT_X, 0, 0)
	end
	local d = target - p
	local dir = if d.Magnitude > 1e-3 then d.Unit else Vector3.new(attack, 0, 0)
	local gap, nx, nz = Sim.boardGap(p.X, p.Z)
	local n = Vector3.new(nx, 0, nz)
	if gap < 4 then
		-- On the wall nobody can get between the puck and the boards, so work it along them
		-- and gently off: forward along the boards, or round the corner when facing the wall.
		local t = Vector3.new(-n.Z, 0, n.X)
		local along = t:Dot(dir)
		if math.abs(along) < 0.3 then
			if t:Dot(p) < 0 then
				t = -t
			end
		elseif along < 0 then
			t = -t
		end
		dir = (t + n).Unit
	elseif gap < 8 then
		local into = dir:Dot(n)
		if into < 0.5 then
			dir = (dir + n * (0.5 - into) * 1.5).Unit
		end
	end
	return dir
end

-- Ask for a velocity directly (the sim steers toward input * MaxSpeed).
local function moveVel(input: Sim.Input, v: Vector3)
	local maxSpeed = Config.Skater.MaxSpeed
	local m = v.Magnitude
	if m > maxSpeed then
		v = v / m * maxSpeed
	end
	input.moveX, input.moveZ = v.X / maxSpeed, v.Z / maxSpeed
end

local function capped(v: Vector3, limit: number): Vector3
	local m = v.Magnitude
	return if m > limit then v / m * limit else v
end

-- An opponent within `radius` of the puck: no time for a full wind-up.
local function crowded(w: Sim.World, s: Sim.Skater, p: Vector3, radius: number): boolean
	for _, o in w.skaters do
		if o.team ~= s.team and (Vector3.new(o.pos.X, 0, o.pos.Z) - p).Magnitude < radius then
			return true
		end
	end
	return false
end

local TOE = STICK.Reach + STICK.BladeLength / 2
local HOLD = TOE + 0.6 -- puck just past the toe, on the stick's line: a swing sends it along that line
local FACE = Config.Puck.Radius + STICK.BladeThickness - 0.1 -- puck resting on the blade's face
local CARRY_SPEED = 30 -- Build 31: a player holding W skates 31 (Skater.MaxSpeed); bots carried at 20
local WALL_CRAWL = 5 -- a wall puck slower than this is not coming off the wall

-- How far the puck is from the blade's segment (it runs at BladeAngle off the stick).
local function bladeDistance(s: Sim.Skater, p: Vector3): number
	local by = Sim.bladeYaw(s.aimYaw)
	local dx, dz = math.cos(by), math.sin(by)
	local half = STICK.BladeLength / 2
	local rx, rz = p.X - s.blade.X, p.Z - s.blade.Z
	local along = math.clamp(rx * dx + rz * dz, -half, half)
	local ex, ez = rx - dx * along, rz - dz * along
	return math.sqrt(ex * ex + ez * ez)
end

-- No defending skater in the puck's path for the next stretch: shooting into a body only
-- hands the puck over. (The goalie is fair game; beating them is the point.)
local LANE_R = Config.Skater.CollisionRadius + Config.Puck.Radius
local function laneClear(w: Sim.World, s: Sim.Skater, from: Vector3, dir: Vector3): boolean
	for _, o in w.skaters do
		if o.team ~= s.team and not o.goalie then
			local rel = Vector3.new(o.pos.X - from.X, 0, o.pos.Z - from.Z)
			local along = rel:Dot(dir)
			if along > -1 and along < 16 and (rel - dir * along).Magnitude < LANE_R then
				return false
			end
		end
	end
	return true
end

-- Build 30: a teammate to move a pinned wall puck to, up or down the boards: 8-45 studs off,
-- mostly along the wall (tangent t) from the puck, with no opponent in the lane. The one
-- furthest up the ice wins.
local function boardsTeammate(w: Sim.World, s: Sim.Skater, from: Vector3, t: Vector3, attack: number): Sim.Skater?
	local best, bestScore = nil, -math.huge
	for _, o in w.skaters do
		if o ~= s and o.team == s.team and not o.goalie then
			local rel = Vector3.new(o.pos.X - from.X, 0, o.pos.Z - from.Z)
			local d = rel.Magnitude
			if d > 8 and d < 45 and math.abs(rel:Dot(t)) / d > 0.75 and laneClear(w, s, from, rel / d) then
				local score = o.pos.X * attack
				if score > bestScore then
					best, bestScore = o, score
				end
			end
		end
	end
	return best
end

local function thinkChase(w: Sim.World, s: Sim.Skater, st: BotState, attack: number): string
	local input = s.input
	local puck = w.puck
	local flatPuck = Vector3.new(puck.pos.X, 0, puck.pos.Z)
	local puckVel = Vector3.new(puck.vel.X, 0, puck.vel.Z)
	local toPuck = flatPuck - s.pos
	local dist = toPuck.Magnitude

	-- The puck glides, so chase where we can meet it, not where it is.
	local spot = flatPuck
	if puckVel.Magnitude > 3 and dist > 8 then
		local reachSpeed = Config.Skater.SprintMaxSpeed
		for i = 1, 15 do
			local t = i * 0.1
			local p = insideRink(flatPuck + puckVel * t)
			spot = p
			if (p - s.pos).Magnitude <= reachSpeed * t + STICK.Reach then
				break
			end
		end
	end

	-- Aim inside the far post.
	local goal = Vector3.new(attack * GOAL.X, 0, -math.sign(flatPuck.Z) * GOAL.Width * 0.32)
	local goalLine = goal - flatPuck
	local goalDist = goalLine.Magnitude
	local shotDir = if goalDist > 1e-3 then goalLine / goalDist else Vector3.new(attack, 0, 0)
	local behindNet = attack * flatPuck.X > GOAL.X - 4
	local canShoot = not behindNet and goalDist < BOTS.ShootRange and math.abs(shotDir.X) > 0.4 and laneClear(w, s, flatPuck, shotDir)

	if st.charging then
		-- Wind-up: keep the puck just past the toe on the line to the target.
		local aimAt = st.target or goal
		local away = aimAt - flatPuck
		local dir = if away.Magnitude > 1e-3 then away.Unit else shotDir
		moveVel(input, puckVel + capped((flatPuck - dir * HOLD - s.pos) * 5, 14))
		setShotAim(input, s, leadTarget(s, aimAt, st.shotSpeed or STICK.QuickShotSpeed), flatPuck, 0)
		-- The stick stays lifted through the wind-up and comes down on release.
		input.lift = true
		return "charging"
	end

	input.sprint = dist > 18 and s.stamina > 0.3

	-- Build 36: after WallClearSeconds with a slow puck on (or near) the boards and this bot on it,
	-- get rid of it: back to a teammate behind with a clear lane, or rimmed hard up the boards (it
	-- rides them round the corner to the other side). Bots used to dig at a pinned puck for ages.
	-- The clock runs ahead of the jam breaker, so stepping out of a jam doesn't restart it (a bot
	-- in a corner once looped jam, step out, come back for 24 seconds).
	do
		local gap, gnx, gnz = Sim.boardGap(flatPuck.X, flatPuck.Z)
		local onWall = gap < 3 and puckVel.Magnitude < 8
		if onWall and dist < 10 then
			st.wallTime = (st.wallTime or 0) + BOTS.ThinkInterval
		elseif gap >= 3 or dist > 14 then
			st.wallTime = 0
		end
		if onWall and (st.wallTime or 0) > BOTS.WallClearSeconds and dist < 6 and s.stickState == Sim.IDLE then
			st.wallTime = 0
			st.stuck = 0
			st.jam = 0
			local n = Vector3.new(gnx, 0, gnz)
			local want = carryDirection(flatPuck, attack)
			local t = want - n * want:Dot(n)
			t = if t.Magnitude > 1e-3 then t.Unit else Vector3.new(-n.Z, 0, n.X)
			-- A swing sends the puck from where the skater can stand: HOLD behind it on the line.
			-- In a rounded corner the spot behind a puck tight to the boards is inside them, so a
			-- line nearly along the boards can't be swung at (the blade fell 2 studs short and the
			-- puck sat there until the stuck reset).
			local function reachable(dir: Vector3): boolean
				local stand = flatPuck - dir * HOLD
				return (Sim.boardGap(stand.X, stand.Z)) >= Config.Skater.BoardRadius + 0.1
			end
			local mate, mateScore = nil, -math.huge
			for _, o in w.skaters do
				if o ~= s and o.team == s.team and not o.goalie then
					local rel = Vector3.new(o.pos.X - flatPuck.X, 0, o.pos.Z - flatPuck.Z)
					local d = rel.Magnitude
					if attack * rel.X < -3 and d > 8 and d < 50 and reachable(rel / d) and laneClear(w, s, flatPuck, rel / d) then
						local score = -d
						if score > mateScore then
							mate, mateScore = o, score
						end
					end
				end
			end
			if mate then
				local passAt = insideRink(Vector3.new(mate.pos.X, 0, mate.pos.Z) + Vector3.new(mate.vel.X, 0, mate.vel.Z) * 0.4)
				takeShot(w, s, st, input, passAt, flatPuck, BOTS.QuickWindSeconds)
				return "wallclearpass"
			end
			-- Rim it: as flat along the boards as the skater can still swing from.
			local rim = (t - n * 0.12).Unit
			for _, into in { 0.12, 0.35, 0.6, 0.9, 1.3 } do
				rim = (t - n * into).Unit
				if reachable(rim) then
					break
				end
			end
			takeShot(w, s, st, input, flatPuck + rim * 45, flatPuck, BOTS.WallClearWind)
			return "wallclear"
		end
	end

	-- Jam breaker: a chaser that has hardly moved for a while is wedged against another body,
	-- the net or the boards. Poke the puck if it is in reach, otherwise step out for a moment.
	if st.escapeUntil and w.time < st.escapeUntil and st.escapeDir then
		input.lift = true
		moveVel(input, st.escapeDir * 20)
		return "escape"
	end
	if Vector3.new(s.vel.X, 0, s.vel.Z).Magnitude < 2 then
		st.jam = (st.jam or 0) + BOTS.ThinkInterval
	else
		st.jam = 0
	end
	if (st.jam or 0) > 1.2 then
		st.jam = 0
		if dist < TOE + 2 and dist > 1e-3 and s.stickState == Sim.IDLE then
			takeShot(w, s, st, input, s.pos + toPuck / dist * 30, flatPuck, BOTS.QuickWindSeconds)
			return "poke"
		end
		local _, nx, nz = Sim.boardGap(s.pos.X, s.pos.Z)
		local inward = Vector3.new(nx, 0, nz)
		local sideways = Vector3.new(-nz, 0, nx) * (if rng:NextNumber() < 0.5 then 1 else -1)
		st.escapeDir = (inward + sideways).Unit
		st.escapeUntil = w.time + 0.5
		return "escape"
	end

	-- Snap shot: whenever the puck sits where a stick pointed at the net would meet it, lift
	-- the stick, swing it onto that line in one go (lifted, so it cannot knock the puck away on
	-- the way round) and shoot. The shot leaves along the stick, whatever the puck was doing.
	if canShoot and s.stickState == Sim.IDLE then
		local rel = toPuck + (puckVel - Vector3.new(s.vel.X, 0, s.vel.Z)) * 0.08
		local along = rel:Dot(shotDir)
		local lateral = (rel - shotDir * along).Magnitude
		if along > 1.5 and along < TOE + 1.5 and lateral < 2.2 then
			-- Build 32: a real wind-up unless an opponent is right on the puck or the net is a
			-- stride away (snap shots used to be a tap from anywhere inside 36 studs).
			local quick = goalDist < BOTS.TapShotRange or crowded(w, s, flatPuck, BOTS.CrowdRadius)
			takeShot(w, s, st, input, goal, flatPuck + puckVel * 0.08, if quick then BOTS.QuickWindSeconds else rng:NextNumber(BOTS.MinChargeSeconds, BOTS.MaxChargeSeconds * 0.65))
			return "snap"
		end
	end

	-- Puck tight on the wall: hold the stick along the boards with the blade on the ice side of
	-- the puck, which scoops it off the wall, then skate off the wall with it. Pointing the stick
	-- at the boards instead would jam it against them and the puck would only crawl along. A puck
	-- even a little off the wall has room for the blade behind it, so it is carried as normal.
	local wallGap, wnx, wnz = Sim.boardGap(flatPuck.X, flatPuck.Z)
	if wallGap < Config.Puck.Radius + STICK.ScoopBoardGap + 0.2 and dist < 16 then
		local n = Vector3.new(wnx, 0, wnz)
		local want = carryDirection(flatPuck, attack)
		local t = want - n * want:Dot(n)
		t = if t.Magnitude > 1e-3 then t.Unit else Vector3.new(-n.Z, 0, n.X)
		-- The body can't get closer to the boards than BoardRadius, so dig from there.
		local digAt = flatPuck - t * STICK.Reach + n * math.max(FACE + 0.1, Config.Skater.BoardRadius + 0.05 - wallGap)
		-- Build 30: pinned on the wall with an opponent on the puck (or stuck there a moment),
		-- look up and move it along the boards to a teammate instead of only digging.
		if s.stickState == Sim.IDLE and bladeDistance(s, flatPuck) < FACE + 1.3 then
			local pressed = false
			for _, o in w.skaters do
				if o.team ~= s.team and not o.goalie and (Vector3.new(o.pos.X, 0, o.pos.Z) - flatPuck).Magnitude < 6 then
					pressed = true
					break
				end
			end
			if (pressed or (st.stuck or 0) > 0.4) and rng:NextNumber() < 0.4 then
				local mate = boardsTeammate(w, s, flatPuck, Vector3.new(-n.Z, 0, n.X), attack)
				if mate then
					st.stuck = 0
					local passAt = insideRink(Vector3.new(mate.pos.X, 0, mate.pos.Z) + Vector3.new(mate.vel.X, 0, mate.vel.Z) * 0.4)
					takeShot(w, s, st, input, passAt, flatPuck, BOTS.QuickWindSeconds)
					return "wallpass"
				end
			end
		end
		-- Two blades leaning on a puck against the wall hold it there, and a body at the boards
		-- limit can only nudge it along them at a crawl: after a moment of either, poke it out
		-- along the boards and off them. (A clean dig has the puck off the wall well above
		-- WALL_CRAWL long before the count runs out; the cut-off used to be 2, and a puck crawling
		-- at 2 kept resetting it.)
		if puckVel.Magnitude < WALL_CRAWL and s.stickState == Sim.IDLE and bladeDistance(s, flatPuck) < FACE + 1.3 then
			st.stuck = (st.stuck or 0) + BOTS.ThinkInterval
			if st.stuck > 0.8 then
				st.stuck = 0
				-- Swing along the stick's own line, turned a little toward the boards: the blade
				-- sweeps into the puck (it sits on the wall side) and sends it along and off them.
				local along = Vector3.new(math.cos(s.aimYaw), 0, math.sin(s.aimYaw))
				takeShot(w, s, st, input, s.pos + (along - n * 0.3).Unit * 30, flatPuck, BOTS.QuickWindSeconds)
				return "wallpoke"
			end
		else
			st.stuck = 0
		end
		local off = digAt - s.pos
		if (s.pos - flatPuck):Dot(t) > -1.5 and off.Magnitude > 2.5 then
			-- Ahead of the puck: swing wide off the wall and come back in behind it, with the stick
			-- held out toward open ice so it stays on the ice and clear of the puck.
			setAim(input, s, s.pos + n, 0)
			moveVel(input, puckVel + capped((insideRink(digAt + n * 4) - s.pos) * 4, 26))
			return "wallround"
		end
		setAim(input, s, s.pos + t * 10, 0)
		if bladeDistance(s, flatPuck) > FACE + 0.2 then
			moveVel(input, puckVel + capped(off * 4, 22))
			return "wallgo"
		end
		-- Blade on the puck: pull away from the wall and the puck comes with it.
		moveVel(input, t * math.max(puckVel:Dot(t), 4) + n * 11) -- was n * 6: pull off the wall harder (puck on the boards 32% of bot play, now about 21%)
		return "dig"
	end

	-- Collect and carry: the puck rides on the blade's face with the stick out to one side,
	-- and the skater pushes it toward the slot (or off the boards).
	local dir = carryDirection(if dist > 8 then spot else flatPuck, attack)
	local perp = Vector3.new(-dir.Z, 0, dir.X)
	-- Keep the stick on the side it is on unless the puck is clearly over the other side, so
	-- it is never flung across the body into the puck.
	local side = st.side or 1
	if toPuck:Dot(perp) * side < -1.2 or st.side == nil then
		side = if toPuck:Dot(perp) >= 0 then 1 else -1
	end
	st.side = side
	-- In shooting range, cut across the slot instead: carried that way the stick points at the
	-- net with the puck on its face, so the shot can go the moment the bot is lined up, with no
	-- stopping to skate round behind the puck. Only cut toward the middle, never into the boards.
	local cutting = false
	if canShoot then
		local cut = Vector3.new(side * shotDir.Z, 0, -side * shotDir.X)
		if cut.Z * flatPuck.Z <= 0 or math.abs(flatPuck.Z) < 14 then
			dir = (cut + shotDir * 0.3).Unit
			perp = Vector3.new(-dir.Z, 0, dir.X)
			cutting = true
		end
	end
	local stickDir = perp * side

	-- Shoot off the carry: puck on the blade, stick pointing near the net.
	local aimDir = Vector3.new(math.cos(s.aimYaw), 0, math.sin(s.aimYaw))
	if canShoot and s.stickState == Sim.IDLE and dist < 8 and aimDir:Dot(shotDir) > 0.8 and bladeDistance(s, flatPuck) < FACE + 1.1 then
		-- Build 31: a real wind-up whenever nobody is right on the bot (the stick swings well back
		-- round the body and comes through); a quick release only with a defender in its face.
		local charge = if crowded(w, s, flatPuck, BOTS.CrowdRadius) then BOTS.QuickWindSeconds else rng:NextNumber(BOTS.MinChargeSeconds, BOTS.MaxChargeSeconds * 0.7)
		takeShot(w, s, st, input, goal, flatPuck, charge)
		return "shoot"
	end
	local holdAt = flatPuck - stickDir * STICK.Reach - dir * FACE
	if dist > 10 then
		local target = spot - stickDir * STICK.Reach - dir * (FACE + 3)
		setMove(input, s, insideRink(target), 3)
		setAim(input, s, s.pos + stickDir, 0)
		return "approach"
	end
	local ahead = (s.pos - flatPuck):Dot(dir)
	local roundTo = holdAt - dir * 3
	if not cutting and ahead > -0.5 and Sim.boardGap(roundTo.X, roundTo.Z) > Config.Skater.CollisionRadius + 0.4 then
		-- In front of the puck: get back behind it without knocking it the wrong way. The stick
		-- stays on the ice, held out on the far side from the puck (never lifted across it).
		setAim(input, s, s.pos - toPuck, 0)
		moveVel(input, puckVel + capped((insideRink(roundTo) - s.pos) * 4, 26))
		return "around"
	end
	setAim(input, s, s.pos + stickDir, 0)
	local offset = insideRink(holdAt) - s.pos
	if offset.Magnitude < 1.6 then
		moveVel(input, dir * CARRY_SPEED + capped(offset * 5, 10))
		-- Far from the net with a teammate open ahead: sometimes pass instead.
		local mate = openTeammate(w, s, attack)
		if mate and goalDist > BOTS.ShootRange and s.stickState == Sim.IDLE and rng:NextNumber() < BOTS.PassChance * 0.1 then
			local passAt = mate.pos + mate.vel * 0.5
			st.target = passAt
			beginSwing(w, st, input, BOTS.QuickWindSeconds, passAt)
			return "pass"
		end
		return "carry"
	end
	-- Two sticks leaning on one still puck can hold each other there for ages, so after a
	-- moment poke it free: a quick swing along a line that still meets the puck, turned as far
	-- toward where the bot wants it to go as that allows.
	local still = puckVel.Magnitude < 2 and Vector3.new(s.vel.X, 0, s.vel.Z).Magnitude < 4
	if still and dist < TOE + 2 and dist > 1e-3 and s.stickState == Sim.IDLE then
		st.stuck = (st.stuck or 0) + BOTS.ThinkInterval
		if st.stuck > 0.8 then
			st.stuck = 0
			local line = toPuck / dist
			local turned = (line + dir * 0.6).Unit
			local pokeDir = if turned:Dot(line) > 0.82 then turned else line
			takeShot(w, s, st, input, s.pos + pokeDir * 30, flatPuck, BOTS.QuickWindSeconds)
			return "poke"
		end
	else
		st.stuck = 0
	end
	moveVel(input, puckVel + capped(offset * 4, 14))
	return "collect"
end

-- Against a carrier: step up and take the puck only in the cases BOTS lists; otherwise give them
-- space (contain).
local function shouldPressure(w: Sim.World, s: Sim.Skater, st: BotState, carrier: Sim.Skater, attack: number): boolean
	local any = st :: any
	if (any.pressureUntil or 0) > w.time then
		return true
	end
	local own = Vector3.new(-attack * GOAL.X, 0, 0)
	if (Vector3.new(carrier.pos.X, 0, carrier.pos.Z) - own).Magnitude < BOTS.PressureRange then
		return true
	end
	if (carrier.pos - s.pos).Magnitude < BOTS.PokeRange then
		-- Commit for a moment: decided afresh every think, a bot on the edge of poke range would
		-- flip between going in and sprinting back to its spot.
		any.pressureUntil = w.time + BOTS.PressureBurst
		return true
	end
	if carrier.pos.X * attack < 0 and (any.containTime or 0) > BOTS.PatienceSeconds then
		any.containTime = 0
		any.pressureUntil = w.time + BOTS.PressureBurst
		return true
	end
	return false
end

-- Passive defence: hold a gap between the carrier and our net, never past centre ice, facing
-- the play with the stick on the ice toward the puck (so a lazy pass or a deke too close still
-- gets poked).
local function thinkContain(w: Sim.World, s: Sim.Skater, st: BotState, carrier: Sim.Skater, attack: number)
	local input = s.input
	local any = st :: any
	any.containTime = (any.containTime or 0) + BOTS.ThinkInterval
	local own = Vector3.new(-attack * GOAL.X, 0, 0)
	local from = Vector3.new(carrier.pos.X, 0, carrier.pos.Z)
	local toNet = own - from
	local d = toNet.Magnitude
	local gap = math.clamp(d * 0.3, BOTS.ContainGapMin, BOTS.ContainGapMax)
	local target = if d > 1e-3 then from + toNet / d * math.min(gap, d * 0.8) else own
	if target.X * attack > 0 then
		-- Never chase past centre ice: wait for them at the red line.
		target = Vector3.new(0, 0, target.Z * 0.6)
	end
	target = insideRink(target)
	input.sprint = (target - s.pos).Magnitude > 28
	setMove(input, s, target, 7)
	setAim(input, s, w.puck.pos, 0)
end

-- Support play, read off the user's gameplay clips (Build 29). Players there never all chase:
-- the nearest goes for the puck, the next one gets open for a pass (the far lane a little ahead
-- when attacking, the gap between the puck and the net when defending, the net front once the
-- puck is deep), and the last one hangs back: in front of its own net when defending, at the
-- top of the zone or the red line waiting for a breakout when attacking. Nobody stands on a
-- fixed spot: each bot drifts a little round its spot, and teammates keep their distance.
local SPACING = 13 -- support players push away from teammates closer than this
local function supportRank(w: Sim.World, s: Sim.Skater): number
	local mine = (s.pos - w.puck.pos).Magnitude
	local rank = 0
	for _, other in w.skaters do
		if other ~= s and other.team == s.team and not other.goalie and (other.pos - w.puck.pos).Magnitude < mine then
			rank += 1
		end
	end
	return rank -- 1: the nearest helper (the chaser is 0), 2 and up: the ones further back
end

local function teamHasGoalie(w: Sim.World, team: number): boolean
	for _, other in w.skaters do
		if other.team == team and other.goalie then
			return true
		end
	end
	return false
end

local function thinkSupport(w: Sim.World, s: Sim.Skater, st: BotState, attack: number)
	local input = s.input
	local any = st :: any
	any.phase = any.phase or rng:NextNumber(0, math.pi * 2)
	local puck = w.puck
	local p = Vector3.new(puck.pos.X, 0, puck.pos.Z)
	local own = Vector3.new(-attack * GOAL.X, 0, 0)
	local defending = p.X * attack < 0
	local deep = p.X * attack > GOAL.X - 32 -- the puck is down in the attacking zone
	local farLane = if p.Z >= 0 then -1 else 1
	local rank = supportRank(w, s)
	-- A slow puck on the boards is a battle: the nearest helper comes in on the inside to dig it
	-- out, the way a second player supports a board battle (the pin test caught pucks stuck there).
	local battle = Sim.boardGap(p.X, p.Z) < 3.5 and puck.vel.Magnitude < 8
	-- Build 36: not when a teammate has it on the boards (the helper used to dive in and knock it
	-- off the player's stick); only when an opponent is on it too.
	local carrier = carrierOf(w)
	local mateOn = carrier ~= nil and carrier ~= s and carrier.team == s.team
	if battle then
		local contested = false
		for _, o in w.skaters do
			if o.team ~= s.team and not o.goalie and (Vector3.new(o.pos.X, 0, o.pos.Z) - p).Magnitude < 6 then
				contested = true
				break
			end
		end
		battle = contested and not mateOn
	end
	local target
	if rank <= 1 and battle then
		target = p + (if p.Magnitude > 1 then -p.Unit else Vector3.zero) * 3
	elseif rank <= 1 then
		if defending then
			-- Cover the pass to the slot: between the puck and our net, off the chaser's side.
			target = own:Lerp(p, if teamHasGoalie(w, s.team) then 0.5 else 0.38) + Vector3.new(0, 0, farLane * 7)
		elseif deep then
			-- Net front, on the far post, for a pass across or a rebound.
			target = Vector3.new(attack * (GOAL.X - 13), 0, farLane * 7)
		else
			-- Open in the far lane, a stride ahead of the puck, ready for a pass.
			target = Vector3.new(math.clamp(p.X + attack * 12, -70, 70), 0, farLane * 21)
		end
	else
		if defending then
			-- The safety: in front of our net (out at the hash marks if a goalie is in it).
			local out = if teamHasGoalie(w, s.team) then 22 else 11
			target = own + Vector3.new(attack * out, 0, -farLane * 5)
		else
			-- Hang back for the breakout: the top of the zone when it is deep, else the red line.
			local x = if deep then attack * (Config.Arena.BlueLineX + 6) else attack * math.clamp(p.X * attack - 34, -8, 20)
			target = Vector3.new(x, 0, -farLane * 9)
		end
	end
	-- Drift round the spot like a person waiting, never parked.
	local t = w.time
	if not battle then
		target += Vector3.new(math.sin(t * 0.45 + any.phase) * 4, 0, math.cos(t * 0.37 + any.phase * 1.7) * 5)
	end
	-- Keep away from teammates so two never stand in the same lane (but a board battle is two on it).
	for _, other in w.skaters do
		if not battle and other ~= s and other.team == s.team and not other.goalie then
			local away = Vector3.new(target.X - other.pos.X, 0, target.Z - other.pos.Z)
			local d = away.Magnitude
			if d < SPACING then
				target += (if d > 0.1 then away / d else Vector3.new(0, 0, farLane)) * (SPACING - d)
			end
		end
	end
	-- Build 36: give a teammate with the puck room (never within MateRoom of them).
	if mateOn and carrier then
		local away = Vector3.new(target.X - carrier.pos.X, 0, target.Z - carrier.pos.Z)
		local d = away.Magnitude
		if d < BOTS.MateRoom then
			target += (if d > 0.1 then away / d else Vector3.new(-attack, 0, farLane)) * (BOTS.MateRoom - d)
		end
	end
	target = insideRink(target)
	input.sprint = (target - s.pos).Magnitude > 34
	setMove(input, s, target, 8)
	setAim(input, s, puck.pos, 0)
end

-- Build 33: a skater going for a puck behind a net skated straight at it, into the net, and
-- stayed stuck in there until the puck came out. One that has ended up inside skates back out
-- of the mouth. Build 34: any skater whose path crosses a net (from the front, the side or
-- behind) now heads for the nearest corner round it instead, one corner at a time, so it goes
-- round the net rather than pushing against it.
local NET_HALF = GOAL.Width / 2
local NET_PAD = Config.Skater.CollisionRadius + 0.9 -- the body's reach past the net's edge
local CORNER_MARGIN = 1.2

-- Does the segment (ad, az) to (bd, bz) pass through the box d0..d1, z0..z1? (Slab test.)
local function crossesBox(ad: number, az: number, bd: number, bz: number, d0: number, d1: number, z0: number, z1: number): boolean
	local t0, t1 = 0, 1
	local dd, dz = bd - ad, bz - az
	if math.abs(dd) < 1e-9 then
		if ad <= d0 or ad >= d1 then
			return false
		end
	else
		local ta, tb = (d0 - ad) / dd, (d1 - ad) / dd
		if ta > tb then
			ta, tb = tb, ta
		end
		t0, t1 = math.max(t0, ta), math.min(t1, tb)
		if t0 >= t1 then
			return false
		end
	end
	if math.abs(dz) < 1e-9 then
		return az > z0 and az < z1
	end
	local ta, tb = (z0 - az) / dz, (z1 - az) / dz
	if ta > tb then
		ta, tb = tb, ta
	end
	return math.max(t0, ta) < math.min(t1, tb)
end

local function steerRoundNets(w: Sim.World, s: Sim.Skater, input: Sim.Input)
	local mx, mz = input.moveX, input.moveZ
	local m = math.sqrt(mx * mx + mz * mz)
	if m < 0.05 then
		return
	end
	local ux, uz = mx / m, mz / m
	-- How far ahead to look: to the puck when heading for it, otherwise a short way.
	local px, pz = w.puck.pos.X - s.pos.X, w.puck.pos.Z - s.pos.Z
	local pd = math.sqrt(px * px + pz * pz)
	local look = 10
	if pd > 1e-3 and (px * ux + pz * uz) / pd > 0.85 then
		look = math.min(pd, 40)
	end
	local ex, ez = s.pos.X + ux * look, s.pos.Z + uz * look
	local d0, d1 = -NET_PAD, GOAL.Depth + NET_PAD
	local z0, z1 = -(NET_HALF + NET_PAD), NET_HALF + NET_PAD
	for side = -1, 1, 2 do
		local depth = side * s.pos.X - GOAL.X -- behind the goal line is positive
		if depth > 0.3 and depth < GOAL.Depth + 0.5 and math.abs(s.pos.Z) < NET_HALF then
			-- Inside the net: out through the mouth, drifting toward the nearer post's side.
			local zSign = if s.pos.Z >= 0 then 1 else -1
			local ox, oz = -side, zSign * 0.25
			local k = m / math.sqrt(ox * ox + oz * oz)
			input.moveX, input.moveZ = ox * k, oz * k
			return
		end
		-- In this net's frame: d along its depth (behind the goal line is positive), z across.
		local sd, sz = depth, s.pos.Z
		local ed, ez2 = side * ex - GOAL.X, ez
		local startIn = sd > d0 and sd < d1 and sz > z0 and sz < z1
		local endIn = ed > d0 and ed < d1 and ez2 > z0 and ez2 < z1
		-- A target on the net itself (a puck in the crease) is played straight on.
		if not startIn and not endIn and crossesBox(sd, sz, ed, ez2, d0, d1, z0, z1) then
			local bestD, bestZ, bestCost = 0, 0, math.huge
			for ci = 1, 4 do
				local cd = if ci <= 2 then d0 - CORNER_MARGIN else d1 + CORNER_MARGIN
				local cz = if ci % 2 == 1 then z0 - CORNER_MARGIN else z1 + CORNER_MARGIN
				if not crossesBox(sd, sz, cd, cz, d0, d1, z0, z1) then
					local cost = math.sqrt((cd - sd) ^ 2 + (cz - sz) ^ 2) + math.sqrt((ed - cd) ^ 2 + (ez2 - cz) ^ 2)
					if cost < bestCost then
						bestD, bestZ, bestCost = cd, cz, cost
					end
				end
			end
			if bestCost < math.huge then
				local tx, tz = side * (GOAL.X + bestD), bestZ
				local dx, dz = tx - s.pos.X, tz - s.pos.Z
				local d = math.sqrt(dx * dx + dz * dz)
				if d > 0.2 then
					input.moveX, input.moveZ = dx / d * m, dz / d * m
				end
			end
			return
		end
	end
end

-- Build 39: the face-off draw. The centres used to wait, ease in and lean on each other at the
-- dot. Now a bot centre goes straight for the dropped puck and sweeps it back to a winger on its
-- own side. A swing sends the puck along the stick, so the bot skates round to stand HOLD past
-- the puck on the line from the winger through it (stick lifted on the way, so it doesn't knock
-- the puck off), then sends a quick pass. Two bot centres take opposite sides (their slots
-- decide which), so they go round each other instead of meeting head on.
local function isCentre(o: Sim.Skater): boolean
	return not o.goalie and o.slot ~= nil and ((o.faceoffIdx or o.slot) - 1) % 3 + 1 == 1
end

local function faceoffFoe(w: Sim.World, s: Sim.Skater): Sim.Skater?
	for _, o in w.skaters do
		if o.team ~= s.team and isCentre(o) then
			return o
		end
	end
	return nil
end

-- TeamService hands each bot the slots players hold (st.humans); the sim tests have none.
local function isHuman(st: BotState, o: Sim.Skater?): boolean
	local humans = (st :: any).humans
	return o ~= nil and humans ~= nil and humans[o.slot] ~= nil
end

local DRAW_REACH = STICK.Reach + STICK.BladeLength * 0.3 -- the puck on the outer blade

local function thinkDraw(w: Sim.World, s: Sim.Skater, st: BotState, attack: number): boolean
	local input = s.input
	local any = st :: any
	local puck = w.puck
	local flatPuck = Vector3.new(puck.pos.X, 0, puck.pos.Z)
	local flatS = Vector3.new(s.pos.X, 0, s.pos.Z)
	if any.drawFor ~= any.dropTime then
		any.drawFor = any.dropTime
		-- A little quicker or slower off the mark each time, so one centre gets there first.
		any.drawPace = rng:NextNumber(0.82, 1)
		local foe = faceoffFoe(w, s)
		local p = if ((s.slot or 0) + (if foe then foe.slot or 0 else 0)) % 2 == 0 then 1 else -1
		local wantZ = p * attack -- team 2's spots are the mirror image, so the two pick opposite sides
		local mate, best = nil, -math.huge
		for _, o in w.skaters do
			if o ~= s and o.team == s.team and not o.goalie then
				local score = o.pos.Z * wantZ
				if score > best then
					mate, best = o, score
				end
			end
		end
		-- Into the winger's lane a little ahead of them (halfway back to the dot), so the pass
		-- goes back and across and they skate onto it.
		any.drawTarget = if mate
			then insideRink(Vector3.new(mate.pos.X * 0.5, 0, mate.pos.Z))
			else insideRink(Vector3.new(-attack * 10, 0, wantZ * 16))
	end
	local target = any.drawTarget :: Vector3
	local away = target - flatPuck
	if away.Magnitude < 2 then
		return false
	end
	local dir = away.Unit
	local stand = flatPuck - dir * DRAW_REACH
	-- Shoot the moment the puck sits on the outer blade on that line (the swing leaves along the
	-- line from the skater to the puck; much further out the blade misses it), without waiting to
	-- stop dead on the spot.
	local toPuck = flatPuck - flatS
	local along = toPuck:Dot(dir)
	-- (Not still sliding through, though: the wind-up would carry the blade off the puck.)
	local slide = Vector3.new(s.vel.X - puck.vel.X, 0, s.vel.Z - puck.vel.Z).Magnitude
	if math.abs(along - DRAW_REACH) < 0.8 and (toPuck - dir * along).Magnitude < 1 and slide < 15 and puck.pos.Y < 2.5 and s.stickState == Sim.IDLE then
		any.drawDone = any.dropTime
		takeShot(w, s, st, input, target, flatPuck, BOTS.QuickWindSeconds)
		return true
	end
	-- Circle the puck (the short way round) at the stick's distance toward that spot, never through
	-- it: round the circle, slowing as the spot comes up, with a pull in or out to hold the radius
	-- (steering at points on the circle let the glide carry the bot well wide of it).
	local rel = flatS - flatPuck
	local r = rel.Magnitude
	local from = math.atan2(rel.Z, rel.X)
	local turn = (math.atan2(-dir.Z, -dir.X) - from + math.pi) % (2 * math.pi) - math.pi
	-- A straight run to the spot that passes clear of the puck (the usual case from the dot) is
	-- quickest; skates turn too slowly to circle fast, so any orbit is gentle.
	local path = stand - flatS
	local len = path.Magnitude
	local clear = true
	if len > 1e-3 then
		local k = math.clamp(-rel:Dot(path) / (len * len), 0, 1)
		clear = (rel + path * k).Magnitude > Config.Skater.PuckBodyRadius + Config.Puck.Radius
	end
	local want: Vector3
	if clear or math.abs(turn) <= math.rad(18) or r < 1e-3 then
		-- Full speed most of the way, easing off over the last few studs to arrive slow.
		want = if len > 1e-3 then path / len * math.clamp(len * 3.5, 3, 22) else Vector3.zero
	else
		local out = rel / r
		local round = Vector3.new(-out.Z, 0, out.X) * math.sign(turn)
		want = round * math.clamp(math.abs(turn) * HOLD * 2.5, 6, 13) + out * (HOLD - r) * 4
	end
	input.lift = true
	input.sprint = false
	moveVel(input, puck.vel * Vector3.new(1, 0, 1) + want * (any.drawPace or 1))
	setAim(input, s, s.pos + dir * 10, 0)
	return true
end

function BotBrain.think(w: Sim.World, s: Sim.Skater, role: Role, st: BotState, dt: number)
	local input = s.input

	-- Swing release has to be tick-accurate, so it runs outside the slower think gate.
	if st.charging then
		-- Release early if the puck is slipping out of the blade's shot window.
		local gap = (Vector3.new(w.puck.pos.X, 0, w.puck.pos.Z) - s.blade).Magnitude
		local window = STICK.BladeLength / 2 + Config.Puck.Radius + STICK.BladeThickness + STICK.ShotForgiveness
		local windowClosing = gap > window - 0.8 and s.windTime > STICK.QuickThreshold
		if w.time >= st.releaseAt or windowClosing then
			st.charging = false
			input.charge = false
			input.lift = false
		end
	end

	st.timer -= dt
	if st.timer > 0 then
		-- Between thinks, glide the stick toward the last think's aim so it turns at a steady rate
		-- instead of jumping there in one tick and then standing still.
		local goalYaw = (st :: any).goalYaw
		if goalYaw then
			local left = math.max(1, math.round(st.timer / dt) + 1)
			local turn = (goalYaw - s.aimYaw + math.pi) % (2 * math.pi) - math.pi
			local yaw = s.aimYaw + turn / left
			local r = (st :: any).goalR or 1
			input.aimX, input.aimZ = math.cos(yaw) * r, math.sin(yaw) * r
		end
		return
	end
	st.timer = BOTS.ThinkInterval
	input.lift = false
	;(st :: any).goalYaw = nil
	-- Build 30: note when a face-off puck is dropped (it hangs over the dot until then).
	do
		local any = st :: any
		if w.puckHeld then
			any.heldSeen = true
		elseif any.heldSeen then
			any.heldSeen = false
			any.dropTime = w.time
		end
	end

	if role == "Dummy" then
		input.moveX, input.moveZ = 0, 0
		return
	end

	if not w.controlsEnabled or not w.stickHits or not w.goalsEnabled then
		st.charging = false
		input.charge = false
		input.moveX, input.moveZ = 0, 0
		setAim(input, s, w.puck.pos, 0)
		return
	end

	local heldX, heldZ = input.aimX, input.aimZ
	local attack = if s.team == 1 then 1 else -1
	local puckGap = Vector3.new(w.puck.pos.X - s.pos.X, 0, w.puck.pos.Z - s.pos.Z).Magnitude
	turnStep = if st.charging then math.huge
		elseif puckGap < STICK.Reach + 4 then GENTLE_STEP
		elseif puckGap < 14 then NEAR_STEP
		else math.huge
	-- Build 30: a teammate on the puck keeps it: the bot gets open instead of taking it off them
	-- (one used to dive in on its own centre). And for a moment after a face-off drop the
	-- wingers hold their lanes unless the puck comes right to them; the centres battle for it.
	local carrierNow = carrierOf(w)
	local mateHasIt = carrierNow ~= nil and carrierNow ~= s and carrierNow.team == s.team
	-- Build 36: a teammate who just had it (a deke or a big stride puts the puck a little off
	-- their blade) still has it for MateCarryGrace, so the bot doesn't swoop in and take it.
	do
		local any = st :: any
		if mateHasIt then
			any.mateCarrier, any.mateCarryAt = carrierNow, w.time
		elseif carrierNow == nil and any.mateCarrier and w.time - (any.mateCarryAt or 0) < BOTS.MateCarryGrace then
			local m = any.mateCarrier :: Sim.Skater
			if (Vector3.new(w.puck.pos.X - m.blade.X, 0, w.puck.pos.Z - m.blade.Z)).Magnitude < 6 then
				mateHasIt = true
			end
		end
	end
	local dropTime = (st :: any).dropTime
	local wing = s.slot ~= nil and ((s.faceoffIdx or s.slot) - 1) % 3 + 1 ~= 1
	local holdLane = wing and dropTime ~= nil and w.time - dropTime < BOTS.FaceoffGrace
		and Vector3.new(w.puck.pos.X - s.pos.X, 0, w.puck.pos.Z - s.pos.Z).Magnitude > 6
	-- Build 34: the goalie seat lines up for the face-off with the other two and then chooses
	-- each think: a loose puck near it while it is far from its net, it plays like a skater; its
	-- team holding the puck deep in the other end, it steps up to the red line as an extra man;
	-- anything else, back to the net.
	local goalieMode = "net"
	-- Build 36: a practice goalie always stays home (never skates out after a puck or roams).
	if role == "Goalie" and not st.practice then
		local ownNet = Vector3.new(-attack * GOAL.X, 0, 0)
		local fromNet = (Vector3.new(s.pos.X, 0, s.pos.Z) - ownNet).Magnitude
		local hasIt = (Vector3.new(w.puck.pos.X, 0, w.puck.pos.Z) - Vector3.new(s.blade.X, 0, s.blade.Z)).Magnitude < CARRY_GAP
		if hasIt or (fromNet > BOTS.GoalieChaseFromNet and puckGap < 9 and carrierNow == nil) then
			goalieMode = "skate"
		elseif carrierNow and carrierNow.team == s.team and attack * carrierNow.pos.X > BOTS.GoalieRoamLine then
			goalieMode = "roam"
		end
	end
	if role == "Goalie" and goalieMode == "skate" then
		thinkChase(w, s, st, attack)
	elseif role == "Goalie" and goalieMode == "roam" then
		local zSide = if (carrierNow and carrierNow.pos.Z or 0) >= 0 then -1 else 1
		setMove(input, s, Vector3.new(attack * BOTS.GoalieRoamX, 0, zSide * 10), 4)
		input.sprint = false
		setAim(input, s, w.puck.pos, 0)
	elseif role == "Goalie" then
		thinkGoalie(w, s, st, attack)
		-- Skating back from the face-off spot (or from roaming): hurry. Build 39: dash there, a
		-- fresh press each time the last dash is spent (holding the key only dashes once), while
		-- it is more than GoalieDashFrom studs out and has the stamina.
		local ownNet = Vector3.new(-attack * GOAL.X, 0, 0)
		local home = ownNet - Vector3.new(s.pos.X, 0, s.pos.Z)
		local far = home.Magnitude > BOTS.GoalieDashFrom
		local move = Vector3.new(input.moveX, 0, input.moveZ)
		local homeward = move.Magnitude > 0.5 and move.Unit:Dot(home.Unit) > 0.7
		input.sprint = input.sprint
			or (far and homeward and not s.sprintHeld and s.dashCooldown <= 0 and s.stamina >= Config.Skater.DashCost)
	elseif role ~= "Goalie" and not wing and dropTime ~= nil and w.time - dropTime < BOTS.FaceoffDrawWindow
		and (st :: any).drawDone ~= dropTime and not st.charging and (carrierNow == nil or isCentre(carrierNow))
		and Vector3.new(w.puck.pos.X, 0, w.puck.pos.Z).Magnitude < 12
		and thinkDraw(w, s, st, attack)
	then
		-- Build 39: the face-off draw (thinkDraw) has this think.
	elseif mateHasIt or holdLane then
		thinkSupport(w, s, st, attack)
	elseif closestFieldSkater(w, s.team) == s then
		local carrier = carrierNow
		local branch
		if carrier and carrier.team ~= s.team and not shouldPressure(w, s, st, carrier, attack) then
			thinkContain(w, s, st, carrier, attack)
			branch = "contain"
		else
			if not (carrier and carrier.team ~= s.team) then
				(st :: any).containTime = 0
			end
			branch = thinkChase(w, s, st, attack)
		end
		-- Optional branch counter for tuning harnesses; nil in normal play.
		local stats = (BotBrain :: any).stats
		if stats then
			stats[branch] = (stats[branch] or 0) + 1
		end
	else
		thinkSupport(w, s, st, attack)
	end
	if role ~= "Goalie" or goalieMode ~= "net" then
		steerRoundNets(w, s, input)
	end
	-- Build 34: right after the drop the bot centre takes a moment to react, and nobody sprints
	-- (a sprint press is a dash).
	-- Build 39: only against a player's centre; two bot centres both go straight in, and the goalie
	-- seat heading back to its net is never held back.
	if dropTime ~= nil then
		local since = w.time - dropTime
		local centre = role ~= "Goalie" and not wing
		local vsPlayer = isHuman(st, faceoffFoe(w, s))
		local homeward = role == "Goalie" and goalieMode == "net"
		if centre and vsPlayer and since < BOTS.FaceoffReaction then
			input.moveX, input.moveZ = 0, 0
		elseif since < BOTS.FaceoffEase and not homeward and (vsPlayer or not centre) then
			-- Build 36: no bot (centre, winger or goalie seat) bursts onto the puck straight after the drop.
			input.moveX *= BOTS.FaceoffEaseSpeed
			input.moveZ *= BOTS.FaceoffEaseSpeed
		end
		if since < BOTS.FaceoffCalm and not homeward then
			input.sprint = false
		end
	end
	-- A released swing keeps its line until it is over, or the shot would leave off it.
	if s.stickState == Sim.ACTIVE then
		input.aimX, input.aimZ = heldX, heldZ
	end
	-- Remember where this think wants the stick, and take the first step of the glide there now.
	local r = math.sqrt(input.aimX * input.aimX + input.aimZ * input.aimZ)
	if r > 0.01 then
		local goalYaw = math.atan2(input.aimZ, input.aimX)
		local any = st :: any
		any.goalYaw, any.goalR = goalYaw, r
		local steps = math.max(1, math.round(BOTS.ThinkInterval / dt))
		local turn = (goalYaw - s.aimYaw + math.pi) % (2 * math.pi) - math.pi
		local yaw = s.aimYaw + turn / steps
		input.aimX, input.aimZ = math.cos(yaw) * r, math.sin(yaw) * r
	end
end

return BotBrain
