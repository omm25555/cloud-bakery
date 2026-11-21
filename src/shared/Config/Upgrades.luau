--!strict
-- อัปเกรด 3 สาย: สวน (ผลผลิต), เตาอบ (ความเร็ว + ช่องอบ), หน้าร้าน (ทิป)

export type UpgradeLine = {
	Id: string,
	Costs: { number }, -- ราคาเพื่อไปเลเวลถัดไป (index = เลเวลปัจจุบัน + 1)
}

local Upgrades = {
	Order = { "Garden", "Oven", "Counter" },
	Lines = {
		Garden = { Id = "Garden", Costs = { 150, 400, 900, 1800, 3500 } },
		Oven = { Id = "Oven", Costs = { 200, 500, 1100, 2200, 4000 } },
		Counter = { Id = "Counter", Costs = { 250, 600, 1300, 2600, 4500 } },
	} :: { [string]: UpgradeLine },

	-- ผลของแต่ละสาย
	GardenYieldBonusPerLevel = 1,
	OvenSpeedBonusPerLevel = 0.12, -- ลดเวลาอบ 12% ต่อเลเวล
	OvenMinTimeMultiplier = 0.4,
	OvenBaseSlots = 2,
	OvenExtraSlotAtLevels = { 2, 4 },
	CounterTipBonusPerLevel = 0.1, -- เหรียญจากการเสิร์ฟเพิ่ม 10% ต่อเลเวล
}

return Upgrades
