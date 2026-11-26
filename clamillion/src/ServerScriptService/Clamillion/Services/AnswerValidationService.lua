-- Turns raw player text into a canonical answer from the question bank. Server-only.
--
-- Matching ignores things that never matter: capitals, accents, punctuation, spaces,
-- "&" vs "and", a leading "The/A/An", number words vs digits ("Toy Story Two" = "Toy Story 2")
-- and Roman numerals ("Rocky IV" = "Rocky 4", "GTA V" = "GTA 5").
-- Answers also carry alternate spellings from the bank (abbreviations, surnames, nicknames...).
-- Unless a question is strict (spelling/letter rules, flagged in the bank), plurals match
-- ("cows" = "Cow"). Typos get a "Did you mean ...?" prompt (suggest) that the player confirms;
-- only a draft left unlocked when time runs out has a small typo accepted automatically.
--
-- Validation.key MUST stay identical to keyfn.py in the bank build script: the bank's
-- alternate spellings were de-duplicated with it.
local Validation = {}

local foldModule = script:FindFirstChild("FoldMap")
local FOLD = foldModule and require(foldModule) or {}
local NUM = {}
for i, w in ipairs({ "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
	"eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty" }) do
	NUM[w] = tostring(i - 1)
end
for r, v in pairs({ ii = 2, iii = 3, iv = 4, vi = 6, vii = 7, viii = 8, ix = 9, xi = 11, xii = 12, xiii = 13, xiv = 14,
	xv = 15, xvi = 16, xvii = 17, xviii = 18, xix = 19, xx = 20 }) do
	NUM[r] = tostring(v)
end
local ROMAN1 = { i = " 1", v = " 5", x = " 10" }
local function strip(c)
	if c == "+" or c == "#" then return c end -- keep C++ and C# apart from C
	return ""
end

-- Readable form: lowercase with tidy spaces.
function Validation.normalize(s)
	s = string.lower(tostring(s or ""))
	s = s:gsub("’", "'"):gsub("‘", "'"):gsub("–", "-"):gsub("‑", "-")
	s = s:gsub("%c", " ")
	s = s:gsub("%s+", " ")
	return s:match("^%s*(.-)%s*$") or ""
end

-- Lookup key, e.g. "The São Tomé & Príncipe!" -> "saotomeandprincipe".
function Validation.key(s)
	s = tostring(s or "")
	if string.find(s, "[\128-\255]") then s = string.gsub(s, "[\192-\247][\128-\191]*", FOLD) end
	s = string.lower(s)
	s = string.gsub(s, "&", " and ")
	s = string.gsub(s, "%c", " ")
	s = string.gsub(s, "%s+", " ")
	s = string.match(s, "^%s*(.-)%s*$") or ""
	local art = string.match(s, "^(%a+) .")
	if art == "the" or art == "a" or art == "an" then s = string.sub(s, #art + 2) end
	s = string.gsub(s, " ([ivx])$", ROMAN1)
	s = string.gsub(s, "%a+", NUM)
	s = string.gsub(s, "[%s%p]", strip)
	return s
end

function Validation.isBlank(s)
	return s == nil or Validation.key(s) == ""
end

-- Builds lookup tables for a question. Returns a list of problems (empty if clean).
-- answers defaults to question.answers. With yieldEvery, pauses a frame every N answers; the
-- question's answers/lookup/keys/keysByLen are only set at the end, all together.
function Validation.prepare(question, rarityConfig, yieldEvery, answers)
	answers = answers or question.answers
	local problems = {}
	local extreme = 0
	for _, a in ipairs(answers) do
		if a.tier == "extremely_rare" then extreme += 1 end
	end
	-- Krillion bank: 0–2 "One in a Krillion" (100-pt) answers per question (18 questions have none)
	if extreme > 2 then table.insert(problems, question.id .. ": has more than 2 extremely rare answers") end
	local lookup, keys, keysByLen = {}, {}, {}
	for n, ans in ipairs(answers) do
		if yieldEvery and n % yieldEvery == 0 then task.wait() end
		if not rarityConfig[ans.tier] then
			table.insert(problems, ("%s: answer %q has unknown tier %q"):format(question.id, ans.name, tostring(ans.tier)))
		end
		ans.id = ans.id or (question.id .. ":" .. Validation.key(ans.name))
		local spellings = { ans.name }
		for _, alias in ipairs(ans.aliases or {}) do table.insert(spellings, alias) end
		for _, spelling in ipairs(spellings) do
			local k = Validation.key(spelling)
			local existing = lookup[k]
			if existing and existing ~= ans then
				table.insert(problems, ("%s: spelling %q maps to both %q and %q"):format(question.id, spelling, existing.name, ans.name))
			elseif k ~= "" and not existing then
				lookup[k] = ans
				local entry = { key = k, answer = ans }
				table.insert(keys, entry)
				local bucket = keysByLen[#k]
				if not bucket then bucket = {}; keysByLen[#k] = bucket end
				table.insert(bucket, entry)
			end
		end
	end
	if yieldEvery and rawget(question, "lookup") then return problems end -- loaded meanwhile; keep that
	rawset(question, "answers", answers)
	rawset(question, "lookup", lookup)
	rawset(question, "keys", keys)
	rawset(question, "keysByLen", keysByLen)
	return problems
end

-- Keyboard-aware edit distance: neighbouring keys and swapped letters cost less.
-- Keys are byte codes; adjacency is precomputed so the inner loop is just table lookups.
local keyboard = {}
for y, row in ipairs({ "qwertyuiop", "asdfghjkl", "zxcvbnm" }) do
	for x = 1, #row do keyboard[string.byte(row, x)] = { x = x + (y - 1) * .35, y = y } end
end
local ADJ = {}
for a, p in pairs(keyboard) do
	ADJ[a] = {}
	for b, q in pairs(keyboard) do
		if a ~= b and math.abs(p.x - q.x) <= 1.4 and math.abs(p.y - q.y) <= 1 then ADJ[a][b] = true end
	end
end
-- Stops early (returns cap + 1) once two consecutive rows are all over the cap: no later
-- row can come back under it, even through a swapped-letter step.
-- adjCost / swapCost: price of hitting a neighbouring key / swapping two letters.
local function distance(a, b, cap, adjCost, swapCost)
	adjCost = adjCost or .65
	swapCost = swapCost or .75
	local la, lb = #a, #b
	local prev, older = {}, nil
	for j = 0, lb do prev[j] = j end
	local prevMin = 0
	for i = 1, la do
		local ca = string.byte(a, i)
		local adj = ADJ[ca]
		local row = { [0] = i }
		local rowMin = i
		for j = 1, lb do
			local cb = string.byte(b, j)
			local cost = ca == cb and 0 or ((adj and adj[cb]) and adjCost or 1)
			local v = math.min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + cost)
			if older and j > 1 and ca == string.byte(b, j - 1) and string.byte(a, i - 1) == cb then
				v = math.min(v, older[j - 2] + swapCost)
			end
			row[j] = v
			if v < rowMin then rowMin = v end
		end
		if rowMin > cap and prevMin > cap then return cap + 1 end
		older, prev, prevMin = prev, row, rowMin
	end
	return prev[lb]
end

-- The one answer a typo is closest to, or nil when nothing is close or two answers are equally close.
local function nearest(question, key)
	local cap = #key >= 7 and 1.7 or 1
	local reach = math.ceil(cap)
	local byLen = question.keysByLen
	local best = {}
	for len = #key - reach, #key + reach do
		local bucket = byLen and byLen[len]
		if bucket then
			for _, entry in ipairs(bucket) do
				local d = distance(key, entry.key, cap)
				if d <= cap and (not best[entry.answer] or d < best[entry.answer]) then best[entry.answer] = d end
			end
		end
	end
	local chosen, score, second = nil, math.huge, math.huge
	for answer, d in pairs(best) do
		if d < score then second = score; score = d; chosen = answer elseif d < second then second = d end
	end
	-- Ambiguous typos need another attempt; never guess between equally plausible answers.
	if chosen and second - score >= .3 then return chosen end
	return nil
end

local function plurals(k)
	local out = {}
	if #k < 3 then return out end
	if string.sub(k, -3) == "ies" then table.insert(out, string.sub(k, 1, -4) .. "y") end
	if string.sub(k, -2) == "es" then table.insert(out, string.sub(k, 1, -3)) end
	if string.sub(k, -1) == "s" then table.insert(out, string.sub(k, 1, -2)) end
	table.insert(out, k .. "s")
	table.insert(out, k .. "es")
	if string.sub(k, -1) == "y" then table.insert(out, string.sub(k, 1, -2) .. "ies") end
	return out
end

-- result.kind: "correct" | "unrecognized" | "blank"
-- Exact spellings, alternate spellings and plurals are accepted. Typos are NOT accepted on
-- lock-in: the player gets a "Did you mean ...?" (Validation.suggest) and confirms it. Only when
-- time runs out (acceptTypos) is a small, unambiguous typo in an unlocked draft accepted.
function Validation.validate(question, text, acceptTypos)
	if Validation.isBlank(text) then
		return { kind = "blank" }
	end
	local k = Validation.key(text)
	local lookup = question.lookup
	local hit = lookup[k]
	if not hit and not question.strict then
		for _, v in ipairs(plurals(k)) do
			hit = lookup[v]
			if hit then break end
		end
		if not hit and acceptTypos and #k >= 5 then hit = nearest(question, k) end
	end
	if hit then
		return { kind = "correct", answer = hit, tier = hit.tier }
	end
	return { kind = "unrecognized" }
end

-- "Did you mean ...?" for an answer that wasn't accepted. More forgiving than nearest():
-- the allowance grows with the length of what they typed, and hitting a key NEXT to the right
-- one costs much less than a random wrong letter, so fat-finger typing like "csmpunh" still
-- finds "camping". Accents never matter (Validation.key folds them).
-- Suggestions never score or lock. Only a subsequent submission can do that.
local SUGGEST_ADJ, SUGGEST_SWAP = .4, .6
local SUGGEST_BUDGET = .02 -- seconds; a question can have 30k+ answers

-- Same keyboard-aware distance, but only cells within `band` of the diagonal are worked out
-- (anything further off already costs more than the cap) and the rows are reused, not allocated.
local R0, R1, R2 = {}, {}, {}
local function bandedDistance(a, b, cap, band)
	local la, lb = #a, #b
	local BIG = cap + 1
	local older, prev, row = R0, R1, R2
	for j = 0, lb + 1 do prev[j] = (j <= band) and j or BIG; older[j] = BIG end
	local prevMin = 0
	for i = 1, la do
		local ca = string.byte(a, i)
		local adj = ADJ[ca]
		local lo, hi = math.max(1, i - band), math.min(lb, i + band)
		row[lo - 1] = (lo == 1 and i <= band) and i or BIG
		if hi < lb then row[hi + 1] = BIG end
		local rowMin = BIG
		for j = lo, hi do
			local cb = string.byte(b, j)
			local cost = ca == cb and 0 or ((adj and adj[cb]) and SUGGEST_ADJ or 1)
			local v = prev[j - 1] + cost
			local up = (j <= i - 1 + band) and prev[j] + 1 or BIG
			if up < v then v = up end
			local left = row[j - 1] + 1
			if left < v then v = left end
			if i > 1 and j > 1 and ca == string.byte(b, j - 1) and string.byte(a, i - 1) == cb then
				local s = older[j - 2] + SUGGEST_SWAP
				if s < v then v = s end
			end
			row[j] = v
			if v < rowMin then rowMin = v end
		end
		if rowMin > cap and prevMin > cap then return BIG end
		older, prev, row = prev, row, older
		prevMin = rowMin
	end
	return prev[lb] or BIG
end

function Validation.suggest(question, text)
	local key = Validation.key(text)
	if #key < 2 or #key > 60 or question.lookup[key] then return nil end
	-- how far off a guess may be: about one slip per 5 letters. Short words (4 letters or
	-- fewer) only get a neighbouring-key slip or two swapped letters, never a different letter.
	if #key < 3 then return nil end
	local cap = #key <= 4 and .8 or math.clamp(#key * .2, 1, 2.4)
	local reach = math.max(1, math.floor(cap))
	local byLen = question.keysByLen
	if not byLen then return nil end
	local k1, k2 = string.byte(key, 1), string.byte(key, 2)
	local adj1 = ADJ[k1] or {}
	local best = {}
	local started = os.clock()
	-- closest lengths first, so running out of time still leaves the likeliest answers checked
	local lens = { #key }
	for d = 1, reach do table.insert(lens, #key - d); table.insert(lens, #key + d) end
	for _, len in ipairs(lens) do
		local bucket = byLen[len]
		if bucket and len >= 1 then
			for n, entry in ipairs(bucket) do
				local ek = entry.key
				local e1 = string.byte(ek, 1)
				-- the first letter has to be right, a neighbouring key, or shifted by one
				if e1 == k1 or adj1[e1] or e1 == k2 or string.byte(ek, 2) == k1 then
					local d = bandedDistance(key, ek, cap, reach)
					if d <= cap and (not best[entry.answer] or d < best[entry.answer]) then best[entry.answer] = d end
				end
				if n % 500 == 0 and os.clock() - started > SUGGEST_BUDGET then break end
			end
		end
		if os.clock() - started > SUGGEST_BUDGET then break end
	end
	local chosen, score, second = nil, math.huge, math.huge
	for answer, d in pairs(best) do
		if d < score then second = score; score = d; chosen = answer elseif d < second then second = d end
	end
	-- two answers about equally close: don't guess
	if chosen and second - score >= .3 then return chosen.name end
	return nil
end

return Validation
