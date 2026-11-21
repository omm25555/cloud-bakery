--!strict

export type CropConfig = {
	Id: string,
	IngredientId: string,
	GrowTimeSeconds: number,
	YieldAmount: number,
}

local Crops: { [string]: CropConfig } = {
	Wheat = {
		Id = "Wheat",
		IngredientId = "Wheat",
		GrowTimeSeconds = 30,
		YieldAmount = 3,
	},
	StarMilk = {
		Id = "StarMilk",
		IngredientId = "StarMilk",
		GrowTimeSeconds = 45,
		YieldAmount = 2,
	},
	Strawberry = {
		Id = "Strawberry",
		IngredientId = "Strawberry",
		GrowTimeSeconds = 60,
		YieldAmount = 2,
	},
}

return Crops
