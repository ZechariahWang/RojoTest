local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Remotes")

local Controllers = script.Parent:WaitForChild("Controllers")
local DashController = require(Controllers.DashController)
local UIController = require(Controllers.UIController)
local KillFeedController = require(Controllers.KillFeedController)

DashController.init()
UIController.init()
KillFeedController.init()
