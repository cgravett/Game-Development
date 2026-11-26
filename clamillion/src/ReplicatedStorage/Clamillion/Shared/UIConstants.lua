-- Shared, non-secret presentation constants (safe for clients).
local UIConstants = {}

-- Bright, candy-coloured palette for a playful, kid-friendly look.
UIConstants.Colors = {
	Panel = Color3.fromRGB(112, 60, 230),
	PanelDark = Color3.fromRGB(66, 30, 156),
	PanelPink = Color3.fromRGB(255, 92, 182),
	Gold = Color3.fromRGB(255, 214, 40),
	GoldDark = Color3.fromRGB(235, 125, 0),
	White = Color3.new(1, 1, 1),
	Muted = Color3.fromRGB(230, 220, 255),
	Danger = Color3.fromRGB(255, 86, 110),
	Good = Color3.fromRGB(80, 230, 120),
	Ink = Color3.fromRGB(52, 20, 96),
	Outline = Color3.fromRGB(44, 14, 84),
	Sky = Color3.fromRGB(60, 190, 255),
	Mint = Color3.fromRGB(80, 230, 170),
}

-- Mode colours match the lobby pads.
UIConstants.Modes = {
	Solo = { label = "SOLO", players = "1 player", color = Color3.fromRGB(255, 200, 40), icon = "★" },
	Duel = { label = "1V1", players = "2 players", color = Color3.fromRGB(60, 170, 255), icon = "⚔" },
	Triple = { label = "1V1V1", players = "3 players", color = Color3.fromRGB(255, 70, 110), icon = "👑" },
}

-- Seat accents always pair a colour with an icon + label so meaning never relies on colour alone.
UIConstants.Seats = {
	{ color = Color3.fromRGB(255, 99, 99), icon = "◆", label = "P1" },
	{ color = Color3.fromRGB(80, 220, 140), icon = "●", label = "P2" },
	{ color = Color3.fromRGB(190, 120, 255), icon = "▲", label = "P3" },
}

UIConstants.Rarity = {
	common = { label = "COMMON", color = Color3.fromRGB(205, 215, 235) },
	too_clever = { label = "TOO CLEVER", color = Color3.fromRGB(255, 175, 110) },
	uncommon = { label = "UNCOMMON", color = Color3.fromRGB(110, 225, 140) },
	rare = { label = "RARE", color = Color3.fromRGB(95, 175, 255) },
	very_rare = { label = "VERY RARE", color = Color3.fromRGB(200, 140, 255) },
	extremely_rare = { label = "EXTREMELY RARE", color = Color3.fromRGB(242, 196, 70) },
}

UIConstants.Status = {
	Waiting = "",
	Thinking = "💭 Thinking",
	Locked = "🔒 Locked In",
	TimeUp = "⏱ Time Up",
	Withdrawn = "✖ Left",
	Out = "— Sitting out",
	Winner = "🏆 Winner",
}

UIConstants.Font = Enum.Font.FredokaOne
UIConstants.FontBlack = Enum.Font.FredokaOne
UIConstants.FontBody = Enum.Font.FredokaOne

function UIConstants.formatNumber(n)
	n = math.floor(n or 0)
	local neg = n < 0
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then out = out:sub(2) end
	return (neg and "-" or "") .. out
end

function UIConstants.seatTag(seat)
	local s = UIConstants.Seats[seat]
	return s and (s.icon .. " " .. s.label) or ""
end

return UIConstants

