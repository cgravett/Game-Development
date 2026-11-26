--!strict
-- Build 34: the Mystery Box, a paid random item (bought with Robux, a developer product).
--
-- Roblox rules (vault "Paid Random Items and Odds Disclosure in Practice"): every possible
-- outcome and its real odds are shown before purchase, summing to 100%, from the very table the
-- server rolls; outcomes a player can only get once (everything here) are taken out for that
-- player, and the rest renormalised; players for whom PolicyService says paid random items are
-- restricted never get the prompt (StoreService gates it on the server).
--
-- So there is one function, MysteryBox.odds(owned), that both the odds panel and the server's
-- roll use. A tier with nothing left in it gets weight 0, so its share goes to the others.

local Catalog = require(script.Parent.Catalog)

local MysteryBox = {}

export type Tier = { key: string, name: string, weight: number }
export type Outcome = { id: string, tier: string, p: number }

-- Tier weights (percent of a box when the player owns nothing in it).
MysteryBox.Tiers = {
	{ key = "rink", name = "RINK", weight = 5 },
	{ key = "outfit", name = "OUTFIT", weight = 10 },
	{ key = "hat", name = "HAT", weight = 20 },
	{ key = "stick", name = "STICK", weight = 20 },
	{ key = "bonus", name = "HAIR, GOAL SOUND OR PUCK", weight = 45 },
} :: { Tier }

local function tierOf(item: Catalog.Item): string?
	if item.retired or item.pass or item.reward then
		return nil
	end
	local sold = Catalog.inShop(item)
	if item.kind == "rink" and sold then
		return "rink"
	elseif item.kind == "outfit" and item.box then
		return "outfit"
	elseif item.kind == "hat" and sold then
		return "hat"
	elseif item.kind == "stick" and sold then
		return "stick"
	elseif (item.kind == "hair" and sold) or (item.kind == "goal" and sold) or (item.kind == "puck" and item.box) then
		return "bonus"
	end
	return nil
end
MysteryBox.tierOf = tierOf

-- Every item in each tier, in catalogue order (fixed, so display and roll agree).
local members: { [string]: { string } } = {}
for _, t in MysteryBox.Tiers do
	members[t.key] = {}
end
for _, item in Catalog.Items do
	local key = tierOf(item)
	if key then
		table.insert(members[key], item.id)
	end
end
MysteryBox.Members = members

-- The odds of every outcome still possible for a player who owns `owned` (id -> true).
-- Probabilities are fractions (0 to 1) and sum to 1. Empty when nothing is left to win.
function MysteryBox.odds(owned: { [string]: any }): { Outcome }
	local total = 0
	local left: { [string]: { string } } = {}
	for _, t in MysteryBox.Tiers do
		local ids = {}
		for _, id in members[t.key] do
			if not owned[id] then
				table.insert(ids, id)
			end
		end
		left[t.key] = ids
		if #ids > 0 then
			total += t.weight
		end
	end
	local out: { Outcome } = {}
	if total <= 0 then
		return out
	end
	for _, t in MysteryBox.Tiers do
		local ids = left[t.key]
		if #ids > 0 then
			local each = t.weight / total / #ids
			for _, id in ids do
				table.insert(out, { id = id, tier = t.key, p = each })
			end
		end
	end
	return out
end

-- Picks one outcome from odds(owned) with a uniform number u in [0, 1). Nil when nothing is left.
function MysteryBox.pick(owned: { [string]: any }, u: number): string?
	local list = MysteryBox.odds(owned)
	local acc = 0
	for _, o in list do
		acc += o.p
		if u < acc then
			return o.id
		end
	end
	local last = list[#list]
	return last and last.id
end

-- Chance of each tier for this player (fractions), for the panel's headings.
function MysteryBox.tierOdds(owned: { [string]: any }): { [string]: number }
	local out = {}
	for _, o in MysteryBox.odds(owned) do
		out[o.tier] = (out[o.tier] or 0) + o.p
	end
	return out
end

-- A fraction as a percentage string, rounded four places below its first non-zero digit (the
-- rounding Roblox allows), trailing zeros trimmed. Never shows a non-zero chance as 0%.
function MysteryBox.percent(p: number): string
	local v = p * 100
	if v <= 0 then
		return "0%"
	end
	local k = math.floor(math.log10(v))
	local decimals = math.clamp(4 - k, 0, 12)
	local text = string.format(`%.{decimals}f`, v)
	if string.find(text, ".", 1, true) then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text .. "%"
end

MysteryBox.Disclaimer = "Odds are rounded, so they may not add up to exactly 100%. Items you already own are left out of your box, so your odds change as you collect."

return MysteryBox
