local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local KillFeedController = {}

local localPlayer = Players.LocalPlayer
local playerGui: PlayerGui

local MAX_ENTRIES = 5
local DISPLAY_TIME = 4
local FADE_IN_TIME = 0.25
local FADE_OUT_TIME = 0.4
local SLIDE_OFFSET = 80

type Entry = {
	label: TextLabel,
	removing: boolean,
	originalTextTransparency: number,
	originalPosition: UDim2,
}

local activeEntries: { Entry } = {}

local function findGameGui(): ScreenGui?
	if not playerGui then return nil end
	local gui = playerGui:FindFirstChild("Game")
	if gui and gui:IsA("ScreenGui") then
		return gui
	end
	return nil
end

local function getTemplate(): TextLabel?
	local gui = findGameGui()
	if not gui then return nil end
	local idObjects = gui:FindFirstChild("ID_Objects")
	if not idObjects then return nil end
	local template = idObjects:FindFirstChild("KillData")
	if template and template:IsA("TextLabel") then
		return template
	end
	return nil
end

local function getFeedFrame(): GuiObject?
	local gui = findGameGui()
	if not gui then return nil end
	local feed = gui:FindFirstChild("Killfeed") or gui:FindFirstChild("KillFeed") or gui:FindFirstChild("killfeed")
	if feed and feed:IsA("GuiObject") then
		return feed
	end
	return nil
end

local function removeEntry(entry: Entry)
	if entry.removing then return end
	entry.removing = true

	for i, e in activeEntries do
		if e == entry then
			table.remove(activeEntries, i)
			break
		end
	end

	local label = entry.label
	if not label or not label.Parent then return end

	local tween = TweenService:Create(
		label,
		TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{
			TextTransparency = 1,
			Position = entry.originalPosition + UDim2.fromOffset(-SLIDE_OFFSET, 0),
		}
	)
	tween:Play()
	tween.Completed:Once(function()
		if label then label:Destroy() end
	end)
end

local function animateIn(entry: Entry)
	local label = entry.label
	label.Position = entry.originalPosition + UDim2.fromOffset(SLIDE_OFFSET, 0)
	label.TextTransparency = 1

	TweenService:Create(
		label,
		TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = entry.originalPosition,
			TextTransparency = entry.originalTextTransparency,
		}
	):Play()
end

local function addEntry(text: string)
	local template = getTemplate()
	local feed = getFeedFrame()
	if not template or not feed then return end

	local label = template:Clone()
	label.Text = text
	label.Visible = true
	label.Parent = feed

	local entry: Entry = {
		label = label,
		removing = false,
		originalTextTransparency = template.TextTransparency,
		originalPosition = label.Position,
	}
	table.insert(activeEntries, entry)

	while #activeEntries > MAX_ENTRIES do
		removeEntry(activeEntries[1])
	end

	animateIn(entry)

	task.delay(DISPLAY_TIME, function()
		removeEntry(entry)
	end)
end

local function formatKillText(killer: string?, victim: string): string
	if killer and killer ~= "" then
		return string.format("%s burned %s", killer, victim)
	end
	return string.format("%s burned", victim)
end

function KillFeedController.init()
	playerGui = localPlayer:WaitForChild("PlayerGui")

	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local KillFeedRemote = Remotes:WaitForChild("KillFeed") :: RemoteEvent

	KillFeedRemote.OnClientEvent:Connect(function(killer: string?, victim: string)
		addEntry(formatKillText(killer, victim))
	end)
end

return KillFeedController
