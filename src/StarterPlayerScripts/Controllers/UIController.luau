local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local UIController = {}

local localPlayer = Players.LocalPlayer
local playerGui: PlayerGui

local statusLabel: TextLabel?
local lastText = ""

local currentPhase = Constants.PHASE_LOBBY
local phaseEndTime = 0
local endExtra: any = nil
local currentStage = 0
local playerStates: { [Player]: string } = {}

local STAGE_DESCRIPTIONS = {
	[1] = "Stay clear of the burned",
	[2] = "They leave fire trails!",
	[3] = "Anything they touch ignites!",
}

local function countByState(state: string): number
	local count = 0
	for _, s in playerStates do
		if s == state then
			count += 1
		end
	end
	return count
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return string.format("%d:%02d", m, s)
end

local function buildStatusText(): string
	local lines: { string } = {}

	if currentPhase == Constants.PHASE_LOBBY then
		local lobbyCount = countByState(Constants.STATE_LOBBY)
		table.insert(lines, "Waiting for players...")
		table.insert(lines, string.format("Players: %d / %d", lobbyCount, Constants.MIN_PLAYERS))
	elseif currentPhase == Constants.PHASE_INTERMISSION then
		table.insert(lines, "Get ready!")
		if phaseEndTime > 0 then
			local remaining = math.max(0, phaseEndTime - os.time())
			table.insert(lines, string.format("Starting in %ds", math.ceil(remaining)))
		end
	elseif currentPhase == Constants.PHASE_ROUND then
		local safeCount = countByState(Constants.STATE_SAFE)
		local burningCount = countByState(Constants.STATE_BURNING)
		local timerText = ""
		if phaseEndTime > 0 then
			timerText = " — " .. formatTime(phaseEndTime - os.time())
		end
		table.insert(lines, "BURN RUSH" .. timerText)
		table.insert(lines, string.format("Safe: %d  |  Burning: %d", safeCount, burningCount))

		if currentStage > 0 then
			table.insert(lines, string.format("STAGE %d/%d", currentStage, Constants.STAGE_COUNT))
			local desc = STAGE_DESCRIPTIONS[currentStage]
			if desc then
				table.insert(lines, desc)
			end
		end

		local myState = playerStates[localPlayer]
		if myState == Constants.STATE_SAFE then
			table.insert(lines, "You are SAFE — press Q to dash")
		elseif myState == Constants.STATE_BURNING then
			table.insert(lines, "You are BURNING — chase them!")
		end
	elseif currentPhase == Constants.PHASE_END then
		if endExtra and endExtra.winner then
			table.insert(lines, endExtra.winner .. " survived!")
		elseif endExtra and endExtra.reason == Constants.REASON_ALL_INFECTED then
			table.insert(lines, "Everyone burned!")
		else
			table.insert(lines, "Round ended")
		end
	end

	return table.concat(lines, "\n")
end

local function resolveStatusLabel(): TextLabel?
	if statusLabel and statusLabel.Parent then
		return statusLabel
	end

	local gameGui = playerGui:FindFirstChild("Game")
	if not gameGui then return nil end
	local frame = gameGui:FindFirstChild("StatusFrame")
	if not frame then return nil end
	local label = frame:FindFirstChild("Status")
	if not label or not label:IsA("TextLabel") then return nil end

	if label ~= statusLabel then
		lastText = "" -- force a write to the freshly-replicated label
	end
	statusLabel = label
	return statusLabel
end

local function updateLoop()
	local label = resolveStatusLabel()
	if not label then return end

	local text = buildStatusText()
	if text ~= lastText then
		label.Text = text
		lastText = text
	end
end

function UIController.init()
	playerGui = localPlayer:WaitForChild("PlayerGui")

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local RoundStateRemote = Remotes:WaitForChild("RoundStateChanged") :: RemoteEvent
	local PlayerStateRemote = Remotes:WaitForChild("PlayerStateChanged") :: RemoteEvent

	RoundStateRemote.OnClientEvent:Connect(function(phase: string, duration: number?, extra: any?)
		currentPhase = phase
		phaseEndTime = if duration then os.time() + duration else 0
		endExtra = extra
		if phase == Constants.PHASE_ROUND and typeof(extra) == "table" and extra.stage then
			currentStage = extra.stage
		elseif phase ~= Constants.PHASE_ROUND then
			currentStage = 0
		end
	end)

	PlayerStateRemote.OnClientEvent:Connect(function(player: Player, state: string)
		playerStates[player] = state
	end)

	Players.PlayerRemoving:Connect(function(player)
		playerStates[player] = nil
	end)

	RunService.RenderStepped:Connect(updateLoop)
end

return UIController
