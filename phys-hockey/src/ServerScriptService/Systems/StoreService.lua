--!strict
-- Build 34: Robux purchases (developer products): the Mystery Box, and (Build 35) coin packs.
--
-- Rules followed (vault "Developer Products and ProcessReceipt", "Paid Random Items and Odds
-- Disclosure in Practice"):
--   * This is the only script that sets MarketplaceService.ProcessReceipt.
--   * The client only asks; the server decides whether the prompt may open (product on sale,
--     profile loaded and saved, something left to win, paid random items allowed for this
--     player by PolicyService, one prompt a second). Nothing is refused at receipt time.
--   * PurchaseGranted only after the grant and its receipt are saved in the player's profile
--     (PlayerData.grantBox); otherwise NotProcessedYet and Roblox delivers it again.
--   * Players for whom ArePaidRandomItemsRestricted is true (or whose policy can't be read:
--     fail closed) never get the box; the shop shows them why (attribute BoxRestricted).

local MarketplaceService = game:GetService("MarketplaceService")
local PolicyService = game:GetService("PolicyService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local PlayerData = require(script.Parent.Parent.Data.PlayerData)

local StoreService = {}

local restricted: { [Player]: boolean } = {}
local lastPrompt: { [Player]: number } = {}
local onGranted: ((Player, string, number) -> ())? = nil

local function readPolicy(player: Player)
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	-- Fail closed: no policy, no box.
	local blocked = not ok or type(info) ~= "table" or (info :: any).ArePaidRandomItemsRestricted ~= false
	restricted[player] = blocked
	if player.Parent then
		player:SetAttribute("BoxRestricted", blocked)
	end
end

-- The shop's "OPEN" button. Returns ok and a message for a refusal.
function StoreService.promptBox(player: Player): (boolean, string)
	local id = Config.Box.ProductId
	if id == 0 then
		return false, "The Mystery Box is coming soon!"
	end
	if restricted[player] ~= false then
		return false, "Mystery Boxes aren't available where you live."
	end
	local now = os.clock()
	if (lastPrompt[player] or -math.huge) > now - 1 then
		return false, ""
	end
	local ok, reason = PlayerData.canOpenBox(player)
	if not ok then
		return false, reason
	end
	lastPrompt[player] = now
	MarketplaceService:PromptProductPurchase(player, id)
	return true, ""
end

-- Build 35: a coin pack from the shop's COINS section, by its Config.CoinPacks key.
local function packByKey(key: any): any
	for _, pack in Config.CoinPacks do
		if pack.key == key then
			return pack
		end
	end
	return nil
end

local function packByProduct(productId: number): any
	if productId == 0 then
		return nil
	end
	for _, pack in Config.CoinPacks do
		if pack.productId == productId then
			return pack
		end
	end
	return nil
end

function StoreService.promptCoins(player: Player, key: any): (boolean, string)
	local pack = packByKey(key)
	if not pack then
		return false, ""
	end
	if pack.productId == 0 then
		return false, "Coin packs are coming soon!"
	end
	local now = os.clock()
	if (lastPrompt[player] or -math.huge) > now - 1 then
		return false, ""
	end
	local ok, reason = PlayerData.canBuyCoins(player, pack.coins)
	if not ok then
		return false, reason
	end
	lastPrompt[player] = now
	MarketplaceService:PromptProductPurchase(player, pack.productId)
	return true, ""
end

local onCoins: ((Player, number) -> ())? = nil

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local pack = packByProduct(info.ProductId)
	if pack then
		local result = PlayerData.grantCoins(player, tostring(info.PurchaseId), info.ProductId, pack.coins, tonumber(info.CurrencySpent) or 0)
		if result == "granted" then
			if onCoins then
				task.spawn(onCoins, player, pack.coins)
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if info.ProductId == Config.Box.ProductId and Config.Box.ProductId ~= 0 then
		local result, item, coins = PlayerData.grantBox(player, tostring(info.PurchaseId), info.ProductId, tonumber(info.CurrencySpent) or 0)
		if result == "granted" then
			if onGranted then
				task.spawn(onGranted, player, item, coins)
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- Unknown product: leave it for a server that knows it.
	warn(`[StoreService] receipt for unknown product {info.ProductId}`)
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- granted(player, itemId, coins): after a box is granted and saved (drives the reveal).
-- coinsGranted(player, coins): after a coin pack is granted and saved.
function StoreService.init(granted: (Player, string, number) -> (), coinsGranted: ((Player, number) -> ())?)
	onGranted = granted
	onCoins = coinsGranted
	MarketplaceService.ProcessReceipt = processReceipt
	Players.PlayerAdded:Connect(function(player)
		task.spawn(readPolicy, player)
	end)
	for _, p in Players:GetPlayers() do
		task.spawn(readPolicy, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		restricted[player] = nil
		lastPrompt[player] = nil
	end)
end

return StoreService
