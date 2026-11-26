-- MYSTERY BOX (client): the glittery gift button under SHOP, the odds window and the opening.
-- The server decides everything (Services.ShopService: boxInfo / openBox / ProcessReceipt);
-- this script only shows it. Odds are always on screen before a player can buy.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local root = RS:WaitForChild("Clamillion")
local Remotes = root:WaitForChild("Remotes")
local Shared = root:WaitForChild("Shared")
local UI = require(Shared:WaitForChild("UIConstants"))
local Catalog = require(Shared:WaitForChild("ShopCatalog"))
local C = UI.Colors
local BOX = Catalog.MysteryBox
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local gui = player:WaitForChild("PlayerGui"):WaitForChild("ClamillionGui", 60)
if not gui then return end
local shopIcon = gui:WaitForChild("ShopIcon", 60)

---------------------------------------------------------------- tiny UI kit (matches the game's style)
local function make(class, props, children)
	local inst = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do if k == "Parent" then parent = v else inst[k] = v end end
	for _, c in ipairs(children or {}) do c.Parent = inst end
	if parent then inst.Parent = parent end
	return inst
end
local function corner(r) return make("UICorner", { CornerRadius = UDim.new(0, r or 12) }) end
local function round() return make("UICorner", { CornerRadius = UDim.new(1, 0) }) end
local function stroke(color, t) return make("UIStroke", { Color = color or C.Outline, Thickness = t or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) end
local function textStroke(color, t) return make("UIStroke", { Color = color or C.Outline, Thickness = t or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }) end
local function grad(a, b, rot) return make("UIGradient", { Color = ColorSequence.new(a, b), Rotation = rot or 90 }) end
local function text(props, max, outline)
	local p = { BackgroundTransparency = 1, TextColor3 = C.White, Font = UI.FontBlack, TextScaled = true, TextWrapped = true, Text = "" }
	for k, v in pairs(props) do p[k] = v end
	local l = make("TextLabel", p, { make("UITextSizeConstraint", { MaxTextSize = max or 24, MinTextSize = 8 }) })
	if outline ~= false then textStroke(C.Outline, (max or 24) >= 30 and 3 or 1.8).Parent = l end
	return l
end
local function candyButton(props, top, bottom, ink, max)
	local p = { BackgroundColor3 = C.White, AutoButtonColor = false, Font = UI.FontBlack, TextScaled = true, TextColor3 = ink or C.Ink, Text = "" }
	for k, v in pairs(props) do p[k] = v end
	local b = make("TextButton", p, { corner(18), stroke(C.Outline, 3), make("UITextSizeConstraint", { MaxTextSize = max or 26 }), make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }), grad(top, bottom) })
	if ink == C.White then textStroke(C.Outline, 2).Parent = b end
	local sc = make("UIScale", { Parent = b })
	b.MouseEnter:Connect(function() TweenService:Create(sc, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1.06 }):Play() end)
	b.MouseLeave:Connect(function() TweenService:Create(sc, TweenInfo.new(0.15), { Scale = 1 }):Play() end)
	b.MouseButton1Down:Connect(function() TweenService:Create(sc, TweenInfo.new(0.08), { Scale = 0.93 }):Play() end)
	b.MouseButton1Up:Connect(function() TweenService:Create(sc, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play() end)
	return b
end

-- a little gift box drawn with frames: box, lid, ribbons and a bow (size = a Frame to draw into)
local BOX_TOP, BOX_BOTTOM = rgb(190, 90, 255), rgb(110, 40, 220)
local RIBBON_TOP, RIBBON_BOTTOM = rgb(255, 230, 90), rgb(255, 160, 30)
local function drawGift(holder, z)
	z = z or 1
	local body = make("Frame", { Name = "Body", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(0.78, 0.58), BackgroundColor3 = C.White, ZIndex = z, Parent = holder }, { corner(6), stroke(C.Outline, 2), grad(BOX_TOP, BOX_BOTTOM) })
	make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.2, 1), BackgroundColor3 = C.White, BorderSizePixel = 0, ZIndex = z + 1, Parent = body }, { grad(RIBBON_TOP, RIBBON_BOTTOM) })
	local lid = make("Frame", { Name = "Lid", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromScale(0.92, 0.2), BackgroundColor3 = C.White, ZIndex = z + 2, Parent = holder }, { corner(6), stroke(C.Outline, 2), grad(rgb(220, 130, 255), BOX_TOP) })
	make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.18, 1), BackgroundColor3 = C.White, BorderSizePixel = 0, ZIndex = z + 3, Parent = lid }, { grad(RIBBON_TOP, RIBBON_BOTTOM) })
	-- the bow: two loops + a knot sitting on the lid
	for _, s in ipairs({ -1, 1 }) do
		make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5 + s * 0.13, 0, 0, 2), Size = UDim2.fromScale(0.3, 0.9), Rotation = s * 28, BackgroundColor3 = C.White, ZIndex = z + 2, Parent = lid }, { round(), stroke(C.Outline, 2), grad(RIBBON_TOP, RIBBON_BOTTOM) })
	end
	make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromScale(0.17, 0.75), BackgroundColor3 = C.White, ZIndex = z + 4, Parent = lid }, { round(), stroke(C.Outline, 2), grad(rgb(255, 245, 160), RIBBON_BOTTOM) })
	-- a question mark on the front
	text({ Text = "?", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.27, 0.55), Size = UDim2.fromScale(0.3, 0.6), ZIndex = z + 2, Parent = body }, 60)
	text({ Text = "?", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.73, 0.55), Size = UDim2.fromScale(0.3, 0.6), ZIndex = z + 2, Parent = body }, 60)
	return body, lid
end
-- twinkling glitter stars scattered over an area
local function glitter(holder, count, z, sizePx)
	local stars = {}
	for i = 1, count do
		local s = text({ Text = (i % 3 == 0) and "✨" or "✦", TextColor3 = (i % 2 == 0) and rgb(255, 245, 170) or C.White, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(math.random(), math.random()), Size = UDim2.fromOffset(sizePx, sizePx), ZIndex = z, Parent = holder }, sizePx, false)
		table.insert(stars, { label = s, phase = math.random() * 10, speed = 1.5 + math.random() * 2 })
	end
	return stars
end
local sparkleSets = {}

---------------------------------------------------------------- the button under SHOP
local btn = make("TextButton", { Name = "MysteryBoxIcon", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 62), Size = UDim2.fromOffset(96, 112),
	Rotation = 3, BackgroundColor3 = C.White, Text = "", AutoButtonColor = false, BorderSizePixel = 0, Parent = gui },
	{ corner(22), make("UIStroke", { Color = C.White, Thickness = 3.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }), grad(rgb(255, 110, 220), rgb(120, 50, 230)) })
local gloss = make("Frame", { Position = UDim2.new(0, 4, 0, 3), Size = UDim2.new(1, -8, 0.42, 0), BackgroundColor3 = C.White, BorderSizePixel = 0, Parent = btn }, { corner(18) })
make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }), Parent = gloss })
local shine = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.White, BorderSizePixel = 0, ZIndex = 4, Parent = btn }, { corner(22) })
local shineGrad = make("UIGradient", { Rotation = 25, Offset = Vector2.new(-1, 0), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1), NumberSequenceKeypoint.new(0.5, 0.4), NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1) }), Parent = shine })
local iconHolder = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(62, 58), ZIndex = 2, Parent = btn })
local iconBody, iconLid = drawGift(iconHolder, 2)
table.insert(sparkleSets, glitter(btn, 7, 5, 14))
text({ Text = "MYSTERY\nBOX", Position = UDim2.new(0, 4, 0, 66), Size = UDim2.new(1, -8, 0, 38), ZIndex = 3, Parent = btn }, 17).UIStroke.Color = rgb(90, 20, 140)
local priceTag = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -8, 0, 6), Size = UDim2.fromOffset(46, 24), Rotation = 12, BackgroundColor3 = C.White, ZIndex = 6, Parent = btn }, { corner(12), stroke(C.White, 2), grad(rgb(255, 90, 150), rgb(230, 40, 110)) })
text({ Text = "R$" .. BOX.price, Size = UDim2.fromScale(1, 1), ZIndex = 7, Parent = priceTag }, 14)
local btnScale = make("UIScale", { Parent = btn })
btn.MouseEnter:Connect(function()
	TweenService:Create(btnScale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1.1 }):Play()
	shineGrad.Offset = Vector2.new(-1, 0); TweenService:Create(shineGrad, TweenInfo.new(0.6), { Offset = Vector2.new(1, 0) }):Play()
end)
btn.MouseLeave:Connect(function() TweenService:Create(btnScale, TweenInfo.new(0.15), { Scale = 1 }):Play() end)
btn.MouseButton1Down:Connect(function() TweenService:Create(btnScale, TweenInfo.new(0.08), { Scale = 0.9 }):Play() end)
btn.MouseButton1Up:Connect(function() TweenService:Create(btnScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play() end)
-- only in the lobby, exactly when the SHOP button is showing
local function syncVisible() btn.Visible = shopIcon.Visible end
shopIcon:GetPropertyChangedSignal("Visible"):Connect(syncVisible)
syncVisible()

---------------------------------------------------------------- the window
local shade = make("Frame", { Name = "MysteryBox", Active = true, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 30, Parent = gui })
local card = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.92, 0.9), BackgroundColor3 = C.White, ZIndex = 31, Parent = shade },
	{ corner(22), stroke(C.White, 4), grad(rgb(150, 70, 240), rgb(255, 90, 190), 120), make("UISizeConstraint", { MaxSize = Vector2.new(720, 560) }), make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14) }) })
local title = text({ Text = "🎁 MYSTERY BOX 🎁", TextColor3 = C.Gold, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -2), Size = UDim2.new(1, -100, 0, 40), ZIndex = 32, Parent = card }, 34)
local close = candyButton({ Text = "X", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 4, 0, -4), Size = UDim2.fromOffset(42, 42), ZIndex = 33, Parent = card }, C.PanelPink, rgb(230, 50, 140), C.White, 20)
close.Activated:Connect(function() shade.Visible = false end)
shade.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
	local p, a, s = input.Position, card.AbsolutePosition, card.AbsoluteSize
	if p.X < a.X or p.X > a.X + s.X or p.Y < a.Y or p.Y > a.Y + s.Y then shade.Visible = false end
end)

-- left: the big glittering gift + the OPEN button
local left = make("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 46), Size = UDim2.new(0.46, -8, 1, -46), ZIndex = 32, Parent = card })
local stage = make("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.78, Size = UDim2.new(1, 0, 1, -128), ClipsDescendants = true, ZIndex = 32, Parent = left }, { corner(18) })
local rays = make("ImageLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromScale(1.6, 1.6), SizeConstraint = Enum.SizeConstraint.RelativeYY,
	Image = "rbxasset://textures/ui/LuaApp/graphic/shimmer_darkTheme.png", ImageTransparency = 1, ZIndex = 32, Parent = stage })
local burst = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromScale(0.7, 0.7), SizeConstraint = Enum.SizeConstraint.RelativeYY, BackgroundColor3 = rgb(255, 240, 160), BackgroundTransparency = 0.55, ZIndex = 32, Parent = stage }, { round() })
make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }), Parent = burst })
local giftHolder = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.56), Size = UDim2.fromScale(0.62, 0.62), SizeConstraint = Enum.SizeConstraint.RelativeYY, ZIndex = 33, Parent = stage })
local giftBody, giftLid = drawGift(giftHolder, 34)
table.insert(sparkleSets, glitter(stage, 18, 40, 22))
local giftScale = make("UIScale", { Parent = giftHolder })
-- the prize reveal (hidden until a box opens)
local reveal = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 45, Parent = stage })
local revealIcon = text({ Text = "", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromScale(0.5, 0.42), ZIndex = 46, Parent = reveal }, 90, false)
local revealKind = text({ Text = "", TextColor3 = C.Gold, Position = UDim2.fromScale(0.05, 0.6), Size = UDim2.fromScale(0.9, 0.12), ZIndex = 46, Parent = reveal }, 22)
local revealName = text({ Text = "", Position = UDim2.fromScale(0.05, 0.72), Size = UDim2.fromScale(0.9, 0.18), ZIndex = 46, Parent = reveal }, 34)
local revealScale = make("UIScale", { Parent = reveal })

local openBtn = candyButton({ Text = "🎁 OPEN  •  R$ " .. BOX.price, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -56), Size = UDim2.new(1, 0, 0, 58), ZIndex = 33, Parent = left }, C.Gold, rgb(255, 150, 20), C.Ink, 28)
local equipBtn = candyButton({ Text = "EQUIP IT!", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -56), Size = UDim2.new(1, 0, 0, 58), Visible = false, ZIndex = 34, Parent = left }, C.Good, rgb(30, 180, 90), C.Ink, 28)
local note = text({ Text = "", Font = UI.FontBody, TextColor3 = C.White, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, 0, 0, 48), ZIndex = 33, Parent = left }, 16)

-- right: the odds, always visible before buying
local right = make("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.78, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 46), Size = UDim2.new(0.54, -8, 1, -46), ZIndex = 32, Parent = card }, { corner(18) })
text({ Text = "🎲 YOUR ODDS", TextColor3 = C.Gold, Position = UDim2.new(0, 10, 0, 6), Size = UDim2.new(1, -20, 0, 26), ZIndex = 33, Parent = right }, 22)
local oddsNote = text({ Text = "Never a duplicate: you only get things you don't own yet!", Font = UI.FontBody, Position = UDim2.new(0, 10, 0, 32), Size = UDim2.new(1, -20, 0, 20), ZIndex = 33, Parent = right }, 14)
local list = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.new(0, 6, 0, 56), Size = UDim2.new(1, -12, 1, -62), ScrollBarThickness = 7, ScrollBarImageColor3 = C.Gold,
	AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 33, Parent = right })
make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
make("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6), Parent = list })

local CAT_COLORS = { Arena = { rgb(255, 200, 60), rgb(255, 130, 30) }, Podium = { rgb(255, 120, 200), rgb(200, 60, 160) }, Title = { rgb(90, 200, 255), rgb(60, 110, 230) }, Emote = { rgb(120, 230, 150), rgb(30, 170, 100) }, Hint = { rgb(255, 240, 120), rgb(240, 180, 30) } }
local function pctText(x)
	if x >= 10 then return ("%.0f%%"):format(x) end
	if x >= 1 then return ("%.1f%%"):format(x) end
	return ("%.2f%%"):format(x)
end
local info -- last boxInfo from the server
local function renderOdds()
	for _, c in ipairs(list:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
	if not info then return end
	local order = 0
	for _, row in ipairs(info.odds or {}) do
		order += 1
		local cols = CAT_COLORS[row.kind] or CAT_COLORS.Hint
		local head = make("Frame", { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = C.White, ZIndex = 34, Parent = list }, { corner(12), stroke(C.Outline, 2), grad(cols[1], cols[2]) })
		local label = row.icon .. "  " .. string.upper(row.kind == "Hint" and (info.hints .. " ANSWER HINTS") or (row.label .. (#row.items > 0 and " (" .. #row.items .. " left)" or "")))
		text({ Text = label, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0, 10, 0, 4), Size = UDim2.new(0.75, -10, 1, -8), ZIndex = 35, Parent = head }, 18)
		text({ Text = pctText(row.pct), TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 4), Size = UDim2.new(0.25, 0, 1, -8), ZIndex = 35, Parent = head }, 20)
		if row.complete then
			order += 1
			text({ LayoutOrder = order, Text = ("You own every %s! This %s pays out %d hints instead."):format(row.label:lower(), pctText(row.pct), info.hints), Font = UI.FontBody, TextColor3 = C.Mint, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 20), ZIndex = 34, Parent = list }, 14)
		elseif #row.items > 0 then
			local each = row.items[1].pct
			order += 1
			text({ LayoutOrder = order, Text = ("Each %s below: %s"):format(row.label:lower(), pctText(each)), Font = UI.FontBody, TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 18), ZIndex = 34, Parent = list }, 14)
			local names = {}
			for _, item in ipairs(row.items) do table.insert(names, item.icon .. " " .. item.name) end
			order += 1
			local l = text({ LayoutOrder = order, Text = table.concat(names, "   "), Font = UI.FontBody, TextScaled = false, TextSize = 14, AutomaticSize = Enum.AutomaticSize.Y, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 0), ZIndex = 34, Parent = list }, 14)
		end
	end
end

local busy = false
local lastPrize = nil
local function setNote(t, color) note.Text = t; note.TextColor3 = color or C.White end
local function showIdle()
	reveal.Visible = false; giftHolder.Visible = true; burst.BackgroundTransparency = 0.55
	giftLid.Position = UDim2.fromScale(0.5, 0.45); giftLid.Rotation = 0; giftHolder.Rotation = 0; giftScale.Scale = 1
	equipBtn.Visible = false
	openBtn.Visible = info == nil or (info.allowed and info.ready)
	if info and not info.allowed then
		setNote("Mystery Boxes aren't available for your account or region. You can still buy any item in the 🛍 SHOP!", C.Muted)
	elseif info and not info.ready then
		setNote("⏳ Mystery Boxes are coming soon!", C.Gold)
	else
		setNote(("One random prize you don't own yet! You have %d hint%s."):format(info and info.hintCredits or 0, (info and info.hintCredits == 1) and "" or "s"))
	end
end
local function refresh()
	local ok, r = pcall(function() return Remotes.ShopRequest:InvokeServer("boxInfo") end)
	if ok and type(r) == "table" then info = r end
	renderOdds()
	if not busy and not reveal.Visible then showIdle() end
end

local function ding()
	local s = SoundService:FindFirstChild("BoxReveal") or make("Sound", { Name = "BoxReveal", SoundId = "rbxassetid://71587723216424", Volume = 0.7, Parent = SoundService })
	s.TimePosition = 0; s:Play()
end
-- the opening: the box shakes harder and harder, the lid pops off, a flash, then the prize
local function playOpening(result)
	busy = true
	lastPrize = result
	openBtn.Visible = false
	setNote("Opening...", C.Gold)
	local start = os.clock()
	while os.clock() - start < 1.6 do
		local t = os.clock() - start
		local power = t / 1.6
		giftHolder.Rotation = math.sin(t * (20 + power * 30)) * (4 + power * 10)
		giftScale.Scale = 1 + power * 0.12
		burst.BackgroundTransparency = 0.55 - power * 0.4
		RunService.RenderStepped:Wait()
	end
	giftHolder.Rotation = 0
	TweenService:Create(giftLid, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, -0.45), Rotation = 25 }):Play()
	task.wait(0.25)
	giftHolder.Visible = false
	burst.BackgroundTransparency = 0
	TweenService:Create(burst, TweenInfo.new(0.8), { BackgroundTransparency = 0.5 }):Play()
	-- fill in the prize
	local item = result.id and Catalog.get(result.id)
	if item then
		revealIcon.Text = item.icon
		revealKind.Text = "YOU GOT A NEW " .. string.upper(item.kind) .. "!"
		revealName.Text = item.name
	else
		revealIcon.Text = "💡"
		revealKind.Text = result.complete and ("YOU OWN EVERY " .. string.upper(result.category or "") .. "!") or "YOU GOT"
		revealName.Text = ("%d ANSWER HINTS"):format(result.hints or BOX.hints)
	end
	reveal.Visible = true
	revealScale.Scale = 0.2
	TweenService:Create(revealScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	ding()
	for _, set in ipairs(sparkleSets) do for _, s in ipairs(set) do s.boost = os.clock() + 2 end end
	if item then
		equipBtn.Visible = true
		setNote("It's in your 🎒 MY STUFF. Open another?", C.Mint)
	else
		setNote("Hints show a Very Rare answer during a show (the HINT ? button).", C.Mint)
	end
	task.wait(0.6)
	busy = false
	openBtn.Text = "🎁 OPEN ANOTHER  •  R$ " .. BOX.price
	openBtn.Visible = info and info.allowed and info.ready
	if equipBtn.Visible then openBtn.Visible = false end
	task.spawn(refresh)
end

equipBtn.Activated:Connect(function()
	if not (lastPrize and lastPrize.id) then return end
	pcall(function() Remotes.ShopRequest:InvokeServer("equip", lastPrize.id) end)
	equipBtn.Visible = false
	openBtn.Visible = info and info.allowed and info.ready
	setNote("✨ Equipped! It shows up in your next show.", C.Mint)
end)

openBtn.Activated:Connect(function()
	if busy then return end
	if reveal.Visible then showIdle() end
	busy = true
	local ok, r = pcall(function() return Remotes.ShopRequest:InvokeServer("openBox") end)
	busy = false
	if not ok or type(r) ~= "table" then setNote("Something went wrong. Please try again!", C.Danger) return end
	if r.result then playOpening(r.result) -- Studio test box (no Developer Product yet)
	elseif r.reason == "prompted" then setNote("Waiting for your purchase...", C.Gold); busy = true
	elseif r.reason == "restricted" then info = info or {}; info.allowed = false; showIdle()
	elseif r.reason == "match" then setNote("Finish your show first!", C.Gold)
	else setNote("⏳ Mystery Boxes are coming soon!", C.Gold) end
end)
-- the purchase window closed: if they didn't buy, go back to normal
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
	if userId ~= player.UserId or productId ~= BOX.productId then return end
	if not purchased then busy = false; showIdle() end
end)
-- the server finished the purchase: play the opening
Remotes.ShopUpdate.OnClientEvent:Connect(function(_, extra)
	if type(extra) == "table" and extra.mysteryBox then
		shade.Visible = true
		if reveal.Visible then showIdle() end
		task.spawn(playOpening, extra.mysteryBox)
	end
end)

btn.Activated:Connect(function()
	shade.Visible = true
	if not busy then reveal.Visible = false; openBtn.Text = "🎁 OPEN  •  R$ " .. BOX.price end
	showIdle()
	task.spawn(refresh)
end)

---------------------------------------------------------------- motion: bobbing, wiggling lid, glitter
task.spawn(function()
	while btn.Parent do
		local t = os.clock()
		if btn.Visible then
			btn.Position = UDim2.new(1, -14, 0.5, 62 + math.sin(t * 1.8 + 1.4) * 5)
			iconHolder.Rotation = math.sin(t * 2.4) * 6
			iconLid.Position = UDim2.new(0.5, 0, 0.45, -math.max(0, math.sin(t * 3.1)) * 3)
			priceTag.Rotation = 12 + math.sin(t * 3) * 6
		end
		if shade.Visible and not busy and giftHolder.Visible then
			giftHolder.Rotation = math.sin(t * 2) * 4
			giftScale.Scale = 1 + math.sin(t * 2.6) * 0.03
			giftLid.Position = UDim2.new(0.5, 0, 0.45, -math.max(0, math.sin(t * 2.6)) * 6)
		end
		for _, set in ipairs(sparkleSets) do
			for _, s in ipairs(set) do
				local k = (math.sin(t * s.speed * ((s.boost and t < s.boost) and 3 or 1) + s.phase) + 1) / 2
				s.label.TextTransparency = 1 - k
				s.label.Rotation = (t * 40 + s.phase * 30) % 360
				if k < 0.03 then s.label.Position = UDim2.fromScale(math.random(), math.random()) end
			end
		end
		local sweep = (t % 5) / 5
		shineGrad.Offset = Vector2.new(sweep < 0.2 and (sweep / 0.2) * 2 - 1 or 1, 0)
		RunService.RenderStepped:Wait()
	end
end)
