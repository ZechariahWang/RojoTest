local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PlayerState = require(script.Parent.PlayerState)
local InfectionSystem = require(script.Parent.InfectionSystem)
local MapManager = require(script.Parent.MapManager)

local RoundManager = {}

local currentPhase = Constants.PHASE_LOBBY
local currentPhaseEndClock = 0
local currentPhaseExtra: any = nil
local RoundStateRemote: RemoteEvent

local function broadcastPhase(phase: string, duration: number?, extra: any?)
	currentPhase = phase
	currentPhaseEndClock = if duration then os.clock() + duration else 0
	currentPhaseExtra = extra
	RoundStateRemote:FireAllClients(phase, duration, extra)
end

local function syncPhaseTo(player: Player)
	if not RoundStateRemote then return end
	local remaining: number? = nil
	if currentPhaseEndClock > 0 then
		remaining = math.max(0, currentPhaseEndClock - os.clock())
	end
	RoundStateRemote:FireClient(player, currentPhase, remaining, currentPhaseExtra)
end

local function setWalkSpeed(player: Player, speed: number)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = speed end
end

local function clearFire(char: Model)
	for _, descendant in char:GetDescendants() do
		if descendant.Name == "BurnFire" and descendant:IsA("Fire") then
			descendant:Destroy()
		end
	end
end

local function applyFire(player: Player, on: boolean)
	local char = player.Character
	if not char then return end

	if not on then
		clearFire(char)
		return
	end

	if char:FindFirstChild("BurnFire", true) then
		return
	end

	local target = char:FindFirstChild("UpperTorso")
		or char:FindFirstChild("Torso")
		or char:FindFirstChild("HumanoidRootPart")
	if not target then return end

	local fire = Instance.new("Fire")
	fire.Name = "BurnFire"
	fire.Heat = 10
	fire.Size = 6
	fire.Color = Color3.fromRGB(255, 130, 0)
	fire.SecondaryColor = Color3.fromRGB(255, 60, 0)
	fire.Parent = target
end

local function setBurning(player: Player, withGrace: boolean)
	PlayerState.set(player, Constants.STATE_BURNING)
	InfectionSystem.markBurner(player, withGrace)
	setWalkSpeed(player, Constants.BURNING_WALKSPEED)
	applyFire(player, true)
end

local function setSafe(player: Player)
	PlayerState.set(player, Constants.STATE_SAFE)
	setWalkSpeed(player, Constants.SAFE_WALKSPEED)
	applyFire(player, false)
end

local function setLobby(player: Player)
	PlayerState.set(player, Constants.STATE_LOBBY)
	setWalkSpeed(player, Constants.SAFE_WALKSPEED)
	applyFire(player, false)
end

local function pickRandom(list: { Player }): Player?
	if #list == 0 then return nil end
	return list[math.random(1, #list)]
end

local function endRound(reason: string, winner: Player?)
	InfectionSystem.stop()

	for _, player in Players:GetPlayers() do
		if player.Character then
			applyFire(player, false)
		end
	end

	broadcastPhase(Constants.PHASE_END, Constants.END_TIME, {
		winner = winner and winner.Name or nil,
		reason = reason,
	})

	task.wait(Constants.END_TIME)

	for _, player in Players:GetPlayers() do
		setLobby(player)
		MapManager.teleportToLobby(player)
	end

	MapManager.unloadMap()
end

local function runRound()
	local participants: { Player } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			setSafe(player)
			MapManager.teleportToArena(player)
			table.insert(participants, player)
		end
	end

	if #participants < Constants.MIN_PLAYERS then
		broadcastPhase(Constants.PHASE_LOBBY)
		return
	end

	local initialBurner = pickRandom(participants)
	if initialBurner then
		setBurning(initialBurner, false)
	end

	local roundStartSafeCount = #participants - 1

	InfectionSystem.start()
	broadcastPhase(Constants.PHASE_ROUND, Constants.ROUND_TIME)

	local roundEnd = os.clock() + Constants.ROUND_TIME

	while os.clock() < roundEnd do
		task.wait(0.25)

		local safeCount = PlayerState.countInState(Constants.STATE_SAFE)
		local burningCount = PlayerState.countInState(Constants.STATE_BURNING)

		if safeCount + burningCount < Constants.MIN_PLAYERS then
			endRound(Constants.REASON_ABORTED, nil)
			return
		end

		if safeCount == 0 then
			endRound(Constants.REASON_ALL_INFECTED, nil)
			return
		end

		if burningCount == 0 then
			local survivors = PlayerState.getAllInState(Constants.STATE_SAFE)
			endRound(Constants.REASON_SURVIVED, survivors[1])
			return
		end

		if safeCount == 1 and roundStartSafeCount > 1 then
			local survivors = PlayerState.getAllInState(Constants.STATE_SAFE)
			endRound(Constants.REASON_SURVIVED, survivors[1])
			return
		end
	end

	-- Time up
	local survivors = PlayerState.getAllInState(Constants.STATE_SAFE)
	if #survivors > 0 then
		endRound(Constants.REASON_SURVIVED, survivors[1])
	else
		endRound(Constants.REASON_ALL_INFECTED, nil)
	end
end

local function gameLoop()
	while true do
		broadcastPhase(Constants.PHASE_LOBBY)

		while PlayerState.countInState(Constants.STATE_LOBBY) < Constants.MIN_PLAYERS do
			task.wait(1)
		end

		broadcastPhase(Constants.PHASE_INTERMISSION, Constants.INTERMISSION_TIME)

		local mapLoaded = MapManager.loadRandomMap()

		task.wait(Constants.INTERMISSION_TIME)

		if not mapLoaded then
			warn("RoundManager: map load failed, returning to lobby")
			task.wait(2)
			continue
		end

		if PlayerState.countInState(Constants.STATE_LOBBY) < Constants.MIN_PLAYERS then
			MapManager.unloadMap()
			continue
		end

		runRound()
	end
end

local function onPlayerInfected(safe: Player, _by: Player)
	if currentPhase ~= Constants.PHASE_ROUND then return end
	setBurning(safe, true)
end

local function onCharacterAdded(player: Player, char: Model)
	char:WaitForChild("HumanoidRootPart", 5)

	syncPhaseTo(player)
	PlayerState.syncTo(player)

	local state = PlayerState.get(player)
	if state == Constants.STATE_BURNING then
		setBurning(player, false)
	elseif state == Constants.STATE_SAFE then
		setSafe(player)
	else
		setLobby(player)
	end

	local inActiveRound = currentPhase == Constants.PHASE_ROUND
		and (state == Constants.STATE_BURNING or state == Constants.STATE_SAFE)

	if inActiveRound and MapManager.hasMap() then
		MapManager.teleportToArena(player)
	else
		MapManager.teleportToLobby(player)
	end
end

local function bindPlayer(player: Player)
	player.CharacterAdded:Connect(function(char)
		onCharacterAdded(player, char)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

function RoundManager.init()
	RoundStateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoundStateChanged") :: RemoteEvent

	InfectionSystem.PlayerInfected:Connect(onPlayerInfected)

	Players.PlayerAdded:Connect(bindPlayer)
	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end

	task.spawn(gameLoop)
end

return RoundManager
