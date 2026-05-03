--!strict
-- First-person flamethrower muzzle effect. Tuned shorter and closer than the
-- server-side third-person stream in FireAttackSystem.spawnVisual so it reads
-- well clipped to the camera.

local Flame = {}

Flame.name = "Flame"

export type Handle = { stop: (self: Handle) -> () }

local function buildEmitter(): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "FlameMuzzleStream"
	emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 130)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 140, 30)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 20, 0)),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.4, 1.6),
		NumberSequenceKeypoint.new(1, 2.4),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.0),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.25, 0.4)
	emitter.Speed = NumberRange.new(28, 38)
	emitter.SpreadAngle = Vector2.new(8, 8)
	emitter.Rate = 240
	emitter.LightEmission = 0.9
	emitter.LightInfluence = 0
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-80, 80)
	emitter.EmissionDirection = Enum.NormalId.Top
	return emitter
end

function Flame.start(muzzle: Instance): Handle
	local emitter = buildEmitter()
	emitter.Parent = muzzle

	local light = Instance.new("PointLight")
	light.Name = "FlameMuzzleLight"
	light.Color = Color3.fromRGB(255, 150, 40)
	light.Brightness = 1.8
	light.Range = 8
	light.Parent = muzzle

	local handle = {} :: Handle
	function handle:stop()
		emitter.Enabled = false
		light.Enabled = false
		task.delay(0.5, function()
			if emitter.Parent then emitter:Destroy() end
			if light.Parent then light:Destroy() end
		end)
	end
	return handle
end

return Flame
