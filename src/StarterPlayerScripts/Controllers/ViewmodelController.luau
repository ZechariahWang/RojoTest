--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
type EquipState = {
	viewmodel: Model,
	weaponDef: any,
	weaponModel: Model?,
	weaponMotor: Motor6D?,
	muzzle: Instance,
	hiddenServerEmitter: ParticleEmitter?, -- the local burner's torso flame, hidden while we own the screen
	savedFOV: number,
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

local function ensureFallbackMuzzle(rightArm: BasePart, weaponDef: any): Attachment
	local existing = rightArm:FindFirstChild(weaponDef.muzzleAttachmentName)
	if existing and existing:IsA("Attachment") then
		return existing
	end
	local att = Instance.new("Attachment")
	att.Name = weaponDef.muzzleAttachmentName
	att.CFrame = weaponDef.muzzleFallbackOffset or CFrame.new(0, -1.5, 0)
	att.Parent = rightArm
	return att
end

local function equipWeapon(viewmodel: Model, weaponDef: any): (Model?, Motor6D?, Instance)
	local rightArm = viewmodel:FindFirstChild("RightArm") :: BasePart?
	if not rightArm then
		error("ViewmodelController: viewmodel is missing RightArm")
	end

	local weaponsFolder = ReplicatedStorage:FindFirstChild("Weapons")
	local template = weaponsFolder and weaponsFolder:FindFirstChild(weaponDef.modelName)

	if not template or not template:IsA("Model") then
		-- Fallback: no weapon model authored yet. Just attach a muzzle to RightArm.
		return nil, nil, ensureFallbackMuzzle(rightArm, weaponDef)
	end

	local weaponModel = template:Clone()
	local primary = weaponModel.PrimaryPart or weaponModel:FindFirstChildWhichIsA("BasePart")
	if not primary then
		weaponModel:Destroy()
		return nil, nil, ensureFallbackMuzzle(rightArm, weaponDef)
	end
	weaponModel.PrimaryPart = primary

	for _, descendant in ipairs(weaponModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end

	local motor = Instance.new("Motor6D")
	motor.Name = "WeaponGrip"
	motor.Part0 = rightArm
	motor.Part1 = primary
	motor.C0 = weaponDef.rightHandGrip or CFrame.new()
	motor.Parent = rightArm

	weaponModel.Parent = viewmodel

	local muzzle: Instance? = primary:FindFirstChild(weaponDef.muzzleAttachmentName)
	if not muzzle then
		muzzle = weaponModel:FindFirstChild(weaponDef.muzzleAttachmentName, true)
	end
	if not muzzle then
		muzzle = ensureFallbackMuzzle(rightArm, weaponDef)
	end

	return weaponModel, motor, muzzle :: Instance
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
	if s.weaponMotor and s.weaponMotor.Parent then
		s.weaponMotor:Destroy()
	end
	if s.weaponModel and s.weaponModel.Parent then
		s.weaponModel:Destroy()
	end
	if s.viewmodel and s.viewmodel.Parent then
		s.viewmodel:Destroy()
	end

	if s.hiddenServerEmitter and s.hiddenServerEmitter.Parent then
		s.hiddenServerEmitter.Enabled = true
	end

	if camera then
		camera.FieldOfView = s.savedFOV
	end
end

local function getViewmodelTemplate(): Model?
	local folder = ReplicatedStorage:FindFirstChild("ViewModels")
	if not folder then
		warn("ViewmodelController: ReplicatedStorage.ViewModels is missing")
		return nil
	end
	local template = folder:FindFirstChild("Viewmodel")
	if not template or not template:IsA("Model") then
		warn("ViewmodelController: ReplicatedStorage.ViewModels.Viewmodel is missing or not a Model")
		return nil
	end
	return template
end

local function attach()
	if equipped then return end

	local template = getViewmodelTemplate()
	if not template then return end

	local viewmodel = template:Clone()

	local hrp = viewmodel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		warn("ViewmodelController: viewmodel has no HumanoidRootPart")
		viewmodel:Destroy()
		return
	end
	viewmodel.PrimaryPart = hrp

	-- Viewmodel is decorative-only: must not collide, raycast, or fight physics.
	for _, descendant in ipairs(viewmodel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
	hrp.Anchored = true

	viewmodel.Parent = camera

	local weaponDef = Weapons[currentWeaponName] or Weapons[Constants.VIEWMODEL_DEFAULT_WEAPON]
	if not weaponDef then
		warn("ViewmodelController: no weapon registered named " .. tostring(currentWeaponName))
		viewmodel:Destroy()
		return
	end

	local weaponModel, weaponMotor, muzzle = equipWeapon(viewmodel, weaponDef)

	-- Hide the local burner's third-person torso flame so it doesn't clip the camera
	-- while we own the first-person view. We keep the ref to re-enable on detach.
	local hiddenEmitter: ParticleEmitter? = findLocalTorsoEmitter()
	if hiddenEmitter then
		hiddenEmitter.Enabled = false
	end

	local savedFOV = camera.FieldOfView
	camera.FieldOfView = Constants.VIEWMODEL_FOV

	equipped = {
		viewmodel = viewmodel,
		weaponDef = weaponDef,
		weaponModel = weaponModel,
		weaponMotor = weaponMotor,
		muzzle = muzzle,
		hiddenServerEmitter = hiddenEmitter,
		savedFOV = savedFOV,
		swayCF = CFrame.new(),
		bobOffset = CFrame.new(),
		lastCameraCF = camera.CFrame,
		projectile = nil,
	}

	RunService:BindToRenderStep(STEP_KEY, Enum.RenderPriority.Character.Value + 1, function(dt: number)
		local e = equipped
		if not e then return end
		if not e.viewmodel.Parent then return end

		-- Sway: respond to camera angular velocity for a tiny weight feel.
		local rot = camera.CFrame:ToObjectSpace(e.lastCameraCF)
		local rx, ry, _ = rot:ToOrientation()
		local targetSway = CFrame.Angles(
			math.sin(rx) * Constants.VIEWMODEL_SWAY_AMOUNT,
			math.sin(ry) * Constants.VIEWMODEL_SWAY_AMOUNT,
			0
		)
		e.swayCF = e.swayCF:Lerp(targetSway, Constants.VIEWMODEL_SWAY_LERP)
		e.lastCameraCF = camera.CFrame

		-- Bob: tied to humanoid movement. Half-frequency on Y so the figure-8 reads correctly.
		local char = localPlayer.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local moving = hum and hum.MoveDirection.Magnitude > 0
		local targetBob: CFrame
		if moving then
			local t = os.clock() * Constants.VIEWMODEL_BOB_FREQ
			targetBob = CFrame.new(
				math.cos(t) * Constants.VIEWMODEL_BOB_X_AMP,
				math.abs(math.sin(t)) * -Constants.VIEWMODEL_BOB_Y_AMP,
				0
			)
		else
			targetBob = CFrame.new()
		end
		e.bobOffset = e.bobOffset:Lerp(targetBob, Constants.VIEWMODEL_BOB_LERP)

		hrp.CFrame = camera.CFrame * e.swayCF * e.bobOffset

		-- The server torso emitter is recreated on every fire-start, so the ref we
		-- captured during attach() can go stale. Re-find and silence it whenever
		-- it reappears so it never clips the camera in first-person.
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

local function onFireStateChanged(active: boolean)
	if not equipped then return end
	if active then
		if equipped.projectile then return end
		local projectile = Projectiles[equipped.weaponDef.projectileName]
		if not projectile then
			warn("ViewmodelController: no projectile named " .. tostring(equipped.weaponDef.projectileName))
			return
		end
		equipped.projectile = projectile.start(equipped.muzzle)
	else
		if equipped.projectile then
			equipped.projectile:stop()
			equipped.projectile = nil
		end
	end
end

function ViewmodelController.setWeapon(name: string)
	if currentWeaponName == name then return end
	currentWeaponName = name
	if equipped then
		detach()
		reconcile()
	end
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

	-- Detach cleanly on respawn so the next attach starts fresh.
	localPlayer.CharacterRemoving:Connect(function()
		if equipped then detach() end
	end)
end

return ViewmodelController
