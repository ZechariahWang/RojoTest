local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local KillConfirmController = {}

local localPlayer = Players.LocalPlayer
local playerGui: PlayerGui

local FRAME_EXPAND_TIME = 0.25
local TEXT_FADE_IN_TIME = 0.20
local HOLD_TIME = 3.0
local TEXT_FADE_OUT_TIME = 0.20
local FRAME_COLLAPSE_TIME = 0.25

local LABEL_COLOR = "rgb(255,255,255)"
local NAME_COLOR = "rgb(255,141,40)"

local confirmGen = 0
local activeClone: GuiObject? = nil

local function findGameGui(): ScreenGui?
	if not playerGui then return nil end
	local gui = playerGui:FindFirstChild("Game")
	if gui and gui:IsA("ScreenGui") then
		return gui
	end
	return nil
end

local function getTemplate(): GuiObject?
	local gui = findGameGui()
	if not gui then return nil end
	local idObjects = gui:FindFirstChild("ID_Objects")
	if not idObjects then return nil end
	local template = idObjects:FindFirstChild("KillConfirm")
	if template and template:IsA("GuiObject") then
		return template
	end
	return nil
end

local function buildText(victimName: string): string
	return string.format(
		'<font color="%s">ELIMINATED</font> <font color="%s">%s</font>',
		LABEL_COLOR,
		NAME_COLOR,
		victimName
	)
end

local function playKillConfirm(victimName: string, myGen: number)
	local template = getTemplate()
	local gui = findGameGui()
	if not template or not gui then return end

	local clone = template:Clone()
	local title = clone:FindFirstChild("Title")
	if not title or not title:IsA("TextLabel") then
		clone:Destroy()
		return
	end

	local stroke = title:FindFirstChildOfClass("UIStroke")
	local originalSize = clone.Size
	local collapsedSize = UDim2.new(0, 0, originalSize.Y.Scale, originalSize.Y.Offset)
	local originalTextTransparency = title.TextTransparency
	local originalStrokeTransparency = stroke and stroke.Transparency or 0

	clone.Size = collapsedSize
	title.RichText = true
	title.Text = buildText(victimName)
	title.TextTransparency = 1
	if stroke then stroke.Transparency = 1 end
	clone.Visible = true
	clone.Parent = gui

	activeClone = clone

	local function bail()
		if activeClone == clone then activeClone = nil end
		clone:Destroy()
	end

	TweenService:Create(
		clone,
		TweenInfo.new(FRAME_EXPAND_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = originalSize }
	):Play()
	task.wait(FRAME_EXPAND_TIME)
	if myGen ~= confirmGen then bail() return end

	TweenService:Create(
		title,
		TweenInfo.new(TEXT_FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = originalTextTransparency }
	):Play()
	if stroke then
		TweenService:Create(
			stroke,
			TweenInfo.new(TEXT_FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = originalStrokeTransparency }
		):Play()
	end
	task.wait(TEXT_FADE_IN_TIME)
	if myGen ~= confirmGen then bail() return end

	task.wait(HOLD_TIME)
	if myGen ~= confirmGen then bail() return end

	TweenService:Create(
		title,
		TweenInfo.new(TEXT_FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1 }
	):Play()
	if stroke then
		TweenService:Create(
			stroke,
			TweenInfo.new(TEXT_FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Transparency = 1 }
		):Play()
	end
	task.wait(TEXT_FADE_OUT_TIME)
	if myGen ~= confirmGen then bail() return end

	TweenService:Create(
		clone,
		TweenInfo.new(FRAME_COLLAPSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = collapsedSize }
	):Play()
	task.wait(FRAME_COLLAPSE_TIME)

	if activeClone == clone then activeClone = nil end
	clone:Destroy()
end

local function onKillFeed(killerName: string?, victimName: string)
	if killerName ~= localPlayer.Name then return end

	confirmGen += 1
	if activeClone then
		activeClone:Destroy()
		activeClone = nil
	end
	task.spawn(playKillConfirm, victimName, confirmGen)
end

function KillConfirmController.init()
	playerGui = localPlayer:WaitForChild("PlayerGui")

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local KillFeedRemote = Remotes:WaitForChild("KillFeed") :: RemoteEvent

	KillFeedRemote.OnClientEvent:Connect(onKillFeed)
end

return KillConfirmController
