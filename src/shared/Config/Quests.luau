--!strict
-- ภารกิจรายวัน 3 ข้อ ทำครบแล้วรับรางวัลรวมครั้งเดียว รีเซ็ตทุกวัน (UTC)

export type QuestKind = "Harvest" | "Bake" | "Serve"

export type QuestConfig = {
	Id: string,
	Kind: QuestKind,
	Target: string, -- IngredientId / RecipeId / "Any"
	Goal: number,
}

local Quests = {
	Daily = {
		{ Id = "HarvestWheat", Kind = "Harvest", Target = "Wheat", Goal = 30 },
		{ Id = "BakeCloudBread", Kind = "Bake", Target = "CloudBread", Goal = 10 },
		{ Id = "ServeOrders", Kind = "Serve", Target = "Any", Goal = 8 },
	} :: { QuestConfig },
	RewardCoins = 500,
	RewardReputation = 200,
	SecondsPerDay = 86400,
}

return Quests
