-- Clamillion question bank: Krillion Answers DB (scraped 2026-10-26). 721 questions, 491,213 answers.
-- The DataNN child modules hold one text stream, split only to fit Studio's script size limit:
--   "#<id>\t<category>\t<prompt>\t<hint answer>\t<hint points>\t<flags>" starts a question
--   (flag S = strict: letter/spelling rules, so no plural or typo leniency),
--   then one line per answer: <tier letter><answer>[\t<alternate spelling>...]
-- Tier letters: x=100 extremely_rare, v=85 very_rare, r=60 rare, u=30 uncommon, t=15 too_clever, c=10 common.
-- Alternate spellings were added at build time (~85k): each part of "A / B" answers, the answer
-- without a trailing "(note)", the old Clamillion bank's spellings, nicknames (JFK, USA), acronyms
-- (UAE, GTA V), St./Mt./Dr. forms, US state codes, surnames for people and first names for
-- characters (only when no other answer shares them), and the part after a title's colon.
-- Accents, capitals, punctuation, plurals and small typos are handled by AnswerValidationService.
-- Categories were assigned for Clamillion (the database has none).
-- The bank order is never the play order: QuestionService.pick shuffles.
--
-- Answers are parsed the first time a question is used, and only the most recently parsed
-- questions stay in memory. Reading q.answers / q.lookup / q.keys always works: an evicted
-- question is simply parsed again.
local T = { x = "extremely_rare", v = "very_rare", r = "rare", u = "uncommon", t = "too_clever", c = "common" }
local CACHE_MAX = 120 -- about 8 concurrent shows' worth of questions

local parts = {}
while true do
	local m = script:FindFirstChild(("Data%02d"):format(#parts + 1))
	if not m then break end
	table.insert(parts, require(m))
end
local text = table.concat(parts)
parts = nil

local Bank = { version = "krillion-721-v1.0-2026-10-26", questions = {} }
local prepareHook
local cache = {}

-- yieldEvery (optional): pause a frame every N answers, so a big question can be loaded in the
-- background without freezing the server. Nothing becomes visible on q until it's complete.
local function parse(q, yieldEvery)
	local raw = rawget(q, "_raw")
	local answers, n = {}, 0
	for line in string.gmatch(string.sub(text, raw[1], raw[2]), "[^\n]+") do
		local tier = T[string.sub(line, 1, 1)]
		if tier then
			n += 1
			local fields = string.split(string.sub(line, 2), "\t")
			local name = table.remove(fields, 1)
			answers[n] = { id = q.id .. "-A" .. string.format("%05d", n), name = name, tier = tier, aliases = fields }
			if yieldEvery and n % yieldEvery == 0 then task.wait() end
		end
	end
	if rawget(q, "lookup") then return end -- loaded by someone else meanwhile
	if prepareHook then
		prepareHook(q, answers, yieldEvery) -- sets answers/lookup/keys/keysByLen together
		if yieldEvery and rawget(q, "lookup") and rawget(q, "answers") ~= answers then return end
	else
		rawset(q, "answers", answers)
	end
	table.insert(cache, q)
	while #cache > CACHE_MAX do
		local old = table.remove(cache, 1)
		rawset(old, "answers", nil)
		rawset(old, "lookup", nil)
		rawset(old, "keys", nil)
		rawset(old, "keysByLen", nil)
	end
end

local lazy = { __index = function(q, k)
	if k == "answers" or k == "lookup" or k == "keys" or k == "keysByLen" then
		parse(q)
		return rawget(q, k)
	end
	return nil
end }

local len, pos = #text, 1
while pos <= len do
	local lineEnd = string.find(text, "\n", pos, true) or (len + 1)
	local f = string.split(string.sub(text, pos + 1, lineEnd - 1), "\t")
	local nextHeader = string.find(text, "\n#", lineEnd - 1, true)
	if nextHeader == lineEnd - 1 then nextHeader = string.find(text, "\n#", lineEnd, true) end
	local q = {
		id = f[1], category = f[2], prompt = f[3], hint = f[4], hintPoints = tonumber(f[5]), strict = f[6] == "S",
		_raw = { lineEnd + 1, nextHeader or len },
	}
	table.insert(Bank.questions, setmetatable(q, lazy))
	pos = nextHeader and nextHeader + 1 or len + 1
end

-- QuestionService passes Validation.prepare here so lookups are built whenever a question is parsed.
function Bank.setPrepare(fn)
	prepareHook = fn
end

-- Load a question's answers ahead of time, spread over several frames. Yields.
function Bank.preload(q)
	if rawget(q, "lookup") then return end
	parse(q, 1500)
end

return Bank
