-- Stars out profanity for display. Clamillion is made for kids, so bad words are NEVER shown:
-- not while typing, not in reveals, recaps, hints or "Did you mean". They still COUNT as answers;
-- only what's displayed changes. Profanity.mask(text) returns text of the SAME length with the
-- bad part of each word replaced by "*" (so the answer box can keep the real text underneath).
--
-- Two kinds of bad words:
--   ROOTS: starred wherever they appear, even inside a longer word ("Brain****", "s******").
--   WORDS: starred only when the whole word matches ("ass" yes, "class"/"grass" no; typing "shit"
--          stars it, keep typing "shitake" and it un-stars).
-- Number/symbol stand-ins count as letters when a word is at least half letters ("sh1t", "5h1t", "Bada$$"),
-- but not in things like ".45s". Must stay identical to profanity.py in the build scripts.
local Profanity = {}

local LEET = { ["0"] = "o", ["1"] = "i", ["3"] = "e", ["4"] = "a", ["5"] = "s", ["7"] = "t", ["@"] = "a", ["$"] = "s" }

local ROOTS = { "fuck", "nigger", "nigga", "cunt", "bitch", "whore", "slut", "porn", "faggot", "asshole", "dildo", "jizz", "motherf" }

local SAFE = {} -- innocent words that contain a root
for w in string.gmatch("ansluten erpornis kanokporn nigslutter slutsk", "%S+") do SAFE[w] = true end

local WORDS = {}
for w in string.gmatch([[
	apeshit arse arsehole arses ass asses asshat asshats asswipe badass bastard bastards
	batshit bollock bollocks boner boners boob boobies boobs bullshit chickenshit chink chinks
	cock cocks cocksucker cocksuckers coon coons crap crapper crappy cum cums dammit
	damn damned damnit dick dickface dickhead dickheads dicks dipshit douche douchebag douches
	dumbass fag faggy fags fatass goddamn goddamned goddamnit gook gooks hell hellhole
	hells horny horseshit jackass kike kikes penis penises piss pissed pisses pissing
	pissy prick pricks pussies pussy rape raped rapes raping rapist rapists retard
	retarded retards sex sexes sexier sexiest sexting sexual sexuality sexually sexy shiit
	shit shite shitface shithead shitheads shithole shitload shits shitshow shitt shitted shitter
	shitters shittier shitting shitty skank skanks skanky smartass spic spick spicks spics
	tit tits titties titty twat twats vagina vaginal vaginas wank wanker wankers
	wanking wanks wanky
	fuk fuks fuking fuker fck fcking phuck phucking shyt biatch biatches thot thots milf milfs orgasm orgasms
]], "%S+") do WORDS[w] = true end

local function isLetter(b) return (b >= 65 and b <= 90) or (b >= 97 and b <= 122) end
local function normChar(ch)
	local b = string.byte(ch)
	if b >= 65 and b <= 90 then return string.char(b + 32) end
	if b >= 97 and b <= 122 then return ch end
	return LEET[ch]
end

local function check(out, i, j, tok)
	if WORDS[tok] then
		for k = i, j do out[k] = "*" end
	elseif not SAFE[tok] then
		for _, r in ipairs(ROOTS) do
			local start = string.find(tok, r, 1, true)
			while start do
				for k = i + start - 1, i + start - 1 + #r - 1 do out[k] = "*" end
				start = string.find(tok, r, start + 1, true)
			end
		end
	end
end

-- Returns s with bad words starred out (same length, byte for byte).
function Profanity.mask(s)
	if type(s) ~= "string" or s == "" then return s end
	local n = #s
	local out = table.create(n)
	local norm = table.create(n)
	for k = 1, n do
		local ch = string.sub(s, k, k)
		out[k] = ch
		norm[k] = normChar(ch) or false
	end
	local i = 1
	while i <= n do
		if not norm[i] then
			i += 1
		else
			local j = i
			while j + 1 <= n and norm[j + 1] do j += 1 end
			local letters = 0
			for k = i, j do if isLetter(string.byte(s, k)) then letters += 1 end end
			if letters >= (j - i + 1) - letters then
				local t = table.create(j - i + 1)
				for k = i, j do t[#t + 1] = norm[k] end
				check(out, i, j, table.concat(t))
			end
			-- the plain-letter runs are always words too ("shit123", but not ".45s")
			local k = i
			while k <= j do
				if not isLetter(string.byte(s, k)) then
					k += 1
				else
					local m = k
					while m + 1 <= j and isLetter(string.byte(s, m + 1)) do m += 1 end
					check(out, k, m, string.lower(string.sub(s, k, m)))
					k = m + 1
				end
			end
			i = j + 1
		end
	end
	return table.concat(out)
end

-- true if mask(s) would change anything
function Profanity.isProfane(s)
	return Profanity.mask(s) ~= s
end

return Profanity
