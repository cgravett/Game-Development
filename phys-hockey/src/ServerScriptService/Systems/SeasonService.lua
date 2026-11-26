--!strict
-- Season pass premium: a game pass per season (vault note "Game Passes").
--
-- Ownership is a fact Roblox holds. The server checks it when a profile loads and when a
-- purchase finishes on this server, retrying with backoff because the check can fail or briefly
-- lag a fresh purchase. Only a confirmed `true` is ever saved (PlayerData.setSeasonPremium);
-- an unknown result is checked again later, never stored as "not owned". The client only
-- opens the purchase prompt; it can never say "I bought it".

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SeasonPass = require(ReplicatedStorage.Shared.SeasonPass)
local PlayerData = require(script.Parent.Parent.Data.PlayerData)

local SeasonService = {}

local seasonByPass: { [number]: string } = {}
for _, season in SeasonPass.Seasons do
	if season.premiumPassId ~= 0 then
		seasonByPass[season.premiumPassId] = season.id
	end
end

-- true / false when Roblox answered, nil when every attempt failed.
local function ownsWithRetry(userId: number, passId: number, attempts: number): boolean?
	for attempt = 1, attempts do
		local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, userId, passId)
		if ok then
			return result == true
		end
		task.wait(attempt)
	end
	return nil
end

local function check(player: Player, passId: number, seasonId: string)
	local owns = ownsWithRetry(player.UserId, passId, 3)
	if owns == nil then
		-- Unknown (Roblox unreachable): look again in a little while, never save "not owned".
		task.delay(30, function()
			if player.Parent and ownsWithRetry(player.UserId, passId, 3) then
				PlayerData.setSeasonPremium(player, seasonId)
			end
		end)
	elseif owns and player.Parent then
		PlayerData.setSeasonPremium(player, seasonId)
	end
end

-- Once the player's profile is loaded: pay out what is owed, then check every season pass.
function SeasonService.onLoaded(player: Player)
	PlayerData.settleSeasons(player)
	for passId, seasonId in seasonByPass do
		task.spawn(check, player, passId, seasonId)
	end
end

function SeasonService.init()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, wasPurchased: boolean)
		local seasonId = seasonByPass[passId]
		if not seasonId or not wasPurchased then
			return
		end
		-- Confirm with Roblox before saving anything. A fresh purchase can take a moment to show,
		-- so poll a few times with growing gaps.
		task.spawn(function()
			for wait = 1, 5 do
				if not player.Parent then
					return
				end
				if ownsWithRetry(player.UserId, passId, 2) then
					PlayerData.setSeasonPremium(player, seasonId)
					return
				end
				task.wait(wait * 2)
			end
			warn(`[SeasonService] {player.UserId}: pass {passId} purchase not confirmed yet; it is checked again on the next join`)
		end)
	end)
end

return SeasonService
