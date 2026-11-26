--!strict
-- Player settings: defaults, limits and the key bindings. Shared so the server can clean a
-- saved or sent settings table with exactly the rules the client menu uses. Anything unknown
-- or out of range falls back to the default, so a bad save can never break controls.

local Settings = {}

export type Values = { [string]: any }

-- Number settings: { default, min, max, step }.
Settings.Numbers = table.freeze({
	sensitivity = table.freeze({ 0.5, 0.2, 3, 0.1 }), -- mouse stick-spin speed (default 0.5 since Build 26)
	-- Not shown in the menu: which defaults a saved table was made under (see sanitize).
	settingsVersion = table.freeze({ 2, 1, 99, 1 }),
	zoom = table.freeze({ 1, 0.6, 1.6, 0.05 }), -- camera distance
	fov = table.freeze({ 48, 36, 75, 1 }), -- camera field of view
	follow = table.freeze({ 6, 2, 14, 0.5 }), -- how tightly the camera follows
	deadzone = table.freeze({ 0.15, 0.05, 0.4, 0.01 }), -- gamepad stick deadzone
	volume = table.freeze({ 0.7, 0, 1, 0.05 }),
	uiScale = table.freeze({ 1, 0.8, 1.3, 0.05 }), -- player UI size, on top of the automatic fit
	zoomStep = table.freeze({ 0.1, 0.02, 0.3, 0.02 }), -- zoom per wheel notch
	camHeight = table.freeze({ 52, 30, 80, 1 }), -- camera height over the ice
	camBack = table.freeze({ 42, 18, 70, 1 }), -- how far behind the skater the camera sits
	camAhead = table.freeze({ 12, -10, 30, 1 }), -- how far up the ice the camera looks
	flipTime = table.freeze({ 0.3, 0, 0.5, 0.05 }), -- seconds the camera flip takes (0 = instant)
	-- Choices are stored as numbers (an index into the matching list below).
	stickColor = table.freeze({ 1, 1, 8, 1 }),
	puckColor = table.freeze({ 1, 1, 8, 1 }),
	trailGround = table.freeze({ 6, 1, 8, 1 }),
	trailAir = table.freeze({ 5, 1, 8, 1 }),
	nameSize = table.freeze({ 1, 0.6, 1.6, 0.05 }),
	minimapScale = table.freeze({ 1, 0.6, 1.6, 0.05 }),
	meterScale = table.freeze({ 1, 0.6, 1.8, 0.05 }),
	meterOpacity = table.freeze({ 1, 0.2, 1, 0.05 }),
	arena = table.freeze({ 1, 1, 4, 1 }), -- 1 = the match's own arena
	sfxVolume = table.freeze({ 1, 0, 1, 0.05 }), -- stick, puck and board sounds
	crowdVolume = table.freeze({ 1, 0, 1, 0.05 }),
	hornVolume = table.freeze({ 1, 0, 1, 0.05 }),
})

-- Labels for the number settings that are really choices.
Settings.Colors = table.freeze({
	{ "Yellow", Color3.fromRGB(255, 214, 40) },
	{ "Cyan", Color3.fromRGB(60, 220, 255) },
	{ "Pink", Color3.fromRGB(255, 90, 200) },
	{ "Lime", Color3.fromRGB(120, 240, 70) },
	{ "Blue", Color3.fromRGB(40, 110, 255) },
	{ "White", Color3.fromRGB(255, 255, 255) },
	{ "Orange", Color3.fromRGB(255, 140, 30) },
	{ "Red", Color3.fromRGB(240, 50, 50) },
})
Settings.Arenas = table.freeze({ "Match default", "Arena", "Night", "Timberline" })

Settings.Toggles = table.freeze({
	shake = true,
	invertSpin = false,
	reduceParticles = false,
	highContrast = false,
	nameTags = true,
	lowGraphics = false,
	matchCamera = true, -- movement keys follow the camera flip
	toggleLoft = false, -- puck lift key toggles instead of hold
	puckOutline = false, -- always outline the puck, not only when hidden
	teamRings = true,
	ownRing = true,
	ownName = true,
	minimap = true,
	showFps = false,
	showPing = true,
	scoreBug = true,
	camSmooth = true,
	shadows = true,
	bloom = true,
	grade = true,
})

-- Rebindable keyboard / mouse actions, in menu order. Gamepad buttons stay fixed.
Settings.Actions = table.freeze({
	{ id = "up", label = "Skate up", default = "W" },
	{ id = "down", label = "Skate down", default = "S" },
	{ id = "left", label = "Skate left", default = "A" },
	{ id = "right", label = "Skate right", default = "D" },
	{ id = "lift", label = "Stick lift", default = "MouseButton1" },
	{ id = "loft", label = "Puck lift", default = "MouseButton2" },
	{ id = "dash", label = "Dash", default = "LeftShift" },
	{ id = "brake", label = "Stop", default = "Space" },
	{ id = "flip", label = "Flip camera", default = "E" },
	{ id = "cursor", label = "Free cursor (hold)", default = "LeftAlt" },
	{ id = "reset", label = "Reset puck (practice)", default = "R" },
	{ id = "addPuck", label = "Add a puck (practice)", default = "P" },
	{ id = "goalie", label = "Goalie on / off (practice)", default = "G" },
	{ id = "hud", label = "Hide HUD", default = "F3" },
	{ id = "board", label = "Scoreboard (hold)", default = "Tab" },
})

local MOUSE = { MouseButton1 = "Left click", MouseButton2 = "Right click", MouseButton3 = "Middle click" }
-- Keys that can never be bound: they belong to Roblox or the menus.
local RESERVED = { Escape = true, Slash = true, Backquote = true, F9 = true, F11 = true, F12 = true, Unknown = true }

local keyNames: { [string]: boolean } = {}
for _, item in Enum.KeyCode:GetEnumItems() do
	keyNames[item.Name] = true
end

function Settings.validBind(bind: any): boolean
	if type(bind) ~= "string" then
		return false
	end
	if MOUSE[bind] then
		return true
	end
	return keyNames[bind] == true and not RESERVED[bind] and string.sub(bind, 1, 6) ~= "Button" and string.sub(bind, 1, 4) ~= "DPad" and string.sub(bind, 1, 10) ~= "Thumbstick"
end

function Settings.bindLabel(bind: string): string
	if MOUSE[bind] then
		return MOUSE[bind]
	end
	local pretty = {
		LeftShift = "Left Shift", RightShift = "Right Shift", LeftControl = "Left Ctrl", RightControl = "Right Ctrl",
		LeftAlt = "Left Alt", RightAlt = "Right Alt", Space = "Space", Return = "Enter", Tab = "Tab",
		Up = "Up", Down = "Down", Left = "Left", Right = "Right", CapsLock = "Caps Lock",
	}
	return pretty[bind] or bind
end

function Settings.defaults(): Values
	local out: Values = {}
	for name, spec in Settings.Numbers do
		out[name] = spec[1]
	end
	for name, value in Settings.Toggles do
		out[name] = value
	end
	local binds = {}
	for _, action in Settings.Actions do
		binds[action.id] = action.default
	end
	out.binds = binds
	return out
end

-- Returns a clean copy: every field present, in range, and every bind valid and unique.
function Settings.sanitize(raw: any): Values
	local out = Settings.defaults()
	if type(raw) ~= "table" then
		return out
	end
	for name, spec in Settings.Numbers do
		local n = tonumber(raw[name])
		if n and n == n and n > -math.huge and n < math.huge then
			out[name] = math.clamp(n, spec[2], spec[3])
		end
	end
	-- Build 26 made 0.5 the default sensitivity; a save from before that still on the old
	-- default of 1 moves to the new one (anyone who picked another value keeps it).
	if (tonumber(raw.settingsVersion) or 1) < 2 and tonumber(raw.sensitivity) == 1 then
		out.sensitivity = 0.5
	end
	out.settingsVersion = 2
	for name in Settings.Toggles do
		if type(raw[name]) == "boolean" then
			out[name] = raw[name]
		end
	end
	if type(raw.binds) == "table" then
		local used: { [string]: boolean } = {}
		local wanted: { [string]: string } = {}
		for _, action in Settings.Actions do
			local bind = raw.binds[action.id]
			if Settings.validBind(bind) and not used[bind] then
				used[bind] = true
				wanted[action.id] = bind
			end
		end
		-- Actions left without a key get their default unless another action already took it.
		for _, action in Settings.Actions do
			local bind = wanted[action.id]
			if not bind then
				bind = if used[action.default] then "" else action.default
				used[bind] = true
			end
			out.binds[action.id] = bind
		end
	end
	return out
end

return Settings
