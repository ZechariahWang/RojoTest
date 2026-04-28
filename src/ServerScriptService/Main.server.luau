local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Systems = ServerScriptService:WaitForChild("Systems")

local PlayerState = require(Systems.PlayerState)
local MapManager = require(Systems.MapManager)
local AbilitySystem = require(Systems.AbilitySystem)
local InfectionSystem = require(Systems.InfectionSystem)
local FireSpreadSystem = require(Systems.FireSpreadSystem)
local RoundManager = require(Systems.RoundManager)

PlayerState.init()
MapManager.init()
AbilitySystem.init()
InfectionSystem.init()
FireSpreadSystem.init()
RoundManager.init()
