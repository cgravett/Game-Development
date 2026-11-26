-- Clamillion server entry point.
local Services = script.Parent.Services
local QuestionService = require(Services.QuestionService)
local StageService = require(Services.StageService)
local MatchService = require(Services.MatchService)
local QueueService = require(Services.QueueService)

local ShopService=require(Services.ShopService)
local LobbyService=require(Services.LobbyService)
QuestionService.init()
StageService.init()
local Players=game:GetService("Players")
local BadgeAwards=require(Services.BadgeAwards)
local Notifications=require(Services.Notifications)
local function onResults(mode, standings, winnerIds)
	LobbyService.record(mode, standings)
	-- every finished show adds to each player's total score (for the Rewards stand)
	for _, row in ipairs(standings) do
		local p = row.userId and not row.withdrawn and Players:GetPlayerByUserId(row.userId)
		if p then
			ShopService.addScore(p, row.score)
			BadgeAwards.award(p, "welcome")
			if row.score >= BadgeAwards.BigScore then BadgeAwards.award(p, "bigscore") end
			if mode ~= "Solo" and winnerIds and winnerIds[row.userId] then
				BadgeAwards.award(p, "champion")
				Notifications.friendWon(p)
			end
		end
	end
end
MatchService.init({ onMatchEnded = function() QueueService.tryStart() end, onResults=onResults })
QueueService.init({ start = MatchService.start, isActive = MatchService.isActive, isInMatch = MatchService.isInMatch })
ShopService.init(MatchService.isInMatch)
LobbyService.init(MatchService.isInMatch)
require(Services.ObbyService).init(MatchService.isInMatch)
-- limited-time Halloween event: switches itself on/off on schedule (Shared.Events)
require(Services.HalloweenEvent).init()
print("[Clamillion] Server ready")

