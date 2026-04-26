local players = game:GetService("Players")

local function onPlayerAdded(player)
    local part = game.Workspace.help
    print("Hello, " .. player.Name .. "!")
end

players.PlayerAdded:Connect(onPlayerAdded)