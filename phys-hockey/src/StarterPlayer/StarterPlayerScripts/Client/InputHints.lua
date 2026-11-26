--!strict
-- Which device the player is using right now (keyboard and mouse, gamepad or touch) and what
-- each control is called on it, so every prompt names the button the player actually has.
-- Vault: "Onboarding Accessibility and Cross-Device Prompts", "Gamepad and Console UX".

local UserInputService = game:GetService("UserInputService")

local Prefs = require(script.Parent:WaitForChild("Prefs"))

local InputHints = {}

export type Device = "kbm" | "pad" | "touch"

local listeners: { (Device) -> () } = {}
local current: Device = "kbm"

local function fromPreferred(): Device?
	local ok, value = pcall(function(): any
		return (UserInputService :: any).PreferredInput
	end)
	if not ok or value == nil then
		return nil
	end
	local okPad, pad = pcall(function(): any
		return (Enum :: any).PreferredInput.Gamepad
	end)
	local okTouch, touch = pcall(function(): any
		return (Enum :: any).PreferredInput.Touch
	end)
	if okPad and value == pad then
		return "pad"
	elseif okTouch and value == touch then
		return "touch"
	end
	return "kbm"
end

local function fromLastInput(t: Enum.UserInputType): Device?
	if t == Enum.UserInputType.Touch then
		return "touch"
	elseif string.sub(t.Name, 1, 7) == "Gamepad" then
		return "pad"
	elseif t == Enum.UserInputType.Keyboard or string.sub(t.Name, 1, 5) == "Mouse" then
		return "kbm"
	end
	return nil
end

local function detect(): Device
	local preferred = fromPreferred()
	if preferred then
		return preferred
	end
	local last = fromLastInput(UserInputService:GetLastInputType())
	if last then
		return last
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "pad"
	end
	return "kbm"
end

local function set(device: Device)
	if device ~= current then
		current = device
		for _, fn in listeners do
			task.spawn(fn, device)
		end
	end
end

current = detect()
pcall(function()
	(UserInputService :: any):GetPropertyChangedSignal("PreferredInput"):Connect(function()
		set(detect())
	end)
end)
UserInputService.LastInputTypeChanged:Connect(function(t: Enum.UserInputType)
	-- Only when PreferredInput isn't available: it already ignores stray events (a phone's
	-- accelerometer, a resting controller) that would make prompts flicker.
	if fromPreferred() == nil then
		local device = fromLastInput(t)
		if device then
			set(device)
		end
	end
end)

function InputHints.device(): Device
	return current
end

function InputHints.onChanged(fn: (Device) -> ())
	table.insert(listeners, fn)
end

-- PlayStation controllers name their buttons differently; the platform's own glyph image tells
-- which pad is connected.
local function playStation(): boolean
	local ok, image = pcall(function(): string
		return UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonA)
	end)
	if not ok or type(image) ~= "string" then
		return false
	end
	local lower = string.lower(image)
	return string.find(lower, "playstation", 1, true) ~= nil or string.find(lower, "ps4", 1, true) ~= nil or string.find(lower, "ps5", 1, true) ~= nil
end

local PAD_XBOX = {
	ButtonA = "A", ButtonB = "B", ButtonX = "X", ButtonY = "Y",
	ButtonL1 = "LB", ButtonR1 = "RB", ButtonL2 = "LT", ButtonR2 = "RT",
	ButtonL3 = "L3", ButtonR3 = "R3", ButtonSelect = "View", DPadRight = "D-pad right", DPadLeft = "D-pad left",
}
local PAD_PS = {
	ButtonA = "Cross", ButtonB = "Circle", ButtonX = "Square", ButtonY = "Triangle",
	ButtonL1 = "L1", ButtonR1 = "R1", ButtonL2 = "L2", ButtonR2 = "R2",
	ButtonL3 = "L3", ButtonR3 = "R3", ButtonSelect = "Create", DPadRight = "D-pad right", DPadLeft = "D-pad left",
}

-- The gamepad button for each action (Controls and Main.client read the same table).
InputHints.Pad = {
	dash = Enum.KeyCode.ButtonA,
	brake = Enum.KeyCode.ButtonB,
	lift = Enum.KeyCode.ButtonR2,
	loft = Enum.KeyCode.ButtonL1,
	reset = Enum.KeyCode.ButtonX,
	addPuck = Enum.KeyCode.ButtonY,
	goalie = Enum.KeyCode.DPadRight,
	flip = Enum.KeyCode.ButtonR1,
	menu = Enum.KeyCode.ButtonSelect,
	board = Enum.KeyCode.DPadLeft,
}

function InputHints.padName(key: Enum.KeyCode): string
	local names = if playStation() then PAD_PS else PAD_XBOX
	return (names :: any)[key.Name] or key.Name
end

-- Touch button labels (Controls draws these).
local TOUCH = {
	dash = "DASH",
	brake = "STOP",
	lift = "LIFT",
	loft = "CHIP",
	reset = "PUCK",
	addPuck = "+ PUCK",
	goalie = "GOALIE",
	menu = "MENU",
}

-- The name of the control for `action` on the current device, ready to drop into a sentence:
-- "Left Shift", "A", "the DASH button".
function InputHints.key(action: string): string
	if current == "pad" then
		local key = (InputHints.Pad :: any)[action]
		return if key then InputHints.padName(key) else "-"
	elseif current == "touch" then
		local label = (TOUCH :: any)[action]
		return if label then `the {label} button` else "-"
	end
	return Prefs.label(action)
end

-- How to skate, and how to swing the stick, as a phrase.
function InputHints.move(): string
	if current == "pad" then
		return "the left stick"
	elseif current == "touch" then
		return "your left thumb (drag anywhere on the left side)"
	end
	return `{Prefs.label("up")} {Prefs.label("left")} {Prefs.label("down")} {Prefs.label("right")}`
end

function InputHints.swing(): string
	if current == "pad" then
		return "the right stick"
	elseif current == "touch" then
		return "your right thumb (drag anywhere on the right side)"
	end
	return "the mouse (move it left and right)"
end

-- "Hold X" / "Press X" / "Tap X" in the device's words.
function InputHints.hold(action: string): string
	return `hold {InputHints.key(action)}`
end

function InputHints.press(action: string): string
	return `{if current == "touch" then "tap" else "press"} {InputHints.key(action)}`
end

return InputHints
