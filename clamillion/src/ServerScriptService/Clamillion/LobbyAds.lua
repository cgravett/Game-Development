-- Slides shown on the lobby ad boards (workspace.ShowLobby.AdBoards).
-- Edit this list to advertise updates, events or shop items; boards cycle through it,
-- each one starting on a different slide. Colours are the top/bottom of the background.
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

return {
	Seconds = 8, -- how long each slide stays up
	Slides = {
		{ tag = "NEW ARENA!", icon = "🐋", title = "Underwater Aquarium", body = "Play the show under the sea! 500 R$ in the Shop.", colors = { rgb(30, 170, 220), rgb(10, 50, 130) } },
		{ tag = "SHOP", icon = "🦄", title = "Custom Podiums", body = "10 themes: Unicorn, Dino, Galaxy & more! 200 R$ each.", colors = { rgb(255, 120, 200), rgb(140, 70, 230) } },
		{ tag = "SHOP", icon = "🏷", title = "Show Off a Title", body = "20 titles for your podium. Just 50 R$!", colors = { rgb(255, 180, 40), rgb(230, 70, 60) } },
		{ tag = "DAILY", icon = "🎡", title = "Spin the Daily Wheel", body = "One free spin every day. Resets at 10 AM!", colors = { rgb(255, 92, 182), rgb(90, 60, 230) } },
		{ tag = "UPDATE", icon = "🏃", title = "Bigger Mini Obby!", body = "New stages and a sky-high tower. Can you beat it?", colors = { rgb(80, 220, 120), rgb(20, 120, 160) } },
		{ tag = "TIP", icon = "💎", title = "Rare Answers Win", body = "The rarer your answer, the bigger your score!", colors = { rgb(150, 90, 255), rgb(40, 20, 120) } },
		{ tag = "COMPETE", icon = "🏆", title = "Top the Leaderboards", body = "Beat your best score in Solo, 1v1 and 1v1v1.", colors = { rgb(255, 210, 60), rgb(255, 120, 40) } },
	},
}
