local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local ChangeIndicatorController = {}

local localPlayer = Players.LocalPlayer
local playerGui: PlayerGui

local frame: Frame?
local titleLabel: TextLabel?
local infoLabel: TextLabel?
local frameScale: UIScale?
local cachedInfoPosition: UDim2? = nil

local activeKind: string? = nil
local gen = 0
local lastSeenStage = 0
local localState: string = Constants.STATE_LOBBY
local currentPhase: string = Constants.PHASE_LOBBY

local ENTRANCE_TIME = 0.3
local EXIT_TIME = 0.5
local SWAP_OUT_TIME = 0.25
local SWAP_IN_TIME = 0.25
local SURVIVOR_HOLD = 0.6
local TOTAL_ON_SCREEN = 5.0
local SLIDE_OFFSET = UDim2.new(0.6, 0, 0, 0)

local STAGE_DESCRIPTIONS: { [number]: string } = {
	[1] = "TAG",
	[2] = "TRAILS",
	[3] = "INFERNO",
}

local STAGE_COLORS: { [number]: Color3 } = {
	[1] = Color3.fromRGB(255, 159, 80),
	[2] = Color3.fromRGB(240, 90, 3),
	[3] = Color3.fromRGB(255, 25, 0),
}

local function ensureScale(parent: GuiObject): UIScale
	local existing = parent:FindFirstChildOfClass("UIScale")
	if existing then return existing end
	local scale = Instance.new("UIScale")
	scale.Parent = parent
	return scale
end

local function resolveElements(): boolean
	if frame and frame.Parent and titleLabel and titleLabel.Parent and infoLabel and infoLabel.Parent then
		return true
	end
	if not playerGui then return false end

	local gameGui = playerGui:FindFirstChild("Game")
	if not gameGui then return false end

	local f = gameGui:FindFirstChild("ChangeIndicator")
	if not f or not f:IsA("Frame") then return false end
	frame = f

	local t = f:FindFirstChild("Title")
	if not t or not t:IsA("TextLabel") then return false end
	titleLabel = t

	local i = f:FindFirstChild("UpdatedInfo")
	if not i or not i:IsA("TextLabel") then return false end
	infoLabel = i

	frameScale = ensureScale(f)
	if not cachedInfoPosition then
		cachedInfoPosition = i.Position
	end

	if not t.RichText then t.RichText = true end
	if not i.RichText then i.RichText = true end

	f.Visible = false
	frameScale.Scale = 0
	return true
end

local function tween(obj: Instance, info: TweenInfo, props: { [string]: any })
	TweenService:Create(obj, info, props):Play()
end

local function isStillActive(myGen: number): boolean
	return myGen == gen and activeKind ~= nil
end

local function finishAnimation(myGen: number)
	if myGen ~= gen then return end
	activeKind = nil
	if frame then frame.Visible = false end
	if frameScale then frameScale.Scale = 0 end
	if infoLabel and cachedInfoPosition then
		infoLabel.Position = cachedInfoPosition
		infoLabel.TextTransparency = 0
	end
end

local function playTag()
	gen += 1
	activeKind = "tag"
	local myGen = gen

	if not resolveElements() then
		activeKind = nil
		return
	end
	assert(frame and titleLabel and infoLabel and frameScale and cachedInfoPosition)

	titleLabel.Text = "TAGGED"
	titleLabel.TextColor3 = Constants.TAGGER_COLOR
	infoLabel.Text = "SURVIVOR"
	infoLabel.TextColor3 = Constants.SURVIVOR_COLOR
	infoLabel.Position = cachedInfoPosition
	infoLabel.TextTransparency = 0

	frameScale.Scale = 0
	frame.Visible = true

	tween(frameScale,
		TweenInfo.new(ENTRANCE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	task.wait(ENTRANCE_TIME)
	if not isStillActive(myGen) then return end

	task.wait(SURVIVOR_HOLD)
	if not isStillActive(myGen) then return end

	tween(infoLabel,
		TweenInfo.new(SWAP_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = cachedInfoPosition + SLIDE_OFFSET, TextTransparency = 1 }
	)
	task.wait(SWAP_OUT_TIME)
	if not isStillActive(myGen) then return end

	infoLabel.Position = cachedInfoPosition - SLIDE_OFFSET
	infoLabel.Text = "TAGGER"
	infoLabel.TextColor3 = Constants.TAGGER_COLOR

	tween(infoLabel,
		TweenInfo.new(SWAP_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = cachedInfoPosition, TextTransparency = 0 }
	)
	task.wait(SWAP_IN_TIME)
	if not isStillActive(myGen) then return end

	local elapsedSoFar = ENTRANCE_TIME + SURVIVOR_HOLD + SWAP_OUT_TIME + SWAP_IN_TIME
	local taggerHold = TOTAL_ON_SCREEN - elapsedSoFar - EXIT_TIME
	if taggerHold > 0 then
		task.wait(taggerHold)
		if not isStillActive(myGen) then return end
	end

	tween(frameScale,
		TweenInfo.new(EXIT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = 0 }
	)
	task.wait(EXIT_TIME)
	finishAnimation(myGen)
end

local function playStage(stageNum: number)
	if activeKind == "tag" then return end

	gen += 1
	activeKind = "stage"
	local myGen = gen

	if not resolveElements() then
		activeKind = nil
		return
	end
	assert(frame and titleLabel and infoLabel and frameScale and cachedInfoPosition)

	local color = STAGE_COLORS[stageNum] or Color3.fromRGB(240, 240, 240)
	local desc = STAGE_DESCRIPTIONS[stageNum] or ""

	titleLabel.Text = "STAGE " .. tostring(stageNum)
	titleLabel.TextColor3 = color
	infoLabel.Text = desc
	infoLabel.TextColor3 = color
	infoLabel.Position = cachedInfoPosition
	infoLabel.TextTransparency = 0

	frameScale.Scale = 0
	frame.Visible = true

	tween(frameScale,
		TweenInfo.new(ENTRANCE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	task.wait(ENTRANCE_TIME)
	if not isStillActive(myGen) then return end

	local hold = TOTAL_ON_SCREEN - ENTRANCE_TIME - EXIT_TIME
	if hold > 0 then
		task.wait(hold)
		if not isStillActive(myGen) then return end
	end

	tween(frameScale,
		TweenInfo.new(EXIT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = 0 }
	)
	task.wait(EXIT_TIME)
	finishAnimation(myGen)
end

function ChangeIndicatorController.init()
	playerGui = localPlayer:WaitForChild("PlayerGui")
	resolveElements()

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent
	local PlayerStateRemote = Remotes:WaitForChild("PlayerStateChanged") :: RemoteEvent

	RoundStateRemote.OnClientEvent:Connect(function(phase: string, _duration: number?, extra: any?)
		currentPhase = phase
		if phase == Constants.PHASE_ROUND and typeof(extra) == "table" and typeof(extra.stage) == "number" then
			local s = extra.stage
			if s ~= lastSeenStage then
				lastSeenStage = s
				task.spawn(playStage, s)
			end
		elseif phase ~= Constants.PHASE_ROUND then
			lastSeenStage = 0
		end
	end)

	PlayerStateRemote.OnClientEvent:Connect(function(player: Player, state: string)
		if player ~= localPlayer then return end
		local prev = localState
		localState = state
		if prev == Constants.STATE_SAFE and state == Constants.STATE_BURNING then
			task.spawn(playTag)
		end
	end)
end

return ChangeIndicatorController
