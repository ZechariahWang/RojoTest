local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PlayerState = require(script.Parent.PlayerState)

local FireAttackSystem = {}

type Visual = {
	attachment: Attachment,
	emitter: ParticleEmitter,
	light: PointLight,
}

type State = {
	firing: boolean,
	fuel: number,
	lastBroadcastFuel: number,
	visual: Visual?,
}

local active = false
local states: { [Player]: State } = {}

local FireRequestRemote: RemoteEvent
local FuelChangedRemote: RemoteEvent

local function ensureRemote(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function getOrCreateState(player: Player): State
	local s = states[player]
	if not s then
		s = {
			firing = false,
			fuel = Constants.FIRE_FUEL_MAX,
			lastBroadcastFuel = -1,
			visual = nil,
		}
		states[player] = s
	end
	return s
end

local function broadcastFuel(player: Player, s: State, force: boolean?)
	if not FuelChangedRemote then return end
	local atTop = s.fuel >= Constants.FIRE_FUEL_MAX - 0.001
	local atBottom = s.fuel <= 0.001
	local justSnapped = (atTop and s.lastBroadcastFuel < Constants.FIRE_FUEL_MAX - 0.001)
		or (atBottom and s.lastBroadcastFuel > 0.001)
	if not force and not justSnapped and math.abs(s.fuel - s.lastBroadcastFuel) < 0.05 then
		return
	end
	s.lastBroadcastFuel = s.fuel
	FuelChangedRemote:FireClient(player, s.fuel, Constants.FIRE_FUEL_MAX)
end

local function getCharParts(player: Player): (BasePart?, BasePart?)
	local char = player.Character
	if not char then return nil, nil end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local torso = (char:FindFirstChild("UpperTorso") :: BasePart?)
		or (char:FindFirstChild("Torso") :: BasePart?)
		or root
	return root, torso
end

local function spawnVisual(player: Player, s: State)
	if s.visual then return end
	local root, torso = getCharParts(player)
	if not torso or not root then return end

	local attachment = Instance.new("Attachment")
	attachment.Name = "FlameAttachment"
	attachment.CFrame = CFrame.new(0, 0, -2) * CFrame.Angles(-math.pi / 2, 0, 0)
	attachment.Parent = torso

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "FlamethrowerStream"
	emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 130)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 140, 30)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 20, 0)),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.0),
		NumberSequenceKeypoint.new(0.3, 2.5),
		NumberSequenceKeypoint.new(1, 4.0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.0),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	
	emitter.Lifetime = NumberRange.new(0.4, 0.6)
	emitter.Speed = NumberRange.new(35, 45)
	emitter.SpreadAngle = Vector2.new(Constants.FIRE_CONE_HALF_ANGLE, Constants.FIRE_CONE_HALF_ANGLE)
	emitter.Rate = 220
	emitter.LightEmission = 0.8
	emitter.LightInfluence = 0
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-80, 80)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Parent = attachment

	local light = Instance.new("PointLight")
	light.Name = "FlamethrowerLight"
	light.Color = Color3.fromRGB(255, 150, 40)
	light.Brightness = 2.5
	light.Range = 14
	light.Parent = attachment

	s.visual = { attachment = attachment, emitter = emitter, light = light }
end

local function destroyVisual(s: State)
	local v = s.visual
	if not v then return end
	s.visual = nil

	-- Stop emitting but let particles in flight finish so the stream tapers off.
	if v.emitter and v.emitter.Parent then
		v.emitter.Enabled = false
	end
	if v.light and v.light.Parent then
		v.light.Enabled = false
	end
	local em, at, lt = v.emitter, v.attachment, v.light
	task.delay(0.7, function()
		if em and em.Parent then em:Destroy() end
		if lt and lt.Parent then lt:Destroy() end
		if at and at.Parent then at:Destroy() end
	end)
end

local function stopFiring(player: Player, s: State)
	if not s.firing then return end
	s.firing = false
	destroyVisual(s)
end

local function tryStartFiring(player: Player)
	if not active then return end
	if PlayerState.get(player) ~= Constants.STATE_BURNING then return end
	local s = getOrCreateState(player)
	if s.firing then return end
	if s.fuel < Constants.FIRE_FUEL_MIN_TO_START then return end
	s.firing = true
	spawnVisual(player, s)
end

local function step(dt: number)
	for player, s in states do
		if s.firing then
			local root, _ = getCharParts(player)
			if not root then
				stopFiring(player, s)
				broadcastFuel(player, s)
				continue
			end

			s.fuel = math.max(0, s.fuel - dt)
			if s.fuel <= 0 then
				stopFiring(player, s)
			end
			broadcastFuel(player, s)
		else
			if s.fuel < Constants.FIRE_FUEL_MAX then
				s.fuel = math.min(Constants.FIRE_FUEL_MAX, s.fuel + Constants.FIRE_FUEL_REGEN_PER_SEC * dt)
				broadcastFuel(player, s)
			end
		end
	end
end

export type FiringInfo = {
	player: Player,
	root: BasePart,
	lookVector: Vector3,
}

function FireAttackSystem.getFiringBurners(): { FiringInfo }
	local result: { FiringInfo } = {}
	for player, s in states do
		if not s.firing then continue end
		if PlayerState.get(player) ~= Constants.STATE_BURNING then continue end
		local root, _ = getCharParts(player)
		if not root then continue end
		table.insert(result, {
			player = player,
			root = root,
			lookVector = root.CFrame.LookVector,
		})
	end
	return result
end

function FireAttackSystem.start()
	active = true
	for _, player in PlayerState.getAllInState(Constants.STATE_BURNING) do
		local s = getOrCreateState(player)
		s.fuel = Constants.FIRE_FUEL_MAX
		broadcastFuel(player, s, true)
	end
end

function FireAttackSystem.stop()
	active = false
	for player, s in states do
		stopFiring(player, s)
		s.fuel = Constants.FIRE_FUEL_MAX
		broadcastFuel(player, s, true)
	end
end

local function onStateChanged(player: Player, _oldState: string?, newState: string)
	if newState == Constants.STATE_BURNING then
		local s = getOrCreateState(player)
		s.fuel = Constants.FIRE_FUEL_MAX
		broadcastFuel(player, s, true)
	else
		local s = states[player]
		if s then
			stopFiring(player, s)
			states[player] = nil
		end
	end
end

function FireAttackSystem.init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	FireRequestRemote = ensureRemote(Remotes, "FireRequest")
	FuelChangedRemote = ensureRemote(Remotes, "FuelChanged")

	FireRequestRemote.OnServerEvent:Connect(function(player, activeArg)
		if typeof(activeArg) ~= "boolean" then return end
		if activeArg then
			tryStartFiring(player)
		else
			local s = states[player]
			if s then stopFiring(player, s) end
		end
	end)

	PlayerState.StateChanged:Connect(onStateChanged)

	Players.PlayerRemoving:Connect(function(player)
		local s = states[player]
		if s then
			stopFiring(player, s)
			states[player] = nil
		end
	end)

	RunService.Heartbeat:Connect(step)
end

return FireAttackSystem
