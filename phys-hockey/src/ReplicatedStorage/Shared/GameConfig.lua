--!strict
-- Every tuning number lives here. Values are starting hypotheses from Appendix A of the
-- manual, changed only where noted. Coordinates: rink centred on the origin, ice top at Y=0,
-- length along X, width along Z. Team 1 defends -X and attacks +X.

local Config = table.freeze({
	Version = "1.0.0",
	-- Bumped on every change pushed to Studio; the menu shows it so the live game can be checked
	-- against Studio (Ctrl+S only saves; File > Publish to Roblox puts it live). Build 37: no longer
	-- on screen; the server and client print it to the F9 console at start.
	Build = 41,
	GameName = "PHYSHOCKEY", -- the brand (Build 28; was PUCK PALS). One word.
	Tick = 1 / 60,
	SnapshotRate = 60, -- one snapshot per tick: the freshest state for prediction and drawing
	InputSendRate = 60,
	InterpDelay = 0.045,

	Arena = table.freeze({
		Length = 228, -- room to skate, with a lane behind each net
		Width = 110,
		CornerRadius = 26,
		BoardHeight = 4.5,
		BlueLineX = 34,
	}),

	-- Goal line sits 26 studs in from the end boards, leaving 19 studs to skate behind the net.
	Goal = table.freeze({
		X = 88,
		Width = 15,
		Depth = 7,
		CrossbarHeight = 8.4, -- tall enough for a skater to stand in the net with room above (Build 33: 8.4, was 9)
		PostRadius = 0.4,
		LineWidth = 0.4, -- Build 36: the painted goal line; a goal needs the whole puck past its far edge
		-- An NHL-style net: open mouth, a short flat top shelf behind the crossbar, then the
		-- netting drops at a steep angle to the base, which runs further back than the top.
		CornerRadius = 3.4, -- the base's rounded back corners (seen from above). Build 33: 3.4 (was 3.2); at most Depth - ShelfDepth
		MouthCornerRadius = 0.8, -- Build 33: where each post bends into the crossbar (drawn only)
		ShelfDepth = 3.6, -- how far back the flat top shelf runs at crossbar height (the top back bar; about half the base depth, like an NHL net)
		BackHeight = 0.5, -- the netting meets the base here at the back (about 68 degrees down from the shelf)
		-- The drink bottle on top of each net: where it stands (behind the goal line), and how high
		-- inside the net a shot must go to pop it ("top shelf": shots top out near BodyHeight).
		BottleDepth = 1.8, -- lying on its side across the middle of the top shelf
		BottleReach = 2.6, -- how far across the net from the middle a high shot still pops it
		BottleTopShelf = 3.2, -- puck height inside the net that knocks the bottle off
	}),

	Skater = table.freeze({
		MaxSpeed = 31,
		-- A firm first push that eases off toward top speed: about 0.85 s from standing to top speed
		-- (was 52, about 0.6 s, which felt twitchy).
		Acceleration = 31, -- a little gentler push (was 38); quick direction changes come from the carve, not raw push
		-- Skates glide: let go at top speed in the middle of the rink and you stop about halfway to
		-- the side boards (about 26 studs, 1.7 s).
		CoastDrag = 26, -- less slick: let go at top speed and you stop in about 1.2 s (was 18.5, 1.7 s)
		BrakeAcceleration = 80,
		BrakeMoveSpeed = 6, -- holding stop, the keys still creep the skater along this slowly
		-- Carving: moving skaters turn their momentum round in smooth arcs.
		CarveMinSpeed = 6, -- below this (studs/s) a skater just pushes off where it wants to go
		CarveTurnRate = 6, -- radians a second when slow (Build 29: was 8, and tapping WASD round spun you in tight fast circles; 4.2 before that was too slow)
		CarveTurnRateTop = 3.8, -- radians a second at top speed (Build 29: was 5; 3 before that)
		CarveBleed = 0.38, -- share of speed lost per radian turned (was 0.08): tight circles slow you down instead of flinging you
		-- Turns build up and settle instead of snapping: the turn rate rises at CarveSpinAccel and
		-- eases out over the last CarveSettle seconds of the turn (W then W+D drifts into the diagonal).
		CarveSpinAccel = 13, -- radians a second, per second (Build 29: was 22, too snappy; 6 before that was laggy)
		CarveSettle = 0.18,
		-- Turning right round (holding the opposite way): the skates dig in and push back the other
		-- way this hard, gentler than a full stop so a direction change never snaps.
		ReverseAcceleration = 125, -- Build 29: 200 stopped you dead in place; 80 slid 10.4 studs. This slides a little (about 7.5 studs)
		-- Keys pointing back past square across: the carve's turn rate fades from full (along the
		-- travel -0.2) to nothing (-CarveStopAlong, about 162 degrees: a straight stop), and the
		-- push hands over to digging in across CarveDigBlend.
		CarveStopAlong = 0.95,
		CarveDigBlend = 0.3,
		-- The push and the dig-in change over at most this fast (studs a second, per second), so the
		-- skater never lurches from slowing to speeding up as the keys swing round.
		CarveJerk = 350,
		CarveDigJerk = 800, -- digging in to stop ramps up faster than the push (Build 29: was 1500, which bit too hard)
		-- How fast the push follows the keys (per second): about a sixth of a second to swing round
		-- (was 8), so tapping keys reads as smooth rather than jerky.
		WishResponse = 10, -- per second (Build 29: was 14, which let quick WASD taps whip the skater round; 6.5 felt delayed)
		CollisionRadius = 1.95, -- matches the smaller body
		-- The puck meets the body at the drawn hem (1.68 at play scale), not the wider skater-on-skater
		-- radius, so a carried puck nestles right in the pocket between the body and the blade.
		PuckBodyRadius = 1.72,
		BoardRadius = 2.35, -- skaters stay this far off the boards, so the helmet and gloves never poke through
		OverspeedDecay = 40,
		BoardRestitution = 0, -- skaters die on the boards: no bounce back off them (was 0.25)
		StickWallRestitution = 0, -- the rigid stick meeting the boards rests on them (no bounce, no jitter)
		PlayerRestitution = 0.03, -- body on body: barely any bounce (was 0.1), so a bump never sends anyone far
		SprintMaxSpeed = 37,
		SprintAccelScale = 1.25,
		-- Shift is a burst, not a hold: tap for a quick push of speed that fades back to normal.
		DashImpulse = 16,
		DashMaxSpeed = 47,
		DashTime = 0.8, -- the whole burst: a quick push, a short hold, then a smooth fade to top speed
		DashPush = 0.3, -- the push and hold; the rest of DashTime is the fade
		DashGain = 30, -- how fast the push closes on the dash speed (per second)
		DashOnset = 0.035, -- the push builds over about two ticks instead of jumping in one
		DashCooldown = 0.7,
		DashCost = 0.4, -- 40% of the bar: two dashes back to back, not three (was 0.3)
		StaminaDrain = 0.4,
		StaminaRegen = 0.28,
		StaminaRegenDelay = 0.8,
		CheckSpeed = 24, -- closing speed for a body check that knocks the other skater off balance
		StunTime = 0.45,
		StunMoveScale = 0.3,
	}),

	Stick = table.freeze({
		Reach = 3.3, -- blade centre from the skater: the heel tucks in 1.9 studs out, just off the drawn body (1.68)
		MouseTurnPerPixel = 0.0068, -- horizontal mouse movement spins the stick around the body
		MouseSwingSpeed = 40, -- the stick follows the hand one to one, up to this many radians a second
		MinRadius = 0.5,
		MaxAimRadiansPerSecond = 40, -- the stick turns as far as the mouse did, the same tick
		-- Spin meter: turning the stick faster than SpinFreeRate drains it. Empty, the skater is
		-- spun out: the stick turns sluggishly for SpinLockSeconds, then the meter refills.
		SpinFreeRate = 7, -- radians a second of stick turn that cost nothing (normal handling)
		SpinDrainPerRadian = 0.054, -- about 3 full turns of hard spinning empty a full meter (was 0.018, about 9)
		SpinRegenDelay = 0.25, -- calm seconds before the meter starts to refill
		SpinRegenPerSecond = 0.6,
		SpinLockSeconds = 3, -- spun out for exactly this long; the bar refills through it
		SpinLockedAimRate = 3, -- radians a second while spun out
		RadialPerSecond = 6,
		BladeLength = 2.8, -- heel to toe
		BladeDrawnHeight = 1.6, -- how tall the blade is drawn: a tall, flat, rectangular blade
		-- The blade is angled off the stick's line, toe toward the backhand side, so the backhand
		-- face looks back at the body: a puck pulled in on the backhand nestles in the pocket
		-- between the body and the blade.
		BladeAngle = 0.8, -- radians (was 0.75: a slightly deeper backhand pocket)
		BladeThickness = 0.16, -- half the blade's thickness, as drawn (a flat-sided blade)
		-- How far the toe bends sideways (the toe half is angled about 5.7 degrees). Negative bends it
		-- toward the forehand, so the forehand face is the hollow side, like a real curved blade.
		BladeCurve = -0.14,
		MaxBladeSpeed = 100, -- a hard flick from the red line carries to the net
		ContactCooldown = 0.08,
		ContactCueSpeed = 10,
		-- The blade only ever pushes the puck: no pull, no grip along the face, so the puck never
		-- clings to the stick. It leaves the blade the moment the blade stops pushing it.
		-- Dull like the boards: a puck meeting the blade keeps little of its own speed.
		-- Very dead: a puck into a blade that isn't swinging at it barely comes off.
		SoftRestitution = 0, -- a puck into a still blade dies on it
		HardRestitution = 0.03,
		-- Catching: a puck coming into a blade that is not swinging at it is cushioned. It keeps
		-- none of its speed into the face, the blade gives (passes on only CatchTransfer of its own
		-- push) and CatchFriction of its slide along the face is taken off, so a pass settles on the
		-- stick instead of bouncing away.
		CatchMinSpeed = 3, -- the puck must come in at least this fast (studs/s) to count as a catch (was 6: more touches are cushioned)
		CatchMaxSwing = 14, -- a blade swinging at the puck faster than this is a hit, not a catch
		CatchTransfer = 0.1,
		CatchFriction = 0.85,
		-- The backhand is the blade's convex side, so a carried puck slid off it. Short of a real
		-- swing (CatchMaxSwing), this share of the puck's slide along the backhand face (relative
		-- to the blade) is taken off each touch.
		BackhandGrip = 0.6,
		-- Soft hands: a slow stick movement passes on only this share of its own push, rising to
		-- all of it by HandTransferFullSpeed (studs/s), so stickhandling nudges the puck and a real
		-- swing still fires it.
		HandTransferSlow = 0.3, -- was 0.6: a light touch no longer pops the puck off the stick
		HandTransferFullSpeed = 50, -- was 28: only a real swing passes on its full push
		ShotForgiveness = 1, -- a swing only counts with the blade this close to touching the puck
		QuickThreshold = 0.16,
		ChargeTime = 0.85,
		-- A released swing comes down onto the puck for ShotDelay before it fires, so the puck
		-- leaves the blade as the drawn stick meets the ice, not while it is still raised from the
		-- wind-up. The shot window after that stays ActiveTime - ShotDelay.
		ShotDelay = 0.05,
		ActiveTime = 0.14,
		RecoveryTime = 0.16,
		QuickShotSpeed = 62,
		MinChargedSpeed = 72,
		MaxChargedSpeed = 140,
		MaxLiftSpeed = 15,
		MaxLoftSpeed = 34, -- puck lift: up to this speed (a flick from the red line reaches the net about halfway up)
		LoftShare = 0.5, -- charged swings: share of the swing speed that becomes upward speed when lofting
		-- Stick hits while lofting: upward speed is this share of how fast the puck leaves the
		-- skater, so a flick lifts it and a carried puck (moving with you) stays down.
		LoftRatio = 0.95, -- Build 33: 0.95 (was 0.85), a little more lift on a flick
		BackhandLoftRatio = 1.3, -- backhand flicks are slower (near the heel), so they get more lift
		LoftMinSpeed = 8, -- the puck must leave the skater at least this fast to lift
		LoftMinUp = 14, -- any lifting hit gets at least this much upward speed
		LoftCarry = 1.4, -- a lofted flick leaves this much faster along the ice: distance, not height
		ShotCeilingGap = 0.8, -- no shot rises higher than this under the crossbar (the puck's top)
		-- Letting go of stick lift with the blade over the puck keeps it up until the blade has
		-- moved off the puck (this much clear of touching it), so it never drops onto the puck.
		LiftClear = 0.05,
		LiftHeight = 1.8, -- how far stick lift raises the blade: high enough to read as clear of the puck
		CarrySpeedShare = 0.3,
		-- Stick on body: a stick swung or skated into any other skater (opponent or teammate)
		-- nudges them out of the way, and only a really hard hit knocks them off balance.
		StickBodyRadius = 0.35,
		StickBodyRestitution = 0.04,
		StickKnockShare = 0.6, -- share of the shove taken by the skater who was hit
		StickBumpMaxSpeed = 4, -- most speed one stick bump can give a skater (was 6.5)
		StickPushMaxStep = 0.3, -- most a stick resting on a body slides it in one tick (studs)
		StickKnockSpeed = 26, -- stick speed into a body that stuns them
		-- Turning the stick into the boards levers the skater off them instead of stopping it.
		StickLeverShare = 0.15, -- share of the lever speed the skater keeps as push-off speed
		StickLeverMaxSpeed = 5, -- a gentle push off: the stick can lean on the wall without a jolt
		StickLeverMaxStep = 1.2, -- most the lever moves the skater in one tick (studs)
		-- Working a puck on the boards: a blade on the ice side of a puck tight to the wall cradles
		-- it, carrying it along at the blade's own speed and drawing it off the wall as the blade
		-- moves away, so it can be flicked straight off the boards.
		ScoopReach = 0.06, -- only a blade actually touching the puck cradles it (was 0.2, which pushed pucks the blade wasn't on)
		-- The pocket (the backhand, between blade and body): a puck tucked in there stays with the
		-- skater through skating and turns. It counts within PocketReach of the backhand face and
		-- PocketDepth of the body; slip under PocketMaxSlip (studs/s, relative to the skater) is
		-- soaked up at PocketGrip per second and it is drawn in at up to PocketPull.
		PocketReach = 0.35,
		PocketDepth = 1.4,
		PocketMaxSlip = 14,
		PocketGrip = 10,
		PocketPull = 3,
		-- Build 30: the blade is angled, so a puck held out on the toe slides down the face toward
		-- the heel (on the backhand, on into the pocket) instead of riding on the tip. Past
		-- HeelSlideSweet of the blade's length from the heel, it slides heelward at HeelSlideRate
		-- per stud past it (at most HeelSlideMax studs/s, relative to the blade), reaching that pace
		-- at HeelSlideGrip per second. A puck balanced beyond the very tip slips off onto the face
		-- it leans toward at TipSlip studs/s.
		HeelSlideSweet = 0.42,
		HeelSlideRate = 5,
		HeelSlideMax = 5,
		HeelSlideGrip = 9,
		HeelSlideReach = 0.12,
		TipSlip = 3,
		ScoopBoardGap = 0.6,
		StickHalfWidth = 0.2, -- the stick's half-width against posts and netting
		-- Stick on stick: blades and the low end of the shafts can't pass through each other. Two
		-- sticks closer than this (centre line to centre line) push both skaters apart, half each.
		StickStickGap = 0.36,
		StickLowShaft = 0.55, -- the shaft counts from this share of the way out to the heel (higher up it is at the hands)
	}),

	Puck = table.freeze({
		Radius = 0.7,
		Thickness = 0.4,
		MaxSpeed = 112,
		Substeps = 4,
		-- A firm pass still crosses most of the rink, but a loose puck settles instead of gliding on.
		-- A touch grippier than before (6 and 0.25), so a carried puck that a turning stick speeds
		-- up doesn't run away from the skater.
		IceDeceleration = 7,
		IceDragPerSecond = 0.29,
		Gravity = 70,
		BounceRestitution = 0, -- pucks never bounce off the ice
		BoardRestitution = 0.3, -- the boards give: a hard rim comes back into play without rocketing off
		BoardHugSpeed = 10, -- a puck meeting the boards slower than this (studs/s into them) hugs them instead of bouncing
		PostRestitution = 0.3, -- a dull ping off the iron (was 0.4)
		NetRestitution = 0.08,
		-- Bodies are dead: a puck hitting a skater square on stops against them (BodyRestitution,
		-- and BodyGrip of its slide across the body taken off), and one clipping a skater's side
		-- glances off with a little bounce (BodySideRestitution). Between the two it blends by how
		-- square the hit is.
		BodyRestitution = 0, -- a puck into a body dies against it
		BodySideRestitution = 0.05, -- was 0.22: even a glancing hit barely comes off
		BodyGrip = 0.85,
		BodyHeight = 6, -- Build 33: 6 (was 5.5). Shots top out just under this, so lifted shots go a little higher
		BodyCueSpeed = 14, -- a puck meeting a body at least this fast makes a thud
		LandCueSpeed = 9, -- Build 29: a puck landing this fast (a drop of about 0.6 studs) smacks the ice
		DropHeight = 8, -- face-offs: the puck hangs this high over the dot, then falls
		BoardCueSpeed = 12,
		IdleResetSeconds = 25,
	}),

	-- Idle players in a match (online or with bots) go back to the lobby so a bot takes their
	-- place: the server counts only live play, warns at WarnSeconds and sends them off at
	-- KickSeconds. Any change in their stick or skate input resets the count.
	Idle = table.freeze({
		WarnSeconds = 20,
		KickSeconds = 30,
	}),

	-- The first-time tutorial: finishing every drill unlocks RewardItem (worn straight away) and
	-- RewardCoins, enough with the starting coins for a first hat. MinSeconds is the quickest a
	-- real run can take; a finish reported sooner than that is ignored.
	Tutorial = table.freeze({
		RewardItem = "foamfinger",
		RewardCoins = 350,
		MinSeconds = 15,
	}),

	-- Build 34: the Mystery Box (Shared/MysteryBox), a developer product. ProductId 0 = not on
	-- sale yet (the shop shows it as coming soon): create the product on the Creator Dashboard
	-- (Monetization > Developer Products) and put its id here. Its price comes from Roblox
	-- (GetProductInfo), never from this file. CompensationCoins: paid instead if a box is somehow
	-- bought with nothing left to win (the prompt is refused then, so it should never happen).
	Box = table.freeze({
		ProductId = 0,
		CompensationCoins = 2000,
	}),

	-- Build 35: coin packs (developer products), the shop's COINS section. ProductId 0 = not
	-- created yet (the card shows SOON). `robux` is only the price shown before Roblox answers;
	-- the real price is read with GetProductInfo, and the product's own price on the Creator
	-- Dashboard is what is charged. Keys are saved in receipts: never rename one.
	CoinPacks = table.freeze({
		-- Build 37: every pack pays twice the coins (keys unchanged: they are saved in receipts).
		table.freeze({ key = "c2000", coins = 4000, robux = 99, productId = 0 }),
		table.freeze({ key = "c5000", coins = 10000, robux = 199, productId = 0 }),
		table.freeze({ key = "c10000", coins = 20000, robux = 399, productId = 0 }),
		table.freeze({ key = "c15000", coins = 30000, robux = 499, productId = 0 }),
		table.freeze({ key = "c50000", coins = 100000, robux = 999, productId = 0 }),
	}),

	-- Build 36: every shop item also shows a Robux price, worked out from its coin price at this
	-- rate (Build 37: 40 coins per Robux, was 20; the smallest coin pack's rate, so buying coins is
	-- never worse) and
	-- rounded up to a whole Robux. Buying with Robux isn't live yet: RobuxBuying stays false (the
	-- button shows SOON) until the per-price developer products exist.
	CoinsPerRobux = 40,
	RobuxBuying = false,

	-- Build 36: accounts that own every item (for testing looks in game). Saved like a normal
	-- unlock, so they keep them. The game owner only.
	Admins = table.freeze({ 271168968 }),

	Match = table.freeze({
		TeamSize = 3,
		LengthSeconds = 300,
		CountdownSeconds = 3,
		FaceoffSeconds = 3, -- the 3-2-1 count with the puck hanging over the dot
		-- After a goal: 3.2 s of celebration (Build 39: was 2.2) (lights down, spotlight on the scorer), then the TV
		-- replay (wipe in, about 4 s of slow motion, wipe out; any key skips it), then the face-off.
		GoalFreeze = 9, -- Build 39: 9 (was 8), the extra second of celebration
		-- The final horn: the clock hits zero, the horn sounds and everyone can still skate about for
		-- this long (no goals count), then the post-game screen.
		BuzzerSeconds = 3,
		-- The post-game screen stays up until everyone on the ice picks PLAY AGAIN (going back to
		-- the menu takes you off the ice). With nobody on the ice it lasts FinalSeconds, and never
		-- longer than FinalMaxSeconds.
		FinalSeconds = 9,
		FinalMaxSeconds = 90,
		CleanupSeconds = 1,
	}),

	Teams = table.freeze({
		[1] = table.freeze({ Name = "Away", Abbrev = "AWAY" }),
		[2] = table.freeze({ Name = "Home", Abbrev = "HOME" }),
	}),

	Security = table.freeze({
		PacketsPerSecond = 90, -- clients send one packet a tick (60 a second)
		PacketBurst = 120,
		-- Input waits in a short queue: long enough to ride out jitter, short enough that what
		-- you press reaches the ice within a few ticks.
		MaxQueuedFrames = 5,
		TrimQueueTo = 2,
		MaxRepeatedTicks = 12,
		MaxFramesPerPacket = 4,
		ActionsPerSecond = 2,
		ActionBurst = 5,
	}),

	Bots = table.freeze({
		ThinkInterval = 1 / 15,
		AimErrorRadians = 0.09,
		MinChargeSeconds = 0.32, -- Build 32: was 0.25 (a longer, more visible wind-up)
		MaxChargeSeconds = 0.75,
		-- Build 30: a quick shot, pass or poke winds up this long (was 0.05), so the stick is seen
		-- to swing back and sweep through instead of chopping at the puck. Still under
		-- Stick.QuickThreshold, so it leaves at quick-shot speed. Build 32: 0.14 (was 0.11).
		QuickWindSeconds = 0.14,
		-- Build 32: a shot is a quick release only this close to the net or with an opponent
		-- within CrowdRadius of the puck; otherwise the bot winds up.
		TapShotRange = 14,
		CrowdRadius = 5,
		-- Seconds after a face-off drop that the wingers keep their lanes (unless the puck comes
		-- within 6 studs), so nobody charges in on their own centre.
		FaceoffGrace = 1.6, -- Build 34: 1.0 (Build 33 had 0.6 and the wingers piled in at once). Build 36: 1.6
		-- Build 34: the bot centre needs a moment to react to the drop, like a person does, and for
		-- a while after it nobody sprints: a sprint press is a dash, and every bot was dashing into
		-- the middle before the player could reach the puck.
		-- Build 36: 0.4 (was 0.2; a bot still beat the player to the puck), and for FaceoffEase
		-- seconds after the drop it skates at FaceoffEaseSpeed of its full stick input.
		FaceoffReaction = 0.4,
		FaceoffEase = 1.0,
		FaceoffEaseSpeed = 0.6,
		FaceoffCalm = 1.5,
		-- Build 39: for this long after the drop a bot centre plays the draw: straight round to
		-- the far side of the puck and a quick pass back to a winger (BotBrain thinkDraw). The
		-- reaction and ease above now apply only against a player's centre.
		FaceoffDrawWindow = 2.0,
		-- Build 39: the goalie seat dashes back to its net while further out than this (past anywhere
		-- it goes to meet a shooter: GoalieChargeOut, and a skater chase starts at GoalieChaseFromNet).
		GoalieDashFrom = 28,
		-- Build 34: the goalie seat lines up for the face-off (back left) and, after the drop,
		-- chooses: back in net, out after a loose puck near it while far from its net, or up to
		-- the red line as an extra man while its team holds the puck deep in the other end.
		GoalieRoamLine = 30, -- the team's carrier this far into the attacking end lets it step up
		GoalieRoamX = 4, -- where it waits then (just past the red line, toward its own end)
		GoalieChaseFromNet = 25, -- it only chases a loose puck itself when at least this far out
		-- Build 36: a bot working a puck on the boards this long clears it (to a teammate behind,
		-- or rimmed hard up the boards with a WallClearWind wind-up).
		-- Build 36: a teammate with the puck: helpers keep MateRoom studs off them, and a puck a
		-- little off their blade is still theirs for MateCarryGrace seconds.
		MateRoom = 9,
		MateCarryGrace = 0.7,
		WallClearSeconds = 1.5,
		WallClearWind = 0.3,
		ShootRange = 62,
		PassChance = 0.25,
		GoalieArc = 6,
		-- Build 32: a carrier this close to the net with no defender within GoalieLaneWidth of
		-- their line to it is a one-on-one: the goalie comes out (up to GoalieChargeOut from the
		-- net) and pokes at the puck.
		-- Build 35: it reads the breakaway from further out (it used to wait until the shooter was
		-- almost on top of it, so it never seemed to come out), steps out to cut the angle, and
		-- only goes all the way to the puck once the shooter is close.
		GoalieChargeRange = 40,
		EasyGoalieChargeRange = 34,
		GoalieChargeOut = 12,
		GoalieLaneWidth = 6,
		GoalieComeOut = 0.45, -- steps out this share of the shooter's distance (GoalieArc..ChargeOut)
		GoalieBreakawayGap = 6, -- a skater this close behind a loose puck is still carrying it (a dash push)
		-- Build 40: every bot goalie reads a shot quicker and, on this share of shots aimed well off
		-- its body, dashes across for it (only practice goalies did before). Measured on 200 random
		-- slot shots: match goalies save 51% (was 42%), lone-player goalies 52% (was 48%), practice
		-- goalies 56% (was 54%). Corners still beat them.
		-- Build 41: a little better again. Measured on 300 random slot shots (same shots each run):
		-- match goalies save 59% (Build 40 values: 54%), lone-player goalies 53% (50%); practice
		-- goalies 58% on 120 shots (56%).
		GoalieReaction = 0.07, -- Build 40: 0.1 (was 0.22, BotBrain's GOALIE_REACTION)
		GoalieDiveChance = 0.82, -- Build 40: 0.7
		-- Playing alone against bots: their goalie reads shots later and shuffles across slower.
		EasyGoalieReaction = 0.18, -- Build 40: 0.24 (was 0.42)
		EasyGoalieDiveChance = 0.62, -- Build 40: 0.5
		EasyGoalieSlowRadius = 9,
		-- Build 36: free-practice goalies (one in each net) read a shot this fast and dash across
		-- on this share of shots aimed away from them. Still beatable in the corners.
		PracticeGoalieReaction = 0.06, -- Build 40: 0.08 (was 0.16)
		PracticeGoalieDiveChance = 0.88, -- Build 40: 0.8 (was 0.6)
		-- Passive defence: against a skater who has the puck, the nearest bot holds a gap between
		-- them and its net (never past centre ice) instead of rushing them, so there is room to
		-- deke or pass. It steps up only when the carrier gets close to its net, skates right at
		-- it, or has been left alone in its half for a while.
		ContainGapMin = 8,
		ContainGapMax = 15,
		PressureRange = 34, -- carrier this close to the bot's own net: go and take it
		PokeRange = 6.5, -- carrier this close to the bot: poke at it
		PatienceSeconds = 4, -- left alone in the bot's half this long: one push of pressure
		PressureBurst = 1.6,
		Names = table.freeze({
			"Moose", "Pip", "Biscuit", "Dex", "Waffles", "Tank",
			"Nugget", "Sully", "Bean", "Rocket", "Maple", "Gus",
		}),
	}),
})

return Config
