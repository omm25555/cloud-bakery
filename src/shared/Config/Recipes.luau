--!strict
-- Recipe data. Ingredient keys are IngredientIds from Ingredients.luau.
-- Rhythm minigame quality multiplies sellPrice; the server computes the result.

export type Recipe = {
	id: string,
	displayName: string,
	ingredients: { [string]: number }, -- IngredientId -> amount
	bakeSeconds: number,
	sellPrice: number, -- base coins at normal quality
	unlockLevel: number,
}

local Recipes: { [string]: Recipe } = {
	CloudBread = {
		id = "CloudBread",
		displayName = "Cloud Bread",
		ingredients = { Wheat = 2, StarMilk = 1 },
		bakeSeconds = 10,
		sellPrice = 15,
		unlockLevel = 1,
	},
	Croissant = {
		id = "Croissant",
		displayName = "Croissant",
		ingredients = { Wheat = 3, StarMilk = 2 },
		bakeSeconds = 15,
		sellPrice = 28,
		unlockLevel = 2,
	},
	StrawberryCake = {
		id = "StrawberryCake",
		displayName = "Strawberry Cake",
		ingredients = { Wheat = 2, StarMilk = 2, Strawberry = 3 },
		bakeSeconds = 20,
		sellPrice = 45,
		unlockLevel = 3,
	},
}

return table.freeze(Recipes)
