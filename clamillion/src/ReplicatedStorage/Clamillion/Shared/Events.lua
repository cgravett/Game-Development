-- Limited-time events (the Halloween event, and any future ones).
--
-- The SERVER decides whether an event is on (from the clock) and publishes it on
-- ReplicatedStorage.Clamillion as an attribute ("HalloweenActive" = true/false), so every
-- player's game switches at exactly the same moment.
--
-- HALLOWEEN 2026: Friday Oct 30, 5:30 PM Eastern  ->  Sunday Nov 1, 11:55 PM Eastern.
-- Clocks fall back on Sunday Nov 1 at 2 AM, so the start is in EDT (UTC-4) and the end in EST (UTC-5):
--   start = Oct 30 21:30 UTC, end = Nov 2 04:55 UTC.
--
-- TESTING IN STUDIO: select Workspace and add a boolean attribute "HalloweenPreview".
--   true  = the event is ON in your playtest (Halloween lobby, rewards tab, claims all work)
--   false = the event is OFF in your playtest, even during the real event dates
--   (no attribute) = use the real clock
-- The attribute is ignored in the live game.
local RunService = game:GetService("RunService")

local Events = {}

Events.List = {
	halloween = {
		id = "halloween",
		name = "Halloween",
		attribute = "HalloweenActive",
		preview = "HalloweenPreview",
		startsAt = DateTime.fromUniversalTime(2026, 10, 30, 21, 30, 0).UnixTimestamp,
		endsAt = DateTime.fromUniversalTime(2026, 11, 2, 4, 55, 0).UnixTimestamp,
		endsText = "Sunday 11:55 PM ET",
	},
}

local function root() return game:GetService("ReplicatedStorage"):FindFirstChild("Clamillion") end

-- SERVER: is the event on right now? (clock + Studio preview switch)
function Events.computeActive(id, now)
	local e = Events.List[id]
	if not e then return false end
	if RunService:IsStudio() then
		local force = workspace:GetAttribute(e.preview)
		if type(force) == "boolean" then return force end
	end
	now = now or os.time()
	return now >= e.startsAt and now < e.endsAt
end

-- ANYWHERE: is the event on? Clients read what the server published.
function Events.isActive(id)
	local e = Events.List[id]
	if not e then return false end
	if RunService:IsServer() then return Events.computeActive(id) end
	local r = root()
	return r ~= nil and r:GetAttribute(e.attribute) == true
end

-- seconds until the event ends (0 if it's over), using the server's clock
function Events.secondsLeft(id)
	local e = Events.List[id]
	if not e then return 0 end
	local now = RunService:IsServer() and os.time() or workspace:GetServerTimeNow()
	return math.max(0, e.endsAt - now)
end

-- fires fn(active) now and whenever the event turns on/off (client or server)
function Events.watch(id, fn)
	local e = Events.List[id]
	local r = root()
	if not (e and r) then return end
	fn(r:GetAttribute(e.attribute) == true)
	return r:GetAttributeChangedSignal(e.attribute):Connect(function() fn(r:GetAttribute(e.attribute) == true) end)
end

return Events
