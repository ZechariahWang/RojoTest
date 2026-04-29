local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local UIController = {}

local localPlayer = Players.LocalPlayer
local playerGui: PlayerGui

local statusLabel: TextLabel?
local secondaryLabel: TextLabel?
local lastMainText = ""
local lastSecondaryText = ""

local currentPhase = Constants.PHASE_LOBBY
local phaseEndTime = 0
local endExtra: any = nil
local currentStage = 0
local playerStates: { [Player]: string } = {}

local WHITE = Color3.fromRGB(240, 240, 240)
local YELLOW = Color3.fromRGB(255, 220, 80)
local ORANGE = Color3.fromRGB(255, 150, 40)
local RED = Color3.fromRGB(255, 80, 60)
local GREEN = Color3.fromRGB(80, 220, 80)
local CYAN = Color3.fromRGB(120, 220, 255)

local STAGE_COLORS: { [number]: Color3 } = {
	[1] = YELLOW,
	[2] = ORANGE,
	[3] = RED,
}

local STAGE_DESCRIPTIONS: { [number]: string } = {
	[1] = "TAG",
	[2] = "TRAILS",
	[3] = "INFERNO",
}

local function colorize(color: Color3, text: string): string
	return string.format(
		"<font color=\"rgb(%d,%d,%d)\">%s</font>",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5),
		text
	)
end

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

local function buildMainText(): string
	if currentPhase == Constants.PHASE_LOBBY then
		return colorize(WHITE, "WAITING FOR PLAYERS...")
	elseif currentPhase == Constants.PHASE_INTERMISSION then
		return colorize(YELLOW, "GET READY!")
	elseif currentPhase == Constants.PHASE_REVEAL then
		if endExtra and typeof(endExtra) == "table" and endExtra.burner then
			return colorize(RED, string.upper(endExtra.burner) .. " IS BURNING!")
		end
		return colorize(RED, "BURNER REVEALED")
	elseif currentPhase == Constants.PHASE_ROUND then
		if currentStage > 0 then
			local stageColor = STAGE_COLORS[currentStage] or WHITE
			local desc = STAGE_DESCRIPTIONS[currentStage] or ""
			return colorize(stageColor, string.format("STAGE %d/%d — %s", currentStage, Constants.STAGE_COUNT, desc))
		end
		return colorize(WHITE, "BURN RUSH")
	elseif currentPhase == Constants.PHASE_END then
		if endExtra and typeof(endExtra) == "table" then
			local winners = endExtra.winners
			if typeof(winners) == "table" and #winners > 0 then
				if #winners == 1 then
					return colorize(GREEN, string.upper(winners[1]) .. " SURVIVED!")
				elseif #winners == 2 then
					return colorize(GREEN, string.upper(winners[1]) .. " AND " .. string.upper(winners[2]) .. " SURVIVED!")
				else
					return colorize(GREEN, string.format("%d PLAYERS SURVIVED!", #winners))
				end
			elseif endExtra.reason == Constants.REASON_ALL_INFECTED then
				return colorize(RED, "EVERYONE BURNED!")
			end
		end
		return colorize(WHITE, "ROUND ENDED")
	end
	return ""
end

local function buildSecondaryText(): string
	if currentPhase == Constants.PHASE_LOBBY then
		local lobbyCount = countByState(Constants.STATE_LOBBY)
		return colorize(WHITE, string.format("Players: %d / %d", lobbyCount, Constants.MIN_PLAYERS))
	elseif currentPhase == Constants.PHASE_INTERMISSION then
		if phaseEndTime > 0 then
			local remaining = math.max(0, phaseEndTime - os.time())
			local color = if remaining <= 3 then RED else WHITE
			return colorize(color, string.format("Starting in %ds", math.ceil(remaining)))
		end
		return ""
	elseif currentPhase == Constants.PHASE_REVEAL then
		if phaseEndTime > 0 then
			local remaining = math.max(0, phaseEndTime - os.time())
			return colorize(YELLOW, string.format("Position yourself! %ds", math.ceil(remaining)))
		end
		return colorize(YELLOW, "Position yourself!")
	elseif currentPhase == Constants.PHASE_ROUND then
		local parts: { string } = {}
		if phaseEndTime > 0 then
			local remaining = phaseEndTime - os.time()
			local color = if remaining <= 30 then RED else WHITE
			table.insert(parts, colorize(color, formatTime(remaining)))
		end
		local safeCount = countByState(Constants.STATE_SAFE)
		local totalCount = safeCount + countByState(Constants.STATE_BURNING)
		table.insert(parts, colorize(WHITE, string.format("%d/%d", safeCount, totalCount-1))) -- dont include sekf
		return table.concat(parts, "  |  ")
	elseif currentPhase == Constants.PHASE_END then
		return ""
	end
	return ""
end

local function resolveLabel(frameName: string, labelName: string, cached: TextLabel?): TextLabel?
	if cached and cached.Parent then
		return cached
	end

	local gameGui = playerGui:FindFirstChild("Game")
	if not gameGui then return nil end
	local frame = gameGui:FindFirstChild(frameName)
	if not frame then return nil end
	local label = frame:FindFirstChild(labelName)
	if not label or not label:IsA("TextLabel") then return nil end

	if not label.RichText then
		label.RichText = true
	end
	return label
end

local function updateLoop()
	local newStatus = resolveLabel("StatusFrame", "Status", statusLabel)
	if newStatus ~= statusLabel then
		statusLabel = newStatus
		lastMainText = ""
	end

	local newSecondary = resolveLabel("SecondaryStatus", "Secondary", secondaryLabel)
	if newSecondary ~= secondaryLabel then
		secondaryLabel = newSecondary
		lastSecondaryText = ""
	end

	if statusLabel then
		local text = buildMainText()
		if text ~= lastMainText then
			statusLabel.Text = text
			lastMainText = text
		end
	end

	if secondaryLabel then
		local text = buildSecondaryText()
		if text ~= lastSecondaryText then
			secondaryLabel.Text = text
			lastSecondaryText = text
		end
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
