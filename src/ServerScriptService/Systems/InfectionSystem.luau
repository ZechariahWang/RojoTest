local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PlayerState = require(script.Parent.PlayerState)

local InfectionSystem = {}

local active = false
local progress: { [Player]: number } = {}
local burnerGrace: { [Player]: number } = {}

local InfectionProgressRemote: RemoteEvent
local infectedEvent = Instance.new("BindableEvent")
InfectionSystem.PlayerInfected = infectedEvent.Event

local function isAlive(player: Player): boolean
	local char = player.Character
	if not char then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
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

	local radius = Constants.INFECTION_RADIUS

	for _, safe in safes do
		local safeRoot = getRoot(safe)
		if not safeRoot then continue end

		local exposingBurner: Player? = nil
		for _, burner in burners do
			local burnerRoot = getRoot(burner)
			if burnerRoot and (burnerRoot.Position - safeRoot.Position).Magnitude <= radius then
				exposingBurner = burner
				break
			end
		end

		local current = progress[safe] or 0
		if exposingBurner then
			current += dt / Constants.INFECTION_TIME
			if current >= 1 then
				progress[safe] = nil
				InfectionProgressRemote:FireClient(safe, 0)
				infectedEvent:Fire(safe, exposingBurner)
				continue
			end
		else
			current -= dt * Constants.INFECTION_DECAY_RATE / Constants.INFECTION_TIME
			if current < 0 then current = 0 end
		end

		progress[safe] = current
		InfectionProgressRemote:FireClient(safe, math.clamp(current, 0, 1))
	end
end

function InfectionSystem.markBurner(player: Player, withGrace: boolean)
	if withGrace then
		burnerGrace[player] = os.clock() + Constants.NEW_BURNER_GRACE
	else
		burnerGrace[player] = nil
	end
end

function InfectionSystem.start()
	active = true
	table.clear(progress)
	table.clear(burnerGrace)
end

function InfectionSystem.stop()
	active = false
	for player in progress do
		if player.Parent then
			InfectionProgressRemote:FireClient(player, 0)
		end
	end
	table.clear(progress)
	table.clear(burnerGrace)
end

function InfectionSystem.init()
	InfectionProgressRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("InfectionProgress") :: RemoteEvent

	RunService.Heartbeat:Connect(step)

	Players.PlayerRemoving:Connect(function(player)
		progress[player] = nil
		burnerGrace[player] = nil
	end)
end

return InfectionSystem
