-- Awards Clamillion's badges (Creator Hub > Engagement > Badges). Server-only.
-- Awards run in the background and never block the show; if Roblox is briefly unavailable the
-- award simply happens the next time the player earns it.
local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")

local Badges = {}
Badges.Ids = {
	welcome = 4230166949901798, -- "Welcome to the Show!": finish your first show
	champion = 546943843226006, -- "Champion!": win a 1v1 or 1v1v1 show
	extreme = 809051077565997, -- "One in a Clamillion": give an Extremely Rare (100-point) answer
	bigscore = 4132013721999, -- "Big Brain": score 1,000+ points in a single show
	legend = 1730711805838212, -- "Clamillion Legend": 10,000 total points across all shows
}
Badges.BigScore = 1000
Badges.LegendTotal = 10000

local done = {} -- player -> { key = true } once owned/awarded (this session)
local busy = {}

function Badges.award(player, key)
	local id = Badges.Ids[key]
	if not id or not player or player.Parent ~= Players then return end
	done[player] = done[player] or {}
	busy[player] = busy[player] or {}
	if done[player][key] or busy[player][key] then return end
	busy[player][key] = true
	task.spawn(function()
		local ok, has = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, id)
		if ok and not has then
			-- AwardBadge returns false in Studio playtests (badges are only awarded in live servers)
			local ok2, awarded = pcall(BadgeService.AwardBadge, BadgeService, player.UserId, id)
			ok, has = ok2, ok2 and awarded == true
			if not ok2 then warn(("[Clamillion] Badge %s not awarded to %s: %s"):format(key, player.Name, tostring(awarded))) end
		end
		if done[player] and ok and has then done[player][key] = true end
		if busy[player] then busy[player][key] = nil end
	end)
end

-- Total points live in the player's "TotalScore" attribute (ShopService); this also covers players
-- who already passed 10,000 before the badge existed.
local function watchTotal(player)
	local function check()
		if (player:GetAttribute("TotalScore") or 0) >= Badges.LegendTotal then Badges.award(player, "legend") end
	end
	player:GetAttributeChangedSignal("TotalScore"):Connect(check)
	check()
end
Players.PlayerAdded:Connect(watchTotal)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(watchTotal, p) end
Players.PlayerRemoving:Connect(function(p) done[p] = nil; busy[p] = nil end)

return Badges
