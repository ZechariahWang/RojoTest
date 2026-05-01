local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Remotes")

local Controllers = script.Parent:WaitForChild("Controllers")
local DashController = require(Controllers.DashController)
local UIController = require(Controllers.UIController)
local KillFeedController = require(Controllers.KillFeedController)
local FireAttackController = require(Controllers.FireAttackController)
local CombatFeedbackController = require(Controllers.CombatFeedbackController)

DashController.init()
UIController.init()
KillFeedController.init()
FireAttackController.init()
CombatFeedbackController.init()
