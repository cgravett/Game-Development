-- Server-authoritative match state machine:
-- MatchIntro -> (RoundIntro -> Question -> AnswerLock -> Reveal) x5 -> RoundTransition ... ->
-- Tiebreak? -> Results -> Cleanup
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Config = require(script.Parent.Parent.Config)
local QuestionService = require(script.Parent.QuestionService)
local Validation = require(script.Parent.AnswerValidationService)
local Scoring = require(script.Parent.ScoringService)
local StageService = require(script.Parent.StageService)
local BotService = require(script.Parent.BotService)
local BadgeAwards = require(script.Parent.BadgeAwards)
local ShopService = require(script.Parent.ShopService)
local UI = require(ReplicatedStorage.Clamillion.Shared.UIConstants)
local Catalog = require(ReplicatedStorage.Clamillion.Shared.ShopCatalog)
local Profanity = require(ReplicatedStorage.Clamillion.Shared.Profanity) -- kid-safe: star out bad words on the stage

local Remotes = ReplicatedStorage.Clamillion.Remotes

local MatchService = {}
local matches = {}
local playerMatches = {}
local hooks = {}
local draftRate = {} -- player -> {windowStart, count}

local function now()
	return workspace:GetServerTimeNow()
end

local function send(match, msg)
	for _, c in ipairs(match.contestants) do
		if c.player and not c.withdrawn and not c.left and c.player.Parent == Players then
			Remotes.MatchState:FireClient(c.player, msg)
		end
	end
end

local function host(match, text, seconds)
	match.stage.hostSay(text, seconds)
	send(match, { type = "Host", text = text })
end

local function sleep(match, seconds)
	local elapsed = 0
	while elapsed < seconds do
		if match.cancelled then return false end
		elapsed += task.wait(0.1)
	end
	return not match.cancelled
end

local function standings(match)
	local list = {}
	for _, c in ipairs(match.contestants) do
		table.insert(list, { seat = c.seat, userId=c.player and c.player.UserId, name = c.name, score = c.score, withdrawn = c.withdrawn })
	end
	return list
end

local function contestantFor(match, player)
	if not match then return nil end
	for _, c in ipairs(match.contestants) do
		if c.player == player then return c end
	end
end

local function setStatus(match, c, key)
	match.stage.setStatus(c.seat, key)
	send(match, { type = "Status", seat = c.seat, status = key })
end

local function leaderName(match)
	local best
	for _, c in ipairs(match.contestants) do
		if not c.withdrawn and (not best or c.score > best.score) then best = c end
	end
	return best
end

-- Lock-in: the only path that can set a contestant's final answer before time runs out.
local function lockIn(match, c, text)
	if match.phase ~= "Question" or not match.current or not match.current.seats[c.seat] then return false, "phase" end
	if c.withdrawn then return false, "withdrawn" end
	if c.locked then return false, "already" end
	if c.lastAttempt and now()-c.lastAttempt<0.25 then return false,"rate" end
	c.lastAttempt=now()
	if now() > match.deadline then return false, "late" end
	if Validation.isBlank(text) then return false, "blank" end
	local result=Validation.validate(match.current.question,text)
	if result.kind~="correct" then
  local suggestion=Validation.suggest(match.current.question,text)
  c.draft=""
  if suggestion then return false,"suggestion",suggestion end
  return false,"unrecognized"
 end
	c.final = text
	c.draft = text
	c.locked = true
	setStatus(match, c, "Locked")
	return true
end

-- Paid hints (HINT ? button): reveal one Very Rare (85-point) answer to the question a player
-- is answering right now. One per question. ShopService handles the Robux side.
local function hintAnswer(question)
	-- The question bank names one hint answer per question (its "Hint" column); use that one.
	if question.hint then
		local a = question.lookup[Validation.key(question.hint)]
		if a then return a, a.tier end
	end
	local byTier = {}
	for _, a in ipairs(question.answers) do
		byTier[a.tier] = byTier[a.tier] or {}
		table.insert(byTier[a.tier], a)
	end
	for _, tier in ipairs({ "very_rare", "extremely_rare", "rare" }) do
		local list = byTier[tier]
		if list and #list > 0 then return list[math.random(1, #list)], tier end
	end
end
local function hintTarget(player)
	local match = playerMatches[player]
	local c = contestantFor(match, player)
	if not c or c.withdrawn or c.locked or c.isBot then return nil end
	if match.phase ~= "Question" or not match.current or not match.current.seats[c.seat] then return nil end
	if now() > match.deadline - 1 then return nil end
	if c.hintToken == match.questionToken then return nil end
	return match, c
end
function MatchService.canHint(player)
	return hintTarget(player) ~= nil
end
function MatchService.giveHint(player)
	local match, c = hintTarget(player)
	if not match then return false end
	local answer, tier = hintAnswer(match.current.question)
	if not answer then return false end
	c.hintToken = match.questionToken
	Remotes.MatchState:FireClient(player, { type = "Hint", token = match.questionToken, answer = answer.name, tier = tier,
		label = Config.Rarity[tier].label, points = Config.Rarity[tier].points })
	return true
end
ShopService.hints = { canHint = MatchService.canHint, give = MatchService.giveHint }

local function validText(text)
	if typeof(text) ~= "string" then return false end
	if #text > Config.MaxAnswerLength * 4 then return false end
	local len = utf8.len(text)
	return len ~= nil and len <= Config.MaxAnswerLength
end

-- One question for the given participants. Returns false if the match was cancelled.
local function runQuestion(match, question, opts)
	match.used[question.id] = true
	-- remember it for each player so their next shows don't repeat it
	for _, c in ipairs(match.contestants) do
		if c.player and not c.withdrawn then ShopService.markSeen(c.player, question.id) end
	end
	local participants, seats, seatList = {}, {}, {}
	for _, c in ipairs(match.contestants) do
		if not c.withdrawn and (not opts.participants or opts.participants[c.seat]) then
			table.insert(participants, c)
			seats[c.seat] = true
			table.insert(seatList, c.seat)
			c.draft, c.final, c.locked = "", nil, false
			setStatus(match, c, "Thinking")
		elseif not c.withdrawn then
			setStatus(match, c, "Out")
		end
	end

	match.current = { question = question, seats = seats }
	match.questionToken=HttpService:GenerateGUID(false)
	match.deadline = now() + Config.AnswerSeconds
	match.phase = "Question"
	send(match, {
		type = "Question", token=match.questionToken, label = opts.label, category = question.category, prompt = question.prompt,
		deadline = match.deadline, duration = Config.AnswerSeconds, base = opts.base,
		participants = seatList, tiebreak = opts.tiebreak == true,
	})
	match.stage.showQuestion(opts.label, question.category, question.prompt)

	for _, c in ipairs(participants) do
		if c.isBot then
			BotService.play(question, Config.AnswerSeconds,
				function(text) if match.phase == "Question" and match.current.question == question and not c.locked then c.draft = text end end,
				function(text) if match.current and match.current.question == question then lockIn(match, c, text) end end)
		end
	end

	local shown = -1
	while true do
		if match.cancelled then return false end
		local remaining = match.deadline - now()
		local secs = math.max(0, math.ceil(remaining))
		if secs ~= shown then shown = secs; match.stage.setTimer(secs) end
		if remaining <= 0 then break end
		local waiting = false
		for _, c in ipairs(participants) do
			if not c.withdrawn and not c.locked then waiting = true break end
		end
		if not waiting then break end
		task.wait(0.1)
	end

	-- AnswerLock: freeze everything, auto-submit non-empty drafts.
	match.phase = "AnswerLock"
	match.stage.setTimer(nil)
	for _, c in ipairs(participants) do
		if not c.withdrawn and not c.locked then
			c.locked = true
			c.final = (not Validation.isBlank(c.draft)) and c.draft or nil
			setStatus(match, c, "TimeUp")
		end
	end

	-- Validate + score. Raw text never leaves the server.
	local results, given, bestTier = {}, {}, 0
	for _, c in ipairs(participants) do
		local entry = { seat = c.seat, name = c.name, points = 0, mult = 0,
			userId = c.player and c.player.UserId, emote = c.player and c.player:GetAttribute("Emote") }
		if c.withdrawn then
			entry.kind = "withdrawn"
		else
			-- time ran out before they could confirm a "Did you mean": a small, unambiguous typo still counts
			local r = Validation.validate(question, c.final, true)
			entry.kind = r.kind
			if r.kind == "correct" then
				entry.answer = r.answer.name
				entry.tier = r.tier
				if r.tier == "extremely_rare" and c.player then BadgeAwards.award(c.player, "extreme") end
				entry.mult = Scoring.multiplier(r.tier)
				entry.points = Scoring.points(opts.base, r.tier)
				given[r.answer.id] = true
				bestTier = math.max(bestTier, Config.Rarity[r.tier].order)
			elseif r.kind == "unrecognized" then
				QuestionService.logUnrecognized(question, c.final)
			end
		end
		if opts.tiebreak then
			c.tiebreakPoints = (c.tiebreakPoints or 0) + entry.points
			entry.newScore = c.tiebreakPoints
		else
			c.score += entry.points
			entry.newScore = c.score
		end
		table.insert(results, entry)
	end

	match.phase = "Reveal"
	local per, recap = Config.Pacing.revealPerContestant, Config.Pacing.recap
	local highlights = QuestionService.highlights(question, given, 3)
	send(match, { type = "Reveal", results = results, perContestant = per, recap = recap, tiebreak = opts.tiebreak == true, highlights = highlights })
	match.stage.showMessage("THE ANSWERS", string.upper(question.category), question.prompt)
	host(match, bestTier >= 5 and "An EXTREMELY rare answer out there — let's see!" or "Let's see what you came up with!", per * #results)
	for _, e in ipairs(results) do
		if not sleep(match, per) then return false end
		if not opts.tiebreak then match.stage.setScore(e.seat, e.newScore) end
	end
	if #highlights > 0 then
		local names = {}
		for _, h in ipairs(highlights) do table.insert(names, Profanity.mask(h.name)) end
		match.stage.showMessage("ALSO ACCEPTED", string.upper(question.category), "Rare answers nobody gave: " .. table.concat(names, ", "))
	end
	return sleep(match, recap)
end

local function leaders(match)
	local best, list = -math.huge, {}
	for _, c in ipairs(match.contestants) do
		if not c.withdrawn then
			if c.score > best then best, list = c.score, { c }
			elseif c.score == best then table.insert(list, c) end
		end
	end
	return list
end

local function run(match)
	-- Arena load barrier: no question/timer is sent until every real entrant loads.
	send(match, {type="MatchLoading", arena=match.arena.Name, matchId=match.id})
	local loadEnd=now()+20
	while now()<loadEnd do
		local ready=true
		for _,c in ipairs(match.contestants) do if c.withdrawn or not match.ready[c.player] then ready=false end end
		if ready then break end
		if match.cancelled then return end
		task.wait(0.1)
	end
	for _,c in ipairs(match.contestants) do if c.withdrawn or not match.ready[c.player] then match.cancelled=true; return end end
	match.phase = "INTRO"
	for _, c in ipairs(match.contestants) do
		match.stage.setName(c.seat, c.name)
		match.stage.setScore(c.seat, 0)
		match.stage.setStatus(c.seat, "Waiting")
		if c.player then match.stage.placePlayer(c.player, c.seat) else match.stage.spawnBot(c.seat, c.name) end
	end
	match.stage.showMessage("CLAMILLION", "WELCOME TO THE SHOW", "Rarer right answers score bigger.")
	-- Host script. Each line is timed to how long the voice takes to say it plus one short,
	-- even beat, so she never gets cut off and never leaves awkward silences.
	local lines={
		"Hello, welcome to Clamillion!",
		"Here's how it works. There are three rounds, with five questions in each round.",
		"You get thirty seconds to answer. If your answer isn't right, that's okay, just try again!",
		"And here's the fun part. The rarer your answer, the more points you'll get!",
		"Alright, let's meet our contestants!",
	}
	local FLIGHT = 9
	local timings, talk = {}, 0
	for i, line in ipairs(lines) do
		timings[i] = Config.Pacing.speechSeconds(line) + Config.Pacing.hostBeat
		talk += timings[i]
	end
	local contestantAt = FLIGHT + talk + 0.2
	local introSeconds = contestantAt + 2.6
	for _, c in ipairs(match.contestants) do
		if c.player then
			Remotes.MatchState:FireClient(c.player, {
				type = "MatchIntro", mode=match.mode, introSeconds=introSeconds, flightSeconds=FLIGHT, contestantAt=contestantAt, startedAt=now(), matchId=match.id, yourSeat = c.seat, contestants = standings(match),
				rounds = #Config.Rounds, perRound = Config.QuestionsPerRound, maxLength = Config.MaxAnswerLength,
			})
		end
	end
 -- Solo players may skip the rules intro (IntroReady "skip"), which jumps straight to Round 1.
 local function introWait(seconds)
  local elapsed=0
  while elapsed<seconds do
   if match.cancelled then return false end
   if match.skipIntro then return true end
   elapsed+=task.wait(0.1)
  end
  return not match.cancelled
 end
 if not introWait(FLIGHT) then return end
 if not match.skipIntro then match.stage.welcome() end
 for i,line in ipairs(lines) do
  if match.skipIntro then break end
  host(match,line,timings[i]+0.3)
  if not introWait(timings[i]) then return end
 end
 if not introWait(introSeconds-contestantAt+0.2) then return end
 local barrierEnd=now()+10
 while now()<barrierEnd and not match.skipIntro do
  local all=true
  for _,c in ipairs(match.contestants) do if not c.withdrawn and not match.introDone[c.player] then all=false end end
  if all then break end
  if not sleep(match,0.1) then return end
 end
 if match.skipIntro then match.stage.hostSay("",0.01) end
 for _,c in ipairs(match.contestants) do
  if not c.withdrawn and not match.introDone[c.player] then match.cancelled=true; return end
 end

	local qi = 0
	for r, round in ipairs(Config.Rounds) do
		match.round = r
		send(match, { type = "RoundIntro", round = r, rounds = #Config.Rounds, name = round.name, base = round.base })
		match.stage.showMessage(string.upper(round.name), "", "Common 10 · Uncommon 30 · Rare 60 · Very Rare 85 · Extremely Rare 100")
		host(match, round.name .. "! Rarity points stay the same in every round.", Config.Pacing.roundIntro)
		if not sleep(match, Config.Pacing.roundIntro) then return end
		for q = 1, Config.QuestionsPerRound do
			qi += 1
			local question = match.questions[qi]
			if not question then break end
			local label = ("ROUND %d · QUESTION %d OF %d"):format(r, q, Config.QuestionsPerRound)
			if not runQuestion(match, question, { base = round.base, label = label }) then return end
			if not sleep(match, Config.Pacing.betweenQuestions) then return end
		end
		if r < #Config.Rounds then
			match.phase = "RoundTransition"
			send(match, { type = "RoundTransition", finished = r, standings = standings(match) })
			local lead = leaderName(match)
			host(match, ("That's the end of %s! %s leads with %s."):format(round.name, lead and lead.name or "Nobody", UI.formatNumber(lead and lead.score or 0)), Config.Pacing.roundTransition)
			match.stage.showMessage("END OF " .. string.upper(round.name), "STANDINGS", lead and (lead.name .. " leads with " .. UI.formatNumber(lead.score)) or "")
			if not sleep(match, Config.Pacing.roundTransition) then return end
		end
	end

	-- Tiebreak
	local winners = leaders(match)
	local attempt = 0
	while #winners > 1 and Config.Tiebreak.enabled and attempt < Config.Tiebreak.maxRounds do
		attempt += 1
		local seats, seatList, tied = {}, {}, {}
		for _, c in ipairs(winners) do
			seats[c.seat] = true; table.insert(seatList, c.seat); table.insert(tied, c.name); c.tiebreakPoints = 0
		end
		match.phase = "Tiebreak"
		send(match, { type = "Tiebreak", attempt = attempt, seats = seatList, names = tied })
		match.stage.showMessage("TIEBREAKER", "", table.concat(tied, " vs ") .. " — most points wins!")
		host(match, "We have a tie at the top! Tiebreaker question — most points wins.", Config.Pacing.tiebreakIntro)
		if not sleep(match, Config.Pacing.tiebreakIntro) then return end
		local question = QuestionService.spare(match.used, match.histories)
		if not question then break end
		if not runQuestion(match, question, { base = Config.Tiebreak.base, label = "TIEBREAKER", participants = seats, tiebreak = true }) then return end
		local best, next = -1, {}
		for _, c in ipairs(winners) do
			if not c.withdrawn then
				if c.tiebreakPoints > best then best, next = c.tiebreakPoints, { c }
				elseif c.tiebreakPoints == best then table.insert(next, c) end
			end
		end
		winners = next
	end

	-- Results
	match.phase = "Results"
	if hooks.onResults then
		local winnerIds = {}
		for _, c in ipairs(winners) do if c.player then winnerIds[c.player.UserId] = true end end
		hooks.onResults(match.mode, standings(match), winnerIds)
	end
	local winnerSeats, winnerSet, winnerNames = {}, {}, {}
	for _, c in ipairs(winners) do
		table.insert(winnerSeats, c.seat); winnerSet[c.seat] = true; table.insert(winnerNames, c.name)
		setStatus(match, c, match.mode=="Solo" and "Waiting" or "Winner")
	end
	local order = {}
	for _, c in ipairs(match.contestants) do table.insert(order, c) end
	table.sort(order, function(a, b)
		if a.withdrawn ~= b.withdrawn then return not a.withdrawn end
		if winnerSet[a.seat] ~= winnerSet[b.seat] then return winnerSet[a.seat] == true end
		if a.score ~= b.score then return a.score > b.score end
		return a.seat < b.seat
	end)
	local placements, place = {}, 0
	for i, c in ipairs(order) do
		if winnerSet[c.seat] then place = 1
		elseif i == 1 or c.score ~= order[i - 1].score or winnerSet[order[i - 1].seat] then place = i end
		table.insert(placements, { seat = c.seat, name = c.name, score = c.score, place = c.withdrawn and 0 or place, withdrawn = c.withdrawn, userId = c.player and c.player.UserId })
	end
	-- winners' emotes play as the camera swoops in (1v1 / 1v1v1 only)
	local emotes = {}
	if match.mode ~= "Solo" then
		for _, c in ipairs(winners) do
			if c.player and c.player:GetAttribute("Emote") then table.insert(emotes, { seat = c.seat, userId = c.player.UserId, emote = c.player:GetAttribute("Emote") }) end
		end
	end
	-- 1v1 / 1v1v1: a victory celebration first — the winner alone on stage with a trophy, picking a dance
	local celebrate = match.mode ~= "Solo" and #winnerSeats > 0 and Config.Pacing.celebrate or 0
	match.champions = {}
	for _, c in ipairs(winners) do if c.player then match.champions[c.player] = true end end
	send(match, { type = "Results", mode=match.mode, winners = winnerSeats, shared = #winnerSeats > 1, placements = placements, tiebreakUsed = attempt > 0, emotes = emotes, celebrate = celebrate })
	local headline = #winnerNames > 1 and ("It's a shared victory for " .. table.concat(winnerNames, " and ") .. "!")
		or (#winnerNames == 1 and (winnerNames[1] .. " wins Clamillion!") or "That's the show!")
	if match.mode=="Solo" then headline="Solo challenge complete! Your score: "..tostring(match.contestants[1].score) end
	host(match, headline .. " Thanks for playing!", Config.Pacing.results)
	match.stage.showMessage(match.mode=="Solo" and "SOLO COMPLETE" or "WINNER", "", headline)
	sleep(match, Config.Pacing.results + celebrate)
end

local function cleanup(match)
	match.phase = "Cleanup"
	for _, c in ipairs(match.contestants) do
		if c.player and c.player.Parent == Players and not c.left then
			match.stage.releasePlayer(c.player)
			Remotes.MatchState:FireClient(c.player, { type = "MatchEnded", cancelled = match.cancelled == true })
		end
	end
	match.stage.clearBots()
	match.stage.resetStage()
	for _,c in ipairs(match.contestants) do if c.player and playerMatches[c.player]==match then playerMatches[c.player]=nil end end
	matches[match.id]=nil
	match.stage.destroy()
	if hooks.onMatchEnded then task.defer(hooks.onMatchEnded) end
end

function MatchService.isActive() return false end -- independent arena per room
function MatchService.isInMatch(player) return playerMatches[player] ~= nil end
function MatchService.start(players, mode)
 local def=Config.Modes[mode]
 if not def or #players~=def.count then return false end
 for _,p in ipairs(players) do
  if p.Parent~=Players or playerMatches[p] or not p.Character or not p.Character:FindFirstChild("HumanoidRootPart") then return false end
 end
 local match={id=HttpService:GenerateGUID(false),bankVersion=QuestionService.version,mode=mode,
  contestants={},used={},phase="Loading",cancelled=false,ready={},introDone={}}
 -- The server always builds the classic stage. Arena themes are cosmetic and CLIENT-SIDE:
 -- each player's own game dresses the stage in the arena they equipped (Shared.ArenaThemes),
 -- so in a 1v1v1 everyone sees their own arena. Podiums, titles and emotes stay shared.
 match.stage,match.arena=StageService.create(match.id,nil)
 local seats=match.stage.prepare(#players)
 for i,p in ipairs(players) do
  table.insert(match.contestants,{seat=seats[i],player=p,name=p.DisplayName,score=0})
  playerMatches[p]=match
  -- each contestant's own podium theme + title from the shop
  local podium=ShopService.equipped(p,"Podium")
  if podium then pcall(match.stage.applyPodium,seats[i],podium.theme) end
  match.stage.setTitle(seats[i],ShopService.titleText(p),ShopService.titleAnim(p))
 end
 match.histories={}
 for _,p in ipairs(players) do table.insert(match.histories,ShopService.seenQuestions(p)) end
 match.questions=QuestionService.pick(#Config.Rounds*Config.QuestionsPerRound,match.histories)
 matches[match.id]=match
 task.spawn(function()
  local ok,err=pcall(run,match)
  if not ok then match.cancelled=true; warn("[Clamillion] Match error: "..tostring(err)) end
  cleanup(match)
 end)
 return true
end

local function onLeaving(player)
	draftRate[player] = nil
	local match = playerMatches[player]
	local c = contestantFor(match, player)
	if not c or c.withdrawn then return end
	c.withdrawn = true
	if match.phase=="Loading" or match.phase=="INTRO" then match.cancelled=true end
	match.stage.setStatus(c.seat, "Withdrawn")
	send(match, { type = "Withdrawn", seat = c.seat })
	local humans = 0
	for _, other in ipairs(match.contestants) do
		if other.player and not other.withdrawn then humans += 1 end
	end
	if humans == 0 then
		match.cancelled = true
		print("[Clamillion] Match cancelled: no contestants left")
	end
end

-- A contestant chose to leave (the Leave button, or Return to Lobby on the results screen).
-- They go straight back to the lobby; the show carries on for anyone still playing.
local function leaveVoluntarily(player)
	local match = playerMatches[player]
	local c = contestantFor(match, player)
	if not c or c.left then return end
	c.left = true
	if not c.withdrawn and match.phase ~= "Results" and match.phase ~= "Cleanup" then
		c.withdrawn = true
		match.stage.setStatus(c.seat, "Withdrawn")
		send(match, { type = "Withdrawn", seat = c.seat })
	end
	playerMatches[player] = nil
	match.stage.releasePlayer(player)
	Remotes.MatchState:FireClient(player, { type = "MatchEnded", cancelled = false, left = true })
	local humans = 0
	for _, other in ipairs(match.contestants) do
		if other.player and not other.left and not other.withdrawn then humans += 1 end
	end
	-- nobody left on stage (or someone bailed before the show got going): wrap it up now
	if humans == 0 or match.phase == "Loading" then match.cancelled = true end
	if hooks.onMatchEnded then task.defer(hooks.onMatchEnded) end
end

function MatchService.init(h)
	hooks = h or {}
	Remotes.LeaveMatch.OnServerEvent:Connect(leaveVoluntarily)
	Remotes.IntroReady.OnServerEvent:Connect(function(player,id,phase)
		local match=playerMatches[player]
		if not match or id~=match.id then return end
		if phase=="loaded" and match.phase=="Loading" then match.ready[player]=true end
		if phase=="done" and match.phase=="INTRO" then match.introDone[player]=true end
		if phase=="skip" and match.phase=="INTRO" then
			if match.mode=="Solo" then
				match.introDone[player]=true; match.skipIntro=true -- solo: skip straight away
			else
				-- 1v1 / 1v1v1: everyone still in the show has to tap SKIP
				match.skipVotes = match.skipVotes or {}
				match.skipVotes[player] = true
				local votes, needed = 0, 0
				for _, c in ipairs(match.contestants) do
					if c.player and not c.withdrawn then
						needed += 1
						if match.skipVotes[c.player] then votes += 1 end
					end
				end
				send(match, { type = "SkipVotes", votes = votes, needed = needed })
				if votes >= needed and not match.skipIntro then
					for _, c in ipairs(match.contestants) do if c.player then match.introDone[c.player] = true end end
					match.skipIntro = true
					send(match, { type = "IntroSkipped" })
				end
			end
		end
	end)

	Remotes.SubmitAnswer.OnServerEvent:Connect(function(player, text, token)
		local match = playerMatches[player]
		local c = contestantFor(match, player)
		if not c or token~=match.questionToken or not validText(text) then return end
		-- simple rate limit: 15 drafts per second
		local t = os.clock()
		local r = draftRate[player]
		if not r or t - r[1] > 1 then r = { t, 0 }; draftRate[player] = r end
		r[2] += 1
		if r[2] > 15 then return end
		if match.phase ~= "Question" or not match.current.seats[c.seat] or c.locked or c.withdrawn then return end
		if now() > match.deadline then return end
		c.draft = text
	end)

	-- the champion picks a victory dance during the celebration (only dances they own)
	local celebrateAt = {}
	Remotes.Celebrate.OnServerEvent:Connect(function(player, emoteId)
		local match = playerMatches[player]
		if not match or match.phase ~= "Results" or not (match.champions and match.champions[player]) then return end
		local item = type(emoteId) == "string" and Catalog.get(emoteId)
		if not item or item.kind ~= "Emote" or not ShopService.owns(player, emoteId) then return end
		if celebrateAt[player] and os.clock() - celebrateAt[player] < 1.2 then return end
		celebrateAt[player] = os.clock()
		send(match, { type = "Celebrate", userId = player.UserId, emote = emoteId })
	end)
	Players.PlayerRemoving:Connect(function(p) celebrateAt[p] = nil end)

	Remotes.LockAnswer.OnServerEvent:Connect(function(player, text, token)
		local match = playerMatches[player]
		local c = contestantFor(match, player)
		if not c or token~=match.questionToken then return end
		if not validText(text) then
			Remotes.MatchState:FireClient(player, { type = "LockAck", token=match.questionToken, ok = false, reason = "invalid" })
			return
		end
		local ok, reason, suggestion = lockIn(match, c, text)
		Remotes.MatchState:FireClient(player, { type = "LockAck", token=match.questionToken, ok = ok, reason = reason, suggestion=suggestion })
	end)

	Players.PlayerRemoving:Connect(onLeaving)

	-- keep contestants on their podium if they respawn mid-match
	local function hookCharacter(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.2)
			local c = contestantFor(playerMatches[player], player)
			if c and not c.withdrawn and playerMatches[player].phase ~= "Cleanup" then
				playerMatches[player].stage.placePlayer(player, c.seat)
			else
				StageService.releasePlayer(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(hookCharacter)
	for _, p in ipairs(Players:GetPlayers()) do hookCharacter(p) end
end

return MatchService

