local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PlayerState = require(script.Parent.PlayerState)

local InfectionSystem = {}

local active = false
local burnerGrace: { [Player]: number } = {}
local hazards: { [BasePart]: { radius: number } } = {}

local infectedEvent = Instance.new("BindableEvent")
InfectionSystem.PlayerInfected = infectedEvent.Event

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

local function step(dt: number)
	if not active then return end

	local now = os.clock()
	local burners: { Player } = {}
	local safes: { Player } = {}

	for _, player in Players:GetPlayers() do
		if not isAlive(player) then continue end
		local state = PlayerState.get(player)
		if state == Constants.STATE_BURNING then
			local graceEnd = burnerGrace[player]
			if not graceEnd or now >= graceEnd then
				table.insert(burners, player)
			end
		elseif state == Constants.STATE_SAFE then
			table.insert(safes, player)
		end
	end

	for _, safe in safes do
		local safeRoot = getRoot(safe)
		if not safeRoot then continue end
		local hum = getHumanoid(safe)
		if not hum then continue end

		local rate = 0
		local source: any = nil

		for _, burner in burners do
			local burnerRoot = getRoot(burner)
			if burnerRoot and (burnerRoot.Position - safeRoot.Position).Magnitude <= Constants.INFECTION_RADIUS then
				rate = Constants.BURNER_DAMAGE_PER_SEC
				source = burner
				break
			end
		end

		if rate == 0 then
			for part, info in hazards do
				if part.Parent and (part.Position - safeRoot.Position).Magnitude <= info.radius then
					rate = Constants.HAZARD_DAMAGE_PER_SEC
					source = part
					break
				end
			end
		end

		if rate > 0 then
			local newHealth = hum.Health - rate * dt
			if newHealth <= 0 then
				hum.Health = hum.MaxHealth
				infectedEvent:Fire(safe, source)
			else
				hum.Health = newHealth
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
	RunService.Heartbeat:Connect(step)

	Players.PlayerRemoving:Connect(function(player)
		burnerGrace[player] = nil
	end)
end

return InfectionSystem
