local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local MapManager = {}

local currentMap: Model? = nil
local lobbySpawn: SpawnLocation? = nil

local function findLobbySpawn(): SpawnLocation?
	for _, child in Workspace.Lobby:GetChildren() do
		if child:IsA("SpawnLocation") then
			return child
		end
	end
	return nil
end

local function getCurrentSpawnPoints(): { BasePart }
	local result = {}
	if not currentMap then return result end
	local folder = currentMap:FindFirstChild("SpawnPoints")
	if not folder then return result end
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") and child.Name == "SpawnPoint" then
			table.insert(result, child)
		end
	end
	return result
end

local function teleportTo(player: Player, cframe: CFrame)
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	root.CFrame = cframe
end

function MapManager.loadRandomMap(): boolean
	MapManager.unloadMap()

	local mapsFolder = ServerStorage:FindFirstChild("Maps")
	if not mapsFolder then
		warn("MapManager: ServerStorage.Maps folder is missing")
		return false
	end

	local maps: { Model } = {}
	for _, child in mapsFolder:GetChildren() do
		if child:IsA("Model") then
			table.insert(maps, child)
		end
	end

	if #maps == 0 then
		warn("MapManager: no Models found in ServerStorage.Maps")
		return false
	end

	local picked = maps[math.random(1, #maps)]
	local clone = picked:Clone()
	clone.Parent = Workspace
	currentMap = clone
	return true
end

function MapManager.unloadMap()
	if currentMap then
		currentMap:Destroy()
		currentMap = nil
	end
end

function MapManager.hasMap(): boolean
	return currentMap ~= nil
end

function MapManager.teleportToArena(player: Player)
	local spawns = getCurrentSpawnPoints()
	if #spawns == 0 then
		warn("MapManager: current map has no SpawnPoints — using fallback")
		teleportTo(player, CFrame.new(0, 5, 0))
		return
	end
	local target = spawns[math.random(1, #spawns)]
	teleportTo(player, target.CFrame + Vector3.new(0, 4, 0))
end

function MapManager.teleportToLobby(player: Player)
	if not lobbySpawn or not lobbySpawn.Parent then
		lobbySpawn = findLobbySpawn()
	end
	if lobbySpawn then
		teleportTo(player, lobbySpawn.CFrame + Vector3.new(0, 4, 0))
	else
		teleportTo(player, CFrame.new(0, 5, 0))
	end
end

function MapManager.init()
	lobbySpawn = findLobbySpawn()
	if not lobbySpawn then
		warn("MapManager: no SpawnLocation found in Workspace at startup")
	end
end

return MapManager
