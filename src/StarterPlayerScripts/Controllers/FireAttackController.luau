local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local FireAttackController = {}

local localPlayer = Players.LocalPlayer
local FireRequestRemote: RemoteEvent
local FuelChangedRemote: RemoteEvent
local PlayerStateRemote: RemoteEvent

local isBurning = false
local isHolding = false
local fuel = Constants.FIRE_FUEL_MAX
local fuelMax = Constants.FIRE_FUEL_MAX

local playerGui: PlayerGui
local container: GuiObject?
local fillBar: GuiObject?
local emptyOverlay: GuiObject?

local function resolveElements()
	if container and container.Parent then return end
	container = nil
	fillBar = nil
	emptyOverlay = nil

	if not playerGui then return end
	local gameGui = playerGui:FindFirstChild("Game")
	if not gameGui then return end

	local fm = gameGui:FindFirstChild("FuelMeter")
	if not fm or not fm:IsA("GuiObject") then return end
	container = fm

	local barBg = fm:FindFirstChild("BarBG")
	if not barBg then return end

	local fill = barBg:FindFirstChild("Fill")
	if fill and fill:IsA("GuiObject") then
		fillBar = fill
	end
	local overlay = barBg:FindFirstChild("EmptyOverlay")
	if overlay and overlay:IsA("GuiObject") then
		emptyOverlay = overlay
	end
end

local function updateMeter()
	resolveElements()
	if not fillBar then return end
	local pct = math.clamp(fuel / fuelMax, 0, 1)
	fillBar:TweenSize(
		UDim2.fromScale(pct, 1),
		Enum.EasingDirection.Out,
		Enum.EasingStyle.Quad,
		0.08,
		true
	)

	if emptyOverlay then
		emptyOverlay.Visible = fuel < Constants.FIRE_FUEL_MIN_TO_START
	end
end

local function setHudVisible(visible: boolean)
	resolveElements()
	if not container then return end
	if container.Visible == visible then return end
	container.Visible = visible
end

local function sendFireRequest(active: boolean)
	if isHolding == active then return end
	isHolding = active
	if FireRequestRemote then
		FireRequestRemote:FireServer(active)
	end
end

local function tryStartHold()
	if not isBurning then return end
	if fuel < Constants.FIRE_FUEL_MIN_TO_START then return end
	sendFireRequest(true)
end

local function stopHold()
	sendFireRequest(false)
end

local function onLocalStateChanged(newState: string)
	local nowBurning = (newState == Constants.STATE_BURNING)
	if nowBurning == isBurning then return end
	isBurning = nowBurning
	setHudVisible(nowBurning)
	if not nowBurning then
		stopHold()
	end
end

function FireAttackController.init()
	playerGui = localPlayer:WaitForChild("PlayerGui")

	-- Hide the authored meter until the player becomes Burning.
	setHudVisible(false)
	updateMeter()

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	FireRequestRemote = Remotes:WaitForChild("FireRequest") :: RemoteEvent
	FuelChangedRemote = Remotes:WaitForChild("FuelChanged") :: RemoteEvent
	PlayerStateRemote = Remotes:WaitForChild("PlayerStateChanged") :: RemoteEvent

	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		tryStartHold()
	end)

	UserInputService.InputEnded:Connect(function(input, _gpe)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		stopHold()
	end)

	FuelChangedRemote.OnClientEvent:Connect(function(newFuel: number, newMax: number?)
		fuel = newFuel
		if newMax then fuelMax = newMax end
		updateMeter()
		
		if isHolding and fuel <= 0 then
			isHolding = false
		end
	end)

	PlayerStateRemote.OnClientEvent:Connect(function(player: Player, state: string)
		if player == localPlayer then
			onLocalStateChanged(state)
		end
	end)

	RunService.RenderStepped:Connect(function()
		if isHolding and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
			stopHold()
		end
	end)
end

return FireAttackController
