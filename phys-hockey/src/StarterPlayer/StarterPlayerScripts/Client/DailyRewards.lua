--!strict
-- The Daily Rewards window: the 7-day login track, today's claim and the countdown to the next
-- day. It only draws what the server sends (profile.login) and asks the server to claim; the
-- server picks the day and the coins (PlayerData.claimLogin).

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Ui = require(script.Parent.Ui)

local DailyRewards = {}

export type Login = {
	track: { number },
	canClaim: boolean,
	slot: number,
	streak: number,
	needsTutorial: boolean,
	resetsAt: number,
}

export type Callbacks = {
	onClaim: () -> (),
	onTutorial: () -> (),
	onOpenChanged: (open: boolean) -> (),
}

local NAVY = Color3.fromRGB(16, 24, 46)
local TILE = Color3.fromRGB(34, 46, 84)
local GOLD = Color3.fromRGB(255, 206, 60)
local GOLD_HOT = Color3.fromRGB(255, 194, 26)
local GREEN = Color3.fromRGB(46, 170, 92)
local MUTED = Color3.fromRGB(170, 184, 220)
local WHITE = Color3.new(1, 1, 1)

local callbacks: Callbacks
local layer: Frame
local card: Frame
local tiles: { { frame: Frame, day: TextLabel, coins: TextLabel, state: TextLabel, stroke: UIStroke } } = {}
local claimButton: TextButton
local streakLabel: TextLabel
local login: Login? = nil
local isOpen = false
local waiting = false -- a claim was sent; the button stays off until the answer comes back

local function coinDot(parent: Instance, size: number): Frame
	return Ui.new("Frame", {
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = GOLD,
		LayoutOrder = 1,
		Parent = parent,
	}, { Ui.corner(size), Ui.stroke(Color3.fromRGB(214, 150, 24), 2) })
end

local function short(n: number): string
	if n >= 1000 then
		local k = n / 1000
		return if k == math.floor(k) then `{k}K` else string.format("%.3gK", k) -- 1250 -> 1.25K
	end
	return tostring(n)
end

local function countdown(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h, m = seconds // 3600, seconds % 3600 // 60
	return if h > 0 then `{h}H {m}M` else `{m}M {seconds % 60}S`
end

function DailyRewards.init(screen: ScreenGui, cb: Callbacks)
	callbacks = cb
	layer = Ui.new("Frame", {
		Name = "DailyRewards",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Active = true,
		Visible = false,
		ZIndex = 42,
		Parent = screen,
	})
	card = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.94, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = NAVY,
		Parent = layer,
	}, {
		Ui.corner(14),
		Ui.stroke(GOLD_HOT, 3),
		Ui.new("UISizeConstraint", { MaxSize = Vector2.new(640, math.huge) }),
		Ui.new("UIScale", {}),
		Ui.new("UIPadding", {
			PaddingTop = UDim.new(0, 14),
			PaddingBottom = UDim.new(0, 16),
			PaddingLeft = UDim.new(0, 16),
			PaddingRight = UDim.new(0, 16),
		}),
		Ui.new("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	-- Header: the title, and the close button (a 44 px target) on the right.
	local header = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = card,
	})
	Ui.label("DAILY LOGIN REWARDS", 30, nil, GOLD_HOT, {
		FontFace = Ui.SportItalic,
		Position = UDim2.fromOffset(52, 0),
		Size = UDim2.new(1, -104, 1, 0),
		TextScaled = true,
		Parent = header,
	})
	Ui.label("Log in every day for more coins to spend on skins. Miss a day and you start again at day 1.", 14, Ui.Theme.BodyFont, MUTED, {
		Size = UDim2.new(1, 0, 0, 34),
		TextWrapped = true,
		LayoutOrder = 2,
		Parent = card,
	})
	Ui.button("X", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = Color3.fromRGB(214, 52, 56),
		FontFace = Ui.Sport,
		TextSize = 22,
		Parent = header,
	}, function()
		DailyRewards.close()
	end)

	local row = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 0, 112),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = card,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for i = 1, 7 do
		local big = i == 7
		local frame: Frame = Ui.new("Frame", {
			Size = UDim2.new(if big then 0.17 else 0.128, 0, if big then 1 else 0.9, 0),
			BackgroundColor3 = TILE,
			LayoutOrder = i,
			Parent = row,
		}, {
			Ui.corner(10),
			Ui.new("UIListLayout", {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 4),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local stroke = Ui.stroke(WHITE, 2, 0.8)
		stroke.Parent = frame
		local day = Ui.label(`DAY {i}`, 15, nil, MUTED, { FontFace = Ui.SportItalic, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 0, Parent = frame })
		coinDot(frame, if big then 26 else 20)
		local coins = Ui.label("", if big then 22 else 18, nil, WHITE, { FontFace = Ui.Sport, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 2, Parent = frame })
		local state = Ui.label("", 12, nil, MUTED, { FontFace = Ui.Sport, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 3, Parent = frame })
		tiles[i] = { frame = frame, day = day, coins = coins, state = state, stroke = stroke }
	end

	streakLabel = Ui.label("", 15, nil, WHITE, {
		FontFace = Ui.SportItalic,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 4,
		Parent = card,
	})
	claimButton = Ui.button("CLAIM", {
		Size = UDim2.new(0.7, 0, 0, 52),
		BackgroundColor3 = GREEN,
		FontFace = Ui.SportItalic,
		TextSize = 24,
		LayoutOrder = 5,
		Parent = card,
	}, function()
		local l = login
		if not l or waiting then
			return
		end
		if l.needsTutorial then
			DailyRewards.close()
			callbacks.onTutorial()
		elseif l.canClaim then
			waiting = true
			DailyRewards.redraw()
			callbacks.onClaim()
		end
	end)

	-- The countdown on the button ticks while the window is open.
	task.spawn(function()
		while true do
			task.wait(1)
			if isOpen and login and not login.canClaim then
				DailyRewards.redraw()
			end
		end
	end)
end

function DailyRewards.redraw()
	local l = login
	if not l or not claimButton then
		return
	end
	-- The run so far: on a claimable day, the days before today's slot are done; once today is
	-- claimed, everything up to it is.
	local doneUpTo = if l.canClaim then l.slot - 1 else l.slot
	local nextSlot = if l.canClaim then l.slot else l.slot % #l.track + 1
	for i, tile in tiles do
		local coins = l.track[i] or 0
		tile.coins.Text = short(coins)
		local done = i <= doneUpTo
		local today = l.canClaim and i == l.slot
		local tomorrow = not l.canClaim and i == nextSlot and not (nextSlot == 1 and doneUpTo == #l.track)
		tile.frame.BackgroundColor3 = if today then Color3.fromRGB(64, 92, 170) elseif done then Color3.fromRGB(30, 74, 58) else TILE
		tile.stroke.Color = if today then GOLD_HOT elseif i == 7 then GOLD else WHITE
		tile.stroke.Transparency = if today or i == 7 then 0 else 0.8
		tile.stroke.Thickness = if today then 3 else 2
		tile.state.Text = if done then "CLAIMED" elseif today then "TODAY" elseif tomorrow then "TOMORROW" else ""
		tile.state.TextColor3 = if done then Color3.fromRGB(150, 255, 170) elseif today then GOLD_HOT else MUTED
		tile.day.TextColor3 = if today then WHITE else MUTED
	end
	local streak = l.streak
	streakLabel.Text = if streak > 0 then `STREAK: {streak} DAY{if streak == 1 then "" else "S"}` else "START YOUR STREAK TODAY"
	local left = l.resetsAt - workspace:GetServerTimeNow()
	if l.needsTutorial then
		claimButton.Text = `FINISH THE TUTORIAL FOR DAY 1`
		claimButton.Active = true
		claimButton.BackgroundColor3 = Color3.fromRGB(40, 104, 214)
	elseif l.canClaim then
		claimButton.Text = if waiting then "CLAIMING..." else `CLAIM {l.track[l.slot]} COINS`
		claimButton.Active = not waiting
		claimButton.BackgroundColor3 = GREEN
	else
		claimButton.Text = `NEXT REWARD IN {countdown(left)}`
		claimButton.Active = false
		claimButton.BackgroundColor3 = Color3.fromRGB(70, 78, 104)
	end
end

function DailyRewards.setState(state: any)
	if type(state) ~= "table" or type(state.track) ~= "table" then
		return
	end
	login = state :: Login
	waiting = false
	DailyRewards.redraw()
end

-- True when today's reward is waiting (and a brand-new player isn't on their tutorial day).
function DailyRewards.available(): boolean
	local l = login
	return l ~= nil and l.canClaim and not l.needsTutorial
end

function DailyRewards.open()
	if isOpen or not login then
		return
	end
	isOpen = true
	DailyRewards.redraw()
	Ui.fadeIn(layer)
	Ui.fadeIn(card)
	callbacks.onOpenChanged(true)
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = claimButton
	end
end

function DailyRewards.close()
	if not isOpen then
		return
	end
	isOpen = false
	layer.Visible = false
	callbacks.onOpenChanged(false)
	GuiService.SelectedObject = nil
end

function DailyRewards.isOpen(): boolean
	return isOpen
end

-- The server's answer to a claim.
function DailyRewards.claimed(ok: boolean, coins: number, day: number)
	waiting = false
	if ok then
		local tile = tiles[day]
		if tile then
			local scale = tile.frame:FindFirstChildOfClass("UIScale") or Ui.new("UIScale", { Parent = tile.frame })
			scale.Scale = 1.25
			TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
	DailyRewards.redraw()
end

return DailyRewards
