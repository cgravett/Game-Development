--!strict
-- One guard for every client remote: rate first, then shape. Invalid traffic is dropped
-- silently and counted, with a periodic summary rather than one log line per rejection.

local Config = require(game:GetService("ReplicatedStorage").Shared.GameConfig)

local SecurityService = {}

local SEC = Config.Security
local SUMMARY_SECONDS = 60

type Bucket = { tokens: number, last: number }
type Record = { packets: Bucket, actions: Bucket, violations: number }

local records: { [Player]: Record } = {}
local pendingViolations = 0
local lastSummary = 0

local function take(bucket: Bucket, rate: number, burst: number): boolean
	local now = os.clock()
	bucket.tokens = math.min(burst, bucket.tokens + (now - bucket.last) * rate)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function SecurityService.add(player: Player)
	local now = os.clock()
	records[player] = {
		packets = { tokens = SEC.PacketBurst, last = now },
		actions = { tokens = SEC.ActionBurst, last = now },
		violations = 0,
	}
end

function SecurityService.remove(player: Player)
	records[player] = nil
end

function SecurityService.allowPacket(player: Player): boolean
	local record = records[player]
	return record ~= nil and take(record.packets, SEC.PacketsPerSecond, SEC.PacketBurst)
end

function SecurityService.allowAction(player: Player): boolean
	local record = records[player]
	return record ~= nil and take(record.actions, SEC.ActionsPerSecond, SEC.ActionBurst)
end

function SecurityService.violation(player: Player)
	local record = records[player]
	if record then
		record.violations += 1
	end
	pendingViolations += 1
	local now = os.clock()
	if now - lastSummary >= SUMMARY_SECONDS then
		lastSummary = now
		warn(`[Security] {pendingViolations} invalid messages discarded in the last period`)
		pendingViolations = 0
	end
end

function SecurityService.violationsFor(player: Player): number
	local record = records[player]
	return if record then record.violations else 0
end

return SecurityService
