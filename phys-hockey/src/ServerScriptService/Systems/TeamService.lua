--!strict
-- Six fixed slots: 1-3 are team 1, 4-6 are team 2. A slot is run by a player or a bot, so a
-- join or leave swaps the controller without touching simulation state. Slots 3 and 6 are the
-- bot goalie's seat, filled by humans last.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.GameConfig)
local Sim = require(ReplicatedStorage.Shared.Sim)
local BotBrain = require(ReplicatedStorage.Shared.BotBrain)
local Catalog = require(ReplicatedStorage.Shared.Catalog)

local TeamService = {}

local FILL_ORDER = { { 1, 2, 3 }, { 4, 5, 6 } }

local world: Sim.World
local slotPlayer: { [number]: Player? } = {}
local playerSlot: { [Player]: number } = {}
local botStates: { [number]: BotBrain.BotState } = {}
local botNames: { [number]: string } = {}
local lookOf: (Player) -> any = function()
	return nil
end

function TeamService.setLookProvider(fn: (Player) -> any)
	lookOf = fn
end

local function goalieSeat(slot: number): boolean
	return slot == 3 or slot == 6
end

local function refreshGoalie(slot: number)
	world.skaters[slot].goalie = goalieSeat(slot) and slotPlayer[slot] == nil
end

function TeamService.init(w: Sim.World)
	world = w
	for slot = 1, 6 do
		local team = if slot <= 3 then 1 else 2
		world.skaters[slot] = Sim.newSkater(slot, team)
		botStates[slot] = BotBrain.newState()
		botNames[slot] = Config.Bots.Names[slot]
		refreshGoalie(slot)
	end
end

function TeamService.humansOnIce(): number
	local count = 0
	for _ in playerSlot do
		count += 1
	end
	return count
end

local function humansOnTeam(team: number): number
	local count = 0
	for _, slot in FILL_ORDER[team] do
		if slotPlayer[slot] then
			count += 1
		end
	end
	return count
end

-- Returns the slot, or nil if the ice is full and the player stays a spectator.
function TeamService.assign(player: Player): number?
	local existing = playerSlot[player]
	if existing then
		return existing
	end
	local first = if humansOnTeam(1) <= humansOnTeam(2) then 1 else 2
	for _, team in { first, 3 - first } do
		for _, slot in FILL_ORDER[team] do
			if not slotPlayer[slot] then
				slotPlayer[slot] = player
				playerSlot[player] = slot
				local s = world.skaters[slot]
				s.input = Sim.newInput()
				refreshGoalie(slot)
				return slot
			end
		end
	end
	return nil
end

function TeamService.release(player: Player)
	local slot = playerSlot[player]
	if not slot then
		return
	end
	playerSlot[player] = nil
	slotPlayer[slot] = nil
	world.skaters[slot].input = Sim.newInput()
	botStates[slot] = BotBrain.newState()
	refreshGoalie(slot)
end

function TeamService.slotOf(player: Player): number?
	return playerSlot[player]
end

function TeamService.playerIn(slot: number): Player?
	return slotPlayer[slot]
end

function TeamService.stepBots(dt: number)
	-- One player alone against bots: the bot goalie they shoot at is easier to beat.
	local solo = TeamService.humansOnIce() == 1
	for slot, s in world.skaters do
		if not slotPlayer[slot] then
			botStates[slot].easy = solo and s.goalie and humansOnTeam(s.team) == 0
			-- Build 39: which slots players hold (a bot centre only holds back against a player's).
			;(botStates[slot] :: any).humans = slotPlayer
			BotBrain.think(world, s, if s.goalie then "Goalie" else "Field", botStates[slot], dt)
		end
	end
end

-- Roster published to clients. Display names only come from the Player object.
function TeamService.roster(): { any }
	local roster = table.create(6)
	for slot = 1, 6 do
		local player = slotPlayer[slot]
		roster[slot] = {
			name = if player then player.DisplayName else botNames[slot],
			userId = if player then player.UserId else 0,
			bot = player == nil,
			look = if player then lookOf(player) else Catalog.botLook(slot + 3),
		}
	end
	return roster
end

return TeamService
