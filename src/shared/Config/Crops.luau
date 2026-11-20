--!strict
-- Crop / source data: what each plot or animal produces and how long it takes.
-- The server owns all timers; these values are read by the server only for
-- decisions and by the client only for display.

export type Crop = {
	id: string,
	ingredient: string, -- IngredientId from Ingredients.luau
	growSeconds: number,
	yieldMin: number,
	yieldMax: number,
	seedCost: number, -- coins to plant
}

local Crops: { [string]: Crop } = {
	Wheat = {
		id = "Wheat",
		ingredient = "Wheat",
		growSeconds = 30,
		yieldMin = 2,
		yieldMax = 3,
		seedCost = 1,
	},
	StarMilk = {
		id = "StarMilk",
		ingredient = "StarMilk",
		growSeconds = 60,
		yieldMin = 1,
		yieldMax = 2,
		seedCost = 0, -- produced by the cloud cow, no seed
	},
	Strawberry = {
		id = "Strawberry",
		ingredient = "Strawberry",
		growSeconds = 45,
		yieldMin = 2,
		yieldMax = 4,
		seedCost = 2,
	},
}

return table.freeze(Crops)
