--!strict
-- The in-game menu. Esc belongs to Roblox, so this opens from the MENU button on the HUD or
-- the held scoreboard (holding Tab frees the cursor to click it), or Select on a gamepad.
-- The match keeps running behind it: it is a menu, not a pause.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local Ui = require(script.Parent.Ui)

local GameMenu = {}

export type Callbacks = {
	onSettings: (parent: Instance, onClose: () -> ()) -> (),
	onLeave: () -> (),
	onOpenChanged: (open: boolean) -> (),
	onClosing: () -> (), -- give back anything borrowed (the Settings panel)
}

local NAVY = Color3.fromRGB(16, 24, 46)
local NAVY_LIGHT = Color3.fromRGB(30, 44, 80)
local BLUE = Color3.fromRGB(40, 104, 214)
local RED = Color3.fromRGB(214, 52, 56)
local GOLD = Color3.fromRGB(255, 206, 60)
local WHITE = Color3.new(1, 1, 1)

local callbacks: Callbacks
local layer: Frame
local card: Frame
local body: Frame
local leaveButton: TextButton
local extraButton: TextButton -- a fourth choice some modes add (LEAVE POND GAME in a pond match)
local extraRun: (() -> ())? = nil
local resumeButton: TextButton
local isOpen = false
-- Build 37: leaving a match under way is a loss, so LEAVE (and the pond's LEAVE POND GAME) first
-- asks "Are you sure?" on a second card.
local confirmLeave = false
local confirmBody: Frame
local confirmRun: (() -> ())? = nil
local stayButton: TextButton
local title: TextLabel

local function bigButton(text: string, color: Color3, order: number, onClick: () -> (), parent: Instance?): TextButton
	local b = Ui.button(text, {
		Size = UDim2.new(1, 0, 0, 46),
		TextSize = 22,
		FontFace = Ui.SportItalic,
		BackgroundColor3 = color,
		LayoutOrder = order,
		Parent = parent or body,
	}, onClick)
	Ui.stroke(WHITE, 2, 0.75).Parent = b
	return b
end

function GameMenu.init(screen: ScreenGui, cb: Callbacks)
	callbacks = cb
	layer = Ui.new("Frame", {
		Name = "GameMenu",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Active = true, -- swallow clicks so they don't reach the stick
		Visible = false,
		ZIndex = 40,
		Parent = screen,
	})
	card = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(320, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = NAVY,
		Parent = layer,
	}, {
		Ui.corner(10),
		Ui.stroke(GOLD, 3),
		Ui.new("UIScale", {}),
	})
	body = Ui.new("Frame", {
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		Ui.new("UIPadding", {
			PaddingTop = UDim.new(0, 16),
			PaddingBottom = UDim.new(0, 18),
			PaddingLeft = UDim.new(0, 20),
			PaddingRight = UDim.new(0, 20),
		}),
		Ui.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	-- Header strip: a red and blue face-off band with the title, like a rink scoreboard.
	local header: Frame = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 0, 54),
		BackgroundColor3 = NAVY_LIGHT,
		BorderSizePixel = 0,
		Parent = card,
	}, { Ui.corner(10) })
	for i, color in { BLUE, RED } do
		Ui.new("Frame", {
			Position = UDim2.new((i - 1) * 0.5, 0, 1, -5),
			Size = UDim2.new(0.5, 0, 0, 5),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = header,
		})
	end
	title = Ui.label("MENU", 30, nil, WHITE, {
		Size = UDim2.new(1, 0, 1, -5),
		FontFace = Ui.SportItalic,
		Parent = header,
	})
	Ui.new("UIStroke", { Color = NAVY, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = title })

	resumeButton = bigButton("RESUME", BLUE, 1, function()
		GameMenu.close()
	end)
	bigButton("SETTINGS", NAVY_LIGHT, 2, function()
		GameMenu.openSettings()
	end)
	local function showConfirm(run: () -> ())
		confirmRun = run
		body.Visible = false
		confirmBody.Visible = true
		title.Text = "LEAVE MATCH?"
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = stayButton
		end
	end
	extraButton = bigButton("", Color3.fromRGB(28, 132, 150), 3, function()
		local run = extraRun
		if confirmLeave and run then
			showConfirm(run)
			return
		end
		GameMenu.close()
		if run then
			run()
		end
	end)
	extraButton.Visible = false
	leaveButton = bigButton("LEAVE MATCH", RED, 4, function()
		if confirmLeave then
			showConfirm(callbacks.onLeave)
			return
		end
		GameMenu.close()
		callbacks.onLeave()
	end)
	-- The "Are you sure?" card: the warning, then STAY (back to the menu) and LEAVE.
	confirmBody = Ui.new("Frame", {
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
		Parent = card,
	}, {
		Ui.new("UIPadding", {
			PaddingTop = UDim.new(0, 16),
			PaddingBottom = UDim.new(0, 18),
			PaddingLeft = UDim.new(0, 20),
			PaddingRight = UDim.new(0, 20),
		}),
		Ui.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	Ui.label("Are you sure? Leaving will result in a loss.", 20, Ui.Theme.BoldFont, WHITE, {
		Size = UDim2.new(1, 0, 0, 52),
		TextWrapped = true,
		LayoutOrder = 1,
		Parent = confirmBody,
	})
	stayButton = bigButton("STAY", BLUE, 2, function()
		confirmRun = nil
		confirmBody.Visible = false
		body.Visible = true
		title.Text = "MENU"
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = resumeButton
		end
	end, confirmBody)
	bigButton("LEAVE", RED, 3, function()
		local run = confirmRun
		GameMenu.close()
		if run then
			run()
		end
	end, confirmBody)
	Ui.label("Hold Tab for the scoreboard and a free cursor.", 12, Ui.Theme.BodyFont, Color3.fromRGB(170, 184, 220), {
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 5,
		Parent = body,
	})
end

-- extra: an optional fourth button above the leave button ({ text, run }). confirm: leaving
-- now counts as a loss, so ask first.
function GameMenu.open(leaveText: string?, extra: { text: string, run: () -> () }?, confirm: boolean?)
	if isOpen then
		return
	end
	isOpen = true
	confirmLeave = confirm == true
	confirmRun = nil
	confirmBody.Visible = false
	body.Visible = true
	title.Text = "MENU"
	leaveButton.Text = leaveText or "LEAVE MATCH"
	extraRun = if extra then extra.run else nil
	extraButton.Text = if extra then extra.text else ""
	extraButton.Visible = extra ~= nil
	card.Visible = true
	Ui.fadeIn(layer)
	Ui.fadeIn(card)
	callbacks.onOpenChanged(true)
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = resumeButton
	end
end

-- Opens the menu straight onto the full Settings panel; BACK returns to the menu card.
function GameMenu.openSettings()
	GameMenu.open()
	card.Visible = false
	callbacks.onSettings(layer, function()
		card.Visible = true
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = resumeButton
		end
	end)
end

function GameMenu.close()
	if not isOpen then
		return
	end
	isOpen = false
	confirmRun = nil
	confirmBody.Visible = false
	body.Visible = true
	title.Text = "MENU"
	callbacks.onClosing()
	layer.Visible = false
	callbacks.onOpenChanged(false)
	GuiService.SelectedObject = nil
end

function GameMenu.isOpen(): boolean
	return isOpen
end

return GameMenu
