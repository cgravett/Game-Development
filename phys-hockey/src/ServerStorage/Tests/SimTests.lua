--!strict
-- Headless acceptance tests for the pure model (Appendix J). No Play session needed.
-- SimTests.run(sharedFolder) returns a list of "PASS/FAIL name: detail" lines.

local SimTests = {}

function SimTests.run(shared: any): { string }
	local Config = require(shared.GameConfig)
	local Sim = require(shared.Sim)
	local Protocol = require(shared.Protocol)
	local BotBrain = require(shared.BotBrain)
	local World = Sim.World
	local TICK = Config.Tick

	local out: { string } = {}
	local function check(name: string, ok: boolean, detail: any?)
		table.insert(out, `{if ok then "PASS" else "FAIL"} {name}: {tostring(detail or "")}`)
	end

	-- Login rewards: the streak rule (Shared/LoginRewards).
	do
		local LR = require(shared.LoginRewards)
		local fresh = LR.evaluate(-1, 0, 100)
		check("login: new player claims day 1", fresh.canClaim and fresh.slot == 1, fresh.slot)
		local next = LR.evaluate(99, 3, 100)
		check("login: yesterday continues the streak", next.canClaim and next.slot == 4, next.slot)
		local same = LR.evaluate(100, 4, 100)
		check("login: no second claim the same day", not same.canClaim and same.slot == 4, same.slot)
		local missed = LR.evaluate(97, 5, 100)
		check("login: a missed day restarts at day 1", missed.canClaim and missed.slot == 1 and missed.streak == 0, missed.slot)
		local wrap = LR.evaluate(99, 7, 100)
		check("login: after day 7 it goes round to day 1", wrap.canClaim and wrap.slot == 1, wrap.slot)
		local skew = LR.evaluate(101, 2, 100)
		check("login: a save from a later day counts as claimed", not skew.canClaim, skew.slot)
		check("login: a day lasts until the next UTC midnight", LR.dayEnds(LR.dayIndex(86400 * 5 + 10)) == 86400 * 6, LR.dayEnds(5))
	end

	-- Build 34: the Mystery Box's odds (the shop shows the same table the server rolls).
	do
		local MB = require(shared.MysteryBox)
		local function sum(list)
			local t = 0
			for _, o in list do
				t += o.p
			end
			return t
		end
		local all = MB.odds({})
		check("box: odds add up to 100%", math.abs(sum(all) - 1) < 1e-9, sum(all))
		local tiers = MB.tierOdds({})
		check("box: tier odds as designed", math.abs(tiers.rink - 0.05) < 1e-9 and math.abs(tiers.outfit - 0.1) < 1e-9 and math.abs(tiers.hat - 0.2) < 1e-9 and math.abs(tiers.stick - 0.2) < 1e-9, `rink {tiers.rink}, outfit {tiers.outfit}`)
		check("box: every tier has items", #MB.Members.rink == 5 and #MB.Members.outfit == 3 and #MB.Members.hat > 0 and #MB.Members.stick > 0 and #MB.Members.bonus > 0, #MB.Members.rink)
		-- Own every rink: they leave the box and the rest still adds up to 100%.
		local owned = {}
		for _, id in MB.Members.rink do
			owned[id] = true
		end
		local left = MB.odds(owned)
		local rinkLeft = false
		for _, o in left do
			if o.tier == "rink" or owned[o.id] then
				rinkLeft = true
			end
		end
		check("box: owned items are taken out and the rest renormalised", not rinkLeft and math.abs(sum(left) - 1) < 1e-9, sum(left))
		-- The roll follows the table: 20,000 even draws land near the listed tier odds.
		local counts = {}
		for i = 0, 19999 do
			local id = MB.pick({}, (i + 0.5) / 20000)
			local item = id and require(shared.Catalog).ById[id]
			local tier = item and MB.tierOf(item)
			if tier then
				counts[tier] = (counts[tier] or 0) + 1
			end
		end
		check("box: rolls match the odds", math.abs((counts.rink or 0) / 20000 - 0.05) < 0.002 and math.abs((counts.hat or 0) / 20000 - 0.2) < 0.002, `rink {counts.rink}, hat {counts.hat}`)
		local everything = {}
		for _, list in MB.Members do
			for _, id in list do
				everything[id] = true
			end
		end
		check("box: nothing left to win means no box", #MB.odds(everything) == 0 and MB.pick(everything, 0.5) == nil, #MB.odds(everything))
		check("box: percentages never round a chance to 0", MB.percent(0.0000123) == "0.00123%" and MB.percent(1 / 3) == "33.333%", MB.percent(0.0000123))
	end

	local function emptyWorld()
		local w = World.new()
		w.controlsEnabled = true
		w.stickHits = true
		w.goalsEnabled = true
		return w
	end

	-- Build 35: on a breakaway the goalie comes out to cut the angle, even when the shooter has
	-- pushed the puck ahead on a dash; with nobody coming it stays home.
	do
		local GOAL = Config.Goal
		local function breakaway(puckAhead: number?, attackerX: number?): number
			local w = emptyWorld()
			local g = Sim.newSkater(6, 2)
			g.goalie = true
			g.pos = Vector3.new(GOAL.X - Config.Bots.GoalieArc, 0, 0)
			g.blade = Sim.bladeAt(g.pos, g.aimYaw, 1)
			g.bladePrev = g.blade
			w.skaters[6] = g
			local a = Sim.newSkater(1, 1)
			a.pos = Vector3.new(attackerX or (GOAL.X - 30), 0, 3)
			a.blade = Sim.bladeAt(a.pos, a.aimYaw, 1)
			a.bladePrev = a.blade
			w.skaters[1] = a
			w.puck.pos = if puckAhead then a.pos + Vector3.new(puckAhead, 0.3, 0) else Vector3.new(a.blade.X, 0.3, a.blade.Z)
			w.puck.vel = Vector3.zero
			local st = BotBrain.newState()
			st.easy = true
			for _ = 1, 90 do
				BotBrain.think(w, g, "Goalie", st, TICK)
				World.step(w, TICK)
			end
			return GOAL.X - g.pos.X
		end
		local carried = breakaway()
		check("goalie comes out on a breakaway", carried > 9, `{math.round(carried * 10) / 10} studs out`)
		local pushed = breakaway(4.5)
		check("goalie comes out on a dash-pushed puck", pushed > 9, `{math.round(pushed * 10) / 10} studs out`)
		local far = breakaway(nil, GOAL.X - 80)
		check("goalie stays home with nobody close", far < 8, `{math.round(far * 10) / 10} studs out`)
	end

	local function countEvents(w, kind: string): number
		local n = 0
		for _, e in World.drainEvents(w) do
			if e.kind == kind then
				n += 1
			end
		end
		return n
	end

	local function shootPuck(from: Vector3, vel: Vector3, seconds: number)
		local w = emptyWorld()
		World.placePuck(w, from, vel)
		local goals = 0
		for _ = 1, math.round(seconds / TICK) do
			World.step(w, TICK)
			goals += countEvents(w, "Goal")
		end
		return goals, w
	end

	-- Diagonal WASD is no faster than straight movement.
	do
		local a, b = Sim.newSkater(1, 1), Sim.newSkater(2, 1)
		local straight, diagonal = Sim.newInput(), Sim.newInput()
		straight.moveX = 1
		diagonal.moveX, diagonal.moveZ = 1, 1
		for _ = 1, 180 do
			a.pos, b.pos = Vector3.zero, Vector3.zero
			Sim.stepMotion(a, straight, TICK, true)
			Sim.stepMotion(b, diagonal, TICK, true)
		end
		check("diagonal not faster", b.vel.Magnitude <= a.vel.Magnitude + 1e-3, `{a.vel.Magnitude} vs {b.vel.Magnitude}`)
		check("top speed respected", a.vel.Magnitude <= Config.Skater.MaxSpeed + 1e-3, a.vel.Magnitude)
	end

	-- Skater glides with no key pressed and stops in a documented distance.
	do
		local s = Sim.newSkater(1, 1)
		s.vel = Vector3.new(Config.Skater.MaxSpeed, 0, 0)
		s.pos = Vector3.new(-40, 0, 0)
		local start = s.pos
		local input = Sim.newInput()
		local t = 0
		while s.vel.Magnitude > 0 and t < 10 do
			Sim.stepMotion(s, input, TICK, true)
			t += TICK
		end
		local d = (s.pos - start).Magnitude
		check("coast stops", t < 2.0 and d > 14 and d < 24, `{math.round(t * 100) / 100}s over {math.round(d)} studs`)
	end

	-- Mouse aim rotates the stick while the skater keeps its heading, within the rate limit.
	do
		local s = Sim.newSkater(1, 1)
		s.vel = Vector3.new(20, 0, 0)
		local input = Sim.newInput()
		input.moveX = 1
		input.aimX, input.aimZ = -1, 0
		local before = s.aimYaw
		Sim.stepMotion(s, input, TICK, true)
		Sim.stepStick(s, input, TICK)
		local turned = math.abs(s.aimYaw - before)
		check("aim rate limited", turned <= Config.Stick.MaxAimRadiansPerSecond * TICK + 1e-6, turned)
		check("aim leaves heading alone", s.vel.Unit:Dot(Vector3.xAxis) > 0.999, s.vel)
	end

	-- Fast stick sweep imparts a stronger impulse than a slow brush.
	do
		local function sweep(speedScale: number): number
			local w = emptyWorld()
			local s = Sim.newSkater(1, 1)
			w.skaters[1] = s
			s.pos = Vector3.new(-30, 0, 0)
			World.placeSkater(s, s.pos)
			s.aimYaw, s.aimRadius = -1.2, 1
			s.blade = Sim.bladeAt(s.pos, s.aimYaw, 1)
			s.bladePrev = s.blade
			World.placePuck(w, Sim.bladeAt(s.pos, 0, 1))
			local peak = 0
			local yaw = -1.2
			for _ = 1, 60 do
				yaw += 12 * TICK * speedScale
				s.input.aimX, s.input.aimZ = math.cos(yaw), math.sin(yaw)
				World.step(w, TICK)
				peak = math.max(peak, w.puck.vel.Magnitude)
			end
			return peak
		end
		local slow, fast = sweep(0.15), sweep(1)
		check("fast sweep stronger", fast > slow * 2, `slow {math.round(slow)} fast {math.round(fast)}`)
		check("sweep under puck cap", fast <= Config.Puck.MaxSpeed + 16, fast)
	end

	-- Goal rules.
	local GX = Config.Goal.X
	-- A shot deflected in off a defender is still the shooter's goal; with no touch from the
	-- scoring team it is an own goal.
	do
		local function creditFor(history: { number }, sticks: { number }?): (number?, boolean?, number?)
			local w = emptyWorld()
			w.skaters[1] = Sim.newSkater(1, 1)
			w.skaters[2] = Sim.newSkater(2, 1)
			w.skaters[3] = Sim.newSkater(3, 2)
			World.placeSkater(w.skaters[1], Vector3.new(-60, 0, 30))
			World.placeSkater(w.skaters[2], Vector3.new(-60, 0, -30))
			World.placeSkater(w.skaters[3], Vector3.new(-40, 0, 30))
			w.touchHistory = table.clone(history)
			w.touch1 = history[1]
			World.placePuck(w, Vector3.new(GX - 20, 0, 0), Vector3.new(120, 0, 0))
			if sticks then
				w.stickHistory = table.clone(sticks)
			end
			for _ = 1, 120 do
				World.step(w, TICK)
				for _, e in World.drainEvents(w) do
					if e.kind == "Goal" then
						return e.scorer, e.ownGoal, e.assist
					end
				end
			end
			return nil, nil, nil
		end
		local scorer, own, assist = creditFor({ 3, 1, 2 })
		check("deflection keeps the shooter's goal, no assist", scorer == 1 and own == false and assist == nil, `{scorer} {own} {assist}`)
		local s3, _, assist3 = creditFor({ 1, 2 })
		check("clean goal keeps its assist", s3 == 1 and assist3 == 2, `{s3} {assist3}`)
		local s2, own2 = creditFor({ 3 })
		check("no own goals: a defender's own touch credits nobody", s2 == nil and own2 == false, `{s2} {own2}`)
		-- Build 32: in off a teammate's body, the shooter's goal (body touches take no credit).
		local s4, _, assist4 = creditFor({ 2, 1 }, { 1 })
		check("off a teammate's body: shooter's goal", s4 == 1 and assist4 == nil, `{s4} {assist4}`)
	end
	do
		local goals = shootPuck(Vector3.new(GX - 20, 0, 0), Vector3.new(120, 0, 0), 2)
		check("centre shot scores exactly once", goals == 1, goals)
		local other = shootPuck(Vector3.new(-GX + 20, 0, 0), Vector3.new(-120, 0, 1), 2)
		check("other net scores exactly once", other == 1, other)
		local graze = shootPuck(Vector3.new(GX - 20, 0, Config.Goal.Width / 2 + 0.2), Vector3.new(120, 0, 0), 2)
		check("near-post graze no goal", graze == 0, graze)
		local wide = shootPuck(Vector3.new(GX - 20, 0, Config.Goal.Width / 2 + 3), Vector3.new(120, 0, 0), 2)
		check("wide shot no goal", wide == 0, wide)
		local behind = shootPuck(Vector3.new(GX + 8, 0, 0), Vector3.new(-120, 0, 0), 0.25)
		check("shot into back of net no goal", behind == 0, behind)
		local inside = Vector3.new(GX + 2, 0.3, 0)
		check("backward crossing no goal", not Sim.crossedGoal(inside, Vector3.new(GX - 3, 0.3, 0), 1))
		-- Build 36: still touching the painted line is no goal; all the way past it is.
		local edge = GX + Config.Goal.LineWidth / 2 + Config.Puck.Radius
		check("puck on the line no goal", not Sim.crossedGoal(Vector3.new(GX - 2, 0.3, 0), Vector3.new(edge - 0.05, 0.3, 0), 1))
		check("puck fully over the line goal", Sim.crossedGoal(Vector3.new(GX - 2, 0.3, 0), Vector3.new(edge + 0.05, 0.3, 0), 1))
		local overBar = Config.Goal.CrossbarHeight + 2
		local high = Sim.crossedGoal(Vector3.new(GX, overBar, 0), Vector3.new(GX + 2, overBar, 0), 1)
		check("above crossbar no goal", not high)
		local w = emptyWorld()
		World.placePuck(w, Vector3.new(GX - 2, 0, 0), Vector3.new(60, 0, 0))
		local fired = 0
		w.goalsEnabled = true
		for _ = 1, 120 do
			World.step(w, TICK)
			fired += countEvents(w, "Goal")
		end
		check("goal latch holds while puck rattles in net", fired == 1, fired)
	end

	-- Dashing with the puck on the forehand carries it along instead of batting it away.
	do
		local w = emptyWorld()
		w.goalsEnabled = false
		local s = Sim.newSkater(1, 1)
		w.skaters[1] = s
		World.placeSkater(s, Vector3.new(-70, 0, 0))
		-- Stick out to the side with the forehand face pushing the puck along the direction of travel.
		local yaw = math.pi / 2 - Config.Stick.BladeAngle
		s.aimYaw, s.aimYawPrev = yaw, yaw
		s.input.aimX, s.input.aimZ, s.input.moveX = math.cos(yaw), math.sin(yaw), 1
		s.vel = Vector3.new(20, 0, 0)
		s.blade = Sim.bladeAt(s.pos, yaw, 1)
		s.bladePrev = s.blade
		local by = Sim.bladeYaw(yaw)
		local forehand = Vector3.new(math.sin(by), 0, -math.cos(by))
		World.placePuck(w, s.blade + forehand * (Config.Puck.Radius + 0.15), Vector3.new(20, 0, 0))
		for _ = 1, 60 do
			World.step(w, TICK)
		end
		s.input.sprint = true
		local worst, fastest = 0, 0
		for i = 1, 120 do
			if i == 3 then
				s.input.sprint = false
			end
			World.step(w, TICK)
			worst = math.max(worst, (w.puck.pos - s.blade).Magnitude)
			fastest = math.max(fastest, Vector3.new(w.puck.vel.X, 0, w.puck.vel.Z).Magnitude)
		end
		check("dash keeps the puck on the stick", worst < 2.5 and fastest <= Config.Skater.MaxSpeed + 1, string.format("gap %.2f, puck %.1f", worst, fastest))
	end

	-- A skater can skate in through the mouth of the net, but not through its back.
	do
		local w = emptyWorld()
		local s = Sim.newSkater(1, 1)
		w.skaters[1] = s
		World.placeSkater(s, Vector3.new(GX - 6, 0, 0))
		s.input.moveX, s.input.aimX = 1, -1
		for _ = 1, 90 do
			World.step(w, TICK)
		end
		local inside = s.pos.X > GX + 1 and s.pos.X <= GX + Config.Goal.Depth - Config.Skater.CollisionRadius + 0.01
		check("skater fits in the net", inside, string.format("%.2f", s.pos.X - GX))
		local b = Sim.newSkater(2, 2)
		local w2 = emptyWorld()
		w2.skaters[1] = b
		World.placeSkater(b, Vector3.new(GX + Config.Goal.Depth + 5, 0, 0))
		b.input.moveX, b.input.aimX = -1, 1
		for _ = 1, 90 do
			World.step(w2, TICK)
		end
		check("net back is solid", b.pos.X >= GX + Config.Goal.Depth + Config.Skater.CollisionRadius - 0.01, string.format("%.2f", b.pos.X - GX))
	end

	-- A lofted quick shot gets up to about a skater's height; a puck dropped on the net stays on top.
	do
		local w = emptyWorld()
		w.goalsEnabled = false
		local s = Sim.newSkater(1, 1)
		w.skaters[1] = s
		World.placeSkater(s, Vector3.new(-30, 0, 0))
		s.aimYaw, s.aimYawPrev = 0, 0
		s.blade = Sim.bladeAt(s.pos, 0, 1)
		s.bladePrev = s.blade
		World.placePuck(w, s.blade + Vector3.new(0.4, 0, 0))
		s.input.aimX = 1
		s.input.loft = true
		s.input.charge = true
		local top = 0
		for i = 1, 90 do
			if i == 3 then
				s.input.charge = false
			end
			World.step(w, TICK)
			top = math.max(top, w.puck.pos.Y)
		end
		check("lofted shot rises to, never over, skater height", top >= 4.8 and top <= Config.Puck.BodyHeight, string.format("%.2f", top))

		local w3 = emptyWorld()
		w3.puck.pos = Vector3.new(GX + 1.2, Config.Goal.CrossbarHeight + 3, 0)
		w3.puck.vel = Vector3.zero
		local goals = 0
		for _ = 1, 60 do
			World.step(w3, TICK)
			goals += countEvents(w3, "Goal")
		end
		local y = w3.puck.pos.Y
		check("puck dropped on the net stays on top", goals == 0 and y >= Config.Goal.CrossbarHeight - 0.1, string.format("%d %.2f", goals, y))
	end

	-- No shot can be lifted over the net: lofted charged shots and lofted stick sweeps, with the
	-- puck met anywhere from the ice up to the top of the blade, all top out under the crossbar.
	do
		local highest, worst = 0, ""
		for _, startY in { 0.2, 0.6, 1.0, 1.4, 1.6 } do
			-- Charged lofted shots of every length.
			for _, hold in { 2, 10, 30, 55 } do
				local w = emptyWorld()
				w.goalsEnabled = false
				local s = Sim.newSkater(1, 1)
				w.skaters[1] = s
				World.placeSkater(s, Vector3.new(-30, 0, 0))
				s.aimYaw, s.aimYawPrev = 0, 0
				s.blade = Sim.bladeAt(s.pos, 0, 1)
				s.bladePrev = s.blade
				World.placePuck(w, s.blade + Vector3.new(0.4, 0, 0))
				w.puck.pos = Vector3.new(w.puck.pos.X, startY, w.puck.pos.Z)
				s.input.aimX = 1
				s.input.loft = true
				s.input.charge = true
				for i = 1, 150 do
					if i == hold then
						s.input.charge = false
					end
					World.step(w, TICK)
					if w.puck.pos.Y > highest then
						highest, worst = w.puck.pos.Y, `charged y{startY} hold{hold}`
					end
				end
			end
			-- Lofted sweeps: the stick whipped round through the puck at full turn rate.
			for _, dirSign in { 1, -1 } do
				local w = emptyWorld()
				w.goalsEnabled = false
				local s = Sim.newSkater(1, 1)
				w.skaters[1] = s
				World.placeSkater(s, Vector3.new(-30, 0, 0))
				local yaw0 = -dirSign * 1.4
				s.aimYaw, s.aimYawPrev = yaw0, yaw0
				s.blade = Sim.bladeAt(s.pos, yaw0, 1)
				s.bladePrev = s.blade
				World.placePuck(w, Sim.bladeAt(s.pos, 0, 1))
				w.puck.pos = Vector3.new(w.puck.pos.X, startY, w.puck.pos.Z)
				s.input.loft = true
				for i = 1, 150 do
					local yaw = if i < 20 then yaw0 + dirSign * i * 0.15 else yaw0 + dirSign * 2.8
					s.input.aimX, s.input.aimZ = math.cos(yaw), math.sin(yaw)
					World.step(w, TICK)
					if w.puck.pos.Y > highest then
						highest, worst = w.puck.pos.Y, `sweep y{startY} dir{dirSign}`
					end
				end
			end
		end
		local top = highest + Config.Puck.Thickness / 2
		check("no shot rises over the crossbar", top <= Config.Goal.CrossbarHeight - 0.5, string.format("puck top %.2f (bar %.1f) %s", top, Config.Goal.CrossbarHeight, worst))
	end

	-- Shots of every height, speed and angle into the net never leave through the netting (a
	-- high shot used to fly out through the sloped top, and one at crossbar height slipped in
	-- over the roof). Leaving means going from inside, under the roof, to outside, behind the line.
	do
		local leaks, shots = 0, 0
		local example = ""
		for _, h in { 0, 3, 6, 7.5, 8.3, 8.8 } do
			for _, sp in { 40, 75, 105 } do
				for _, ang in { -0.4, 0, 0.25 } do
					for _, vy in { -5, 0, 8, 14 } do
						shots += 1
						local w = emptyWorld()
						local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
						local start = Vector3.new(GX - 1.5, 0, 0) - dir * 4
						World.placePuck(w, start)
						w.puck.pos = Vector3.new(start.X, Config.Puck.Thickness / 2 + h, start.Z)
						w.puck.vel = dir * sp + Vector3.new(0, vy, 0)
						for _ = 1, 120 do
							local p0 = w.puck.pos
							World.step(w, TICK)
							World.drainEvents(w)
							local p = w.puck.pos
							local d0, d1 = p0.X - GX, p.X - GX
							local half = Config.Puck.Thickness / 2
							local in0 = Sim.insideNet(d0, p0.Z) and p0.Y - half < Sim.netRoofAt(d0) - 0.1
							local in1 = Sim.insideNet(d1, p.Z) and p.Y - half < Sim.netRoofAt(d1) + 0.05
							if in0 and not in1 and d1 > 0.3 then
								leaks += 1
								example = string.format(" (h %.1f, speed %d, angle %.2f, up %d)", h, sp, ang, vy)
								break
							end
						end
					end
				end
			end
		end
		check("shots never leave through the netting", leaks == 0, string.format("%d of %d%s", leaks, shots, example))
	end

	-- Puck never leaves the rink or the ice, from many fast random shots.
	do
		local rng = Random.new(42)
		local escaped = 0
		local underIce = 0
		local hx, hz = Config.Arena.Length / 2, Config.Arena.Width / 2
		for _ = 1, 400 do
			local w = emptyWorld()
			w.goalsEnabled = false
			local dir = rng:NextNumber() * 2 * math.pi
			World.placePuck(
				w,
				Vector3.new(rng:NextNumber(-60, 60), 0, rng:NextNumber(-30, 30)),
				Vector3.new(math.cos(dir), 0, math.sin(dir)) * Config.Puck.MaxSpeed
			)
			for _ = 1, 180 do
				World.step(w, TICK)
				local p = w.puck.pos
				if math.abs(p.X) > hx or math.abs(p.Z) > hz then
					escaped += 1
				end
				if p.Y < 0 then
					underIce += 1
				end
			end
			table.clear(w.events)
		end
		check("puck stays in rink at max speed", escaped == 0, escaped)
		check("puck stays above ice", underIce == 0, underIce)
	end

	-- A swing applies at most one impulse, and misses when the puck is out of reach.
	do
		local w = emptyWorld()
		local s = Sim.newSkater(1, 1)
		w.skaters[1] = s
		World.placeSkater(s, Vector3.new(-30, 0, 0))
		-- Stick already extended and steady, puck resting just off the blade face.
		s.aimYaw, s.aimRadius = 0, 1
		s.blade = Sim.bladeAt(s.pos, 0, 1)
		s.bladePrev = s.blade
		-- Just off the backhand face, by the heel.
		local by = Sim.bladeYaw(0)
		local face = Vector3.new(-math.sin(by), 0, math.cos(by))
		local heel = s.blade - Vector3.new(math.cos(by), 0, math.sin(by)) * (Config.Stick.BladeLength / 2 - 0.4)
		World.placePuck(w, heel + face * (Config.Puck.Radius + Config.Stick.BladeThickness + 0.05))
		s.input.aimX = 1
		s.input.charge = true
		local shots = 0
		for i = 1, 90 do
			if i == 45 then
				s.input.charge = false
			end
			World.step(w, TICK)
			shots += countEvents(w, "Shot")
		end
		check("swing token fires once", shots == 1, shots)
		check("charged shot moves puck", w.puck.pos.X > s.pos.X + 15, w.puck.pos.X)

		local far = emptyWorld()
		local t = Sim.newSkater(1, 1)
		far.skaters[1] = t
		World.placeSkater(t, Vector3.new(-30, 0, 0))
		World.placePuck(far, Vector3.new(20, 0, 20))
		t.input.aimX = 1
		t.input.charge = true
		local missed = 0
		for i = 1, 60 do
			if i == 20 then
				t.input.charge = false
			end
			World.step(far, TICK)
			missed += countEvents(far, "Shot")
		end
		check("click out of reach moves nothing", missed == 0 and far.puck.vel.Magnitude < 1, missed)
	end

	-- Protocol: forged or malformed packets never decode and never throw.
	do
		local good = Protocol.encodeInput(5, { { seq = 9, moveX = 0.6, moveZ = -0.6, aimX = 0.5, aimZ = 0.5, charge = true, sprint = false } }, 1, 1)
		local phaseId, frames = Protocol.decodeInput(good, 4)
		check("valid packet decodes", phaseId == 5 and frames ~= nil and frames[1].seq == 9 and frames[1].charge)

		local bad = 0
		local garbage: { any } = { nil, 1, "x", {}, Vector3.zero, buffer.create(0), buffer.create(3), buffer.create(500) }
		for i = 1, 8 do
			local ok, id = pcall(Protocol.decodeInput, garbage[i], 4)
			if not ok or id ~= nil then
				bad += 1
			end
		end
		check("garbage rejected without error", bad == 0, bad)

		local fast = buffer.create(15)
		buffer.writeu8(fast, 0, Protocol.VERSION)
		buffer.writeu8(fast, 3, 1)
		buffer.writei8(fast, 8, 127)
		buffer.writei8(fast, 9, 127)
		check("over-length move rejected", Protocol.decodeInput(fast, 4) == nil)

		local rng = Random.new(7)
		local thrown = 0
		for _ = 1, 2000 do
			local size = rng:NextInteger(0, 80)
			local b = buffer.create(size)
			for j = 0, size - 1 do
				buffer.writeu8(b, j, rng:NextInteger(0, 255))
			end
			if not pcall(Protocol.decodeInput, b, 4) then
				thrown += 1
			end
		end
		check("fuzz never throws", thrown == 0, thrown)

		local snap = buffer.create(Protocol.SNAPSHOT_BYTES)
		Protocol.writeSnapshotHeader(snap, 77, 1234.5, 10.5, 0.3, -20.25, 100, -50)
		Protocol.writeSnapshotSkater(snap, 6, 40, -12, 31, -31, 3, 0.5, 5, 0.25, 1, 4242)
		local read = Protocol.newSnapshot()
		local ok = Protocol.readSnapshot(snap, read)
		local s6 = read.skaters[6]
		check(
			"snapshot round trip",
			ok and read.tick == 77 and read.puckX == 10.5 and s6.x == 40 and s6.ack == 4242 and s6.charging and s6.sprinting,
			Protocol.SNAPSHOT_BYTES
		)
		check("snapshot under unreliable limit", Protocol.SNAPSHOT_BYTES < 900, Protocol.SNAPSHOT_BYTES)
	end

	-- Full bot match: no errors, goals happen, nobody leaves the rink.
	do
		local w = emptyWorld()
		local brains = {}
		for slot = 1, 6 do
			local s = Sim.newSkater(slot, if slot <= 3 then 1 else 2)
			s.goalie = slot == 3 or slot == 6
			w.skaters[slot] = s
			brains[slot] = BotBrain.newState()
		end
		World.resetForFaceoff(w)
		local goals, shots, resets, outside = 0, 0, 0, 0
		local topSpeed = 0
		local pinTicks, longestPin = 0, 0
		local started = os.clock()
		local waited = 0 -- time spent yielding (so a Play-start run never hits the script timeout)
		local MINUTES = 10
		for tick = 1, 60 * 60 * MINUTES do
			if tick % 900 == 0 then
				local before = os.clock()
				task.wait()
				waited += os.clock() - before
			end
			for slot, s in w.skaters do
				BotBrain.think(w, s, if s.goalie then "Goalie" else "Field", brains[slot], TICK)
			end
			World.step(w, TICK)
			topSpeed = math.max(topSpeed, w.puck.vel.Magnitude)
			-- A slow puck right on the boards counts as pinned.
			if Sim.boardGap(w.puck.pos.X, w.puck.pos.Z) < 3 and w.puck.vel.Magnitude < 8 then
				pinTicks += 1
				longestPin = math.max(longestPin, pinTicks)
			else
				pinTicks = 0
			end
			for _, e in World.drainEvents(w) do
				if e.kind == "Goal" then
					goals += 1
					World.resetForFaceoff(w)
				elseif e.kind == "Shot" then
					shots += 1
				elseif e.kind == "Stuck" then
					resets += 1
					World.resetForFaceoff(w)
				end
			end
			for _, s in w.skaters do
				if math.abs(s.pos.X) > Config.Arena.Length / 2 or math.abs(s.pos.Z) > Config.Arena.Width / 2 then
					outside += 1
				end
			end
		end
		local msPerTick = (os.clock() - started - waited) / (60 * 60 * MINUTES) * 1000
		-- Bots only shoot with a clear lane and keep their sticks on the ice (no lifting the blade
		-- across the puck), so the count is lower than a spray-at-the-net bot would give, but
		-- every shot is a real chance.
		check(`bots shoot in {MINUTES} simulated minutes`, shots >= 5, `{shots} shots`)
		check("bots score a believable amount", goals >= 1 and goals <= 60, `{goals} goals, {resets} idle resets`)
		check("bots never pin the puck on the boards", longestPin < 60 * 10, `longest {math.round(longestPin / 6) / 10}s`)
		check("bots stay in rink", outside == 0, outside)
		check("server tick cost under 2ms", msPerTick < 2, `{math.round(msPerTick * 1000) / 1000}ms, top puck speed {math.round(topSpeed)}`)
	end

	return out
end

return SimTests
