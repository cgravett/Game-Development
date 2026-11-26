local ServerStorage = game:GetService("ServerStorage")
local Config = require(script.Parent.Parent.Config)
local Validation = require(script.Parent.AnswerValidationService)

local QuestionService = {}
local rng = Random.new() -- OS entropy; independent of global math.random calls
local bank
QuestionService.version = "unloaded"
QuestionService.reviewLog = {} -- unrecognized answers awaiting human review (aggregate only)

function QuestionService.init()
	bank = require(ServerStorage.ClamillionData.QuestionBank)
	QuestionService.version = bank.version
	local seen = {}
	local function prepare(q, answers, yieldEvery)
		for _, problem in ipairs(Validation.prepare(q, Config.Rarity, yieldEvery, answers)) do
			warn("[Clamillion] Question bank problem: " .. problem)
		end
	end
	-- Large banks parse each question's answers the first time it's used (see QuestionBank).
	if bank.setPrepare then bank.setPrepare(prepare) end
	for _, q in ipairs(bank.questions) do
		assert(not seen[q.id], "duplicate question id " .. q.id)
		seen[q.id] = true
		if not bank.setPrepare then prepare(q) end
	end
	print(("[Clamillion] Loaded question bank %s (%d questions)"):format(bank.version, #bank.questions))
end

function QuestionService.count()
	return #bank.questions
end

local function shuffle(t)
	for i = #t, 2, -1 do
		local j = rng:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

-- How recently any of these players saw each question: id -> age (0 = the last question one
-- of them was asked). Questions nobody has seen are absent.
local function ages(histories)
	local age = {}
	for _, list in ipairs(histories or {}) do
		local len = #list
		for i, id in ipairs(list) do
			local a = len - i
			if age[id] == nil or a < age[id] then age[id] = a end
		end
	end
	return age
end

-- Big banks parse a question's answers on first use (one can take a few hundred ms), so a show's
-- questions are parsed in the background, a little per frame, as soon as they're picked.
local function warm(list)
	task.spawn(function()
		for _, q in ipairs(list) do
			if bank.preload then bank.preload(q) else local _ = q.lookup end
			task.wait()
		end
	end)
end

-- Truly random picks, no repeats inside a show, and no repeats across shows: questions none of
-- the contestants has been asked before always come first (in random order). Only once they've
-- played through the whole bank do old ones come back, longest-ago first.
-- `histories` = each human contestant's list of seen question ids (ShopService.seenQuestions).
function QuestionService.pick(n, histories)
	local age = ages(histories)
	local fresh, seen = {}, {}
	for _, q in ipairs(bank.questions) do
		if age[q.id] == nil then table.insert(fresh, q) else table.insert(seen, q) end
	end
	shuffle(fresh)
	if #fresh < n then
		shuffle(seen)
		table.sort(seen, function(a, b) return age[a.id] > age[b.id] end)
	end
	local out = {}
	for i = 1, math.min(n, #fresh) do out[i] = fresh[i] end
	local k = 1
	while #out < n and seen[k] do table.insert(out, seen[k]); k += 1 end
	shuffle(out)
	warm(out)
	return out
end

-- One extra question (tiebreaker): unused this show, and the least recently seen by the players.
function QuestionService.spare(usedIds, histories)
	local age = ages(histories)
	local best, candidates = -1, {}
	for _, q in ipairs(bank.questions) do
		if not usedIds[q.id] then
			local a = age[q.id] or math.huge
			if a > best then best, candidates = a, { q }
			elseif a == best then table.insert(candidates, q) end
		end
	end
	if #candidates == 0 then return nil end
	local q = candidates[rng:NextInteger(1, #candidates)]
	warm({ q })
	return q
end

-- Up to `limit` of the rarest valid answers that nobody gave, for the reveal recap.
function QuestionService.highlights(question, givenIds, limit)
	local list = {}
	for _, a in ipairs(question.answers) do
		if not givenIds[a.id] and Config.Rarity[a.tier].order >= 3 then table.insert(list, a) end
	end
	table.sort(list, function(x, y) return Config.Rarity[x.tier].order > Config.Rarity[y.tier].order end)
	local out = {}
	for i = 1, math.min(limit or 3, #list) do
		out[i] = { name = list[i].name, tier = list[i].tier }
	end
	return out
end

function QuestionService.logUnrecognized(question, text)
	-- Kept server-side for answer-bank review; never shown to other players unfiltered.
	local entry = { questionId = question.id, text = string.sub(tostring(text), 1, 60), version = bank.version, at = os.time() }
	if #QuestionService.reviewLog >= 200 then table.remove(QuestionService.reviewLog,1) end
	table.insert(QuestionService.reviewLog, entry)

end

return QuestionService

