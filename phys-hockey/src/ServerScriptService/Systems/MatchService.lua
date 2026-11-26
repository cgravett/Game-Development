--!strict
-- The match state machine. Timers are plain numbers read on the server tick, so two
-- countdowns can never run at once. Every change goes through transition(), which validates
-- the old state, bumps the phase token and publishes one snapshot of match state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.GameConfig)
local Sim = require(ReplicatedStorage.Shared.Sim)

local MatchService = {}

local MATCH = Config.Match
local World = Sim.World

local ALLOWED: { [string]: { [string]: boolean } } = {
	Waiting = { Countdown = true },
	Countdown = { Countdown = true, Faceoff = true, Waiting = true },
	Faceoff = { Live = true, Overtime = true, Waiting = true, Countdown = true },
	Live = { GoalFrozen = true, Faceoff = true, Overtime = true, Final = true, Buzzer = true, Waiting = true, Countdown = true },
	Buzzer = { Final = true, Waiting = true, Countdown = true },
	Overtime = { GoalFrozen = true, Faceoff = true, Waiting = true, Countdown = true },
	GoalFrozen = { Faceoff = true, Final = true, Waiting = true, Countdown = true },
	Final = { Cleanup = true, Waiting = true },
	Cleanup = { Waiting = true, Countdown = true },
}

local state = {
	phase = "Waiting",
	phaseId = 1,
	revision = 0,
	phaseEndsAt = 0,
	clock = MATCH.LengthSeconds,
	scores = { 0, 0 },
	lastGoalId = 0,
	inOvertime = false,
	matchId = 0,
	winner = 0,
}

local world: Sim.World
local publish: () -> ()
local hooks: {
	humanCount: () -> number,
	onMatchReset: () -> (),
	onFinal: ((winner: number) -> ())?,
	readyForNext: ((waited: number) -> boolean)?,
}
local finalSince = 0

local function applyPhaseRules(phase: string)
	local playing = phase == "Live" or phase == "Overtime"
	-- After a goal everyone keeps skating through the celebration; the goal just can't count twice.
	-- The same after the final horn, for a few seconds before the post-game screen.
	local celebrating = phase == "GoalFrozen" or phase == "Buzzer"
	world.controlsEnabled = playing or celebrating
	world.stickHits = playing or celebrating
	world.goalsEnabled = playing
	-- Until play starts the puck hangs over the face-off dot, then drops.
	world.puckHeld = not (playing or celebrating)
end

local function transition(nextPhase: string, seconds: number?): boolean
	local allowed = ALLOWED[state.phase]
	if not allowed or not allowed[nextPhase] then
		warn(`[Match] refused transition {state.phase} -> {nextPhase}`)
		return false
	end
	state.phase = nextPhase
	state.phaseId = state.phaseId % 65535 + 1
	state.revision += 1
	state.phaseEndsAt = if seconds then workspace:GetServerTimeNow() + seconds else 0
	applyPhaseRules(nextPhase)
	publish()
	return true
end

local function resetMatch()
	state.scores = { 0, 0 }
	state.clock = MATCH.LengthSeconds
	state.inOvertime = false
	state.winner = 0
	state.matchId += 1
	hooks.onMatchReset()
	World.resetForFaceoff(world, true)
end

local function toFaceoff()
	World.resetForFaceoff(world, true)
	transition("Faceoff", MATCH.FaceoffSeconds)
end

local function toFinal()
	state.winner = if state.scores[1] > state.scores[2] then 1 elseif state.scores[2] > state.scores[1] then 2 else 0
	if hooks.onFinal then
		hooks.onFinal(state.winner)
	end
	finalSince = workspace:GetServerTimeNow()
	transition("Final", MATCH.FinalMaxSeconds)
end

function MatchService.init(w: Sim.World, publishFn: () -> (), hookFns: any)
	world = w
	publish = publishFn
	hooks = hookFns
	applyPhaseRules(state.phase)
end

function MatchService.get()
	return state
end

-- Studio testing only (Main's DebugClock attribute).
function MatchService.debugClock(seconds: number)
	state.clock = math.max(0, seconds)
end

function MatchService.phaseId(): number
	return state.phaseId
end

-- Used when the first human steps onto the ice during a bot-only attract match.
function MatchService.restart()
	if state.phase == "Final" then
		return
	end
	resetMatch()
	transition("Countdown", MATCH.CountdownSeconds)
end

-- Returns the goal id once, or nil if this goal must not count.
function MatchService.awardGoal(team: number): number?
	if state.phase ~= "Live" and state.phase ~= "Overtime" then
		return nil
	end
	state.scores[team] += 1
	state.lastGoalId += 1
	transition("GoalFrozen", MATCH.GoalFreeze)
	return state.lastGoalId
end

-- Enough players voted to skip the goal replay: cut the goal freeze short. The celebration
-- (Replay.CELEBRATE, 3.2 s since Build 39) still plays, then the replay wipes out (about 1.3 s) and the
-- face-off comes straight after.
local CELEBRATE, WIPE_OUT = 3.2, 1.3
function MatchService.skipReplay()
	if state.phase ~= "GoalFrozen" then
		return
	end
	local now = workspace:GetServerTimeNow()
	local startedAt = state.phaseEndsAt - MATCH.GoalFreeze
	local endsAt = math.max(now, startedAt + CELEBRATE) + WIPE_OUT
	if endsAt < state.phaseEndsAt then
		state.phaseEndsAt = endsAt
		state.revision += 1
		publish()
	end
end

function MatchService.puckStuck()
	if state.phase == "Live" or state.phase == "Overtime" then
		toFaceoff()
	end
end

function MatchService.step(dt: number)
	local phase = state.phase
	local now = workspace:GetServerTimeNow()
	local expired = state.phaseEndsAt > 0 and now >= state.phaseEndsAt

	if hooks.humanCount() == 0 and phase ~= "Waiting" then
		transition("Waiting")
		return
	end

	if phase == "Waiting" then
		if hooks.humanCount() > 0 then
			resetMatch()
			transition("Countdown", MATCH.CountdownSeconds)
		end
	elseif phase == "Countdown" then
		if expired then
			toFaceoff()
		end
	elseif phase == "Faceoff" then
		if expired then
			transition(if state.inOvertime then "Overtime" else "Live")
		end
	elseif phase == "Live" then
		state.clock = math.max(0, state.clock - dt)
		if state.clock <= 0 then
			if state.scores[1] == state.scores[2] then
				state.inOvertime = true
				toFaceoff()
			else
				-- The horn: the result is settled now, then a few seconds of skating about.
				state.winner = if state.scores[1] > state.scores[2] then 1 else 2
				transition("Buzzer", MATCH.BuzzerSeconds)
			end
		end
	elseif phase == "Buzzer" then
		if expired then
			toFinal()
		end
	elseif phase == "GoalFrozen" then
		if expired then
			if state.inOvertime or state.clock <= 0 then
				toFinal()
			else
				toFaceoff()
			end
		end
	elseif phase == "Final" then
		-- The post-game screen waits for the players (see Match.FinalMaxSeconds).
		local ready = if hooks.readyForNext then hooks.readyForNext(now - finalSince) else now - finalSince >= MATCH.FinalSeconds
		if expired or ready then
			transition("Cleanup", MATCH.CleanupSeconds)
		end
	elseif phase == "Cleanup" then
		if expired then
			resetMatch()
			transition("Countdown", MATCH.CountdownSeconds)
		end
	end
end

return MatchService
