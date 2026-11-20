--!strict
-- Ingredient data. All numbers are placeholders for balancing later.

export type IngredientId = "Wheat" | "StarMilk" | "Strawberry"

export type Ingredient = {
	id: IngredientId,
	displayName: string,
	maxStack: number,
	sellPrice: number, -- coins per unit if sold raw
}

local Ingredients: { [IngredientId]: Ingredient } = {
	Wheat = {
		id = "Wheat",
		displayName = "Wheat",
		maxStack = 99,
		sellPrice = 2,
	},
	StarMilk = {
		id = "StarMilk",
		displayName = "Star Milk",
		maxStack = 99,
		sellPrice = 4,
	},
	Strawberry = {
		id = "Strawberry",
		displayName = "Strawberry",
		maxStack = 99,
		sellPrice = 3,
	},
}

return table.freeze(Ingredients)
