--!strict
-- The season pass: one XP bar, 50 tiers, a free track (an item and 1,000 coins every 5 tiers)
-- and a premium track (an item on every tier), from the vault note "Battle Pass and Season Design". Everything
-- is keyed on the season id, so a new season is a new entry here and old progress is never mixed in.
--
-- Shared so the client can draw the tracks; the server alone adds XP, decides premium and
-- grants rewards. Rewards are granted automatically the moment a tier is reached (premium ones
-- too, back to tier 1, the moment premium is bought), so there is nothing to claim by hand and
-- nothing a client can ask for.
--
-- XP budget (Build 31): a flat TIER_XP per tier, so the last tier needs (50 - 1) x 350 = 17,150.
-- Pass XP comes from matches (matchXp: the match score, Build 35) and daily challenges (200 each). A
-- regular player (5 days a week, 3 matches and the 4 challenges a day) earns about 7,750 a week,
-- so finishes in a bit over 2 weeks; size the season (or TIER_XP) to that before launch. The vault
-- note "Battle Pass and Season Design" targets finishing at about 80 percent of the season.

local RunService = game:GetService("RunService")
local Catalog = require(script.Parent:WaitForChild("Catalog"))

local SeasonPass = {}

-- `soon` marks a reward whose system is not built yet (jerseys, back bling, pucks, goal sounds,
-- rinks, body types, skins): it shows on the track as a teaser and is never granted or marked
-- claimed, so when the real item replaces it, everyone who reached the tier gets it.
export type Reward = { item: string?, coins: number?, soon: string? }
export type Tier = {
	xp: number, -- cumulative XP needed to reach this tier
	free: Reward?,
	premium: Reward?,
}
export type Season = {
	id: string, -- never reuse an id
	name: string,
	-- false = on hold: live servers ignore it (the menu shows its track as "coming soon");
	-- Studio still runs it so it can be tested.
	live: boolean,
	startsAt: number, -- UTC seconds
	endsAt: number,
	-- Premium is a game pass made in the Creator Dashboard (Monetization > Passes) for this
	-- experience. 0 = not created yet: the premium button shows "coming soon".
	premiumPassId: number,
	tiers: { Tier },
}

-- Premium-track and free-track rewards, tier by tier. `item` ids are season items in Catalog
-- (marked pass = "S1", never sold in the shop). The full plan is in docs/SEASON1_PASS.md.
local function item(id: string, coins: number?): Reward
	assert(Catalog.ById[id], `SeasonPass: unknown item {id}`)
	return { item = id, coins = coins }
end
-- Every 5th free tier also pays this many coins (Build 32: 500, was 1,000; Build 37: 1,000
-- again), and every 5th premium tier PREMIUM_COINS on top of its item (Build 37: 2,000, was 1,000).
local FREE_COINS = 1000
local PREMIUM_COINS = 2000
local function soon(what: string): Reward
	return { soon = what }
end

local FREE: { [number]: Reward } = {
	[5] = item("s1_ember", FREE_COINS),
	[10] = item("s1_goldspecs", FREE_COINS),
	[15] = item("s1_timber", FREE_COINS),
	[20] = item("s1_frostbeanie", FREE_COINS),
	[25] = item("s1_snowman", FREE_COINS),
	[30] = item("s1_glacier", FREE_COINS),
	[35] = item("s1_snowshades", FREE_COINS),
	[40] = item("s1_snowviking", FREE_COINS),
	[45] = item("s1_chefhat", FREE_COINS),
	[50] = item("s1_snowmanhead", FREE_COINS), -- the free track's own capstone (goes with tier 25's Snowman)
}

local PREMIUM: { Reward } = {
	item("s1_goldcap"), -- 1: granted the moment premium is bought
	item("s1_toxic"),
	item("s1_snowflakepuck"),
	item("s1_frostnose"),
	item("s1_frostfang"), -- 5: the first modelled stick
	item("s1_camo"),
	item("s1_santa"),
	item("s1_peppermint"), -- 8: candy cane
	item("s1_rosespecs"),
	item("s1_airhorn"), -- 10
	item("s1_neonparty"),
	item("s1_sharkbite"), -- 12: shark on a fishing rod
	item("s1_hockeybag"),
	item("s1_frostystache"),
	item("s1_ripsaw"), -- 15: the chainsaw
	item("s1_midnighttop"),
	item("s1_lavapuck"),
	item("s1_roboclaw"), -- 18
	item("s1_frostskin"),
	item("s1_lavachef"), -- 20
	item("s1_reaper"),
	item("s1_trident"), -- 22
	item("s1_icewings"),
	item("s1_berrymelon"),
	item("s1_shredder"), -- 25: the guitar
	item("s1_fireworks"),
	item("s1_carbon"),
	item("s1_galaxypuck"),
	item("s1_lavabeanie"),
	item("s1_galaxyhead"), -- 30 (Build 37: the Galaxy Head; was Big Bruiser, a body size)
	item("s1_dragonbone"), -- 31
	item("s1_chrome"),
	item("s1_galaxy"),
	item("s1_neoncap"),
	item("s1_icecrown"), -- 35
	item("s1_jetpack"),
	item("s1_goldchrome"),
	item("s1_champion"),
	item("s1_frozenlake"),
	item("s1_plasma"), -- 40
	-- Build 31: tiers 41-50, the themed outfits' matching pieces.
	item("s1_santahat"), -- 41: goes with the Santa Suit
	item("s1_galaxycap"), -- 42: goes with the Galaxy Body
	item("s1_santabeard"),
	item("s1_peppermintbeanie"), -- 44: goes with the Peppermint Crook
	item("s1_frostgoggles"), -- 45
	item("s1_chefcoat"), -- 46: goes with the Chef Hat / Lava Chef
	item("s1_lavagoggles"), -- 47: goes with the Lava Beanie / Lava Puck
	item("s1_galaxyshades"),
	item("s1_soulshades"), -- 49: goes with the Reaper Cloak
	item("s1_reaperscythe"), -- 50: the season's capstone, the Reaper Cloak's scythe
}

local TIER_COUNT = 50
-- XP for each tier after the first (tier 1 is reached at once).
SeasonPass.TierXp = 350
local function ladder(): { Tier }
	local tiers = {}
	for i = 1, TIER_COUNT do
		local premium = PREMIUM[i]
		if premium and i % 5 == 0 and premium.item and not premium.coins then
			premium = { item = premium.item, coins = PREMIUM_COINS }
		end
		tiers[i] = { xp = (i - 1) * SeasonPass.TierXp, free = FREE[i], premium = premium }
	end
	return tiers
end

SeasonPass.Seasons = {
	{
		-- "S1B": the 50-tier ladder (40 until Build 31; the season has never been live, so no saved
		-- progress is read against different tiers). The 30-tier "S1" draft was briefly scheduled, so any progress
		-- saved under "S1" stays apart instead of being read against different tiers.
		id = "S1B",
		name = "SEASON 1 - FIRST FREEZE",
		live = false, -- on hold until every reward is built; set true and set real dates to launch
		startsAt = 1797292800, -- placeholder: 2026-12-15 00:00 UTC
		-- Build 32: six weeks. At 350 XP a tier a regular player finishes in about two; the rest
		-- is room for everyone else.
		endsAt = 1797292800 + 42 * 24 * 60 * 60, -- placeholder: 2027-01-26 00:00 UTC
		premiumPassId = 0,
		tiers = ladder(),
	},
} :: { Season }

SeasonPass.ById = {} :: { [string]: Season }
for _, s in SeasonPass.Seasons do
	SeasonPass.ById[s.id] = s
end

-- Build 35: a match is worth its score: pass XP equal to the player's score (no cap), and half
-- the score in coins. The score is the server's own count (100 a goal, 50 an assist, 25 a save,
-- 10 a shot: Main.server).
function SeasonPass.matchXp(score: number): number
	return math.max(0, math.floor(score))
end

function SeasonPass.matchCoins(score: number): number
	return math.max(0, math.floor(score / 2))
end

-- In Studio a season counts as running up to this long before it starts, and even while it is
-- on hold, so it can be tested before launch day. Live servers use the real start time and skip
-- seasons on hold.
local IS_STUDIO = RunService:IsStudio()
local STUDIO_LEAD = if IS_STUDIO then 60 * 86400 else 0

-- The season running at `now` (UTC seconds), or nil between seasons.
function SeasonPass.current(now: number): Season?
	for _, s in SeasonPass.Seasons do
		if (s.live or IS_STUDIO) and now >= s.startsAt - STUDIO_LEAD and now < s.endsAt then
			return s
		end
	end
	return nil
end

-- The next season to start after `now` (on hold or not), or nil if none is planned.
function SeasonPass.upcoming(now: number): Season?
	local best: Season? = nil
	for _, s in SeasonPass.Seasons do
		-- A season on hold counts as upcoming whatever its placeholder dates say.
		local ahead = s.startsAt > now or (not s.live and now < s.endsAt)
		if ahead and (best == nil or s.startsAt < best.startsAt) then
			best = s
		end
	end
	return best
end

-- Highest tier reached with this much XP (0 if none).
function SeasonPass.tierFor(season: Season, xp: number): number
	local reached = 0
	for i, tier in season.tiers do
		if xp >= tier.xp then
			reached = i
		else
			break
		end
	end
	return reached
end

return SeasonPass
