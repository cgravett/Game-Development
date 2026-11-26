local Config = require(script.Parent.Parent.Config)
local Scoring = {}
function Scoring.multiplier(tier)
 local r = tier and Config.Rarity[tier]
 return r and r.mult or 0
end
function Scoring.points(_base, tier)
 local r = tier and Config.Rarity[tier]
 return r and r.points or 0
end
function Scoring.wager(score, wager, tier)
 assert(wager >= 0 and wager <= score and wager % 1 == 0, "Invalid wager")
 return score + (tier and Config.Rarity[tier] and wager * Scoring.multiplier(tier) or -wager)
end
return Scoring

