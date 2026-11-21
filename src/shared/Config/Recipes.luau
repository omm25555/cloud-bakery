--!strict

export type RecipeConfig = {
	Id: string,
	DisplayNameTh: string,
	DisplayNameEn: string,
	Ingredients: { [string]: number },
	BakeTimeSeconds: number,
	SellPrice: number,
}

local Recipes: { [string]: RecipeConfig } = {
	CloudBread = {
		Id = "CloudBread",
		DisplayNameTh = "ขนมปังเมฆ",
		DisplayNameEn = "Cloud Bread",
		Ingredients = { Wheat = 2, StarMilk = 1 },
		BakeTimeSeconds = 20,
		SellPrice = 30,
	},
	Croissant = {
		Id = "Croissant",
		DisplayNameTh = "ครัวซองต์",
		DisplayNameEn = "Croissant",
		Ingredients = { Wheat = 3, StarMilk = 2 },
		BakeTimeSeconds = 30,
		SellPrice = 55,
	},
	StrawberryCake = {
		Id = "StrawberryCake",
		DisplayNameTh = "เค้กสตรอว์เบอรี",
		DisplayNameEn = "Strawberry Cake",
		Ingredients = { Wheat = 3, StarMilk = 2, Strawberry = 2 },
		BakeTimeSeconds = 40,
		SellPrice = 90,
	},
}

return Recipes
