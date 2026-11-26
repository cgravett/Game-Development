--!strict
-- Daily challenges (weekly until Build 27): four goals that change every day at 00:00 UTC, each
-- worth Reward season pass XP the moment it is done (Reward coins when no season is running). Progress comes from finished Quick Play matches only.
-- The day's four are picked from Pool by the day number, so every server and client agrees on
-- them without storing the list. (The save still calls the day number "week".)

local Challenges = {}

-- Paid for each one done: pass XP while a season runs, else the same number of coins.
Challenges.Reward = 200
Challenges.Count = 4
-- 1 January 2024, 00:00 UTC: days count from here.
local EPOCH = 1704067200
local PERIOD = 24 * 60 * 60

export type Def = { stat: string, targets: { number }, text: string }
export type Challenge = { id: string, stat: string, target: number, text: string }

-- stat is a field of the match line (matches, wins, goals, assists, saves, shots). Targets are
-- sized for a day of play (a few matches).
Challenges.Pool = {
	{ stat = "matches", targets = { 2, 3, 4 }, text = "PLAY %d GAMES" },
	{ stat = "wins", targets = { 1, 2, 3 }, text = "WIN %d GAMES" },
	{ stat = "goals", targets = { 2, 3, 5 }, text = "SCORE %d GOALS" },
	{ stat = "assists", targets = { 1, 2, 3 }, text = "GET %d ASSISTS" },
	{ stat = "saves", targets = { 1, 2, 3 }, text = "MAKE %d SAVES" },
	{ stat = "shots", targets = { 4, 6, 8 }, text = "GET %d SHOTS ON NET" },
} :: { Def }

-- Today's number (the challenges change when it does).
function Challenges.period(now: number): number
	return math.floor((now - EPOCH) / PERIOD)
end

-- Seconds until the next daily reset.
function Challenges.secondsLeft(now: number): number
	return PERIOD - (now - EPOCH) % PERIOD
end

-- Unix time of the next daily reset.
function Challenges.resetsAt(now: number): number
	return now + Challenges.secondsLeft(now)
end

-- The day's four challenges, the same everywhere: a seeded shuffle of the pool, each with one
-- of its targets.
function Challenges.forPeriod(period: number): { Challenge }
	local rng = Random.new(period * 7919 + 13)
	local order = {}
	for i = 1, #Challenges.Pool do
		order[i] = i
	end
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local out = {}
	for k = 1, Challenges.Count do
		local def = Challenges.Pool[order[k]]
		local target = def.targets[rng:NextInteger(1, #def.targets)]
		table.insert(out, { id = `{def.stat}{target}`, stat = def.stat, target = target, text = string.format(def.text, target) })
	end
	return out
end

return Challenges
