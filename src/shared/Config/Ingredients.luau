--!strict

export type IngredientConfig = {
	Id: string,
	DisplayNameTh: string,
	DisplayNameEn: string,
	SellPrice: number,
}

local Ingredients: { [string]: IngredientConfig } = {
	Wheat = {
		Id = "Wheat",
		DisplayNameTh = "ข้าวสาลี",
		DisplayNameEn = "Wheat",
		SellPrice = 5,
	},
	StarMilk = {
		Id = "StarMilk",
		DisplayNameTh = "น้ำนมดาว",
		DisplayNameEn = "Star Milk",
		SellPrice = 8,
	},
	Strawberry = {
		Id = "Strawberry",
		DisplayNameTh = "สตรอว์เบอรี",
		DisplayNameEn = "Strawberry",
		SellPrice = 10,
	},
}

return Ingredients
