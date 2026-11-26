--!strict
-- Login rewards: a 7-day streak of coins, one claim per day. A "day" is a whole UTC day (resets
-- at 00:00 UTC, the same moment the daily challenges change), counted as an integer so every
-- comparison is exact. Miss a day and the streak starts again at day 1; after day 7 it goes
-- round again. Only the server's clock decides (vault: "Daily Rewards System End to End").
--
-- Day 1 is the tutorial's coins for a brand-new player: finishing the tutorial counts as that
-- day's claim (see PlayerData.finishTutorial), so a new player is never paid day 1 twice.

local LoginRewards = {}

LoginRewards.Track = { 350, 500, 750, 1000, 1250, 1500, 2000 }
LoginRewards.GraceDays = 0 -- days that can be missed without losing the streak
LoginRewards.ResetOffsetHours = 0 -- 00:00 UTC

local DAY = 86400

function LoginRewards.dayIndex(unixTime: number): number
	return math.floor((unixTime - LoginRewards.ResetOffsetHours * 3600) / DAY)
end

-- Unix time when the given day ends (the next reset).
function LoginRewards.dayEnds(day: number): number
	return (day + 1) * DAY + LoginRewards.ResetOffsetHours * 3600
end

export type State = {
	canClaim: boolean,
	slot: number, -- 1..7: the slot claimed today, or the one that would be
	streak: number, -- the streak as it stands (after today's claim, if made)
}

-- The track as it stands, from the save (last claimed day, streak) and today. Pure: no data,
-- no players, so it is easy to test.
function LoginRewards.evaluate(lastDay: number, streak: number, today: number): State
	local length = #LoginRewards.Track
	if lastDay >= today then
		-- Claimed today. (A later day than today only happens with clock skew or a Studio test
		-- offset: treat it as claimed rather than paying again.)
		local shown = math.max(streak, 1)
		return { canClaim = false, slot = (shown - 1) % length + 1, streak = shown }
	end
	local continues = lastDay >= 0 and today - lastDay <= 1 + LoginRewards.GraceDays
	local nextStreak = if continues then streak + 1 else 1
	return { canClaim = true, slot = (nextStreak - 1) % length + 1, streak = if continues then streak else 0 }
end

return LoginRewards
