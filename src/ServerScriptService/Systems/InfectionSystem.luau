local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PlayerState = require(script.Parent.PlayerState)
local FireAttackSystem = require(script.Parent.FireAttackSystem)

local InfectionSystem = {}

local active = false
local burnerGrace: { [Player]: number } = {}
local hazards: { [BasePart]: { radius: number } } = {}

local infectedEvent = Instance.new("BindableEvent")
InfectionSystem.PlayerInfected = infectedEvent.Event

local DamageDealtRemote: RemoteEvent
local DamageTakenRemote: RemoteEvent

local CONE_DOT_THRESHOLD = math.cos(math.rad(Constants.FIRE_CONE_HALF_ANGLE))

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

local function getHumanoid(player: Player): Humanoid?
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function isAlive(player: Player): boolean
	local hum = getHumanoid(player)
	return hum ~= nil and hum.Health > 0
end

local function getRoot(player: Player): BasePart?
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function closestPointOnPart(part: BasePart, pos: Vector3): Vector3
	local localPos = part.CFrame:PointToObjectSpace(pos)
	local half = part.Size * 0.5
	local clamped = Vector3.new(
		math.clamp(localPos.X, -half.X, half.X),
		math.clamp(localPos.Y, -half.Y, half.Y),
		math.clamp(localPos.Z, -half.Z, half.Z)
	)
	return part.CFrame:PointToWorldSpace(clamped)
end

local function inFireCone(burner: FireAttackSystem.FiringInfo, targetPos: Vector3): boolean
	local toTarget = targetPos - burner.root.Position
	local dist = toTarget.Magnitude
	if dist > Constants.FIRE_CONE_RANGE then return false end
	if dist < 0.001 then return true end -- standing on top of the burner
	local dot = burner.lookVector:Dot(toTarget.Unit)
	return dot >= CONE_DOT_THRESHOLD
end

local function step(dt: number)
	if not active then return end

	local now = os.clock()

	-- Filter firing burners to those past their grace window.
	local rawFiring = FireAttackSystem.getFiringBurners()
	local firing: { FireAttackSystem.FiringInfo } = {}
	for _, info in rawFiring do
		local graceEnd = burnerGrace[info.player]
		if graceEnd and now < graceEnd then continue end
		table.insert(firing, info)
	end

	for _, safe in Players:GetPlayers() do
		if PlayerState.get(safe) ~= Constants.STATE_SAFE then continue end
		if not isAlive(safe) then continue end

		local safeRoot = getRoot(safe)
		if not safeRoot then continue end
		local hum = getHumanoid(safe)
		if not hum then continue end

		local rate = 0
		local source: any = nil

		for _, info in firing do
			if inFireCone(info, safeRoot.Position) then
				rate = Constants.FIRE_DAMAGE_PER_SEC
				source = info.player
				break
			end
		end

		if rate == 0 then
			for part, hazardInfo in hazards do
				if part.Parent then
					local nearest = closestPointOnPart(part, safeRoot.Position)
					if (nearest - safeRoot.Position).Magnitude <= hazardInfo.radius then
						rate = Constants.HAZARD_DAMAGE_PER_SEC
						source = part
						break
					end
				end
			end
		end

		if rate > 0 then
			local dmg = rate * dt
			local newHealth = hum.Health - dmg
			if newHealth <= 0 then
				hum.Health = hum.MaxHealth
				infectedEvent:Fire(safe, source)
			else
				hum.Health = newHealth
				if typeof(source) == "Instance" and source:IsA("Player") then
					if DamageDealtRemote then
						DamageDealtRemote:FireClient(source, safe, dmg, newHealth)
					end
					if DamageTakenRemote then
						DamageTakenRemote:FireClient(safe, source, dmg, newHealth)
					end
				elseif DamageTakenRemote then
					DamageTakenRemote:FireClient(safe, nil, dmg, newHealth)
				end
			end
		end
	end
end

function InfectionSystem.markBurner(player: Player, withGrace: boolean)
	if withGrace then
		burnerGrace[player] = os.clock() + Constants.NEW_BURNER_GRACE
	else
		burnerGrace[player] = nil
	end
end

function InfectionSystem.registerHazard(part: BasePart, radius: number)
	hazards[part] = { radius = radius }
end

function InfectionSystem.unregisterHazard(part: BasePart)
	hazards[part] = nil
end

function InfectionSystem.start()
	active = true
	table.clear(burnerGrace)
	table.clear(hazards)
end

function InfectionSystem.stop()
	active = false
	table.clear(burnerGrace)
	table.clear(hazards)
end

function InfectionSystem.init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	DamageDealtRemote = ensureRemote(Remotes, "DamageDealt")
	DamageTakenRemote = ensureRemote(Remotes, "DamageTaken")

	RunService.Heartbeat:Connect(step)

	Players.PlayerRemoving:Connect(function(player)
		burnerGrace[player] = nil
	end)
end

return InfectionSystem
