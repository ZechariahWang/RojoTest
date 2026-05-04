--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Projectiles = require(ReplicatedStorage.Shared.Projectiles)
local RoleRevealController = require(script.Parent.RoleRevealController)
local FireAttackController = require(script.Parent.FireAttackController)

local ViewmodelController = {}

local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local STEP_KEY = "ViewmodelController_Step"

type ProjectileHandle = { stop: (any) -> () }

type TrackSet = {
	idle: AnimationTrack?,
	equip: AnimationTrack?,
	deEquip: AnimationTrack?,
	fire: AnimationTrack?,
	emptyFire: AnimationTrack?,
	reload: AnimationTrack?,
	emptyReload: AnimationTrack?,
	inspect: AnimationTrack?,
}

type EquipState = {
	settings: any,

	-- Viewmodel lives in Workspace.CurrentCamera (client-only, doesn't replicate)
	-- so it picks up real PBR lighting, shadows, sun, atmosphere — same as any
	-- world part. Raycast pullback in step() prevents wall clipping.
	viewmodel: Model,
	muzzle: Instance,
	rayParams: RaycastParams,

	-- Animation state.
	fpTracks: TrackSet,
	tpTracks: TrackSet,

	clonedSounds: { [string]: Sound },

	-- Other.
	hiddenServerEmitter: ParticleEmitter?,
	swayCF: CFrame,
	bobOffset: CFrame,
	lastCameraCF: CFrame,
	projectile: ProjectileHandle?,
}

local equipped: EquipState? = nil
local isBurner = false
local currentPhase: string = Constants.PHASE_LOBBY
local revealBlocking = false
local currentWeaponName: string = Constants.VIEWMODEL_DEFAULT_WEAPON

local function shouldBeActive(): boolean
	if not isBurner then return false end
	if revealBlocking then return false end
	return currentPhase == Constants.PHASE_REVEAL or currentPhase == Constants.PHASE_ROUND
end

local function findLocalTorsoEmitter(): ParticleEmitter?
	local char = localPlayer.Character
	if not char then return nil end
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	if not torso then return nil end
	local attachment = torso:FindFirstChild("FlameAttachment")
	if not attachment then return nil end
	return attachment:FindFirstChild("FlamethrowerStream") :: ParticleEmitter?
end

local function disablePhysicsFlags(p: BasePart)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	-- Viewmodel sits inches from the camera; if it cast shadows, the player
	-- would see their gun's silhouette across the world.
	p.CastShadow = false
end

local function ensureFallbackMuzzle(rightArm: BasePart, settings: any): Attachment
	local existing = rightArm:FindFirstChild(settings.muzzleAttachmentName or "Muzzle")
	if existing and existing:IsA("Attachment") then
		return existing
	end
	local att = Instance.new("Attachment")
	att.Name = settings.muzzleAttachmentName or "Muzzle"
	att.CFrame = settings.muzzleFallbackOffset or CFrame.new(0, -1.5, 0)
	att.Parent = rightArm
	return att
end

-- Settings resolution: Studio Modules folder first, then Rojo Shared/Weapons fallback.
local function resolveSettings(name: string): any?
	local studioModules = ReplicatedStorage:FindFirstChild("Modules")
	if studioModules then
		local m = studioModules:FindFirstChild(name)
		if m and m:IsA("ModuleScript") then
			local ok, result = pcall(require, m)
			if ok and type(result) == "table" then
				return result
			end
		end
	end
	return Weapons[name]
end

-- Viewmodel resolution: per-weapon rig first, then legacy generic Viewmodel.
local function resolveViewmodel(name: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("ViewModels")
	if not folder then
		warn("ViewmodelController: ReplicatedStorage.ViewModels folder is missing")
		return nil
	end
	local perWeapon = folder:FindFirstChild(name)
	if perWeapon and perWeapon:IsA("Model") then return perWeapon end
	local legacy = folder:FindFirstChild("Viewmodel")
	if legacy and legacy:IsA("Model") then return legacy end
	return nil
end

local function loadTrack(
	animator: Animator?,
	animId: string?,
	looped: boolean?,
	priority: Enum.AnimationPriority?
): AnimationTrack?
	if not animator or not animId or animId == "" then return nil end
	local a = Instance.new("Animation")
	a.AnimationId = animId
	local ok, track = pcall(function() return animator:LoadAnimation(a) end)
	if not ok or not track then
		warn("ViewmodelController: failed to load animation " .. tostring(animId))
		return nil
	end
	if looped ~= nil then track.Looped = looped end
	if priority then track.Priority = priority end
	return track
end

local function buildFPTracks(animator: Animator?, settings: any): TrackSet
	local continuous = settings.fireMode == "Continuous"
	return {
		idle = loadTrack(animator, settings.idleAnim, true, Enum.AnimationPriority.Idle),
		equip = loadTrack(animator, settings.equipAnim, false, Enum.AnimationPriority.Action),
		deEquip = loadTrack(animator, settings.deEquipAnim, false, Enum.AnimationPriority.Action),
		fire = loadTrack(animator, settings.fireAnim, continuous, Enum.AnimationPriority.Action2),
		emptyFire = loadTrack(animator, settings.emptyFireAnim, continuous, Enum.AnimationPriority.Action2),
		reload = loadTrack(animator, settings.reloadAnim, false, Enum.AnimationPriority.Action),
		emptyReload = loadTrack(animator, settings.emptyReloadAnim, false, Enum.AnimationPriority.Action),
		inspect = loadTrack(animator, settings.inspectAnim, false, Enum.AnimationPriority.Action),
	}
end

local function buildTPTracks(animator: Animator?, settings: any): TrackSet
	local continuous = settings.fireMode == "Continuous"
	return {
		idle = loadTrack(animator, settings.TPIdleAnim, true, Enum.AnimationPriority.Action),
		equip = loadTrack(animator, settings.TPEquipAnim, false, Enum.AnimationPriority.Action2),
		deEquip = nil,
		fire = loadTrack(animator, settings.TPFireAnim, continuous, Enum.AnimationPriority.Action3),
		emptyFire = nil,
		reload = loadTrack(animator, settings.TPReloadAnim, false, Enum.AnimationPriority.Action2),
		emptyReload = nil,
		inspect = nil,
	}
end

local function stopAllTracks(tracks: TrackSet, fade: number?)
	local f = fade or 0.1
	for _, track in pairs(tracks :: any) do
		if typeof(track) == "Instance" and (track :: any).IsPlaying then
			(track :: AnimationTrack):Stop(f)
		end
	end
end

local SOUND_SLOTS = { "fire", "equip", "deEquip", "reload", "emptyReload", "inspect" }

local function cloneSounds(settings: any, parent: Instance): { [string]: Sound }
	local out: { [string]: Sound } = {}
	for _, slot in ipairs(SOUND_SLOTS) do
		local src = settings[slot .. "Sound"]
		if src and typeof(src) == "Instance" and src:IsA("Sound") then
			local s = src:Clone()
			s.Name = slot .. "Sound"
			s.Parent = parent
			out[slot] = s
		end
	end
	return out
end

local function destroySounds(sounds: { [string]: Sound })
	for _, s in pairs(sounds) do
		if s.Parent then s:Destroy() end
	end
end

local function detach()
	if not equipped then return end
	local s = equipped
	equipped = nil

	pcall(function()
		RunService:UnbindFromRenderStep(STEP_KEY)
	end)

	if s.projectile then
		s.projectile:stop()
	end

	stopAllTracks(s.tpTracks, 0.1)
	stopAllTracks(s.fpTracks, 0.05)

	destroySounds(s.clonedSounds)

	if s.viewmodel and s.viewmodel.Parent then
		s.viewmodel:Destroy()
	end

	if s.hiddenServerEmitter and s.hiddenServerEmitter.Parent then
		s.hiddenServerEmitter.Enabled = true
	end
end

local function getCharacterAnimator(): (Model?, Animator?, BasePart?)
	local char = localPlayer.Character
	if not char then return nil, nil, nil end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return char, nil, nil end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
	return char, animator, torso :: BasePart?
end

local function attach()
	if equipped then return end

	local settings = resolveSettings(currentWeaponName)
	if not settings then
		warn("ViewmodelController: no settings module for " .. tostring(currentWeaponName))
		return
	end

	local template = resolveViewmodel(currentWeaponName)
	if not template then return end

	local viewmodel = template:Clone()
	local hrp = viewmodel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		warn("ViewmodelController: viewmodel has no HumanoidRootPart")
		viewmodel:Destroy()
		return
	end
	viewmodel.PrimaryPart = hrp

	for _, descendant in ipairs(viewmodel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if descendant == hrp then
				descendant.Anchored = true
			else
				descendant.Anchored = false
			end
			disablePhysicsFlags(descendant)
		end
	end

	viewmodel.Parent = Workspace.CurrentCamera

	local animController = viewmodel:FindFirstChildOfClass("AnimationController")
	local fpAnimator: Animator? = if animController then animController:FindFirstChildOfClass("Animator") else nil
	local fpTracks = buildFPTracks(fpAnimator, settings)

	local _char, tpAnimator, torso = getCharacterAnimator()
	local tpTracks: TrackSet = if tpAnimator then buildTPTracks(tpAnimator, settings) else ({} :: any)
	local clonedSounds = if torso then cloneSounds(settings, torso) else {}

	-- Muzzle: search the entire rig for the named attachment, fall back to RightArm.
	local muzzle: Instance? = viewmodel:FindFirstChild(settings.muzzleAttachmentName or "Muzzle", true)
	if not muzzle then
		local rightArm = viewmodel:FindFirstChild("RightArm") :: BasePart?
		if rightArm then
			muzzle = ensureFallbackMuzzle(rightArm, settings)
		end
	end
	if not muzzle then
		warn("ViewmodelController: could not resolve muzzle for " .. tostring(currentWeaponName))
		viewmodel:Destroy()
		return
	end

	local hiddenEmitter: ParticleEmitter? = findLocalTorsoEmitter()
	if hiddenEmitter then
		hiddenEmitter.Enabled = false
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true
	local localChar = localPlayer.Character
	rayParams.FilterDescendantsInstances = if localChar then { viewmodel, localChar } else { viewmodel }

	equipped = {
		settings = settings,
		viewmodel = viewmodel,
		muzzle = muzzle,
		rayParams = rayParams,
		fpTracks = fpTracks,
		tpTracks = tpTracks,
		clonedSounds = clonedSounds,
		hiddenServerEmitter = hiddenEmitter,
		swayCF = CFrame.new(),
		bobOffset = CFrame.new(),
		lastCameraCF = camera.CFrame,
		projectile = nil,
	}

	if fpTracks.equip then fpTracks.equip:Play(0.1) end
	if tpTracks.equip then tpTracks.equip:Play(0.1) end
	if clonedSounds.equip then clonedSounds.equip:Play() end
	if fpTracks.idle then fpTracks.idle:Play(0.2) end
	if tpTracks.idle then tpTracks.idle:Play(0.2) end

	RunService:BindToRenderStep(STEP_KEY, Enum.RenderPriority.Character.Value + 1, function(_dt: number)
		local e = equipped
		if not e then return end
		if not e.viewmodel.Parent then return end

		local rot = camera.CFrame:ToObjectSpace(e.lastCameraCF)
		local rx, ry, _ = rot:ToOrientation()
		local targetSway = CFrame.Angles(
			math.sin(rx) * Constants.VIEWMODEL_SWAY_AMOUNT,
			math.sin(ry) * Constants.VIEWMODEL_SWAY_AMOUNT,
			0
		)
		e.swayCF = e.swayCF:Lerp(targetSway, Constants.VIEWMODEL_SWAY_LERP)
		e.lastCameraCF = camera.CFrame

		-- Realistic bob: amplitude scales with actual horizontal speed (so walking
		-- vs sprinting vs idling all read differently), with roll + pitch on
		-- each step and a constant low-freq breathing that fades down when
		-- moving. Airborne kills the bob and lets the gun "settle" downward.
		local localChar = localPlayer.Character
		local hum = localChar and localChar:FindFirstChildOfClass("Humanoid")
		local hrp = localChar and localChar:FindFirstChild("HumanoidRootPart")

		local speedRatio = 0
		if hrp and hrp:IsA("BasePart") then
			local v = hrp.AssemblyLinearVelocity
			local hSpeed = Vector3.new(v.X, 0, v.Z).Magnitude
			speedRatio = math.clamp(hSpeed / Constants.SAFE_WALKSPEED, 0, 1.5)
		end

		local airborne = false
		if hum then
			local hState = hum:GetState()
			airborne = hState == Enum.HumanoidStateType.Freefall
				or hState == Enum.HumanoidStateType.Jumping
		end

		local now = os.clock()
		local targetBob: CFrame
		if airborne then
			targetBob = CFrame.new(0, -Constants.VIEWMODEL_AIRBORNE_DROP, 0)
		else
			local phase = now * Constants.VIEWMODEL_BOB_FREQ
			local walkX = math.cos(phase) * Constants.VIEWMODEL_BOB_X_AMP * speedRatio
			local walkY = math.abs(math.sin(phase)) * -Constants.VIEWMODEL_BOB_Y_AMP * speedRatio
			local roll = math.cos(phase) * Constants.VIEWMODEL_BOB_ROLL_RAD * speedRatio
			local pitch = math.abs(math.sin(phase)) * Constants.VIEWMODEL_BOB_PITCH_RAD * speedRatio

			-- Idle breathing fades out when walking/sprinting so the patterns don't fight.
			local breathScale = math.max(0, 1 - speedRatio * 0.8)
			local breathPhase = now * Constants.VIEWMODEL_BREATH_FREQ
			local breathY = math.sin(breathPhase) * Constants.VIEWMODEL_BREATH_AMP * breathScale
			local breathX = math.sin(breathPhase * 0.6) * Constants.VIEWMODEL_BREATH_AMP * 0.35 * breathScale

			targetBob = CFrame.new(walkX + breathX, walkY + breathY, 0)
				* CFrame.Angles(pitch, 0, roll)
		end
		e.bobOffset = e.bobOffset:Lerp(targetBob, Constants.VIEWMODEL_BOB_LERP)

		local origin = camera.CFrame.Position
		local probe = camera.CFrame.LookVector * Constants.VIEWMODEL_PULLBACK_DEPTH
		local hit = Workspace:Raycast(origin, probe, e.rayParams)
		local pullback = 0
		if hit then
			local hitDist = (hit.Position - origin).Magnitude
			pullback = (Constants.VIEWMODEL_PULLBACK_DEPTH - hitDist) + Constants.VIEWMODEL_PULLBACK_PADDING
			if pullback < 0 then pullback = 0 end
		end

		local pivot = camera.CFrame * e.swayCF * e.bobOffset * CFrame.new(0, 0, pullback)
		e.viewmodel:PivotTo(pivot)

		if not e.hiddenServerEmitter or not e.hiddenServerEmitter.Parent then
			local found = findLocalTorsoEmitter()
			if found then
				found.Enabled = false
				e.hiddenServerEmitter = found
			else
				e.hiddenServerEmitter = nil
			end
		end
	end)
end

local function reconcile()
	if shouldBeActive() then
		if not equipped then attach() end
	else
		if equipped then detach() end
	end
end

local function playFire(s: EquipState)
	local fp, tp = s.fpTracks.fire, s.tpTracks.fire
	if fp then fp:Play(0.05) end
	if tp then tp:Play(0.05) end
	if s.clonedSounds.fire then s.clonedSounds.fire:Play() end
end

local function stopFire(s: EquipState)
	if s.settings.fireMode ~= "Continuous" then return end
	if s.fpTracks.fire and s.fpTracks.fire.IsPlaying then s.fpTracks.fire:Stop(0.08) end
	if s.tpTracks.fire and s.tpTracks.fire.IsPlaying then s.tpTracks.fire:Stop(0.08) end
	if s.clonedSounds.fire and s.clonedSounds.fire.IsPlaying then s.clonedSounds.fire:Stop() end
end

local function onFireStateChanged(active: boolean)
	if not equipped then return end
	if active then
		if not equipped.projectile then
			local projectile = Projectiles[equipped.settings.projectileName]
			if projectile then
				equipped.projectile = projectile.start(equipped.muzzle)
			else
				warn("ViewmodelController: no projectile named " .. tostring(equipped.settings.projectileName))
			end
		end
		playFire(equipped)
	else
		if equipped.projectile then
			equipped.projectile:stop()
			equipped.projectile = nil
		end
		stopFire(equipped)
	end
end

local function playInspect()
	local s = equipped
	if not s then return end
	local fp = s.fpTracks.inspect

	if not fp then 
		print("no inspect animation for " .. tostring(currentWeaponName))
		return 
	end

	if fp.IsPlaying then return end
	if s.fpTracks.fire and s.fpTracks.fire.IsPlaying then return end
	if s.fpTracks.reload and s.fpTracks.reload.IsPlaying then return end

	if s.clonedSounds.inspect then s.clonedSounds.inspect:Play() end
	fp:Play(0.1)
end

function ViewmodelController.setWeapon(name: string)
	if currentWeaponName == name then return end
	currentWeaponName = name
	if equipped then
		detach()
		reconcile()
	end
end

function ViewmodelController.inspect()
	playInspect()
end

function ViewmodelController.init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local PlayerStateRemote = Remotes:WaitForChild("PlayerStateChanged") :: RemoteEvent
	local RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

	revealBlocking = RoleRevealController.isRevealActive()

	PlayerStateRemote.OnClientEvent:Connect(function(player: Player, state: string)
		if player ~= localPlayer then return end
		isBurner = (state == Constants.STATE_BURNING)
		reconcile()
	end)

	RoundStateRemote.OnClientEvent:Connect(function(phase: string)
		currentPhase = phase
		if phase == Constants.PHASE_ROLE_REVEAL then
			revealBlocking = true
		end
		reconcile()
	end)

	RoleRevealController.RevealEnded:Connect(function()
		revealBlocking = false
		reconcile()
	end)

	FireAttackController.FireStateChanged:Connect(onFireStateChanged)

	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == Enum.KeyCode.F then
			playInspect()
		end
	end)

	localPlayer.CharacterRemoving:Connect(function()
		if equipped then detach() end
	end)
	-- Re-attach for the new character (fresh Humanoid.Animator + welded weapon).
	localPlayer.CharacterAdded:Connect(function()
		reconcile()
	end)
end

return ViewmodelController
