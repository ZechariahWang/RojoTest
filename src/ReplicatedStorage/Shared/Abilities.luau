local Constants = require(script.Parent.Constants)

export type AbilityDef = {
	id: string,
	displayName: string,
	cooldown: number,
	iconName: string,
}

local Abilities: { [string]: AbilityDef } = {
	Dash = {
		id = "Dash",
		displayName = "DASH",
		cooldown = Constants.DASH_COOLDOWN,
		iconName = "Dash",
	},
}

return Abilities
