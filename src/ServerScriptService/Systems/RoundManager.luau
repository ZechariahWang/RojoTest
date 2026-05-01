local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PlayerState = require(script.Parent.PlayerState)
local InfectionSystem = require(script.Parent.InfectionSystem)
local FireAttackSystem = require(script.Parent.FireAttackSystem)
local FireSpreadSystem = require(script.Parent.FireSpreadSystem)
local AbilitySystem = require(script.Parent.AbilitySystem)
local MapManager = require(script.Parent.MapManager)

local RoundManager = {}

local currentPhase = Constants.PHASE_LOBBY
local currentPhaseEndClock = 0
local currentPhaseExtra: any = nil
local currentStage = 0
local RoundStateRemote: RemoteEvent
local KillFeedRemote: RemoteEvent

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

local function applyOutline(player: Player, on: boolean)
	local char = player.Character
	if not char then return end

	local existing = char:FindFirstChild("BurnOutline")
	if existing then
		existing:Destroy()
	end

	if not on then return end

	local highlight = Instance.new("Highlight")
	highlight.Name = "BurnOutline"
	highlight.FillColor = Color3.fromRGB(255, 130, 0)
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(255, 130, 0)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Adornee = char
	highlight.Parent = char
end

local function setBurning(player: Player, withGrace: boolean)
	PlayerState.set(player, Constants.STATE_BURNING)
	InfectionSystem.markBurner(player, withGrace)
	setWalkSpeed(player, Constants.BURNING_WALKSPEED)
	applyOutline(player, true)
end

local function setSafe(player: Player)
	PlayerState.set(player, Constants.STATE_SAFE)
	setWalkSpeed(player, Constants.SAFE_WALKSPEED)
	applyFire(player, false)
	applyOutline(player, false)
end

local function setLobby(player: Player)
	PlayerState.set(player, Constants.STATE_LOBBY)
	setWalkSpeed(player, Constants.SAFE_WALKSPEED)
	applyFire(player, false)
	applyOutline(player, false)
end

local function pickRandom(list: { Player }): Player?
	if #list == 0 then return nil end
	return list[math.random(1, #list)]
end

local function healAllPlayers()
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if not char then continue end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health = hum.MaxHealth
		end
	end
end

local function endRound(reason: string, winners: { string })
	FireAttackSystem.stop()
	InfectionSystem.stop()
	FireSpreadSystem.stop()
	AbilitySystem.stop()
	currentStage = 0

	healAllPlayers()

	for _, player in Players:GetPlayers() do
		if player.Character then
			applyFire(player, false)
		end
		setLobby(player)
		MapManager.teleportToLobby(player)
	end

	MapManager.unloadMap()

	broadcastPhase(Constants.PHASE_END, Constants.END_TIME, {
		winners = winners,
		reason = reason,
	})

	task.wait(Constants.END_TIME)
end

local function broadcastRoundStage(stage: number, remaining: number)
	broadcastPhase(Constants.PHASE_ROUND, remaining, { stage = stage })
end

local function survivorNames(): { string }
	local names: { string } = {}
	for _, p in PlayerState.getAllInState(Constants.STATE_SAFE) do
		table.insert(names, p.Name)
	end
	return names
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
	if not initialBurner then
		broadcastPhase(Constants.PHASE_LOBBY)
		return
	end
	setBurning(initialBurner, false)

	-- Role reveal phase: clients animate the per-player role UI. No damage, no
	-- abilities. Burner already has fire + outline so they appear ignited
	-- when the animation settles.
	broadcastPhase(Constants.PHASE_ROLE_REVEAL, Constants.ROLE_REVEAL_TIME, {
		burner = initialBurner.Name,
	})
	task.wait(Constants.ROLE_REVEAL_TIME)

	-- Reveal phase: positioning countdown. Damage and abilities still off.
	broadcastPhase(Constants.PHASE_REVEAL, Constants.REVEAL_TIME, {
		burner = initialBurner.Name,
	})
	task.wait(Constants.REVEAL_TIME)

	local burningStill = PlayerState.countInState(Constants.STATE_BURNING)
	local safeStill = PlayerState.countInState(Constants.STATE_SAFE)
	if safeStill + burningStill < Constants.MIN_PLAYERS then
		endRound(Constants.REASON_ABORTED, {})
		return
	end

	InfectionSystem.start()
	FireSpreadSystem.start()
	FireAttackSystem.start()
	AbilitySystem.start()

	local roundStart = os.clock()
	local roundEnd = roundStart + Constants.ROUND_TIME

	currentStage = 1
	broadcastRoundStage(1, Constants.ROUND_TIME)

	while os.clock() < roundEnd do
		task.wait(0.25)

		local elapsed = os.clock() - roundStart
		local nextStage = math.min(Constants.STAGE_COUNT, math.floor(elapsed / Constants.STAGE_DURATION) + 1)
		if nextStage ~= currentStage then
			currentStage = nextStage
			FireSpreadSystem.setStage(currentStage)
			broadcastRoundStage(currentStage, math.max(0, roundEnd - os.clock()))
		end

		local safeCount = PlayerState.countInState(Constants.STATE_SAFE)
		local burningCount = PlayerState.countInState(Constants.STATE_BURNING)

		if safeCount + burningCount < Constants.MIN_PLAYERS then
			endRound(Constants.REASON_ABORTED, {})
			return
		end

		if safeCount == 0 then
			endRound(Constants.REASON_ALL_INFECTED, {})
			return
		end
	end

	-- Time up — every safe player is a winner.
	local winners = survivorNames()
	if #winners > 0 then
		endRound(Constants.REASON_SURVIVED, winners)
	else
		endRound(Constants.REASON_ALL_INFECTED, {})
	end
end

local function gameLoop()
	while true do
		broadcastPhase(Constants.PHASE_LOBBY)

		while PlayerState.countInState(Constants.STATE_LOBBY) < Constants.MIN_PLAYERS do
			task.wait(1)
		end

		local mapLoaded = MapManager.loadRandomMap()
		if not mapLoaded then
			warn("RoundManager: yo add the maps back to server storage")
			task.wait(5)
			continue
		end

		broadcastPhase(Constants.PHASE_INTERMISSION, Constants.INTERMISSION_TIME)
		task.wait(Constants.INTERMISSION_TIME)

		if PlayerState.countInState(Constants.STATE_LOBBY) < Constants.MIN_PLAYERS then
			MapManager.unloadMap()
			continue
		end

		runRound()
	end
end

local function onPlayerInfected(safe: Player, by: any)
	if currentPhase ~= Constants.PHASE_ROUND then return end

	local killerName: string? = nil
	if typeof(by) == "Instance" and by:IsA("Player") then
		killerName = by.Name
	end
	KillFeedRemote:FireAllClients(killerName, safe.Name)

	setBurning(safe, true)
end

local function onCharacterAdded(player: Player, char: Model)
	char:WaitForChild("HumanoidRootPart", 5)

	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.BreakJointsOnDeath = false
	end

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
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

	local existingKillFeed = Remotes:FindFirstChild("KillFeed")
	if existingKillFeed and existingKillFeed:IsA("RemoteEvent") then
		KillFeedRemote = existingKillFeed
	else
		KillFeedRemote = Instance.new("RemoteEvent")
		KillFeedRemote.Name = "KillFeed"
		KillFeedRemote.Parent = Remotes
	end

	InfectionSystem.PlayerInfected:Connect(onPlayerInfected)

	Players.PlayerAdded:Connect(bindPlayer)
	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end

	task.spawn(gameLoop)
end

return RoundManager
