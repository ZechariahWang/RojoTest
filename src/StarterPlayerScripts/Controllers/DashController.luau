local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

local DashController = {}

local DashRequestRemote: RemoteEvent
local lastDash = 0

local function tryDash()
	local now = os.clock()
	if now - lastDash < Constants.DASH_COOLDOWN then return end
	lastDash = now
	DashRequestRemote:FireServer()
end

function DashController.init()
	DashRequestRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DashRequest") :: RemoteEvent

	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == Enum.KeyCode.Q then
			tryDash()
		end
	end)
end

return DashController
