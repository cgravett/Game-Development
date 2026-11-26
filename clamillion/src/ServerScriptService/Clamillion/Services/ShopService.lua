-- Player inventory for the shop: what each player owns and has equipped (podium theme, arena,
-- title, emote). Saved in a DataStore. Purchases go through Developer Products (see ShopCatalog for
-- where to put product ids); ProcessReceipt grants the item.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local RS = game:GetService("ReplicatedStorage")
local Catalog = require(RS.Clamillion.Shared.ShopCatalog)
local Events = require(RS.Clamillion.Shared.Events)
local Config = require(script.Parent.Parent.Config)
local Remotes = RS.Clamillion.Remotes

local Shop = {}
local store = DataStoreService:GetDataStore("ClamillionInventory_v1")
local receipts = DataStoreService:GetDataStore("ClamillionReceipts_v1")
local data = {}    -- player -> {owned = {id=true}, equipped = {Podium=, Arena=, Title=}}
local loaded = {}  -- player -> true once their save has loaded (or failed safely)
local dirty = {}

local STUDIO_UNLOCK = RunService:IsStudio() and Config.Shop and Config.Shop.unlockAllInStudio

local function blank() return { owned = {}, equipped = {}, pending = {}, stats = { playtime = 0, totalScore = 0, halloween = 0 }, seen = {}, hintCredits = 0 } end
local CollectionService = game:GetService("CollectionService")

function Shop.owns(p, id)
	local item = Catalog.get(id)
	if not item then return false end
	if item.source == "free" then return true end
	-- rewards always have to be earned and claimed, even in Studio
	if STUDIO_UNLOCK and item.source ~= "reward" then return true end
	local d = data[p]
	return d ~= nil and d.owned[id] == true
end

function Shop.equipped(p, kind)
	local d = data[p]
	local id = d and d.equipped[kind]
	if id and Shop.owns(p, id) then return Catalog.get(id) end
	return nil
end

-- the text shown on a podium / above the head, e.g. "🧠 Big Brain"
function Shop.titleText(p)
	local t = Shop.equipped(p, "Title")
	return t and (t.icon .. " " .. t.name) or nil
end
-- animation style for the equipped title ("rainbow", "gold"...), nil for a still title
function Shop.titleAnim(p)
	local t = Shop.equipped(p, "Title")
	return t and t.anim or nil
end

---------------------------------------------------------------- playtime + total score
local function stats(p) return data[p] and data[p].stats end
local function publishStats(p)
	local s = stats(p)
	if not s then return end
	p:SetAttribute("Playtime", s.playtime)
	p:SetAttribute("TotalScore", s.totalScore)
	p:SetAttribute("HalloweenPlaytime", s.halloween or 0)
end
function Shop.addScore(p, points)
	local s = stats(p)
	if not s or type(points) ~= "number" or points <= 0 then return end
	s.totalScore += math.floor(points)
	dirty[p] = true
	publishStats(p)
end
function Shop.addPlaytime(p, seconds)
	local s = stats(p)
	if not s then return end
	s.playtime += seconds
	dirty[p] = true
	publishStats(p)
end
-- playtime that only counts while an event is on (e.g. the Halloween title needs 5 event minutes)
function Shop.addEventPlaytime(p, stat, seconds)
	local s = stats(p)
	if not s then return end
	s[stat] = (s[stat] or 0) + seconds
	dirty[p] = true
	publishStats(p)
end
function Shop.canClaim(p, item)
	local s = stats(p)
	if not (item and item.source == "reward" and s ~= nil) then return false end
	-- event rewards can only be claimed while their event is on (owners keep them afterwards)
	if item.event and not Events.isActive(item.event) then return false end
	return (s[item.stat] or 0) >= item.req
end

-- emote TRY button in the shop: 3 free previews every 12 hours (saved, so rejoining doesn't reset it)
local TRY_MAX, TRY_WINDOW = 3, 12 * 3600
function Shop.tryStatus(p)
	local d = data[p]
	local t = d and d.tries
	local now = os.time()
	if not t or not t.start or now - t.start >= TRY_WINDOW then return { left = TRY_MAX, resetAt = nil } end
	return { left = math.max(0, TRY_MAX - (t.count or 0)), resetAt = t.start + TRY_WINDOW }
end
local function useTry(p)
	local d = data[p]
	if not d then return { ok = false, left = 0 } end
	local now = os.time()
	local t = d.tries
	if not t or not t.start or now - t.start >= TRY_WINDOW then t = { start = now, count = 0 } end
	if (t.count or 0) >= TRY_MAX then return { ok = false, left = 0, resetAt = t.start + TRY_WINDOW } end
	t.count = (t.count or 0) + 1
	d.tries = t
	dirty[p] = true
	return { ok = true, left = TRY_MAX - t.count, resetAt = t.start + TRY_WINDOW }
end

---------------------------------------------------------------- mystery box
-- Paid random items: only for players whose region allows them (PolicyService). If the policy
-- can't be checked, the box stays closed for that player, to be safe.
local PolicyService = game:GetService("PolicyService")
local BOX = Catalog.MysteryBox
local boxPolicy = {} -- player -> true (allowed) / false (restricted)
local function boxAllowed(p)
	if boxPolicy[p] ~= nil then return boxPolicy[p] end
	local ok, info = pcall(function() return PolicyService:GetPolicyInfoForPlayerAsync(p) end)
	if not ok or type(info) ~= "table" then return false end -- try again next time
	boxPolicy[p] = info.ArePaidRandomItemsRestricted ~= true
	return boxPolicy[p]
end
-- shop items of this kind the player doesn't own yet (their real save; Studio's "unlock all" is ignored)
local function boxPool(p, kind)
	local list = {}
	local owned = data[p] and data[p].owned or {}
	for _, item in ipairs(Catalog.Kinds[kind] or {}) do
		if item.source == "shop" and not owned[item.id] then table.insert(list, item) end
	end
	return list
end
-- the exact odds for THIS player, shown before they buy: every category, every item in it
function Shop.boxOdds(p)
	local rows = {}
	for _, cat in ipairs(BOX.odds) do
		local row = { kind = cat.kind, label = cat.label, icon = cat.icon, pct = cat.pct, items = {} }
		if cat.kind ~= "Hint" then
			local pool = boxPool(p, cat.kind)
			if #pool == 0 then
				row.complete = true -- they own the whole category: this slice pays out hints instead
			else
				for _, item in ipairs(pool) do table.insert(row.items, { id = item.id, name = item.name, icon = item.icon, pct = cat.pct / #pool }) end
			end
		end
		table.insert(rows, row)
	end
	return rows
end
-- open one box: pick the category by its odds, then an item they don't own from it
function Shop.rollBox(p)
	local d = data[p]
	if not d then return nil end
	local roll = math.random() * 100
	local cat = BOX.odds[#BOX.odds]
	for _, c in ipairs(BOX.odds) do
		roll -= c.pct
		if roll <= 0 then cat = c break end
	end
	local pool = cat.kind ~= "Hint" and boxPool(p, cat.kind) or {}
	if #pool == 0 then
		d.hintCredits += BOX.hints
		dirty[p] = true
		p:SetAttribute("HintCredits", d.hintCredits)
		return { kind = "Hint", hints = BOX.hints, category = cat.kind, complete = cat.kind ~= "Hint" }
	end
	local item = pool[math.random(1, #pool)]
	Shop.grant(p, item.id, false)
	return { kind = item.kind, id = item.id, category = cat.kind }
end

local function snapshot(p)
	local owned = {}
	for kind, list in pairs(Catalog.Kinds) do
		for _, item in ipairs(list) do if Shop.owns(p, item.id) then owned[item.id] = true end end
	end
	local d = data[p] or blank()
	return { owned = owned, equipped = d.equipped, studioUnlock = STUDIO_UNLOCK == true, stats = d.stats, tries = Shop.tryStatus(p) }
end

local function push(p)
	-- the equipped emote rides on the player so the show can play it (wins + very rare answers)
	local emote = Shop.equipped(p, "Emote")
	p:SetAttribute("Emote", emote and emote.id or nil)
	-- the equipped arena theme: only this player's own client dresses the stage with it
	local arena = Shop.equipped(p, "Arena")
	p:SetAttribute("ArenaTheme", arena and arena.theme or nil)
	if p.Parent == Players then Remotes.ShopUpdate:FireClient(p, snapshot(p)) end
end

-- overhead title in the lobby (hidden while on stage, where the podium shows it instead)
local function showTitle(p)
	local text = Shop.titleText(p)
	p:SetAttribute("Title", text)
	local head = p.Character and p.Character:FindFirstChild("Head")
	if not head then return end
	local old = head:FindFirstChild("DailyTitle")
	if old then old:Destroy() end
	if not text then return end
	local g = Instance.new("BillboardGui")
	g.Name = "DailyTitle"; g.Size = UDim2.fromOffset(180, 28); g.StudsOffset = Vector3.new(0, 2.6, 0); g.MaxDistance = 65
	g.Enabled = not p:GetAttribute("OnStage"); g.Parent = head
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1); t.BackgroundTransparency = 1; t.Text = text; t.Font = Enum.Font.FredokaOne
	t.TextColor3 = Color3.fromRGB(255, 215, 70); t.TextStrokeTransparency = 0.3; t.TextScaled = true; t.Parent = g
	local anim = Shop.titleAnim(p)
	if anim then -- clients animate anything tagged AnimatedTitle
		t:SetAttribute("Anim", anim)
		CollectionService:AddTag(t, "AnimatedTitle")
		g.Size = UDim2.fromOffset(210, 32)
	end
end
Shop.showTitle = showTitle

local function save(p)
	if RunService:IsStudio() or not loaded[p] or not dirty[p] then return end
	local d = data[p]
	local ok = pcall(function()
		store:UpdateAsync("u" .. p.UserId, function(old)
			old = old or blank()
			for id in pairs(d.owned) do old.owned[id] = true end -- never lose an item
			if d.loadFailed then
				-- we never managed to read their save this visit: don't wipe what's stored there
				if next(d.equipped) ~= nil then
					old.equipped = old.equipped or {}
					for kind, id in pairs(d.equipped) do old.equipped[kind] = id end
				end
				old.hintCredits = math.max(old.hintCredits or 0, d.hintCredits)
			else
				old.equipped = d.equipped
				old.pending = d.pending
				old.seen = d.seen
				old.hintCredits = d.hintCredits
				old.tries = d.tries
			end
			local os_ = old.stats or {}
			old.stats = { playtime = math.max(os_.playtime or 0, d.stats.playtime), totalScore = math.max(os_.totalScore or 0, d.stats.totalScore),
				halloween = math.max(os_.halloween or 0, d.stats.halloween or 0) }
			return old
		end)
	end)
	if ok then dirty[p] = nil end
end

-- give an item (purchase, wheel prize...). Returns true if it's now owned.
function Shop.grant(p, id, equipNow)
	local item = Catalog.get(id)
	if not item or not data[p] then return false end
	data[p].owned[id] = true
	dirty[p] = true
	if equipNow then data[p].equipped[item.kind] = id end
	if item.kind == "Title" then showTitle(p) end
	push(p)
	task.spawn(save, p)
	return true
end

local saveSoon = {}
local function scheduleSave(p)
	if saveSoon[p] then return end
	saveSoon[p] = true
	task.delay(6, function() saveSoon[p] = nil; if p.Parent == Players then save(p) end end)
end

function Shop.equip(p, id)
	local item = Catalog.get(id)
	if not item or not data[p] or not Shop.owns(p, id) then return false end
	data[p].equipped[item.kind] = id
	dirty[p] = true
	if item.kind == "Title" then showTitle(p) end
	push(p)
	scheduleSave(p)
	return true
end

function Shop.unequip(p, kind)
	if not data[p] or not Catalog.Kinds[kind] then return end
	data[p].equipped[kind] = nil
	dirty[p] = true
	if kind == "Title" then showTitle(p) end
	push(p)
	scheduleSave(p)
end

-- Questions this player has been asked, oldest first, so new shows can skip ones they've seen.
-- Capped a bit under the bank size (276) so a full show of brand-new questions always exists.
local SEEN_CAP = 260
function Shop.seenQuestions(p)
	return data[p] and data[p].seen or {}
end
function Shop.markSeen(p, id)
	local d = data[p]
	if not d or type(id) ~= "string" then return end
	local list = d.seen
	local at = table.find(list, id)
	if at then table.remove(list, at) end
	table.insert(list, id)
	while #list > SEEN_CAP do table.remove(list, 1) end
	dirty[p] = true
end

-- wait (briefly) until a player's save is loaded
function Shop.ready(p)
	local t = os.clock()
	while not loaded[p] and p.Parent == Players and os.clock() - t < 10 do task.wait(0.1) end
	return loaded[p] == true
end

local function load(p)
	data[p] = blank()
	if not RunService:IsStudio() then
		-- a few tries: a failed read must never be mistaken for "brand-new player" (that would
		-- un-equip their podium, title, arena and emote the next time we save)
		local ok, saved
		for attempt = 1, 4 do
			ok, saved = pcall(function() return store:GetAsync("u" .. p.UserId) end)
			if ok or p.Parent ~= Players then break end
			task.wait(attempt * 1.5)
		end
		if not ok then data[p].loadFailed = true; warn("[Clamillion] couldn't load save for " .. p.Name .. "; keeping their stored items safe") end
		if ok and saved then
			data[p].owned = saved.owned or {}
			data[p].equipped = saved.equipped or {}
			data[p].pending = saved.pending or {}
			data[p].seen = type(saved.seen) == "table" and saved.seen or {}
			data[p].hintCredits = tonumber(saved.hintCredits) or 0
			if type(saved.tries) == "table" then data[p].tries = saved.tries end
			if saved.stats then
				data[p].stats.playtime = saved.stats.playtime or 0
				data[p].stats.totalScore = saved.stats.totalScore or 0
				data[p].stats.halloween = saved.stats.halloween or 0
			end
		end
	end
	loaded[p] = true
	p:SetAttribute("HintCredits", data[p].hintCredits)
	publishStats(p)
	showTitle(p)
	push(p)
end

function Shop.init(isInMatch)
	Remotes.ShopRequest.OnServerInvoke = function(p, action, id)
		Shop.ready(p)
		if action == "inventory" then return snapshot(p) end
		if action == "equip" then return { ok = Shop.equip(p, id), state = snapshot(p) } end
		if action == "unequip" then Shop.unequip(p, id); return { ok = true, state = snapshot(p) } end
		if action == "claim" then
			local item = Catalog.get(id)
			if not item or item.source ~= "reward" then return { ok = false, reason = "missing" } end
			if Shop.owns(p, id) then return { ok = false, reason = "owned", state = snapshot(p) } end
			if not Shop.canClaim(p, item) then return { ok = false, reason = "locked", state = snapshot(p) } end
			Shop.grant(p, id, false)
			return { ok = true, state = snapshot(p) }
		end
		-- HINT ? button: a Very Rare answer for the question you're on (MatchService delivers it).
		-- A paid hint that arrives too late (time ran out) is kept as a free hint for next time.
		if action == "boxInfo" then
			return { allowed = boxAllowed(p), price = BOX.price, hints = BOX.hints, odds = Shop.boxOdds(p), ready = BOX.productId ~= nil or RunService:IsStudio(), hintCredits = data[p] and data[p].hintCredits or 0 }
		end
		if action == "openBox" then
			if not boxAllowed(p) then return { ok = false, reason = "restricted" } end
			if isInMatch(p) then return { ok = false, reason = "match" } end
			if not BOX.productId then
				-- no Developer Product yet: Studio playtests open for free so the box can be tested
				if RunService:IsStudio() then return { ok = true, reason = "studio", result = Shop.rollBox(p), state = snapshot(p) } end
				return { ok = false, reason = "soon" }
			end
			MarketplaceService:PromptProductPurchase(p, BOX.productId)
			return { ok = true, reason = "prompted" }
		end
		if action == "tryEmote" then
			local item = Catalog.get(id)
			if not item or item.kind ~= "Emote" then return { ok = false, left = 0 } end
			return useTry(p)
		end
		if action == "hint" then
			local h = Shop.hints
			if not (h and h.canHint(p)) then return { ok = false, reason = "closed" } end
			local d = data[p]
			if d.hintCredits > 0 then
				if h.give(p) then
					d.hintCredits -= 1; dirty[p] = true
					p:SetAttribute("HintCredits", d.hintCredits)
				end
				return { ok = true, reason = "given" }
			end
			if not Catalog.HintProduct then
				if RunService:IsStudio() then h.give(p); return { ok = true, reason = "studio" } end
				return { ok = false, reason = "soon" }
			end
			MarketplaceService:PromptProductPurchase(p, Catalog.HintProduct)
			return { ok = true, reason = "prompted" }
		end
		if action == "buy" then
			local item = Catalog.get(id)
			if not item then return { ok = false, reason = "missing" } end
			if Shop.owns(p, id) then return { ok = false, reason = "owned" } end
			if item.source == "wheel" then return { ok = false, reason = "wheel" } end
			if not Catalog.forSale(item) then return { ok = false, reason = "soon" } end
			if isInMatch(p) then return { ok = false, reason = "match" } end
			-- remember which item this price-tier purchase is for (saved, in case they rejoin before it's granted)
			data[p].pending[item.kind] = item.id
			dirty[p] = true
			task.spawn(save, p)
			MarketplaceService:PromptProductPurchase(p, Catalog.productFor(item))
			return { ok = true, reason = "prompted" }
		end
		return nil
	end

	-- Robux purchases (Developer Products). Grants are idempotent per receipt.
	MarketplaceService.ProcessReceipt = function(info)
		local p = Players:GetPlayerByUserId(info.PlayerId)
		if not p or not Shop.ready(p) then return Enum.ProductPurchaseDecision.NotProcessedYet end
		local key = "r" .. info.PurchaseId
		local ok, already = pcall(function() return receipts:GetAsync(key) end)
		if ok and already then return Enum.ProductPurchaseDecision.PurchaseGranted end
		if Catalog.HintProduct and info.ProductId == Catalog.HintProduct then
			local h = Shop.hints
			if not (h and h.canHint(p) and h.give(p)) then
				data[p].hintCredits += 1
				dirty[p] = true
				p:SetAttribute("HintCredits", data[p].hintCredits)
				task.spawn(save, p)
				Remotes.MatchState:FireClient(p, { type = "HintSaved" })
			end
			pcall(function() receipts:SetAsync(key, true) end)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		-- MYSTERY BOX: roll the prize, save it, then show the opening on their screen
		if BOX.productId and info.ProductId == BOX.productId then
			local result = Shop.rollBox(p)
			if not result then return Enum.ProductPurchaseDecision.NotProcessedYet end
			dirty[p] = true
			save(p)
			if dirty[p] then return Enum.ProductPurchaseDecision.NotProcessedYet end -- save failed, retry later
			pcall(function() receipts:SetAsync(key, true) end)
			Remotes.ShopUpdate:FireClient(p, snapshot(p), { mysteryBox = result })
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		local item = Catalog.byProduct(info.ProductId)
		local tier = not item and Catalog.tierKind(info.ProductId)
		if tier then item = Catalog.get(data[p].pending[tier] or "") end
		if not item then return Enum.ProductPurchaseDecision.NotProcessedYet end
		Shop.grant(p, item.id, true)
		if tier then data[p].pending[tier] = nil end
		dirty[p] = true
		save(p)
		if dirty[p] then return Enum.ProductPurchaseDecision.NotProcessedYet end -- save failed, retry later
		pcall(function() receipts:SetAsync(key, true) end)
		Remotes.ShopUpdate:FireClient(p, snapshot(p), { purchased = item.id })
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- EMOTE button: play any emote you own, any time. Everyone nearby sees it (each client animates).
	local emoteRemote = Remotes:FindFirstChild("Emote") or Instance.new("RemoteEvent")
	emoteRemote.Name = "Emote"; emoteRemote.Parent = Remotes
	local emoteAt = {}
	emoteRemote.OnServerEvent:Connect(function(p, emoteId)
		if type(emoteId) ~= "string" then return end
		local item = Catalog.get(emoteId)
		if not item or item.kind ~= "Emote" or not Shop.owns(p, emoteId) then return end
		if emoteAt[p] and os.clock() - emoteAt[p] < 2.5 then return end
		emoteAt[p] = os.clock()
		emoteRemote:FireAllClients(p.UserId, emoteId)
	end)
	Players.PlayerRemoving:Connect(function(p) emoteAt[p] = nil; boxPolicy[p] = nil end)

	Players.PlayerAdded:Connect(function(p)
		task.spawn(load, p)
		p.CharacterAdded:Connect(function() task.wait(0.5); showTitle(p) end)
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(load, p)
		p.CharacterAdded:Connect(function() task.wait(0.5); showTitle(p) end)
	end
	Players.PlayerRemoving:Connect(function(p)
		save(p)
		data[p], loaded[p], dirty[p] = nil, nil, nil
	end)
	game:BindToClose(function()
		for _, p in ipairs(Players:GetPlayers()) do save(p) end
	end)
	-- Studio-only test hook: ServerStorage.ClamillionTest:Invoke(player, "playtime"|"score", amount)
	if RunService:IsStudio() then
		local hook = Instance.new("BindableFunction")
		hook.Name = "ClamillionTest"
		hook.OnInvoke = function(p, what, amount)
			Shop.ready(p)
			if what == "playtime" then Shop.addPlaytime(p, amount) elseif what == "score" then Shop.addScore(p, amount)
			elseif what == "halloween" then Shop.addEventPlaytime(p, "halloween", amount) end
			return data[p] and data[p].stats
		end
		hook.Parent = game:GetService("ServerStorage")
	end
	-- playtime: +1 minute every minute you're here and not AFK (AFK is reported by the lobby queue)
	task.spawn(function()
		while true do
			task.wait(60)
			local halloween = Events.isActive("halloween")
			for _, p in ipairs(Players:GetPlayers()) do
				if not p:GetAttribute("AFK") then
					Shop.addPlaytime(p, 60)
					if halloween then Shop.addEventPlaytime(p, "halloween", 60) end
				end
			end
		end
	end)
	-- autosave equips every couple of minutes
	task.spawn(function()
		while true do
			task.wait(120)
			for _, p in ipairs(Players:GetPlayers()) do task.spawn(save, p) end
		end
	end)
end

return Shop
