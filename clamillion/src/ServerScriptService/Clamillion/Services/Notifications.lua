-- Experience notifications (Creator Hub > Engagement > Notifications). Server-only.
--
-- SETUP (one time, by the game owner):
--   1. Creator Hub > Open Cloud > API Keys > Create API Key. Add the "user-notification" API
--      system with this experience and the write permission.
--   2. Creator Hub > this experience > Configurations > Secrets > Create Secret, name it
--      exactly NotificationsKey and paste the API key as its value.
--   3. Studio: File > Experience Settings > Security > Allow HTTP Requests = ON (already on).
-- Until the secret exists, sending is switched off quietly (one warning in the output).
-- Roblox only delivers to players who opted in (13+), at most 1 per player per day per game, and
-- only once the game has 100+ visits.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Notifications = {}
Notifications.Messages = {
	friendWon = "54359276-b9f4-0a4e-8de4-6ae2ac5f03f5", -- "{userId-winner} just won a show! Think you can beat them? 🏆"
	dethroned = "481a0b74-6125-a049-9574-3ec09725a0a3", -- "Someone just knocked you off #1 on the {mode} leaderboard! Take back your crown 👑"
}
local UNIVERSE = "universes/" .. tostring(game.GameId)
local ENDPOINT = "https://apis.roblox.com/cloud/v2/users/%d/notifications"

local key, disabled
local function apiKey()
	if disabled then return nil end
	if key then return key end
	local ok, secret = pcall(function() return HttpService:GetSecret("NotificationsKey") end)
	if ok and secret then key = secret return key end
	disabled = true
	warn("[Clamillion] Notifications are off: add the NotificationsKey secret (see Notifications module).")
	return nil
end

local recent = {} -- "message:userId" -> os.time() (don't re-send within a few hours from this server)

-- params: { name = number (sent as int64, e.g. a userId) | string }
function Notifications.send(userId, messageKey, params, category)
	local messageId = Notifications.Messages[messageKey]
	if not messageId or type(userId) ~= "number" or userId <= 0 then return end
	if game.GameId == 0 or game:GetService("RunService"):IsStudio() then return end -- live servers only
	local tag = messageKey .. ":" .. userId
	if recent[tag] and os.time() - recent[tag] < 6 * 3600 then return end
	recent[tag] = os.time()
	local secret = apiKey()
	if not secret then return end
	local parameters = {}
	for name, value in pairs(params or {}) do
		parameters[name] = type(value) == "number" and { int64_value = value } or { string_value = tostring(value) }
	end
	task.spawn(function()
		local ok, res = pcall(function()
			return HttpService:RequestAsync({
				Url = ENDPOINT:format(userId),
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json", ["x-api-key"] = secret },
				Body = HttpService:JSONEncode({
					source = { universe = UNIVERSE },
					payload = { message_id = messageId, type = "MOMENT", parameters = parameters },
					analytics_data = { category = category or messageKey },
				}),
			})
		end)
		if not ok then
			warn("[Clamillion] Notification failed: " .. tostring(res))
		elseif not res.Success and res.StatusCode ~= 429 then
			warn(("[Clamillion] Notification %s -> %d: %s"):format(messageKey, res.StatusCode, string.sub(res.Body or "", 1, 200)))
		end
	end)
end

-- A player won a 1v1 / 1v1v1: tell their friends who aren't in this server (up to 50).
function Notifications.friendWon(winner)
	if not winner or winner.Parent ~= Players then return end
	local winnerId = winner.UserId
	task.spawn(function()
		local ok, pages = pcall(function() return Players:GetFriendsAsync(winnerId) end)
		if not ok or not pages then return end
		local sent = 0
		while sent < 50 do
			for _, f in ipairs(pages:GetCurrentPage()) do
				if sent >= 50 then break end
				if not Players:GetPlayerByUserId(f.Id) then
					Notifications.send(f.Id, "friendWon", { ["userId-winner"] = winnerId })
					sent += 1
					task.wait(0.2)
				end
			end
			if pages.IsFinished then break end
			local more = pcall(function() pages:AdvanceToNextPageAsync() end)
			if not more then break end
		end
	end)
end

return Notifications
