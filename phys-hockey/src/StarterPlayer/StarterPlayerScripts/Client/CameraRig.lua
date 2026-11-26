--!strict
-- Scriptable oblique overhead camera. The tracking anchor follows the local skater only, leads
-- the skater's velocity, and is clamped to the rink. Shake is only for impact cues and can be
-- turned off in settings.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local CameraRig = {}

local HEIGHT = 52 -- a little higher than before so the stick and puck read clearly around the skater
local BACK = 42
local baseFov = 48 -- set from Settings
local LOOK_AHEAD = 12
local LEAD_SECONDS = 0.22
local followRate = 6 -- set from Settings
local CLAMP_X = Config.Arena.Length / 2 - 10 -- loose: the camera stays over your skater, even along the boards
local CLAMP_Z = Config.Arena.Width / 2 - 6

local anchor = Vector3.zero
local leadVel = Vector3.zero
local flipBlend = 1
-- The E flip runs a fixed time (a setting, 0 = instant) along an ease in and out.
local flipFrom, flipTo, flipAge = 1, 1, math.huge
local flipTime = 0.3
local fov = baseFov
local shake = 0
local shakeEnabled = true
local orbit = 0
-- Mouse wheel / D-pad zoom: scales the camera height and distance together.
local ZOOM_MIN, ZOOM_MAX = 0.6, 1.6
local ZOOM_STEP = 0.1
local zoomTarget = 1
local zoom = 1

local smooth = true
-- The match rink keeps the camera over its ice; the pond's open lake lets it go anywhere.
local clamped = true

function CameraRig.setClamped(on: boolean)
	clamped = on
end

function CameraRig.setZoomStep(step: number)
	ZOOM_STEP = step
end

-- Camera height, distance behind the skater and look-ahead (Settings, Camera).
function CameraRig.setFrame(height: number, back: number, ahead: number)
	HEIGHT, BACK, LOOK_AHEAD = height, back, ahead
end

-- Smoothing off: the camera sits exactly over the skater every frame.
function CameraRig.setSmooth(on: boolean)
	smooth = on
end

function CameraRig.zoomBy(steps: number): number
	zoomTarget = math.clamp(zoomTarget + steps * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	return zoomTarget
end

function CameraRig.setZoom(z: number)
	zoomTarget = math.clamp(z, ZOOM_MIN, ZOOM_MAX)
end

function CameraRig.setFov(value: number)
	baseFov = value
end

function CameraRig.setFlipTime(seconds: number)
	flipTime = math.max(0, seconds)
end

function CameraRig.setFollow(rate: number)
	followRate = rate
end

function CameraRig.zoom(): number
	return zoomTarget
end

function CameraRig.setShakeEnabled(on: boolean)
	shakeEnabled = on
end

function CameraRig.kick(amount: number)
	if shakeEnabled then
		shake = math.min(1.4, shake + amount)
	end
end

-- screenForward is +1 when team 1's attacking direction is up the screen, -1 for team 2.
function CameraRig.follow(camera: Camera, dt: number, focus: Vector3, velocity: Vector3, _puck: Vector3, screenForward: number)
	camera.CameraType = Enum.CameraType.Scriptable
	-- The camera stays on your own skater; it never drifts toward the puck. The look-ahead eases
	-- with the skater's velocity, so a bump, a dash or a sharp turn glides the view across
	-- instead of jerking it.
	leadVel = leadVel:Lerp(Vector3.new(velocity.X, 0, velocity.Z), 1 - math.exp(-3.5 * dt))
	velocity = leadVel
	local target = focus + velocity * LEAD_SECONDS
	if clamped then
		target = Vector3.new(math.clamp(target.X, -CLAMP_X, CLAMP_X), 0, math.clamp(target.Z, -CLAMP_Z, CLAMP_Z))
	else
		target = Vector3.new(target.X, 0, target.Z)
	end
	anchor = if smooth then anchor:Lerp(target, 1 - math.exp(-followRate * dt)) else target
	if screenForward ~= flipTo then
		flipFrom, flipTo, flipAge = flipBlend, screenForward, 0
	end
	flipAge += dt
	local u = if flipTime <= 0 then 1 else math.clamp(flipAge / flipTime, 0, 1)
	flipBlend = flipFrom + (flipTo - flipFrom) * (u * u * (3 - 2 * u))

	local wantedFov = baseFov + math.min(1, velocity.Magnitude / Config.Skater.MaxSpeed) * 4
	fov += (wantedFov - fov) * (1 - math.exp(-3 * dt))
	camera.FieldOfView = fov

	local offset = Vector3.new(0, 0, 0)
	if shake > 0.001 then
		local t = os.clock() * 42
		offset = Vector3.new(math.sin(t), math.sin(t * 1.3) * 0.6, math.cos(t * 0.9)) * shake
		shake *= math.exp(-7 * dt)
	end
	zoom += (zoomTarget - zoom) * (1 - math.exp(-10 * dt))
	local side = if flipBlend >= 0 then 1 else -1
	local back = BACK * zoom * (if math.abs(flipBlend) < 0.05 then 0.05 * side else flipBlend)
	local look = anchor + Vector3.new(flipBlend * LOOK_AHEAD, 0, 0)
	camera.CFrame = CFrame.lookAt(anchor + Vector3.new(-back, HEIGHT * zoom, 0) + offset, look + offset * 0.5)
end

-- Smoothly eases to a fixed shot (lobby, podium). snap jumps straight there.
local fixedCFrame: CFrame? = nil
function CameraRig.fixed(camera: Camera, dt: number, target: CFrame, fieldOfView: number, snap: boolean?)
	camera.CameraType = Enum.CameraType.Scriptable
	if snap or not fixedCFrame then
		fixedCFrame = target
	else
		fixedCFrame = (fixedCFrame :: CFrame):Lerp(target, 1 - math.exp(-5 * dt))
	end
	camera.FieldOfView += (fieldOfView - camera.FieldOfView) * (1 - math.exp(-5 * dt))
	camera.CFrame = fixedCFrame :: CFrame
end

function CameraRig.releaseFixed()
	fixedCFrame = nil
end

-- Slow orbit behind the main menu, with the live attract match in view.
function CameraRig.orbit(camera: Camera, dt: number)
	camera.CameraType = Enum.CameraType.Scriptable
	orbit += dt * 0.06
	camera.FieldOfView = 55
	local pos = Vector3.new(math.cos(orbit) * 96, 64, math.sin(orbit) * 62)
	camera.CFrame = CFrame.lookAt(pos, Vector3.zero)
	anchor = Vector3.zero
end

return CameraRig
