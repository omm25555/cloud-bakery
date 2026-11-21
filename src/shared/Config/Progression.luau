--!strict
-- เลเวลร้าน (จาก Reputation) และการปลดล็อกสูตร

local Progression = {
	-- Reputation สะสมที่ต้องมีเพื่อถึงเลเวลนั้น (index = เลเวล)
	LevelReputation = { 0, 100, 250, 500, 900, 1400, 2000, 2800, 3800, 5000 },
	RecipeUnlockLevel = {
		CloudBread = 1,
		Croissant = 2,
		StrawberryCake = 3,
	} :: { [string]: number },
	-- ลำดับแสดงผลสูตร/วัตถุดิบใน UI
	RecipeOrder = { "CloudBread", "Croissant", "StrawberryCake" },
	IngredientOrder = { "Wheat", "StarMilk", "Strawberry" },
}

return Progression
