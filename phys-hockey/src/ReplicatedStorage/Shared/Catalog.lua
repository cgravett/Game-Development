--!strict
-- Every cosmetic in the game. The server checks ownership against this table; the client
-- only reads it to draw the shop and the locker. Prices are soft currency (coins) earned by
-- playing, so nothing here is sold for Robux.

local Catalog = {}

export type Item = {
	id: string,
	kind: string, -- "hat" | "hair" | "face" | "stick" | "outfit" | "finish" | "build" | "back" | "puck" | "goal" | "rink"
	name: string,
	price: number,
	color: Color3?,
	accent: Color3?,
	-- Which model builder draws it (Looks.STICK_STYLES for sticks; for hats and face wear, the
	-- hat or face whose shape it reuses in its own colours). Lets a future shop item be a sword
	-- or a spatula without touching the hitbox, which always comes from Sim.
	style: string?,
	-- Season pass reward (the season id): earned from the pass, never sold in the shop.
	pass: string?,
	-- No longer sold (players who bought it keep it and can still wear it).
	retired: boolean?,
	-- Earned another way, never sold: "tutorial" (finishing the first-time tutorial) or
	-- "firstgame" (Build 40: finishing a first whole match; the Nova set).
	reward: string?,
	-- Build 34: only from the Mystery Box (Shared/MysteryBox), never sold for coins.
	box: boolean?,
	-- Build 41: a line about the item on its shop page (the rinks say what their goal show is).
	desc: string?,
}

export type Look = {
	hat: string,
	hair: string,
	face: string,
	stick: string,
	outfit: string,
	finish: string, -- body finish (the SKIN slot: Frost, Gold Chrome); "skin" is the skin tone
	build: string, -- body type
	back: string, -- back bling
	puck: string, -- the puck you see in your own games
	goal: string, -- the goal sound everyone hears when you score
	rink: string, -- the rink your matches show in (looks only)
	skin: number,
	hairColor: number,
}

Catalog.Kinds = { "hat", "hair", "face", "stick", "outfit", "finish", "build", "back", "puck", "goal", "rink" }
Catalog.KindNames = {
	hat = "HEADWEAR",
	hair = "HAIR",
	face = "FACE",
	stick = "STICK",
	outfit = "OUTFIT",
	finish = "SKIN",
	build = "BODY",
	back = "BACK BLING",
	puck = "PUCK",
	goal = "GOAL SOUND",
	rink = "RINK",
}
-- Slots the coin shop sells (outfits are season pass and Mystery Box rewards). Build 34: goal
-- sounds and rinks are sold too.
-- Build 36: sticks first, then faces (in shop order).
Catalog.ShopKinds = { "stick", "face", "hat", "hair", "back", "goal", "rink" }

Catalog.SkinTones = {
	Color3.fromRGB(255, 219, 186),
	Color3.fromRGB(241, 194, 160),
	Color3.fromRGB(224, 172, 128),
	Color3.fromRGB(190, 132, 92),
	Color3.fromRGB(141, 92, 62),
	Color3.fromRGB(98, 62, 42),
}

Catalog.HairColors = {
	Color3.fromRGB(46, 34, 30),
	Color3.fromRGB(96, 62, 38),
	Color3.fromRGB(176, 120, 64),
	Color3.fromRGB(236, 196, 104),
	Color3.fromRGB(196, 72, 44),
	Color3.fromRGB(232, 232, 236),
	Color3.fromRGB(96, 156, 232),
	Color3.fromRGB(240, 120, 184),
}

local ITEMS: { Item } = {
	-- Headwear
	{ id = "helmet", kind = "hat", name = "Team Helmet", price = 0 },
	{ id = "nohat", kind = "hat", name = "No Hat", price = 0 },
	{ id = "beanie", kind = "hat", name = "Pom Beanie", price = 600, color = Color3.fromRGB(226, 70, 70), accent = Color3.fromRGB(250, 250, 250) },
	{ id = "cap", kind = "hat", name = "Ball Cap", price = 600, color = Color3.fromRGB(52, 98, 196), accent = Color3.fromRGB(240, 240, 244) },
	{ id = "army", kind = "hat", name = "Field Helmet", price = 1200, retired = true, color = Color3.fromRGB(86, 112, 64), accent = Color3.fromRGB(64, 86, 48) },
	{ id = "chef", kind = "hat", name = "Chef Hat", price = 1200, retired = true, color = Color3.fromRGB(246, 246, 246), accent = Color3.fromRGB(230, 230, 230) },
	{ id = "party", kind = "hat", name = "Party Hat", price = 1000, color = Color3.fromRGB(246, 92, 196), accent = Color3.fromRGB(255, 222, 70) },
	{ id = "tophat", kind = "hat", name = "Top Hat", price = 2000, color = Color3.fromRGB(30, 30, 36), accent = Color3.fromRGB(196, 40, 52) },
	{ id = "viking", kind = "hat", name = "Viking Helm", price = 2600, color = Color3.fromRGB(150, 156, 166), accent = Color3.fromRGB(246, 236, 210) },
	{ id = "melon", kind = "hat", name = "Melon Lid", price = 3200, color = Color3.fromRGB(70, 168, 70), accent = Color3.fromRGB(28, 92, 36) },
	{ id = "crown", kind = "hat", name = "Rink Crown", price = 6000, color = Color3.fromRGB(255, 200, 40), accent = Color3.fromRGB(226, 52, 72) },
	{ id = "propeller", kind = "hat", name = "Propeller Cap", price = 1600, color = Color3.fromRGB(52, 98, 196), accent = Color3.fromRGB(255, 214, 60) },
	-- Build 26 (assets/headwear/headwear3.py): ten of everything in the shop.
	{ id = "trapper", kind = "hat", name = "Trapper Hat", price = 1400, color = Color3.fromRGB(150, 40, 40), accent = Color3.fromRGB(246, 236, 214) },
	{ id = "antlers", kind = "hat", name = "Antler Band", price = 2200, color = Color3.fromRGB(200, 40, 52), accent = Color3.fromRGB(150, 104, 62) },

	-- Hair
	{ id = "short", kind = "hair", name = "Short", price = 0 },
	{ id = "bald", kind = "hair", name = "Clean", price = 0 },
	{ id = "spiky", kind = "hair", name = "Spiky", price = 400 },
	{ id = "long", kind = "hair", name = "Flow", price = 600 },
	{ id = "mohawk", kind = "hair", name = "Mohawk", price = 1000 },
	{ id = "afro", kind = "hair", name = "Big Puff", price = 1200 },
	{ id = "bun", kind = "hair", name = "Top Knot", price = 800 },
	{ id = "pigtails", kind = "hair", name = "Braids", price = 800 },
	{ id = "bob", kind = "hair", name = "Bob", price = 1000 },
	{ id = "quiff", kind = "hair", name = "Quiff", price = 1400 },
	{ id = "ponytail", kind = "hair", name = "Ponytail", price = 900 },
	{ id = "curly", kind = "hair", name = "Curly Top", price = 1600 },

	-- Face
	{ id = "plain", kind = "face", name = "Smile", price = 0 },
	{ id = "shades", kind = "face", name = "Shades", price = 800, color = Color3.fromRGB(24, 24, 30) },
	{ id = "glasses", kind = "face", name = "Specs", price = 600, color = Color3.fromRGB(40, 40, 48) },
	{ id = "mustache", kind = "face", name = "Mustache", price = 800, color = Color3.fromRGB(70, 44, 30) },
	{ id = "rednose", kind = "face", name = "Red Nose", price = 1000, color = Color3.fromRGB(230, 40, 40) },
	{ id = "beard", kind = "face", name = "Big Beard", price = 1200, color = Color3.fromRGB(84, 56, 36) },
	{ id = "eyepatch", kind = "face", name = "Eye Patch", price = 1000, color = Color3.fromRGB(24, 24, 30) },
	-- Build 36: Ski Goggles 2000 and Monocle 1400 (were the other way round); the card colour follows the price.
	{ id = "goggles", kind = "face", name = "Ski Goggles", price = 2000, color = Color3.fromRGB(246, 246, 250) },
	{ id = "monocle", kind = "face", name = "Monocle", price = 1400, color = Color3.fromRGB(255, 200, 60) },
	{ id = "bandage", kind = "face", name = "Bandage", price = 500, color = Color3.fromRGB(232, 190, 150) },
	{ id = "starshades", kind = "face", name = "Star Shades", price = 1600, color = Color3.fromRGB(255, 92, 170) },

	-- Outfits: a whole modelled body (Looks OUTFITS, meshes in ReplicatedStorage.OutfitMeshes).
	-- The colour is the card swatch.
	{ id = "teamkit", kind = "outfit", name = "Team Kit", price = 0 },
	{ id = "s1_santa", kind = "outfit", name = "Santa Suit", price = 0, style = "Santa", pass = "S1", color = Color3.fromRGB(199, 28, 38), accent = Color3.fromRGB(250, 247, 242) },
	{ id = "s1_reaper", kind = "outfit", name = "Reaper Cloak", price = 0, style = "Reaper", pass = "S1", color = Color3.fromRGB(38, 33, 48), accent = Color3.fromRGB(178, 92, 255) },
	{ id = "s1_snowman", kind = "outfit", name = "Snowman", price = 0, style = "Snowman", pass = "S1", color = Color3.fromRGB(242, 247, 252), accent = Color3.fromRGB(41, 143, 214) },
	{ id = "s1_galaxy", kind = "outfit", name = "Galaxy Body", price = 0, style = "Galaxy", pass = "S1", color = Color3.fromRGB(118, 46, 186), accent = Color3.fromRGB(36, 170, 214) },
	-- Build 31: completes the chef set (the Chef Hat and Lava Chef).
	{ id = "s1_chefcoat", kind = "outfit", name = "Chef Coat", price = 0, style = "Chef", pass = "S1", color = Color3.fromRGB(247, 247, 242), accent = Color3.fromRGB(219, 33, 38) },

	-- Skins: a finish over the whole body (Looks FINISHES). Colour and accent are the swatch.
	{ id = "natural", kind = "finish", name = "Natural", price = 0 },
	{ id = "s1_frostskin", kind = "finish", style = "Frost", name = "Frost Skin", price = 0, pass = "S1", color = Color3.fromRGB(176, 226, 255), accent = Color3.fromRGB(255, 255, 255) },
	{ id = "s1_goldchrome", kind = "finish", style = "GoldChrome", name = "Gold Chrome", price = 0, pass = "S1", color = Color3.fromRGB(255, 196, 46), accent = Color3.fromRGB(255, 244, 190) },

	-- Body types (Looks BUILDS). Looks only: every body has the same hitbox.
	{ id = "standard", kind = "build", name = "Standard", price = 0 },
	-- Build 37: no longer on the pass and has no effect (body sizes are gone); kept so saves that
	-- own it still load.
	{ id = "s1_bruiser", kind = "build", style = "Bruiser", name = "Big Bruiser", price = 0, pass = "S1", color = Color3.fromRGB(196, 60, 52), accent = Color3.fromRGB(40, 40, 48) },

	-- Back bling: modelled pieces worn on the back (Looks BACKS, meshes in BackMeshes).
	{ id = "noback", kind = "back", name = "None", price = 0 },
	{ id = "s1_hockeybag", kind = "back", style = "HockeyBag", name = "Hockey Bag", price = 0, pass = "S1", color = Color3.fromRGB(40, 70, 150), accent = Color3.fromRGB(240, 196, 40) },
	{ id = "s1_icewings", kind = "back", style = "IceWings", name = "Ice Wings", price = 0, pass = "S1", color = Color3.fromRGB(150, 220, 255), accent = Color3.fromRGB(255, 255, 255) },
	{ id = "s1_jetpack", kind = "back", style = "Jetpack", name = "Jetpack", price = 0, pass = "S1", color = Color3.fromRGB(200, 204, 214), accent = Color3.fromRGB(255, 120, 30) },
	-- Shop back bling (assets/backbling), priced like the hats: a simple pack up to a gold trophy.
	{ id = "puckpack", kind = "back", style = "PuckPack", name = "Puck Pack", price = 1200, color = Color3.fromRGB(32, 32, 38), accent = Color3.fromRGB(255, 140, 40) },
	{ id = "mininet", kind = "back", style = "MiniNet", name = "Mini Net", price = 1800, color = Color3.fromRGB(220, 40, 44), accent = Color3.fromRGB(240, 242, 246) },
	{ id = "shredboard", kind = "back", style = "Snowboard", name = "Shred Board", price = 2400, color = Color3.fromRGB(40, 182, 222), accent = Color3.fromRGB(255, 92, 150) },
	{ id = "penguinpal", kind = "back", style = "PenguinPal", name = "Penguin Pal", price = 3200, color = Color3.fromRGB(36, 40, 56), accent = Color3.fromRGB(255, 154, 40) },
	{ id = "champcup", kind = "back", style = "ChampCup", name = "Champ Cup", price = 6000, color = Color3.fromRGB(214, 220, 230), accent = Color3.fromRGB(255, 200, 60) },
	-- Build 25 shop back bling (assets/backbling/backbling2.py).
	{ id = "snowpal", kind = "back", style = "SnowPal", name = "Snow Pal", price = 1400, color = Color3.fromRGB(246, 250, 255), accent = Color3.fromRGB(214, 40, 52) },
	{ id = "resurfacer", kind = "back", style = "Resurfacer", name = "Mini Resurfacer", price = 2800, color = Color3.fromRGB(244, 246, 250), accent = Color3.fromRGB(36, 96, 206) },
	{ id = "cocoamug", kind = "back", style = "CocoaMug", name = "Cocoa Mug", price = 1600, color = Color3.fromRGB(206, 44, 52), accent = Color3.fromRGB(252, 246, 240) },
	{ id = "skatepair", kind = "back", style = "SkatePair", name = "Spare Skates", price = 2200, color = Color3.fromRGB(30, 30, 36), accent = Color3.fromRGB(40, 110, 220) },
	{ id = "miniscoreboard", kind = "back", style = "MiniScoreboard", name = "Mini Scoreboard", price = 4000, color = Color3.fromRGB(34, 36, 44), accent = Color3.fromRGB(255, 196, 40) },

	-- Pucks: how the puck looks in your own games (Looks.dressPuck).
	{ id = "blackpuck", kind = "puck", name = "Game Puck", price = 0 },
	{ id = "s1_snowflakepuck", kind = "puck", style = "Snowflake", name = "Snowflake Puck", price = 0, pass = "S1", color = Color3.fromRGB(226, 242, 255), accent = Color3.fromRGB(120, 196, 255) },
	{ id = "s1_lavapuck", kind = "puck", style = "Lava", name = "Lava Puck", price = 0, pass = "S1", color = Color3.fromRGB(40, 28, 26), accent = Color3.fromRGB(255, 110, 20) },
	{ id = "s1_galaxypuck", kind = "puck", style = "Galaxy", name = "Galaxy Puck", price = 0, pass = "S1", color = Color3.fromRGB(70, 30, 140), accent = Color3.fromRGB(60, 210, 255) },
	-- Build 34: Mystery Box exclusives.
	{ id = "mb_goldpuck", kind = "puck", style = "Gold", name = "Gold Puck", price = 0, box = true, color = Color3.fromRGB(255, 196, 46), accent = Color3.fromRGB(255, 244, 190) },
	{ id = "mb_toxicpuck", kind = "puck", style = "Toxic", name = "Toxic Puck", price = 0, box = true, color = Color3.fromRGB(30, 34, 30), accent = Color3.fromRGB(120, 255, 60) },
	{ id = "mb_shadowreaper", kind = "outfit", style = "ShadowReaper", name = "Shadow Reaper", price = 0, box = true, color = Color3.fromRGB(22, 16, 24), accent = Color3.fromRGB(255, 40, 40) },
	{ id = "mb_goldsuit", kind = "outfit", style = "GoldenSuit", name = "Golden Suit", price = 0, box = true, color = Color3.fromRGB(240, 186, 40), accent = Color3.fromRGB(250, 247, 242) },
	{ id = "mb_slimeman", kind = "outfit", style = "SlimeSnowman", name = "Slime Snowman", price = 0, box = true, color = Color3.fromRGB(130, 240, 90), accent = Color3.fromRGB(150, 60, 220) },

	-- Goal sounds: what everyone hears when you score (Fx GOAL_SOUNDS).
	{ id = "arenahorn", kind = "goal", name = "Arena Horn", price = 0, color = Color3.fromRGB(196, 40, 52), accent = Color3.fromRGB(255, 255, 255) },
	{ id = "s1_airhorn", kind = "goal", style = "AirHorn", name = "Air Horn", price = 0, pass = "S1", color = Color3.fromRGB(240, 70, 60), accent = Color3.fromRGB(255, 220, 60) },
	{ id = "s1_fireworks", kind = "goal", style = "Fireworks", name = "Fireworks", price = 0, pass = "S1", color = Color3.fromRGB(30, 26, 70), accent = Color3.fromRGB(255, 90, 200) },
	-- Build 34: goal sounds for coins (licensed library clips: Fx.SOUNDS).
	{ id = "duckyhorn", kind = "goal", style = "RubberDucky", name = "Rubber Ducky", price = 1500, color = Color3.fromRGB(255, 214, 40), accent = Color3.fromRGB(255, 130, 30) },
	{ id = "goathorn", kind = "goal", style = "BillyGoat", name = "Billy Goat", price = 1800, color = Color3.fromRGB(236, 230, 214), accent = Color3.fromRGB(120, 90, 60) },
	{ id = "partyhorn", kind = "goal", style = "PartyPopper", name = "Guitar Shred", price = 2000, color = Color3.fromRGB(255, 80, 170), accent = Color3.fromRGB(60, 210, 255) },
	{ id = "vikinghorn", kind = "goal", style = "VikingHorn", name = "Viking Horn", price = 2500, color = Color3.fromRGB(230, 214, 180), accent = Color3.fromRGB(140, 96, 56) },
	{ id = "trainhorn", kind = "goal", style = "ChooChoo", name = "Choo Choo", price = 3000, color = Color3.fromRGB(200, 40, 44), accent = Color3.fromRGB(40, 40, 48) },

	-- Rinks: the rink your own matches are shown in (looks only; ArenaBuilder themes).
	{ id = "matchrink", kind = "rink", name = "Match Rink", price = 0, color = Color3.fromRGB(206, 222, 238), accent = Color3.fromRGB(40, 72, 160), desc = "The classic rink. Every goal dims the lights and puts the spotlight on the scorer." },
	{ id = "s1_frozenlake", kind = "rink", style = "FrozenLake", name = "Frozen Lake", price = 0, pass = "S1", color = Color3.fromRGB(70, 110, 170), accent = Color3.fromRGB(255, 170, 90), desc = "Comes with its own custom goal effect: a frost shockwave rings out across the ice and a snow squall blows in." },
	-- Build 34: rinks for coins, the dearest things in the shop. The same rink everywhere (looks
	-- only): ArenaBuilder themes of the same name.
	-- Build 39: Moon Base and Neon Arcade swapped prices (ids unchanged, so owners keep them).
	{ id = "moonrink", kind = "rink", style = "MoonBase", name = "Moon Base", price = 12000, color = Color3.fromRGB(40, 44, 70), accent = Color3.fromRGB(120, 200, 255), desc = "Comes with its own custom goal effect: the floodlights sweep the ice in circles and flicker." },
	{ id = "candyrink", kind = "rink", style = "CandyLand", name = "Candy Land", price = 14000, color = Color3.fromRGB(255, 170, 214), accent = Color3.fromRGB(110, 220, 255), desc = "Comes with its own custom goal effect: the crowd throws sweets onto the ice." },
	{ id = "beachrink", kind = "rink", style = "TropicalBeach", name = "Tropical Beach", price = 16000, color = Color3.fromRGB(250, 214, 150), accent = Color3.fromRGB(40, 190, 210), desc = "Comes with its own custom goal effect: giant beach balls bounce across the ice under a shower of petals." },
	{ id = "volcanorink", kind = "rink", style = "Volcano", name = "Volcano", price = 20000, color = Color3.fromRGB(40, 30, 30), accent = Color3.fromRGB(255, 110, 20), desc = "Comes with its own custom goal effect: the braziers erupt and lob glowing lava bombs onto the ice." },
	{ id = "neonrink", kind = "rink", style = "NeonArcade", name = "Neon Arcade", price = 25000, color = Color3.fromRGB(30, 16, 60), accent = Color3.fromRGB(255, 60, 200), desc = "Comes with its own custom goal effect: a neon laser show sweeps the ice." },

	-- Sticks: shaft colour, then blade tape colour
	{ id = "classic", kind = "stick", name = "Classic", price = 0, color = Color3.fromRGB(32, 32, 38), accent = Color3.fromRGB(40, 42, 52) },
	-- Shop sticks: modelled in Blender (assets/sticks/shopsticks.py), sold for coins.
	{ id = "spatula", kind = "stick", style = "Spatula", name = "Spatula", price = 800, retired = true, color = Color3.fromRGB(204, 209, 219), accent = Color3.fromRGB(219, 41, 36) },
	{ id = "baguette", kind = "stick", style = "Baguette", name = "Toast & Baguette", price = 1000, color = Color3.fromRGB(214, 160, 90), accent = Color3.fromRGB(250, 228, 170) },
	{ id = "curlingbroom", kind = "stick", style = "CurlingBroom", name = "Curling Broom", price = 1400, color = Color3.fromRGB(200, 40, 48), accent = Color3.fromRGB(240, 240, 244) },
	{ id = "bamboo", kind = "stick", style = "Bamboo", name = "Bamboo", price = 1800, color = Color3.fromRGB(150, 190, 90), accent = Color3.fromRGB(70, 120, 50) },
	{ id = "vikingoar", kind = "stick", style = "VikingOar", name = "Viking Oar", price = 2400, color = Color3.fromRGB(160, 110, 64), accent = Color3.fromRGB(200, 40, 40) },
	{ id = "thunderbolt", kind = "stick", style = "Thunderbolt", name = "Thunderbolt", price = 4800, color = Color3.fromRGB(60, 66, 80), accent = Color3.fromRGB(255, 210, 40) },
	-- Build 25 shop sticks (assets/sticks/shopsticks2.py).
	{ id = "banana", kind = "stick", style = "Banana", name = "Top Banana", price = 800, color = Color3.fromRGB(252, 214, 46), accent = Color3.fromRGB(92, 64, 36) },
	{ id = "hotdog", kind = "stick", style = "HotDog", name = "Hot Dog", price = 1600, color = Color3.fromRGB(219, 153, 76), accent = Color3.fromRGB(184, 66, 41) },
	{ id = "icepop", kind = "stick", style = "IcePop", name = "Rocket Pop", price = 1200, color = Color3.fromRGB(240, 51, 66), accent = Color3.fromRGB(56, 133, 245) },
	{ id = "fairwayclub", kind = "stick", style = "FairwayClub", name = "Fairway Club", price = 2000, color = Color3.fromRGB(31, 33, 41), accent = Color3.fromRGB(51, 191, 89) },
	{ id = "rockaxe", kind = "stick", style = "RockAxe", name = "Rock Axe", price = 3600, color = Color3.fromRGB(219, 31, 36), accent = Color3.fromRGB(245, 242, 235) },
	-- Build 27: the tutorial reward (assets/sticks/rewardstick.py), never sold.
	-- Build 30: the reward is now the Golden Comet stick (Build 29's Rookie Gold before it). The id stays "foamfinger" so every player
	-- who already earned it keeps it (saves store item ids).
	{ id = "foamfinger", kind = "stick", style = "GoldenComet", name = "Golden Comet", price = 0, reward = "tutorial", color = Color3.fromRGB(255, 196, 46), accent = Color3.fromRGB(38, 217, 255) },
	-- Build 40: the first-full-match reward, the Nova set (never sold): all four are granted (and
	-- worn) the first time a player finishes a whole match (PlayerData.grantMatch). Its neon
	-- pulses, the reactor's rings spin and the blade leaves a light trail (Looks).
	{ id = "fg_novaarmor", kind = "outfit", style = "Nova", name = "Nova Armor", price = 0, reward = "firstgame", color = Color3.fromRGB(26, 28, 42), accent = Color3.fromRGB(0, 225, 255) },
	{ id = "fg_novavisor", kind = "hat", style = "novavisor", name = "Nova Visor", price = 0, reward = "firstgame", color = Color3.fromRGB(26, 28, 42), accent = Color3.fromRGB(0, 225, 255) },
	{ id = "fg_novareactor", kind = "back", style = "NovaReactor", name = "Nova Reactor", price = 0, reward = "firstgame", color = Color3.fromRGB(60, 66, 88), accent = Color3.fromRGB(255, 50, 200) },
	{ id = "fg_novablade", kind = "stick", style = "NovaBlade", name = "Nova Blade", price = 0, reward = "firstgame", color = Color3.fromRGB(26, 28, 42), accent = Color3.fromRGB(0, 225, 255) },
	-- Old colour-swap sticks, retired from the shop (owners keep them). Prices were quadrupled in
	-- Build 25. Since Build 26 every shop slot sells exactly 10 items, none of them season pass rewards.
	{ id = "wood", kind = "stick", name = "Old Wood", price = 480, retired = true, color = Color3.fromRGB(168, 116, 66), accent = Color3.fromRGB(246, 246, 248) },
	{ id = "neon", kind = "stick", name = "Neon Tape", price = 1000, retired = true, color = Color3.fromRGB(32, 32, 38), accent = Color3.fromRGB(230, 250, 60) },
	{ id = "candy", kind = "stick", name = "Candy Cane", price = 1400, retired = true, color = Color3.fromRGB(246, 246, 248), accent = Color3.fromRGB(224, 40, 52) },
	{ id = "frost", kind = "stick", name = "Frostbite", price = 2000, retired = true, color = Color3.fromRGB(150, 210, 250), accent = Color3.fromRGB(240, 250, 255) },
	{ id = "gold", kind = "stick", name = "Gold Twig", price = 4800, retired = true, color = Color3.fromRGB(255, 196, 40), accent = Color3.fromRGB(255, 232, 130) },

	-- Season 1 pass rewards (see SeasonPass). Hats and face wear reuse a shape in new colours.
	{ id = "s1_ember", kind = "stick", name = "Ember", price = 0, pass = "S1", color = Color3.fromRGB(44, 30, 30), accent = Color3.fromRGB(255, 110, 40) },
	{ id = "s1_glacier", kind = "stick", name = "Glacier", price = 0, pass = "S1", color = Color3.fromRGB(70, 170, 205), accent = Color3.fromRGB(232, 250, 255) },
	-- Build 41: the Toxic, Carbon and Champion Gold sticks remade as animated modelled sticks (ids
	-- unchanged; the season has never been live). assets/sticks/passsticks41.py.
	{ id = "s1_toxic", kind = "stick", style = "ToxicSludge", name = "Toxic Sludge", price = 0, pass = "S1", color = Color3.fromRGB(30, 34, 30), accent = Color3.fromRGB(120, 255, 60) },
	-- Midnight, Royal, Sunset, Bubblegum and Aurora were pass sticks; modelled sticks took their
	-- tiers, so they are sold in the shop for coins instead.
	{ id = "s1_midnight", kind = "stick", name = "Midnight", price = 1600, retired = true, color = Color3.fromRGB(26, 28, 64), accent = Color3.fromRGB(150, 110, 255) },
	{ id = "s1_royal", kind = "stick", name = "Royal", price = 2400, retired = true, color = Color3.fromRGB(92, 40, 150), accent = Color3.fromRGB(255, 200, 60) },
	{ id = "s1_sunset", kind = "stick", name = "Sunset", price = 1800, retired = true, color = Color3.fromRGB(250, 120, 80), accent = Color3.fromRGB(255, 222, 120) },
	{ id = "s1_bubblegum", kind = "stick", name = "Bubblegum", price = 1400, retired = true, color = Color3.fromRGB(255, 140, 200), accent = Color3.fromRGB(255, 255, 255) },
	{ id = "s1_carbon", kind = "stick", style = "CarbonStrike", name = "Carbon Striker", price = 0, pass = "S1", color = Color3.fromRGB(18, 18, 22), accent = Color3.fromRGB(210, 34, 44) },
	{ id = "s1_aurora", kind = "stick", name = "Aurora", price = 3200, retired = true, color = Color3.fromRGB(40, 220, 170), accent = Color3.fromRGB(180, 90, 255) },
	{ id = "s1_champion", kind = "stick", style = "ChampionGold", name = "Champion Gold", price = 0, pass = "S1", color = Color3.fromRGB(255, 210, 70), accent = Color3.fromRGB(30, 30, 36) },
	-- Modelled sticks (Blender meshes in ReplicatedStorage.StickMeshes; assets/sticks). Same hitbox
	-- as every stick: only the look changes. Their colours are part of the model.
	{ id = "s1_timber", kind = "stick", style = "OldTimber", name = "Old Timber", price = 0, pass = "S1", color = Color3.fromRGB(204, 153, 97), accent = Color3.fromRGB(26, 26, 31) },
	{ id = "s1_frostfang", kind = "stick", style = "FrostFang", name = "Frost Fang", price = 0, pass = "S1", color = Color3.fromRGB(66, 43, 31), accent = Color3.fromRGB(140, 224, 255) },
	{ id = "s1_ripsaw", kind = "stick", style = "Ripsaw", name = "Ripsaw", price = 0, pass = "S1", color = Color3.fromRGB(26, 26, 28), accent = Color3.fromRGB(250, 115, 20) },
	{ id = "s1_shredder", kind = "stick", style = "Shredder", name = "Shredder", price = 0, pass = "S1", color = Color3.fromRGB(235, 191, 128), accent = Color3.fromRGB(204, 20, 36) },
	{ id = "s1_plasma", kind = "stick", style = "PlasmaSaber", name = "Plasma Saber", price = 0, pass = "S1", color = Color3.fromRGB(153, 158, 173), accent = Color3.fromRGB(255, 64, 204) },
	{ id = "s1_dragonbone", kind = "stick", style = "DragonBone", name = "Dragon Bone", price = 0, pass = "S1", color = Color3.fromRGB(235, 222, 189), accent = Color3.fromRGB(255, 89, 13) },
	{ id = "s1_sharkbite", kind = "stick", style = "SharkBite", name = "Shark Bite", price = 0, pass = "S1", color = Color3.fromRGB(20, 46, 107), accent = Color3.fromRGB(107, 135, 163) },
	{ id = "s1_peppermint", kind = "stick", style = "Peppermint", name = "Peppermint Crook", price = 0, pass = "S1", color = Color3.fromRGB(250, 247, 242), accent = Color3.fromRGB(219, 20, 31) },
	{ id = "s1_trident", kind = "stick", style = "Trident", name = "Golden Trident", price = 0, pass = "S1", color = Color3.fromRGB(255, 199, 64), accent = Color3.fromRGB(26, 242, 217) },
	{ id = "s1_roboclaw", kind = "stick", style = "RoboClaw", name = "Robo Claw", price = 0, pass = "S1", color = Color3.fromRGB(71, 77, 87), accent = Color3.fromRGB(255, 199, 26) },
	{ id = "s1_frostbeanie", kind = "hat", style = "beanie", name = "Frost Beanie", price = 0, pass = "S1", color = Color3.fromRGB(150, 210, 250), accent = Color3.fromRGB(255, 255, 255) },
	-- Build 41: the plain caps, shades and specs remade as animated pieces (assets/headwear/headwear7.py):
	-- halos that spin and float, an orbiting planet, scanner visors and hologram specs.
	{ id = "s1_neoncap", kind = "hat", style = "halo", name = "Neon Halo", price = 0, pass = "S1", color = Color3.fromRGB(40, 40, 48), accent = Color3.fromRGB(120, 255, 60) },
	{ id = "s1_snowviking", kind = "hat", style = "viking", name = "Snowcap Viking", price = 0, pass = "S1", color = Color3.fromRGB(222, 234, 246), accent = Color3.fromRGB(120, 200, 255) },
	{ id = "s1_goldcap", kind = "hat", style = "halo", name = "Golden Halo", price = 0, pass = "S1", color = Color3.fromRGB(255, 200, 50), accent = Color3.fromRGB(255, 244, 190) },
	{ id = "s1_camo", kind = "hat", style = "army", name = "Snow Camo Helmet", price = 0, pass = "S1", color = Color3.fromRGB(220, 226, 232), accent = Color3.fromRGB(130, 140, 150) },
	{ id = "s1_neonparty", kind = "hat", style = "party", name = "Neon Party Hat", price = 0, pass = "S1", color = Color3.fromRGB(40, 230, 255), accent = Color3.fromRGB(255, 60, 200) },
	{ id = "s1_midnighttop", kind = "hat", style = "tophat", name = "Midnight Top Hat", price = 0, pass = "S1", color = Color3.fromRGB(26, 28, 64), accent = Color3.fromRGB(255, 200, 60) },
	{ id = "s1_lavachef", kind = "hat", style = "chef", name = "Lava Chef", price = 0, pass = "S1", color = Color3.fromRGB(255, 120, 60), accent = Color3.fromRGB(255, 222, 90) },
	{ id = "s1_berrymelon", kind = "hat", style = "melon", name = "Berry Lid", price = 0, pass = "S1", color = Color3.fromRGB(120, 60, 200), accent = Color3.fromRGB(70, 30, 120) },
	{ id = "s1_lavabeanie", kind = "hat", style = "beanie", name = "Lava Beanie", price = 0, pass = "S1", color = Color3.fromRGB(230, 60, 40), accent = Color3.fromRGB(30, 30, 36) },
	{ id = "s1_icecrown", kind = "hat", style = "crown", name = "Ice Crown", price = 0, pass = "S1", color = Color3.fromRGB(170, 225, 255), accent = Color3.fromRGB(60, 200, 255) },
	{ id = "s1_goldspecs", kind = "face", style = "HoloSpecs", name = "Gold Holo Specs", price = 0, pass = "S1", color = Color3.fromRGB(255, 200, 60), accent = Color3.fromRGB(255, 236, 150) },
	{ id = "s1_snowshades", kind = "face", style = "ScanVisor", name = "Snow Scanner", price = 0, pass = "S1", color = Color3.fromRGB(240, 244, 250), accent = Color3.fromRGB(90, 200, 255) },
	{ id = "s1_frostnose", kind = "face", style = "rednose", name = "Frost Nose", price = 0, pass = "S1", color = Color3.fromRGB(80, 170, 255) },
	{ id = "s1_rosespecs", kind = "face", style = "HoloSpecs", name = "Rose Holo Specs", price = 0, pass = "S1", color = Color3.fromRGB(255, 110, 170), accent = Color3.fromRGB(255, 196, 244) },
	{ id = "s1_frostystache", kind = "face", style = "mustache", name = "Frosty Stache", price = 0, pass = "S1", color = Color3.fromRGB(230, 240, 255) },
	{ id = "s1_chrome", kind = "face", style = "ScanVisor", name = "Chrome Scanner", price = 0, pass = "S1", color = Color3.fromRGB(170, 182, 204), accent = Color3.fromRGB(255, 40, 60) },
	-- Build 31 (tiers 41-50): each themed outfit's matching pieces, plus variants in the season's colours.
	{ id = "s1_santahat", kind = "hat", style = "santahat", name = "Santa Hat", price = 0, pass = "S1", color = Color3.fromRGB(199, 28, 38), accent = Color3.fromRGB(250, 247, 242) },
	{ id = "s1_snowmanhead", kind = "hat", style = "snowmanhead", name = "Snowman Head", price = 0, pass = "S1", color = Color3.fromRGB(242, 247, 252), accent = Color3.fromRGB(255, 128, 32) },
	{ id = "s1_chefhat", kind = "hat", style = "chef", name = "Chef Hat", price = 0, pass = "S1", color = Color3.fromRGB(248, 248, 246), accent = Color3.fromRGB(232, 232, 230) },
	{ id = "s1_galaxycap", kind = "hat", style = "orbit", name = "Galaxy Orbit", price = 0, pass = "S1", color = Color3.fromRGB(118, 46, 186), accent = Color3.fromRGB(36, 170, 214) },
	{ id = "s1_peppermintbeanie", kind = "hat", style = "beanie", name = "Peppermint Beanie", price = 0, pass = "S1", color = Color3.fromRGB(219, 20, 31), accent = Color3.fromRGB(250, 247, 242) },
	{ id = "s1_santabeard", kind = "face", style = "beard", name = "Santa Beard", price = 0, pass = "S1", color = Color3.fromRGB(250, 248, 244) },
	{ id = "s1_frostgoggles", kind = "face", style = "goggles", name = "Frost Goggles", price = 0, pass = "S1", color = Color3.fromRGB(150, 215, 255) },
	-- Build 41: modelled molten-lava goggles (pulsing lava, embers), replacing the painted lens.
	{ id = "s1_lavagoggles", kind = "face", style = "LavaGoggles", name = "Lava Goggles", price = 0, pass = "S1", color = Color3.fromRGB(255, 110, 30) },
	{ id = "s1_galaxyshades", kind = "face", style = "starshades", name = "Galaxy Shades", price = 0, pass = "S1", color = Color3.fromRGB(140, 70, 230) },
	-- Build 37: pass tier 30 (premium), replacing the Big Bruiser: the whole head is the galaxy.
	{ id = "s1_galaxyhead", kind = "face", style = "GalaxyHead", name = "Galaxy Head", price = 0, pass = "S1", color = Color3.fromRGB(158, 115, 255) },
	{ id = "s1_soulshades", kind = "face", style = "ScanVisor", name = "Soul Scanner", price = 0, pass = "S1", color = Color3.fromRGB(40, 30, 56), accent = Color3.fromRGB(178, 92, 255) },
	{ id = "s1_reaperscythe", kind = "stick", style = "ReaperScythe", name = "Reaper Scythe", price = 0, pass = "S1", color = Color3.fromRGB(51, 38, 31), accent = Color3.fromRGB(178, 92, 255) },
}

Catalog.Items = ITEMS
Catalog.ById = {} :: { [string]: Item }
for _, item in ITEMS do
	Catalog.ById[item.id] = item
end

Catalog.DefaultLook = table.freeze({
	hat = "helmet",
	hair = "short",
	face = "plain",
	stick = "classic",
	outfit = "teamkit",
	finish = "natural",
	build = "standard",
	back = "noback",
	puck = "blackpuck",
	goal = "arenahorn",
	rink = "matchrink",
	skin = 2,
	hairColor = 1,
})

-- Starting items every profile owns.
Catalog.Starter = { "helmet", "nohat", "short", "bald", "plain", "classic", "teamkit", "natural", "standard", "noback", "blackpuck", "arenahorn", "matchrink" }

-- Build 40: the Nova set, granted (and worn) together at the end of a player's first whole
-- match (PlayerData.grantMatch). The armour is the marker: owning it means the set was given.
Catalog.FirstGameReward = { "fg_novaarmor", "fg_novavisor", "fg_novareactor", "fg_novablade" }

-- Sold in the shop for coins (season pass rewards and starter items are not).
function Catalog.inShop(item: Item): boolean
	return item.price > 0 and item.pass == nil and not item.retired and not item.box
end

-- The shape an item draws with: its style, or its own id.
function Catalog.styleOf(id: string): string
	local item = Catalog.ById[id]
	return (item and item.style) or id
end

function Catalog.itemsOfKind(kind: string): { Item }
	local out = {}
	for _, item in ITEMS do
		if item.kind == kind then
			table.insert(out, item)
		end
	end
	return out
end

-- Fills in anything missing or invalid, so a look from any source can be drawn safely.
function Catalog.sanitizeLook(look: any): Look
	local out = table.clone(Catalog.DefaultLook) :: any
	if type(look) ~= "table" then
		return out
	end
	for _, kind in Catalog.Kinds do
		local id = look[kind]
		local item = type(id) == "string" and Catalog.ById[id]
		if item and item.kind == kind then
			out[kind] = id
		end
	end
	local skin = tonumber(look.skin)
	if skin and Catalog.SkinTones[math.floor(skin)] then
		out.skin = math.floor(skin)
	end
	local hairColor = tonumber(look.hairColor)
	if hairColor and Catalog.HairColors[math.floor(hairColor)] then
		out.hairColor = math.floor(hairColor)
	end
	return out
end

-- Bots get a stable, varied look from their seed so a lobby full of bots doesn't look cloned.
-- Build 30: each one wears a full, put-together set from the shop and the season pass (the
-- things players can get), so the ice shows off what is on offer. Team kits stay on, so the
-- teams still read at a glance. Seed 9 is Coach Gus, dressed like a coach.
local BOT_SETS: { { hat: string, face: string, stick: string, back: string, finish: string?, hair: string? } } = {
	{ hat = "viking", face = "beard", stick = "vikingoar", back = "s1_hockeybag" },
	{ hat = "s1_neoncap", face = "s1_chrome", stick = "s1_plasma", back = "s1_jetpack" },
	{ hat = "crown", face = "shades", stick = "thunderbolt", back = "champcup" },
	{ hat = "s1_icecrown", face = "s1_snowshades", stick = "s1_frostfang", back = "s1_icewings", finish = "s1_frostskin" },
	{ hat = "helmet", face = "goggles", stick = "s1_ripsaw", back = "mininet" },
	{ hat = "s1_midnighttop", face = "monocle", stick = "s1_trident", back = "miniscoreboard" },
	{ hat = "s1_lavabeanie", face = "eyepatch", stick = "s1_dragonbone", back = "puckpack" },
	{ hat = "propeller", face = "starshades", stick = "icepop", back = "penguinpal" },
	{ hat = "cap", face = "mustache", stick = "classic", back = "noback", hair = "short" },
	{ hat = "s1_snowviking", face = "s1_goldspecs", stick = "s1_roboclaw", back = "shredboard", finish = "s1_goldchrome" },
	{ hat = "trapper", face = "s1_frostystache", stick = "s1_sharkbite", back = "resurfacer" },
	{ hat = "s1_neonparty", face = "s1_rosespecs", stick = "rockaxe", back = "skatepair" },
}
local BOT_HAIRS = { "spiky", "long", "mohawk", "afro", "bun", "quiff", "curly", "ponytail" }

function Catalog.botLook(seed: number): Look
	local set = BOT_SETS[(seed - 1) % #BOT_SETS + 1]
	local function valid(id: string?, kind: string, fallback: string): string
		local item = id and Catalog.ById[id]
		return if item and item.kind == kind then id :: string else fallback
	end
	return {
		hat = valid(set.hat, "hat", "helmet"),
		hair = valid(set.hair or BOT_HAIRS[(seed * 7 + 26) % #BOT_HAIRS + 1], "hair", "short"),
		face = valid(set.face, "face", "plain"),
		stick = valid(set.stick, "stick", "classic"),
		outfit = "teamkit",
		finish = valid(set.finish, "finish", "natural"),
		build = "standard",
		back = valid(set.back, "back", "noback"),
		puck = "blackpuck",
		goal = "arenahorn",
		rink = "matchrink",
		skin = (seed * 5 + 1) % #Catalog.SkinTones + 1,
		hairColor = (seed * 3 + 2) % #Catalog.HairColors + 1,
	}
end

return Catalog
