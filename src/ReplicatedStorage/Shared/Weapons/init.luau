--!strict
-- Weapon registry. Auto-discovers every sibling ModuleScript and exposes them
-- by name. Drop a new module in this folder and it's available immediately —
-- no manual registration needed. See Flamethrower.luau for the field shape.

local Weapons: { [string]: any } = {}

for _, child in ipairs(script:GetChildren()) do
	if child:IsA("ModuleScript") then
		local ok, mod = pcall(require, child)
		if ok and type(mod) == "table" then
			Weapons[child.Name] = mod
		else
			warn("Weapons registry: failed to load " .. child.Name .. ": " .. tostring(mod))
		end
	end
end

return Weapons
