--!strict
-- Turns physical input into semantic intent for keyboard and mouse, gamepad and touch.
-- Movement and aim are converted to world space using the camera's rink orientation, and
-- chat or menu focus always releases every control.

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local Prefs = require(script.Parent:WaitForChild("Prefs"))

local Controls = {}

local TURN_PER_PIXEL = Config.Stick.MouseTurnPerPixel

local enabled = false
-- The stick's angle around the body. Horizontal mouse movement turns it; the distance from the
-- body never changes. nil until the first sample, which starts it pointing up the rink.
local aimAngle: number? = nil
local READY_ANGLE = 0.7 -- radians toward screen-right from straight up the screen
-- Hold Left Alt to free the cursor (for clicking menu buttons) while in a match.
local cursorFree = false
-- Other reasons the cursor is free (the held scoreboard, the in-game menu), by name.
local cursorHolds: { [string]: boolean } = {}
-- Stick lift (left mouse / RT) raises the blade over the puck; puck lift (right mouse / LB)
-- opens the blade face for chips. There is no shoot button: you shoot by swinging the stick.
local mouseLift = false
local mouseLoft = false
local padLift = false
local padLoft = false
local touchLift = false
local touchLoft = false
local touchSprint = false
-- A dash press is latched until the next sim tick so a quick tap is never missed.
local dashTap = false
local touchBrake = false
local leftStick = Vector2.zero
local rightStick = Vector2.zero
local padLeft = Vector2.zero
local padRight = Vector2.zero
local lastAim = Vector2.new(0.7, 0)
local usingStickAim = false
local deadzone = 0.15
local touchGui: Frame? = nil

local function applyDeadzone(v: Vector2): Vector2
	local m = v.Magnitude
	if m < deadzone then
		return Vector2.zero
	end
	return v / m * math.min(1, (m - deadzone) / (1 - deadzone))
end

-- The stick angle the mouse is holding right now, read every rendered frame so the local stick
-- is drawn smoothly between fixed sim ticks. nil when the mouse isn't steering the stick.
function Controls.liveAim(): number?
	if enabled and not usingStickAim and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		return aimAngle
	end
	return nil
end

-- Frees the mouse cursor while `on` for the named reason (several can overlap).
function Controls.holdCursor(reason: string, on: boolean)
	cursorHolds[reason] = if on then true else nil
end

function Controls.setEnabled(on: boolean)
	enabled = on
	if not on then
		mouseLift, mouseLoft, padLift, padLoft = false, false, false, false
		touchLift, touchLoft, touchSprint, touchBrake = false, false, false, false
		dashTap = false
		leftStick, rightStick = Vector2.zero, Vector2.zero
		aimAngle = nil
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
	if touchGui then
		touchGui.Visible = on
		if not on and Controls.releaseTouches then
			Controls.releaseTouches()
		end
	end
end

local function chatFocused(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if not enabled then
		return
	end
	if processed then
		return
	end
	if Prefs.matches("lift", input) then
		mouseLift = true
		usingStickAim = false
	elseif Prefs.matches("loft", input) then
		-- Settings: puck lift can toggle (press once on, once off) instead of hold.
		mouseLoft = if Prefs.get("toggleLoft") then not mouseLoft else true
	elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
		padLift = true
	elseif input.KeyCode == Enum.KeyCode.ButtonL1 then
		padLoft = true
	end
	-- Dash: Left Shift, or A (L3 too, for players used to clicking the stick to sprint).
	if Prefs.matches("dash", input) or input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.ButtonL3 then
		dashTap = true
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if Prefs.matches("lift", input) then
		mouseLift = false
	elseif Prefs.matches("loft", input) then
		if not Prefs.get("toggleLoft") then
			mouseLoft = false
		end
	elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
		padLift = false
	elseif input.KeyCode == Enum.KeyCode.ButtonL1 then
		padLoft = false
	end
end)

UserInputService.InputChanged:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.Thumbstick1 then
		padLeft = Vector2.new(input.Position.X, input.Position.Y)
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		padRight = Vector2.new(input.Position.X, input.Position.Y)
		if padRight.Magnitude > 0.3 then
			usingStickAim = true
		end
	elseif input.UserInputType == Enum.UserInputType.MouseMovement then
		usingStickAim = false
	end
end)

-- Called first thing every rendered frame, before the fixed steps: while the mouse is locked,
-- its sideways movement spins the stick around the body, in that same frame. Moving the mouse
-- up or down does nothing, and with the mouse still the stick never moves.
-- Swing speed has a fixed top speed: small mouse moves turn the stick by exactly that much, and
-- any faster movement swings it at one steady speed instead of speeding up with the hand (or
-- with Windows pointer acceleration). Any extra movement is dropped, never stored.
local MAX_TURN_PER_FRAME = 2.4 -- under half a turn, so a wild flick can't wrap the wrong way
local SWING_SPEED = Config.Stick.MouseSwingSpeed
function Controls.pollMouse(dt: number)
	if
		enabled
		and aimAngle
		and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
		and UserInputService:GetFocusedTextBox() == nil
	then
		local dx = UserInputService:GetMouseDelta().X
		if dx ~= 0 then
			usingStickAim = false
			local turn = TURN_PER_PIXEL * Prefs.get("sensitivity") * (if Prefs.get("invertSpin") then -1 else 1)
			local cap = math.min(MAX_TURN_PER_FRAME, SWING_SPEED * Prefs.get("sensitivity") * math.max(dt, 1 / 240))
			local step = math.clamp(dx * turn, -cap, cap)
			aimAngle = ((aimAngle :: number) + step + math.pi) % (2 * math.pi) - math.pi
		end
	end
end

-- After each sim step: the aim becomes wherever the stick really is. If the boards (or the
-- turn limit) stopped it, that blocked turn is dropped, so the stick never keeps spinning on
-- its own afterwards to catch up with an old mouse movement.
function Controls.syncAim(yaw: number)
	if aimAngle ~= nil and not usingStickAim then
		aimAngle = yaw
	end
end

UserInputService.WindowFocusReleased:Connect(function()
	mouseLift, mouseLoft, padLift, padLoft = false, false, false, false
end)

-- screenForward is the rink direction shown as "up": +1 for team 1 (+X), -1 for team 2.
function Controls.sample(into: any, screenForward: number, _camera: Camera, _skaterPos: Vector3)
	-- Lock the mouse in the middle of the screen while skating so it can spin the stick forever
	-- without hitting the screen edge. Chat, Left Alt and menus free the cursor.
	cursorFree = Prefs.isDown("cursor") or next(cursorHolds) ~= nil
	deadzone = Prefs.get("deadzone")
	local lockMouse = enabled and not chatFocused() and not cursorFree and not UserInputService.TouchEnabled
	UserInputService.MouseBehavior = if lockMouse then Enum.MouseBehavior.LockCenter else Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = not lockMouse
	if aimAngle == nil then
		-- Start in a ready stance: blade out ahead and toward the forehand (screen-right) side,
		-- where the chase camera can see it instead of hiding it behind the helmet.
		aimAngle = if screenForward > 0 then READY_ANGLE else READY_ANGLE - math.pi
	end

	if not enabled or chatFocused() then
		into.moveX, into.moveZ = 0, 0
		into.charge, into.sprint, into.lift, into.loft, into.brake = false, false, false, false, false
		return
	end

	local forward, right = 0, 0
	if Prefs.isDown("up") then
		forward += 1
	end
	if Prefs.isDown("down") then
		forward -= 1
	end
	if Prefs.isDown("right") then
		right += 1
	end
	if Prefs.isDown("left") then
		right -= 1
	end
	local stick = applyDeadzone(padLeft)
	if stick.Magnitude < 0.01 then
		stick = leftStick
	end
	forward += stick.Y
	right += stick.X
	local mag = math.sqrt(forward * forward + right * right)
	if mag > 1 then
		forward, right = forward / mag, right / mag
	end
	-- Screen up is world X * screenForward; screen right is world Z * screenForward.
	into.moveX = forward * screenForward
	into.moveZ = right * screenForward

	local aimStick = applyDeadzone(padRight)
	if aimStick.Magnitude < 0.01 then
		aimStick = rightStick
	end
	if aimStick.Magnitude > 0.01 then
		-- Right stick / aim pad points the stick directly.
		lastAim = Vector2.new(aimStick.Y * screenForward, aimStick.X * screenForward).Unit
		aimAngle = math.atan2(lastAim.Y, lastAim.X)
		usingStickAim = true
	elseif not usingStickAim and not UserInputService.TouchEnabled then
		local a = aimAngle :: number
		lastAim = Vector2.new(math.cos(a), math.sin(a))
	end
	into.aimX, into.aimZ = lastAim.X, lastAim.Y

	into.charge = false
	into.lift = mouseLift or padLift or touchLift
	into.loft = mouseLoft or padLoft or touchLoft
	-- Dash (Left Shift / A / L3) and Stop (Space / B / LT) by default; keys come from Settings.
	into.sprint = Prefs.isDown("dash")
		or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA)
		or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL3)
		or touchSprint
		or dashTap
	dashTap = false
	into.brake = Prefs.isDown("brake")
		or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonB)
		or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL2)
		or touchBrake
end

-- Touch (vault: "Touch Gestures - Pinch, Pan, Swipe and Long Press", "Safe Areas and Insets").
-- Two floating thumb sticks: a thumb landing anywhere on the left side of the screen steers,
-- one landing on the right side swings the stick. Each stick is measured from where that
-- thumb first landed, so it reads the same on every phone whatever its top-bar inset. Action
-- buttons sit in reach of the right thumb (LIFT, CHIP) and the left thumb (DASH, STOP); a touch
-- that starts on any button never moves a stick.
local GuiService = game:GetService("GuiService")

local STICK_SIZE = 0.3 -- of the screen's shorter side
local touchRoot: Frame? = nil
type Pad = { zone: Frame, knob: Frame, home: UDim2, input: InputObject?, start: Vector2, onMove: (Vector2) -> () }
local pads: { [string]: Pad } = {}
local extrasBar: Frame? = nil

local function makePad(parent: Frame, name: string, home: UDim2, onMove: (Vector2) -> ()): Pad
	local zone = Instance.new("Frame")
	zone.Name = name
	zone.Position = home
	zone.Size = UDim2.fromScale(STICK_SIZE, STICK_SIZE)
	zone.AnchorPoint = Vector2.new(0.5, 0.5)
	zone.BackgroundColor3 = Color3.new(1, 1, 1)
	zone.BackgroundTransparency = 0.85
	zone.Active = false
	zone.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = zone
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = zone
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.5
	stroke.Thickness = 2
	stroke.Parent = zone
	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.Size = UDim2.fromScale(0.42, 0.42)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BackgroundTransparency = 0.3
	knob.Active = false
	knob.Parent = zone
	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob
	local pad: Pad = { zone = zone, knob = knob, home = home, input = nil, start = Vector2.zero, onMove = onMove }
	pads[name] = pad
	return pad
end

-- A touch position in the GUI's own space (the controls' ScreenGui ignores the top-bar inset,
-- touch positions don't): only used to draw the stick under the thumb.
local function toScale(root: Frame, p: Vector3): UDim2
	local inset = GuiService:GetGuiInset()
	local at = Vector2.new(p.X, p.Y) + inset
	local rel = (at - root.AbsolutePosition) / root.AbsoluteSize
	return UDim2.fromScale(math.clamp(rel.X, 0, 1), math.clamp(rel.Y, 0, 1))
end

local function padRadius(pad: Pad): number
	return math.max(30, pad.zone.AbsoluteSize.X / 2)
end

local function releasePad(pad: Pad)
	pad.input = nil
	pad.zone.Position = pad.home
	pad.zone.BackgroundTransparency = 0.85
	pad.knob.Position = UDim2.fromScale(0.5, 0.5)
	pad.onMove(Vector2.zero)
end

local function makeHoldButton(parent: Frame, text: string, position: UDim2, size: number, color: Color3, onChange: (boolean) -> ())
	local button = Instance.new("TextButton")
	button.Text = text
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = position
	button.Size = UDim2.fromScale(size, size)
	button.Font = Enum.Font.FredokaOne
	button.TextScaled = true
	button.TextColor3 = Color3.new(1, 1, 1)
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 0.2
	button.AutoButtonColor = false
	button.Selectable = false
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.4
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.16, 0)
	padding.PaddingRight = UDim.new(0.16, 0)
	padding.PaddingTop = UDim.new(0.16, 0)
	padding.PaddingBottom = UDim.new(0.16, 0)
	padding.Parent = button
	button.MouseButton1Down:Connect(function()
		onChange(true)
		button.BackgroundTransparency = 0
	end)
	local function release()
		onChange(false)
		button.BackgroundTransparency = 0.2
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
end

UserInputService.TouchStarted:Connect(function(input: InputObject, processed: boolean)
	local root = touchRoot
	-- A touch on a button (or any menu) is that button's, never a stick's.
	if processed or not enabled or not root or not root.Visible then
		return
	end
	local camera = workspace.CurrentCamera
	local width = if camera then camera.ViewportSize.X else 1000
	local pad = pads[if input.Position.X < width / 2 then "MoveStick" else "AimPad"]
	if not pad or pad.input then
		return
	end
	pad.input = input
	pad.start = Vector2.new(input.Position.X, input.Position.Y)
	pad.zone.Position = toScale(root, input.Position)
	pad.zone.BackgroundTransparency = 0.7
	pad.knob.Position = UDim2.fromScale(0.5, 0.5)
end)

UserInputService.TouchMoved:Connect(function(input: InputObject)
	for _, pad in pads do
		if pad.input == input then
			local v = (Vector2.new(input.Position.X, input.Position.Y) - pad.start) / padRadius(pad)
			if v.Magnitude > 1 then
				v = v.Unit
			end
			pad.knob.Position = UDim2.fromScale(0.5 + v.X * 0.5, 0.5 + v.Y * 0.5)
			pad.onMove(Vector2.new(v.X, -v.Y))
		end
	end
end)

UserInputService.TouchEnded:Connect(function(input: InputObject)
	for _, pad in pads do
		if pad.input == input then
			releasePad(pad)
		end
	end
end)

function Controls.setupTouch(screen: ScreenGui)
	if not UserInputService.TouchEnabled then
		return
	end
	local root = Instance.new("Frame")
	root.Name = "TouchControls"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = enabled
	root.Active = false
	root.Parent = screen
	touchGui = root
	touchRoot = root

	-- Resting spots; each stick jumps to wherever its thumb lands.
	makePad(root, "MoveStick", UDim2.fromScale(0.16, 0.7), function(v)
		leftStick = v
	end)
	makePad(root, "AimPad", UDim2.fromScale(0.84, 0.7), function(v)
		-- The stick points where the thumb drags; a thumb that has barely moved from where it
		-- landed leaves the stick where it was (no twitching on touch-down).
		rightStick = if v.Magnitude >= 0.25 then v else Vector2.zero
	end)
	-- Hold buttons mirror the mouse buttons and keys. All at least 0.13 of the short side
	-- (about 50 px on a phone), above the 44 px touch target minimum.
	makeHoldButton(root, "LIFT", UDim2.fromScale(0.66, 0.86), 0.16, Color3.fromRGB(255, 120, 40), function(down)
		touchLift = down
	end)
	makeHoldButton(root, "CHIP", UDim2.fromScale(0.68, 0.62), 0.13, Color3.fromRGB(150, 90, 230), function(down)
		touchLoft = down
	end)
	makeHoldButton(root, "DASH", UDim2.fromScale(0.34, 0.86), 0.16, Color3.fromRGB(40, 150, 220), function(down)
		touchSprint = down
	end)
	makeHoldButton(root, "STOP", UDim2.fromScale(0.32, 0.62), 0.13, Color3.fromRGB(60, 60, 70), function(down)
		touchBrake = down
	end)

	-- Practice and pond extras (reset puck, add a puck, goalie), top left under the menu button.
	local bar = Instance.new("Frame")
	bar.Name = "Extras"
	bar.BackgroundTransparency = 1
	bar.Position = UDim2.new(0, 12, 0, 116)
	bar.Size = UDim2.fromOffset(120, 200)
	bar.Visible = false
	bar.Parent = root
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = bar
	extrasBar = bar
end

-- Shows these tap buttons (text, action) for practice and the pond on touch screens, or hides
-- them all (nil).
function Controls.setTouchExtras(actions: { { text: string, run: () -> () } }?)
	local bar = extrasBar
	if not bar then
		return
	end
	for _, child in bar:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	bar.Visible = actions ~= nil and #actions > 0
	for i, action in actions or {} do
		local b = Instance.new("TextButton")
		b.Text = action.text
		b.LayoutOrder = i
		b.Size = UDim2.fromOffset(120, 48)
		b.Font = Enum.Font.FredokaOne
		b.TextSize = 20
		b.TextColor3 = Color3.new(1, 1, 1)
		b.BackgroundColor3 = Color3.fromRGB(16, 24, 46)
		b.BackgroundTransparency = 0.15
		b.Selectable = false
		b.Parent = bar
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = b
		b.Activated:Connect(action.run)
	end
end

-- Lets go of both thumb sticks (when the controls switch off mid-touch).
local function releaseTouches()
	for _, pad in pads do
		if pad.input then
			releasePad(pad)
		end
	end
end
Controls.releaseTouches = releaseTouches

return Controls
