-- Lobby mini obby: checkpoints, lava, a spinning bar, a timer and a "fastest today" board.
-- Run state lives on the player as attributes so the client can show the timer:
--   ObbyCP     = last checkpoint reached (nil when not on a run)
--   ObbyStart  = server time the run started
--
-- "Fastest today" is shared by ALL servers: each day (midnight to midnight US Eastern) has its own
-- OrderedDataStore of everyone's best time, so a new day starts with an empty board. The board
-- shows today's top 3. Servers re-read it every 20 s, and immediately when another server
-- reports a new time (MessagingService). Studio playtests use a separate test board.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local UserService = game:GetService("UserService")
local RunService = game:GetService("RunService")
local Remotes = RS.Clamillion.Remotes

local Obby = {}
local obby, checkpoints, lastCP
local inMatch
local cooldown = {} -- player -> os.clock of last teleport
local best = {}     -- userId -> {name, time} : today's times known to THIS server (merged with the shared top 3)
local shared = {}   -- today's shared top 3 from the DataStore: { {userId, time} }
local names = {}    -- userId -> display name
local BOUNDS_MIN, BOUNDS_MAX = Vector2.new(24, 96), Vector2.new(128, 278)
local TOP = 3
local TOPIC = "ClamillionObbyTimes"

---------------------------------------------------------------- today's date (US Eastern, midnight reset)
local function daysFromCivil(y, m, d)
	y = y - (m <= 2 and 1 or 0)
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + d - 1
	return era * 146097 + yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy - 719468
end
local function nthSunday(y, m, n)
	local first = daysFromCivil(y, m, 1)
	return first + ((7 - (first + 4) % 7) % 7) + (n - 1) * 7
end
local function easternOffset(t) -- EDT (UTC-4) 2nd Sun of March .. 1st Sun of November, else EST (UTC-5)
	local y = tonumber(os.date("!%Y", t))
	local dstStart = nthSunday(y, 3, 2) * 86400 + 7 * 3600
	local dstEnd = nthSunday(y, 11, 1) * 86400 + 6 * 3600
	return (t >= dstStart and t < dstEnd) and -4 or -5
end
local function today()
	local t = os.time()
	return math.floor((t + easternOffset(t) * 3600) / 86400)
end

local currentDay = today()
local function storeFor(day)
	local scope = (RunService:IsStudio() and "studio_" or "day_") .. day
	local ok, store = pcall(function() return DataStoreService:GetOrderedDataStore("ClamillionObbyDaily_v1", scope) end)
	return ok and store or nil
end

local function now() return workspace:GetServerTimeNow() end
local function root(p) return p.Character and p.Character:FindFirstChild("HumanoidRootPart") end

local function inBounds(pos)
	return pos.X >= BOUNDS_MIN.X and pos.X <= BOUNDS_MAX.X and pos.Z >= BOUNDS_MIN.Y and pos.Z <= BOUNDS_MAX.Y
end

local function formatTime(t)
	return ("%d:%05.2f"):format(math.floor(t / 60), t % 60)
end

local function nameFor(userId)
	if names[userId] then return names[userId] end
	local live = Players:GetPlayerByUserId(userId)
	if live then names[userId] = live.DisplayName return names[userId] end
	local ok, infos = pcall(function() return UserService:GetUserInfosByUserIdsAsync({ userId }) end)
	names[userId] = (ok and infos and infos[1] and infos[1].DisplayName) or ("Player " .. userId)
	return names[userId]
end

local function renderBoard()
	local board = obby:FindFirstChild("ObbyBoard")
	local body = board and board:FindFirstChild("Sign") and board.Sign:FindFirstChild("Body", true)
	if not body then return end
	-- today's shared top 3, merged with this server's own fresh times (in case a save is still on its way)
	local merged = {}
	for _, e in ipairs(shared) do merged[e.userId] = e.time end
	for userId, e in pairs(best) do
		if not merged[userId] or e.time < merged[userId] then merged[userId] = e.time end
	end
	local list = {}
	for userId, t in pairs(merged) do table.insert(list, { userId = userId, time = t }) end
	table.sort(list, function(a, b) return a.time < b.time end)
	if #list == 0 then body.Text = "Be the first to finish today!" return end
	local medals = { "🥇", "🥈", "🥉" }
	local lines = {}
	for i = 1, math.min(TOP, #list) do
		local e = list[i]
		table.insert(lines, ("%s %s  %s"):format(medals[i], best[e.userId] and best[e.userId].name or nameFor(e.userId), formatTime(e.time)))
	end
	body.Text = table.concat(lines, "\n")
end

-- new day: forget yesterday's times
local function checkDay()
	local d = today()
	if d ~= currentDay then
		currentDay = d
		best, shared = {}, {}
		return true
	end
	return false
end

-- read today's top 3 from the shared store
local pulling = false
local function pullShared()
	if pulling then return end
	pulling = true
	checkDay()
	local store = storeFor(currentDay)
	if store then
		local ok, pages = pcall(function() return store:GetSortedAsync(true, TOP) end)
		if ok and pages then
			local list = {}
			for _, item in ipairs(pages:GetCurrentPage()) do
				local userId = tonumber(item.key)
				if userId and item.value > 0 then table.insert(list, { userId = userId, time = item.value / 100 }) end
			end
			for _, e in ipairs(list) do nameFor(e.userId) end
			shared = list
		end
	end
	pulling = false
	renderBoard()
end

-- save a finish to today's shared store (keeps the player's fastest). Returns their previous best.
local function saveShared(p, t)
	local store = storeFor(currentDay)
	if not store then return nil end
	local cs = math.max(1, math.floor(t * 100 + 0.5)) -- hundredths of a second, lower is better
	local previous
	local ok = pcall(function()
		store:UpdateAsync(tostring(p.UserId), function(old)
			old = tonumber(old)
			previous = old and old / 100 or nil
			if old and old <= cs then return nil end
			return cs
		end)
	end)
	if ok then
		pcall(function() MessagingService:PublishAsync(TOPIC, currentDay) end)
	end
	return previous
end

local function backToCheckpoint(p)
	local r = root(p)
	local i = p:GetAttribute("ObbyCP")
	if not r or i == nil then return end
	if cooldown[p] and os.clock() - cooldown[p] < 0.4 then return end
	cooldown[p] = os.clock()
	local cp = checkpoints[i] or checkpoints[0]
	r.AssemblyLinearVelocity = Vector3.zero
	p.Character:PivotTo(CFrame.new(cp.Position + Vector3.new(0, cp.Size.Y / 2 + 3.2, 0)) * CFrame.Angles(0, math.rad(-90), 0))
	Remotes.ObbyAction:FireClient(p, { type = "Respawn", checkpoint = i })
end

local function endRun(p)
	p:SetAttribute("ObbyCP", nil)
	p:SetAttribute("ObbyStart", nil)
end

-- THE FLOOR IS LAVA: during a run, standing on the ground under the course (the purple play
-- floor, the hall floor, or the red lava at the start) sends you back to your last checkpoint.
-- The timer keeps running. The start pad and every platform are safe.
local FLOOR = { AtriumFloor = true, PlayFloor = true, PlayFloorEdge = true, FloorSeam = true, ShowCarpet = true, CarpetInlay = true, Lava = true }
local floorRay = RaycastParams.new()
floorRay.FilterType = Enum.RaycastFilterType.Exclude
floorRay.RespectCanCollide = false
local function onFloor(p)
	local char = p.Character
	local r = root(p)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (r and hum) or r.Position.Y > 7 then return false end
	local ignore = {}
	for _, pl in ipairs(Players:GetPlayers()) do if pl.Character then table.insert(ignore, pl.Character) end end
	floorRay.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(r.Position, Vector3.new(0, -(hum.HipHeight + r.Size.Y / 2 + 1.2), 0), floorRay)
	return hit ~= nil and FLOOR[hit.Instance.Name] == true
end

local function reachCheckpoint(p, i)
	if inMatch(p) then return end
	local current = p:GetAttribute("ObbyCP")
	if i == 0 then
		-- the start pad (re)starts the run and the timer
		if current ~= 0 then Remotes.ObbyAction:FireClient(p, { type = "Start" }) end
		p:SetAttribute("ObbyCP", 0)
		p:SetAttribute("ObbyStart", now())
		return
	end
	if current == nil or i <= current then return end
	p:SetAttribute("ObbyCP", i)
	Remotes.ObbyAction:FireClient(p, { type = "Checkpoint", checkpoint = i, total = lastCP })
end

local function finish(p)
	local started = p:GetAttribute("ObbyStart")
	if not started or p:GetAttribute("ObbyCP") == nil then return end
	-- must have come through the last checkpoint
	if p:GetAttribute("ObbyCP") < lastCP then return end
	local t = now() - started
	endRun(p)
	checkDay()
	local fx = obby.Finish:FindFirstChild("Confetti")
	if fx and fx:FindFirstChild("Celebration") then fx.Celebration:Emit(120) end
	names[p.UserId] = p.DisplayName
	local prev = best[p.UserId]
	if not prev or t < prev.time then best[p.UserId] = { name = p.DisplayName, time = t } end
	renderBoard()
	task.spawn(function()
		-- compare with the player's best from ANY server today
		local sharedPrev = saveShared(p, t)
		local earlier = sharedPrev
		if prev and (not earlier or prev.time < earlier) then earlier = prev.time end
		local dayBest = earlier and math.min(earlier, t) or t
		if p.Parent == Players then
			Remotes.ObbyAction:FireClient(p, { type = "Finish", time = t, best = dayBest, newBest = not earlier or t < earlier })
		end
		task.wait(1)
		pullShared()
	end)
end

function Obby.init(isInMatch)
	inMatch = isInMatch
	obby = workspace.ShowLobby:FindFirstChild("Obby")
	if not obby then return end
	checkpoints, lastCP = {}, 0
	for _, cp in ipairs(obby.Checkpoints:GetChildren()) do
		local i = cp:GetAttribute("Checkpoint")
		if i then
			checkpoints[i] = cp
			lastCP = math.max(lastCP, i)
			cp.Touched:Connect(function(hit)
				local p = Players:GetPlayerFromCharacter(hit.Parent)
				if p then reachCheckpoint(p, i) end
			end)
		end
	end
	for _, k in ipairs(obby.Kill:GetChildren()) do
		if k:IsA("BasePart") and not k:GetAttribute("Spinner") then
			k.Touched:Connect(function(hit)
				local p = Players:GetPlayerFromCharacter(hit.Parent)
				if not p then return end
				if p:GetAttribute("ObbyCP") ~= nil then backToCheckpoint(p)
				else
					-- wandered into the lava without starting: pop them back to the start pad
					p:SetAttribute("ObbyCP", 0); p:SetAttribute("ObbyStart", now()); backToCheckpoint(p)
				end
			end)
		end
	end
	obby.Finish.Touched:Connect(function(hit)
		local p = Players:GetPlayerFromCharacter(hit.Parent)
		if p then finish(p) end
	end)
	-- the spinning bar is animated on each client; the client reports when it hits its own player
	Remotes.ObbyAction.OnServerEvent:Connect(function(p, action)
		if action == "hit" then
			local r = root(p)
			local bar = obby.Kill:FindFirstChild("SpinnerBar")
			if r and bar and (r.Position - bar.Position).Magnitude < 12 and p:GetAttribute("ObbyCP") ~= nil then backToCheckpoint(p) end
		elseif action == "quit" then
			endRun(p)
		end
	end)
	-- falling off a high stage sends you back to your checkpoint (typical obby rules);
	-- walking out of the obby area on the ground ends the run
	task.spawn(function()
		while true do
			task.wait(0.2)
			for _, p in ipairs(Players:GetPlayers()) do
				local i = p:GetAttribute("ObbyCP")
				local r = root(p)
				if i ~= nil and r then
					if inMatch(p) then endRun(p)
					elseif inBounds(r.Position) then
						local cp = checkpoints[i]
						if cp and i > 0 and r.Position.Y < cp.Position.Y - 6 then backToCheckpoint(p)
						elseif onFloor(p) then backToCheckpoint(p) end
					elseif r.Position.Y < 6 then
						endRun(p)
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p) cooldown[p] = nil end)
	renderBoard()
	-- other servers announce new times; re-read the shared board right away
	pcall(function()
		MessagingService:SubscribeAsync(TOPIC, function() task.spawn(pullShared) end)
	end)
	-- and re-read regularly (also handles the midnight reset)
	task.spawn(function()
		while true do
			pullShared()
			task.wait(20)
		end
	end)
end

return Obby
