--!strict
-- Rank emblems drawn from UI shapes, so they stay crisp at any size: a faceted metal gem in the
-- tier's colours, growing more ornate up the ladder (wings from Silver, a star from Gold, a
-- second facet ring from Platinum, a cut gem for Diamond, a crown for Champion), with one to
-- three chevrons underneath for the division.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rank = require(ReplicatedStorage.Shared.Rank)

local RankBadge = {}

local function shape(parent: Instance, props: { [string]: any }, colors: { Color3 }?, rotation: number?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	for k, v in props do
		(f :: any)[k] = v
	end
	if colors then
		local g = Instance.new("UIGradient")
		local keys = {}
		for i, c in colors do
			table.insert(keys, ColorSequenceKeypoint.new((i - 1) / math.max(1, #colors - 1), c))
		end
		g.Color = ColorSequence.new(keys)
		g.Rotation = rotation or 90
		g.Parent = f
	end
	f.Parent = parent
	return f
end

local function corner(f: GuiObject, scale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = f
end

local function stroke(f: GuiObject, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
end

-- Draws the emblem for a rank index (1..16) filling `parent` (keep it square). Returns the holder.
function RankBadge.draw(parent: GuiObject, index: number, zIndex: number?): Frame
	local tierIndex, division = Rank.parts(index)
	local tier = Rank.Tiers[tierIndex]
	local z = zIndex or 1
	local holder = Instance.new("Frame")
	holder.Name = "RankBadge"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = z
	holder.Parent = parent
	local px = math.max(1, math.floor(parent.AbsoluteSize.X / 40))

	local function at(x: number, y: number, w: number, h: number): { [string]: any }
		return { Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h), ZIndex = z }
	end

	-- Wings from Silver up: two swept blades behind the gem, more of them higher up.
	if tierIndex >= 2 then
		local feathers = if tierIndex >= 5 then 3 elseif tierIndex >= 3 then 2 else 1
		for side = -1, 1, 2 do
			for k = 1, feathers do
				local w = shape(holder, at(0.5 + side * (0.26 + k * 0.05), 0.46 + k * 0.05, 0.36 - k * 0.04, 0.11), { tier.glow, tier.color, tier.dark }, 0)
				w.Rotation = side * (18 + k * 16)
				w.ZIndex = z
				corner(w, 0.5)
				stroke(w, tier.dark, px)
			end
		end
	end
	-- Champion: a crown over the gem.
	if tierIndex == #Rank.Tiers then
		local gold = Color3.fromRGB(255, 214, 90)
		local goldDark = Color3.fromRGB(176, 112, 20)
		local band = shape(holder, at(0.5, 0.2, 0.42, 0.1), { Color3.fromRGB(255, 244, 190), gold, goldDark })
		corner(band, 0.25)
		stroke(band, goldDark, px)
		for i = -1, 1 do
			local spike = shape(holder, at(0.5 + i * 0.15, 0.11 - (if i == 0 then 0.04 else 0), 0.11, 0.11), { Color3.fromRGB(255, 244, 190), gold }, 45)
			spike.Rotation = 45
			stroke(spike, goldDark, px)
			local jewel = shape(holder, at(0.5 + i * 0.15, 0.05 - (if i == 0 then 0.04 else 0), 0.06, 0.06), nil)
			jewel.BackgroundColor3 = tier.glow
			jewel.ZIndex = z + 1
			corner(jewel, 0.5)
		end
	end

	-- The gem: a diamond of metal with a darker inner facet and a bright top-left highlight.
	local gemSize = if tierIndex == 5 then 0.58 else 0.54
	local outer = shape(holder, at(0.5, 0.48, gemSize, gemSize), { tier.glow, tier.color, tier.dark }, 45)
	outer.Rotation = 45
	outer.ZIndex = z + 1
	corner(outer, if tierIndex == 1 then 0.12 else 0.08)
	stroke(outer, tier.dark, px * 2)
	-- Platinum and up: a second ring of facets (a square turned the other way) for an eight-point star.
	if tierIndex >= 4 then
		local ring = shape(holder, at(0.5, 0.48, gemSize * 0.86, gemSize * 0.86), { tier.glow, tier.color, tier.dark }, 0)
		ring.ZIndex = z + 1
		corner(ring, 0.08)
		stroke(ring, tier.dark, px * 2)
	end
	local inner = shape(holder, at(0.5, 0.48, gemSize * 0.58, gemSize * 0.58), { tier.color, tier.dark }, 45)
	inner.Rotation = 45
	inner.ZIndex = z + 2
	corner(inner, 0.1)
	stroke(inner, tier.glow, px)
	-- Diamond: a cut table and facet lines across the inner gem.
	if tierIndex == 5 then
		local tableCut = shape(holder, at(0.5, 0.48, gemSize * 0.3, gemSize * 0.3), { Color3.new(1, 1, 1), tier.glow }, 45)
		tableCut.Rotation = 45
		tableCut.ZIndex = z + 3
		for _, rot in { 0, 90 } do
			local line = shape(holder, at(0.5, 0.48, gemSize * 0.78, 0.02), nil)
			line.Rotation = rot
			line.BackgroundColor3 = tier.glow
			line.BackgroundTransparency = 0.3
			line.ZIndex = z + 3
		end
	end
	-- Gold and up: a star in the middle.
	if tierIndex == 3 or tierIndex == 4 or tierIndex == 6 then
		for _, rot in { 0, 45 } do
			local star = shape(holder, at(0.5, 0.48, gemSize * 0.26, gemSize * 0.26), { Color3.new(1, 1, 1), tier.glow }, 45)
			star.Rotation = rot
			star.ZIndex = z + 3
		end
	end
	-- Shine on the upper left of the gem.
	local shine = shape(holder, at(0.4, 0.36, gemSize * 0.16, gemSize * 0.08), nil)
	shine.Rotation = -40
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.25
	shine.ZIndex = z + 4
	corner(shine, 0.5)

	-- Division chevrons under the gem (none for Champion).
	for i = 1, division do
		local x = 0.5 + (i - (division + 1) / 2) * 0.17
		for side = -1, 1, 2 do
			local arm = shape(holder, at(x + side * 0.032, 0.88, 0.09, 0.05), { tier.glow, tier.color })
			arm.Rotation = side * -35
			arm.ZIndex = z + 1
			corner(arm, 0.5)
			stroke(arm, tier.dark, px)
		end
	end
	return holder
end

return RankBadge
