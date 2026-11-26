--!strict
-- End-of-match screen and the hold-Tab scoreboard. Both read only server-published stats.
-- End of match: a menu column on the left (play again, practice, pond, menu), the player's
-- level and rewards under it, and both teams' tables along the bottom while the camera
-- shows the winning team lined up on the ice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Ui = require(script.Parent.Ui)
local Rank = require(game:GetService("ReplicatedStorage").Shared.Rank)
local Hud = require(script.Parent.Hud)

local Results = {}
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local playAgainButton: TextButton? = nil

export type Callbacks = {
	onQuickPlay: () -> (),
	onPractice: () -> (),
	onPond: () -> (),
	onMenu: () -> (),
	onBoardMenu: () -> (), -- MENU on the held scoreboard (in-game menu)
	onBoardSettings: () -> (), -- SETTINGS on the held scoreboard
}

local INK = Color3.fromRGB(30, 34, 48)
local NAVY = Color3.fromRGB(16, 24, 46)
local NAVY_LIGHT = Color3.fromRGB(30, 44, 80)
local GOLD = Color3.fromRGB(255, 206, 60)
local PANEL_BLUE = Color3.fromRGB(34, 86, 190)
local COLUMNS = { "NAME", "SCORE", "GOALS", "ASSISTS", "SHOTS", "SAVES" }
local KEYS = { "points", "goals", "assists", "shots", "saves" }

local root: Frame
local levelLabel: TextLabel
local xpFill: Frame
local xpLabel: TextLabel
local rewardLabel: TextLabel
local scoreLine: TextLabel
local winnerTags: { TextLabel } = {}
local tables: { { rows: { { TextLabel } } } } = {}
local board: Frame
local boardTables: { { rows: { { TextLabel } } } } = {}
local boardScores: { TextLabel } = {}
local boardClock: TextLabel

local function teamTable(parent: Instance, team: number, position: UDim2, anchor: Vector2, width: number): { rows: { { TextLabel } } }
	local color = if team == 1 then Hud.AWAY else Hud.HOME
	local frame: Frame = Ui.new("Frame", {
		AnchorPoint = anchor,
		Position = position,
		Size = UDim2.fromOffset(width, 106),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local header: Frame = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.3),
		BorderSizePixel = 0,
		Parent = frame,
	}, { Ui.corner(2) })
	local body: Frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 84),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = frame,
	}, { Ui.corner(3) })
	local nameWidth = 0.34
	local function cellX(i: number): (number, number)
		if i == 1 then
			return 0.03, nameWidth
		end
		local w = (1 - nameWidth - 0.04) / 5
		return nameWidth + 0.03 + (i - 2) * w, w
	end
	for i, text in COLUMNS do
		local x, w = cellX(i)
		Ui.label(text, 12, nil, Color3.new(1, 1, 1), {
			FontFace = Ui.SportItalic,
			Position = UDim2.new(x, 0, 0, 2),
			Size = UDim2.new(w, 0, 0, 16),
			TextXAlignment = if i == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
			Parent = header,
		})
	end
	local rows = {}
	for r = 1, 3 do
		local row = {}
		for i = 1, #COLUMNS do
			local x, w = cellX(i)
			row[i] = Ui.label("", 15, Enum.Font.GothamBlack, Color3.new(1, 1, 1), {
				Position = UDim2.new(x, 0, 0, 5 + (r - 1) * 26),
				Size = UDim2.new(w, 0, 0, 22),
				TextXAlignment = if i == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = body,
			})
		end
		rows[r] = row
	end
	return { rows = rows }
end

local function fillTable(t: { rows: { { TextLabel } } }, state: any, team: number, mySlot: number?)
	local first = if team == 1 then 1 else 4
	for r = 1, 3 do
		local slot = first + r - 1
		local entry = state.roster[slot]
		local s = state.stats[slot]
		local row = t.rows[r]
		row[1].Text = string.upper(entry.name) .. (if entry.bot then "  (BOT)" else "")
		row[1].TextColor3 = if slot == mySlot then Color3.fromRGB(255, 230, 120) else Color3.new(1, 1, 1)
		for i, key in KEYS do
			row[i + 1].Text = tostring(s[key] or 0)
		end
	end
end

local function sideButton(text: string, parent: Instance, order: number, onClick: () -> ()): TextButton
	local b = Ui.button(text, {
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = 16,
		Font = Enum.Font.GothamBlack,
		BackgroundColor3 = PANEL_BLUE,
		LayoutOrder = order,
		Parent = parent,
	}, onClick)
	return b
end

function Results.init(screen: ScreenGui, callbacks: Callbacks)
	root = Ui.new("Frame", {
		Name = "Results",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = screen,
	})

	local column: Frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(24, 40),
		Size = UDim2.fromOffset(200, 236),
		BackgroundColor3 = Color3.fromRGB(26, 60, 140),
		BackgroundTransparency = 0.1,
		Parent = root,
	}, {
		Ui.corner(6),
		Ui.new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
		Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	Ui.label("END OF MATCH", 12, Enum.Font.GothamBlack, Color3.new(1, 1, 1), { Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 0, Parent = column })
	-- Big enough for a thumb (40 px, vault: touch targets 44 px after the screen scale) and
	-- the first stop for a controller.
	playAgainButton = sideButton("PLAY AGAIN", column, 1, callbacks.onQuickPlay)
	sideButton("PRACTICE", column, 2, callbacks.onPractice)
	sideButton("THE POND", column, 3, callbacks.onPond)
	sideButton("RETURN TO MENU", column, 4, callbacks.onMenu)

	local levelBox: Frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(24, 286),
		Size = UDim2.fromOffset(200, 96),
		BackgroundColor3 = Color3.fromRGB(26, 60, 140),
		BackgroundTransparency = 0.1,
		Parent = root,
	}, { Ui.corner(6) })
	Ui.label("LEVEL", 10, Enum.Font.GothamBlack, Color3.fromRGB(170, 196, 255), { Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 12), Parent = levelBox })
	levelLabel = Ui.label("1", 22, Enum.Font.GothamBlack, Color3.new(1, 1, 1), { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 24), Parent = levelBox })
	local track: Frame = Ui.new("Frame", {
		Position = UDim2.new(0, 10, 0, 46),
		Size = UDim2.new(1, -20, 0, 6),
		BackgroundColor3 = Color3.fromRGB(14, 30, 70),
		BorderSizePixel = 0,
		Parent = levelBox,
	}, { Ui.corner(3) })
	xpFill = Ui.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(255, 214, 70), BorderSizePixel = 0, Parent = track }, { Ui.corner(3) })
	xpLabel = Ui.label("", 9, Ui.Theme.BodyFont, Color3.fromRGB(200, 214, 255), { Position = UDim2.fromOffset(0, 53), Size = UDim2.new(1, 0, 0, 11), Parent = levelBox })
	rewardLabel = Ui.label("", 11, Enum.Font.GothamBlack, Color3.fromRGB(255, 220, 90), { Position = UDim2.fromOffset(6, 66), Size = UDim2.new(1, -12, 0, 28), TextWrapped = true, Parent = levelBox })

	-- Bottom: AWAY table, score, HOME table.
	tables[1] = teamTable(root, 1, UDim2.new(0.5, -12, 1, -36), Vector2.new(1, 1), 360)
	tables[2] = teamTable(root, 2, UDim2.new(0.5, 12, 1, -36), Vector2.new(0, 1), 360)
	for team = 1, 2 do
		local label = Ui.label(string.upper(Config.Teams[team].Name) .. " TEAM", 14, Enum.Font.GothamBlack, if team == 1 then Hud.AWAY else Hud.HOME, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = if team == 1 then UDim2.new(0.5, -192, 1, -146) else UDim2.new(0.5, 192, 1, -146),
			Size = UDim2.fromOffset(200, 18),
			Parent = root,
		})
		Ui.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = label })
		winnerTags[team] = Ui.label("WINNER", 10, Enum.Font.GothamBlack, Color3.fromRGB(240, 180, 40), {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = if team == 1 then UDim2.new(0.5, -192, 1, -164) else UDim2.new(0.5, 192, 1, -164),
			Size = UDim2.fromOffset(200, 12),
			Parent = root,
		})
	end
	scoreLine = Ui.label("0-0", 20, Enum.Font.GothamBlack, INK, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -144),
		Size = UDim2.fromOffset(80, 24),
		Parent = root,
	})
	Ui.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = scoreLine })

	-- Hold-Tab scoreboard: a rink-scoreboard panel over the ice. Holding Tab frees the cursor,
	-- so its MENU and SETTINGS buttons can be clicked (Esc belongs to Roblox).
	board = Ui.new("Frame", {
		Name = "Scoreboard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromOffset(540, 380),
		BackgroundColor3 = NAVY,
		BackgroundTransparency = 0.06,
		Visible = false,
		ZIndex = 10,
		Parent = screen,
	}, { Ui.corner(10), Ui.stroke(GOLD, 3) })
	local header: Frame = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = NAVY_LIGHT,
		BorderSizePixel = 0,
		Parent = board,
	}, { Ui.corner(10) })
	for i, color in { Hud.AWAY, Hud.HOME } do
		Ui.new("Frame", {
			Position = UDim2.new((i - 1) * 0.5, 0, 1, -5),
			Size = UDim2.new(0.5, 0, 0, 5),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = header,
		})
	end
	Ui.label("SCOREBOARD", 26, nil, Color3.new(1, 1, 1), {
		FontFace = Ui.SportItalic,
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(0.6, 0, 1, -5),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})
	boardClock = Ui.label("5:00", 24, nil, GOLD, {
		FontFace = Ui.SportItalic,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 0),
		Size = UDim2.new(0.4, 0, 1, -5),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = header,
	})
	for team = 1, 2 do
		local y = 60 + (team - 1) * 128
		local color = if team == 1 then Hud.AWAY else Hud.HOME
		Ui.label(string.upper(Config.Teams[team].Name) .. " TEAM", 14, nil, color:Lerp(Color3.new(1, 1, 1), 0.35), {
			FontFace = Ui.SportItalic,
			Position = UDim2.fromOffset(84, y),
			Size = UDim2.fromOffset(300, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = board,
		})
		boardScores[team] = Ui.label("0", 40, nil, Color3.new(1, 1, 1), {
			FontFace = Ui.SportItalic,
			Position = UDim2.fromOffset(16, y + 20),
			Size = UDim2.fromOffset(58, 84),
			BackgroundTransparency = 0,
			BackgroundColor3 = color,
			Parent = board,
		})
		Ui.corner(6).Parent = boardScores[team]
		boardTables[team] = teamTable(board, team, UDim2.fromOffset(84, y + 18), Vector2.zero, 440)
	end
	local function boardButton(text: string, x: number, color: Color3, onClick: () -> ())
		local b = Ui.button(text, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, x, 1, -14),
			Size = UDim2.fromOffset(170, 38),
			TextSize = 20,
			FontFace = Ui.SportItalic,
			BackgroundColor3 = color,
			Parent = board,
		}, onClick)
		Ui.stroke(Color3.new(1, 1, 1), 2, 0.7).Parent = b
	end
	boardButton("MENU", -92, Color3.fromRGB(214, 52, 56), callbacks.onBoardMenu)
	boardButton("SETTINGS", 92, Color3.fromRGB(40, 104, 214), callbacks.onBoardSettings)
end

function Results.show(state: any, mySlot: number?)
	fillTable(tables[1], state, 1, mySlot)
	fillTable(tables[2], state, 2, mySlot)
	scoreLine.Text = `{state.scores[1]}-{state.scores[2]}`
	winnerTags[1].Visible = state.winner == 1
	winnerTags[2].Visible = state.winner == 2
	rewardLabel.Text = if mySlot then "counting rewards..." else "spectating"
	root.Visible = true
	if UserInputService.GamepadEnabled and playAgainButton then
		GuiService.SelectedObject = playAgainButton
	end
end

function Results.setProfile(profile: any)
	if not profile then
		return
	end
	levelLabel.Text = tostring(profile.level)
	xpFill.Size = UDim2.fromScale(math.clamp(profile.xp / math.max(1, profile.xpNext), 0, 1), 1)
	xpLabel.Text = `{profile.xp} / {profile.xpNext} GAMES`
end

function Results.setReward(reward: any)
	local pass = ""
	if type(reward.passXp) == "number" and reward.passXp > 0 then
		pass = `   +{reward.passXp} PASS XP` .. (if (reward.tierAfter or 0) > (reward.tierBefore or 0) then `  TIER {reward.tierAfter}!` else "")
	end
	-- Build 31: matches pay pass XP; every 3 full games is a level worth 500 coins.
	local level = if reward.leveled then `LEVEL UP! +{tonumber(reward.levelCoins) or 0} COINS`
		elseif (tonumber(reward.games) or 0) > 0 then "+1 GAME TO NEXT LEVEL"
		else "JOINED LATE: NOT A FULL GAME"
	-- Build 35: half the score comes back as coins.
	local scoreCoins = tonumber(reward.scoreCoins) or 0
	local earned = if scoreCoins > 0 then `+{scoreCoins} COINS   ` else ""
	rewardLabel.Text = earned .. level .. pass .. (if reward.late then "   LATE JOIN: NO LOSS" else "")
	-- Rank change, and any weekly challenge this match completed.
	if type(reward.eloAfter) == "number" and type(reward.eloBefore) == "number" and reward.eloAfter ~= reward.eloBefore then
		local diff = reward.eloAfter - reward.eloBefore
		local before, after = Rank.index(reward.eloBefore), Rank.index(reward.eloAfter)
		local sign = if diff > 0 then "+" else ""
		local change = if after > before then `  RANK UP: {Rank.name(after)}!` elseif after < before then `  {Rank.name(after)}` else ""
		rewardLabel.Text ..= `   {sign}{diff} ELO{change}`
	end
	if type(reward.challengesDone) == "table" and #reward.challengesDone > 0 then
		-- Build 32: collected from the menu's challenge card.
		local n = #reward.challengesDone
		rewardLabel.Text ..= if n > 1 then `   {n} CHALLENGES DONE: COLLECT IN THE MENU` else "   CHALLENGE DONE: COLLECT IN THE MENU"
	end
end

function Results.hide()
	root.Visible = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(root) then
		GuiService.SelectedObject = nil
	end
end

function Results.isShown(): boolean
	return root.Visible
end

function Results.showBoard(state: any, mySlot: number?)
	if not state then
		return
	end
	for team = 1, 2 do
		fillTable(boardTables[team], state, team, mySlot)
		boardScores[team].Text = tostring(state.scores[team])
	end
	boardClock.Text = Hud.clockText()
	board.Visible = true
end

function Results.hideBoard()
	board.Visible = false
end

return Results
