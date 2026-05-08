local Constants = require(script.Parent.Constants)

export type AbilityDef = {
	id: string,
	displayName: string,
	cooldown: number,
	iconName: string,
}

local Abilities = {}

Abilities.CATEGORY_SURVIVOR = "Survivor"
Abilities.CATEGORY_TAGGER = "Tagger"

Abilities.Defs = {
	Dash = {
		id = "Dash",
		displayName = "DASH",
		cooldown = Constants.DASH_COOLDOWN,
		iconName = "Dash",
	},
} :: { [string]: AbilityDef }

Abilities.Categories = {
	[Abilities.CATEGORY_SURVIVOR] = { "Dash" },
	[Abilities.CATEGORY_TAGGER] = { "Dash" },
} :: { [string]: { string } }

function Abilities.get(id: string): AbilityDef?
	return Abilities.Defs[id]
end

function Abilities.primaryFor(category: string): AbilityDef?
	local ids = Abilities.Categories[category]
	if not ids or #ids == 0 then return nil end
	return Abilities.Defs[ids[1]]
end

function Abilities.categoryForState(state: string): string?
	if state == Constants.STATE_SAFE then
		return Abilities.CATEGORY_SURVIVOR
	elseif state == Constants.STATE_BURNING then
		return Abilities.CATEGORY_TAGGER
	end
	return nil
end

return Abilities
