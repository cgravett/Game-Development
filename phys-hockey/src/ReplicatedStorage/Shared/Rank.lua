--!strict
-- Competitive rank. Every finished Quick Play match moves your ELO: a win is +20, a loss -18.
-- Each 50 ELO is the next rank: Bronze 1 at 50, Bronze 2 at 100, Bronze 3 at 150, Silver 1 at
-- 200 ... Diamond 3 at 750 and Champion from 800 up. New players start at Bronze 1 (50); ELO never
-- goes below 0, and anything under 100 still shows Bronze 1. When a season ends, the rank you
-- hold becomes a title you keep ("SEASON 1 GOLD 2").

local Rank = {}

Rank.START = 50
Rank.WIN = 20
Rank.LOSS = 18
Rank.STEP = 50

export type Tier = { name: string, color: Color3, dark: Color3, glow: Color3 }

-- The metal of each tier, darkest to brightest.
Rank.Tiers = {
	{ name = "BRONZE", color = Color3.fromRGB(214, 132, 78), dark = Color3.fromRGB(122, 64, 34), glow = Color3.fromRGB(255, 196, 150) },
	{ name = "SILVER", color = Color3.fromRGB(196, 206, 222), dark = Color3.fromRGB(104, 114, 134), glow = Color3.fromRGB(245, 250, 255) },
	{ name = "GOLD", color = Color3.fromRGB(255, 198, 52), dark = Color3.fromRGB(170, 104, 12), glow = Color3.fromRGB(255, 240, 160) },
	{ name = "PLATINUM", color = Color3.fromRGB(86, 214, 206), dark = Color3.fromRGB(26, 116, 124), glow = Color3.fromRGB(190, 255, 246) },
	{ name = "DIAMOND", color = Color3.fromRGB(108, 168, 255), dark = Color3.fromRGB(44, 70, 196), glow = Color3.fromRGB(214, 236, 255) },
	{ name = "CHAMPION", color = Color3.fromRGB(240, 72, 112), dark = Color3.fromRGB(120, 20, 64), glow = Color3.fromRGB(255, 214, 120) },
} :: { Tier }

Rank.COUNT = 16 -- five tiers of three divisions, then Champion

-- Rank index 1..16 for an ELO.
function Rank.index(elo: number): number
	return math.clamp(math.floor(elo / Rank.STEP), 1, Rank.COUNT)
end

-- The tier (1..6) and division (1..3, or 0 for Champion) of a rank index.
function Rank.parts(index: number): (number, number)
	if index >= Rank.COUNT then
		return #Rank.Tiers, 0
	end
	return math.floor((index - 1) / 3) + 1, (index - 1) % 3 + 1
end

function Rank.name(index: number): string
	local tier, division = Rank.parts(index)
	local t = Rank.Tiers[tier]
	return if division == 0 then t.name else `{t.name} {division}`
end

-- ELO at which a rank starts (Bronze 1 counts from 0).
function Rank.floorOf(index: number): number
	return if index <= 1 then 0 else index * Rank.STEP
end

-- The ELO after a match.
function Rank.after(elo: number, won: boolean, lost: boolean): number
	if won then
		return elo + Rank.WIN
	elseif lost then
		return math.max(0, elo - Rank.LOSS)
	end
	return elo
end

return Rank
