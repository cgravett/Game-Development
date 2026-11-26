--!strict
-- Live match HUD. It only draws what the server publishes: score, clock and phase are never
-- computed here. Layout: score bug top-centre (the Roblox buttons own the top-left corner),
-- minimap top-right, meters bottom-centre, goal call-outs mid-screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Ui = require(script.Parent.Ui)
local InputHints = require(script.Parent.InputHints)

local Hud = {}

local Theme = Ui.Theme
local AWAY = Color3.fromRGB(40, 104, 214)
local HOME = Color3.fromRGB(222, 52, 56)
Hud.AWAY = AWAY
Hud.HOME = HOME
local NAVY = Color3.fromRGB(16, 24, 46)
local GOLD = Color3.fromRGB(255, 206, 60)

local MAP_W, MAP_H = 74, 138
local HX = Config.Arena.Length / 2
local HZ = Config.Arena.Width / 2

local root: Frame
local scoreBug: Frame
local scoreA: TextLabel
local scoreB: TextLabel
local clockText = "5:00"
local clockLabel: TextLabel
local phaseLabel: TextLabel
local banner: TextLabel
local bannerSub: TextLabel
local bannerSmall: TextLabel
local bannerScale: UIScale
local spinFill: Frame
local spinIcon: ImageLabel
local staminaFill: Frame
local countLabel: TextLabel
local timeCall: Frame
local timeCallLabel: TextLabel
local timeCallStroke: UIStroke
local timeCallScale: UIScale
local timeCallShown = ""
local countScale: UIScale
local countShown = -1
local meters: CanvasGroup
local pingLabel: TextLabel
local fpsLabel: TextLabel
local meterScale: UIScale
local mapScale: UIScale
local matchWidgets = true
-- Display settings (Settings: HUD and Minimap).
local show = { scoreBug = true, minimap = true, ping = true, fps = false }
local fpsSmoothed = 60
local degraded: TextLabel
local objective: Frame
local objectiveText: TextLabel
local objectiveStep: TextLabel
local objectiveDismissed: string? = nil -- the card title the player closed with X
local debugLabel: TextLabel
local map: Frame
local mapDots: { Frame } = {}
local mapPuck: Frame
local toastLabel: TextLabel
local cornerLabel: TextLabel
local noticeLabel: TextLabel
local bannerToken = 0
local toastToken = 0
local menuButton: TextButton
local holdTab: TextLabel
local idleCard: Frame
local idleText: TextLabel
local idleScale: UIScale
local idleShown = -1
local rewardCard: Frame? = nil
local hudScreen: ScreenGui
local applyDevice: () -> ()

local function outline(label: TextLabel, color: Color3, thickness: number)
	Ui.new("UIStroke", { Color = color, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = label })
end

function Hud.init(screen: ScreenGui, onMenu: () -> ())
	root = Ui.new("Frame", {
		Name = "Hud",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = screen,
	})

	-- Score bug, broadcast style: [AWAY][2][ 4:53 ][1][HOME] on one bar with a soft shadow, a
	-- two-colour team stripe under it and a small phase tag (FACEOFF, GOAL...) below the clock.
	local BUG_W, BUG_H = 392, 46
	scoreBug = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(BUG_W, BUG_H + 4),
		BackgroundTransparency = 1,
		Parent = root,
	}, { Ui.new("UIScale", { Scale = 1.15 }) })
	Ui.new("Frame", {
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.fromOffset(BUG_W, BUG_H + 2),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.65,
		BorderSizePixel = 0,
		Parent = scoreBug,
	}, { Ui.corner(8) })
	local bar: CanvasGroup = Ui.new("CanvasGroup", {
		Size = UDim2.fromOffset(BUG_W, BUG_H),
		BackgroundColor3 = NAVY,
		BorderSizePixel = 0,
		Parent = scoreBug,
	}, { Ui.corner(8) })
	local function block(x: number, w: number, color: Color3, shade: number): Frame
		return Ui.new("Frame", {
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.fromOffset(w, BUG_H),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Parent = bar,
		}, {
			Ui.new("UIGradient", {
				Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), shade), color:Lerp(Color3.new(0, 0, 0), shade)),
				Rotation = 90,
			}),
		})
	end
	local function teamChip(text: string, color: Color3, x: number)
		local chip = block(x, 100, color, 0.12)
		local label = Ui.label(text, 24, nil, Theme.Text, {
			FontFace = Ui.SportItalic,
			Size = UDim2.fromScale(1, 1),
			Parent = chip,
		})
		outline(label, color:Lerp(Color3.new(0, 0, 0), 0.45), 1.5)
	end
	local SCORE_INK = Color3.fromRGB(20, 28, 52)
	local function scoreCell(x: number): TextLabel
		return Ui.label("0", 34, nil, SCORE_INK, {
			FontFace = Ui.SportItalic,
			Size = UDim2.fromScale(1, 1),
			Parent = block(x, 52, Color3.fromRGB(240, 243, 250), 0.04),
		})
	end
	teamChip(Config.Teams[1].Abbrev, AWAY, 0)
	scoreA = scoreCell(100)
	local clockCell = block(152, 88, Color3.fromRGB(14, 20, 40), 0.06)
	clockLabel = Ui.label("5:00", 30, nil, Color3.new(1, 1, 1), {
		FontFace = Ui.SportItalic,
		Size = UDim2.fromScale(1, 1),
		Parent = clockCell,
	})
	scoreB = scoreCell(240)
	teamChip(Config.Teams[2].Abbrev, HOME, 292)
	-- Team stripe along the bottom edge.
	Ui.new("Frame", { Position = UDim2.new(0, 0, 1, -4), Size = UDim2.new(0.5, 0, 0, 4), BackgroundColor3 = AWAY:Lerp(Color3.new(1, 1, 1), 0.25), BorderSizePixel = 0, Parent = bar })
	Ui.new("Frame", { Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.new(0.5, 0, 0, 4), BackgroundColor3 = HOME:Lerp(Color3.new(1, 1, 1), 0.25), BorderSizePixel = 0, Parent = bar })
	-- Phase tag under the clock; hidden when there is nothing to say.
	local tag: Frame = Ui.new("Frame", {
		Name = "PhaseTag",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, BUG_H + 2),
		Size = UDim2.fromOffset(104, 22),
		BackgroundColor3 = Color3.fromRGB(14, 20, 40),
		BorderSizePixel = 0,
		Visible = false,
		Parent = scoreBug,
	}, { Ui.corner(6), Ui.stroke(GOLD, 1.5) })
	phaseLabel = Ui.label("", 15, nil, GOLD, {
		FontFace = Ui.SportItalic,
		Size = UDim2.fromScale(1, 1),
		Parent = tag,
	})
	phaseLabel:GetPropertyChangedSignal("Text"):Connect(function()
		tag.Visible = phaseLabel.Text ~= ""
	end)
	-- End-of-game call-out just under the score bug: "30 SECONDS LEFT", "10 SECONDS LEFT", then
	-- a big 3, 2, 1, and "FINAL HORN" while the horn sounds.
	timeCallStroke = Ui.stroke(GOLD, 2)
	timeCall = Ui.new("Frame", {
		Name = "TimeCall",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, BUG_H + 30),
		Size = UDim2.fromOffset(230, 36),
		BackgroundColor3 = NAVY,
		BorderSizePixel = 0,
		Visible = false,
		Parent = scoreBug,
	}, { Ui.corner(8), timeCallStroke })
	timeCallLabel = Ui.label("", 22, nil, GOLD, {
		FontFace = Ui.SportItalic,
		Size = UDim2.fromScale(1, 1),
		Parent = timeCall,
	})
	outline(timeCallLabel, Color3.fromRGB(8, 12, 26), 1.5)
	timeCallScale = Ui.new("UIScale", { Parent = timeCall })

	-- Mid-screen call-outs: team-coloured text with a white outline.
	banner = Ui.label("", 40, nil, Theme.Text, {
		FontFace = Ui.SportItalic,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.new(1, 0, 0, 42),
		Visible = false,
		Parent = root,
	})
	outline(banner, Color3.new(1, 1, 1), 3)
	bannerScale = Ui.new("UIScale", { Parent = banner })
	bannerSub = Ui.label("", 17, Enum.Font.GothamBlack, Theme.Text, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.36, 22),
		Size = UDim2.new(1, 0, 0, 22),
		Visible = false,
		Parent = root,
	})
	outline(bannerSub, Color3.new(1, 1, 1), 2)
	bannerSmall = Ui.label("", 11, Enum.Font.GothamBlack, Theme.Text, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.36, 44),
		Size = UDim2.new(1, 0, 0, 14),
		Visible = false,
		Parent = root,
	})
	outline(bannerSmall, Color3.new(1, 1, 1), 1.5)

	-- Slim bars, bottom centre: energy (green) for the sprint burst, and under it the spin meter
	-- (blue). Spinning the stick hard drains the spin meter; empty, its icon turns red and the
	-- stick turns sluggishly until it comes back.
	meters = Ui.new("CanvasGroup", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(206, 28),
		BackgroundTransparency = 1,
		Parent = root,
	})
	meterScale = Ui.new("UIScale", { Parent = meters })
	local BAR_X = 22
	local function meter(y: number, color: Color3): Frame
		local track: Frame = Ui.new("Frame", {
			Position = UDim2.fromOffset(BAR_X, y),
			Size = UDim2.new(1, -BAR_X, 0, 5),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			Parent = meters,
		}, { Ui.corner(3) })
		return Ui.new("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = track,
		}, { Ui.corner(3) })
	end
	staminaFill = meter(5, Color3.fromRGB(88, 224, 104))
	spinFill = meter(18, Color3.fromRGB(78, 122, 232))
	-- Icons (assets/ui/icons.py): a lightning bolt for dash energy and a swirl for the spin meter
	-- (white, tinted red while spun out). Each fits inside the meter group so none is clipped.
	Ui.new("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(9, 7.5),
		Size = UDim2.fromOffset(13, 13),
		BackgroundTransparency = 1,
		Image = "rbxassetid://119551094982188",
		Parent = meters,
	})
	spinIcon = Ui.new("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(9, 20.5),
		Size = UDim2.fromOffset(13, 13),
		BackgroundTransparency = 1,
		Image = "rbxassetid://130349438664061",
		ImageColor3 = Color3.fromRGB(220, 226, 240),
		Parent = meters,
	})

	-- Face-off count (3, 2, 1) while the puck hangs over the dot.
	countLabel = Ui.label("", 64, nil, Color3.new(1, 1, 1), {
		FontFace = Ui.SportItalic,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(160, 70),
		Visible = false,
		Parent = root,
	})
	outline(countLabel, Color3.fromRGB(20, 28, 52), 3)
	countScale = Ui.new("UIScale", { Parent = countLabel })

	-- Minimap, top right: grey glass with rink lines. Up is the local attacking direction.
	map = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(MAP_W, MAP_H),
		BackgroundColor3 = Color3.fromRGB(22, 30, 48),
		BackgroundTransparency = 0.3,
		Parent = root,
	}, { Ui.corner(14), Ui.stroke(Color3.new(1, 1, 1), 1, 0.6) })
	mapScale = Ui.new("UIScale", { Parent = map })
	local function mapLine(v: number, color: Color3, thickness: number)
		Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, v),
			Size = UDim2.new(0.86, 0, 0, thickness),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			Parent = map,
		})
	end
	mapLine(0.5, Color3.fromRGB(240, 110, 110), 2)
	mapLine(0.5 - Config.Arena.BlueLineX / Config.Arena.Length, Color3.fromRGB(120, 160, 240), 2)
	mapLine(0.5 + Config.Arena.BlueLineX / Config.Arena.Length, Color3.fromRGB(120, 160, 240), 2)
	for _, v in { 0.5 - Config.Goal.X / Config.Arena.Length, 0.5 + Config.Goal.X / Config.Arena.Length } do
		mapLine(v, Color3.fromRGB(240, 110, 110), 1)
	end
	for _, v in { 0.22, 0.78 } do
		for _, u in { 0.28, 0.72 } do
			Ui.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(u, v),
				Size = UDim2.fromOffset(17, 17),
				BackgroundTransparency = 1,
				Parent = map,
			}, { Ui.corner(9), Ui.stroke(Color3.fromRGB(240, 110, 110), 1, 0.3) })
		end
	end
	for slot = 1, 6 do
		mapDots[slot] = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(7, 7),
			BackgroundColor3 = if slot <= 3 then AWAY else HOME,
			ZIndex = 2,
			Parent = map,
		}, { Ui.corner(4), Ui.stroke(Color3.new(1, 1, 1), 1) })
	end
	mapPuck = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(5, 5),
		BackgroundColor3 = Color3.new(0, 0, 0),
		ZIndex = 3,
		Parent = map,
	}, { Ui.corner(3) })

	-- In-game menu (settings, leave), bottom right, clear of the minimap. Esc belongs to Roblox,
	-- so hold Tab to free the cursor. On a phone it moves to the top left (applyDevice), out of
	-- the right thumb's way.
	menuButton = Ui.button("MENU", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -54),
		Size = UDim2.fromOffset(84, 34),
		TextSize = 20,
		FontFace = Ui.SportItalic,
		BackgroundColor3 = NAVY,
		Parent = root,
	}, onMenu)
	Ui.stroke(GOLD, 2).Parent = menuButton
	menuButton.Selectable = false -- the gamepad opens it with View / Create instead
	holdTab = Ui.label("HOLD TAB", 12, nil, Color3.new(1, 1, 1), {
		FontFace = Ui.Sport,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -4),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = menuButton,
	})
	holdTab.TextStrokeTransparency = 0.4

	pingLabel = Ui.label("", 14, Theme.BodyFont, Color3.fromRGB(60, 66, 84), {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -8),
		Size = UDim2.fromOffset(140, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = root,
	})
	fpsLabel = Ui.label("", 14, Theme.BodyFont, Color3.fromRGB(60, 66, 84), {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -28),
		Size = UDim2.fromOffset(140, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
		Parent = root,
	})

	degraded = Ui.label("Connection unstable. Waiting for match data...", 16, Theme.BoldFont, HOME, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(560, 22),
		Visible = false,
		Parent = root,
	})
	debugLabel = Ui.label("", 13, Enum.Font.Code, Color3.fromRGB(30, 120, 60), {
		Position = UDim2.fromOffset(14, 90),
		Size = UDim2.fromOffset(460, 120),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = false,
		Parent = root,
	})

	-- Practice objective card (white card with a cone-orange edge, like a coach's note).
	-- It grows to fit its text (a drill's tip adds a line). Placed by applyDevice.
	objective = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -20, 0.45, 0),
		Size = UDim2.fromOffset(350, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(250, 250, 252),
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = root,
	}, {
		Ui.corner(8),
		Ui.stroke(Color3.fromRGB(250, 130, 40), 2),
		Ui.new("UIPadding", { PaddingBottom = UDim.new(0, 12) }),
		Ui.new("UISizeConstraint", { MinSize = Vector2.new(260, 70), MaxSize = Vector2.new(440, 400) }),
	})
	objectiveStep = Ui.label("", 13, Enum.Font.GothamBlack, Color3.fromRGB(250, 130, 40), {
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.new(1, -44, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = objective,
	})
	-- X closes the card (free the cursor first); it stays closed until the next drill's card.
	local close = Ui.button("X", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(24, 24),
		TextSize = 14,
		Font = Enum.Font.GothamBlack,
		BackgroundColor3 = Color3.fromRGB(250, 130, 40),
		TextColor3 = Color3.fromRGB(255, 255, 255),
		ZIndex = 3,
		Parent = objective,
	}, function()
		objectiveDismissed = objectiveStep.Text
		objective.Visible = false
	end)
	Ui.corner(12).Parent = close
	objectiveText = Ui.label("", 16, Theme.BodyFont, Color3.fromRGB(40, 44, 58), {
		Position = UDim2.fromOffset(14, 32),
		Size = UDim2.new(1, -28, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = objective,
	})

	toastLabel = Ui.label("", 16, Enum.Font.GothamBlack, Theme.Text, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -48),
		Size = UDim2.fromOffset(500, 22),
		Visible = false,
		Parent = screen,
		ZIndex = 20,
	})
	outline(toastLabel, Color3.fromRGB(20, 24, 36), 2)

	-- Bottom-left card for joining a match already under way (above where a touch thumbstick sits).
	cornerLabel = Ui.label("", 14, Enum.Font.GothamBlack, Theme.Text, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, if game:GetService("UserInputService").TouchEnabled then -230 else -110),
		Size = UDim2.fromOffset(300, 46),
		BackgroundTransparency = 0.15,
		BackgroundColor3 = Color3.fromRGB(20, 24, 36),
		TextWrapped = true,
		Visible = false,
		ZIndex = 25,
		Parent = screen,
	})
	Ui.corner(8).Parent = cornerLabel
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = cornerLabel })

	noticeLabel = Ui.label("", 13, Theme.BoldFont, Theme.Text, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 92), -- below the menu bar
		Size = UDim2.fromOffset(640, 30),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = HOME,
		TextWrapped = true,
		Visible = false,
		ZIndex = 30,
		Parent = screen,
	})
	Ui.corner(6).Parent = noticeLabel

	-- Idle warning (vault: "AFK Detection and Idle Kick"): big, centred and readable on a phone,
	-- counting down the last seconds before an idle player goes back to the lobby.
	hudScreen = screen
	idleCard = Ui.new("Frame", {
		Name = "IdleWarning",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0, 132),
		BackgroundColor3 = NAVY,
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 40,
		Parent = screen,
	}, {
		Ui.corner(14),
		Ui.stroke(Color3.fromRGB(255, 86, 86), 3),
		Ui.new("UISizeConstraint", { MaxSize = Vector2.new(480, 132) }),
	})
	idleScale = Ui.new("UIScale", { Parent = idleCard })
	Ui.label("ARE YOU STILL THERE?", 32, nil, Color3.fromRGB(255, 206, 60), {
		FontFace = Ui.SportItalic,
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 38),
		Parent = idleCard,
	})
	idleText = Ui.label("", 18, Theme.BoldFont, Theme.Text, {
		Position = UDim2.new(0, 16, 0, 60),
		Size = UDim2.new(1, -32, 0, 56),
		TextWrapped = true,
		Parent = idleCard,
	})

	applyDevice()
	InputHints.onChanged(applyDevice)
end

-- Places the controls for the device in use. On a phone the MENU button goes top left, out of
-- the right thumb's way.
function applyDevice()
	if not menuButton then
		return
	end
	local device = InputHints.device()
	if device == "touch" then
		menuButton.AnchorPoint = Vector2.new(0, 0)
		menuButton.Position = UDim2.fromOffset(12, 64)
		menuButton.Size = UDim2.fromOffset(100, 44)
		objective.Size = UDim2.new(0.5, 0, 0, 0)
	else
		menuButton.AnchorPoint = Vector2.new(1, 1)
		menuButton.Position = UDim2.new(1, -12, 1, -54)
		menuButton.Size = UDim2.fromOffset(84, 34)
		objective.Size = UDim2.fromOffset(440, 0)
	end
	-- Top centre on every device: the score bug is hidden in practice, and down the sides the
	-- card would cover the drill rings.
	objective.AnchorPoint = Vector2.new(0.5, 0)
	objective.Position = UDim2.new(0.5, 0, 0, 12)
	holdTab.Visible = device ~= "touch"
	holdTab.Text = if device == "pad" then `PRESS {string.upper(InputHints.padName(InputHints.Pad.menu))}` else "HOLD TAB"
	if idleShown > 0 then
		Hud.idleWarning(idleShown, true)
	end
end

-- Seconds left before the idle kick; nil hides the warning. Each new second pops in.
function Hud.idleWarning(seconds: number?, redraw: boolean?)
	if not idleCard then
		return
	end
	local n = seconds or -1
	if n == idleShown and not redraw then
		return
	end
	idleShown = n
	idleCard.Visible = seconds ~= nil
	if not seconds then
		return
	end
	local device = InputHints.device()
	local how = if device == "touch" then "Touch the screen"
		elseif device == "pad" then "Move a stick or press a button"
		else "Move or press a key"
	idleText.Text = `{how}, or you'll go back to the lobby in {seconds}...`
	if not redraw then
		idleScale.Scale = 1.08
		TweenService:Create(idleScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- The tutorial reward screen: the prize, the coins and what to do next. Controller players start
-- on PLAY A MATCH (vault: "First-Time User Experience and Onboarding" - end the tutorial with
-- the reward and a clear next goal).
export type RewardScreen = {
	itemName: string,
	coins: number,
	preview: GuiObject?,
	onPlay: () -> (),
	onPractice: () -> (),
	onMenu: () -> (),
}

function Hud.hideReward()
	local card = rewardCard
	rewardCard = nil
	if card then
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(card) then
			GuiService.SelectedObject = nil
		end
		card:Destroy()
	end
end

function Hud.showReward(info: RewardScreen)
	Hud.hideReward()
	local GOLD_HOT = Color3.fromRGB(255, 194, 26)
	local card: Frame = Ui.new("Frame", {
		Name = "TutorialReward",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.92, 0, 0.9, 0),
		BackgroundColor3 = NAVY,
		BackgroundTransparency = 0.02,
		ZIndex = 45,
		Parent = hudScreen,
	}, {
		Ui.corner(18),
		Ui.stroke(GOLD_HOT, 4),
		Ui.new("UISizeConstraint", { MaxSize = Vector2.new(520, 420) }),
	})
	rewardCard = card
	local scale = Ui.new("UIScale", { Scale = 0.7, Parent = card })
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local list = Ui.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = card,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Ui.new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 14) }),
	})
	local title = Ui.label("TUTORIAL COMPLETE!", 34, nil, GOLD_HOT, {
		FontFace = Ui.SportItalic,
		LayoutOrder = 1,
		Size = UDim2.new(1, -24, 0, 40),
		TextScaled = true,
		Parent = list,
	})
	outline(title, Color3.fromRGB(8, 12, 26), 2)
	Ui.label("YOU EARNED", 16, Enum.Font.GothamBlack, Theme.Muted, { LayoutOrder = 2, Parent = list })
	local stage = Ui.new("Frame", {
		LayoutOrder = 3,
		Size = UDim2.new(0.7, 0, 0.36, 0),
		BackgroundColor3 = Color3.fromRGB(34, 46, 84),
		Parent = list,
	}, { Ui.corner(12), Ui.new("UISizeConstraint", { MaxSize = Vector2.new(300, 150) }) })
	local preview = info.preview
	if preview then
		preview.AnchorPoint = Vector2.new(0.5, 0.5)
		preview.Position = UDim2.fromScale(0.5, 0.5)
		preview.Size = UDim2.fromScale(1, 1)
		preview.Parent = stage
	end
	Ui.label(string.upper(info.itemName) .. " STICK", 24, nil, Theme.Text, {
		FontFace = Ui.SportItalic,
		LayoutOrder = 4,
		Size = UDim2.new(1, -24, 0, 28),
		Parent = list,
	})
	Ui.label(`+{info.coins} COINS`, 22, nil, GOLD_HOT, {
		FontFace = Ui.SportItalic,
		LayoutOrder = 5,
		Size = UDim2.new(1, -24, 0, 26),
		Parent = list,
	})
	Ui.label("It's equipped already. Show it off in a match!", 15, Theme.BodyFont, Theme.Muted, {
		LayoutOrder = 6,
		Size = UDim2.new(1, -24, 0, 20),
		TextWrapped = true,
		Parent = list,
	})
	local row = Ui.new("Frame", {
		LayoutOrder = 7,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 0, 54),
		Parent = list,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local play = Ui.button("PLAY A MATCH", {
		LayoutOrder = 1,
		Size = UDim2.new(0.48, 0, 1, 0),
		TextSize = 22,
		FontFace = Ui.SportItalic,
		BackgroundColor3 = Color3.fromRGB(46, 170, 92),
		Parent = row,
	}, function()
		Hud.hideReward()
		info.onPlay()
	end)
	local practice = Ui.button("KEEP PRACTISING", {
		LayoutOrder = 2,
		Size = UDim2.new(0.48, 0, 1, 0),
		TextSize = 20,
		FontFace = Ui.SportItalic,
		BackgroundColor3 = Color3.fromRGB(38, 46, 78),
		Parent = row,
	}, function()
		Hud.hideReward()
		info.onPractice()
	end)
	-- Back to the lobby, under the two big choices (Build 29).
	local menu = Ui.button("MAIN MENU", {
		LayoutOrder = 8,
		Size = UDim2.new(0.5, 0, 0, 40),
		TextSize = 18,
		FontFace = Ui.SportItalic,
		BackgroundColor3 = Color3.fromRGB(70, 78, 104),
		Parent = list,
	}, function()
		Hud.hideReward()
		info.onMenu()
	end)
	play.NextSelectionRight = practice
	practice.NextSelectionLeft = play
	play.NextSelectionDown = menu
	practice.NextSelectionDown = menu
	menu.NextSelectionUp = play
	if InputHints.device() == "pad" then
		GuiService.SelectedObject = play
	end
end

function Hud.rewardOpen(): boolean
	return rewardCard ~= nil
end

-- F3 hides the HUD for clean screenshots; modes still say when it should show.
local wantVisible = false
local hiddenByPlayer = false
function Hud.setVisible(visible: boolean)
	wantVisible = visible
	root.Visible = visible and not hiddenByPlayer
end

function Hud.toggleHidden(): boolean
	hiddenByPlayer = not hiddenByPlayer
	root.Visible = wantVisible and not hiddenByPlayer
	return hiddenByPlayer
end

-- Practice and the pond hide the score bug and minimap.
local function applyWidgets()
	scoreBug.Visible = matchWidgets and show.scoreBug
	map.Visible = matchWidgets and show.minimap
	pingLabel.Visible = show.ping
	fpsLabel.Visible = show.fps
end

function Hud.setMatchWidgets(visible: boolean)
	matchWidgets = visible
	applyWidgets()
end

-- name: "scoreBug", "minimap", "ping" or "fps".
function Hud.setShown(name: string, on: boolean)
	show[name] = on
	applyWidgets()
end

function Hud.setMinimapScale(scale: number)
	mapScale.Scale = scale
end

function Hud.setMeterLook(scale: number, opacity: number)
	meterScale.Scale = scale
	meters.GroupTransparency = 1 - opacity
end

-- Call once per rendered frame.
function Hud.tickFps(dt: number)
	if dt > 0 then
		fpsSmoothed += (1 / dt - fpsSmoothed) * math.min(1, dt * 4)
	end
	if show.fps then
		fpsLabel.Text = `FPS: {math.round(fpsSmoothed)}`
	end
end

function Hud.setScores(a: number, b: number)
	scoreA.Text = tostring(a)
	scoreB.Text = tostring(b)
end

function Hud.setClock(seconds: number, overtime: boolean, phase: string?)
	local s = math.max(0, math.ceil(seconds))
	clockText = if overtime then "OT" else string.format("%d:%02d", s // 60, s % 60)
	clockLabel.Text = clockText
	local p = phase or ""
	phaseLabel.Text = if p == "Faceoff" then "FACEOFF"
		elseif p == "Countdown" or p == "Waiting" then "WARMUP"
		elseif p == "GoalFrozen" then "GOAL"
		elseif p == "Final" or p == "Buzzer" then "FINAL"
		elseif overtime then "OVERTIME"
		else ""
end

function Hud.clockText(): string
	return clockText
end

-- A plain call-out (countdown, GO!, results title).
function Hud.banner(text: string, sub: string?, color: Color3?, seconds: number?, small: string?)
	bannerToken += 1
	local token = bannerToken
	local c = color or Color3.fromRGB(30, 34, 48)
	banner.Text = text
	banner.TextColor3 = c
	banner.Visible = text ~= ""
	bannerSub.Text = sub or ""
	bannerSub.TextColor3 = c
	bannerSub.Visible = sub ~= nil and sub ~= ""
	bannerSmall.Text = small or ""
	bannerSmall.TextColor3 = c
	bannerSmall.Visible = small ~= nil and small ~= ""
	bannerScale.Scale = 0.6
	TweenService:Create(bannerScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	if seconds then
		task.delay(seconds, function()
			if token == bannerToken then
				banner.Visible = false
				bannerSub.Visible = false
				bannerSmall.Visible = false
			end
		end)
	end
end

function Hud.toast(text: string, good: boolean?, seconds: number?)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = text
	toastLabel.TextColor3 = if good == false then Color3.fromRGB(255, 140, 140) else Color3.fromRGB(255, 255, 255)
	toastLabel.Visible = true
	task.delay(seconds or 2.4, function()
		if token == toastToken then
			toastLabel.Visible = false
		end
	end)
end

local cornerToken = 0
function Hud.cornerToast(text: string, seconds: number?)
	cornerToken += 1
	local token = cornerToken
	cornerLabel.Text = text
	cornerLabel.Visible = true
	task.delay(seconds or 6, function()
		if token == cornerToken then
			cornerLabel.Visible = false
		end
	end)
end

function Hud.setNotice(text: string?)
	noticeLabel.Visible = text ~= nil and text ~= ""
	noticeLabel.Text = text or ""
end

local SPIN_GREY = Color3.fromRGB(220, 226, 240)
local SPIN_RED = Color3.fromRGB(236, 60, 64)
function Hud.setMeters(spin: number, stamina: number, visible: boolean, spunOut: boolean?)
	meters.Visible = visible
	spinFill.Size = UDim2.fromScale(math.clamp(spin, 0, 1), 1)
	staminaFill.Size = UDim2.fromScale(math.clamp(stamina, 0, 1), 1)
	local color = if spunOut then SPIN_RED else SPIN_GREY
	if spinIcon.ImageColor3 ~= color then
		spinIcon.ImageColor3 = color
	end
	-- Spun out, the swirl turns slowly so the penalty reads at a glance.
	spinIcon.Rotation = if spunOut then (os.clock() * 360) % 360 else 0
end

-- The face-off count; nil hides it. Each new number pops in.
function Hud.setCount(n: number?)
	local value = n or -1
	if value == countShown then
		return
	end
	countShown = value
	countLabel.Visible = n ~= nil
	if n then
		countLabel.Text = tostring(n)
		countScale.Scale = 1.5
		TweenService:Create(countScale, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- The end-of-game call-out under the score bug; nil hides it. Each new call pops in, and
-- `urgent` ones (the last ten seconds) are red.
function Hud.setTimeCall(text: string?, urgent: boolean?)
	if not timeCall then
		return
	end
	local key = text or ""
	if key == timeCallShown then
		return
	end
	timeCallShown = key
	timeCall.Visible = text ~= nil
	if not text then
		return
	end
	local big = #text <= 2
	timeCallLabel.Text = text
	timeCallLabel.TextSize = if big then 40 else 22
	timeCall.Size = if big then UDim2.fromOffset(70, 54) else UDim2.fromOffset(230, 36)
	local color = if urgent then Color3.fromRGB(255, 86, 86) else GOLD
	timeCallLabel.TextColor3 = color
	timeCallStroke.Color = color
	timeCallScale.Scale = if big then 1.7 else 1.35
	TweenService:Create(timeCallScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- World X/Z to map: up is the attacking direction, right matches the screen's right.
local function mapPosition(x: number, z: number, screenForward: number): UDim2
	local u = 0.5 + (z * screenForward) / (2 * HZ) * 0.86
	local v = 0.5 - (x * screenForward) / (2 * HX) * 0.92
	return UDim2.fromScale(u, v)
end

function Hud.setMapSkater(slot: number, x: number, z: number, screenForward: number, visible: boolean, isLocal: boolean)
	local dot = mapDots[slot]
	dot.Visible = visible
	if visible then
		dot.Position = mapPosition(x, z, screenForward)
		dot.Size = if isLocal then UDim2.fromOffset(10, 10) else UDim2.fromOffset(7, 7)
	end
end

function Hud.setMapPuck(x: number, z: number, screenForward: number)
	mapPuck.Position = mapPosition(x, z, screenForward)
end

function Hud.setPing()
	local ms = math.round(Players.LocalPlayer:GetNetworkPing() * 1000)
	pingLabel.Text = `Ping: {ms}`
end

function Hud.setDegraded(on: boolean)
	degraded.Visible = on
end

function Hud.setDebug(text: string?)
	debugLabel.Visible = text ~= nil
	if text then
		debugLabel.Text = text
	end
end

function Hud.setObjective(step: string?, text: string?)
	if text == nil then
		objectiveDismissed = nil -- leaving practice: the card shows again next time
	end
	objective.Visible = text ~= nil and step ~= objectiveDismissed
	if text then
		objectiveStep.Text = step or ""
		objectiveText.Text = text
	end
end

return Hud
