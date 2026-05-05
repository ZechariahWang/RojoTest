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

-- Read the grip CFrame and motor name from the third-person rig's Right-Arm motor.
-- This lets the user author the grip in Studio (via the rig's pre-rigged weapon)
-- and have it pick up automatically. Falls back to identity + "Weapon" if missing.
local function extractTPGrip(weaponName: string): (CFrame, string)
	local rigsFolder = ReplicatedStorage:FindFirstChild("ThirdPersonRigs")
	if not rigsFolder then return CFrame.new(), "Weapon" end
	local rig = rigsFolder:FindFirstChild(weaponName)
	if not rig or not rig:IsA("Model") then return CFrame.new(), "Weapon" end
	local rightArm = rig:FindFirstChild("Right Arm")
	if not rightArm then return CFrame.new(), "Weapon" end
	for _, m in ipairs(rig:GetDescendants()) do
		if m:IsA("Motor6D") and m.Part0 == rightArm and m.Part1 then
			return m.C0, m.Name
		end
	end
	return CFrame.new(), "Weapon"
end

-- Attach / detach the third-person weapon model on the burner's character.
-- Server-side so the welded weapon replicates to every observer. The animation
-- system targets the Motor6D by name (extracted from ThirdPersonRigs.<Name>),
-- so the weapon follows the player's right arm via the TP fire/idle animations.
local function applyTPWeapon(player: Player, on: boolean)
	local char = player.Character
	if not char then return end

	local existing = char:FindFirstChild("EquippedWeapon")
	if existing then existing:Destroy() end
	local rightArm = char:FindFirstChild("Right Arm")
	if rightArm then
		for _, c in ipairs(rightArm:GetChildren()) do
			if c:IsA("Motor6D") and c.Part1 == nil then
				c:Destroy()
			end
		end
	end

	if not on then return end
	if not rightArm then return end

	local weaponName = Constants.VIEWMODEL_DEFAULT_WEAPON
	local weaponsFolder = ReplicatedStorage:FindFirstChild("Weapons")
	if not weaponsFolder then return end
	local template = weaponsFolder:FindFirstChild(weaponName)
	if not template or not template:IsA("Model") then return end

	local clone = template:Clone()
	clone.Name = "EquippedWeapon"
	local primary: BasePart? = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
	if not primary then
		clone:Destroy()
		return
	end
	clone.PrimaryPart = primary

	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end

	local grip, motorName = extractTPGrip(weaponName)

	local motor = Instance.new("Motor6D")
	motor.Name = motorName
	motor.Part0 = rightArm
	motor.Part1 = primary
	motor.C0 = grip
	motor.Parent = rightArm

	clone.Parent = char
end

-- withCosmetics gates both the outline AND the third-person welded weapon —
-- the two visuals that would identify the burner to other players. Defaults
-- true; the initial burner passes false during role-reveal so neither shows
-- up until the role-reveal UI fades out.
local function setBurning(player: Player, withGrace: boolean, withCosmetics: boolean?)
	PlayerState.set(player, Constants.STATE_BURNING)
	InfectionSystem.markBurner(player, withGrace)
	setWalkSpeed(player, Constants.BURNING_WALKSPEED)
	if withCosmetics ~= false then
		applyOutline(player, true)
		applyTPWeapon(player, true)
	end
end

local function setSafe(player: Player)
	PlayerState.set(player, Constants.STATE_SAFE)
	setWalkSpeed(player, Constants.SAFE_WALKSPEED)
	applyFire(player, false)
	applyOutline(player, false)
	applyTPWeapon(player, false)
end

local function setLobby(player: Player)
	PlayerState.set(player, Constants.STATE_LOBBY)
	setWalkSpeed(player, Constants.SAFE_WALKSPEED)
	applyFire(player, false)
	applyOutline(player, false)
	applyTPWeapon(player, false)
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
	-- Disable damage / abilities / tagging immediately. Clients gate fire+dash
	-- on currentPhase being PHASE_ROUND, so broadcasting PHASE_END below also
	-- shuts down the local viewmodel stream, burner first-person, etc.
	FireAttackSystem.stop()
	InfectionSystem.stop()
	FireSpreadSystem.stop()
	AbilitySystem.stop()

	for _, player in Players:GetPlayers() do
		applyTPWeapon(player, false)
	end
	
	currentStage = 0

	-- Belt-and-suspenders invincibility for the freeze window in case any
	-- in-flight damage tick lands after the systems stopped.
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char and not char:FindFirstChild("RoundEndForceField") then
			local ff = Instance.new("ForceField")
			ff.Name = "RoundEndForceField"
			ff.Visible = false
			ff.Parent = char
		end
	end

	-- Broadcast END now (with the full freeze + lobby duration) so clients
	-- transition out of round-mode visuals while players remain in the arena.
	broadcastPhase(Constants.PHASE_END, Constants.END_DELAY_TIME + Constants.END_TIME, {
		winners = winners,
		reason = reason,
	})

	task.wait(Constants.END_DELAY_TIME)

	healAllPlayers()

	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char then
			applyFire(player, false)
			local ff = char:FindFirstChild("RoundEndForceField")
			if ff then ff:Destroy() end
		end
		setLobby(player)
		MapManager.teleportToLobby(player)
	end

	MapManager.unloadMap()

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
	-- Initial burner: no outline / no welded weapon yet — both would identify
	-- the burner during the role-reveal animation and spoil the suspense.
	-- Cosmetics are added once the role-reveal window closes.
	setBurning(initialBurner, false, false)

	broadcastPhase(Constants.PHASE_ROLE_REVEAL, Constants.ROLE_REVEAL_TIME, {
		burner = initialBurner.Name,
	})
	task.wait(Constants.ROLE_REVEAL_TIME)

	-- Role-reveal UI is gone now — show the visuals that reveal the burner.
	applyOutline(initialBurner, true)
	applyTPWeapon(initialBurner, true)

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
