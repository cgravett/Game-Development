-- Studio-only stand-in contestants so a single developer can play a full match.
local Config = require(script.Parent.Parent.Config)
local BotService = {}

local NAMES = { "Bot Ada", "Bot Turing", "Bot Curie", "Bot Hopper", "Bot Darwin" }
local WEIGHTS = { common = 6, uncommon = 3, rare = 1.4, extremely_rare = 0.5 }

function BotService.name(i)
	return NAMES[((i - 1) % #NAMES) + 1]
end

local function chooseAnswer(question)
	local roll = math.random()
	if roll < 0.1 then return "" end              -- blank / timeout
	if roll < 0.2 then return "no idea" end       -- unrecognized
	local total = 0
	for _, a in ipairs(question.answers) do total += WEIGHTS[a.tier] or 1 end
	local pick = math.random() * total
	for _, a in ipairs(question.answers) do
		pick -= WEIGHTS[a.tier] or 1
		if pick <= 0 then
			-- sometimes type an alias or lowercase to exercise normalisation
			if #a.aliases > 0 and math.random() < 0.3 then return a.aliases[math.random(#a.aliases)] end
			return math.random() < 0.5 and string.lower(a.name) or a.name
		end
	end
	return question.answers[1].name
end

-- onDraft(text) and onLock(text) are provided by MatchService and do their own phase checks.
function BotService.play(question, duration, onDraft, onLock)
	local answer = chooseAnswer(question)
	if answer == "" then return end
	task.delay(math.random(15, 70) / 10, function()
		if math.random() < 0.85 then onLock(answer) else onDraft(answer) end
	end)
end

return BotService

