local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local CombatFeedbackController = {}
local localPlayer = Players.LocalPlayer

-- need to update these later, i dont have the sounds rn
local SOUND_IDS = {
	hitConfirm = "",     -- short tick when burner lands a damage tick on a victim
	sizzleLoop = "",     -- looping crackle while local player is taking damage
	grunt75 = "",        -- HP crossed below 75%
	grunt50 = "",        -- HP crossed below 50%
	grunt25 = "",        -- HP crossed below 25%
	killWhoosh = "",     -- victim was just converted by the local player
	convertImpact = "",  -- local player was just converted
}

local screenGui: ScreenGui
local vignette: Frame
local crosshair: Frame
local damageNumberTemplate: BillboardGui

local sizzleSound: Sound

local lastDamageTakenAt = -math.huge
local sizzlePlaying = false
local SIZZLE_GRACE = 0.18 

local lastKnownHP = math.huge
local HP_THRESHOLDS = { { hp = 75, key = "grunt75" }, { hp = 50, key = "grunt50" }, { hp = 25, key = "grunt25" } }

local shakeIntensity = 0
local SHAKE_DECAY = 5.0

local function initHUD()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	screenGui = playerGui:WaitForChild("Game") :: ScreenGui
	vignette = screenGui:WaitForChild("Vignette") :: Frame
	crosshair = screenGui:WaitForChild("Crosshair") :: Frame
	damageNumberTemplate = ReplicatedStorage:FindFirstChild("Assets"):FindFirstChild("UI"):WaitForChild("DamageNumber") :: BillboardGui
end

local function playSound(id: string, volume: number?)
	if id == "" then return end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 1
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	-- Cleanup if Ended never fires (e.g., bad ID)
	task.delay(5, function()
		if sound and sound.Parent then sound:Destroy() end
	end)
end

local function pulseVignette(intensity: number)
	-- intensity 0..1. Higher = darker, faster.
	local target = math.clamp(0.85 - intensity * 0.55, 0.3, 0.85)
	TweenService:Create(
		vignette,
		TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = target }
	):Play()
	task.delay(0.1, function()
		TweenService:Create(
			vignette,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		):Play()
	end)
end

local CROSSHAIR_IDLE_SIZE = UDim2.fromOffset(10, 10)
local CROSSHAIR_FIRING_SIZE = UDim2.fromOffset(22, 22)
local CROSSHAIR_IDLE_COLOR = Color3.fromRGB(255, 200, 140)
local CROSSHAIR_FIRING_COLOR = Color3.fromRGB(255, 80, 30)
local CROSSHAIR_IDLE_TRANSPARENCY = 0.5
local CROSSHAIR_FIRING_TRANSPARENCY = 0
local CROSSHAIR_TWEEN_TIME = 0.12

local isBurner = false
local isFiring = false

local function applyCrosshairFiring(firing: boolean)
	if not crosshair then return end
	TweenService:Create(
		crosshair,
		TweenInfo.new(CROSSHAIR_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = if firing then CROSSHAIR_FIRING_SIZE else CROSSHAIR_IDLE_SIZE,
			BackgroundColor3 = if firing then CROSSHAIR_FIRING_COLOR else CROSSHAIR_IDLE_COLOR,
			BackgroundTransparency = if firing then CROSSHAIR_FIRING_TRANSPARENCY else CROSSHAIR_IDLE_TRANSPARENCY,
		}
	):Play()
end

local function setBurnerMode(active: boolean)
	if active then
		localPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
		UserInputService.MouseIconEnabled = false
		if crosshair then
			crosshair.Size = CROSSHAIR_IDLE_SIZE
			crosshair.BackgroundColor3 = CROSSHAIR_IDLE_COLOR
			crosshair.BackgroundTransparency = CROSSHAIR_IDLE_TRANSPARENCY
			crosshair.Visible = true
		end
	else
		localPlayer.CameraMode = Enum.CameraMode.Classic
		UserInputService.MouseIconEnabled = true
		if crosshair then
			crosshair.Visible = false
		end
		isFiring = false
	end
end


local DAMAGE_BATCH_WINDOW = 0.25
local pendingDamage: { [Player]: { total: number, expireAt: number } } = {}
local HIT_CONFIRM_THROTTLE = 0.08
local lastHitConfirmAt = -math.huge

local function colorForDamage(dmg: number): (Color3, Color3)
	if dmg >= 12 then
		return Color3.fromRGB(255, 70, 30), Color3.fromRGB(60, 0, 0)
	elseif dmg >= 5 then
		return Color3.fromRGB(255, 150, 30), Color3.fromRGB(40, 5, 0)
	else
		return Color3.fromRGB(255, 220, 90), Color3.fromRGB(40, 20, 0)
	end
end

local function spawnDamageNumber(victim: Player, dmg: number)
	local char = victim.Character
	if not char then return end
	local head = char:FindFirstChild("Head") :: BasePart?
	if not head then return end

	local gui = damageNumberTemplate:Clone()
	local hOffset = (math.random() - 0.5) * 1.6
	gui.StudsOffset = Vector3.new(hOffset, 1.2, 0)
	gui.Parent = head

	local label = gui:FindFirstChild("Label") :: TextLabel?
	if not label then
		gui:Destroy()
		return
	end

	label.Text = string.format("%d", math.ceil(dmg))
	label.TextTransparency = 0

	local fillColor, strokeColor = colorForDamage(dmg)
	label.TextColor3 = fillColor

	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = strokeColor
		stroke.Transparency = 0
	end

	local scale = label:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = label
	end
	scale.Scale = 1.5
	TweenService:Create(
		scale,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1.0 }
	):Play()

	local riseTarget = gui.StudsOffset + Vector3.new(hOffset * 0.6, 2.4, 0)
	TweenService:Create(
		gui,
		TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffset = riseTarget }
	):Play()

	task.delay(0.3, function()
		if not gui.Parent then return end
		TweenService:Create(
			label,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ TextTransparency = 1 }
		):Play()
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		end
		TweenService:Create(scale, TweenInfo.new(0.4), { Scale = 0.85 }):Play()
	end)

	task.delay(0.75, function()
		if gui and gui.Parent then gui:Destroy() end
	end)
end

local function damageNumberStep(_dt: number)
	local now = os.clock()
	for victim, entry in pendingDamage do
		if now >= entry.expireAt then
			pendingDamage[victim] = nil
			if victim.Parent then
				spawnDamageNumber(victim, entry.total)
			end
		end
	end
end

local function startSizzle()
	if sizzlePlaying or sizzleSound.SoundId == "" then return end
	sizzlePlaying = true
	sizzleSound.Volume = 0
	sizzleSound:Play()
	TweenService:Create(sizzleSound, TweenInfo.new(0.08), { Volume = 0.7 }):Play()
end

local function stopSizzle()
	if not sizzlePlaying then return end
	sizzlePlaying = false
	local tween = TweenService:Create(sizzleSound, TweenInfo.new(0.18), { Volume = 0 })
	tween:Play()
	tween.Completed:Once(function()
		if not sizzlePlaying then sizzleSound:Stop() end
	end)
end

local function checkHpThresholds(currentHP: number)
	for _, t in HP_THRESHOLDS do
		if lastKnownHP > t.hp and currentHP <= t.hp then
			playSound(SOUND_IDS[t.key], 0.9)
		end
	end
	lastKnownHP = currentHP
end

local function getLocalHumanoid(): Humanoid?
	local char = localPlayer.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function shake(intensity: number)
	shakeIntensity = math.max(shakeIntensity, intensity)
end

local function shakeStep(dt: number)
	local hum = getLocalHumanoid()
	if not hum then return end

	if shakeIntensity <= 0.001 then
		if hum.CameraOffset.Magnitude > 0.001 then
			hum.CameraOffset = Vector3.new()
		end
		return
	end

	local i = shakeIntensity
	hum.CameraOffset = Vector3.new(
		(math.random() - 0.5) * 2 * i,
		(math.random() - 0.5) * 2 * i,
		(math.random() - 0.5) * 2 * i
	)

	shakeIntensity = math.max(0, shakeIntensity - SHAKE_DECAY * dt)
end

local function sizzleStep(_dt: number)
	if (os.clock() - lastDamageTakenAt) < SIZZLE_GRACE then
		startSizzle()
	else
		stopSizzle()
	end
end

local function onDamageDealt(victim: Player, dmg: number, _victimHP: number)
	-- Only the burner who landed the hit receives this. Fires every server tick
	-- (~60Hz) while the cone connects, so we throttle and batch.
	if not victim or not victim.Parent then return end

	local now = os.clock()
	if now - lastHitConfirmAt >= HIT_CONFIRM_THROTTLE then
		playSound(SOUND_IDS.hitConfirm, 0.6)
		lastHitConfirmAt = now
	end

	local entry = pendingDamage[victim]
	if entry then
		entry.total += dmg
		entry.expireAt = now + DAMAGE_BATCH_WINDOW
	else
		pendingDamage[victim] = { total = dmg, expireAt = now + DAMAGE_BATCH_WINDOW }
	end
end

local function onDamageTaken(_attacker: Player?, dmg: number, currentHP: number)
	-- Only the victim receives this.
	lastDamageTakenAt = os.clock()
	pulseVignette(math.clamp(dmg * 0.06, 0.3, 1))
	shake(0.18)
	checkHpThresholds(currentHP)
end

local function onKillFeed(killerName: string?, victimName: string)
	if killerName == localPlayer.Name then
		playSound(SOUND_IDS.killWhoosh, 1)
		shake(0.35)
	elseif victimName == localPlayer.Name then
		pulseVignette(1)
		shake(0.5)
		playSound(SOUND_IDS.convertImpact, 1)
		lastKnownHP = math.huge
	end
end

local function onCharacterAdded(_char: Model)
	lastKnownHP = math.huge
	shakeIntensity = 0
end

function CombatFeedbackController.init()

	initHUD()
	-- Burner mode + custom crosshair are off until the local player is Burning.
	setBurnerMode(false)

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local DamageDealtRemote = Remotes:WaitForChild("DamageDealt") :: RemoteEvent
	local DamageTakenRemote = Remotes:WaitForChild("DamageTaken") :: RemoteEvent
	local KillFeedRemote = Remotes:WaitForChild("KillFeed") :: RemoteEvent
	local PlayerStateRemote = Remotes:WaitForChild("PlayerStateChanged") :: RemoteEvent

	DamageDealtRemote.OnClientEvent:Connect(onDamageDealt)
	DamageTakenRemote.OnClientEvent:Connect(onDamageTaken)
	KillFeedRemote.OnClientEvent:Connect(onKillFeed)

	PlayerStateRemote.OnClientEvent:Connect(function(player: Player, state: string)
		if player ~= localPlayer then return end
		local nowBurner = state == Constants.STATE_BURNING
		if nowBurner == isBurner then return end
		isBurner = nowBurner
		setBurnerMode(nowBurner)
	end)

	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if not isBurner then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if isFiring then return end
		isFiring = true
		applyCrosshairFiring(true)
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if not isFiring then return end
		isFiring = false
		applyCrosshairFiring(false)
	end)

	localPlayer.CharacterAdded:Connect(onCharacterAdded)
	if localPlayer.Character then
		onCharacterAdded(localPlayer.Character)
	end

	RunService.RenderStepped:Connect(function(dt)
		shakeStep(dt)
		sizzleStep(dt)
		damageNumberStep(dt)
	end)
end

return CombatFeedbackController
