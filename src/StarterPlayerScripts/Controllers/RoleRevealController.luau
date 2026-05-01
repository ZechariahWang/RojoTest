local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local RoleRevealController = {}

local localPlayer = Players.LocalPlayer
local playerGui: PlayerGui

local roleFrame: Frame?
local roleLabel: TextLabel?
local frameScale: UIScale?
local labelScale: UIScale?

local revealGen = 0
local currentPhase: string = Constants.PHASE_LOBBY

local CYCLE_DURATION = 2.0
local CYCLE_INTERVAL_FAST = 0.04
local CYCLE_INTERVAL_SLOW = 0.30
local SETTLE_TIME = 3.0 
local ENTRANCE_TIME = 0.3
local EXIT_TIME = 1

local function ensureScale(parent: GuiObject): UIScale
	local existing = parent:FindFirstChildOfClass("UIScale")
	if existing then return existing end
	local scale = Instance.new("UIScale")
	scale.Parent = parent
	return scale
end

local function resolveElements(): boolean
	if roleFrame and roleFrame.Parent and roleLabel and roleLabel.Parent then
		return true
	end
	if not playerGui then return false end

	local gameGui = playerGui:FindFirstChild("Game")
	if not gameGui then return false end

	local frame = gameGui:FindFirstChild("Role")
	if not frame or not frame:IsA("Frame") then return false end
	roleFrame = frame

	local label = frame:FindFirstChild("ROLE")
	if not label or not label:IsA("TextLabel") then return false end
	roleLabel = label

	frameScale = ensureScale(frame)
	labelScale = ensureScale(label)

	frame.Visible = false
	frameScale.Scale = 0
	labelScale.Scale = 1
	return true
end

local function setRoleText(isBurner: boolean)
	if not roleLabel then return end
	if isBurner then
		roleLabel.Text = "TAGGER"
		roleLabel.TextColor3 = Constants.TAGGER_COLOR
	else
		roleLabel.Text = "SURVIVOR"
		roleLabel.TextColor3 = Constants.SURVIVOR_COLOR
	end
end

local function tween(obj: Instance, info: TweenInfo, props: { [string]: any })
	TweenService:Create(obj, info, props):Play()
end

local function bailIfStale(myGen: number): boolean
	return myGen ~= revealGen or currentPhase ~= Constants.PHASE_ROLE_REVEAL
end

local function playReveal(localIsBurner: boolean, durationBudget: number)
	revealGen += 1
	local myGen = revealGen
	if not resolveElements() then return end
	assert(roleFrame and frameScale and labelScale)

	-- Reset to clean entrance state
	frameScale.Scale = 0
	labelScale.Scale = 1
	roleFrame.Visible = true

	local skipCycle = durationBudget < (Constants.ROLE_REVEAL_TIME * 0.6)
	setRoleText(localIsBurner)

	tween(frameScale,
		TweenInfo.new(ENTRANCE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	task.wait(ENTRANCE_TIME)
	if bailIfStale(myGen) then return end

	if not skipCycle then
		local elapsed = 0
		local idx = 0
		while elapsed < CYCLE_DURATION do
			idx += 1
			setRoleText(idx % 2 == 1)
			local t = elapsed / CYCLE_DURATION
			local interval = CYCLE_INTERVAL_FAST + (t * t) * (CYCLE_INTERVAL_SLOW - CYCLE_INTERVAL_FAST)
			task.wait(interval)
			elapsed += interval
			if bailIfStale(myGen) then return end
		end
	end

	setRoleText(localIsBurner)
	labelScale.Scale = 1.25
	tween(labelScale,
		TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	task.wait(SETTLE_TIME)
	if bailIfStale(myGen) then return end

	tween(frameScale,
		TweenInfo.new(EXIT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = 0 }
	)
	task.wait(EXIT_TIME+1)
	if bailIfStale(myGen) then return end
	if roleFrame then roleFrame.Visible = false end
end

local function hideImmediately()
	revealGen += 1 -- invalidate any in-flight task
	if roleFrame then roleFrame.Visible = false end
	if frameScale then frameScale.Scale = 0 end
end

function RoleRevealController.init()
	playerGui = localPlayer:WaitForChild("PlayerGui")
	resolveElements()

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

	RoundStateRemote.OnClientEvent:Connect(function(phase: string, duration: number?, extra: any?)
		currentPhase = phase

		if phase == Constants.PHASE_ROLE_REVEAL then
			local burnerName: string? = nil
			if typeof(extra) == "table" then
				burnerName = extra.burner
			end
			local localIsBurner = burnerName == localPlayer.Name
			local budget = duration or Constants.ROLE_REVEAL_TIME
			task.spawn(playReveal, localIsBurner, budget)
		else
			hideImmediately()
		end
	end)
end

return RoleRevealController
