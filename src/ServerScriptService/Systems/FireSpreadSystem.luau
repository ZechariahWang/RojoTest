local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PlayerState = require(script.Parent.PlayerState)
local InfectionSystem = require(script.Parent.InfectionSystem)

local FireSpreadSystem = {}

local TRAIL_FADE_OUT = 2.5

local active = false
local currentStage = 0
local lastTrailEmit: { [Player]: number } = {}
local igniteConnections: { [Player]: { RBXScriptConnection } } = {}
local ignitedFires: { [Fire]: BasePart } = {}
local trailEmitters: { [Player]: { attachment: Attachment, emitter: ParticleEmitter } } = {}
local hazardFolder: Folder? = nil

local function getOrCreateHazardFolder(): Folder
	if hazardFolder and hazardFolder.Parent then
		return hazardFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "FireHazards"
	folder.Parent = Workspace
	hazardFolder = folder
	return folder
end

local function getRoot(player: Player): BasePart?
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function spawnHazardPart(position: Vector3)
	local part = Instance.new("Part")
	part.Name = "TrailHazard"
	part.Size = Vector3.new(2, 0.2, 2)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Position = position
	part.Parent = getOrCreateHazardFolder()

	InfectionSystem.registerHazard(part, Constants.TRAIL_RADIUS)

	task.delay(Constants.TRAIL_DURATION, function()
		InfectionSystem.unregisterHazard(part)
		if part.Parent then
			part:Destroy()
		end
	end)
end

local function buildTrailEmitter(): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "TrailEmitter"
	emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 90)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 130, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 20, 0)),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.4),
		NumberSequenceKeypoint.new(0.5, 1.0),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.7, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(1.6, 2.4)
	emitter.Rate = 90
	emitter.Speed = NumberRange.new(0.4, 1.2)
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.Acceleration = Vector3.new(0, 2, 0)
	emitter.LightEmission = 0.6
	emitter.LightInfluence = 0
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-30, 30)
	emitter.LockedToPart = false
	emitter.EmissionDirection = Enum.NormalId.Top
	return emitter
end

local function attachTrailEmitter(player: Player)
	if trailEmitters[player] then return end
	local root = getRoot(player)
	if not root then return end

	local attachment = Instance.new("Attachment")
	attachment.Name = "TrailEmitterPoint"
	attachment.Position = Vector3.new(0, -2.5, 0)
	attachment.Parent = root

	local emitter = buildTrailEmitter()
	emitter.Parent = attachment

	trailEmitters[player] = { attachment = attachment, emitter = emitter }
end

local function detachTrailEmitter(player: Player)
	local entry = trailEmitters[player]
	if not entry then return end
	trailEmitters[player] = nil

	local emitter = entry.emitter
	local attachment = entry.attachment
	if emitter and emitter.Parent then
		emitter.Enabled = false
	end
	task.delay(TRAIL_FADE_OUT, function()
		if emitter and emitter.Parent then emitter:Destroy() end
		if attachment and attachment.Parent then attachment:Destroy() end
	end)
end

local function attachAllTrailEmitters()
	for _, player in PlayerState.getAllInState(Constants.STATE_BURNING) do
		attachTrailEmitter(player)
	end
end

local function detachAllTrailEmitters()
	for player in trailEmitters do
		detachTrailEmitter(player)
	end
end

local function igniteTouchedPart(hit: BasePart)
	if not hit.Parent then return end
	if hit:HasTag(Constants.TAG_FIREPROOF) then return end
	if Players:GetPlayerFromCharacter(hit.Parent) then return end
	if hit:FindFirstChild("BurnFire") then return end

	local fire = Instance.new("Fire")
	fire.Name = "BurnFire"
	fire.Heat = 8
	fire.Size = 5
	fire.Color = Color3.fromRGB(255, 130, 0)
	fire.SecondaryColor = Color3.fromRGB(255, 60, 0)
	fire.Parent = hit

	InfectionSystem.registerHazard(hit, Constants.IGNITE_RADIUS)
	ignitedFires[fire] = hit

	task.delay(Constants.IGNITE_DURATION, function()
		InfectionSystem.unregisterHazard(hit)
		ignitedFires[fire] = nil
		if fire and fire.Parent then
			fire:Destroy()
		end
	end)
end

local function attachIgnite(player: Player)
	if igniteConnections[player] then return end
	local char = player.Character
	if not char then return end

	local conns: { RBXScriptConnection } = {}
	for _, descendant in char:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(conns, descendant.Touched:Connect(igniteTouchedPart))
		end
	end
	igniteConnections[player] = conns
end

local function detachIgnite(player: Player)
	local conns = igniteConnections[player]
	if not conns then return end
	for _, conn in conns do
		conn:Disconnect()
	end
	igniteConnections[player] = nil
end

local function attachAllIgnite()
	for _, player in PlayerState.getAllInState(Constants.STATE_BURNING) do
		attachIgnite(player)
	end
end

local function detachAllIgnite()
	for player in igniteConnections do
		detachIgnite(player)
	end
end

local function step(_dt: number)
	if not active then return end
	if currentStage < 2 then return end

	local now = os.clock()
	for _, burner in PlayerState.getAllInState(Constants.STATE_BURNING) do
		local root = getRoot(burner)
		if not root then continue end

		local last = lastTrailEmit[burner] or 0
		if now - last >= Constants.TRAIL_EMIT_INTERVAL then
			lastTrailEmit[burner] = now
			local footY = root.Position.Y - 2.5
			spawnHazardPart(Vector3.new(root.Position.X, footY, root.Position.Z))
		end
	end
end

local function clearHazardFolder()
	if hazardFolder and hazardFolder.Parent then
		for _, part in hazardFolder:GetChildren() do
			if part:IsA("BasePart") then
				InfectionSystem.unregisterHazard(part)
			end
		end
		hazardFolder:Destroy()
		hazardFolder = nil
	end
end

function FireSpreadSystem.setStage(stage: number)
	local previous = currentStage
	currentStage = stage

	if stage >= 2 and previous < 2 then
		attachAllTrailEmitters()
	elseif stage < 2 and previous >= 2 then
		detachAllTrailEmitters()
	end

	if stage >= 3 and previous < 3 then
		attachAllIgnite()
	elseif stage < 3 and previous >= 3 then
		detachAllIgnite()
	end
end

function FireSpreadSystem.start()
	active = true
	currentStage = 1
	table.clear(lastTrailEmit)
end

function FireSpreadSystem.stop()
	active = false
	currentStage = 0
	table.clear(lastTrailEmit)
	detachAllIgnite()
	detachAllTrailEmitters()
	clearHazardFolder()
	for fire, part in ignitedFires do
		InfectionSystem.unregisterHazard(part)
		if fire and fire.Parent then
			fire:Destroy()
		end
	end
	table.clear(ignitedFires)
end

local function onStateChanged(player: Player, _oldState: string?, newState: string)
	if not active then return end
	if newState == Constants.STATE_BURNING then
		if currentStage >= 2 then
			attachTrailEmitter(player)
		end
		if currentStage >= 3 then
			attachIgnite(player)
		end
	else
		detachIgnite(player)
		detachTrailEmitter(player)
		lastTrailEmit[player] = nil
	end
end

function FireSpreadSystem.init()
	RunService.Heartbeat:Connect(step)

	PlayerState.StateChanged:Connect(onStateChanged)

	Players.PlayerRemoving:Connect(function(player)
		detachIgnite(player)
		detachTrailEmitter(player)
		lastTrailEmit[player] = nil
	end)
end

return FireSpreadSystem
