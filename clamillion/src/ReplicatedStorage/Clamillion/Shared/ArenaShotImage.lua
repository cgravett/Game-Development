-- Turns an arena's stored still shot (Shared.ArenaShots.<Theme>, captured in Studio from above
-- the crowd) into an EditableImage the shop can show. One image per arena, made once and reused.
-- Published games need Game Settings > Security > "Allow Mesh / Image APIs" turned on; if images
-- aren't allowed (or the device is out of image memory) get() returns nil and the shop falls back
-- to the arena's emoji.
local AssetService = game:GetService("AssetService")
local Shots = script.Parent:WaitForChild("ArenaShots")

local ArenaShotImage = {}
local cache = {}

local DEC = {}
do
	local A = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 1, 64 do DEC[string.byte(A, i)] = i - 1 end
end

local function decode(s)
	local n = #s
	local pad = s:sub(-2) == "==" and 2 or (s:sub(-1) == "=" and 1 or 0)
	local len = n // 4 * 3 - pad
	local out = buffer.create(len)
	local o = 0
	for i = 1, n, 4 do
		local a, b, c, d = string.byte(s, i, i + 3)
		local v = DEC[a] * 262144 + DEC[b] * 4096 + (DEC[c] or 0) * 64 + (DEC[d] or 0)
		buffer.writeu8(out, o, bit32.rshift(v, 16))
		if o + 1 < len then buffer.writeu8(out, o + 1, bit32.band(bit32.rshift(v, 8), 255)) end
		if o + 2 < len then buffer.writeu8(out, o + 2, bit32.band(v, 255)) end
		o += 3
	end
	return out
end

function ArenaShotImage.get(theme)
	theme = theme or "Classic"
	local hit = cache[theme]
	if hit ~= nil then return hit or nil end
	local mod = Shots:FindFirstChild(theme)
	local ok, img = pcall(function()
		if not mod then return nil end
		local data = require(mod)
		local pal, px = decode(data.pal), decode(data.px)
		local count = data.w * data.h
		local rgba = buffer.create(count * 4)
		for i = 0, count - 1 do
			local p = buffer.readu8(px, i) * 3
			local o = i * 4
			buffer.writeu8(rgba, o, buffer.readu8(pal, p))
			buffer.writeu8(rgba, o + 1, buffer.readu8(pal, p + 1))
			buffer.writeu8(rgba, o + 2, buffer.readu8(pal, p + 2))
			buffer.writeu8(rgba, o + 3, 255)
		end
		local image = AssetService:CreateEditableImage({ Size = Vector2.new(data.w, data.h) })
		if not image then return nil end
		image:WritePixelsBuffer(Vector2.zero, image.Size, rgba)
		return image
	end)
	cache[theme] = (ok and img) or false
	return cache[theme] or nil
end

return ArenaShotImage
