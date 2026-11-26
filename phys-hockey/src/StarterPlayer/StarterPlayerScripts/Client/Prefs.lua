--!strict
-- The local player's settings and key bindings. The saved copy arrives with the profile; every
-- change applies at once and is sent to the server a moment later (one save per burst of
-- slider clicks, inside the action rate limit).

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Settings = require(Shared:WaitForChild("Settings"))
local Protocol = require(Shared:WaitForChild("Protocol"))

local Prefs = {}

local current: Settings.Values = Settings.defaults()
local listeners: { (name: string, value: any) -> () } = {}
local touched = false -- once the player edits anything, later profile pushes don't overwrite it
local saveToken = 0
local SAVE_DELAY = 1.5

local function fire(name: string, value: any)
	for _, fn in listeners do
		task.spawn(fn, name, value)
	end
end

local function scheduleSave()
	touched = true
	saveToken += 1
	local token = saveToken
	task.delay(SAVE_DELAY, function()
		if token == saveToken then
			local remotes = ReplicatedStorage:FindFirstChild("Remotes")
			local remote = remotes and remotes:FindFirstChild(Protocol.Remotes.Shop)
			if remote then
				(remote :: RemoteEvent):FireServer("Settings", current)
			end
		end
	end)
end

function Prefs.get(name: string): any
	return current[name]
end

function Prefs.bind(action: string): string
	return current.binds[action] or ""
end

-- fn(name, value) runs for every change; name "*" means everything changed at once.
function Prefs.onChanged(fn: (name: string, value: any) -> ())
	table.insert(listeners, fn)
end

function Prefs.set(name: string, value: any)
	local spec = Settings.Numbers[name]
	if spec then
		local n = tonumber(value) or spec[1]
		n = math.clamp(math.round(n / spec[4]) * spec[4], spec[2], spec[3])
		value = n
	elseif Settings.Toggles[name] == nil then
		return
	end
	if current[name] == value then
		return
	end
	current[name] = value
	fire(name, value)
	scheduleSave()
end

-- Binding a key that another action already uses swaps the two, so nothing is ever doubled.
function Prefs.setBind(action: string, bind: string)
	if not Settings.validBind(bind) then
		return
	end
	local old = current.binds[action]
	for id, other in current.binds do
		if id ~= action and other == bind then
			current.binds[id] = old or ""
		end
	end
	current.binds[action] = bind
	fire("binds", current.binds)
	scheduleSave()
end

-- A copy of every setting, for the Settings panel's CANCEL.
function Prefs.snapshot(): Settings.Values
	local copy = table.clone(current)
	copy.binds = table.clone(current.binds)
	return copy
end

function Prefs.restore(snap: Settings.Values)
	current = Settings.sanitize(snap)
	fire("*", current)
	scheduleSave()
end

function Prefs.resetAll()
	current = Settings.defaults()
	fire("*", current)
	scheduleSave()
end

-- Resets just these settings (and the key bindings when `binds` is true) to their defaults.
function Prefs.resetSome(names: { string }, binds: boolean?)
	local defaults = Settings.defaults()
	for _, name in names do
		if defaults[name] ~= nil then
			current[name] = defaults[name]
		end
	end
	if binds then
		current.binds = defaults.binds
	end
	fire("*", current)
	scheduleSave()
end

function Prefs.loadFromProfile(raw: any)
	if touched or raw == nil then
		return
	end
	current = Settings.sanitize(raw)
	fire("*", current)
end

-- True when this input event is the key or mouse button bound to the action.
function Prefs.matches(action: string, input: InputObject): boolean
	local bind = current.binds[action]
	if not bind or bind == "" then
		return false
	end
	if string.sub(bind, 1, 11) == "MouseButton" then
		return input.UserInputType.Name == bind
	end
	return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == bind
end

function Prefs.isDown(action: string): boolean
	local bind = current.binds[action]
	if not bind or bind == "" then
		return false
	end
	if string.sub(bind, 1, 11) == "MouseButton" then
		return UserInputService:IsMouseButtonPressed((Enum.UserInputType :: any)[bind])
	end
	return UserInputService:IsKeyDown((Enum.KeyCode :: any)[bind])
end

function Prefs.label(action: string): string
	local bind = current.binds[action]
	if not bind or bind == "" then
		return "-"
	end
	return Settings.bindLabel(bind)
end

return Prefs
