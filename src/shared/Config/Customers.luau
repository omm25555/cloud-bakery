--!strict
-- ลูกค้าสัตว์และออเดอร์

export type AnimalConfig = {
	Id: string,
	BodyColor: Color3,
	AccentColor: Color3,
	EarShape: "Round" | "Pointy" | "Long",
}

local Customers = {
	Order = { "Panda", "Fox", "Bunny" },
	Animals = {
		Panda = {
			Id = "Panda",
			BodyColor = Color3.fromRGB(250, 250, 250),
			AccentColor = Color3.fromRGB(45, 45, 50),
			EarShape = "Round",
		},
		Fox = {
			Id = "Fox",
			BodyColor = Color3.fromRGB(240, 150, 80),
			AccentColor = Color3.fromRGB(255, 245, 235),
			EarShape = "Pointy",
		},
		Bunny = {
			Id = "Bunny",
			BodyColor = Color3.fromRGB(255, 250, 252),
			AccentColor = Color3.fromRGB(255, 190, 210),
			EarShape = "Long",
		},
	} :: { [string]: AnimalConfig },

	FirstSpawnDelaySeconds = 6,
	SpawnIntervalSeconds = 22,
	MaxActiveOrders = 3,
	PatienceMinSeconds = 150,
	PatienceMaxSeconds = 240,
	AmountRange = {
		CloudBread = { 1, 3 },
		Croissant = { 1, 2 },
		StrawberryCake = { 1, 2 },
	} :: { [string]: { number } },

	HeartCount = 3,
	-- ตัวคูณเหรียญตามจำนวนหัวใจที่เหลือตอนเสิร์ฟ (index = หัวใจ)
	HeartCoinMultiplier = { 0.8, 1.0, 1.25 },
	ReputationPerItem = 10,

	WalkSpeedStudsPerSecond = 9,
	LeaveDelaySeconds = 1.5,
}

return Customers
