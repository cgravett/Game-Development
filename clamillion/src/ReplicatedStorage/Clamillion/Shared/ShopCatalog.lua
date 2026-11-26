-- Everything players can own: podium themes, arenas and titles.
--
-- PRICES: podiums 200 R$, arenas 500 R$, titles 50 R$, emotes 50 R$ (shown in the shop).
--
-- PURCHASES: every shop item has its OWN Developer Product (Creator Hub > [⚔️1v1] CLAMILLION >
-- Monetization > Developer Products), so the Roblox purchase window names the exact item.
-- The ids are in Catalog.ProductIds below (created 2026-10-26, Managed Pricing on).
-- A NEW shop item needs its own Developer Product: create it, then add its id to ProductIds.
-- Keep `price` below equal to the product's price on Roblox (the shop shows `price`).
-- source = "shop" (buyable), "wheel" (won on the Daily Wheel) or "free" (everyone owns it).
local Catalog = {}

-- Old one-product-per-price setup (no longer used; every item has its own product now).
Catalog.TierProducts = { Podium = nil, Arena = nil, Title = nil, Emote = nil }

-- item id -> Developer Product id
Catalog.ProductIds = {
	podium_aquarium = 3722649076, -- Podium: Aquarium, 200 R$
	podium_sports = 3722649325, -- Podium: Sports Star, 200 R$
	podium_unicorn = 3722649470, -- Podium: Unicorn Dream, 200 R$
	podium_rainbow = 3722649714, -- Podium: Rainbow Burst, 200 R$
	podium_galaxy = 3722649722, -- Podium: Galaxy Explorer, 200 R$
	podium_candy = 3722649728, -- Podium: Candy Land, 200 R$
	podium_dino = 3722649732, -- Podium: Dino Roar, 200 R$
	podium_gamer = 3722649734, -- Podium: Pro Gamer, 200 R$
	podium_kitty = 3722649739, -- Podium: Kitty Cat, 200 R$
	podium_superhero = 3722649744, -- Podium: Superhero, 200 R$
	arena_aquarium = 3722649748, -- Arena: Underwater Aquarium, 500 R$
	arena_space = 3722649753, -- Arena: Space Station, 500 R$
	arena_candy = 3722649755, -- Arena: Candy Kingdom, 500 R$
	arena_jungle = 3722649759, -- Arena: Jungle Safari, 500 R$
	arena_winter = 3722649764, -- Arena: Winter Wonderland, 500 R$
	title_quiz_champ = 3722649770, -- Title: Quiz Champ, 50 R$
	title_brain_blaster = 3722649775, -- Title: Brain Blaster, 50 R$
	title_answer_ace = 3722649779, -- Title: Answer Ace, 50 R$
	title_trivia_titan = 3722649784, -- Title: Trivia Titan, 50 R$
	title_fact_hunter = 3722649791, -- Title: Fact Hunter, 50 R$
	title_rare_finder = 3722649800, -- Title: Rare Finder, 50 R$
	title_big_brain = 3722649808, -- Title: Big Brain, 50 R$
	title_spotlight_star = 3722649812, -- Title: Spotlight Star, 50 R$
	title_show_stopper = 3722649820, -- Title: Show Stopper, 50 R$
	title_living_legend = 3722649827, -- Title: Living Legend, 50 R$
	title_know_it_all = 3722649832, -- Title: Know-It-All, 50 R$
	title_mega_mind = 3722649839, -- Title: Mega Mind, 50 R$
	title_smarty_pants = 3722649841, -- Title: Smarty Pants, 50 R$
	title_lightning_fast = 3722649852, -- Title: Lightning Fast, 50 R$
	title_puzzle_pro = 3722649856, -- Title: Puzzle Pro, 50 R$
	title_genius_mode = 3722649861, -- Title: Genius Mode, 50 R$
	title_fan_favorite = 3722649865, -- Title: Fan Favorite, 50 R$
	title_prime_time = 3722649867, -- Title: Prime Time, 50 R$
	title_golden_buzzer = 3722649874, -- Title: Golden Buzzer, 50 R$
	title_mystery_master = 3722649877, -- Title: Mystery Master, 50 R$
	emote_jump = 3722649879, -- Emote: Jump for Joy, 50 R$
	emote_twirl = 3722649882, -- Emote: Twirl, 50 R$
	emote_fistpump = 3722649887, -- Emote: Fist Pump, 50 R$
	emote_dance = 3722649891, -- Emote: Happy Dance, 50 R$
	emote_disco = 3722649896, -- Emote: Disco Fever, 50 R$
	emote_robot = 3722649899, -- Emote: Robot Groove, 50 R$
	emote_wave = 3722649908, -- Emote: Big Wave, 50 R$
	emote_point = 3722649913, -- Emote: Spin & Point, 50 R$
	emote_giggle = 3722649918, -- Emote: Giggle Fit, 50 R$
	emote_rocket = 3722649922, -- Emote: Rocket Spin, 50 R$
}
Catalog.TierPrices = { Podium = 200, Arena = 500, Title = 50, Emote = 50 }

-- HINTS (the HINT ? button next to the answer box during a show): one Developer Product priced
-- 50 R$, bought again each time. A hint reveals the question bank's hint answer (85 points).
Catalog.HintProduct = 3722649924 -- "Answer Hint", 50 R$
Catalog.HintPrice = 50

-- MYSTERY BOX (the gift button under SHOP): 100 R$ for one random prize from the SHOP items.
-- It's a Roblox "paid random item", so (1) the odds are always shown before buying, (2) players
-- in places where paid random items aren't allowed can't buy it (PolicyService), and (3) the
-- experience's maturity questionnaire must say it has paid random items.
-- PRODUCT: create a Developer Product "Mystery Box" priced 100 R$ (Creator Hub > Monetization >
-- Developer Products) and paste its id below. Until then, Studio playtests open boxes for free
-- (so you can test) and the live game shows "coming soon".
-- Odds are per CATEGORY; the item inside a category is picked evenly from the ones the player
-- doesn't own yet (never a duplicate). If they own the whole category, they get the hints instead.
Catalog.MysteryBox = {
	productId = 3723634186, -- "Mystery Box" Developer Product, 100 R$ (created 2026-10-29)
	price = 100,
	hints = 2, -- the hint prize (and the prize when a category is already complete)
	odds = {
		{ kind = "Arena", pct = 15, label = "Arena", icon = "🏟" },
		{ kind = "Podium", pct = 25, label = "Podium", icon = "🎤" },
		{ kind = "Title", pct = 20, label = "Title", icon = "🏷" },
		{ kind = "Emote", pct = 20, label = "Emote", icon = "💃" },
		{ kind = "Hint", pct = 20, label = "2 Answer Hints", icon = "💡" },
	},
}

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

Catalog.Podiums = {
	{ id = "podium_aquarium", theme = "aquarium", name = "Aquarium", icon = "🐠", blurb = "Glass fish tanks, coral and bubbles!", colors = { rgb(40, 150, 230), rgb(20, 70, 150) }, price = 200, productId = nil, source = "shop" },
	{ id = "podium_sports", theme = "sports", name = "Sports Star", icon = "🏀", blurb = "Jersey stripes, a turf pedestal and a trophy.", colors = { rgb(240, 70, 70), rgb(60, 170, 70) }, price = 200, productId = nil, source = "shop" },
	{ id = "podium_unicorn", theme = "unicorn", name = "Unicorn Dream", icon = "🦄", blurb = "A golden horn, rainbow mane and fluffy clouds.", colors = { rgb(255, 190, 230), rgb(190, 150, 255) }, price = 200, productId = nil, source = "shop" },
	{ id = "podium_rainbow", theme = "rainbow", name = "Rainbow Burst", icon = "🌈", blurb = "A glowing rainbow arch right over your head!", colors = { rgb(255, 90, 120), rgb(90, 140, 255) }, price = 200, productId = nil, source = "shop" },
	{ id = "podium_galaxy", theme = "galaxy", name = "Galaxy Explorer", icon = "🪐", blurb = "Twinkling stars, a ringed planet and a rocket.", colors = { rgb(120, 60, 220), rgb(30, 15, 70) }, price = 200, productId = nil, source = "shop" },
	{ id = "podium_candy", theme = "candy", name = "Candy Land", icon = "🍭", blurb = "Candy canes, lollipops and frosting drips.", colors = { rgb(255, 140, 200), rgb(140, 235, 200) }, price = 200, productId = nil, source = "shop" },
	{ id = "podium_dino", theme = "dino", name = "Dino Roar", icon = "🦖", blurb = "Spikes, spots and a dino egg about to hatch.", colors = { rgb(100, 190, 80), rgb(255, 150, 40) }, price = 200, productId = nil, source = "shop" },
	{ id = "podium_gamer", theme = "gamer", name = "Pro Gamer", icon = "🎮", blurb = "RGB lights everywhere and a giant controller.", colors = { rgb(0, 230, 140), rgb(160, 60, 255) }, price = 200, productId = nil, source = "shop" },
	{ id = "podium_kitty", theme = "space_cat", name = "Kitty Cat", icon = "🐱", blurb = "Kitty ears, a curly tail, paw prints and yarn.", colors = { rgb(255, 170, 70), rgb(255, 150, 200) }, price = 200, productId = nil, source = "shop" },
	{ id = "podium_superhero", theme = "superhero", name = "Superhero", icon = "⚡", blurb = "A flowing cape, lightning bolts and a hero emblem.", colors = { rgb(50, 90, 230), rgb(230, 40, 50) }, price = 200, productId = nil, source = "shop" },
}

-- REWARD podiums (free, claimed at the Rewards stand once your total score is high enough)
for _, r in ipairs({
	{ id = "podium_bronze", theme = "bronze", name = "Bronze Star", icon = "🥉", blurb = "A shiny bronze podium with a medal on top.", colors = { rgb(215, 140, 70), rgb(120, 70, 30) }, req = 1000 },
	{ id = "podium_silver", theme = "silver", name = "Silver Star", icon = "🥈", blurb = "Gleaming silver with a sparkle shine.", colors = { rgb(215, 220, 235), rgb(120, 130, 150) }, req = 5000 },
	{ id = "podium_gold", theme = "gold", name = "Gold Star", icon = "🥇", blurb = "Solid gold, a trophy and a laurel crown.", colors = { rgb(255, 210, 60), rgb(200, 130, 10) }, req = 10000 },
	{ id = "podium_prism", theme = "prism", name = "Rainbow Legend", icon = "🌈", blurb = "ANIMATED! Glows every color of the rainbow.", colors = { rgb(255, 90, 160), rgb(90, 140, 255) }, req = 50000, animated = true },
}) do
	r.source = "reward"; r.stat = "totalScore"
	table.insert(Catalog.Podiums, r)
end

-- HALLOWEEN EVENT (Shared.Events): free to claim at the Rewards stand ONLY while the event is on
-- (Fri Oct 30 5:30 PM ET -> Sun Nov 1 11:55 PM ET). Anyone who claims one keeps it forever.
-- stat = "halloween" is playtime counted only during the event; req 0 = claim right away.
Catalog.EventStats = { halloween = "halloween" } -- reward stat -> event id
table.insert(Catalog.Podiums, { id = "podium_halloween", theme = "halloween", name = "Haunted Pumpkin", icon = "🎃", blurb = "Glowing jack-o'-lanterns, bats, cobwebs and a spooky graveyard!", colors = { rgb(255, 120, 20), rgb(90, 30, 140) }, source = "reward", stat = "halloween", req = 0, event = "halloween", limited = true })

Catalog.Arenas = {
	{ id = "arena_classic", theme = nil, name = "Classic Studio", icon = "⭐", blurb = "The original Clamillion studio.", colors = { rgb(255, 92, 182), rgb(60, 128, 255) }, source = "free" },
	{ id = "arena_aquarium", theme = "Aquarium", name = "Underwater Aquarium", icon = "🐋", blurb = "Play the show at the bottom of the sea! Whales, fish, coral and bubbles.", colors = { rgb(30, 170, 220), rgb(10, 50, 120) }, price = 500, productId = nil, source = "shop" },
	{ id = "arena_space", theme = "Space", name = "Space Station", icon = "🚀", blurb = "Blast off! Stars, glowing planets, rockets and a satellite zooming overhead.", colors = { rgb(110, 70, 230), rgb(15, 10, 50) }, price = 500, productId = nil, source = "shop" },
	{ id = "arena_candy", theme = "Candy", name = "Candy Kingdom", icon = "🍭", blurb = "A sugary studio with giant lollipops, candy canes and floating sweets.", colors = { rgb(255, 140, 200), rgb(140, 230, 210) }, price = 500, productId = nil, source = "shop" },
	{ id = "arena_jungle", theme = "Jungle", name = "Jungle Safari", icon = "🌴", blurb = "Palm trees, hanging vines, a waterfall and parrots flying around!", colors = { rgb(70, 190, 90), rgb(120, 80, 40) }, price = 500, productId = nil, source = "shop" },
	{ id = "arena_winter", theme = "Winter", name = "Winter Wonderland", icon = "❄️", blurb = "Snow falling on stage, snowy pine trees, snowmen and giant snowflakes.", colors = { rgb(170, 220, 255), rgb(60, 110, 200) }, price = 500, productId = nil, source = "shop" },
	-- Halloween event arena (free to claim during the event only)
	{ id = "arena_halloween", theme = "Halloween", name = "Haunted Halloween", icon = "🎃", blurb = "Witches flying overhead, giant jack-o'-lanterns, dancing skeletons, bats, ghosts and graveyard fog!", colors = { rgb(255, 120, 20), rgb(60, 15, 90) }, source = "reward", stat = "halloween", req = 0, event = "halloween", limited = true },
}

-- titles players show on their podium (and above their head in the lobby)
local shopTitles = {
	{ "Quiz Champ", "🏆" }, { "Brain Blaster", "💥" }, { "Answer Ace", "🃏" }, { "Trivia Titan", "🗿" }, { "Fact Hunter", "🔍" },
	{ "Rare Finder", "💎" }, { "Big Brain", "🧠" }, { "Spotlight Star", "🌟" }, { "Show Stopper", "🎬" }, { "Living Legend", "👑" },
	{ "Know-It-All", "📚" }, { "Mega Mind", "🔮" }, { "Smarty Pants", "👖" }, { "Lightning Fast", "⚡" }, { "Puzzle Pro", "🧩" },
	{ "Genius Mode", "🤓" }, { "Fan Favorite", "💖" }, { "Prime Time", "📺" }, { "Golden Buzzer", "🔔" }, { "Mystery Master", "🎩" },
}
-- titles won on the Daily Wheel (in wheel order, clockwise from the top)
-- RARE ones are animated and have a thinner slice on the wheel (weight < 1 = smaller slice = rarer).
Catalog.WheelTitles = {
	{ "Rising Star", "★" }, { "Crowd Favorite", "♥" }, { "Golden Voice", "♪" }, { "Showtime", "✦" },
	{ "Spotlight Seeker", "☀" }, { "Encore", "↻" }, { "Studio VIP", "♛" }, { "Lucky Star", "✿" },
	{ "Cosmic Legend", "🌌", anim = "rainbow", weight = 0.6, rare = true },
	{ "Lucky Duck", "☘" }, { "Party Starter", "☂" }, { "Wild Card", "♠" }, { "Rock Star", "⚡" },
	{ "Star Power", "✪" }, { "Happy Camper", "⛺" }, { "Cool Cat", "😎" }, { "Top Banana", "🍌" },
	{ "Golden Jackpot", "💰", anim = "gold", weight = 0.6, rare = true },
}
-- where each wheel title sits: { center = angle, half = half-width } in radians, clockwise from the top
function Catalog.wheelLayout()
	local total = 0
	for _, t in ipairs(Catalog.WheelTitles) do total += t.weight or 1 end
	local layout, at = {}, 0
	for i, t in ipairs(Catalog.WheelTitles) do
		local width = (t.weight or 1) / total * math.pi * 2
		if i == 1 then at = -width / 2 end -- the first prize is centred under the pointer at rest
		layout[i] = { center = at + width / 2, half = width / 2, weight = t.weight or 1 }
		at += width
	end
	return layout
end

Catalog.Titles = {}
local function titleId(name) return "title_" .. name:lower():gsub("[^%w]+", "_") end
for _, t in ipairs(shopTitles) do
	table.insert(Catalog.Titles, { id = titleId(t[1]), name = t[1], icon = t[2], price = 50, productId = nil, source = "shop" })
end
for _, t in ipairs(Catalog.WheelTitles) do
	table.insert(Catalog.Titles, { id = titleId(t[1]), name = t[1], icon = t[2], source = "wheel", anim = t.anim, rare = t.rare })
end
-- REWARD titles: animated titles unlocked by playtime (seconds), claimed at the Rewards stand.
-- anim = how the title moves: "pulse", "candy", "sparkle", "gold" or "rainbow".
local playtimeTitles = {
	{ "Trivial Challenger", "💡", 0, "rainbow" }, -- free welcome gift on first join
	{ "Snack Break", "🍿", 15 * 60, "pulse" },
	{ "Lobby Buddy", "🎈", 30 * 60, "candy" },
	{ "Show Regular", "🎟", 60 * 60, "sparkle" },
	{ "Sweet Tooth", "🍭", 2 * 3600, "candy" },
	{ "Super Fan", "📣", 5 * 3600, "rainbow" },
	{ "Studio Legend", "🌟", 10 * 3600, "gold" },
	{ "Candy Royalty", "👑", 24 * 3600, "rainbow" },
}
for _, t in ipairs(playtimeTitles) do
	table.insert(Catalog.Titles, { id = titleId(t[1]), name = t[1], icon = t[2], source = "reward", stat = "playtime", req = t[3], anim = t[4] })
end
-- Halloween event title: play 5 minutes DURING the event, then claim it (animated "spooky" colours)
table.insert(Catalog.Titles, { id = "title_halloween_hero", name = "Halloween Hero", icon = "🎃", source = "reward", stat = "halloween", req = 5 * 60, anim = "spooky", event = "halloween", limited = true, colors = { rgb(255, 120, 20), rgb(90, 30, 140) } })
Catalog.titleId = titleId

-- EMOTES: your victory move! Plays when you win a 1v1 / 1v1v1 show (as the camera swoops in)
-- and whenever you score a VERY RARE or EXTREMELY RARE answer. `style` is read by Shared.EmotePlayer.
Catalog.Emotes = {}
local emoteList = {
	{ "emote_jump", "Jump for Joy", "🦘", "Two big happy hops!", "jump", rgb(255, 170, 60), rgb(255, 90, 120) },
	{ "emote_twirl", "Twirl", "🌀", "A speedy spin like a ballerina.", "twirl", rgb(120, 200, 255), rgb(150, 90, 255) },
	{ "emote_fistpump", "Fist Pump", "✊", "YES! Pump those fists!", "fistpump", rgb(255, 90, 90), rgb(255, 180, 40) },
	{ "emote_dance", "Happy Dance", "💃", "A cheerful little dance.", "dance", rgb(255, 120, 200), rgb(255, 200, 80) },
	{ "emote_disco", "Disco Fever", "🕺", "Groovy disco moves!", "disco", rgb(190, 90, 255), rgb(60, 200, 255) },
	{ "emote_robot", "Robot Groove", "🤖", "Beep boop… dance mode ON.", "robot", rgb(150, 170, 200), rgb(60, 220, 180) },
	{ "emote_wave", "Big Wave", "👋", "Wave hello to all your fans!", "wave", rgb(80, 220, 140), rgb(60, 140, 255) },
	{ "emote_point", "Spin & Point", "👉", "Spin around, then point at the crowd.", "point", rgb(255, 210, 60), rgb(255, 120, 60) },
	{ "emote_giggle", "Giggle Fit", "😂", "Can't stop laughing!", "giggle", rgb(255, 230, 90), rgb(255, 140, 190) },
	{ "emote_rocket", "Rocket Spin", "🚀", "Blast off with a spinning super-jump!", "rocket", rgb(255, 110, 70), rgb(110, 90, 255) },
}
for _, e in ipairs(emoteList) do
	table.insert(Catalog.Emotes, { id = e[1], name = e[2], icon = e[3], blurb = e[4], style = e[5], colors = { e[6], e[7] }, price = 50, source = "shop" })
end
-- Halloween event emote (free to claim during the event): ride a witch's broom like a bucking bull!
table.insert(Catalog.Emotes, { id = "emote_broom", name = "Broom Rodeo", icon = "🧹", blurb = "Hop on a witch's broom and ride it like a bucking bull, one arm in the air!", style = "broom", colors = { rgb(255, 120, 20), rgb(120, 40, 200) }, source = "reward", stat = "halloween", req = 0, event = "halloween", limited = true })

-- lookup helpers -----------------------------------------------------------------
Catalog.Kinds = { Podium = Catalog.Podiums, Arena = Catalog.Arenas, Title = Catalog.Titles, Emote = Catalog.Emotes }
local byId, byProduct = {}, {}
for kind, list in pairs(Catalog.Kinds) do
	for _, item in ipairs(list) do
		item.kind = kind
		item.productId = item.productId or Catalog.ProductIds[item.id]
		byId[item.id] = item
		if item.productId then byProduct[item.productId] = item end
	end
end
function Catalog.get(id) return byId[id] end
function Catalog.byProduct(productId) return byProduct[productId] end
function Catalog.productFor(item) return item.productId or Catalog.TierProducts[item.kind] end
function Catalog.tierKind(productId)
	for kind, id in pairs(Catalog.TierProducts) do if id == productId then return kind end end
	return nil
end
function Catalog.forSale(item) return item.source == "shop" and Catalog.productFor(item) ~= nil end

-- Rewards stand lists, in unlock order
Catalog.Rewards = { playtime = {}, totalScore = {}, halloween = {} }
for _, list in pairs(Catalog.Kinds) do
	for _, item in ipairs(list) do
		if item.source == "reward" then table.insert(Catalog.Rewards[item.stat], item) end
	end
end
local KIND_ORDER = { Arena = 1, Podium = 2, Emote = 3, Title = 4 }
for _, list in pairs(Catalog.Rewards) do table.sort(list, function(a, b)
	if a.req ~= b.req then return a.req < b.req end
	return (KIND_ORDER[a.kind] or 9) < (KIND_ORDER[b.kind] or 9)
end) end

return Catalog
