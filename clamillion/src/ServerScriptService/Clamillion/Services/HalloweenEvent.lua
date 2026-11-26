-- HALLOWEEN EVENT (server). Turns the event on and off from the clock (Shared.Events) and swaps
-- in the Halloween lobby while it's on.
--
-- The ORIGINAL lobby (workspace.ShowLobby) is never changed in the place file. While the event is
-- on, the running server:
--   1. re-paints the lobby in Halloween colours (it remembers every original colour), and
--   2. adds the Halloween decorations: a copy of ServerStorage.ClamillionEvents.HalloweenLobby
--      (open that model to edit the decorations; it's a normal model you can move things in).
-- When the event ends (Sunday 11:55 PM ET), every server puts the original colours back and
-- removes the decorations on its own, so the lobby is exactly as it was. Same obby, same pads,
-- same stands throughout: only the look changes.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Events = require(RS.Clamillion.Shared.Events)

local Service = {}
local ACTIVE_ATTR = Events.List.halloween.attribute
local active = nil
local painted = {} -- part -> { Color, Material }
local decor = nil

-- parts that keep their normal colours: mode pads (players read them), the obby's lava, the
-- wheel's prize slices, and the prize host
local function skip(part)
	local full = part:GetFullName()
	return full:find("%.Pads%.") ~= nil or full:find("Obby%.Kill") ~= nil or full:find("DailyWheel%.Rotor") ~= nil
		or part:FindFirstAncestor("Attendant") ~= nil or part.Transparency >= 1
end

-- the Halloween palette: reds/pinks -> pumpkin orange & witchy purple, golds -> orange,
-- greens -> slime green, blues -> purple, whites/greys -> dark violet stone, navy -> near-black
local function spooky(c, mat)
	local h, s, v = c:ToHSV()
	if mat == Enum.Material.Fabric then return Color3.fromHSV(0.78, 0.7, math.max(0.22, v * 0.75)) end -- velvet -> purple
	if s < 0.2 then
		if mat == Enum.Material.Neon then return Color3.fromHSV(0.75, 0.55, 0.42) end -- white glows -> dim moody purple
		return Color3.fromHSV(0.76, 0.25, 0.1 + v * 0.3) -- marble/ceiling/trim -> dark violet stone
	end
	if v < 0.3 then return Color3.fromHSV(0.77, 0.65, math.max(v * 0.8, 0.05)) end -- navy walls -> black-purple
	local function hue(x) return Color3.fromHSV(x, math.min(1, s * 1.05 + 0.05), v) end
	if h < 0.045 or h >= 0.96 then return hue(0.07) -- red -> orange
	elseif h < 0.19 then return hue(0.075) -- orange / gold -> pumpkin orange
	elseif h < 0.45 then return hue(0.3) -- green -> slime green
	elseif h < 0.7 then return hue(0.76) -- cyan / blue -> purple
	else return hue(0.79) end -- violet / pink / magenta -> purple
end

local function paint(on)
	local lobby = workspace:FindFirstChild("ShowLobby")
	if not lobby then return end
	if on then
		local n = 0
		for _, d in ipairs(lobby:GetDescendants()) do
			if d:IsA("BasePart") and not painted[d] and not skip(d) then
				painted[d] = { d.Color, d.Material }
				d.Color = spooky(d.Color, d.Material)
				n += 1
				if n % 400 == 0 then task.wait() end
			end
			-- lights in the lobby glow orange / purple
			if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				if not painted[d] then painted[d] = { d.Color } ; d.Color = spooky(d.Color, Enum.Material.Neon) end
			end
		end
	else
		for inst, old in pairs(painted) do
			if inst.Parent then
				inst.Color = old[1]
				if old[2] then inst.Material = old[2] end
			end
		end
		table.clear(painted)
	end
end

local function setDecor(on)
	if on then
		if decor and decor.Parent then return end
		local folder = ServerStorage:FindFirstChild("ClamillionEvents")
		local template = folder and folder:FindFirstChild("HalloweenLobby")
		if not template then warn("[Clamillion] HalloweenLobby decorations are missing from ServerStorage.ClamillionEvents"); return end
		decor = template:Clone()
		decor.Name = "HalloweenLobbyDecor"
		decor.Parent = workspace
	elseif decor then
		decor:Destroy()
		decor = nil
	end
end

-- Halloween slides on the lobby ad boards (put first so they come round often)
local SLIDES = {
	{ tag = "EVENT!", icon = "🎃", title = "Halloween Event!", body = "FREE spooky arena, podium & broom emote at the Rewards stand!", colors = { Color3.fromRGB(255, 120, 20), Color3.fromRGB(90, 25, 140) } },
	{ tag = "EVENT!", icon = "🧙", title = "Halloween Hero Title", body = "Play 5 minutes during Halloween to claim it. Ends Sunday!", colors = { Color3.fromRGB(110, 40, 190), Color3.fromRGB(255, 120, 20) } },
}
local function setSlides(on)
	local ok, ads = pcall(require, script.Parent.Parent:FindFirstChild("LobbyAds"))
	if not ok or type(ads) ~= "table" or type(ads.Slides) ~= "table" then return end
	for i = #ads.Slides, 1, -1 do if ads.Slides[i].halloween then table.remove(ads.Slides, i) end end
	if on then
		for i = #SLIDES, 1, -1 do
			local s = table.clone(SLIDES[i]); s.halloween = true
			table.insert(ads.Slides, 1, s)
		end
	end
end

local function apply(on)
	if on == active then return end
	active = on
	RS.Clamillion:SetAttribute(ACTIVE_ATTR, on)
	print("[Clamillion] Halloween event " .. (on and "ON: Halloween lobby is live" or "OFF: original lobby"))
	setSlides(on)
	setDecor(on)
	paint(on)
end

function Service.init()
	RS.Clamillion:SetAttribute(ACTIVE_ATTR, false)
	apply(Events.computeActive("halloween"))
	-- check the clock every second, so every server switches right on time
	task.spawn(function()
		while true do
			task.wait(1)
			apply(Events.computeActive("halloween"))
		end
	end)
end

return Service
