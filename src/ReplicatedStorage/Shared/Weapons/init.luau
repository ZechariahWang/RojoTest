--!strict
-- Weapon registry. Each weapon module returns a WeaponDef table; see
-- Flamethrower.luau for the field shape. Add a new weapon by dropping a sibling
-- module here and listing it below.

local Weapons = {}

Weapons.Flamethrower = require(script:WaitForChild("Flamethrower"))

return Weapons
