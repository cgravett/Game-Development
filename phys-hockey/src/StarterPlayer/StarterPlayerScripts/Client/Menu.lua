--!strict
-- Main menu over the locker-room lobby. The player's own skater stands in the room; the Locker
-- sits on the right so the skater stays in view. The Shop and Season Pass cover the screen like
-- a sports game's store; an item's own page shows your skater wearing it.
-- Every button here leads somewhere that works. Purchases and equips are requests: the server
-- decides, and the menu redraws from the profile it sends back.

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Catalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Catalog"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local SettingsDef = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Settings"))
local Protocol = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Protocol"))
local Looks = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Looks"))
local SeasonPass = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SeasonPass"))
local Rank = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rank"))
local MysteryBox = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MysteryBox"))
local Ui = require(script.Parent.Ui)
local RankBadge = require(script.Parent.RankBadge)
local Prefs = require(script.Parent.Prefs)

local Menu = {}

export type Callbacks = {
	onPlay: () -> (),
	onPractice: () -> (), -- free practice: skate, add pucks, bring in a goalie
	onTutorial: () -> (), -- the guided drills
	onPond: () -> (),
	onDaily: () -> (), -- the Daily Rewards window
	onPreviewLook: (look: any) -> (),
	onEquip: (kind: string, value: any) -> (),
	onBuy: (id: string) -> (),
	onOpenBox: (() -> ())?, -- Build 34: the Mystery Box's OPEN button (the server decides)
	onBuyCoins: ((key: string) -> ())?, -- Build 35: a coin pack's BUY button (the server decides)
	onStayTuned: (() -> ())?, -- Build 36: the 1v1 teaser's STAY TUNED (offers notifications)
	onPreviewGoal: ((style: string?) -> ())?, -- Build 34: plays a goal sound in the shop
	onClaimChallenge: ((id: string) -> ())?, -- Build 32: collect a finished daily challenge
	onPanel: (name: string?) -> (),
}

local BLUE = Color3.fromRGB(34, 86, 190)
local DEEP = Color3.fromRGB(22, 50, 120)
local RED = Color3.fromRGB(214, 52, 56)
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(30, 34, 48)
local GOLD = Color3.fromRGB(255, 206, 60)
local BLACK = Enum.Font.GothamBlack
-- Menu chrome: a bright sports-broadcast blue.
local NAV = Color3.fromRGB(40, 116, 204)
local NAV_DARK = Color3.fromRGB(24, 78, 156)
local BUTTON = Color3.fromRGB(38, 108, 200)
local BAR_H = 76

local callbacks: Callbacks
local root: Frame
local home: Frame
local playButton: TextButton
local panels: { [string]: Frame } = {}
local coinLabel: TextLabel
local levelLabel: TextLabel
local xpFill: Frame
local statusLabel: TextLabel
local nameLabel: TextLabel
local careerLabels: { [string]: TextLabel } = {}
-- Daily challenges card on the home column.
local challengeCells: { { text: TextLabel, count: TextLabel, fill: Frame, bar: Frame, cell: Frame, collect: TextButton, id: string?, pending: boolean? } } = {}
local challengeReset: TextLabel
-- Rank: the emblem by the name in the top bar, and the Rank panel.
local topBadge: Frame
local topBadgeIndex = 0
local rankView: { badge: Frame, name: TextLabel, elo: TextLabel, next: TextLabel, fill: Frame, titles: TextLabel, strokes: { UIStroke } }? = nil
local rankBadgeIndex = 0
local navTabs: { [string]: TextButton } = {}
local promo: Frame
local promoFits = true
local refreshPromo: () -> () = function() end
local tutorialDone = false
local tutorialButton: TextButton? = nil
local tutorialSub: TextLabel? = nil
local howLabel: TextLabel? = nil
local statLabels: { [string]: TextLabel } = {}
local lockerGrid: ScrollingFrame
local shopGrid: ScrollingFrame
local lockerKind = "hat"
local shopKind = "stick" -- Build 36: the shop opens on sticks (its first section)
local lockerTabs: { [string]: TextButton } = {}
local shopScrollTo: ((string) -> ())? = nil
local shopJump: string? = nil -- a slot to scroll to when the shop opens (from the Locker)
local profile: any = nil
-- Set while the Settings panel is borrowed by the in-game menu; BACK then returns there.
local overlayClose: (() -> ())? = nil

local HOW_TO_PLAY = [[<b>Skate</b>   {up} {left} {down} {right}  (left stick). You keep your momentum, so turn early.
<b>Spin stick</b>   Move the mouse left / right  (right stick). Shoot by sweeping the stick through the puck: faster sweep, harder shot.
<b>Stick lift</b>   Hold {lift}  (RT). Raises the stick just over the puck.
<b>Puck lift</b>   Hold {loft}  (LB). Tips the blade back so your sweep chips the puck into the air.
<b>Dash</b>   Tap {dash}  (L3) for a burst the way you are steering. Uses stamina.     <b>Stop</b>   {brake}  (LT).
<b>Flip camera</b>   {flip}  (RB).     <b>Free the cursor</b>   Hold {cursor}.
<b>Zoom</b>   Mouse wheel  (D-pad up / down).     <b>Hide HUD</b>   {hud}.
<b>Scoreboard</b>   Hold {board}.     <b>Practice</b>   {reset} resets the puck, {addPuck} adds a puck, {goalie} brings in a goalie.

3 v 3. Most goals in 5 minutes wins; a tie goes to sudden-death overtime.
Every key can be changed in Settings, Controls.]]

-- The help text always shows the keys the player has actually bound.
local function howToPlay(): string
	return (string.gsub(HOW_TO_PLAY, "{(%a+)}", function(action: string)
		return Prefs.label(action)
	end))
end

-- Menu buttons use small corners, like the reference.
local function squareCorners(b: GuiObject)
	local c = b:FindFirstChildOfClass("UICorner")
	if c then
		c.CornerRadius = UDim.new(0, 4)
	end
end

-- A gear icon from plain frames: a ring of teeth around a hub.
local function drawGear(parent: GuiObject)
	local holder: Frame = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		BackgroundTransparency = 1,
		ZIndex = 7,
		Parent = parent,
	})
	for i = 0, 3 do
		Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.26, 1),
			Rotation = i * 45,
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 7,
			Parent = holder,
		}, { Ui.corner(2) })
	end
	Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.74, 0.74),
		BackgroundColor3 = WHITE,
		ZIndex = 7,
		Parent = holder,
	}, { Ui.corner(100) })
	Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.34, 0.34),
		BackgroundColor3 = NAV,
		ZIndex = 8,
		Parent = holder,
	}, { Ui.corner(100) })
end

local function panelFrame(name: string, title: string, size: UDim2, anchor: Vector2, position: UDim2): Frame
	local frame: Frame = Ui.new("Frame", {
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = size,
		BackgroundColor3 = NAV_DARK,
		BackgroundTransparency = 0.04,
		Visible = false,
		Parent = root,
	}, { Ui.corner(6), Ui.stroke(NAV:Lerp(WHITE, 0.25), 2), Ui.new("UIScale", {}) })
	Ui.label(title, 27, BLACK, WHITE, {
		Position = UDim2.fromOffset(18, 10),
		Size = UDim2.new(1, -36, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	Ui.button("BACK", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(96, 34),
		TextSize = 18,
		Font = BLACK,
		BackgroundColor3 = RED,
		Parent = frame,
	}, function()
		Menu.back()
	end)
	panels[name] = frame
	return frame
end

-- Short tab labels, so six slots fit across the locker.
local TAB_NAMES = {
	hat = "HATS",
	hair = "HAIR",
	face = "FACE",
	stick = "STICK",
	outfit = "OUTFIT",
	colors = "COLOURS",
	finish = "SKIN",
	build = "BODY",
	back = "BACK",
	puck = "PUCK",
	goal = "GOAL SOUND",
	rink = "RINK",
}

local function tabRow(parent: Frame, kinds: { string }, store: { [string]: TextButton }, onPick: (string) -> (), y: number?)
	local row: Frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(18, y or 52),
		Size = UDim2.new(1, -36, 0, 32),
		BackgroundTransparency = 1,
		Parent = parent,
	}, { Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }) })
	for _, kind in kinds do
		store[kind] = Ui.button((TAB_NAMES :: any)[kind] or (Catalog.KindNames :: any)[kind] or "COLOURS", {
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			TextSize = 14,
			Font = BLACK,
			BackgroundColor3 = BLUE,
			Parent = row,
		}, function()
			onPick(kind)
		end)
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9), Parent = store[kind] })
	end
end

local function paintTabs(store: { [string]: TextButton }, active: string)
	for kind, button in store do
		button.TextColor3 = if kind == active then GOLD else WHITE
	end
end

local function grid(parent: Frame, top: number?): ScrollingFrame
	local y = top or 94
	return Ui.new("ScrollingFrame", {
		Position = UDim2.fromOffset(18, y),
		Size = UDim2.new(1, -36, 1, -(y + 14)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = parent,
	}, {
		Ui.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(120, 86),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

local function card(parent: Instance, order: number, title: string, sub: string, color: Color3, selected: boolean, swatch: Color3?, onClick: () -> ())
	local b = Ui.button("", {
		Size = UDim2.fromOffset(120, 86),
		BackgroundColor3 = color,
		LayoutOrder = order,
		Parent = parent,
	}, onClick)
	if selected then
		Ui.stroke(GOLD, 3).Parent = b
	end
	if swatch then
		Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 10),
			Size = UDim2.fromOffset(34, 34),
			BackgroundColor3 = swatch,
			Parent = b,
		}, { Ui.corner(17), Ui.stroke(WHITE, 2) })
	end
	Ui.label(title, 14, BLACK, WHITE, {
		Position = UDim2.fromOffset(4, if swatch then 48 else 10),
		Size = UDim2.new(1, -8, 0, if swatch then 18 else 40),
		TextWrapped = true,
		Parent = b,
	})
	if sub ~= "" then
		Ui.label(sub, 12, BLACK, if sub == "EQUIPPED" then GOLD else Color3.fromRGB(200, 214, 255), {
			Position = UDim2.fromOffset(4, if swatch then 66 else 56),
			Size = UDim2.new(1, -8, 0, 16),
			Parent = b,
		})
	end
end

local function clearGrid(g: ScrollingFrame)
	for _, child in g:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
end

local function currentLook(): any
	return if profile then profile.look else Catalog.DefaultLook
end

-- Locker cards look like the shop's: a picture of the item on a skater (sticks on their own) over
-- a backdrop in its rarity colour, the name under it, and a gold edge on what you're wearing.
local LOCKER_W, LOCKER_H, LOCKER_PIC = 124, 152, 116
local COMMON = { a = Color3.fromRGB(70, 88, 120), b = Color3.fromRGB(128, 150, 186) }
local SEASON = { a = Color3.fromRGB(150, 70, 190), b = Color3.fromRGB(232, 168, 36) }
local lockerPreviews: { [string]: ViewportFrame } = {}
local buildPreview: (item: Catalog.Item) -> ViewportFrame
local tierOf: (item: Catalog.Item) -> any

local function rarityOf(item: Catalog.Item): any
	if item.pass or item.reward == "firstgame" then
		return SEASON -- (Build 40: the Nova set wears the special frame too)
	elseif item.price <= 0 then
		return COMMON
	end
	return tierOf(item)
end

local function lockerCard(parent: Instance, order: number, item: Catalog.Item, equipped: boolean)
	local rarity = rarityOf(item)
	local b = Ui.button("", {
		Size = UDim2.fromOffset(LOCKER_W, LOCKER_H),
		BackgroundColor3 = BUTTON,
		LayoutOrder = order,
		ClipsDescendants = true,
		Parent = parent,
	}, function()
		callbacks.onEquip(item.kind, item.id)
	end)
	squareCorners(b)
	local pic: Frame = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 0, LOCKER_PIC),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Parent = b,
	}, { Ui.new("UIGradient", { Color = ColorSequence.new(rarity.b, rarity.a), Rotation = 90 }) })
	local vf = lockerPreviews[item.id]
	if not vf then
		vf = buildPreview(item)
		lockerPreviews[item.id] = vf
	end
	vf.Parent = pic
	if equipped then
		Ui.stroke(GOLD, 3).Parent = b
		local tag = Ui.label("EQUIPPED", 11, BLACK, WHITE, {
			Position = UDim2.fromOffset(5, 5),
			Size = UDim2.new(0, 0, 0, 18),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Color3.fromRGB(46, 170, 80),
			ZIndex = 3,
			Parent = pic,
		})
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), Parent = tag })
		Ui.corner(4).Parent = tag
	end
	Ui.label(string.upper(item.name), 13, BLACK, WHITE, {
		Position = UDim2.fromOffset(6, LOCKER_PIC + 4),
		Size = UDim2.new(1, -12, 0, LOCKER_H - LOCKER_PIC - 8),
		TextWrapped = true,
		Parent = b,
	})
end

local function redrawLocker()
	if not lockerGrid then
		return
	end
	-- Keep the cached pictures: lift them out before the old cards go.
	for _, vf in lockerPreviews do
		vf.Parent = nil
	end
	clearGrid(lockerGrid)
	paintTabs(lockerTabs, lockerKind)
	local layout = lockerGrid:FindFirstChildOfClass("UIGridLayout")
	if layout then
		layout.CellSize = if lockerKind == "colors" then UDim2.fromOffset(120, 86) else UDim2.fromOffset(LOCKER_W, LOCKER_H)
	end
	local look = currentLook()
	if lockerKind == "colors" then
		for i, color in Catalog.SkinTones do
			card(lockerGrid, i, `Skin {i}`, if look.skin == i then "EQUIPPED" else "", BLUE, look.skin == i, color, function()
				callbacks.onEquip("skin", i)
			end)
		end
		for i, color in Catalog.HairColors do
			card(lockerGrid, 100 + i, `Hair {i}`, if look.hairColor == i then "EQUIPPED" else "", BLUE, look.hairColor == i, color, function()
				callbacks.onEquip("hairColor", i)
			end)
		end
		return
	end
	local order = 0
	for _, item in Catalog.itemsOfKind(lockerKind) do
		local owned = profile and profile.owned[item.id]
		if owned then
			order += 1
			local equipped = (look :: any)[lockerKind] == item.id
			lockerCard(lockerGrid, order, item, equipped)
		end
	end
	local locked = 0
	for _, item in Catalog.itemsOfKind(lockerKind) do
		if Catalog.inShop(item) and not (profile and profile.owned[item.id]) then
			locked += 1
		end
	end
	if locked > 0 then
		card(lockerGrid, 999, `+{locked} more`, "IN THE SHOP", Color3.fromRGB(60, 70, 100), false, nil, function()
			shopKind = lockerKind
			shopJump = lockerKind
			Menu.open("Shop")
		end)
	end
end

-- Shop cards, like a sports-game item store: a big picture of the item itself (a 3D preview of
-- it on a skater's head, or the stick on its own) over a backdrop coloured by price tier, the
-- slot in the top corner, and the name and price under it. Clicking a card opens the item's
-- own page (your skater wearing it, the item, its price and BUY).
local CARD_W, CARD_H, PIC_H = 170, 224, 166
-- Five cards to a row (two rows a slot), each keeping this shape as the screen gets wider.
local SHOP_COLUMNS = 5
local CARD_ASPECT = CARD_W / CARD_H
-- Rarity colours, lowest to highest. A slot's shop items are ranked by price: the cheapest
-- 30% are green, then blue to 60%, purple to 80%, and the dearest gold.
local TIERS = {
	{ upTo = 0.3, a = Color3.fromRGB(46, 150, 72), b = Color3.fromRGB(112, 214, 120) },
	{ upTo = 0.6, a = Color3.fromRGB(44, 116, 214), b = Color3.fromRGB(108, 182, 250) },
	{ upTo = 0.8, a = Color3.fromRGB(132, 58, 196), b = Color3.fromRGB(206, 120, 240) },
	{ upTo = math.huge, a = Color3.fromRGB(214, 146, 24), b = Color3.fromRGB(252, 212, 84) },
}
local SLOT_TAG = { hat = "HAT", hair = "HAIR", face = "FACE", stick = "STICK", back = "BACK", goal = "GOAL SOUND", rink = "RINK" }
local previews: { [string]: ViewportFrame } = {}
local redrawShop: () -> ()
local shopCards: { [string]: { button: TextButton, owned: Frame } } = {}
local openShopItem: (id: string) -> ()

-- The shop prices of each slot, cheapest first (worked out once).
local shopPrices: { [string]: { number } } = {}
local function pricesOf(kind: string): { number }
	local list = shopPrices[kind]
	if not list then
		list = {}
		for _, other in Catalog.itemsOfKind(kind) do
			if Catalog.inShop(other) then
				table.insert(list, other.price)
			end
		end
		table.sort(list)
		shopPrices[kind] = list
	end
	return list
end

-- An item's rarity: its price's rank among the shop items of its slot. Items no longer sold
-- rank where their price would fall.
function tierOf(item: Catalog.Item)
	local list = pricesOf(item.kind)
	if #list == 0 then
		return TIERS[1]
	end
	local rank = 0
	for _, price in list do
		if price <= item.price then
			rank += 1
		end
	end
	local share = math.max(1, rank) / #list
	for _, t in TIERS do
		if share <= t.upTo + 1e-6 then
			return t
		end
	end
	return TIERS[#TIERS]
end

-- Props for items that aren't worn (pucks, goal sounds, rinks): small 3D models built from
-- parts, so each picture shows the thing itself rather than a skater.
local function prop(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end
local UP_CYL = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder's axis (x) turned upright

-- Fits the camera on everything in `world`, looking along `dir` (toward the model).
local function fitCamera(camera: Camera, world: Instance, dir: Vector3, pad: number?)
	local model = Instance.new("Model")
	for _, c in world:GetChildren() do
		if c ~= camera and not c:IsA("Model") then
			c.Parent = model
		end
	end
	model.Parent = world
	local cf, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local dist = radius / math.tan(math.rad(camera.FieldOfView / 2)) * (pad or 1.05)
	camera.CFrame = CFrame.lookAt(cf.Position - dir.Unit * dist, cf.Position)
end

local function puckProp(world: Instance, style: string?)
	local puck = prop(world, Vector3.new(0.55, 2, 2), UP_CYL, Color3.fromRGB(24, 24, 28), nil, Enum.PartType.Cylinder)
	Looks.dressPuck(puck, style, Color3.fromRGB(24, 24, 28))
	-- A little ice under it.
	prop(world, Vector3.new(0.12, 3.6, 3.6), CFrame.new(0, -0.34, 0) * UP_CYL, Color3.fromRGB(214, 236, 250), Enum.Material.Ice, Enum.PartType.Cylinder).Transparency = 0.2
end

-- A squashed sphere (a Ball part is always round; a sphere mesh can be any shape).
local function blob(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = prop(parent, size, cf, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Build 34: the shop rinks' icons: the same little rink in the theme's colours, on its ground,
-- with a few of the world's props round it (corner props sit on the corner diagonals).
type RinkLook = { ice: Color3, board: Color3, kick: Color3, ground: Color3?, groundMat: Enum.Material?, decor: (world: Instance, corners: { Vector3 }, hx: number, hz: number) -> () }
local RINK_LOOKS: { [string]: RinkLook } = {
	NeonArcade = {
		ice = Color3.fromRGB(34, 30, 58), board = Color3.fromRGB(28, 26, 46), kick = Color3.fromRGB(255, 60, 180),
		decor = function(world, _corners, hx, hz)
			for _, s in { -1, 1 } do
				for row = 1, 3 do
					prop(world, Vector3.new((hx - 1) * 2, 0.4, 0.6), CFrame.new(0, 0.3 + row * 0.45, s * (hz + 0.6 + row * 0.6)), if row % 2 == 0 then Color3.fromRGB(40, 170, 230) else Color3.fromRGB(230, 50, 160))
				end
				prop(world, Vector3.new((hx - 1) * 2, 0.15, 0.15), CFrame.new(0, 1.9, s * (hz + 2.6)), if s > 0 then Color3.fromRGB(255, 60, 180) else Color3.fromRGB(40, 220, 255), Enum.Material.Neon)
			end
			for k = 0, 23 do
				local a = k / 24 * math.pi * 2
				prop(world, Vector3.new(0.18, 0.18, 0.5), CFrame.new(math.cos(a) * 2.2, 3, math.sin(a) * 2.2) * CFrame.Angles(0, -a, 0), if k % 2 == 0 then Color3.fromRGB(255, 60, 180) else Color3.fromRGB(40, 220, 255), Enum.Material.Neon)
			end
		end,
	},
	CandyLand = {
		ice = Color3.fromRGB(255, 232, 244), board = Color3.fromRGB(255, 250, 252), kick = Color3.fromRGB(255, 120, 180),
		ground = Color3.fromRGB(150, 228, 180),
		decor = function(world, corners)
			local colors = { Color3.fromRGB(255, 90, 150), Color3.fromRGB(120, 200, 255), Color3.fromRGB(255, 210, 70), Color3.fromRGB(190, 130, 255) }
			for i, at in corners do
				prop(world, Vector3.new(0.12, 1.8, 0.12), CFrame.new(at + Vector3.new(0, 0.9, 0)), Color3.fromRGB(255, 255, 255))
				prop(world, Vector3.new(0.2, 1.3, 1.3), CFrame.new(at + Vector3.new(0, 2.1, 0)) * CFrame.Angles(0, math.pi / 2, 0), colors[i], nil, Enum.PartType.Cylinder)
				prop(world, Vector3.new(0.22, 0.6, 0.6), CFrame.new(at + Vector3.new(0, 2.1, 0)) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(255, 255, 255), nil, Enum.PartType.Cylinder)
			end
			for i, at in { Vector3.new(-3, 0, 4.6), Vector3.new(2.5, 0, -4.7), Vector3.new(4.5, 0, 4.4) } do
				blob(world, Vector3.new(1.1, 0.9, 1.1), CFrame.new(at), colors[i + 1])
			end
		end,
	},
	TropicalBeach = {
		ice = Color3.fromRGB(214, 240, 248), board = Color3.fromRGB(255, 246, 226), kick = Color3.fromRGB(30, 170, 170),
		ground = Color3.fromRGB(238, 216, 164), groundMat = Enum.Material.Sand,
		decor = function(world, corners, hx, hz)
			prop(world, Vector3.new(hx * 2 + 6, 0.2, 1.6), CFrame.new(0, -0.12, hz + 2.6), Color3.fromRGB(40, 160, 210), Enum.Material.Glass)
			for _, at in corners do
				prop(world, Vector3.new(0.22, 2.6, 0.22), CFrame.new(at + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, 0, 0.15), Color3.fromRGB(150, 108, 66))
				for k = 0, 4 do
					local a = k / 5 * math.pi * 2
					prop(world, Vector3.new(0.3, 0.06, 1.1), CFrame.new(at + Vector3.new(-0.2 + math.cos(a) * 0.45, 2.5, math.sin(a) * 0.45)) * CFrame.Angles(0, -a + math.pi / 2, 0) * CFrame.Angles(-0.35, 0, 0), Color3.fromRGB(54, 168, 82))
				end
			end
		end,
	},
	Volcano = {
		ice = Color3.fromRGB(214, 206, 208), board = Color3.fromRGB(56, 48, 50), kick = Color3.fromRGB(255, 96, 20),
		ground = Color3.fromRGB(52, 44, 44), groundMat = Enum.Material.Basalt,
		decor = function(world, corners, hx)
			for i = 0, 3 do
				local d = 4.4 * (1 - i * 0.2)
				prop(world, Vector3.new(0.7, d, d), CFrame.new(-hx - 2.8, 0.35 + i * 0.7, -2) * UP_CYL, Color3.fromRGB(70, 58, 56), Enum.Material.Basalt, Enum.PartType.Cylinder)
			end
			prop(world, Vector3.new(0.2, 1.2, 1.2), CFrame.new(-hx - 2.8, 2.85, -2) * UP_CYL, Color3.fromRGB(255, 92, 20), Enum.Material.Neon, Enum.PartType.Cylinder)
			for _, at in corners do
				prop(world, Vector3.new(0.3, 0.9, 0.3), CFrame.new(at + Vector3.new(0, 0.45, 0)), Color3.fromRGB(70, 60, 58))
				prop(world, Vector3.new(0.4, 0.4, 0.4), CFrame.new(at + Vector3.new(0, 1.05, 0)), Color3.fromRGB(255, 120, 30), Enum.Material.Neon, Enum.PartType.Ball)
			end
			prop(world, Vector3.new(0.5, 0.06, 7), CFrame.new(hx + 2, -0.07, 0), Color3.fromRGB(255, 92, 20), Enum.Material.Neon)
		end,
	},
	MoonBase = {
		ice = Color3.fromRGB(222, 228, 240), board = Color3.fromRGB(214, 218, 226), kick = Color3.fromRGB(60, 66, 82),
		ground = Color3.fromRGB(158, 158, 166), groundMat = Enum.Material.Sand,
		decor = function(world, corners, hx, hz)
			local dome = prop(world, Vector3.new(2.6, 2.6, 2.6), CFrame.new(-hx - 2.2, 0, -1.5), Color3.fromRGB(150, 210, 255), Enum.Material.Glass, Enum.PartType.Ball)
			dome.Transparency = 0.35
			prop(world, Vector3.new(0.8, 0.8, 0.8), CFrame.new(-hx - 2.2, 0.3, -1.5), Color3.fromRGB(140, 255, 200), Enum.Material.Neon, Enum.PartType.Ball)
			-- A little rocket on the far end.
			prop(world, Vector3.new(2.2, 0.7, 0.7), CFrame.new(hx + 2, 1.1, 1.5) * UP_CYL, Color3.fromRGB(240, 240, 246), nil, Enum.PartType.Cylinder)
			blob(world, Vector3.new(0.7, 1.0, 0.7), CFrame.new(hx + 2, 2.5, 1.5), Color3.fromRGB(230, 60, 60))
			for _, at in { Vector3.new(-2, 0, hz + 1.8), Vector3.new(3.5, 0, -hz - 1.6) } do
				prop(world, Vector3.new(0.06, 1.4, 1.4), CFrame.new(at + Vector3.new(0, -0.06, 0)) * UP_CYL, Color3.fromRGB(116, 116, 124), nil, Enum.PartType.Cylinder)
			end
			for _, at in corners do
				prop(world, Vector3.new(0.15, 2.2, 0.15), CFrame.new(at + Vector3.new(0, 1.1, 0)), Color3.fromRGB(120, 128, 146), Enum.Material.Metal)
				prop(world, Vector3.new(0.6, 0.3, 0.1), CFrame.lookAt(at + Vector3.new(0, 2.25, 0), Vector3.new(0, 0, 0)), Color3.fromRGB(235, 245, 255), Enum.Material.Neon)
			end
		end,
	},
}

local function goalProp(world: Instance, style: string?)
	if style == "AirHorn" then
		-- A red air-horn can with a white horn flaring up, and sound bars fanning out.
		prop(world, Vector3.new(2.2, 1.2, 1.2), CFrame.new(0, 1.1, 0) * UP_CYL, Color3.fromRGB(220, 50, 46), nil, Enum.PartType.Cylinder)
		prop(world, Vector3.new(0.35, 1.24, 1.24), CFrame.new(0, 1.5, 0) * UP_CYL, Color3.fromRGB(250, 250, 250), nil, Enum.PartType.Cylinder)
		prop(world, Vector3.new(0.3, 0.9, 0.9), CFrame.new(0, 2.35, 0) * UP_CYL, Color3.fromRGB(40, 40, 46), nil, Enum.PartType.Cylinder)
		for i, r in { 0.42, 0.6, 0.8, 1.0 } do
			prop(world, Vector3.new(0.36, r, r), CFrame.new(0.28 * i, 2.55 + 0.32 * i, 0) * CFrame.Angles(0, 0, math.rad(-35)) * UP_CYL, Color3.fromRGB(245, 245, 250), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		end
		for i = -1, 1 do
			local a = math.rad(-35 + i * 28)
			prop(world, Vector3.new(0.16, 0.9, 0.16), CFrame.new(2.6 + math.cos(a) * 0.4, 4.0 + math.sin(a) * 0.4, 0) * CFrame.Angles(0, 0, a - math.pi / 2), Color3.fromRGB(255, 220, 60), Enum.Material.Neon)
		end
	elseif style == "Fireworks" then
		-- Three rockets on a launch board and a starburst over them.
		prop(world, Vector3.new(3.2, 0.3, 1.4), CFrame.new(0, 0.15, 0), Color3.fromRGB(70, 50, 40), Enum.Material.Wood)
		local colors = { Color3.fromRGB(255, 80, 120), Color3.fromRGB(80, 220, 255), Color3.fromRGB(255, 210, 70) }
		for i = 1, 3 do
			local x = (i - 2) * 1.0
			local tilt = (i - 2) * 0.18
			local base = CFrame.new(x, 0.3, 0) * CFrame.Angles(0, 0, -tilt)
			prop(world, Vector3.new(1.8, 0.5, 0.5), base * CFrame.new(0, 0.9, 0) * UP_CYL, colors[i], nil, Enum.PartType.Cylinder)
			prop(world, Vector3.new(0.55, 0.55, 0.55), base * CFrame.new(0, 1.9, 0), Color3.fromRGB(245, 245, 245), nil, Enum.PartType.Ball)
		end
		local burst = Vector3.new(0, 5.2, 0)
		for k = 1, 14 do
			local a = k / 14 * math.pi * 2
			local d = Vector3.new(math.cos(a), math.sin(a), 0)
			prop(world, Vector3.new(0.3, 0.3, 0.3), CFrame.new(burst + d * 1.6), colors[k % 3 + 1], Enum.Material.Neon, Enum.PartType.Ball)
			prop(world, Vector3.new(0.12, 0.8, 0.12), CFrame.lookAt(burst + d * 0.9, burst + d * 2) * CFrame.Angles(math.pi / 2, 0, 0), Color3.fromRGB(255, 240, 200), Enum.Material.Neon)
		end
	elseif style == "RubberDucky" then
		-- Build 34: a yellow rubber duck with an orange beak, and three quack bubbles.
		local yellow = Color3.fromRGB(255, 214, 40)
		blob(world, Vector3.new(2.8, 1.8, 2.0), CFrame.new(0, 0.9, 0), yellow)
		blob(world, Vector3.new(1.0, 0.8, 1.0), CFrame.new(-1.3, 1.5, 0), yellow)
		prop(world, Vector3.new(1.6, 1.6, 1.6), CFrame.new(0.8, 2.3, 0), yellow, nil, Enum.PartType.Ball)
		prop(world, Vector3.new(0.9, 0.3, 0.7), CFrame.new(1.75, 2.15, 0), Color3.fromRGB(255, 130, 30))
		for _, z in { -0.45, 0.45 } do
			prop(world, Vector3.new(0.26, 0.26, 0.26), CFrame.new(1.35, 2.55, z), Color3.fromRGB(20, 20, 24), nil, Enum.PartType.Ball)
		end
		for i, r in { 0.4, 0.55, 0.7 } do
			prop(world, Vector3.new(r, r, r), CFrame.new(1.9 + i * 0.55, 2.8 + i * 0.5, 0), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, Enum.PartType.Ball)
		end
	elseif style == "BillyGoat" then
		-- Build 34: a goat's head with curly horns and a little beard.
		local fur = Color3.fromRGB(240, 236, 226)
		blob(world, Vector3.new(1.8, 2.0, 1.6), CFrame.new(0, 2, 0), fur)
		blob(world, Vector3.new(1.2, 1.1, 1.1), CFrame.new(0.9, 1.4, 0), fur)
		prop(world, Vector3.new(0.3, 0.3, 0.3), CFrame.new(1.45, 1.55, 0), Color3.fromRGB(240, 140, 150), nil, Enum.PartType.Ball)
		blob(world, Vector3.new(0.4, 0.9, 0.4), CFrame.new(0.6, 0.6, 0), fur:Lerp(Color3.fromRGB(150, 140, 120), 0.4))
		for _, z in { -0.55, 0.55 } do
			prop(world, Vector3.new(0.3, 0.3, 0.3), CFrame.new(0.65, 2.3, z), Color3.fromRGB(30, 26, 20), nil, Enum.PartType.Ball)
			prop(world, Vector3.new(0.5, 0.25, 1.1), CFrame.new(-0.1, 2.4, z * 2.1) * CFrame.Angles(math.sign(z) * 0.5, 0, 0), fur)
			for k = 0, 4 do
				local a = k / 4 * math.pi * 1.1
				prop(world, Vector3.new(0.34, 0.34, 0.34) * (1 - k * 0.12), CFrame.new(-0.2 - math.sin(a) * 0.7, 2.9 + math.cos(a) * 0.6 - k * 0.05, z * (1 + k * 0.12)), Color3.fromRGB(150, 130, 100), nil, Enum.PartType.Ball)
			end
		end
	elseif style == "PartyPopper" then
		-- Build 35: "Guitar Shred" (the saved style stays PartyPopper): a red electric guitar,
		-- tilted like it is mid-solo, with sound bolts flying off the headstock.
		local f = CFrame.new(-0.3, 1.5, 0) * CFrame.Angles(0, 0, math.rad(-35))
		local red, black = Color3.fromRGB(220, 36, 48), Color3.fromRGB(26, 26, 30)
		blob(world, Vector3.new(2.3, 1.8, 0.5), f * CFrame.new(0, -0.55, 0), red)
		blob(world, Vector3.new(1.7, 1.3, 0.5), f * CFrame.new(0, 0.45, 0), red)
		prop(world, Vector3.new(1.0, 0.9, 0.08), f * CFrame.new(0.3, -0.35, 0.27), Color3.fromRGB(245, 245, 245))
		for _, y in { -0.75, -0.2 } do
			prop(world, Vector3.new(0.75, 0.2, 0.1), f * CFrame.new(0, y, 0.3), black)
		end
		prop(world, Vector3.new(0.34, 2.8, 0.22), f * CFrame.new(0, 2.15, 0.08), Color3.fromRGB(150, 96, 52), Enum.Material.Wood)
		prop(world, Vector3.new(0.62, 0.95, 0.24), f * CFrame.new(0, 3.95, 0.08), black)
		for i = 0, 2 do
			prop(world, Vector3.new(0.14, 0.14, 0.3), f * CFrame.new(0.38, 3.7 + i * 0.25, 0.08), Color3.fromRGB(220, 220, 228), Enum.Material.Metal)
		end
		local head = (f * CFrame.new(0, 4.1, 0)).Position
		for i = -1, 1 do
			local a = math.rad(15 + i * 30)
			prop(world, Vector3.new(0.16, 0.9, 0.16), CFrame.new(head + Vector3.new(math.cos(a) * 1.0, math.sin(a) * 1.0, 0)) * CFrame.Angles(0, 0, a - math.pi / 2), Color3.fromRGB(255, 220, 60), Enum.Material.Neon)
		end
	elseif style == "VikingHorn" then
		-- Build 34: a curved ivory war horn with gold bands.
		local prev: Vector3? = nil
		for k = 0, 9 do
			local a = k / 9 * math.pi * 0.9
			local p = Vector3.new(-math.cos(a) * 1.8, 0.6 + math.sin(a) * 1.8, 0)
			local r = 0.35 + k * 0.1
			local color = if k % 3 == 1 then Color3.fromRGB(230, 180, 60) else Color3.fromRGB(244, 232, 204)
			local mat = if k % 3 == 1 then Enum.Material.Metal else Enum.Material.SmoothPlastic
			prop(world, Vector3.new(r, r, r), CFrame.new(p), color, mat, Enum.PartType.Ball)
			if prev then
				local mid = (prev + p) / 2
				prop(world, Vector3.new((p - prev).Magnitude, r * 0.95, r * 0.95), CFrame.lookAt(mid, p) * CFrame.Angles(0, math.pi / 2, 0), color, mat, Enum.PartType.Cylinder)
			end
			prev = p
		end
		prop(world, Vector3.new(0.3, 1.4, 1.4), CFrame.new(1.75, 0.95, 0) * CFrame.Angles(0, 0, math.rad(80)), Color3.fromRGB(230, 180, 60), Enum.Material.Metal, Enum.PartType.Cylinder)
	elseif style == "ChooChoo" then
		-- Build 34: a little red steam train with a puff of smoke.
		local red, black = Color3.fromRGB(214, 40, 44), Color3.fromRGB(30, 30, 34)
		prop(world, Vector3.new(3, 1.4, 1.4), CFrame.new(0.4, 1.3, 0), red, nil, Enum.PartType.Cylinder)
		prop(world, Vector3.new(1.6, 2.2, 1.7), CFrame.new(-1.6, 1.7, 0), Color3.fromRGB(40, 80, 170))
		prop(world, Vector3.new(1.9, 0.3, 2.0), CFrame.new(-1.6, 2.9, 0), black)
		prop(world, Vector3.new(0.6, 0.8, 0.8), CFrame.new(-1.6, 2.1, 0), Color3.fromRGB(255, 230, 140), Enum.Material.Neon)
		prop(world, Vector3.new(0.9, 0.6, 0.6), CFrame.new(1.2, 2.3, 0) * UP_CYL, black, nil, Enum.PartType.Cylinder)
		prop(world, Vector3.new(0.3, 1.0, 1.0), CFrame.new(1.95, 1.3, 0), Color3.fromRGB(230, 180, 60), Enum.Material.Metal, Enum.PartType.Cylinder)
		for _, x in { -1.6, -0.4, 0.8 } do
			for _, z in { -0.75, 0.75 } do
				prop(world, Vector3.new(0.2, 0.9, 0.9), CFrame.new(x, 0.45, z) * CFrame.Angles(0, math.pi / 2, 0), black, nil, Enum.PartType.Cylinder)
			end
		end
		for i, r in { 0.7, 0.9, 1.1 } do
			prop(world, Vector3.new(r, r, r), CFrame.new(1.2 + i * 0.35, 2.7 + i * 0.6, 0), Color3.fromRGB(235, 235, 240), nil, Enum.PartType.Ball)
		end
	else
		-- The arena goal light: a red dome lamp on a black base.
		prop(world, Vector3.new(0.6, 2.4, 2.4), CFrame.new(0, 0.3, 0) * UP_CYL, Color3.fromRGB(30, 30, 36), nil, Enum.PartType.Cylinder)
		prop(world, Vector3.new(0.5, 1.9, 1.9), CFrame.new(0, 0.8, 0) * UP_CYL, Color3.fromRGB(210, 210, 216), Enum.Material.Metal, Enum.PartType.Cylinder)
		prop(world, Vector3.new(1.9, 2.4, 1.9), CFrame.new(0, 1.4, 0), Color3.fromRGB(255, 40, 40), Enum.Material.Neon, Enum.PartType.Ball)
	end
end

local function rinkProp(world: Instance, style: string?)
	local lake = style == "FrozenLake"
	local look = RINK_LOOKS[style or ""]
	local ice = if look then look.ice elseif lake then Color3.fromRGB(150, 196, 224) else Color3.fromRGB(226, 238, 248)
	local board = if look then look.board elseif lake then Color3.fromRGB(236, 228, 214) else Color3.fromRGB(245, 245, 248)
	local kick = if look then look.kick elseif lake then Color3.fromRGB(122, 86, 58) else Color3.fromRGB(40, 72, 160)
	-- Every rink is the game's one rink (Config.Arena), scaled down: same length, width and
	-- rounded corners whatever the theme, so only the dressing differs between rink icons.
	local A = Config.Arena
	local k = 6 / (A.Length / 2)
	local hx, hz, cr = 6, A.Width / 2 * k, A.CornerRadius * k
	-- A rounded box of ice (two crossed slabs and four corner discs).
	local function roundSlab(rx: number, rz: number, r: number, y: number, h: number, color: Color3, material: Enum.Material?)
		local ix, iz = rx - r, rz - r
		prop(world, Vector3.new(rx * 2, h, iz * 2), CFrame.new(0, y, 0), color, material)
		prop(world, Vector3.new(ix * 2, h, rz * 2), CFrame.new(0, y, 0), color, material)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				prop(world, Vector3.new(h, r * 2, r * 2), CFrame.new(sx * ix, y, sz * iz) * UP_CYL, color, material, Enum.PartType.Cylinder)
			end
		end
	end
	if lake then
		-- Lake ice round the rink following its rounded shape, snowbanks on the shore, pines and
		-- lamp posts.
		local m = 1.1
		local lx, lz, lr = hx + m, hz + m, cr + m
		roundSlab(lx, lz, lr, -0.15, 0.2, Color3.fromRGB(120, 168, 206), Enum.Material.Ice)
		local ix, iz = lx - lr, lz - lr
		local function bank(x: number, z: number, nx: number, nz: number)
			local at = Vector3.new(x + nx * 0.3, -0.05, z + nz * 0.3)
			prop(world, Vector3.new(1.8, 0.8, 1.2), CFrame.lookAt(at, at + Vector3.new(nx, 0, nz)), Color3.fromRGB(246, 250, 255), Enum.Material.Snow, Enum.PartType.Ball)
		end
		for _, s in { -1, 1 } do
			for x = -ix, ix + 0.01, ix / 3 do
				bank(x, s * lz, 0, s)
			end
			for z = -iz, iz + 0.01, math.max(iz, 0.5) do
				bank(s * lx, z, s, 0)
			end
		end
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				for i = 1, 2 do
					local a = (math.pi / 2) * i / 3
					local nx, nz = sx * math.cos(a), sz * math.sin(a)
					bank(sx * ix + nx * lr, sz * iz + nz * lr, nx, nz)
				end
			end
		end
		for _, at in { Vector3.new(-8.6, 0, -4.6), Vector3.new(8.8, 0, -3.9), Vector3.new(-8.9, 0, 4.1), Vector3.new(8.6, 0, 4.5) } do
			prop(world, Vector3.new(0.3, 1, 0.3), CFrame.new(at + Vector3.new(0, 0.5, 0)), Color3.fromRGB(90, 60, 40), Enum.Material.Wood)
			for j, r in { 1.8, 1.35, 0.9 } do
				prop(world, Vector3.new(r, 1.0, r), CFrame.new(at + Vector3.new(0, 0.6 + j * 0.7, 0)), Color3.fromRGB(46, 110, 70), nil, Enum.PartType.Ball)
			end
		end
		local d = 0.7071 * (lr + 0.4)
		for _, s in { -1, 1 } do
			local at = Vector3.new(s * (ix + d), 0, s * (iz + d))
			prop(world, Vector3.new(0.15, 3.2, 0.15), CFrame.new(at + Vector3.new(0, 1.6, 0)), Color3.fromRGB(44, 40, 38), Enum.Material.Metal)
			prop(world, Vector3.new(0.45, 0.45, 0.45), CFrame.new(at + Vector3.new(0, 3.3, 0)), Color3.fromRGB(255, 214, 150), Enum.Material.Neon, Enum.PartType.Ball)
		end
	elseif look then
		-- Build 34: a shop rink on its own ground, with its props.
		if look.ground then
			local m = 2.6
			roundSlab(hx + m, hz + m, cr + m, -0.15, 0.2, look.ground, look.groundMat)
		end
		local corners = {}
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local d = 0.7071 * (cr + 1)
				table.insert(corners, Vector3.new(sx * (hx - cr + d), 0, sz * (hz - cr + d)))
			end
		end
		look.decor(world, corners, hx, hz)
	else
		-- Arena: stands in team colours behind the boards.
		for _, s in { -1, 1 } do
			for row = 1, 3 do
				prop(world, Vector3.new((hx - cr) * 2 + 1, 0.4, 0.6), CFrame.new(0, 0.3 + row * 0.45, s * (hz + 0.6 + row * 0.6)), if row % 2 == 0 then Color3.fromRGB(44, 82, 170) else Color3.fromRGB(196, 50, 56))
			end
		end
	end
	roundSlab(hx, hz, cr, 0, 0.1, ice, Enum.Material.Ice)
	-- Boards with the kick plate: straight runs, then the rounded corners in short panels.
	local ix, iz = hx - cr, hz - cr
	local function panel(cf: CFrame, width: number)
		prop(world, Vector3.new(width, 0.55, 0.15), cf * CFrame.new(0, 0.3, 0), board)
		prop(world, Vector3.new(width + 0.02, 0.14, 0.17), cf * CFrame.new(0, 0.1, 0), kick)
	end
	for _, s in { -1, 1 } do
		panel(CFrame.new(0, 0, s * hz), ix * 2)
		panel(CFrame.new(s * hx, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), iz * 2)
	end
	local segs = 6
	local w = 2 * cr * math.tan(math.pi / 4 / segs) + 0.04
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			for i = 0, segs - 1 do
				local a = (math.pi / 2) * (i + 0.5) / segs
				local nx, nz = sx * math.cos(a), sz * math.sin(a)
				local at = Vector3.new(sx * ix + nx * cr, 0, sz * iz + nz * cr)
				panel(CFrame.lookAt(at, at + Vector3.new(nx, 0, nz)), w)
			end
		end
	end
	for _, s in { -1, 1 } do
		-- Blue line and a little net.
		prop(world, Vector3.new(0.12, 0.02, hz * 2), CFrame.new(s * 2, 0.06, 0), Color3.fromRGB(60, 110, 200))
		prop(world, Vector3.new(0.5, 0.45, 1.0), CFrame.new(s * (hx - 0.9), 0.28, 0), Color3.fromRGB(220, 40, 40)).Transparency = 0.15
	end
	prop(world, Vector3.new(0.12, 0.02, hz * 2), CFrame.new(0, 0.06, 0), Color3.fromRGB(214, 60, 60))
	prop(world, Vector3.new(0.02, 1.6, 1.6), CFrame.new(0, 0.06, 0) * UP_CYL, Color3.fromRGB(60, 110, 200), nil, Enum.PartType.Cylinder)
	prop(world, Vector3.new(0.03, 1.4, 1.4), CFrame.new(0, 0.065, 0) * UP_CYL, ice, Enum.Material.Ice, Enum.PartType.Cylinder)
end

-- A 3D picture of one item: a default skater wearing it, framed on the head (hats, hair,
-- faces), the whole skater (outfits, skins, bodies; back bling seen from behind), the stick
-- alone, or the thing itself for pucks, goal sounds and rinks.
-- Build 35: a real picture of each rink for its shop card (Studio captures of ArenaBuilder's
-- build, assets/rinks/rink_<style>.png, uploaded as Images). Keyed on the rink style; the
-- Match Rink has no style and shows the Arena.
-- Build 37: all retaken from high over the blue net looking at the red one, nearly straight down,
-- so the whole rink and its surroundings show (assets/rinks/rink37_<style>.png; the roofed
-- Arena and Neon Arcade with the roof left off).
-- Build 38: retaken lower and less face-down, from (-210, 132, 0) looking at (22, 0, 0)
-- (assets/rinks/rink38_<style>.png; the roofed rinks with the near end wall off too).
local RINK_PHOTOS: { [string]: string } = {
	Arena = "rbxassetid://104371536766851",
	FrozenLake = "rbxassetid://73097913428748", -- Build 39: retaken by day with the fans in (rink39_FrozenLake.png)
	NeonArcade = "rbxassetid://133246632512398",
	CandyLand = "rbxassetid://129086397908564",
	TropicalBeach = "rbxassetid://110946145196587",
	Volcano = "rbxassetid://140507252741177",
	MoonBase = "rbxassetid://77319121486939",
}
-- Build 36: goal sounds show a Blender-rendered icon (assets/goals/goal_<id>.png, uploaded as
-- Images), keyed on the item id. A goal without one falls back to the toy horn model.
local GOAL_ICONS: { [string]: string } = {
	arenahorn = "rbxassetid://122378310583025",
	s1_airhorn = "rbxassetid://112816473327980",
	s1_fireworks = "rbxassetid://114183409179206",
	duckyhorn = "rbxassetid://98439302302959",
	goathorn = "rbxassetid://121148016499887",
	partyhorn = "rbxassetid://127336623044804",
	vikinghorn = "rbxassetid://78169395838451",
	trainhorn = "rbxassetid://72309453913607",
}

function buildPreview(item: Catalog.Item): ViewportFrame
	local vf: ViewportFrame = Ui.new("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 150, 165),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.6, -1, 0.7),
	})
	-- Build 35: rinks show a real picture of the rink (captured in Studio), not the toy model.
	local photo = if item.kind == "rink" then RINK_PHOTOS[item.style or "Arena"] else nil
	if photo then
		Ui.new("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = photo,
			ScaleType = Enum.ScaleType.Crop,
			Parent = vf,
		})
		return vf
	end
	local icon = if item.kind == "goal" then GOAL_ICONS[item.id] else nil
	if icon then
		Ui.new("ImageLabel", {
			Size = UDim2.fromScale(0.9, 0.9),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = icon,
			ScaleType = Enum.ScaleType.Fit,
			Parent = vf,
		})
		return vf
	end
	local world = Instance.new("WorldModel")
	world.Parent = vf
	if item.kind == "puck" or item.kind == "goal" or item.kind == "rink" then
		local camera = Instance.new("Camera")
		camera.FieldOfView = 30
		camera.Parent = vf
		vf.CurrentCamera = camera
		if item.kind == "puck" then
			puckProp(world, item.style)
			fitCamera(camera, world, Vector3.new(-0.45, -0.75, 1), 1.0)
		elseif item.kind == "goal" then
			goalProp(world, item.style)
			fitCamera(camera, world, Vector3.new(-0.35, -0.25, 1), 1.0)
		else
			rinkProp(world, item.style)
			fitCamera(camera, world, Vector3.new(-0.3, -0.75, 1), 0.92)
		end
		return vf
	end
	local look = table.clone(Catalog.DefaultLook) :: any
	if item.kind == "hair" or item.kind == "face" then
		look.hat = "nohat"
	end
	look[item.kind] = item.id
	-- Back bling sits on the red home kit, so white pieces (the snow pal, the resurfacer, the
	-- mini net) stand out instead of vanishing into the white away jersey.
	local rig = Looks.build(world, look, if item.kind == "back" then 2 else 1, 1)
	-- Back bling is the point of the picture: the skater turned round, three-quarter from behind.
	pcall(Looks.pose, rig, if item.kind == "back" then CFrame.Angles(0, math.pi - 0.55, 0) else CFrame.new(), -1)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = vf
	vf.CurrentCamera = camera
	-- Hands and the team ring never show; the stick only on stick pictures (on the others the
	-- gloves and shaft would cover the chin, and the item is the point).
	for _, p in { rig.gloveA, rig.gloveB, rig.cuffA, rig.cuffB } do
		p.Transparency = 1
	end
	for _, p in rig.ring do
		p.Transparency = 1
	end
	if item.kind ~= "stick" then
		for _, d in rig.stickModel:GetDescendants() do
			if d:IsA("BasePart") then
				d.Transparency = 1
			end
		end
	end
	if item.kind == "stick" then
		-- Only the stick shows; the camera fits its bounding box, seen from the front and above.
		for _, p in rig.body do
			p.Transparency = 1
		end
		local cf, size = rig.stickModel:GetBoundingBox()
		local reach = math.max(size.X, size.Y, size.Z)
		local centre = cf.Position
		camera.CFrame = CFrame.lookAt(centre + Vector3.new(reach * 0.55, reach * 1.1, -reach * 1.6), centre)
	elseif item.kind == "outfit" or item.kind == "finish" or item.kind == "build" or item.kind == "back" then
		-- The whole skater, head to ice (a bit further out for the bigger body and the wings).
		local at = Vector3.new(0, if item.kind == "back" then 3.6 else 3.2, 0)
		local k = if item.kind == "build" or item.kind == "back" then 1.15 else 1
		camera.CFrame = CFrame.lookAt(at + Vector3.new(7.5, 4.0, -17) * k, at)
	else
		local y = Looks.HEAD_Y + (if item.kind == "hat" then 1.1 elseif item.kind == "hair" then 0.55 else 0)
		local dist = if item.kind == "face" then 10 else 14.5
		local at = Vector3.new(0, y, 0)
		camera.CFrame = CFrame.lookAt(at + Vector3.new(dist * 0.42, dist * 0.18, -dist), at)
	end
	return vf
end

-- The card pictures are built once and kept.
local function itemPreview(item: Catalog.Item): ViewportFrame
	local cached = previews[item.id]
	if not cached then
		cached = buildPreview(item)
		previews[item.id] = cached
	end
	return cached
end

local function coinIcon(parent: Instance, size: number, position: UDim2): Frame
	return Ui.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = position,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = GOLD,
		Parent = parent,
	}, { Ui.corner(size), Ui.stroke(Color3.fromRGB(214, 150, 24), math.max(2, size // 8)) })
end

local function shopCard(parent: Instance, order: number, item: Catalog.Item)
	local tier = tierOf(item)
	local b = Ui.button("", {
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundColor3 = BUTTON,
		LayoutOrder = order,
		ClipsDescendants = true,
		Parent = parent,
	}, function()
		openShopItem(item.id)
	end)
	squareCorners(b)
	local pic: Frame = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 1, -(CARD_H - PIC_H)),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Parent = b,
	}, {
		Ui.new("UIGradient", { Color = ColorSequence.new(tier.b, tier.a), Rotation = 90 }),
	})
	itemPreview(item).Parent = pic
	-- Slot tag, top left.
	local tag = Ui.label(SLOT_TAG[item.kind] or "", 12, BLACK, WHITE, {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(0, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.62,
		ZIndex = 3,
		Parent = pic,
	})
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = tag })
	Ui.corner(4).Parent = tag
	-- Owned tick, top right.
	local owned: Frame = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(62, 20),
		BackgroundColor3 = Color3.fromRGB(46, 170, 80),
		ZIndex = 3,
		Visible = false,
		Parent = pic,
	}, { Ui.corner(4) })
	Ui.label("OWNED", 12, BLACK, WHITE, { Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = owned })
	-- Name and price under the picture.
	Ui.label(string.upper(item.name), 18, BLACK, WHITE, {
		Position = UDim2.new(0, 10, 1, -(CARD_H - PIC_H) + 7),
		Size = UDim2.new(1, -16, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = b,
	})
	coinIcon(b, 15, UDim2.new(0, 10, 1, -(CARD_H - PIC_H) + 41))
	Ui.label(tostring(item.price), 17, Ui.Theme.BoldFont, WHITE, {
		Position = UDim2.new(0, 31, 1, -(CARD_H - PIC_H) + 30),
		Size = UDim2.new(1, -40, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = b,
	})
	shopCards[item.id] = { button = b, owned = owned }
end

local shopSections: { [string]: { frame: Frame, cards: Frame } } = {}
local shopNav: { [string]: { button: TextButton, marker: Frame } } = {}
local shopCoins: TextLabel? = nil

-- The item page (opened from a card).
local itemPage: Frame? = nil
local itemPageId: string? = nil
local itemWorld: WorldModel
local itemCamera: Camera
local itemRig: any = nil
local itemSpin = 0
local itemSpinConn: RBXScriptConnection? = nil
-- Click and hold on the skater and swipe to turn it (itemYaw); it sways gently until touched.
local itemYaw = 0
local itemDragX: number? = nil
local itemTouched = false
local itemProduct: Frame
local itemName: TextLabel
local itemSlot: TextLabel
local itemPrice: TextLabel
local itemBuy: TextButton
local itemSound: TextButton? = nil -- Build 34: PLAY SOUND on a goal sound's page
local itemRobux: TextButton? = nil -- Build 36: the Robux price next to BUY
local itemStatus: TextLabel

local function refreshShopItem()
	local id = itemPageId
	local item = id and Catalog.ById[id]
	if not item or not itemPage then
		return
	end
	local owned = profile ~= nil and profile.owned[item.id] == true
	local equipped = owned and profile.look[item.kind] == item.id
	local coins = if profile then profile.coins else 0
	local affordable = coins >= item.price
	itemPrice.Text = tostring(item.price)
	-- Build 36: the Robux price next to BUY, worked out from the coin price (SOON until buying
	-- with Robux is live).
	if itemRobux then
		local robux = math.max(1, math.ceil(item.price / Config.CoinsPerRobux))
		itemRobux.Visible = not owned and item.price > 0
		itemRobux.Text = `{utf8.char(0xE002)} {robux}` .. (if Config.RobuxBuying then "" else "\n<font size=\"13\">SOON</font>")
		itemRobux.Active = Config.RobuxBuying
	end
	itemBuy.Text = if equipped then "EQUIPPED" elseif owned then "EQUIP" elseif affordable then "BUY" else "NEED COINS"
	local live = (owned and not equipped) or (not owned and affordable)
	itemBuy.Active = live
	itemBuy.AutoButtonColor = live
	itemBuy.BackgroundColor3 = if equipped then Color3.fromRGB(70, 110, 170)
		elseif owned then BUTTON
		elseif affordable then Color3.fromRGB(46, 170, 80)
		else Color3.fromRGB(90, 96, 110)
	local status = if equipped then "You're wearing this."
		elseif owned then "You own this. Equip it here or from the Locker."
		elseif affordable then ""
		else `You need {item.price - coins} more coins. Play matches to earn them.`
	itemStatus.Text = status
	-- Build 41: the item's own line (each rink names its goal show), across the foot of its picture.
	local desc = itemProduct and itemProduct:FindFirstChild("Desc") :: TextLabel?
	if desc then
		desc.Text = item.desc or ""
		desc.Visible = item.desc ~= nil
	end
end

local function closeShopItem()
	itemPageId = nil
	if itemSpinConn then
		itemSpinConn:Disconnect()
		itemSpinConn = nil
	end
	itemRig = nil
	if itemWorld then
		itemWorld:ClearAllChildren()
	end
	if itemProduct then
		for _, c in itemProduct:GetChildren() do
			if c:IsA("ViewportFrame") then
				c:Destroy()
			end
		end
	end
	if itemPage then
		itemPage.Visible = false
	end
end

function openShopItem(id: string)
	local item = Catalog.ById[id]
	local page = itemPage
	if not item or not page then
		return
	end
	closeShopItem()
	itemPageId = id
	itemName.Text = string.upper(item.name)
	itemSlot.Text = (Catalog.KindNames :: any)[item.kind] or ""
	-- The item on its own, big, on its price-tier colours.
	local tier = tierOf(item)
	local grad = itemProduct:FindFirstChildOfClass("UIGradient")
	if grad then
		grad.Color = ColorSequence.new(tier.b, tier.a)
	end
	buildPreview(item).Parent = itemProduct
	-- Your skater wearing it (a hair or face item with the hat off, so it shows).
	local look = table.clone(currentLook()) :: any
	look[item.kind] = item.id
	if item.kind == "hair" then
		look.hat = "nohat"
	end
	itemRig = Looks.build(itemWorld, look, 0, 1)
	for _, p in itemRig.ring do
		p.Transparency = 1
	end
	itemSpin = 0
	-- Back bling starts turned round so you see it; everything else faces you.
	itemYaw = if item.kind == "back" then math.pi - 0.4 else 0
	itemTouched = false
	itemDragX = nil
	local rig = itemRig
	pcall(Looks.pose, rig, CFrame.Angles(0, itemYaw, 0), -1)
	-- A slow sway until you grab it; then it turns only as you swipe.
	itemSpinConn = game:GetService("RunService").RenderStepped:Connect(function(dt: number)
		itemSpin += dt
		local sway = if itemTouched then 0 else math.sin(itemSpin * 0.8) * 0.6
		pcall(Looks.pose, rig, CFrame.Angles(0, itemYaw + sway, 0), -1)
	end)
	refreshShopItem()
	-- Build 34: a goal sound's page plays it once and offers PLAY SOUND to hear it again.
	if itemSound then
		itemSound.Visible = item.kind == "goal"
	end
	if item.kind == "goal" and callbacks.onPreviewGoal then
		callbacks.onPreviewGoal(item.style)
	end
	Ui.fadeIn(page)
end

-- Build 34: the Mystery Box (Robux). The banner at the top of the store and its page: every item
-- still possible for you with its real chance, from MysteryBox.odds (the very table the server
-- rolls), shown before you can buy; the BUY button lives on that page, so nobody buys without
-- seeing the odds (vault "Paid Random Items and Odds Disclosure in Practice").
local ROBUX = utf8.char(0xE002)
local boxPage: Frame? = nil
local boxList: ScrollingFrame
local boxBuy: TextButton
local boxNote: TextLabel
local boxBannerOpen: TextButton? = nil
local boxPrice: number? = nil
local boxPriceAsked = false

-- Build 35: the store's hero banners (Mystery Box, Season Pass): a rich two-tone gradient,
-- diagonal light bands, a gloss that sweeps across every few seconds, twinkling sparkles and a
-- gold frame. Only plain frames and gradients, so nothing pokes out of the rounded banner.
-- Content goes on ZIndex 3 and up (the bands, shade and gloss sit on 1-2).
local function heroBanner(parent: Instance, order: number, from: Color3, to: Color3, edge: Color3, sparkles: { Vector2 }): Frame
	local banner: Frame = Ui.new("Frame", {
		Size = UDim2.new(1, -10, 0, 128),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		LayoutOrder = order,
		Parent = parent,
	}, {
		Ui.corner(10),
		Ui.new("UIGradient", { Color = ColorSequence.new(from, to), Rotation = 20 }),
		Ui.stroke(edge, 3),
	})
	-- Diagonal light bands.
	local kp = { NumberSequenceKeypoint.new(0, 1) }
	for i = 0, 3 do
		local a = 0.08 + i * 0.24
		table.insert(kp, NumberSequenceKeypoint.new(a, 1))
		table.insert(kp, NumberSequenceKeypoint.new(a + 0.001, 0.9))
		table.insert(kp, NumberSequenceKeypoint.new(a + 0.06, 0.9))
		table.insert(kp, NumberSequenceKeypoint.new(a + 0.061, 1))
	end
	table.insert(kp, NumberSequenceKeypoint.new(1, 1))
	Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 1, Parent = banner }, {
		Ui.corner(10),
		Ui.new("UIGradient", { Transparency = NumberSequence.new(kp), Rotation = -60 }),
	})
	-- A darker floor under the text, for depth.
	Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 1, Parent = banner }, {
		Ui.corner(10),
		Ui.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.45, 1), NumberSequenceKeypoint.new(1, 0.55) }), Rotation = 90 }),
	})
	-- The gloss.
	local gloss: Frame = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2, Parent = banner }, { Ui.corner(10) })
	local sweep: UIGradient = Ui.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.72),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = 25,
		Offset = Vector2.new(-1, 0),
		Parent = gloss,
	})
	task.spawn(function()
		while banner.Parent do
			if banner.Visible then
				sweep.Offset = Vector2.new(-1, 0)
				TweenService:Create(sweep, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Offset = Vector2.new(1, 0) }):Play()
			end
			task.wait(4.5)
		end
	end)
	-- Sparkles: little diamonds that twinkle out of step with each other.
	for i, at in sparkles do
		local size = 6 + (i % 3) * 3
		local s: Frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(at.X, 0, at.Y, 0),
			Size = UDim2.fromOffset(size, size),
			Rotation = 45,
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = banner,
		})
		-- Build 36: fade and turn (a size tween snaps a few pixels at a time and looked choppy).
		TweenService:Create(s, TweenInfo.new(0.8 + (i % 4) * 0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, i * 0.17), { BackgroundTransparency = 0.85, Rotation = 135 }):Play()
	end
	return banner
end

-- A big italic banner title with a hard drop shadow and an outline.
local function heroTitle(parent: GuiObject, text: string, color: Color3, outline: Color3, position: UDim2, width: UDim)
	local size = UDim2.new(width, UDim.new(0, 44))
	Ui.label(text, 40, BLACK, Color3.new(0, 0, 0), { Position = position + UDim2.fromOffset(3, 3), Size = size, TextTransparency = 0.6, TextXAlignment = Enum.TextXAlignment.Left, FontFace = Ui.SportItalic, ZIndex = 3, Parent = parent })
	local title = Ui.label(text, 40, BLACK, color, { Position = position, Size = size, TextXAlignment = Enum.TextXAlignment.Left, FontFace = Ui.SportItalic, ZIndex = 4, Parent = parent })
	Ui.new("UIStroke", { Color = outline, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = title })
	return title
end

-- A small rounded tag above a banner title.
local function heroKicker(parent: GuiObject, text: string, bg: Color3, fg: Color3, position: UDim2)
	local tag: TextLabel = Ui.label(text, 13, BLACK, fg, { Position = position, Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0, BackgroundColor3 = bg, ZIndex = 4, Parent = parent })
	Ui.new("UICorner", { CornerRadius = UDim.new(0, 10), Parent = tag })
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = tag })
	return tag
end

-- Build 36: a banner call-to-action that reads as a chunky game button: a shaded face, a dark
-- edge, a gloss across the top and a hard shadow under it. `edge` also colours the shadow.
local function heroCta(button: TextButton, edge: Color3, outlineText: boolean?)
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, 10)
	end
	button.BackgroundTransparency = 0
	Ui.new("UIGradient", { Color = ColorSequence.new(WHITE, Color3.fromRGB(196, 196, 196)), Rotation = 90, Parent = button })
	Ui.new("UIStroke", { Color = edge, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = button })
	if outlineText then
		Ui.new("UIStroke", { Color = edge, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = button })
	end
	Ui.new("Frame", {
		Position = UDim2.fromOffset(5, 3),
		Size = UDim2.new(1, -10, 0.4, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		ZIndex = button.ZIndex,
		Parent = button,
	}, { Ui.corner(7) })
	Ui.new("Frame", {
		AnchorPoint = button.AnchorPoint,
		Position = button.Position + UDim2.fromOffset(0, 4),
		Size = button.Size,
		BackgroundColor3 = edge,
		BorderSizePixel = 0,
		ZIndex = button.ZIndex - 1,
		Parent = button.Parent,
	}, { Ui.corner(10) })
end

-- A soft round glow behind banner art.
local function heroGlow(parent: GuiObject, center: UDim2, size: number, color: Color3)
	for i, k in { 1, 0.7 } do
		Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = center,
			Size = UDim2.fromOffset(size * k, size * k),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.82 - i * 0.08,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = parent,
		}, { Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	end
end

-- The box drawn from frames: a purple box, a gold ribbon and bow, a big question mark.
local function drawBox(parent: GuiObject, size: number, position: UDim2, z: number)
	local holder: Frame = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = position, Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, ZIndex = z, Parent = parent })
	Ui.new("Frame", {
		Position = UDim2.fromScale(0.1, 0.32),
		Size = UDim2.fromScale(0.8, 0.64),
		BackgroundColor3 = WHITE,
		ZIndex = z,
		Parent = holder,
	}, { Ui.corner(size // 14), Ui.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(176, 90, 255), Color3.fromRGB(90, 30, 170)), Rotation = 90 }) })
	Ui.new("Frame", {
		Position = UDim2.fromScale(0.04, 0.2),
		Size = UDim2.fromScale(0.92, 0.18),
		BackgroundColor3 = Color3.fromRGB(130, 54, 214),
		ZIndex = z + 1,
		Parent = holder,
	}, { Ui.corner(size // 16) })
	Ui.new("Frame", { Position = UDim2.fromScale(0.43, 0.2), Size = UDim2.fromScale(0.14, 0.76), BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = z + 2, Parent = holder })
	for _, x in { 0.3, 0.7 } do
		Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.13), Size = UDim2.fromScale(0.26, 0.18), Rotation = if x < 0.5 then -20 else 20, BackgroundColor3 = GOLD, ZIndex = z + 2, Parent = holder }, { Ui.corner(size // 10) })
	end
	Ui.label("?", math.floor(size * 0.42), BLACK, WHITE, { Position = UDim2.fromScale(0.1, 0.38), Size = UDim2.fromScale(0.33, 0.52), ZIndex = z + 3, Parent = holder })
	Ui.label("?", math.floor(size * 0.42), BLACK, WHITE, { Position = UDim2.fromScale(0.57, 0.38), Size = UDim2.fromScale(0.33, 0.52), ZIndex = z + 3, Parent = holder })
	return holder
end

-- What the BUY button says, and whether it works.
local function boxState(): (string, boolean, string)
	if Config.Box.ProductId == 0 then
		return "COMING SOON", false, "The Mystery Box opens soon. Check back!"
	end
	if Players.LocalPlayer:GetAttribute("BoxRestricted") == true then
		return "NOT AVAILABLE", false, "Mystery Boxes aren't available where you live."
	end
	if profile and #MysteryBox.odds(profile.owned) == 0 then
		return "YOU OWN IT ALL!", false, "You already own everything a box can give. Legend!"
	end
	return if boxPrice then `BUY  {ROBUX} {boxPrice}` else "BUY", true, "You always get something you don't own yet."
end

local function fillOdds()
	for _, c in boxList:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local owned = if profile then profile.owned else {}
	local list = MysteryBox.odds(owned)
	local byTier: { [string]: { MysteryBox.Outcome } } = {}
	for _, o in list do
		byTier[o.tier] = byTier[o.tier] or {}
		table.insert(byTier[o.tier], o)
	end
	local tierP = MysteryBox.tierOdds(owned)
	local order = 0
	local function row(text: string, right: string, size: number, color: Color3, height: number)
		order += 1
		local f: Frame = Ui.new("Frame", { Size = UDim2.new(1, -12, 0, height), BackgroundTransparency = 1, LayoutOrder = order, Parent = boxList })
		Ui.label(text, size, BLACK, color, { Size = UDim2.new(1, -110, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = f })
		Ui.label(right, size, BLACK, color, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 104, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, Parent = f })
	end
	for _, t in MysteryBox.Tiers do
		local items = byTier[t.key]
		row(t.name, MysteryBox.percent(tierP[t.key] or 0), 20, GOLD, 34)
		if items then
			for _, o in items do
				local item = Catalog.ById[o.id]
				row("   " .. string.upper(if item then item.name else o.id), MysteryBox.percent(o.p), 15, WHITE, 22)
			end
		else
			row("   You own all of these!", "", 15, Color3.fromRGB(190, 210, 255), 22)
		end
	end
	order += 1
	Ui.label(MysteryBox.Disclaimer, 13, Ui.Theme.BoldFont, Color3.fromRGB(200, 214, 255), {
		Size = UDim2.new(1, -12, 0, 52),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = order,
		Parent = boxList,
	})
end

local function redrawBox()
	local text, live, note = boxState()
	if boxBannerOpen then
		boxBannerOpen.Text = if live then "OPEN" else text
	end
	if boxPage then
		boxBuy.Text = text
		boxBuy.Active = live
		boxBuy.AutoButtonColor = live
		boxBuy.BackgroundColor3 = if live then Color3.fromRGB(46, 170, 80) else Color3.fromRGB(90, 96, 110)
		boxNote.Text = note
		if boxPage.Visible then
			fillOdds()
		end
	end
end

-- The price comes from Roblox (never typed in here), once.
local function askBoxPrice()
	if boxPriceAsked or Config.Box.ProductId == 0 then
		return
	end
	boxPriceAsked = true
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(Config.Box.ProductId, Enum.InfoType.Product)
		end)
		if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
			boxPrice = info.PriceInRobux
		else
			boxPriceAsked = false -- try again next time the store opens
		end
		redrawBox()
	end)
end

local function openBoxPage()
	local page = boxPage
	if not page then
		return
	end
	askBoxPrice()
	page.Visible = true
	redrawBox()
	Ui.fadeIn(page)
end

local function closeBoxPage()
	if boxPage then
		boxPage.Visible = false
	end
end

-- The banner at the top of the store and the box's own page (built with the store).
local function buildBoxShop(shop: Frame, grid: ScrollingFrame)
	-- Build 35: a hero banner (was a flat orange strip): deep violet into hot magenta, the box
	-- bobbing in a gold glow, sparkles, an outlined title and big buttons.
	local banner = heroBanner(grid, 0, Color3.fromRGB(64, 16, 140), Color3.fromRGB(226, 50, 150), GOLD, {
		Vector2.new(0.03, 0.2), Vector2.new(0.17, 0.16), Vector2.new(0.15, 0.82), Vector2.new(0.04, 0.78),
		Vector2.new(0.58, 0.14), Vector2.new(0.66, 0.86), Vector2.new(0.74, 0.22),
	})
	heroGlow(banner, UDim2.new(0, 84, 0.5, 0), 132, GOLD)
	local art = drawBox(banner, 104, UDim2.new(0, 84, 0.5, 0), 4)
	-- Build 36: a rocking wobble (turning is drawn smoothly; the old bob moved a few whole
	-- pixels a second and looked low-FPS).
	art.Rotation = -6
	TweenService:Create(art, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 6 }):Play()
	heroKicker(banner, "ALWAYS SOMETHING NEW", GOLD, INK, UDim2.fromOffset(160, 12))
	heroTitle(banner, "MYSTERY BOX", WHITE, Color3.fromRGB(70, 10, 110), UDim2.fromOffset(160, 32), UDim.new(1, -360))
	Ui.label("A rink, a box-only outfit, a hat, a stick, hair, a goal sound or a puck you don't own yet.", 14, Ui.Theme.BoldFont, WHITE, {
		Position = UDim2.fromOffset(160, 78),
		Size = UDim2.new(1, -360, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		ZIndex = 4,
		Parent = banner,
	})
	local odds = Ui.button("SEE ODDS", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -18, 0.5, -28),
		Size = UDim2.fromOffset(176, 40),
		TextSize = 17,
		Font = BLACK,
		BackgroundColor3 = Color3.fromRGB(160, 90, 255),
		ZIndex = 5,
		Parent = banner,
	}, openBoxPage)
	heroCta(odds, Color3.fromRGB(60, 16, 120), true)
	local open = Ui.button("OPEN", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -18, 0.5, 22),
		Size = UDim2.fromOffset(176, 46),
		TextSize = 20,
		Font = BLACK,
		BackgroundColor3 = Color3.fromRGB(255, 212, 70),
		TextColor3 = INK,
		ZIndex = 5,
		Parent = banner,
	}, openBoxPage)
	heroCta(open, Color3.fromRGB(160, 96, 0))
	boxBannerOpen = open

	-- The page: the box and BUY on the left, every outcome and its odds on the right.
	local page: Frame = Ui.new("Frame", {
		Name = "BoxPage",
		Active = true, -- Build 36: clicks stop here, not on the store cards underneath
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		Visible = false,
		ZIndex = 20,
		Parent = shop,
	}, {
		Ui.corner(6),
		Ui.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(110, 46, 190), Color3.fromRGB(40, 18, 96)), Rotation = 90 }),
	})
	boxPage = page
	Ui.label("MYSTERY BOX", 27, BLACK, WHITE, { Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -36, 0, 32), TextXAlignment = Enum.TextXAlignment.Left, Parent = page })
	Ui.button("BACK", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(96, 34),
		TextSize = 18,
		Font = BLACK,
		BackgroundColor3 = RED,
		Parent = page,
	}, closeBoxPage)
	local left: Frame = Ui.new("Frame", { Position = UDim2.fromOffset(18, 58), Size = UDim2.new(0.45, -27, 1, -76), BackgroundTransparency = 1, Parent = page })
	drawBox(left, 200, UDim2.new(0.5, 0, 0, 120), 2)
	Ui.label("OPEN A BOX, WIN SOMETHING NEW!", 22, BLACK, GOLD, { Position = UDim2.fromOffset(0, 236), Size = UDim2.new(1, 0, 0, 28), TextScaled = true, Parent = left })
	boxBuy = Ui.button("BUY", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 276),
		Size = UDim2.fromOffset(260, 60),
		TextSize = 26,
		Font = BLACK,
		BackgroundColor3 = Color3.fromRGB(46, 170, 80),
		Parent = left,
	}, function()
		local _, live = boxState()
		if live and callbacks.onOpenBox then
			callbacks.onOpenBox()
		end
	end)
	squareCorners(boxBuy)
	boxNote = Ui.label("", 15, Ui.Theme.BoldFont, Color3.fromRGB(214, 222, 255), { Position = UDim2.fromOffset(0, 344), Size = UDim2.new(1, 0, 0, 44), TextWrapped = true, Parent = left })
	local right: Frame = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 58),
		Size = UDim2.new(0.55, -9, 1, -76),
		BackgroundColor3 = Color3.fromRGB(26, 12, 64),
		BackgroundTransparency = 0.2,
		Parent = page,
	}, { Ui.corner(6) })
	Ui.label("WHAT'S INSIDE AND THE ODDS", 20, BLACK, WHITE, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, Parent = right })
	boxList = Ui.new("ScrollingFrame", {
		Position = UDim2.fromOffset(14, 42),
		Size = UDim2.new(1, -20, 1, -50),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = right,
	}, { Ui.new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }) })
	Players.LocalPlayer:GetAttributeChangedSignal("BoxRestricted"):Connect(redrawBox)
	redrawBox()
end

-- After a box is bought and saved: what came out, big, with EQUIP.
local boxReveal: Frame? = nil
function Menu.boxReveal(id: string?, coins: number)
	if boxReveal then
		boxReveal:Destroy()
	end
	local item = id and Catalog.ById[id]
	local overlay: Frame = Ui.new("Frame", {
		Name = "BoxReveal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		ZIndex = 60,
		Active = true,
		Parent = root,
	})
	boxReveal = overlay
	local card: Frame = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 470),
		BackgroundColor3 = WHITE,
		ZIndex = 61,
		Parent = overlay,
	}, { Ui.corner(10), Ui.stroke(GOLD, 3) })
	local tier = if item then tierOf(item) else TIERS[4]
	Ui.new("UIGradient", { Color = ColorSequence.new(tier.b, tier.a), Rotation = 90, Parent = card })
	local scale = Ui.new("UIScale", { Scale = 0.3, Parent = card })
	TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	Ui.label("YOU GOT", 22, BLACK, WHITE, { Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 28), ZIndex = 62, Parent = card })
	local pic: Frame = Ui.new("Frame", { Position = UDim2.fromOffset(60, 46), Size = UDim2.fromOffset(300, 240), BackgroundTransparency = 1, ZIndex = 62, Parent = card })
	if item then
		local vf = buildPreview(item)
		vf.ZIndex = 62
		vf.Parent = pic
	else
		coinIcon(pic, 120, UDim2.new(0.5, -60, 0.5, 0))
	end
	local title = if item then string.upper(item.name) else `{coins} COINS`
	Ui.label(title, 34, BLACK, WHITE, { Position = UDim2.fromOffset(12, 292), Size = UDim2.new(1, -24, 0, 40), TextScaled = true, FontFace = Ui.SportItalic, ZIndex = 62, Parent = card })
	local sub = if item then ((Catalog.KindNames :: any)[item.kind] or "") else "You already own everything!"
	Ui.label(sub, 16, BLACK, Color3.fromRGB(255, 244, 210), { Position = UDim2.fromOffset(12, 334), Size = UDim2.new(1, -24, 0, 22), ZIndex = 62, Parent = card })
	local function close()
		overlay:Destroy()
		if boxReveal == overlay then
			boxReveal = nil
		end
	end
	if item then
		local equip = Ui.button("EQUIP", {
			Position = UDim2.new(0.5, -170, 0, 380),
			Size = UDim2.fromOffset(160, 56),
			TextSize = 24,
			Font = BLACK,
			BackgroundColor3 = Color3.fromRGB(46, 170, 80),
			ZIndex = 62,
			Parent = card,
		}, function()
			callbacks.onEquip(item.kind, item.id)
			close()
		end)
		squareCorners(equip)
	end
	local ok = Ui.button("AWESOME!", {
		Position = if item then UDim2.new(0.5, 10, 0, 380) else UDim2.new(0.5, -80, 0, 380),
		Size = UDim2.fromOffset(160, 56),
		TextSize = 22,
		Font = BLACK,
		BackgroundColor3 = BUTTON,
		ZIndex = 62,
		Parent = card,
	}, close)
	squareCorners(ok)
	redrawBox()
end

-- Build 40: the first-whole-match prize, the Nova set. The server grants and equips all four at
-- the end of the match; Main.client queues this and it opens the next time the menu shows: the
-- four pieces pop in one by one on a dark card whose neon edge sweeps cyan to magenta.
local NOVA_CYAN = Color3.fromRGB(0, 225, 255)
local NOVA_MAG = Color3.fromRGB(255, 50, 200)
local pendingFirstGame: { string }? = nil
local firstGameOverlay: Frame? = nil
-- (Build 41: the "play a match to get this set" offer state and function live on Menu, not in
-- locals: this script is at Luau's limit of 200 locals in scope.)
Menu.firstGameOffered = false

-- offer (Build 41): the same card before the set is won, as a nudge: what a first whole match
-- wins, with PLAY A MATCH and LATER.
local function firstGameReveal(ids: { string }, offer: boolean?)
	if firstGameOverlay then
		firstGameOverlay:Destroy()
	end
	local overlay: Frame = Ui.new("Frame", {
		Name = "FirstGameReveal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.3,
		ZIndex = 60,
		Active = true,
		Parent = root,
	})
	firstGameOverlay = overlay
	local card: Frame = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(760, 440),
		BackgroundColor3 = Color3.fromRGB(26, 28, 42),
		ZIndex = 61,
		Parent = overlay,
	}, { Ui.corner(12) })
	Ui.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(44, 48, 72), Color3.fromRGB(14, 15, 24)), Rotation = 90, Parent = card })
	local edge = Ui.stroke(WHITE, 4)
	edge.Parent = card
	local sweep = Ui.new("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, NOVA_CYAN), ColorSequenceKeypoint.new(0.5, NOVA_MAG), ColorSequenceKeypoint.new(1, NOVA_CYAN) }), Parent = edge })
	local spin = TweenService:Create(sweep, TweenInfo.new(2.4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 })
	spin:Play()
	local scale = Ui.new("UIScale", { Scale = 0.3, Parent = card })
	TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	Ui.label(if offer then "YOUR NEXT REWARD" else "FIRST MATCH COMPLETE!", 20, BLACK, NOVA_CYAN, { Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 24), ZIndex = 62, Parent = card })
	Ui.label(if offer then "PLAY YOUR FIRST MATCH TO GET THIS SET!" else "NOVA SET UNLOCKED", 40, BLACK, WHITE, { Position = UDim2.fromOffset(12, 40), Size = UDim2.new(1, -24, 0, 46), TextScaled = true, FontFace = Ui.SportItalic, ZIndex = 62, Parent = card })
	-- The four pieces, popping in one after another.
	local n = #ids
	local w, gap = 168, 14
	local x0 = (760 - (n * w + (n - 1) * gap)) / 2
	for i, id in ids do
		local item = Catalog.ById[id]
		if item then
			local tile: Frame = Ui.new("Frame", {
				Position = UDim2.fromOffset(x0 + (i - 1) * (w + gap) + w / 2, 96 + 105),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(w, 210),
				BackgroundColor3 = Color3.fromRGB(36, 40, 60),
				ZIndex = 62,
				Parent = card,
			}, { Ui.corner(10), Ui.stroke(if i % 2 == 1 then NOVA_CYAN else NOVA_MAG, 2) })
			local pop = Ui.new("UIScale", { Scale = 0, Parent = tile })
			task.delay(0.35 + 0.18 * i, function()
				TweenService:Create(pop, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end)
			local vf = buildPreview(item)
			vf.Position = UDim2.fromOffset(4, 4)
			vf.Size = UDim2.new(1, -8, 1, -44)
			vf.ZIndex = 63
			vf.Parent = tile
			Ui.label(string.upper(item.name), 16, BLACK, WHITE, { Position = UDim2.new(0, 4, 1, -38), Size = UDim2.new(1, -8, 0, 20), TextScaled = true, ZIndex = 63, Parent = tile })
			Ui.label(string.upper((Catalog.KindNames :: any)[item.kind] or ""), 12, BLACK, if i % 2 == 1 then NOVA_CYAN else NOVA_MAG, { Position = UDim2.new(0, 4, 1, -18), Size = UDim2.new(1, -8, 0, 14), ZIndex = 63, Parent = tile })
		end
	end
	Ui.label(if offer then "Finish one whole match and the animated Nova set is yours, free. It glows and spins!"
		else "You're wearing it now. It glows, spins and sparks in every match!", 16, BLACK, Color3.fromRGB(205, 215, 240), { Position = UDim2.fromOffset(12, 314), Size = UDim2.new(1, -24, 0, 22), ZIndex = 62, Parent = card })
	local function close()
		spin:Cancel()
		overlay:Destroy()
		if firstGameOverlay == overlay then
			firstGameOverlay = nil
		end
	end
	local ok = Ui.button(if offer then "PLAY A MATCH" else "AWESOME!", {
		Position = if offer then UDim2.new(0.5, -230, 0, 354) else UDim2.new(0.5, -100, 0, 354),
		Size = if offer then UDim2.fromOffset(280, 60) else UDim2.fromOffset(200, 60),
		TextSize = 24,
		Font = BLACK,
		BackgroundColor3 = Color3.fromRGB(0, 170, 205),
		ZIndex = 62,
		Parent = card,
	}, function()
		close()
		if offer and callbacks then
			callbacks.onPlay()
		end
	end)
	squareCorners(ok)
	if offer then
		local later = Ui.button("LATER", {
			Position = UDim2.new(0.5, 70, 0, 354),
			Size = UDim2.fromOffset(160, 60),
			TextSize = 22,
			Font = BLACK,
			BackgroundColor3 = Color3.fromRGB(70, 76, 104),
			ZIndex = 62,
			Parent = card,
		}, close)
		squareCorners(later)
	end
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = ok
	end
end

-- Build 41: once the tutorial is done (on coming back to the menu, or on joining later) and the
-- set isn't won yet, the card shows what a first whole match wins: once a session.
function Menu.offerFirstGame()
	if Menu.firstGameOffered or not tutorialDone or firstGameOverlay or pendingFirstGame or not (root and root.Visible) then
		return
	end
	local owned = profile and profile.owned
	if type(owned) ~= "table" or owned[Catalog.FirstGameReward[1]] or profile.status == "loading" then
		return
	end
	Menu.firstGameOffered = true
	firstGameReveal(Catalog.FirstGameReward, true)
end

-- Queued by Main.client when the match reward says the set was granted; shown at once if the
-- menu is already up, else the next time it opens (after the results screen).
function Menu.queueFirstGame(ids: { string })
	pendingFirstGame = ids
	if root and root.Visible then
		pendingFirstGame = nil
		firstGameReveal(ids)
	end
end

function redrawShop()
	if not shopGrid then
		return
	end
	if next(shopCards) == nil then
		-- Built once: one section per slot, each a header and a grid of picture cards. Only
		-- items sold for coins (season pass rewards are earned on the pass).
		for k, kind in Catalog.ShopKinds do
			local section = shopSections[kind]
			local sold = {}
			for _, item in Catalog.itemsOfKind(kind) do
				if Catalog.inShop(item) then
					table.insert(sold, item)
				end
			end
			table.sort(sold, function(a, b)
				if a.price ~= b.price then
					return a.price < b.price
				end
				return a.name < b.name
			end)
			for order, item in sold do
				shopCard(section.cards, order, item)
			end
			section.frame.LayoutOrder = k + 1
		end
	end
	for id, entry in shopCards do
		entry.owned.Visible = profile ~= nil and profile.owned[id] == true
	end
	for kind, nav in shopNav do
		local on = kind == shopKind
		nav.button.TextColor3 = if on then WHITE else Color3.fromRGB(200, 218, 255)
		nav.marker.BackgroundColor3 = if on then GOLD else NAV
	end
	if shopCoins then
		shopCoins.Text = tostring(if profile then profile.coins else 0)
	end
	refreshShopItem()
	redrawBox()
end

-- Season pass panel: your tier and XP, the 30-tier track (premium row over free row), the
-- reward you picked, and the premium offer. The server grants every reward the moment a tier is
-- reached (vault note "Battle Pass and Season Design"); this panel only draws what it sends.
-- Build 36: cells 108 tall (were 124), so the picked reward's panel has room for PLAY SOUND
-- under its text.
local PASS_COL, PASS_CELL = 122, 108
local PREMIUM_A, PREMIUM_B = Color3.fromRGB(232, 168, 36), Color3.fromRGB(150, 70, 190)
local FREE_A, FREE_B = Color3.fromRGB(110, 190, 250), Color3.fromRGB(40, 100, 196)
type PassCell = { frame: TextButton, shade: Frame, lock: TextLabel, got: Frame }
local passTrack: ScrollingFrame
local passColumns: { { dot: Frame, num: TextLabel, free: PassCell?, premium: PassCell? } } = {}
local passBuiltFor: string? = nil
local passTitle: TextLabel
local passEnds: TextLabel
local passTierLabel: TextLabel
local passXpText: TextLabel
local passXpFill: Frame
local passBuy: TextButton
local passBuyNote: TextLabel
local passDetailPic: Frame
local passDetailName: TextLabel
local passDetailSub: TextLabel
local passDetailNote: TextLabel
-- Build 35: PLAY SOUND on the picked reward when it is a goal sound (owned or not: hearing it
-- is the sales pitch). Holds the goal style it plays.
local passSound: TextButton? = nil
local passSoundStyle: string? = nil
local passPick: { tier: number, track: string }? = nil
local passPrices: { [number]: number } = {}
local redrawPass: () -> ()

local function rewardName(reward: SeasonPass.Reward): string
	if reward.soon then
		return string.upper(reward.soon)
	end
	if reward.item then
		local item = Catalog.ById[reward.item]
		local name = if item then string.upper(item.name) else "?"
		return if reward.coins then `{name} + {reward.coins} COINS` else name
	end
	return `{reward.coins or 0} COINS`
end

-- The picture for one reward: the item in 3D, or a coin and the amount.
local function rewardPicture(parent: GuiObject, reward: SeasonPass.Reward, big: boolean)
	if reward.soon then
		-- Not built yet: a teaser tag instead of a picture.
		Ui.label("?", if big then 64 else 40, BLACK, WHITE, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.42),
			Size = UDim2.new(1, 0, 0, if big then 70 else 44),
			Parent = parent,
		})
		Ui.label("COMING SOON", if big then 18 else 12, BLACK, WHITE, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.42, if big then 38 else 24),
			Size = UDim2.new(1, 0, 0, if big then 22 else 16),
			Parent = parent,
		})
	elseif reward.item then
		local item = Catalog.ById[reward.item]
		if item then
			buildPreview(item).Parent = parent
		end
		if reward.coins then
			-- A coin bonus on the same tier. Build 36: a dark pill in the bottom corner (in the top
			-- corner the PREMIUM tag covered half the number).
			local size = if big then 24 else 15
			local pill: Frame = Ui.new("Frame", {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -4, 1, -4),
				Size = UDim2.fromOffset(0, size + 4),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = Color3.fromRGB(20, 14, 44),
				BackgroundTransparency = 0.2,
				ZIndex = 3,
				Parent = parent,
			}, {
				Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
				Ui.new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 3),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 2) }),
			})
			Ui.label(`+{reward.coins}`, if big then 17 else 11, BLACK, GOLD, {
				Size = UDim2.fromOffset(0, size),
				AutomaticSize = Enum.AutomaticSize.X,
				LayoutOrder = 1,
				Parent = pill,
			})
			coinIcon(pill, size, UDim2.new()).LayoutOrder = 2
		end
	else
		local size = if big then 52 else 40
		coinIcon(parent, size, UDim2.new(0.5, -size // 2, if big then 0.36 else 0.42, 0))
		Ui.label(`+{reward.coins or 0}`, if big then 30 else 20, BLACK, WHITE, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, if big then 0.36 else 0.42, size // 2 + 4),
			Size = UDim2.new(1, 0, 0, if big then 32 else 22),
			Parent = parent,
		})
	end
end

-- The season to draw: the one the server says is running, else the one about to start.
local function passSeason(): SeasonPass.Season?
	local view = profile and profile.season
	if view and SeasonPass.ById[view.id] then
		return SeasonPass.ById[view.id]
	end
	local now = os.time()
	return SeasonPass.current(now) or SeasonPass.upcoming(now)
end

local function daysText(seconds: number): string
	local days = math.max(1, math.ceil(seconds / 86400))
	return if days == 1 then "1 DAY" else `{days} DAYS`
end

local function passCell(parent: Instance, order: number, tier: number, track: string, reward: SeasonPass.Reward?): PassCell?
	local premium = track == "premium"
	local frame = Ui.button("", {
		NoGrow = true, -- Build 36: no hover growth (the cards sit in a clipped row)
		Size = UDim2.new(1, 0, 0, PASS_CELL),
		BackgroundColor3 = WHITE,
		LayoutOrder = order,
		ClipsDescendants = true,
		Parent = parent,
	}, function()
		if reward then
			passPick = { tier = tier, track = track }
			redrawPass()
		end
	end)
	-- Build 37: livelier cards: rounder corners, a bright rim, a three-tone gradient, a soft
	-- spotlight and halo behind the reward, a glassy sheen across the top and a dark name plate.
	local corner = frame:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, 9)
	end
	if not reward then
		-- A tier with nothing on this track: an empty slot.
		frame.BackgroundColor3 = Color3.fromRGB(16, 38, 96)
		frame.BackgroundTransparency = 0.45
		frame.Active = false
		local rim = Ui.stroke(WHITE, 1.5, 0.82)
		rim.Parent = frame
		return nil
	end
	local rimColor = if premium then Color3.fromRGB(255, 226, 140) else Color3.fromRGB(196, 236, 255)
	Ui.new("UIGradient", {
		Color = if premium
			then ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 206, 80)),
				ColorSequenceKeypoint.new(0.45, PREMIUM_A:Lerp(Color3.fromRGB(240, 110, 60), 0.35)),
				ColorSequenceKeypoint.new(1, PREMIUM_B:Lerp(Color3.fromRGB(70, 20, 120), 0.35)),
			})
			else ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(140, 214, 255)),
				ColorSequenceKeypoint.new(0.5, FREE_A:Lerp(FREE_B, 0.45)),
				ColorSequenceKeypoint.new(1, FREE_B:Lerp(Color3.fromRGB(16, 40, 110), 0.4)),
			}),
		Rotation = 90,
		Parent = frame,
	})
	local rim = Ui.stroke(rimColor, 2, 0.1)
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = frame
	-- The spotlight: a soft disc and a thin halo ring behind the reward.
	local glow: Frame = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -12),
		Size = UDim2.fromOffset(78, 78),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		Parent = frame,
	}, { Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	Ui.new("UIGradient", {
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.85) }),
		Rotation = 90,
		Parent = glow,
	})
	local halo = Ui.stroke(rimColor, 2, 0.45)
	halo.Parent = glow
	-- A glassy sheen, a diagonal band across the top left.
	local sheen: Frame = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.2, 0, 0, 0),
		Size = UDim2.new(0, 34, 2, 0),
		Rotation = 32,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		Parent = frame,
	})
	sheen.Name = "Sheen"
	local pic: Frame = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 1, -24),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	rewardPicture(pic, reward, false)
	local plate: Frame = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, -6, 0, 22),
		BackgroundColor3 = Color3.fromRGB(12, 10, 30),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = frame,
	}, { Ui.corner(6) })
	Ui.label(rewardName(reward), 13, BLACK, WHITE, {
		Position = UDim2.fromOffset(4, 0),
		Size = UDim2.new(1, -8, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 2,
		Parent = plate,
	})
	-- Not reached yet: dimmed. Premium without the pass: a lock tag. Granted: a green strip.
	local shade: Frame = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ZIndex = 4,
		Visible = false,
		Parent = frame,
	})
	local lock = Ui.label("PREMIUM", 12, BLACK, WHITE, {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(0, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color3.fromRGB(40, 20, 70),
		BackgroundTransparency = 0.15,
		ZIndex = 5,
		Visible = false,
		Parent = frame,
	})
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = lock })
	Ui.corner(4).Parent = lock
	local got: Frame = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(46, 20),
		BackgroundColor3 = Color3.fromRGB(46, 170, 80),
		ZIndex = 5,
		Visible = false,
		Parent = frame,
	}, { Ui.corner(4) })
	Ui.label("GOT", 12, BLACK, WHITE, { Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = got })
	return { frame = frame, shade = shade, lock = lock, got = got }
end

local function buildPassTrack(season: SeasonPass.Season)
	for _, c in passTrack:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	table.clear(passColumns)
	for i, tier in season.tiers do
		local col: Frame = Ui.new("Frame", {
			Size = UDim2.new(0, PASS_COL, 1, -12),
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Parent = passTrack,
		}, { Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }) })
		local dot: Frame = Ui.new("Frame", {
			Size = UDim2.fromOffset(40, 30),
			BackgroundColor3 = DEEP,
			LayoutOrder = 1,
			Parent = col,
		}, { Ui.corner(15) })
		local num = Ui.label(tostring(i), 18, BLACK, WHITE, { Size = UDim2.fromScale(1, 1), Parent = dot })
		passColumns[i] = {
			dot = dot,
			num = num,
			premium = passCell(col, 2, i, "premium", tier.premium),
			free = passCell(col, 3, i, "free", tier.free),
		}
	end
	passBuiltFor = season.id
end

local function fetchPassPrice(passId: number)
	if passId == 0 or passPrices[passId] then
		return
	end
	passPrices[passId] = -1 -- asked
	task.spawn(function()
		local ok, info = pcall(function()
			return (MarketplaceService :: any):GetProductInfoAsync(passId, Enum.InfoType.GamePass)
		end)
		if not ok then
			ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass)
			end)
		end
		if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
			passPrices[passId] = info.PriceInRobux
		else
			passPrices[passId] = nil -- try again next time the panel opens
		end
		if panels.Pass and panels.Pass.Visible then
			redrawPass()
		end
	end)
end

function redrawPass()
	if not passTrack then
		return
	end
	local season = passSeason()
	if not season then
		passTitle.Text = "SEASON PASS"
		passEnds.Text = "No season is running. The next one is on its way."
		passTierLabel.Text = ""
		passXpText.Text = ""
		passXpFill.Size = UDim2.fromScale(0, 1)
		passBuy.Visible = false
		passBuyNote.Text = ""
		return
	end
	if passBuiltFor ~= season.id then
		buildPassTrack(season)
		passPick = nil
	end
	local now = os.time()
	local view = profile and profile.season
	local running = view ~= nil and view.id == season.id
	local xp = if running then view.xp else 0
	local premium = running and view.premium == true
	local reached = if running then SeasonPass.tierFor(season, xp) else 0
	local count = #season.tiers
	passTitle.Text = season.name
	passEnds.Text = if running then `ENDS IN {daysText(season.endsAt - now)}`
		elseif not season.live then "COMING SOON - A SNEAK PEEK AT EVERY REWARD"
		else `STARTS IN {daysText(season.startsAt - now)}`
	passTierLabel.Text = if running then `TIER {reached}` else "TIER 0"
	if reached >= count then
		passXpFill.Size = UDim2.fromScale(1, 1)
		passXpText.Text = `{xp} XP  ·  EVERY TIER REACHED`
	else
		local from = if reached > 0 then season.tiers[reached].xp else 0
		local need = season.tiers[reached + 1].xp
		local span = math.max(1, need - from)
		passXpFill.Size = UDim2.fromScale(math.clamp((xp - from) / span, 0, 1), 1)
		passXpText.Text = `{xp - from} / {span} XP TO TIER {reached + 1}`
	end
	for i, col in passColumns do
		local on = i <= reached
		col.dot.BackgroundColor3 = if on then GOLD else DEEP
		col.num.TextColor3 = if on then INK else WHITE
		for track, cell in { free = col.free, premium = col.premium } do
			if cell then
				local claimed = running and ((if track == "free" then view.claimedFree else view.claimedPremium) or {})[tostring(i)] == true
				cell.got.Visible = claimed
				cell.shade.Visible = not claimed and (not on or (track == "premium" and not premium))
				cell.lock.Visible = track == "premium" and not premium
			end
		end
	end
	-- The picked reward (default: the next one you will get).
	if not passPick then
		for i = math.max(1, reached + 1), count do
			local tier = season.tiers[i]
			if tier.free or tier.premium then
				passPick = { tier = i, track = if tier.free then "free" else "premium" }
				break
			end
		end
		passPick = passPick or { tier = count, track = "premium" }
	end
	local pick = passPick :: { tier: number, track: string }
	local tier = season.tiers[pick.tier]
	local reward = if pick.track == "free" then tier.free else tier.premium
	for _, c in passDetailPic:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local grad = passDetailPic:FindFirstChildOfClass("UIGradient")
	if grad then
		grad.Color = if pick.track == "premium" then ColorSequence.new(PREMIUM_A, PREMIUM_B) else ColorSequence.new(FREE_A, FREE_B)
	end
	if reward then
		rewardPicture(passDetailPic, reward, true)
		passDetailName.Text = rewardName(reward)
		local slot = reward.item and Catalog.ById[reward.item] and (Catalog.KindNames :: any)[Catalog.ById[reward.item].kind]
		passDetailSub.Text = `TIER {pick.tier}  ·  {if pick.track == "premium" then "PREMIUM" else "FREE"}{if slot then "  ·  " .. string.upper(slot) else ""}`
		local claimed = running and ((if pick.track == "free" then view.claimedFree else view.claimedPremium) or {})[tostring(pick.tier)] == true
		passDetailNote.Text = if reward.soon then "Still being made. Reach this tier and it's yours the moment it's ready."
			elseif claimed then (if reward.item then "Yours. Wear it from the Locker." else "Added to your coins.")
			elseif pick.track == "premium" and not premium then `Needs the premium track. Reach tier {pick.tier} with it and it's yours.`
			elseif not running then "The season hasn't started yet."
			else `Reach tier {pick.tier} and it's yours straight away.`
	end
	do
		local item = reward and reward.item and Catalog.ById[reward.item]
		passSoundStyle = if item and item.kind == "goal" then item.style else nil
		if passSound then
			passSound.Visible = passSoundStyle ~= nil
		end
	end
	-- Premium offer.
	passBuy.Visible = true
	if premium then
		passBuy.Text = "PREMIUM ACTIVE"
		passBuy.Active = false
		passBuy.BackgroundColor3 = Color3.fromRGB(70, 110, 170)
		passBuyNote.Text = "Every premium reward you reach is yours."
	elseif season.premiumPassId == 0 then
		passBuy.Text = "COMING SOON"
		passBuy.Active = false
		passBuy.BackgroundColor3 = Color3.fromRGB(90, 96, 110)
		passBuyNote.Text = "Opens soon. Your XP already counts: buy it later and every premium reward you've reached is yours."
	else
		fetchPassPrice(season.premiumPassId)
		local price = passPrices[season.premiumPassId]
		passBuy.Text = if price and price > 0 then `GET PREMIUM\n{price} ROBUX` else "GET PREMIUM"
		passBuy.Active = running
		passBuy.BackgroundColor3 = if running then Color3.fromRGB(46, 170, 80) else Color3.fromRGB(90, 96, 110)
		passBuyNote.Text = "Unlocks the premium track. Every premium reward you've already reached is yours at once."
	end
end

local rankTitle: TextLabel
local rankMine: TextLabel
local rankMessage: TextLabel
local rankCells: { { name: TextLabel, value: TextLabel } } = {}
local rankTabButtons: { [string]: TextButton } = {}
local rankStat = "points"
local rankData: any = nil

local function redrawRankings()
	if not rankTitle then
		return
	end
	for stat, b in rankTabButtons do
		b.BackgroundTransparency = if stat == rankStat then 0 else 1
	end
	rankTitle.Text = `ALL-TIME TOP 50 (GLOBAL): {string.upper(rankStat)}`
	local mine = profile and profile.stats and profile.stats[rankStat] or 0
	rankMine.Text = `Your {rankStat}: {mine}`
	local rows = rankData and rankData.boards and rankData.boards[rankStat] or {}
	for i, cell in rankCells do
		local entry = rows[i]
		cell.name.Text = if entry then `{i}. {tostring(entry.name)}` else "" -- Build 36: as typed (capitals ran wide)
		cell.value.Text = if entry then tostring(entry.value) else ""
		cell.value.Visible = entry ~= nil
	end
	if not rankData or rankData.status == "loading" then
		rankMessage.Text = "Loading the rankings..."
	elseif rankData.status == "offline" then
		rankMessage.Text = "Rankings can't be reached right now. They update every two minutes."
	elseif #rows == 0 then
		rankMessage.Text = "No scores yet. Play matches to get on the board!"
	else
		rankMessage.Text = ""
	end
end

-- Global boards pushed by the server every couple of minutes.
function Menu.setRankings(data: any)
	if type(data) == "table" then
		rankData = data
		redrawRankings()
	end
end

-- Build 36: countUp rolls the numbers up from 0 (when the panel opens with the camera zoom).
local statsCount = 0
local function redrawStats(countUp: boolean?)
	if not profile then
		return
	end
	local s = profile.stats
	statsCount += 1
	local token = statsCount
	local order = 0
	local function set(key: string, text: string, value: number?, format: ((number) -> string)?)
		local label = statLabels[key]
		if not label then
			return
		end
		label.Text = text
		if countUp and value and value > 0 then
			order += 1
			local delay, length = 0.25 + order * 0.04, 0.7
			local started = os.clock()
			label.Text = if format then format(0) else "0"
			task.spawn(function()
				while token == statsCount do
					local u = math.clamp((os.clock() - started - delay) / length, 0, 1)
					local k = 1 - (1 - u) ^ 3
					label.Text = if u >= 1 then text elseif format then format(value * k) else tostring(math.floor(value * k))
					if u >= 1 then
						break
					end
					task.wait()
				end
			end)
		end
	end
	set("level", tostring(profile.level), profile.level)
	set("matches", tostring(s.matches), s.matches)
	set("wins", tostring(s.wins), s.wins)
	set("losses", tostring(s.losses), s.losses)
	local rate = if s.matches > 0 then math.round(s.wins / s.matches * 100) else nil
	set("winrate", if rate then `{rate}%` else "-", rate, function(v: number): string
		return `{math.floor(v)}%`
	end)
	set("goals", tostring(s.goals), s.goals)
	set("assists", tostring(s.assists), s.assists)
	set("shots", tostring(s.shots), s.shots)
	set("saves", tostring(s.saves), s.saves)
	set("points", tostring(s.points), s.points)
	local gpg = if s.matches > 0 then s.goals / s.matches else nil
	set("gpg", if gpg then string.format("%.2f", gpg) else "-", gpg, function(v: number): string
		return string.format("%.2f", v)
	end)
	set("coins", tostring(profile.coins), profile.coins)
end

function Menu.init(screen: ScreenGui, cb: Callbacks)
	callbacks = cb
	local fitBar: () -> ()
	root = Ui.new("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = screen,
	})

	-- Top navigation bar, full width: logo, section tabs, then settings, the badge, name,
	-- level, XP and coins on the right.
	local bar: Frame = Ui.new("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, BAR_H),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = root,
	}, {
		Ui.new("UIGradient", {
			Color = ColorSequence.new(NAV:Lerp(WHITE, 0.05), NAV:Lerp(Color3.new(0, 0, 0), 0.08)),
			Rotation = 90,
		}),
	})
	local barScale: UIScale = Ui.new("UIScale", { Parent = bar })
	-- The logo starts just right of Roblox's own menu and chat buttons (GuiService.TopbarInset;
	-- placed in fitBar below). Build 29: it sat about 70 px further right than it needed to.
	local LOGO_W = 166 -- Build 30: narrower (was 188), so the tabs start further left
	local RIGHT_W = 448 -- the right cluster (430) and its margin (18)
	local logo: Frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(112, 7),
		Size = UDim2.fromOffset(LOGO_W, BAR_H - 14),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = bar,
	})
	-- The brand, one word: PHYS in gold, HOCKEY in white, in the sport italic.
	local brand = Ui.label(`<font color="#FFC83C">PHYS</font>HOCKEY`, 34, nil, WHITE, {
		FontFace = Ui.SportItalic,
		RichText = true,
		Size = UDim2.fromScale(1, 1),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = logo,
	})
	Ui.new("UIStroke", { Color = Color3.fromRGB(12, 24, 60), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = brand })

	local tabs: Frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(112 + LOGO_W + 6, 8),
		Size = UDim2.new(1, -(112 + LOGO_W + 6 + RIGHT_W + 10), 0, BAR_H - 16),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = bar,
	})
	local tabLayout: UIListLayout = Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tabs })
	-- Shrinks the tab row when the bar is too narrow for it, so PASS never runs under the gear.
	local tabScale: UIScale = Ui.new("UIScale", { Parent = tabs })
	local function navTab(order: number, text: string, panel: string?)
		local b = Ui.button(text, {
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = NAV,
			TextSize = 23, -- Build 30: was 25
			Font = BLACK,
			LayoutOrder = order,
			ZIndex = 6,
			Parent = tabs,
		}, function()
			if panel then
				Menu.open(panel)
			else
				Menu.showHome()
			end
		end)
		b.BackgroundTransparency = 1
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = b })
		squareCorners(b)
		navTabs[panel or "Home"] = b
	end
	navTab(1, "PLAY", nil)
	navTab(2, "PLAYER", "Player")
	navTab(3, "RANKINGS", "Rankings")
	navTab(4, "SHOP", "Shop")
	navTab(5, "PASS", "Pass")

	-- Right cluster: settings gear, badge, name, level pill, XP bar and coins.
	local right: Frame = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 0),
		Size = UDim2.fromOffset(430, BAR_H),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = bar,
	})
	local gear = Ui.button("", {
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.fromOffset(BAR_H - 20, BAR_H - 20),
		BackgroundColor3 = NAV,
		ZIndex = 6,
		Parent = right,
	}, function()
		Menu.open("Settings")
	end)
	gear.BackgroundTransparency = 1
	squareCorners(gear)
	drawGear(gear)
	navTabs.Settings = gear
	Ui.new("Frame", {
		Position = UDim2.fromOffset(BAR_H - 4, 12),
		Size = UDim2.new(0, 2, 1, -24),
		BackgroundColor3 = NAV_DARK,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = right,
	})
	-- Rank emblem (drawn once the profile arrives); clicking it opens the Rank panel.
	local badge: Frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(BAR_H + 4, 6),
		Size = UDim2.fromOffset(BAR_H - 12, BAR_H - 12),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = right,
	})
	topBadge = badge
	local badgeButton = Ui.button("", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 12, Parent = badge }, function()
		Menu.open("Rank")
	end)
	badgeButton.BackgroundTransparency = 1
	local info: Frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(BAR_H * 2 - 6, 11),
		Size = UDim2.new(1, -(BAR_H * 2 - 6), 1, -22),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = right,
	})
	local nameRow: Frame = Ui.new("Frame", {
		Size = UDim2.new(1, -120, 0, 20),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = info,
	}, { Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }) })
	nameLabel = Ui.label("PLAYER", 16, BLACK, WHITE, {
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
		ZIndex = 6,
		Parent = nameRow,
	})
	local pill: Frame = Ui.new("Frame", {
		Size = UDim2.fromOffset(60, 20),
		BackgroundColor3 = NAV_DARK,
		LayoutOrder = 2,
		ZIndex = 6,
		Parent = nameRow,
	}, { Ui.corner(10) })
	levelLabel = Ui.label("Lv. 1", 13, Ui.Theme.BoldFont, Color3.fromRGB(200, 222, 255), { Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = pill })
	local coins: Frame = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(110, 20),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = info,
	})
	coinLabel = Ui.label("0", 16, BLACK, WHITE, {
		Size = UDim2.new(1, -24, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 6,
		Parent = coins,
	})
	Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = GOLD,
		ZIndex = 6,
		Parent = coins,
	}, { Ui.corner(9), Ui.stroke(Color3.fromRGB(214, 150, 24), 2) })
	local track: Frame = Ui.new("Frame", {
		Position = UDim2.new(0, 0, 1, -8),
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = info,
	}, { Ui.corner(4) })
	xpFill = Ui.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 7, Parent = track }, { Ui.corner(4) })
	statusLabel = Ui.label("Loading your profile...", 12, Ui.Theme.BoldFont, Color3.fromRGB(255, 230, 160), {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, BAR_H + 6),
		Size = UDim2.fromOffset(320, 16),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.5,
		Parent = root,
	})

	-- Left column: the play modes, then the career card.
	home = Ui.new("Frame", {
		Name = "Home",
		-- Sized to fit the 640-high design screen: the three modes, career and challenges all
		-- end above the bottom edge (about 480 tall from just under the top bar).
		Position = UDim2.fromOffset(26, BAR_H + 14),
		Size = UDim2.fromOffset(380, 600),
		BackgroundTransparency = 1,
		Parent = root,
	}, {
		Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		Ui.new("UIScale", {}),
	})
	local order = 0
	local function add(item: GuiObject)
		order += 1
		item.LayoutOrder = order
		item.Parent = home
	end
	local function modeButton(text: string, sub: string?, onClick: () -> ()): (TextButton, TextLabel?)
		local h = if sub then 54 else 46
		local subLabel: TextLabel? = nil
		local b = Ui.button("", { Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = BUTTON }, onClick)
		squareCorners(b)
		Ui.label(text, 22, BLACK, WHITE, {
			Position = UDim2.fromOffset(20, if sub then 5 else 0),
			Size = UDim2.new(1, -70, 0, if sub then 26 else h),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = b,
		})
		Ui.label("›", 36, BLACK, Color3.fromRGB(190, 212, 255), {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -18, 0, 0),
			Size = UDim2.new(0, 30, 1, -4),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = b,
		})
		if sub then
			subLabel = Ui.label(sub, 14, Ui.Theme.BoldFont, Color3.fromRGB(214, 228, 255), {
				Position = UDim2.fromOffset(20, 31),
				Size = UDim2.new(1, -70, 0, 18),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = b,
			})
		end
		add(b)
		return b, subLabel
	end
	playButton = modeButton("QUICK PLAY", "3 v 3 online. Bots fill any empty spot", cb.onPlay)
	modeButton("THE POND", "Open world on the lake with everyone", cb.onPond)
	modeButton("PRACTICE", "Free skate. Add pucks and a goalie", cb.onPractice)
	-- The tutorial is always one tap away from home, on every screen size (the promo card is
	-- hidden on narrow screens). Until it's done it sits at the top and names the reward.
	local tb, tsub = modeButton("TUTORIAL", "Learn to play. Win the Golden Comet stick!", cb.onTutorial)
	tutorialButton, tutorialSub = tb, tsub

	-- Career card: the four numbers that matter most, laid out like a challenge board.
	local career: Frame = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 134), BackgroundColor3 = BUTTON }, { Ui.corner(4) })
	add(career)
	Ui.label("CAREER", 24, BLACK, WHITE, { Position = UDim2.fromOffset(18, 8), Size = UDim2.new(1, -40, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, Parent = career })
	local viewStats = Ui.button("VIEW", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 9),
		Size = UDim2.fromOffset(80, 28),
		TextSize = 16,
		Font = BLACK,
		BackgroundColor3 = BUTTON,
		Parent = career,
	}, function()
		Menu.open("Stats")
	end)
	squareCorners(viewStats)
	Ui.stroke(WHITE, 2).Parent = viewStats
	local cells: Frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(14, 46),
		Size = UDim2.new(1, -28, 1, -56),
		BackgroundTransparency = 1,
		Parent = career,
	}, { Ui.new("UIGridLayout", { CellSize = UDim2.new(0.5, -3, 0.5, -3), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	for i, entry in { { "matches", "GAMES" }, { "saves", "SAVES" }, { "goals", "GOALS" }, { "wins", "WINS" } } do
		local cell: Frame = Ui.new("Frame", { BackgroundColor3 = BUTTON:Lerp(Color3.new(0, 0, 0), 0.12), LayoutOrder = i, Parent = cells }, { Ui.corner(3), Ui.stroke(BUTTON:Lerp(WHITE, 0.25), 1) })
		Ui.label(entry[2], 17, BLACK, Color3.fromRGB(214, 228, 255), { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.7, -10, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = cell })
		careerLabels[entry[1]] = Ui.label("0", 26, BLACK, WHITE, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.new(0.3, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, Parent = cell })
	end

	-- Daily challenges: four boxes like the career card, each with its goal, a progress bar and
	-- the count. Each one done pays 300 coins; they change every Monday.
	local chall: Frame = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 150), BackgroundColor3 = BUTTON }, { Ui.corner(4) })
	add(chall)
	Ui.label("CHALLENGES", 24, BLACK, WHITE, { Position = UDim2.fromOffset(18, 8), Size = UDim2.new(1, -40, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, Parent = chall })
	challengeReset = Ui.label("", 13, Ui.Theme.BoldFont, Color3.fromRGB(214, 228, 255), {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 15),
		Size = UDim2.fromOffset(170, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = chall,
	})
	local challGrid: Frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(14, 44),
		Size = UDim2.new(1, -28, 1, -54),
		BackgroundTransparency = 1,
		Parent = chall,
	}, { Ui.new("UIGridLayout", { CellSize = UDim2.new(0.5, -3, 0.5, -3), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	for i = 1, 4 do
		-- Compact: the goal on one line, the bar and count straight under it.
		local cell: Frame = Ui.new("Frame", { BackgroundColor3 = BUTTON:Lerp(Color3.new(0, 0, 0), 0.12), LayoutOrder = i, Parent = challGrid }, { Ui.corner(3), Ui.stroke(BUTTON:Lerp(WHITE, 0.25), 1) })
		local text = Ui.label("", 13, BLACK, WHITE, { Position = UDim2.fromOffset(8, 5), Size = UDim2.new(1, -16, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = cell })
		local bar: Frame = Ui.new("Frame", { Position = UDim2.fromOffset(8, 27), Size = UDim2.new(1, -58, 0, 7), BackgroundColor3 = Color3.fromRGB(16, 48, 110), BorderSizePixel = 0, Parent = cell }, { Ui.corner(4) })
		local fill: Frame = Ui.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = GOLD, BorderSizePixel = 0, Parent = bar }, { Ui.corner(4) })
		local count = Ui.label("", 13, BLACK, Color3.fromRGB(214, 228, 255), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -7, 0, 22), Size = UDim2.fromOffset(46, 16), TextXAlignment = Enum.TextXAlignment.Right, Parent = cell })
		-- Build 32: a finished challenge waits here to be collected.
		local collect: TextButton = Ui.new("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -5, 0.5, 0),
			Size = UDim2.fromOffset(78, 26),
			BackgroundColor3 = Color3.fromRGB(60, 190, 90),
			AutoButtonColor = true,
			Font = BLACK,
			TextSize = 13,
			TextColor3 = WHITE,
			Text = "COLLECT",
			Visible = false,
			ZIndex = 3,
			Parent = cell,
		}, { Ui.corner(4), Ui.stroke(Color3.fromRGB(30, 110, 50), 1) })
		challengeCells[i] = { text = text, count = count, fill = fill, bar = bar, cell = cell, collect = collect }
		local entry = challengeCells[i]
		collect.Activated:Connect(function()
			if entry.id and not entry.pending and callbacks.onClaimChallenge then
				entry.pending = true
				collect.Text = "..."
				callbacks.onClaimChallenge(entry.id)
			end
		end)
	end

	-- Promo card, top right: a ticker that turns to the next card every PROMO_SECONDS. Each card
	-- is one entry in promoCards (kicker, title, line, button, colours, when it shows and what the
	-- button does), so adding another is one more entry.
	local PROMO_SECONDS = 10
	type PromoCard = {
		kicker: string,
		title: string,
		line: () -> string,
		button: () -> string,
		color: Color3,
		edge: Color3,
		accent: Color3,
		shows: () -> boolean,
		run: () -> (),
	}
	local promoCards: { PromoCard } = {
		{
			kicker = "NEW TO THE ICE?",
			title = "LEARN TO SHOOT!",
			line = function()
				return "FINISH IT TO WIN THE GOLDEN COMET STICK + 350 COINS"
			end,
			button = function()
				return "START TUTORIAL"
			end,
			color = Color3.fromRGB(60, 34, 140),
			edge = Color3.fromRGB(124, 100, 255),
			accent = Color3.fromRGB(255, 214, 90),
			shows = function()
				return not tutorialDone
			end,
			run = cb.onTutorial,
		},
		{
			-- Build 40: once the tutorial is done, the next goal: a first whole match wins the
			-- animated Nova set (Catalog.FirstGameReward, granted in PlayerData.grantMatch).
			kicker = "YOUR FIRST MATCH",
			title = "PLAY A FULL GAME!",
			line = function()
				return "FINISH ONE AND WIN THE GLOWING NOVA SET: ARMOR, VISOR, REACTOR + BLADE"
			end,
			button = function()
				return "PLAY A MATCH"
			end,
			color = Color3.fromRGB(26, 28, 52),
			edge = Color3.fromRGB(0, 225, 255),
			accent = Color3.fromRGB(255, 50, 200),
			shows = function()
				local owned = profile and profile.owned
				return tutorialDone and type(owned) == "table" and not owned[Catalog.FirstGameReward[1]]
			end,
			run = cb.onPlay,
		},
		{
			kicker = "THE SEASON PASS",
			title = "NEW SKINS INSIDE!",
			line = function()
				local season = passSeason()
				return if season then `GET THE {string.upper(season.name)} PASS AND UNLOCK NEW SKINS` else "GET THE PASS AND UNLOCK NEW SKINS"
			end,
			button = function()
				return "OPEN THE PASS"
			end,
			color = Color3.fromRGB(150, 62, 14),
			edge = Color3.fromRGB(255, 160, 60),
			accent = Color3.fromRGB(255, 226, 120),
			shows = function()
				return passSeason() ~= nil
			end,
			run = function()
				Menu.open("Pass")
			end,
		},
		{
			kicker = "DAILY REWARDS",
			title = "LOG IN EVERY DAY!",
			line = function()
				return "COINS EVERY DAY TO BUY SKINS: UP TO 2,000 ON DAY 7"
			end,
			button = function()
				local login = profile and profile.login
				return if login and login.canClaim and not login.needsTutorial then "CLAIM TODAY'S COINS" else "SEE YOUR REWARDS"
			end,
			color = Color3.fromRGB(16, 104, 92),
			edge = Color3.fromRGB(80, 230, 190),
			accent = Color3.fromRGB(255, 214, 90),
			shows = function()
				return true
			end,
			run = cb.onDaily,
		},
		{
			-- Build 35: a teaser for the next mode (the game itself stays 3v3 until it ships).
			kicker = "COMING SOON",
			title = "1V1 SHOOTOUT!",
			line = function()
				return "PENALTY SHOTS: YOU VS THE GOALIE. ONE SHOT. NO MERCY."
			end,
			button = function()
				return "STAY TUNED!"
			end,
			color = Color3.fromRGB(150, 20, 40),
			edge = Color3.fromRGB(255, 90, 90),
			accent = Color3.fromRGB(255, 214, 90),
			shows = function()
				return true
			end,
			run = function()
				-- Build 36: offer Roblox's notification opt-in, so they hear the moment it lands.
				if callbacks.onStayTuned then
					callbacks.onStayTuned()
				end
				-- The button gives a little bounce so it still feels alive.
				local scale = promo and promo:FindFirstChildOfClass("UIScale")
				if scale then
					-- The scale also fits the screen (fit() below), so bounce around today's value.
					local base = scale.Scale
					scale.Scale = base * 1.04
					TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = base }):Play()
				end
			end,
		},
	}
	promo = Ui.new("Frame", {
		Name = "Promo",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -30, 0, BAR_H + 78),
		Size = UDim2.fromOffset(360, 196),
		BackgroundColor3 = promoCards[1].color,
		Parent = root,
	}, {
		Ui.corner(4),
		Ui.new("UIScale", {}),
	})
	local promoEdge = Ui.stroke(promoCards[1].edge, 3)
	promoEdge.Parent = promo
	local promoBody: CanvasGroup = Ui.new("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = promo,
	})
	local kicker = Ui.label("", 19, BLACK, Color3.fromRGB(214, 204, 255), { Position = UDim2.fromOffset(22, 20), Size = UDim2.new(1, -90, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Parent = promoBody })
	local headline = Ui.label("", 37, BLACK, WHITE, { Position = UDim2.fromOffset(22, 44), Size = UDim2.new(1, -44, 0, 42), TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, Parent = promoBody })
	local line = Ui.label("", 13, BLACK, Color3.fromRGB(255, 214, 90), { Position = UDim2.fromOffset(22, 90), Size = UDim2.new(1, -44, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, Parent = promoBody })
	local promoIndex = 1
	local learn = Ui.button("", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.new(1, -44, 0, 54),
		TextSize = 24,
		Font = BLACK,
		BackgroundColor3 = BUTTON,
		Parent = promo,
	}, function()
		promoCards[promoIndex].run()
	end)
	-- Dots, top right: which card this is, one per card on show. Build 37: each dot is a button
	-- (a 22-unit hit area round a 10-unit dot) that jumps straight to its card.
	local dots = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 20),
		Size = UDim2.fromOffset(120, 22),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = promo,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 0),
		}),
	})
	local dotFrames: { Frame } = {}
	local jumpToCard: (number) -> () = function() end
	for i = 1, #promoCards do
		local hit: TextButton = Ui.new("TextButton", {
			Size = UDim2.fromOffset(22, 22),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = i,
			ZIndex = 3,
			Parent = dots,
		})
		dotFrames[i] = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(10, 10),
			BackgroundColor3 = WHITE,
			ZIndex = 3,
			Parent = hit,
		}, { Ui.corner(5) })
		hit.MouseEnter:Connect(function()
			dotFrames[i].Size = UDim2.fromOffset(13, 13)
		end)
		hit.MouseLeave:Connect(function()
			dotFrames[i].Size = UDim2.fromOffset(10, 10)
		end)
		hit.Activated:Connect(function()
			jumpToCard(i)
		end)
	end
	local function paintPromo()
		local card = promoCards[promoIndex]
		kicker.Text = card.kicker
		headline.Text = card.title
		line.Text = card.line()
		line.TextColor3 = card.accent
		learn.Text = card.button()
		promo.BackgroundColor3 = card.color
		promoEdge.Color = card.edge
		for i, dot in dotFrames do
			local hit = dot.Parent :: GuiObject
			hit.Visible = promoCards[i].shows()
			dot.BackgroundTransparency = if i == promoIndex then 0 else 0.6
		end
	end
	-- The next card that shows (from `from`, going round); the current one if nothing else does.
	local function nextShowing(from: number): number
		for step = 0, #promoCards - 1 do
			local i = (from - 1 + step) % #promoCards + 1
			if promoCards[i].shows() then
				return i
			end
		end
		return promoIndex
	end
	local promoChanged = os.clock()
	local promoFading = false
	-- Build 37: a quick fade to card i (a clicked dot), and the 10-second clock starts again.
	jumpToCard = function(i: number)
		if i == promoIndex or promoFading or not promoCards[i].shows() then
			return
		end
		promoFading = true
		promoChanged = os.clock()
		local fade = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(promoBody, fade, { GroupTransparency = 1 }):Play()
		task.wait(0.12)
		promoIndex = i
		promoChanged = os.clock()
		paintPromo()
		TweenService:Create(promoBody, fade, { GroupTransparency = 0 }):Play()
		promoFading = false
	end
	refreshPromo = function()
		if not promoCards[promoIndex].shows() then
			promoIndex = nextShowing(promoIndex + 1)
			promoChanged = os.clock()
		end
		paintPromo()
	end
	task.spawn(function()
		while true do
			task.wait(0.5)
			if promo.Visible and not promoFading and os.clock() - promoChanged >= PROMO_SECONDS then
				local nextIndex = nextShowing(promoIndex + 1)
				promoChanged = os.clock()
				if nextIndex ~= promoIndex then
					promoFading = true
					local fade = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
					TweenService:Create(promoBody, fade, { GroupTransparency = 1 }):Play()
					task.wait(0.18)
					promoIndex = nextIndex
					paintPromo()
					TweenService:Create(promoBody, fade, { GroupTransparency = 0 }):Play()
					promoFading = false
				end
			end
		end
	end)
	refreshPromo()
	squareCorners(learn)

	-- The logo and tabs in the bar's own (scaled) units: the logo right after Roblox's buttons, the
	-- tabs after the logo, shrunk if they would reach the settings gear.
	local fittingBar = false
	function fitBar()
		if fittingBar then
			return
		end
		fittingBar = true
		local s = math.max(barScale.Scale, 0.01)
		local insetX = GuiService.TopbarInset.Min.X
		local logoX = math.clamp((insetX + 4) / s, 8, 200)
		local tabsX = logoX + LOGO_W + 2
		-- Build 31: the logo sits 12 units further left (and a touch narrower) than the tabs leave
		-- room for, so its italic tail no longer touches PLAY. The tabs stay where they were.
		logo.Position = UDim2.fromOffset(math.max(2, logoX - 12), 7)
		logo.Size = UDim2.fromOffset(LOGO_W - 4, BAR_H - 14)
		tabs.Position = UDim2.fromOffset(tabsX, 8)
		-- Build 30: the room is measured to where the settings gear really is on screen (the
		-- old sum of fixed widths let PASS run under the gear on the player's screen).
		local tabsLeft = bar.AbsolutePosition.X + tabsX * s
		local avail = math.max(120, (gear.AbsolutePosition.X - 16 - tabsLeft) / s)
		local content = tabLayout.AbsoluteContentSize.X / (s * math.max(tabScale.Scale, 0.01))
		local k = if content > 0 then math.clamp(avail / content, 0.45, 1) else 1
		tabScale.Scale = k
		tabs.Size = UDim2.fromOffset(avail / k, BAR_H - 16)
		fittingBar = false
	end
	tabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitBar)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(fitBar)
	gear:GetPropertyChangedSignal("AbsolutePosition"):Connect(fitBar)
	bar:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitBar)

	-- Keep the bar and columns readable on any screen size.
	local function fit()
		local cam = workspace.CurrentCamera
		local size = if cam then cam.ViewportSize else Vector2.new(1280, 720)
		-- A touch smaller than full fit, so the home screen breathes.
		local s = math.clamp(math.min(size.X / 1500, size.Y / 860) * 0.9, 0.45, 1)
		barScale.Scale = s
		bar.Size = UDim2.new(1 / s, 0, 0, BAR_H)
		fitBar()
		for _, frame in { home, promo } do
			local scale = frame:FindFirstChildOfClass("UIScale")
			if scale then
				scale.Scale = s
			end
		end
		home.Position = UDim2.fromOffset(26 * s, (BAR_H + 14) * s)
		promo.Position = UDim2.new(1, -30 * s, 0, (BAR_H + 14) * s)
		promoFits = size.X >= 900
		promo.Visible = promoFits and home.Visible
		statusLabel.Position = UDim2.new(1, -18, 0, BAR_H * s + 6)
		-- Fixed-size panels (Locker, Rank, Rankings, Settings, ...) shrink to fit smaller screens
		-- too, so their corners never run off the edge. Panels sized to the screen (Shop, Pass)
		-- already fit.
		local ps = math.clamp(math.min(size.X / 1100, (size.Y - BAR_H * s) / 600), 0.5, 1)
		for _, frame in panels do
			local scale = frame:FindFirstChildOfClass("UIScale")
			if scale and frame.Size.X.Scale == 0 and frame.Size.Y.Scale == 0 then
				-- Build 37: a panel wider than 1060 (Rankings) also fits the screen's own width.
				local gui = frame:FindFirstAncestorOfClass("ScreenGui")
				local guiScale = gui and gui:FindFirstChildOfClass("UIScale")
				local outer = if guiScale then guiScale.Scale else 1
				scale.Scale = math.clamp(math.min(ps, (size.X - 40) / (math.max(frame.Size.X.Offset, 1) * outer)), 0.5, 1)
			end
		end
	end
	fit()
	task.defer(fit) -- again once every panel exists
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end

	-- Locker.
	local rightPanel = UDim2.fromOffset(440, 510)
	local locker = panelFrame("Locker", "LOCKER", rightPanel, Vector2.new(1, 0.5), UDim2.new(1, -24, 0.55, 0))
	local function pickLocker(kind: string)
		lockerKind = kind
		redrawLocker()
	end
	-- Two rows of slots: what you wear, then the rest (skin, body, back bling, puck, goal sound, rink).
	tabRow(locker, { "hat", "hair", "face", "stick", "outfit", "colors" }, lockerTabs, pickLocker)
	-- Build 37: no BUILD tab (body sizes are gone).
	tabRow(locker, { "finish", "back", "puck", "goal", "rink" }, lockerTabs, pickLocker, 90)
	lockerGrid = grid(locker, 132)

	-- Shop.
	-- A full-width store, like a sports game's item shop: no skater in view while you browse.
	-- Coins and a "go to" list down the left; on the right a season pass banner, then one
	-- section of big picture cards per slot. A card opens the item's own page.
	local shop = panelFrame("Shop", "SHOP", UDim2.new(1, -40, 1, -(BAR_H + 36)), Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -16))
	shop.BackgroundTransparency = 0
	shop.BackgroundColor3 = WHITE
	Ui.new("UIGradient", { Color = ColorSequence.new(NAV:Lerp(WHITE, 0.08), NAV_DARK), Rotation = 90, Parent = shop })
	local side: Frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(18, 58),
		Size = UDim2.new(0, 200, 1, -76),
		BackgroundTransparency = 1,
		Parent = shop,
	}, { Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local coinBox: Frame = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = DEEP, LayoutOrder = 1, Parent = side }, { Ui.corner(4) })
	coinIcon(coinBox, 24, UDim2.new(0, 10, 0.5, 0))
	shopCoins = Ui.label("0", 22, BLACK, WHITE, { Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -52, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = coinBox })
	local passButton = Ui.button("SEASON PASS", {
		Size = UDim2.new(1, 0, 0, 38),
		TextSize = 17,
		Font = BLACK,
		BackgroundColor3 = Color3.fromRGB(46, 170, 80),
		LayoutOrder = 2,
		Parent = side,
	}, function()
		Menu.open("Pass")
	end)
	squareCorners(passButton)
	Ui.label("GO TO...", 24, BLACK, WHITE, { Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom, LayoutOrder = 3, Parent = side })
	shopGrid = Ui.new("ScrollingFrame", {
		Position = UDim2.fromOffset(238, 58),
		Size = UDim2.new(1, -254, 1, -72),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		Parent = shop,
	}, {
		Ui.new("UIListLayout", { Padding = UDim.new(0, 18), SortOrder = Enum.SortOrder.LayoutOrder }),
		-- Build 36: a few pixels of room, so the banners' outlines aren't clipped at the top and left.
		Ui.new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 4) }),
	})
	do
		-- lihfolk-ignore: findfirstchild-chain (the layout is made in the same Ui.new call above)
		local list = shopGrid:FindFirstChildOfClass("UIListLayout") :: UIListLayout
		local function fit()
			-- Build 35: AbsoluteContentSize is in screen pixels, already scaled by every UIScale
			-- above; CanvasSize is scaled again by them, so on a big screen the canvas came out far
			-- taller than the store (the giant gap after RINK). Undo the scale first.
			local scale = 1
			local node: Instance? = shopGrid
			while node do
				local s = node:FindFirstChildOfClass("UIScale")
				if s and s.Scale > 0 then
					scale *= s.Scale
				end
				if node:IsA("LayerCollector") then
					break
				end
				node = node.Parent
			end
			shopGrid.CanvasSize = UDim2.fromOffset(0, math.ceil(list.AbsoluteContentSize.Y / scale) + 24)
		end
		list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
		fit()
	end
	-- Build 34: the Mystery Box banner first, then the season pass.
	buildBoxShop(shop, shopGrid)
	-- Season pass banner across the top of the store.
	-- Build 35: a hero banner (was a flat purple strip): icy navy into glacier blue for the
	-- First Freeze season, a gold season medal in a glow, an outlined gold title.
	local banner = heroBanner(shopGrid, 1, Color3.fromRGB(10, 30, 96), Color3.fromRGB(30, 160, 220), GOLD, {
		Vector2.new(0.03, 0.22), Vector2.new(0.17, 0.14), Vector2.new(0.16, 0.84), Vector2.new(0.03, 0.8),
		Vector2.new(0.6, 0.12), Vector2.new(0.68, 0.88), Vector2.new(0.76, 0.2),
	})
	heroGlow(banner, UDim2.new(0, 84, 0.5, 0), 132, Color3.fromRGB(150, 230, 255))
	do
		-- The medal: two ribbon tails, a gold disc with a ring, "S1" in the middle.
		local medal: Frame = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 84, 0.5, 0), Size = UDim2.fromOffset(100, 100), BackgroundTransparency = 1, ZIndex = 4, Parent = banner })
		for _, x in { 0.36, 0.64 } do
			Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(x, 0.52), Size = UDim2.fromScale(0.2, 0.5), Rotation = if x < 0.5 then 18 else -18, BackgroundColor3 = Color3.fromRGB(220, 40, 60), BorderSizePixel = 0, ZIndex = 4, Parent = medal })
		end
		local disc: Frame = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.74, 0.74), BackgroundColor3 = WHITE, ZIndex = 5, Parent = medal }, {
			Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			Ui.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 236, 130), Color3.fromRGB(230, 150, 20)), Rotation = 60 }),
			Ui.stroke(Color3.fromRGB(170, 100, 10), 3),
		})
		Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.74, 0.74), BackgroundTransparency = 1, ZIndex = 6, Parent = disc }, {
			Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			Ui.stroke(Color3.fromRGB(200, 120, 10), 2),
		})
		Ui.label("S1", 30, BLACK, Color3.fromRGB(150, 80, 0), { Size = UDim2.fromScale(1, 1), FontFace = Ui.SportItalic, ZIndex = 7, Parent = disc })
		-- Build 36: a smooth swing (see the Mystery Box art).
		medal.Rotation = 6
		TweenService:Create(medal, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = -6 }):Play()
	end
	local season = SeasonPass.current(os.time()) or SeasonPass.upcoming(os.time()) or SeasonPass.Seasons[1]
	heroKicker(banner, string.upper(season.name), Color3.fromRGB(190, 240, 255), INK, UDim2.fromOffset(160, 12))
	heroTitle(banner, "SEASON PASS", GOLD, Color3.fromRGB(80, 40, 0), UDim2.fromOffset(160, 32), UDim.new(1, -360))
	Ui.label(`Play matches to earn XP: {#season.tiers} tiers of hats, sticks, goal sounds and coins on a free and a premium track.`, 14, Ui.Theme.BoldFont, WHITE, {
		Position = UDim2.fromOffset(160, 78),
		Size = UDim2.new(1, -360, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		ZIndex = 4,
		Parent = banner,
	})
	local bannerGo = Ui.button("VIEW PASS", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -18, 0.5, -2),
		Size = UDim2.fromOffset(176, 50),
		TextSize = 21,
		Font = BLACK,
		BackgroundColor3 = Color3.fromRGB(255, 212, 70),
		TextColor3 = INK,
		ZIndex = 5,
		Parent = banner,
	}, function()
		Menu.open("Pass")
	end)
	heroCta(bannerGo, Color3.fromRGB(160, 96, 0))
	local jumping = false
	local function scrollTo(kind: string)
		local section = shopSections[kind]
		if section then
			jumping = true
			local y = section.frame.AbsolutePosition.Y - shopGrid.AbsolutePosition.Y + shopGrid.CanvasPosition.Y
			shopGrid.CanvasPosition = Vector2.new(0, math.max(0, y))
			jumping = false
		end
	end
	for k, kind in Catalog.ShopKinds do
		local frame: Frame = Ui.new("Frame", {
			Size = UDim2.new(1, -10, 0, 0),
			BackgroundTransparency = 1,
			LayoutOrder = k + 1,
			Parent = shopGrid,
		}, { Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
		Ui.label((Catalog.KindNames :: any)[kind] or kind, 36, BLACK, WHITE, { Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Left, FontFace = Ui.SportItalic, LayoutOrder = 1, Parent = frame })
		local cards: Frame = Ui.new("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			Parent = frame,
		}, {
			Ui.new("UIGridLayout", {
				CellSize = UDim2.new(1 / SHOP_COLUMNS, -12, 0, CARD_H),
				CellPadding = UDim2.fromOffset(12, 12),
				FillDirectionMaxCells = SHOP_COLUMNS,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		do
			-- Build 29: the cell height used to come from a UIAspectRatioConstraint on the grid, but
			-- the grid still reported its content at the unconstrained CARD_H rows, so every section
			-- reserved far more height than its cards used (big gaps, endless scroll at the end).
			-- Now the rows are sized here, from the real column width, and measured by hand.
			local grid = cards:FindFirstChildOfClass("UIGridLayout") :: UIGridLayout
			local list = frame:FindFirstChildOfClass("UIListLayout") :: UIListLayout
			local function fit()
				-- Build 30: every UIScale above the grid counts (the screen-wide one too); with only the
				-- panel's, the width came out too big, 5 columns were planned where 4 fit, and each
				-- section was sized a row short, so the next one slid up over its last row.
				local scale = 1
				local node: Instance? = cards
				while node do
					local s = node:FindFirstChildOfClass("UIScale")
					if s and s.Scale > 0 then
						scale *= s.Scale
					end
					if node:IsA("LayerCollector") then
						break
					end
					node = node.Parent
				end
				local width = cards.AbsoluteSize.X / scale
				-- Cards keep their designed shape and never grow past it (Build 30: letting them
				-- grow made the picture taller than its camera framing, so hats, faces and sticks
				-- were cut off).
				local cellW = math.max(40, math.min(CARD_W, math.floor(width / SHOP_COLUMNS - 12)))
				local cellH = math.floor(cellW / CARD_ASPECT)
				if grid.CellSize.Y.Offset ~= cellH or grid.CellSize.X.Offset ~= cellW then
					grid.CellSize = UDim2.fromOffset(cellW, cellH)
				end
				local count = 0
				for _, child in cards:GetChildren() do
					if child:IsA("GuiObject") then
						count += 1
					end
				end
				-- Rows from the columns that really fit at this cell width, never from the plan alone.
				local columns = math.clamp(math.floor((width + 12) / (cellW + 12)), 1, SHOP_COLUMNS)
				local rows = math.ceil(count / columns)
				local gridH = if rows > 0 then rows * cellH + (rows - 1) * 12 else 0
				cards.Size = UDim2.new(1, 0, 0, gridH)
				frame.Size = UDim2.new(1, -10, 0, 40 + 8 + gridH)
			end
			cards:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
			cards.ChildAdded:Connect(fit)
			cards.ChildRemoved:Connect(fit)
			fit()
		end
		shopSections[kind] = { frame = frame, cards = cards }
		local navButton = Ui.button(string.upper((Catalog.KindNames :: any)[kind] or kind), {
			Size = UDim2.new(1, 0, 0, 36),
			BackgroundTransparency = 1,
			TextSize = 20,
			Font = BLACK,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 3 + k,
			Parent = side,
		}, function()
			shopKind = kind
			scrollTo(kind)
			redrawShop()
		end)
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 14), Parent = navButton })
		local marker: Frame = Ui.new("Frame", {
			Position = UDim2.new(0, -14, 0, 4),
			Size = UDim2.new(0, 4, 1, -8),
			BackgroundColor3 = NAV,
			BorderSizePixel = 0,
			Parent = navButton,
		})
		shopNav[kind] = { button = navButton, marker = marker }
	end
	-- Build 35: COINS at the bottom of the store: five coin packs for Robux (developer
	-- products, Config.CoinPacks). The server decides whether the prompt opens; the price shown
	-- comes from Roblox once it answers (until then, the planned price).
	do
		local coinsFrame: Frame = Ui.new("Frame", {
			Size = UDim2.new(1, -10, 0, 40 + 8 + 210),
			BackgroundTransparency = 1,
			LayoutOrder = #Catalog.ShopKinds + 2,
			Parent = shopGrid,
		}, { Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
		Ui.label("COINS", 36, BLACK, WHITE, { Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Left, FontFace = Ui.SportItalic, LayoutOrder = 1, Parent = coinsFrame })
		local packCards: Frame = Ui.new("Frame", {
			Size = UDim2.new(1, 0, 0, 210),
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			Parent = coinsFrame,
		}, {
			Ui.new("UIGridLayout", {
				CellSize = UDim2.new(1 / #Config.CoinPacks, -10, 0, 210),
				CellPadding = UDim2.fromOffset(10, 10),
				FillDirectionMaxCells = #Config.CoinPacks,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local function commas(n: number): string
			local s = tostring(math.floor(n))
			local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
			return (out:gsub("^,", ""))
		end
		local piles = { 1, 2, 3, 4, 6 }
		local tags: { [number]: string } = { [3] = "POPULAR", [5] = "BEST VALUE" }
		for i, pack in Config.CoinPacks do
			local card: Frame = Ui.new("Frame", { BackgroundColor3 = WHITE, LayoutOrder = i, Parent = packCards }, {
				Ui.corner(8),
				Ui.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(40, 70, 150), Color3.fromRGB(16, 30, 76)), Rotation = 90 }),
				Ui.stroke(if tags[i] then GOLD else Color3.fromRGB(90, 130, 210), 2),
			})
			-- The coin pile grows with the pack.
			local pile: Frame = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22), Size = UDim2.fromOffset(110, 74), BackgroundTransparency = 1, Parent = card })
			local n = piles[i] or 1
			local spots = {
				{ Vector2.new(0.5, 0.55) },
				{ Vector2.new(0.36, 0.62), Vector2.new(0.62, 0.48) },
				{ Vector2.new(0.28, 0.66), Vector2.new(0.72, 0.66), Vector2.new(0.5, 0.38) },
				{ Vector2.new(0.26, 0.68), Vector2.new(0.74, 0.68), Vector2.new(0.36, 0.36), Vector2.new(0.64, 0.34) },
				{},
				{ Vector2.new(0.2, 0.72), Vector2.new(0.5, 0.74), Vector2.new(0.8, 0.72), Vector2.new(0.35, 0.44), Vector2.new(0.65, 0.44), Vector2.new(0.5, 0.16) },
			}
			local size = if n >= 6 then 34 elseif n >= 3 then 40 else 46
			for _, at in spots[n] do
				local c = coinIcon(pile, size, UDim2.new(at.X, -size // 2, at.Y, 0))
				Ui.label("C", math.floor(size * 0.55), BLACK, Color3.fromRGB(190, 120, 10), { Size = UDim2.fromScale(1, 1), Parent = c })
			end
			Ui.label(commas(pack.coins), 30, BLACK, WHITE, { Position = UDim2.fromOffset(0, 102), Size = UDim2.new(1, 0, 0, 32), FontFace = Ui.SportItalic, Parent = card })
			Ui.label("COINS", 14, BLACK, GOLD, { Position = UDim2.fromOffset(0, 132), Size = UDim2.new(1, 0, 0, 16), Parent = card })
			local tagText = tags[i]
			if tagText then
				local tag = Ui.label(tagText, 12, BLACK, INK, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0, BackgroundColor3 = GOLD, Parent = card })
				Ui.new("UICorner", { CornerRadius = UDim.new(0, 9), Parent = tag })
				Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = tag })
			end
			local live = pack.productId ~= 0
			local buy = Ui.button(if live then `{ROBUX} {pack.robux}` else "SOON", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -10),
				Size = UDim2.new(1, -20, 0, 40),
				TextSize = 18,
				Font = BLACK,
				BackgroundColor3 = if live then Color3.fromRGB(46, 170, 80) else Color3.fromRGB(90, 96, 110),
				AutoButtonColor = live,
				Parent = card,
			}, function()
				if live and callbacks.onBuyCoins then
					callbacks.onBuyCoins(pack.key)
				end
			end)
			squareCorners(buy)
			if live then
				-- The real price from Roblox (the dashboard price is what is charged).
				task.spawn(function()
					local ok, info = pcall(function()
						return MarketplaceService:GetProductInfo(pack.productId, Enum.InfoType.Product)
					end)
					if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
						buy.Text = `{ROBUX} {info.PriceInRobux}`
					end
				end)
			end
		end
		shopSections.coins = { frame = coinsFrame, cards = packCards }
		local navButton = Ui.button("COINS", {
			Size = UDim2.new(1, 0, 0, 36),
			BackgroundTransparency = 1,
			TextSize = 20,
			Font = BLACK,
			TextColor3 = GOLD,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 4 + #Catalog.ShopKinds,
			Parent = side,
		}, function()
			shopKind = "coins"
			scrollTo("coins")
			redrawShop()
		end)
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 14), Parent = navButton })
		local marker: Frame = Ui.new("Frame", {
			Position = UDim2.new(0, -14, 0, 4),
			Size = UDim2.new(0, 4, 1, -8),
			BackgroundColor3 = NAV,
			BorderSizePixel = 0,
			Parent = navButton,
		})
		shopNav.coins = { button = navButton, marker = marker }
	end
	shopScrollTo = scrollTo
	-- Scrolling the store lights up the slot you are looking at.
	shopGrid:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		if jumping then
			return
		end
		local top = shopGrid.AbsolutePosition.Y + 40
		local current = shopKind
		for _, kind in Catalog.ShopKinds do
			local section = shopSections[kind]
			if section and section.frame.AbsolutePosition.Y <= top then
				current = kind
			end
		end
		local coinsSection = shopSections.coins
		if coinsSection and coinsSection.frame.AbsolutePosition.Y <= top then
			current = "coins"
		end
		if current ~= shopKind then
			shopKind = current
			redrawShop()
		end
	end)

	-- Item page: your skater wearing the item on the left; the item, its name, price and BUY on
	-- the right. It covers the store; BACK returns to it.
	local page: Frame = Ui.new("Frame", {
		Name = "ItemPage",
		Active = true, -- Build 36: clicks stop here (they used to reach the store cards underneath
		-- and open a different item, e.g. the next rink)
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		Visible = false,
		ZIndex = 20,
		Parent = shop,
	}, {
		Ui.corner(6),
		Ui.new("UIGradient", { Color = ColorSequence.new(NAV:Lerp(WHITE, 0.08), NAV_DARK), Rotation = 90 }),
	})
	itemPage = page
	Ui.label("SHOP", 27, BLACK, Color3.fromRGB(200, 218, 255), { Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -36, 0, 32), TextXAlignment = Enum.TextXAlignment.Left, Parent = page })
	Ui.button("BACK", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(96, 34),
		TextSize = 18,
		Font = BLACK,
		BackgroundColor3 = RED,
		Parent = page,
	}, function()
		closeShopItem()
	end)
	-- Left: the skater.
	local stage: Frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(18, 58),
		Size = UDim2.new(0.5, -27, 1, -76),
		BackgroundColor3 = DEEP,
		Parent = page,
	}, {
		Ui.corner(6),
		Ui.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(52, 108, 196), Color3.fromRGB(18, 40, 100)), Rotation = 90 }),
	})
	local charView: ViewportFrame = Ui.new("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 150, 165),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.6, -1, 0.7),
		Parent = stage,
	})
	charView.Active = true
	charView.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			itemDragX = input.Position.X
			if not itemTouched then
				-- Keep the pose where the sway had it, so grabbing doesn't jump.
				itemYaw += math.sin(itemSpin * 0.8) * 0.6
				itemTouched = true
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local from = itemDragX
		if from and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			itemYaw += (input.Position.X - from) * 0.012
			itemDragX = input.Position.X
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			itemDragX = nil
		end
	end)
	Ui.label("DRAG TO SPIN", 13, BLACK, Color3.fromRGB(200, 218, 255), {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.fromOffset(160, 18),
		ZIndex = 3,
		Parent = stage,
	})
	itemWorld = Instance.new("WorldModel")
	itemWorld.Parent = charView
	itemCamera = Instance.new("Camera")
	itemCamera.FieldOfView = 30
	itemCamera.CFrame = CFrame.lookAt(Vector3.new(4.6, 6.6, -21.5), Vector3.new(0, 3.8, 0))
	itemCamera.Parent = charView
	charView.CurrentCamera = itemCamera
	-- Right: the item and how to get it.
	local info: Frame = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 58),
		Size = UDim2.new(0.5, -27, 1, -76),
		BackgroundTransparency = 1,
		Parent = page,
	})
	itemProduct = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 0.56, 0),
		BackgroundColor3 = WHITE,
		Parent = info,
	}, { Ui.corner(6), Ui.new("UIGradient", { Color = ColorSequence.new(TIERS[1].b, TIERS[1].a), Rotation = 90 }) })
	itemSlot = Ui.label("", 16, BLACK, WHITE, {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(0, 0, 0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6,
		ZIndex = 3,
		Parent = itemProduct,
	})
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = itemSlot })
	Ui.corner(4).Parent = itemSlot
	-- Build 41: the item's description (a rink's goal show), a caption across the picture's foot.
	local descCaption = Ui.label("", 16, Ui.Theme.BoldFont, WHITE, {
		Name = "Desc",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 58),
		TextScaled = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = Color3.fromRGB(6, 10, 30),
		BackgroundTransparency = 0.25,
		Visible = false,
		ZIndex = 4,
		Parent = itemProduct,
	})
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), Parent = descCaption })
	Ui.new("UITextSizeConstraint", { MaxTextSize = 16, Parent = descCaption })
	itemName = Ui.label("", 44, BLACK, WHITE, {
		Position = UDim2.new(0, 0, 0.56, 14),
		Size = UDim2.new(1, 0, 0, 50),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		FontFace = Ui.SportItalic,
		Parent = info,
	}, nil)
	Ui.new("UITextSizeConstraint", { MaxTextSize = 44, Parent = itemName })
	local priceRow: Frame = Ui.new("Frame", {
		Position = UDim2.new(0, 0, 0.56, 70),
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Parent = info,
	})
	coinIcon(priceRow, 30, UDim2.new(0, 0, 0.5, 0))
	itemPrice = Ui.label("", 32, BLACK, WHITE, { Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -42, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = priceRow })
	itemBuy = Ui.button("BUY", {
		Position = UDim2.new(0, 0, 0.56, 122),
		Size = UDim2.fromOffset(180, 58),
		TextSize = 26,
		Font = BLACK,
		BackgroundColor3 = Color3.fromRGB(46, 170, 80),
		Parent = info,
	}, function()
		local id = itemPageId
		local item = id and Catalog.ById[id]
		if not item or not profile then
			return
		end
		if profile.owned[item.id] then
			if profile.look[item.kind] ~= item.id then
				callbacks.onEquip(item.kind, item.id)
			end
		elseif profile.coins >= item.price then
			callbacks.onBuy(item.id)
		end
	end)
	squareCorners(itemBuy)
	-- Build 36: buy with Robux instead (shows the price; SOON until it's live).
	local robuxButton = Ui.button("", {
		NoGrow = true,
		Position = UDim2.new(0, 190, 0.56, 122),
		Size = UDim2.fromOffset(150, 58),
		TextSize = 22,
		Font = BLACK,
		RichText = true,
		LineHeight = 0.9,
		BackgroundColor3 = Color3.fromRGB(34, 44, 72),
		Visible = false,
		Parent = info,
	}, function()
		-- Not live yet (Config.RobuxBuying): the per-price developer products come later.
	end)
	squareCorners(robuxButton)
	Ui.new("UIStroke", { Color = Color3.fromRGB(120, 230, 150), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = robuxButton })
	itemRobux = robuxButton
	local soundButton = Ui.button("PLAY SOUND", {
		NoGrow = true,
		Position = UDim2.new(0, 350, 0.56, 122),
		Size = UDim2.fromOffset(160, 58),
		TextSize = 17,
		Font = BLACK,
		BackgroundColor3 = Color3.fromRGB(110, 40, 170),
		Visible = false,
		Parent = info,
	}, function()
		local id = itemPageId
		local item = id and Catalog.ById[id]
		if item and callbacks.onPreviewGoal then
			callbacks.onPreviewGoal(item.style)
		end
	end)
	squareCorners(soundButton)
	itemSound = soundButton
	itemStatus = Ui.label("", 15, Ui.Theme.BoldFont, Color3.fromRGB(210, 224, 255), {
		Position = UDim2.new(0, 0, 0.56, 188),
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Parent = info,
	})

	-- Season pass.
	-- Full width like the store: season name, time left and how XP is earned on the left, your
	-- tier and XP bar on the right, the 30-tier track across the middle (premium over free), and
	-- under it the reward you picked next to the premium offer.
	local pass = panelFrame("Pass", "SEASON PASS", UDim2.new(1, -40, 1, -(BAR_H + 36)), Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -16))
	pass.BackgroundTransparency = 0
	pass.BackgroundColor3 = WHITE
	Ui.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(70, 46, 150), NAV_DARK), Rotation = 90, Parent = pass })
	passTitle = Ui.label("", 30, BLACK, GOLD, { Position = UDim2.fromOffset(18, 48), Size = UDim2.new(0.6, -18, 0, 36), TextXAlignment = Enum.TextXAlignment.Left, FontFace = Ui.SportItalic, Parent = pass })
	passEnds = Ui.label("", 16, BLACK, WHITE, { Position = UDim2.fromOffset(18, 84), Size = UDim2.new(0.6, -18, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, Parent = pass })
	Ui.label("Every match: XP equal to your score, plus half your score in coins.", 13, Ui.Theme.BoldFont, Color3.fromRGB(214, 222, 255), {
		Position = UDim2.fromOffset(18, 106),
		Size = UDim2.new(0.6, -18, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = pass,
	})
	local meter: Frame = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 52),
		Size = UDim2.fromOffset(440, 76),
		BackgroundTransparency = 1,
		Parent = pass,
	})
	passTierLabel = Ui.label("", 34, BLACK, WHITE, { Size = UDim2.new(1, 0, 0, 36), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Ui.SportItalic, Parent = meter })
	local bar: Frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 0, 12),
		BackgroundColor3 = Color3.fromRGB(14, 28, 70),
		Parent = meter,
	}, { Ui.corner(6) })
	passXpFill = Ui.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = GOLD, BorderSizePixel = 0, Parent = bar }, { Ui.corner(6) })
	passXpText = Ui.label("", 13, BLACK, Color3.fromRGB(214, 222, 255), { Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Right, Parent = meter })
	-- Track labels on the left, then the scrolling track.
	local TRACK_Y = 140
	local TRACK_H = 30 + 8 + PASS_CELL + 8 + PASS_CELL + 14
	-- Build 39: the two track tiles dressed like the tier cards beside them (the user liked those):
	-- the track's three-tone gradient, a bright rim, a glossy top, an emblem (a gem for premium, a
	-- puck for free) and the name in the house italic over TRACK on a dark plate.
	for row, info in { { "PREMIUM", true }, { "FREE", false } } do
		local premium = info[2]
		local rimColor = if premium then Color3.fromRGB(255, 226, 140) else Color3.fromRGB(196, 236, 255)
		local tag: Frame = Ui.new("Frame", {
			Position = UDim2.fromOffset(18, TRACK_Y + 38 + (row - 1) * (PASS_CELL + 8)),
			Size = UDim2.fromOffset(96, PASS_CELL),
			BackgroundColor3 = WHITE,
			Parent = pass,
		}, {
			Ui.new("UICorner", { CornerRadius = UDim.new(0, 9) }),
			Ui.new("UIGradient", {
				Color = if premium
					then ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 206, 80)),
						ColorSequenceKeypoint.new(0.45, PREMIUM_A:Lerp(Color3.fromRGB(240, 110, 60), 0.35)),
						ColorSequenceKeypoint.new(1, PREMIUM_B:Lerp(Color3.fromRGB(70, 20, 120), 0.35)),
					})
					else ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(140, 214, 255)),
						ColorSequenceKeypoint.new(0.5, FREE_A:Lerp(FREE_B, 0.45)),
						ColorSequenceKeypoint.new(1, FREE_B:Lerp(Color3.fromRGB(16, 40, 110), 0.4)),
					}),
				Rotation = 90,
			}),
		})
		local rim = Ui.stroke(rimColor, 2.5, 0)
		rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rim.Parent = tag
		-- Gloss over the top half, fading out downwards.
		Ui.new("Frame", {
			Size = UDim2.new(1, 0, 0.48, 0),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.72,
			BorderSizePixel = 0,
			Parent = tag,
		}, {
			Ui.new("UICorner", { CornerRadius = UDim.new(0, 9) }),
			Ui.new("UIGradient", { Transparency = NumberSequence.new(0, 1), Rotation = 90 }),
		})
		-- The emblem, a soft glow behind it.
		local emblem: Frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, -20),
			Size = UDim2.fromOffset(40, 40),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.78,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = tag,
		}, { Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		local halo = Ui.stroke(rimColor, 1.5, 0.35)
		halo.Parent = emblem
		if premium then
			-- A cut gem: a diamond with a lighter crown facet.
			Ui.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(19, 19),
				Rotation = 45,
				BackgroundColor3 = Color3.fromRGB(255, 214, 80),
				BorderSizePixel = 0,
				ZIndex = 3,
				Parent = emblem,
			}, {
				Ui.corner(3),
				Ui.stroke(WHITE, 2, 0),
				Ui.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 250, 220), Color3.fromRGB(240, 140, 40)), Rotation = 45 }),
			})
		else
			-- A puck seen from the side-top: a dark disc with a light rim.
			Ui.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(24, 15),
				BackgroundColor3 = Color3.fromRGB(26, 30, 44),
				BorderSizePixel = 0,
				ZIndex = 3,
				Parent = emblem,
			}, { Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), Ui.stroke(WHITE, 2, 0) })
		end
		-- The name over TRACK, on a dark plate like the cards' name plates.
		local plate: Frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -5),
			Size = UDim2.new(1, -10, 0, 42),
			BackgroundColor3 = Color3.fromRGB(12, 10, 30),
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = tag,
		}, { Ui.corner(6) })
		local name = Ui.label(info[1], 20, BLACK, WHITE, {
			Position = UDim2.fromOffset(2, 3),
			Size = UDim2.new(1, -4, 0, 22),
			FontFace = Ui.SportItalic,
			TextScaled = true,
			ZIndex = 2,
			Parent = plate,
		})
		Ui.new("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 10, Parent = name })
		Ui.label("TRACK", 12, BLACK, if premium then Color3.fromRGB(255, 214, 110) else Color3.fromRGB(160, 222, 255), {
			Position = UDim2.fromOffset(2, 24),
			Size = UDim2.new(1, -4, 0, 14),
			ZIndex = 2,
			Parent = plate,
		})
	end
	passTrack = Ui.new("ScrollingFrame", {
		Position = UDim2.fromOffset(124, TRACK_Y),
		Size = UDim2.new(1, -142, 0, TRACK_H),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		Parent = pass,
	}, { Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
	-- Under the track: the picked reward, then the premium offer.
	local lowerY = TRACK_Y + TRACK_H + 10
	local detail: Frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(18, lowerY),
		Size = UDim2.new(0.55, -27, 1, -(lowerY + 18)),
		BackgroundColor3 = Color3.fromRGB(14, 28, 70),
		BackgroundTransparency = 0.2,
		Parent = pass,
	}, { Ui.corner(6) })
	passDetailPic = Ui.new("Frame", {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(0, 150, 1, -20),
		BackgroundColor3 = WHITE,
		ClipsDescendants = true,
		Parent = detail,
	}, { Ui.corner(4), Ui.new("UIGradient", { Color = ColorSequence.new(FREE_A, FREE_B), Rotation = 90 }), Ui.new("UISizeConstraint", { MaxSize = Vector2.new(150, 190) }) })
	passDetailName = Ui.label("", 28, BLACK, WHITE, { Position = UDim2.fromOffset(176, 10), Size = UDim2.new(1, -188, 0, 32), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, FontFace = Ui.SportItalic, Parent = detail })
	passDetailSub = Ui.label("", 15, BLACK, GOLD, { Position = UDim2.fromOffset(176, 44), Size = UDim2.new(1, -188, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, Parent = detail })
	passDetailNote = Ui.label("", 15, Ui.Theme.BoldFont, Color3.fromRGB(214, 222, 255), {
		Position = UDim2.fromOffset(176, 66),
		Size = UDim2.new(1, -188, 0, 38),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = detail,
	})
	-- Build 36: under the text (the cells are shorter now, so the panel has room for it), and it
	-- doesn't grow on hover.
	local soundButton = Ui.button("PLAY SOUND", {
		NoGrow = true,
		Position = UDim2.fromOffset(176, 108),
		Size = UDim2.fromOffset(160, 32),
		TextSize = 15,
		Font = BLACK,
		BackgroundColor3 = Color3.fromRGB(110, 40, 170),
		Visible = false,
		Parent = detail,
	}, function()
		if passSoundStyle and callbacks.onPreviewGoal then
			callbacks.onPreviewGoal(passSoundStyle)
		end
	end)
	squareCorners(soundButton)
	passSound = soundButton
	local offer: Frame = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, lowerY),
		Size = UDim2.new(0.45, -9, 1, -(lowerY + 18)),
		BackgroundColor3 = WHITE,
		Parent = pass,
	}, {
		Ui.corner(6),
		Ui.stroke(GOLD, 2),
		Ui.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(110, 52, 170), Color3.fromRGB(50, 24, 104)), Rotation = 0 }),
	})
	Ui.label("PREMIUM TRACK", 26, BLACK, GOLD, { Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -230, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, FontFace = Ui.SportItalic, Parent = offer })
	passBuyNote = Ui.label("", 14, Ui.Theme.BoldFont, WHITE, {
		Position = UDim2.fromOffset(16, 44),
		Size = UDim2.new(1, -230, 1, -54),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Parent = offer,
	})
	passBuy = Ui.button("GET PREMIUM", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(190, 52),
		TextSize = 18,
		TextWrapped = true,
		Font = BLACK,
		BackgroundColor3 = Color3.fromRGB(46, 170, 80),
		Parent = offer,
	}, function()
		local season = passSeason()
		if season and season.premiumPassId ~= 0 then
			-- Only opens Roblox's prompt. The server confirms the purchase with Roblox and turns
			-- premium on; the panel redraws when the new profile arrives.
			pcall(function()
				MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, season.premiumPassId)
			end)
		end
	end)
	squareCorners(passBuy)

	-- Stats.
	-- Build 36: on the right; the lobby camera zooms in so the skater fills the left (Main.client).
	local stats = panelFrame("Stats", "CAREER STATS", UDim2.fromOffset(520, 288), Vector2.new(1, 0.5), UDim2.new(1, -40, 0.54, 0))
	local statGrid: Frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(18, 56),
		Size = UDim2.new(1, -36, 1, -70),
		BackgroundTransparency = 1,
		Parent = stats,
	}, { Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(112, 64), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local STAT_CARDS = {
		{ "level", "LEVEL" }, { "matches", "MATCHES" }, { "wins", "WINS" }, { "losses", "LOSSES" },
		{ "winrate", "WIN RATE" }, { "goals", "GOALS" }, { "assists", "ASSISTS" }, { "shots", "SHOTS" },
		{ "saves", "SAVES" }, { "points", "POINTS" }, { "gpg", "GOALS / GAME" }, { "coins", "COINS" },
	}
	for i, entry in STAT_CARDS do
		local box: Frame = Ui.new("Frame", { BackgroundColor3 = BLUE, LayoutOrder = i, Parent = statGrid }, { Ui.corner(6) })
		Ui.label(entry[2], 12, BLACK, Color3.fromRGB(190, 206, 255), { Position = UDim2.fromOffset(0, 7), Size = UDim2.new(1, 0, 0, 16), Parent = box })
		statLabels[entry[1]] = Ui.label("0", 30, BLACK, WHITE, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 34), Parent = box })
	end

	-- How to play.
	local how = panelFrame("HowToPlay", "HOW TO PLAY", UDim2.fromOffset(640, 400), Vector2.new(0.5, 0.5), UDim2.fromScale(0.6, 0.5))
	howLabel = Ui.label(howToPlay(), 15, Ui.Theme.BodyFont, WHITE, {
		Position = UDim2.fromOffset(22, 54),
		Size = UDim2.new(1, -44, 1, -70),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		RichText = true,
		LineHeight = 1.3,
		Parent = how,
	})

	-- A left column of big buttons, like the home column (PLAYER and EXTRAS tabs).
	local function columnPanel(name: string, title: string, items: { { string } }): Frame
		local frame = panelFrame(name, title, UDim2.fromOffset(340, 74 + #items * 64), Vector2.new(0, 0.5), UDim2.new(0, 24, 0.5, 30))
		for i, item in items do
			local b = Ui.button(item[1], {
				Position = UDim2.fromOffset(18, 58 + (i - 1) * 64),
				Size = UDim2.new(1, -36, 0, 54),
				TextSize = 20,
				Font = BLACK,
				TextXAlignment = Enum.TextXAlignment.Left,
				BackgroundColor3 = BUTTON,
				Parent = frame,
			}, function()
				Menu.open(item[2])
			end)
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 18), Parent = b })
			squareCorners(b)
		end
		return frame
	end
	local extras = columnPanel("Player", "PLAYER", { { "APPEARANCE", "Locker" }, { "RANK", "Rank" }, { "CAREER STATS", "Stats" }, { "HOW TO PLAY", "HowToPlay" } })
	extras.Size += UDim2.fromOffset(0, 18)

	-- Rank: your emblem, ELO and progress to the next rank, the whole ladder, and season titles.
	local rankPanel = panelFrame("Rank", "RANK", UDim2.fromOffset(820, 500), Vector2.new(0.5, 0.5), UDim2.new(0.5, 0, 0.5, 40))
	local mine: Frame = Ui.new("Frame", { Position = UDim2.fromOffset(18, 54), Size = UDim2.fromOffset(250, 380), BackgroundColor3 = BUTTON:Lerp(Color3.new(0, 0, 0), 0.15), Parent = rankPanel }, { Ui.corner(6) })
	local bigBadge: Frame = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(170, 170), BackgroundTransparency = 1, Parent = mine })
	local rankName = Ui.label("", 30, BLACK, WHITE, { Position = UDim2.fromOffset(0, 190), Size = UDim2.new(1, 0, 0, 34), Parent = mine })
	local eloLabel = Ui.label("", 18, BLACK, GOLD, { Position = UDim2.fromOffset(0, 226), Size = UDim2.new(1, 0, 0, 22), Parent = mine })
	local nextBar: Frame = Ui.new("Frame", { Position = UDim2.fromOffset(20, 258), Size = UDim2.new(1, -40, 0, 12), BackgroundColor3 = Color3.fromRGB(16, 48, 110), BorderSizePixel = 0, Parent = mine }, { Ui.corner(6) })
	local nextFill: Frame = Ui.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = GOLD, BorderSizePixel = 0, Parent = nextBar }, { Ui.corner(6) })
	local nextLabel = Ui.label("", 14, Ui.Theme.BoldFont, Color3.fromRGB(214, 228, 255), { Position = UDim2.fromOffset(10, 276), Size = UDim2.new(1, -20, 0, 18), Parent = mine })
	Ui.label(`WIN +{Rank.WIN} ELO  ·  LOSS -{Rank.LOSS} ELO\nEVERY {Rank.STEP} ELO IS A NEW RANK\nQUICK PLAY MATCHES COUNT`, 13, Ui.Theme.BoldFont, Color3.fromRGB(190, 206, 240), {
		Position = UDim2.fromOffset(10, 304),
		Size = UDim2.new(1, -20, 0, 66),
		TextWrapped = true,
		Parent = mine,
	})
	-- The ladder: all sixteen ranks with where each starts (yours outlined in gold).
	local ladderStrokes: { UIStroke } = {}
	local ladder: Frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(284, 54),
		Size = UDim2.new(1, -302, 0, 380),
		BackgroundTransparency = 1,
		Parent = rankPanel,
	}, { Ui.new("UIGridLayout", { CellSize = UDim2.new(0.25, -6, 0.25, -6), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
	for index = 1, Rank.COUNT do
		local cell: Frame = Ui.new("Frame", { BackgroundColor3 = BUTTON:Lerp(Color3.new(0, 0, 0), 0.15), LayoutOrder = index, Parent = ladder }, { Ui.corner(4) })
		ladderStrokes[index] = Ui.stroke(GOLD, 2)
		ladderStrokes[index].Transparency = 1
		ladderStrokes[index].Parent = cell
		local icon: Frame = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 3), Size = UDim2.fromOffset(52, 52), BackgroundTransparency = 1, Parent = cell })
		RankBadge.draw(icon, index)
		Ui.label(Rank.name(index), 13, BLACK, WHITE, { Position = UDim2.new(0, 2, 1, -32), Size = UDim2.new(1, -4, 0, 15), Parent = cell })
		Ui.label(if index == Rank.COUNT then `{index * Rank.STEP}+ ELO` else `{index * Rank.STEP} ELO`, 12, Ui.Theme.BoldFont, Color3.fromRGB(190, 206, 240), { Position = UDim2.new(0, 2, 1, -17), Size = UDim2.new(1, -4, 0, 13), Parent = cell })
	end
	local titlesLabel = Ui.label("", 14, Ui.Theme.BoldFont, Color3.fromRGB(214, 228, 255), {
		Position = UDim2.fromOffset(18, 444),
		Size = UDim2.new(1, -36, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Parent = rankPanel,
	})
	rankView = { badge = bigBadge, name = rankName, elo = eloLabel, next = nextLabel, fill = nextFill, titles = titlesLabel, strokes = ladderStrokes }
	-- Build 37: no version line here (the build prints to the F9 console instead).

	-- Rankings: global top 50 for each career stat, five columns of ten like a league table.
	-- Build 36: 1040 wide (was 900), so longer names fit in the five columns.
	-- Build 37: 1260 wide, rows 36 tall and names in a bigger font (Build 36 only shrank them):
	-- every column is about 230 wide, and the number tag hugs its digits, so the name gets the
	-- rest of the row.
	local rankings = panelFrame("Rankings", "RANKINGS", UDim2.fromOffset(1260, 540), Vector2.new(0.5, 0.5), UDim2.new(0.5, 0, 0.5, 40))
	local rankTabs: Frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(18, 48),
		Size = UDim2.new(1, -36, 0, 42),
		BackgroundColor3 = NAV,
		Parent = rankings,
	}, {
		Ui.corner(6),
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6) }),
	})
	local board: Frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(18, 98),
		Size = UDim2.new(1, -36, 1, -112),
		BackgroundColor3 = Color3.fromRGB(34, 98, 178),
		Parent = rankings,
	}, { Ui.corner(6) })
	local boardHead: Frame = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = Color3.fromRGB(26, 76, 148),
		Parent = board,
	}, { Ui.corner(6) })
	rankTitle = Ui.label("", 18, BLACK, WHITE, {
		Position = UDim2.fromOffset(22, 0),
		Size = UDim2.new(0.6, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = boardHead,
	})
	rankMine = Ui.label("", 16, Ui.Theme.BodyFont, WHITE, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -22, 0, 0),
		Size = UDim2.new(0.4, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = boardHead,
	})
	rankMessage = Ui.label("", 17, Ui.Theme.BodyFont, Color3.fromRGB(215, 228, 255), {
		Position = UDim2.fromOffset(20, 60),
		Size = UDim2.new(1, -40, 0, 60),
		TextWrapped = true,
		Parent = board,
	})
	for i = 1, 50 do
		local col, rowIndex = (i - 1) // 10, (i - 1) % 10
		-- A row: the name fills what the number tag (sized to its digits) leaves.
		local cell: Frame = Ui.new("Frame", {
			Position = UDim2.new(col * 0.2, 10, 0, 52 + rowIndex * 36),
			Size = UDim2.new(0.2, -12, 0, 32),
			BackgroundColor3 = Color3.fromRGB(26, 76, 148),
			BackgroundTransparency = if rowIndex % 2 == 0 then 0.5 else 1,
			Parent = board,
		}, {
			Ui.corner(5),
			Ui.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 6),
			}),
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 4) }),
		})
		-- A very long name shrinks (to 15 pt at the least) before it is cut off.
		local name = Ui.label("", 19, BLACK, WHITE, {
			Size = UDim2.new(0, 40, 1, -4),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = 1,
			Parent = cell,
		})
		Ui.new("UITextSizeConstraint", { MaxTextSize = 19, MinTextSize = 15, Parent = name })
		Ui.new("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = name })
		local value = Ui.label("", 16, Ui.Theme.BoldFont, WHITE, {
			Size = UDim2.fromOffset(0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.fromRGB(52, 128, 214),
			LayoutOrder = 2,
			Parent = cell,
		})
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = value })
		Ui.corner(4).Parent = value
		rankCells[i] = { name = name, value = value }
	end
	for i, stat in Protocol.RankingStats do
		local b = Ui.button(string.upper(stat), {
			Size = UDim2.new(0, 0, 0, 34),
			AutomaticSize = Enum.AutomaticSize.X,
			TextSize = 19,
			Font = BLACK,
			BackgroundColor3 = NAV:Lerp(WHITE, 0.16),
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Parent = rankTabs,
		}, function()
			rankStat = stat
			redrawRankings()
		end)
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = b })
		rankTabButtons[stat] = b
	end

	-- Settings: GENERAL, CAMERA, ARENAS, SOCIAL, CONTROLS, VIDEO, AUDIO. Every row is wired to
	-- something that changes in the game; every change applies at once. SAVE keeps the changes
	-- (they are saved with the profile), CANCEL puts back what was there when the panel opened.
	local settings = panelFrame("Settings", "SETTINGS", UDim2.fromOffset(860, 530), Vector2.new(0.5, 0.5), UDim2.new(0.5, 0, 0.5, 44))
	local ROW_DARK = Color3.fromRGB(34, 98, 178)
	local ROW_LIGHT = Color3.fromRGB(40, 110, 194)
	local HEADER = Color3.fromRGB(26, 76, 148)
	local PICKED = Color3.fromRGB(140, 162, 206)
	local pages: { [string]: ScrollingFrame } = {}
	local pageTabs: { [string]: TextButton } = {}
	local refreshers: { () -> () } = {}
	local function refreshAll()
		for _, fn in refreshers do
			fn()
		end
	end
	-- Which settings each page shows, so RESET TO DEFAULTS resets only the page you're on.
	local pageSettings: { [Instance]: { string } } = {}
	local shownPage = "general"
	local function remember(parent: Instance, name: string)
		local list = pageSettings[parent]
		if not list then
			list = {}
			pageSettings[parent] = list
		end
		table.insert(list, name)
	end
	local function showPage(name: string)
		shownPage = name
		for id, page in pages do
			page.Visible = id == name
		end
		for id, b in pageTabs do
			local on = id == name
			b.BackgroundTransparency = if on then 0 else 1
			b.BackgroundColor3 = NAV:Lerp(WHITE, 0.16)
		end
	end
	local tabBar: Frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(18, 48),
		Size = UDim2.new(1, -36, 0, 42),
		BackgroundColor3 = NAV,
		Parent = settings,
	}, {
		Ui.corner(6),
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6) }),
	})
	local function page(order: number, id: string, title: string): ScrollingFrame
		local tab = Ui.button(title, {
			Size = UDim2.new(0, 0, 0, 34),
			AutomaticSize = Enum.AutomaticSize.X,
			TextSize = 19,
			Font = BLACK,
			BackgroundColor3 = NAV,
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = tabBar,
		}, function()
			showPage(id)
		end)
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = tab })
		pageTabs[id] = tab
		local p: ScrollingFrame = Ui.new("ScrollingFrame", {
			Position = UDim2.fromOffset(18, 98),
			Size = UDim2.new(1, -36, 1, -164),
			BackgroundColor3 = ROW_DARK,
			BorderSizePixel = 0,
			ScrollBarThickness = 8,
			ScrollBarImageColor3 = WHITE,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			Visible = false,
			Parent = settings,
		}, { Ui.corner(6), Ui.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }) })
		pages[id] = p
		return p
	end
	local function nextOrder(parent: Instance): number
		local n = (parent:GetAttribute("Rows") or 0) + 1
		parent:SetAttribute("Rows", n)
		return n
	end
	local function section(parent: Instance, title: string)
		local h: Frame = Ui.new("Frame", {
			Size = UDim2.new(1, -8, 0, 48),
			BackgroundColor3 = HEADER,
			BorderSizePixel = 0,
			LayoutOrder = nextOrder(parent),
			Parent = parent,
		})
		Ui.label(title, 20, BLACK, WHITE, {
			Position = UDim2.fromOffset(24, 0),
			Size = UDim2.new(1, -48, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = h,
		})
	end
	local function row(parent: Instance, label: string, hint: string?): Frame
		local order = nextOrder(parent)
		local r: Frame = Ui.new("Frame", {
			Size = UDim2.new(1, -8, 0, 54),
			BackgroundColor3 = if order % 2 == 0 then ROW_LIGHT else ROW_DARK,
			BorderSizePixel = 0,
			LayoutOrder = order,
			Parent = parent,
		})
		Ui.label(label, 18, Ui.Theme.BodyFont, WHITE, {
			Position = UDim2.fromOffset(36, if hint then 6 else 0),
			Size = UDim2.new(0.46, -36, if hint then 0 else 1, if hint then 24 else 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = r,
		})
		if hint then
			Ui.label(hint, 13, Ui.Theme.BodyFont, Color3.fromRGB(205, 220, 250), {
				Position = UDim2.fromOffset(36, 30),
				Size = UDim2.new(0.5, -36, 0, 16),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = r,
			})
		end
		return r
	end
	-- The control area: the right 52% of a row.
	local function controlArea(r: Frame): Frame
		return Ui.new("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 0),
			Size = UDim2.new(0.52, -14, 1, 0),
			BackgroundTransparency = 1,
			Parent = r,
		})
	end

	-- Number: value box plus a slider you can click or drag.
	local dragging: { bar: GuiObject, name: string }? = nil
	local function setFromX(bar: GuiObject, name: string, x: number)
		local spec = SettingsDef.Numbers[name]
		local t = math.clamp((x - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X), 0, 1)
		Prefs.set(name, spec[2] + (spec[3] - spec[2]) * t)
	end
	local function numberRow(parent: Instance, label: string, name: string, format: (number) -> string, hint: string?)
		local spec = SettingsDef.Numbers[name]
		remember(parent, name)
		local area = controlArea(row(parent, label, hint))
		local box: Frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(78, 38),
			BackgroundColor3 = Color3.fromRGB(46, 124, 210),
			Parent = area,
		}, { Ui.corner(6), Ui.stroke(Color3.fromRGB(70, 146, 226), 1) })
		local value = Ui.label("", 17, Ui.Theme.BodyFont, WHITE, { Size = UDim2.fromScale(1, 1), Parent = box })
		local bar: TextButton = Ui.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 98, 0.5, 0),
			Size = UDim2.new(1, -112, 0, 30),
			BackgroundTransparency = 1,
			Parent = area,
		})
		local track: Frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, 0, 0, 6),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Parent = bar,
		}, { Ui.corner(3) })
		local knob: Frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(14, 22),
			BackgroundColor3 = WHITE,
			Parent = bar,
		}, { Ui.corner(5), Ui.stroke(Color3.fromRGB(20, 60, 130), 2) })
		local _ = track
		bar.MouseButton1Down:Connect(function(x: number)
			dragging = { bar = bar, name = name }
			setFromX(bar, name, x)
		end)
		table.insert(refreshers, function()
			local v = Prefs.get(name)
			value.Text = format(v)
			knob.Position = UDim2.fromScale((v - spec[2]) / (spec[3] - spec[2]), 0.5)
		end)
	end
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local d = dragging
		if d and input.UserInputType == Enum.UserInputType.MouseMovement then
			setFromX(d.bar, d.name, input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = nil
		end
	end)

	-- On / Off: two halves, the chosen one lit, like a broadcast switch.
	local function toggleRow(parent: Instance, label: string, name: string, hint: string?)
		remember(parent, name)
		local area = controlArea(row(parent, label, hint))
		local halves: { TextButton } = {}
		for i, text in { "On", "Off" } do
			halves[i] = Ui.button(text, {
				Position = UDim2.fromScale((i - 1) * 0.5, 0),
				Size = UDim2.fromScale(0.5, 1),
				TextSize = 18,
				Font = Ui.Theme.BodyFont,
				BackgroundColor3 = PICKED,
				Parent = area,
			}, function()
				Prefs.set(name, i == 1)
			end)
			squareCorners(halves[i])
		end
		table.insert(refreshers, function()
			local on = Prefs.get(name) == true
			halves[1].BackgroundTransparency = if on then 0 else 1
			halves[2].BackgroundTransparency = if on then 1 else 0
		end)
	end

	-- A choice stored as a number: click the left half for the previous one, right for the next.
	local function choiceRow(parent: Instance, label: string, name: string, count: number, show: (number) -> (string, Color3?), hint: string?)
		remember(parent, name)
		local area = controlArea(row(parent, label, hint))
		local face: TextButton = Ui.button("", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, 0, 0, 34),
			TextSize = 17,
			Font = BLACK,
			BackgroundColor3 = BUTTON,
			Parent = area,
		}, function() end)
		face.Activated:Connect(function(input: InputObject?)
			local x = if input then input.Position.X else face.AbsolutePosition.X + face.AbsoluteSize.X
			local dir = if x < face.AbsolutePosition.X + face.AbsoluteSize.X / 2 then -1 else 1
			local v = (Prefs.get(name) - 1 + dir) % count + 1
			Prefs.set(name, v)
		end)
		Ui.corner(6).Parent = face
		for i, arrow in { "<", ">" } do
			Ui.label(arrow, 22, BLACK, WHITE, {
				AnchorPoint = Vector2.new(if i == 1 then 0 else 1, 0.5),
				Position = UDim2.new(if i == 1 then 0 else 1, if i == 1 then 10 else -10, 0.5, 0),
				Size = UDim2.fromOffset(20, 30),
				Parent = face,
			})
		end
		local faceStroke = Ui.stroke(WHITE, 2, 0.6)
		faceStroke.Parent = face
		table.insert(refreshers, function()
			local text, color = show(Prefs.get(name))
			face.Text = string.upper(text)
			if color then
				face.BackgroundColor3 = color
				local light = color.R * 0.3 + color.G * 0.59 + color.B * 0.11 > 0.6
				face.TextColor3 = if light then INK else WHITE
			else
				face.BackgroundColor3 = BUTTON
				face.TextColor3 = WHITE
			end
		end)
	end
	local function colorChoice(i: number): (string, Color3?)
		local c = SettingsDef.Colors[i] or SettingsDef.Colors[1]
		return c[1], c[2]
	end
	local function buttonRow(parent: Instance, label: string, text: string, onClick: () -> ())
		local area = controlArea(row(parent, label))
		local b = Ui.button(text, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(190, 36),
			TextSize = 17,
			Font = BLACK,
			BackgroundColor3 = BUTTON,
			Parent = area,
		}, onClick)
		Ui.corner(6).Parent = b
		Ui.stroke(WHITE, 2, 0.6).Parent = b
	end
	local function note(parent: Instance, text: string)
		Ui.label(text, 14, Ui.Theme.BodyFont, Color3.fromRGB(205, 220, 250), {
			Size = UDim2.new(1, -8, 0, 40),
			TextWrapped = true,
			LayoutOrder = nextOrder(parent),
			Parent = parent,
		})
	end
	local function pct(v: number): string
		return `{math.round(v * 100)}`
	end
	local function one(v: number): string
		return string.format("%.1f", v)
	end
	local function two(v: number): string
		return string.format("%.2f", v)
	end
	local function whole(v: number): string
		return tostring(math.round(v))
	end

	local general = page(1, "general", "GENERAL")
	section(general, "GAMEPLAY")
	numberRow(general, "Mouse sensitivity", "sensitivity", one, "How far the stick turns per mouse movement")
	numberRow(general, "Controller deadzone", "deadzone", two)
	numberRow(general, "Zoom sensitivity", "zoomStep", two, "Zoom per mouse-wheel notch")
	toggleRow(general, "Controls match camera", "matchCamera", "Up on the keys follows the flipped camera")
	toggleRow(general, "Toggle puck lift", "toggleLoft", "Press once to open the blade, again to close it")
	toggleRow(general, "Invert stick spin", "invertSpin")
	section(general, "VISUALS")
	choiceRow(general, "Stick highlight color", "stickColor", #SettingsDef.Colors, colorChoice)
	choiceRow(general, "Puck highlight color", "puckColor", #SettingsDef.Colors, colorChoice)
	toggleRow(general, "Puck outline", "puckOutline", "Outline the puck all the time, not only when hidden")
	choiceRow(general, "Puck trail color (Ground)", "trailGround", #SettingsDef.Colors, colorChoice)
	choiceRow(general, "Puck trail color (Air)", "trailAir", #SettingsDef.Colors, colorChoice)
	toggleRow(general, "High-contrast puck", "highContrast")
	section(general, "MINIMAP")
	toggleRow(general, "Display minimap", "minimap")
	numberRow(general, "Minimap scale", "minimapScale", one)
	section(general, "HUD")
	numberRow(general, "UI size", "uiScale", two, "Every menu and the HUD")
	numberRow(general, "Stamina bar scale", "meterScale", one)
	numberRow(general, "Stamina bar opacity", "meterOpacity", one)
	toggleRow(general, "Display score bug", "scoreBug", "The game score and time at the top")
	toggleRow(general, "Display FPS", "showFps")
	toggleRow(general, "Display ping", "showPing")

	local cameraPage = page(2, "camera", "CAMERA")
	section(cameraPage, "CAMERA")
	numberRow(cameraPage, "Field of view", "fov", one)
	numberRow(cameraPage, "Camera height", "camHeight", one)
	numberRow(cameraPage, "Camera distance", "camBack", one, "How far behind your skater")
	numberRow(cameraPage, "Camera look-ahead", "camAhead", one, "How far up the ice it looks")
	numberRow(cameraPage, "Camera flip speed", "flipTime", function(v: number): string
		return if v < 0.01 then "Instant" else string.format("%.2fs", v)
	end, "How long the flip takes: instant up to half a second")
	toggleRow(cameraPage, "Camera smoothing", "camSmooth")
	numberRow(cameraPage, "Follow speed", "follow", one, "With smoothing on")
	numberRow(cameraPage, "Zoom", "zoom", two)
	buttonRow(cameraPage, "Zoom", "RESET ZOOM", function()
		Prefs.set("zoom", SettingsDef.Numbers.zoom[1])
	end)
	toggleRow(cameraPage, "Camera shake", "shake", "On hits and goals")

	local arenas = page(3, "arenas", "ARENAS")
	section(arenas, "ARENA OVERRIDE")
	choiceRow(arenas, "Arena in matches", "arena", #SettingsDef.Arenas, function(i: number)
		return SettingsDef.Arenas[i] or SettingsDef.Arenas[1], nil
	end, "Changes only what you see; every rink plays the same")
	toggleRow(arenas, "Low-detail crowd", "lowGraphics", "Fewer fans for older devices")
	note(arenas, "Match default shows the arena the match is played in.")

	local social = page(4, "social", "SOCIAL")
	section(social, "NAMEPLATES")
	toggleRow(social, "Name tags", "nameTags")
	toggleRow(social, "Display own name tag", "ownName")
	numberRow(social, "Nameplate size", "nameSize", two)
	section(social, "INDICATORS")
	toggleRow(social, "Display team indicators", "teamRings", "Coloured rings under other skaters")
	toggleRow(social, "Display own team indicator", "ownRing")

	-- Controls: a bindings table (keyboard and mouse can be changed; controller is fixed).
	local controlsPage = page(5, "controls", "CONTROLS")
	local head: Frame = Ui.new("Frame", {
		Size = UDim2.new(1, -8, 0, 44),
		BackgroundColor3 = HEADER,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(controlsPage),
		Parent = controlsPage,
	})
	for i, text in { "ACTIONS", "KEYBOARD / MOUSE", "CONTROLLER" } do
		Ui.label(text, 18, BLACK, WHITE, {
			Position = UDim2.new(({ 0, 0.42, 0.74 })[i], if i == 1 then 24 else 0, 0, 0),
			Size = UDim2.new(if i == 1 then 0.4 else 0.28, 0, 1, 0),
			TextXAlignment = if i == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
			Parent = head,
		})
	end
	local PAD = {
		up = "Left stick", down = "Left stick", left = "Left stick", right = "Left stick",
		lift = "RT", loft = "LB", dash = "L3", brake = "LT", flip = "RB",
		cursor = "-", reset = "-", addPuck = "-", goalie = "-", hud = "-", board = "Select",
	}
	local capturing: { id: string, button: TextButton }? = nil
	for _, action in SettingsDef.Actions do
		local order = nextOrder(controlsPage)
		local r: Frame = Ui.new("Frame", {
			Size = UDim2.new(1, -8, 0, 48),
			BackgroundColor3 = if order % 2 == 0 then ROW_LIGHT else ROW_DARK,
			BorderSizePixel = 0,
			LayoutOrder = order,
			Parent = controlsPage,
		})
		Ui.label(action.label, 18, Ui.Theme.BodyFont, WHITE, {
			Position = UDim2.fromOffset(24, 0),
			Size = UDim2.new(0.4, -24, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = r,
		})
		local b: TextButton
		b = Ui.button("", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.58, 0.5),
			Size = UDim2.new(0.26, 0, 0, 36),
			TextSize = 16,
			Font = Ui.Theme.BoldFont,
			BackgroundColor3 = Color3.fromRGB(70, 96, 120),
			Parent = r,
		}, function()
			if capturing then
				return
			end
			capturing = { id = action.id, button = b }
			b.Text = "PRESS A KEY..."
			b.TextColor3 = GOLD
		end)
		Ui.corner(4).Parent = b
		Ui.label(PAD[action.id] or "-", 16, Ui.Theme.BoldFont, Color3.fromRGB(200, 214, 240), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.87, 0.5),
			Size = UDim2.new(0.22, 0, 0, 36),
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.fromRGB(34, 46, 60),
			Parent = r,
		})
		table.insert(refreshers, function()
			if not (capturing and capturing.id == action.id) then
				b.Text = Prefs.label(action.id)
				b.TextColor3 = WHITE
			end
		end)
	end
	note(controlsPage, "Click a key, then press the new key or mouse button. Esc cancels. Esc itself always opens the Roblox menu.")
	UserInputService.InputBegan:Connect(function(input: InputObject)
		local c = capturing
		if not c then
			return
		end
		local t = input.UserInputType
		local bind: string? = nil
		if t == Enum.UserInputType.Keyboard then
			if input.KeyCode == Enum.KeyCode.Escape then
				capturing = nil
				refreshAll()
				return
			end
			bind = input.KeyCode.Name
		elseif t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.MouseButton3 then
			bind = t.Name
		end
		if bind and SettingsDef.validBind(bind) then
			capturing = nil
			Prefs.setBind(c.id, bind)
			refreshAll()
		end
	end)

	local video = page(6, "video", "VIDEO")
	section(video, "GRAPHICS")
	toggleRow(video, "Shadows", "shadows")
	toggleRow(video, "Bloom", "bloom", "Soft glow on bright lights")
	toggleRow(video, "Color grading", "grade", "Richer contrast and colour")
	toggleRow(video, "Reduced particles", "reduceParticles", "Fewer sparks, trails and confetti")
	toggleRow(video, "Low-detail crowd", "lowGraphics")

	local audio = page(7, "audio", "AUDIO")
	section(audio, "AUDIO")
	numberRow(audio, "Master volume", "volume", pct)
	numberRow(audio, "Game volume", "sfxVolume", pct, "Stick, puck, boards and checks")
	numberRow(audio, "Crowd volume", "crowdVolume", pct)
	numberRow(audio, "Goal horn volume", "hornVolume", pct)

	-- Bottom buttons, as in the reference: reset, cancel, save.
	local snapshot: any = nil
	settings:GetPropertyChangedSignal("Visible"):Connect(function()
		if settings.Visible then
			snapshot = Prefs.snapshot()
			capturing = nil
			refreshAll()
		end
	end)
	local function bottom(text: string, x: number, width: number, filled: boolean, onClick: () -> ())
		local b = Ui.button(text, {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, x, 1, -14),
			Size = UDim2.fromOffset(width, 40),
			TextSize = 18,
			Font = BLACK,
			BackgroundColor3 = if filled then WHITE else NAV_DARK,
			TextColor3 = if filled then BUTTON else WHITE,
			Parent = settings,
		}, onClick)
		Ui.corner(6).Parent = b
		Ui.stroke(WHITE, 2).Parent = b
	end
	bottom("SAVE", -18, 140, true, function()
		Menu.back()
	end)
	bottom("CANCEL", -172, 140, false, function()
		if snapshot then
			Prefs.restore(snapshot)
		end
		Menu.back()
	end)
	-- Only the page you're on: its settings, or the key bindings on CONTROLS.
	bottom("RESET TO DEFAULTS", -326, 230, false, function()
		local page = pages[shownPage]
		capturing = nil
		Prefs.resetSome(if page then pageSettings[page] or {} else {}, shownPage == "controls")
	end)

	showPage("general")
	refreshAll()
	Prefs.onChanged(function()
		refreshAll()
		if howLabel then
			howLabel.Text = howToPlay()
		end
	end)
end

-- Panels opened from inside another tab light that tab.
local NAV_OWNER: { [string]: string } = { Locker = "Player", Stats = "Player", HowToPlay = "Player", Rank = "Player" }

-- The Rank panel: emblem, ELO, progress to the next rank and any season titles.
local function redrawRank()
	local view = rankView
	if not view or not profile then
		return
	end
	local elo = profile.elo or Rank.START
	local index = Rank.index(elo)
	if index ~= rankBadgeIndex then
		rankBadgeIndex = index
		view.badge:ClearAllChildren()
		RankBadge.draw(view.badge, index)
	end
	view.name.Text = Rank.name(index)
	for i, st in view.strokes do
		st.Transparency = if i == index then 0 else 1
	end
	view.elo.Text = `{elo} ELO`
	if index >= Rank.COUNT then
		view.fill.Size = UDim2.fromScale(1, 1)
		view.next.Text = "TOP RANK"
	else
		local from, to = Rank.floorOf(index), Rank.floorOf(index + 1)
		view.fill.Size = UDim2.fromScale(math.clamp((elo - from) / math.max(1, to - from), 0, 1), 1)
		view.next.Text = `NEXT: {Rank.name(index + 1)} AT {to}`
	end
	local titles = {}
	for id, titleIndex in profile.titles or {} do
		local season = SeasonPass.ById[id]
		local seasonName = if season then string.split(season.name, " - ")[1] else id
		table.insert(titles, `{seasonName} {Rank.name(titleIndex)}`)
	end
	table.sort(titles)
	view.titles.Text = if #titles > 0 then "SEASON TITLES:  " .. table.concat(titles, "   ·   ")
		else "SEASON TITLES: none yet. When a season ends, the rank you hold becomes a title you keep."
end

-- The home column's daily challenges (they change at 00:00 UTC).
local function redrawChallenges()
	local c = profile and profile.challenges
	if not c or not challengeReset then
		return
	end
	-- Counted down against the server clock, so it stays right however long the menu is open.
	local secs = if c.resetsAt then c.resetsAt - workspace:GetServerTimeNow() else (c.resetsIn or 0)
	secs = math.max(0, secs)
	local hours, mins = math.floor(secs / 3600), math.floor(secs % 3600 / 60)
	challengeReset.Text = `NEW IN {hours}H {mins}M  ·  +{c.reward or 200} {c.rewardUnit or "COINS"} EACH`
	for i, cell in challengeCells do
		local ch = c.list and c.list[i]
		cell.cell.Visible = ch ~= nil
		if ch then
			if cell.id ~= ch.id then
				cell.pending = false
			end
			cell.id = ch.id
			local canCollect = ch.done and not ch.claimed
			cell.text.Text = ch.text
			cell.fill.Size = UDim2.fromScale(math.clamp(ch.progress / math.max(1, ch.target), 0, 1), 1)
			cell.fill.BackgroundColor3 = if ch.done then Color3.fromRGB(90, 220, 120) else GOLD
			cell.count.Text = if ch.claimed then "DONE" elseif ch.done then "" else `{ch.progress}/{ch.target}`
			cell.count.TextColor3 = if ch.done then Color3.fromRGB(150, 255, 170) else Color3.fromRGB(214, 228, 255)
			cell.count.Visible = not canCollect
			cell.bar.Size = if canCollect then UDim2.new(1, -96, 0, 7) else UDim2.new(1, -58, 0, 7)
			cell.collect.Visible = canCollect
			if canCollect and not cell.pending then
				cell.collect.Text = "COLLECT"
			end
		end
	end
end

-- Build 32: the server's answer to a Collect press. On success a "+200 COINS" pops up off the
-- card and floats away; the profile push that follows redraws the card as collected.
function Menu.challengeClaimed(id: any, ok: boolean, amount: number, unit: string)
	for _, cell in challengeCells do
		if cell.id == id then
			cell.pending = false
			if not ok then
				cell.collect.Text = "COLLECT"
				return
			end
			cell.collect.Visible = false
			cell.count.Visible = true
			cell.count.Text = "DONE"
			cell.bar.Size = UDim2.new(1, -58, 0, 7)
			local pop = Ui.label(`+{amount} {unit}`, 18, BLACK, GOLD, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				Size = UDim2.fromOffset(160, 24),
				ZIndex = 10,
				TextStrokeTransparency = 0.2,
				TextStrokeColor3 = Color3.fromRGB(70, 40, 0),
				Parent = cell.cell,
			})
			local scale = Instance.new("UIScale")
			scale.Scale = 0.4
			scale.Parent = pop
			TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.15 }):Play()
			task.delay(0.35, function()
				TweenService:Create(pop, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.new(0.5, 0, 0.5, -46),
					TextTransparency = 1,
					TextStrokeTransparency = 1,
				}):Play()
			end)
			task.delay(1.4, function()
				pop:Destroy()
			end)
			return
		end
	end
end

-- The reset countdown ticks over while the home screen is up.
task.spawn(function()
	while true do
		task.wait(20)
		if home and home.Visible then
			redrawChallenges()
		end
	end
end)

local function paintNav(active: string)
	active = NAV_OWNER[active] or active
	for id, b in navTabs do
		local on = id == active
		b.BackgroundColor3 = if on then NAV:Lerp(WHITE, 0.16) else NAV
		b.BackgroundTransparency = if on then 0 else 1
	end
end

local openPanel: string? = nil

function Menu.open(name: string)
	closeShopItem()
	openPanel = name
	paintNav(name)
	if promo then
		promo.Visible = false
	end
	if name == "HowToPlay" and howLabel then
		howLabel.Text = howToPlay()
	end
	for _, frame in panels do
		frame.Visible = false
	end
	local frame = panels[name]
	if not frame then
		return
	end
	-- Locker and Shop keep the home column so the skater is framed between them.
	home.Visible = false
	if name == "Locker" then
		redrawLocker()
	elseif name == "Shop" then
		redrawShop()
		local jump = shopScrollTo
		local target = shopJump
		shopJump = nil
		if jump and target then
			task.defer(jump, target)
		elseif shopGrid then
			shopGrid.CanvasPosition = Vector2.zero
		end
	elseif name == "Pass" then
		redrawPass()
	elseif name == "Stats" then
		redrawStats(true)
		-- Build 36: slides in from the right while the camera zooms in on the skater.
		local final = UDim2.new(1, -40, 0.54, 0) -- where panelFrame put it (fixed, so a quick re-open never drifts)
		frame.Position = final + UDim2.fromOffset(160, 0)
		TweenService:Create(frame, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = final }):Play()
	elseif name == "Rankings" then
		redrawRankings()
	elseif name == "Rank" then
		redrawRank()
	end
	Ui.fadeIn(frame)
	callbacks.onPreviewLook(currentLook())
	callbacks.onPanel(name)
	-- A controller lands on the new page, not on a button that just went away.
	if UserInputService.GamepadEnabled then
		pcall(function()
			GuiService:Select(frame)
		end)
	end
end

-- BACK on a panel goes one step back: a panel opened from a tab's column (Locker, Rank, Career
-- Stats, How to Play from PLAYER) returns to that column; a top-level panel returns home. From
-- the in-game menu it returns to the game.
function Menu.back()
	local close = overlayClose
	if close then
		Menu.closeSettingsOverlay()
		close()
		return
	end
	local owner = openPanel and NAV_OWNER[openPanel]
	if owner and owner ~= openPanel and panels[owner] then
		Menu.open(owner)
	else
		Menu.showHome()
	end
end

-- Shows the full Settings panel over the game (keys, camera, controls, UI size, everything
-- the lobby has). `onClose` runs when the player presses BACK.
function Menu.openSettingsOverlay(parent: Instance, onClose: () -> ())
	local frame = panels.Settings
	overlayClose = onClose
	frame.Parent = parent
	Ui.fadeIn(frame)
end

function Menu.closeSettingsOverlay()
	local frame = panels.Settings
	if overlayClose then
		overlayClose = nil
		frame.Visible = false
		frame.Parent = root
	end
end

function Menu.showHome()
	closeShopItem()
	openPanel = nil
	for _, frame in panels do
		frame.Visible = false
	end
	home.Visible = true
	paintNav("Home")
	if promo then
		promo.Visible = promoFits
		refreshPromo()
	end
	callbacks.onPreviewLook(currentLook())
	callbacks.onPanel(nil)
end

function Menu.setProfile(p: any)
	profile = p
	coinLabel.Text = tostring(p.coins)
	levelLabel.Text = `Lv. {p.level}`
	nameLabel.Text = string.upper(game:GetService("Players").LocalPlayer.DisplayName)
	for key, label in careerLabels do
		label.Text = tostring((p.stats and p.stats[key]) or 0)
	end
	-- The rank emblem by the name.
	local index = Rank.index(p.elo or Rank.START)
	if topBadge and index ~= topBadgeIndex then
		topBadgeIndex = index
		for _, child in topBadge:GetChildren() do
			if child.Name == "RankBadge" then
				child:Destroy()
			end
		end
		RankBadge.draw(topBadge, index, 7)
	end
	redrawChallenges()
	-- Tutorial: top of the column with its reward until it's done, then a quiet replay below.
	tutorialDone = p.tutorialDone == true
	if tutorialButton and tutorialSub then
		tutorialButton.LayoutOrder = if tutorialDone then 4 else 0
		tutorialSub.Text = if tutorialDone then "Replay the drills" else "Learn to play. Win the Golden Comet stick!"
	end
	refreshPromo()
	Menu.offerFirstGame() -- a returning player whose save arrives with the menu already up
	if panels.Rank and panels.Rank.Visible then
		redrawRank()
	end
	xpFill.Size = UDim2.fromScale(math.clamp(p.xp / math.max(1, p.xpNext), 0, 1), 1)
	statusLabel.Text = if p.status == "loading" then "Loading your profile..."
		elseif p.status == "temporary" then "Progress not saving this session"
		else ""
	if panels.Locker.Visible then
		redrawLocker()
	end
	if panels.Shop.Visible then
		redrawShop()
	end
	if panels.Pass.Visible then
		redrawPass()
	end
	callbacks.onPreviewLook(p.look)
	if panels.Stats.Visible then
		redrawStats()
	end
end

function Menu.show()
	Menu.closeSettingsOverlay()
	root.Visible = true
	Menu.showHome()
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = if tutorialButton and not tutorialDone then tutorialButton else playButton
	end
	local ids = pendingFirstGame
	if ids then
		pendingFirstGame = nil
		firstGameReveal(ids)
	else
		Menu.offerFirstGame()
	end
end

-- A stand-alone 3D preview of a catalog item (the tutorial reward screen shows the stick).
function Menu.previewFor(id: string): ViewportFrame?
	local item = Catalog.ById[id]
	return if item then buildPreview(item) else nil
end

-- Gamepad (vault: "Gamepad and Console UX"): B goes back a step, LB / RB walk the top tabs.
local TAB_ORDER = { "Home", "Player", "Rankings", "Shop", "Pass" }

local function selectIn(frame: Instance?)
	if not UserInputService.GamepadEnabled then
		return
	end
	if frame == nil then
		GuiService.SelectedObject = if tutorialButton and not tutorialDone then tutorialButton else playButton
		return
	end
	pcall(function()
		GuiService:Select(frame)
	end)
end

-- Returns true if B was used (a page closed or the menu went back a step).
function Menu.padBack(): boolean
	if overlayClose then
		Menu.back()
		return true
	end
	if not root.Visible then
		return false
	end
	if itemPageId then
		closeShopItem()
		selectIn(panels.Shop)
		return true
	end
	if boxPage and boxPage.Visible then
		closeBoxPage()
		selectIn(panels.Shop)
		return true
	end
	if openPanel then
		Menu.back()
		selectIn(if openPanel then panels[openPanel] else nil)
		return true
	end
	return false
end

function Menu.cycleTab(dir: number)
	if not root.Visible or overlayClose then
		return
	end
	local current = NAV_OWNER[openPanel or "Home"] or openPanel or "Home"
	local index = table.find(TAB_ORDER, current) or 1
	local nextTab = TAB_ORDER[(index - 1 + dir) % #TAB_ORDER + 1]
	if nextTab == "Home" then
		Menu.showHome()
		selectIn(nil)
	else
		Menu.open(nextTab)
		selectIn(panels[nextTab])
	end
end

function Menu.hide()
	root.Visible = false
	GuiService.SelectedObject = nil
end

function Menu.isVisible(): boolean
	return root.Visible
end

return Menu
