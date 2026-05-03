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
	-- ViewportFrame layer (renders the arms on top of the world, no clipping).
	screenGui: ScreenGui,
	viewportFrame: ViewportFrame,
	viewportCamera: Camera,
	worldModel: WorldModel,

	viewmodel: Model,
	weaponDef: any,
	weaponModel: Model?,

	-- The muzzle inside the viewport (visual position). ParticleEmitters can't
	-- render in a ViewportFrame, so we mirror this CFrame onto a workspace
	-- tracker each frame, and the projectile spawns on the tracker.
	internalMuzzle: Instance,
	muzzleTracker: BasePart,
	trackerMuzzle: Attachment,

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

local function lockPart(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
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

-- Position weapon model relative to the right arm (rigid offset preserved by
-- viewmodel:PivotTo each frame). Returns the internal muzzle reference.
local function equipWeapon(viewmodel: Model, weaponDef: any): (Model?, Instance)
	local rightArm = viewmodel:FindFirstChild("RightArm") :: BasePart?
	if not rightArm then
		error("ViewmodelController: viewmodel is missing RightArm")
	end

	local weaponsFolder = ReplicatedStorage:FindFirstChild("Weapons")
	local template = weaponsFolder and weaponsFolder:FindFirstChild(weaponDef.modelName)

	if not template or not template:IsA("Model") then
		return nil, ensureFallbackMuzzle(rightArm, weaponDef)
	end

	local weaponModel = template:Clone()
	local primary = weaponModel.PrimaryPart or weaponModel:FindFirstChildWhichIsA("BasePart")
	if not primary then
		weaponModel:Destroy()
		return nil, ensureFallbackMuzzle(rightArm, weaponDef)
	end
	weaponModel.PrimaryPart = primary

	for _, descendant in ipairs(weaponModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			lockPart(descendant)
		end
	end

	weaponModel.Parent = viewmodel
	weaponModel:PivotTo(rightArm.CFrame * (weaponDef.rightHandGrip or CFrame.new()))

	local muzzle: Instance? = primary:FindFirstChild(weaponDef.muzzleAttachmentName)
	if not muzzle then
		muzzle = weaponModel:FindFirstChild(weaponDef.muzzleAttachmentName, true)
	end
	if not muzzle then
		muzzle = ensureFallbackMuzzle(rightArm, weaponDef)
	end

	return weaponModel, muzzle :: Instance
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
	if s.muzzleTracker and s.muzzleTracker.Parent then
		s.muzzleTracker:Destroy()
	end
	if s.screenGui and s.screenGui.Parent then
		s.screenGui:Destroy() -- destroys ViewportFrame, WorldModel, Viewmodel, weapon
	end

	if s.hiddenServerEmitter and s.hiddenServerEmitter.Parent then
		s.hiddenServerEmitter.Enabled = true
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

local function buildViewportLayer(): (ScreenGui, ViewportFrame, WorldModel, Camera)
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ViewmodelLayer"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	-- Drawn behind the HUD (which sits at default DisplayOrder = 0) so the
	-- crosshair, fuel meter, etc. overlay the arms.
	screenGui.DisplayOrder = -1
	screenGui.Parent = localPlayer:WaitForChild("PlayerGui")

	local viewportFrame = Instance.new("ViewportFrame")
	viewportFrame.Name = "Viewport"
	viewportFrame.Size = UDim2.fromScale(1, 1)
	viewportFrame.BackgroundTransparency = 1
	viewportFrame.LightColor = Color3.fromRGB(255, 240, 230)
	viewportFrame.LightDirection = Vector3.new(-1, -2, 1)
	viewportFrame.Ambient = Color3.fromRGB(140, 140, 140)
	viewportFrame.Parent = screenGui

	-- WorldModel inherits from WorldRoot, so motors / animations work inside
	-- (we anchor everything in v1, but this keeps the door open for animation).
	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "ViewmodelWorld"
	worldModel.Parent = viewportFrame

	local viewportCamera = Instance.new("Camera")
	viewportCamera.Name = "ViewmodelCamera"
	viewportCamera.FieldOfView = Constants.VIEWMODEL_FOV
	viewportCamera.Parent = viewportFrame
	viewportFrame.CurrentCamera = viewportCamera

	return screenGui, viewportFrame, worldModel, viewportCamera
end

local function attach()
	if equipped then return end

	local template = getViewmodelTemplate()
	if not template then return end

	local weaponDef = Weapons[currentWeaponName] or Weapons[Constants.VIEWMODEL_DEFAULT_WEAPON]
	if not weaponDef then
		warn("ViewmodelController: no weapon registered named " .. tostring(currentWeaponName))
		return
	end

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
			lockPart(descendant)
		end
	end

	local screenGui, viewportFrame, worldModel, viewportCamera = buildViewportLayer()
	viewmodel.Parent = worldModel

	local weaponModel, internalMuzzle = equipWeapon(viewmodel, weaponDef)

	-- The workspace tracker carries the ParticleEmitter (which doesn't render
	-- inside a ViewportFrame). Each frame, its CFrame mirrors the visual world
	-- CFrame of the in-viewport muzzle, so the flame appears at the right spot.
	local muzzleTracker = Instance.new("Part")
	muzzleTracker.Name = "ViewmodelMuzzleTracker"
	muzzleTracker.Size = Vector3.new(0.1, 0.1, 0.1)
	muzzleTracker.Transparency = 1
	lockPart(muzzleTracker)
	muzzleTracker.Parent = Workspace.CurrentCamera

	local trackerMuzzle = Instance.new("Attachment")
	trackerMuzzle.Name = weaponDef.muzzleAttachmentName
	trackerMuzzle.Parent = muzzleTracker

	local hiddenEmitter: ParticleEmitter? = findLocalTorsoEmitter()
	if hiddenEmitter then
		hiddenEmitter.Enabled = false
	end

	equipped = {
		screenGui = screenGui,
		viewportFrame = viewportFrame,
		viewportCamera = viewportCamera,
		worldModel = worldModel,
		viewmodel = viewmodel,
		weaponDef = weaponDef,
		weaponModel = weaponModel,
		internalMuzzle = internalMuzzle,
		muzzleTracker = muzzleTracker,
		trackerMuzzle = trackerMuzzle,
		hiddenServerEmitter = hiddenEmitter,
		swayCF = CFrame.new(),
		bobOffset = CFrame.new(),
		lastCameraCF = camera.CFrame,
		projectile = nil,
	}

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

		-- Pivot the whole viewmodel (arms + weapon, all anchored) as a rigid body.
		local pivot = camera.CFrame * e.swayCF * e.bobOffset
		e.viewmodel:PivotTo(pivot)

		-- Mirror viewport camera to main camera so the rendered POV matches.
		e.viewportCamera.CFrame = camera.CFrame

		-- Tracker follows the visual muzzle so the workspace particle emitter
		-- spawns at the same on-screen position as the in-viewport muzzle.
		if e.internalMuzzle and e.internalMuzzle.Parent then
			if e.internalMuzzle:IsA("Attachment") then
				e.muzzleTracker.CFrame = e.internalMuzzle.WorldCFrame
			elseif e.internalMuzzle:IsA("BasePart") then
				e.muzzleTracker.CFrame = e.internalMuzzle.CFrame
			end
		end

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
		-- Particles spawn on the workspace tracker, not the in-viewport muzzle,
		-- because ViewportFrame doesn't render ParticleEmitters.
		equipped.projectile = projectile.start(equipped.trackerMuzzle)
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

	localPlayer.CharacterRemoving:Connect(function()
		if equipped then detach() end
	end)
end

return ViewmodelController
