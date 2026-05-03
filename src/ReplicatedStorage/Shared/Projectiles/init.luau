--!strict
-- Projectile registry. Auto-discovers every sibling ModuleScript. Each module
-- exposes:
--   .name : string
--   .start(muzzle: Instance) : { stop: (self) -> () }

local Projectiles: { [string]: any } = {}

for _, child in ipairs(script:GetChildren()) do
	if child:IsA("ModuleScript") then
		local ok, mod = pcall(require, child)
		if ok and type(mod) == "table" then
			Projectiles[child.Name] = mod
		else
			warn("Projectiles registry: failed to load " .. child.Name .. ": " .. tostring(mod))
		end
	end
end

return Projectiles
