--!strict
-- Projectile registry. Each projectile module exposes:
--   .name : string
--   .start(muzzle: Instance) : { stop: (self) -> () }
-- Add a new projectile by dropping a sibling module here and listing it below.

local Projectiles = {}

Projectiles.Flame = require(script:WaitForChild("Flame"))

return Projectiles
