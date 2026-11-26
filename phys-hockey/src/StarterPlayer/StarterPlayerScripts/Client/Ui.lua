--!strict
-- Small UI kit: instance builder, theme tokens, and a button with hover, press and disabled
-- states plus a controller-selectable focus.

local TweenService = game:GetService("TweenService")

local Ui = {}

Ui.Theme = table.freeze({
	Ink = Color3.fromRGB(14, 18, 34),
	Panel = Color3.fromRGB(24, 30, 54),
	PanelLight = Color3.fromRGB(38, 46, 78),
	Text = Color3.fromRGB(244, 247, 252),
	Muted = Color3.fromRGB(170, 180, 205),
	Accent = Color3.fromRGB(255, 142, 44),
	AccentHot = Color3.fromRGB(255, 172, 84),
	Cyan = Color3.fromRGB(64, 214, 214),
	Good = Color3.fromRGB(96, 224, 140),
	TitleFont = Enum.Font.FredokaOne,
	BodyFont = Enum.Font.GothamMedium,
	BoldFont = Enum.Font.GothamBold,
})

-- Vault: "Text Fonts and Rich Text" (Gotham enums now render Montserrat; say what renders with
-- FontFace, two families at most). Sarpanch is a squared, sporty display face for scores,
-- labels and buttons, like a rink scoreboard; Montserrat stays for body text.
Ui.Sport = Font.fromName("Sarpanch", Enum.FontWeight.Heavy)
Ui.SportItalic = Font.fromName("Sarpanch", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local FACES: { [Enum.Font]: Font } = {
	[Enum.Font.GothamBlack] = Ui.Sport,
	[Enum.Font.GothamBold] = Font.fromName("Sarpanch", Enum.FontWeight.Bold),
	[Enum.Font.GothamMedium] = Font.fromName("Montserrat", Enum.FontWeight.Medium),
}

local Theme = Ui.Theme
local FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function Ui.new(class: string, props: { [string]: any }, children: { Instance }?): any
	local instance: any = Instance.new(class)
	local parent = props.Parent
	for key, value in props do
		-- FontFace goes last: setting Font afterwards would reset it.
		if key ~= "Parent" and key ~= "FontFace" then
			instance[key] = value
		end
	end
	-- Readability floor: small text gets a little bigger everywhere (12 becomes 14, 15 becomes 16).
	if (class == "TextLabel" or class == "TextButton" or class == "TextBox") and not instance.TextScaled then
		local size = instance.TextSize
		if size <= 12 then
			instance.TextSize = size + 2
		elseif size <= 16 then
			instance.TextSize = size + 1
		end
	end
	-- Swap the old Gotham enum for the house faces (FontFace given explicitly always wins).
	if props.FontFace ~= nil then
		instance.FontFace = props.FontFace
	elseif (class == "TextLabel" or class == "TextButton" or class == "TextBox") then
		local face = FACES[instance.Font]
		if face then
			instance.FontFace = face
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Ui.corner(radius: number): UICorner
	return Ui.new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

function Ui.stroke(color: Color3, thickness: number, transparency: number?): UIStroke
	return Ui.new("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Ui.label(text: string, size: number, font: Enum.Font?, color: Color3?, props: { [string]: any }?): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		Font = font or Theme.BodyFont,
		TextColor3 = color or Theme.Text,
		Size = UDim2.new(1, 0, 0, size + 6),
	}
	if props then
		for key, value in props do
			base[key] = value
		end
	end
	return Ui.new("TextLabel", base)
end

-- The controller focus: a thick gold ring round whichever button the gamepad has selected, so
-- it reads from the sofa (vault: "Gamepad and Console UX"). One shared template; Roblox draws a
-- copy of it on the selected button.
Ui.SelectionRing = Ui.new("Frame", {
	Name = "SelectionRing",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(-5, -5),
	Size = UDim2.new(1, 10, 1, 10),
}, {
	Ui.corner(16),
	Ui.stroke(Color3.fromRGB(255, 206, 60), 4),
})

function Ui.button(text: string, props: { [string]: any }, onClick: () -> ()): TextButton
	local baseColor = props.BackgroundColor3 or Theme.PanelLight
	local hoverColor = baseColor:Lerp(Color3.new(1, 1, 1), 0.14)
	local pressColor = baseColor:Lerp(Color3.new(0, 0, 0), 0.2)
	local base: { [string]: any } = {
		Text = text,
		Font = Theme.TitleFont,
		TextSize = 22,
		TextColor3 = Theme.Text,
		BackgroundColor3 = baseColor,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 50),
	}
	-- Build 36: NoGrow = true keeps the button its size on hover (cards in a clipped row, and
	-- buttons sat close to text, where growing looked like a glitch).
	local grow = if props.NoGrow then 1 else 1.025
	for key, value in props do
		if key ~= "NoGrow" then
			base[key] = value
		end
	end
	local button: TextButton = Ui.new("TextButton", base, { Ui.corner(12) })
	local scale: UIScale = Ui.new("UIScale", { Parent = button })
	if button.Selectable then
		button.SelectionImageObject = Ui.SelectionRing
	end

	local hovering = false
	local function paint(color: Color3)
		TweenService:Create(button, FAST, { BackgroundColor3 = color }):Play()
	end
	local function setHover(on: boolean)
		hovering = on
		if not button.Active then
			return
		end
		paint(if on then hoverColor else baseColor)
		TweenService:Create(scale, FAST, { Scale = if on then grow else 1 }):Play()
	end
	button.MouseEnter:Connect(function()
		setHover(true)
	end)
	button.MouseLeave:Connect(function()
		setHover(false)
	end)
	button.SelectionGained:Connect(function()
		setHover(true)
	end)
	button.SelectionLost:Connect(function()
		setHover(false)
	end)
	button.MouseButton1Down:Connect(function()
		if button.Active then
			paint(pressColor)
			TweenService:Create(scale, FAST, { Scale = 0.97 }):Play()
		end
	end)
	button.MouseButton1Up:Connect(function()
		if button.Active then
			paint(if hovering then hoverColor else baseColor)
			TweenService:Create(scale, FAST, { Scale = if hovering then grow else 1 }):Play()
		end
	end)
	button.Activated:Connect(function()
		if button.Active then
			onClick()
		end
	end)
	return button
end

function Ui.fadeIn(frame: GuiObject)
	frame.Visible = true
	local scale = frame:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 0.96
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

return Ui
