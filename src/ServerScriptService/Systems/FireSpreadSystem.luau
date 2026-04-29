local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PlayerState = require(script.Parent.PlayerState)
local InfectionSystem = require(script.Parent.InfectionSystem)

local FireSpreadSystem = {}

local WALL_FADE_OUT = 1.5

local active = false
local currentStage = 0
local lastTrailPos: { [Player]: Vector3 } = {}
local igniteConnections: { [Player]: { RBXScriptConnection } } = {}
local ignitedEmitters: { [BasePart]: { ParticleEmitter } } = {}
local hazardFolder: Folder? = nil

local IGNITE_FACES = {
	Enum.NormalId.Top,
	Enum.NormalId.Bottom,
	Enum.NormalId.Front,
	Enum.NormalId.Back,
	Enum.NormalId.Left,
	Enum.NormalId.Right,
}

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

local function footPosition(root: BasePart): Vector3
	return Vector3.new(root.Position.X, root.Position.Y - 2.5, root.Position.Z)
end

local function buildWallParticles(parent: BasePart)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "WallFlame"
	emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 90)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 130, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 20, 0)),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.6),
		NumberSequenceKeypoint.new(0.5, 1.1),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.7, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.9, 1.6)
	emitter.Rate = 80
	emitter.Speed = NumberRange.new(0.5, 1.4)
	emitter.SpreadAngle = Vector2.new(20, 20)
	emitter.Acceleration = Vector3.new(0, 4, 0)
	emitter.LightEmission = 0.6
	emitter.LightInfluence = 0
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-30, 30)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Parent = parent
end

local function spawnWallSegment(fromPos: Vector3, toPos: Vector3)
	local diff = toPos - fromPos
	local horizontal = Vector3.new(diff.X, 0, diff.Z)
	local length = horizontal.Magnitude
	if length < 0.05 then return end

	local height = Constants.TRAIL_WALL_HEIGHT
	local thickness = Constants.TRAIL_WALL_THICKNESS

	local baseY = math.min(fromPos.Y, toPos.Y)
	local mid = Vector3.new((fromPos.X + toPos.X) * 0.5, baseY + height * 0.5, (fromPos.Z + toPos.Z) * 0.5)
	local cf = CFrame.lookAt(mid, mid + horizontal)

	local part = Instance.new("Part")
	part.Name = "TrailWall"
	part.Size = Vector3.new(thickness, height, length)
	part.CFrame = cf
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 110, 20)
	part.Transparency = 0.35
	part.Parent = getOrCreateHazardFolder()

	buildWallParticles(part)

	InfectionSystem.registerHazard(part, Constants.TRAIL_RADIUS)

	task.delay(Constants.TRAIL_DURATION, function()
		InfectionSystem.unregisterHazard(part)
		if not part.Parent then return end
		for _, child in part:GetChildren() do
			if child:IsA("ParticleEmitter") then
				child.Enabled = false
			end
		end
		task.delay(WALL_FADE_OUT, function()
			if part.Parent then
				part:Destroy()
			end
		end)
	end)
end

local function primeTrailFor(player: Player)
	local root = getRoot(player)
	if root then
		lastTrailPos[player] = footPosition(root)
	end
end

local function primeTrailForAllBurners()
	for _, player in PlayerState.getAllInState(Constants.STATE_BURNING) do
		primeTrailFor(player)
	end
end

local function buildFaceEmitter(face: Enum.NormalId, rate: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "BurnFlames_" .. face.Name
	emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 90)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 130, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 20, 0)),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.),
		NumberSequenceKeypoint.new(0.4, 4),
		NumberSequenceKeypoint.new(1, 6),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.0),
		NumberSequenceKeypoint.new(0.3, 0.15),
		NumberSequenceKeypoint.new(0.75, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})

	emitter.Lifetime = NumberRange.new(1.0, 1.5)
	emitter.Speed = NumberRange.new(4, 8)
	emitter.SpreadAngle = Vector2.new(40, 40)
	emitter.Acceleration = Vector3.new(0, 7, 0)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-50, 50)
	emitter.EmissionDirection = face
	emitter.Rate = rate
	-- Push the billboard toward the camera so it doesn't z-fight with the face
	-- it's spawning on (otherwise head-on viewers see nothing).
	emitter.ZOffset = 0.5
	return emitter
end

local function igniteTouchedPart(hit: BasePart)
	if not hit.Parent then return end
	local flag = hit:FindFirstChild(Constants.FIREPROOF_FLAG_NAME)
	if flag and flag:IsA("BoolValue") and flag.Value then return end
	if Players:GetPlayerFromCharacter(hit.Parent) then return end
	if ignitedEmitters[hit] then return end -- already burning

	-- Per-face rate scales with that face's area so each side gets proportional flame coverage.
	local s = hit.Size
	local rateXZ = math.clamp(s.X * s.Z * 6, 25, 180)
	local rateXY = math.clamp(s.X * s.Y * 6, 25, 180)
	local rateYZ = math.clamp(s.Y * s.Z * 6, 25, 180)

	local emitters: { ParticleEmitter } = {}
	for _, face in IGNITE_FACES do
		local rate
		if face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
			rate = rateXZ
		elseif face == Enum.NormalId.Front or face == Enum.NormalId.Back then
			rate = rateXY
		else
			rate = rateYZ
		end
		local emitter = buildFaceEmitter(face, rate)
		emitter.Parent = hit
		table.insert(emitters, emitter)
	end

	InfectionSystem.registerHazard(hit, Constants.IGNITE_RADIUS)
	ignitedEmitters[hit] = emitters
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

	for _, burner in PlayerState.getAllInState(Constants.STATE_BURNING) do
		local root = getRoot(burner)
		if not root then continue end

		local foot = footPosition(root)
		local last = lastTrailPos[burner]
		if not last then
			lastTrailPos[burner] = foot
			continue
		end

		local moved = (foot - last).Magnitude
		if moved >= Constants.TRAIL_SEGMENT_MIN_LENGTH then
			-- Skip emitting on a teleport / huge frame jump, but still resync the anchor.
			if moved <= Constants.TRAIL_SEGMENT_MAX_LENGTH then
				spawnWallSegment(last, foot)
			end
			lastTrailPos[burner] = foot
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
		primeTrailForAllBurners()
	elseif stage < 2 and previous >= 2 then
		table.clear(lastTrailPos)
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
	table.clear(lastTrailPos)
end

function FireSpreadSystem.stop()
	active = false
	currentStage = 0
	table.clear(lastTrailPos)
	detachAllIgnite()
	clearHazardFolder()
	for part, emitters in ignitedEmitters do
		InfectionSystem.unregisterHazard(part)
		for _, emitter in emitters do
			if emitter and emitter.Parent then
				emitter:Destroy()
			end
		end
	end
	table.clear(ignitedEmitters)
end

local function onStateChanged(player: Player, _oldState: string?, newState: string)
	if not active then return end
	if newState == Constants.STATE_BURNING then
		if currentStage >= 2 then
			primeTrailFor(player)
		end
		if currentStage >= 3 then
			attachIgnite(player)
		end
	else
		detachIgnite(player)
		lastTrailPos[player] = nil
	end
end

function FireSpreadSystem.init()
	RunService.Heartbeat:Connect(step)

	PlayerState.StateChanged:Connect(onStateChanged)

	Players.PlayerRemoving:Connect(function(player)
		detachIgnite(player)
		lastTrailPos[player] = nil
	end)
end

return FireSpreadSystem
