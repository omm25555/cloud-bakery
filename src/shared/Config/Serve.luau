--!strict
-- ค่าตั้งของระบบเสิร์ฟ (ServeService / ServeController): ที่เคาน์เตอร์ ลูกค้า ออเดอร์ รางวัล และ UI ฝั่ง client
-- ราคาขนมอ่านจาก Config/Recipes.luau (SellPrice) ตัวเลขทั้งหมดเป็นค่าชั่วคราว รอปรับบาลานซ์

export type StationSpec = {
	Name: string,
	Size: Vector3,
	Color: Color3,
	Material: Enum.Material,
	SpawnOffsetXZ: Vector2, -- ระยะจาก SpawnLocation ในแกน X/Z (studs)
	FallbackXZ: Vector2, -- ตำแหน่ง X/Z เมื่อไม่มี SpawnLocation หรือทับสถานีอื่น
}

export type HeartTier = {
	MinRatio: number, -- สัดส่วนเวลาที่เหลือตอนเสิร์ฟ (0-1) อย่างน้อยเท่านี้ได้หัวใจระดับนี้
	Hearts: number,
}

local Counter: StationSpec = {
	Name = "OrderCounter",
	Size = Vector3.new(12, 4, 4),
	Color = Color3.fromRGB(245, 170, 190),
	Material = Enum.Material.Wood,
	SpawnOffsetXZ = Vector2.new(-30, -4),
	FallbackXZ = Vector2.new(-30, -4),
}

local ServingTable: StationSpec = {
	Name = "ServingTable",
	Size = Vector3.new(8, 3, 6),
	Color = Color3.fromRGB(255, 200, 215),
	Material = Enum.Material.Fabric,
	SpawnOffsetXZ = Vector2.new(-30, 10),
	FallbackXZ = Vector2.new(-30, 10),
}

-- จำนวนช่องยืน = จำนวนรายการ (ลูกค้า 1 ตัวต่อ 1 ช่อง) วางหน้าเคาน์เตอร์
local Seats: { StationSpec } = {
	{
		Name = "Seat1",
		Size = Vector3.new(4, 0.4, 4),
		Color = Color3.fromRGB(255, 235, 200),
		Material = Enum.Material.SmoothPlastic,
		SpawnOffsetXZ = Vector2.new(-22, -8),
		FallbackXZ = Vector2.new(-22, -8),
	},
	{
		Name = "Seat2",
		Size = Vector3.new(4, 0.4, 4),
		Color = Color3.fromRGB(255, 235, 200),
		Material = Enum.Material.SmoothPlastic,
		SpawnOffsetXZ = Vector2.new(-22, -4),
		FallbackXZ = Vector2.new(-22, -4),
	},
	{
		Name = "Seat3",
		Size = Vector3.new(4, 0.4, 4),
		Color = Color3.fromRGB(255, 235, 200),
		Material = Enum.Material.SmoothPlastic,
		SpawnOffsetXZ = Vector2.new(-22, 0),
		FallbackXZ = Vector2.new(-22, 0),
	},
}

-- หัวใจความพอใจ: เรียงจากสูงไปต่ำ (ตัวสุดท้ายต้องมี MinRatio = 0)
local HeartTiers: { HeartTier } = {
	{ MinRatio = 2 / 3, Hearts = 3 },
	{ MinRatio = 1 / 3, Hearts = 2 },
	{ MinRatio = 0, Hearts = 1 },
}

return {
	-- สถานีในโลก (สร้างจากโค้ดใน Workspace.ServeStations)
	FolderName = "ServeStations",
	KindAttribute = "StationKind",
	SeatIndexAttribute = "SeatIndex",
	KindCounter = "Counter",
	KindTable = "ServingTable",
	KindSeat = "Seat",
	Counter = Counter,
	ServingTable = ServingTable,
	Seats = Seats,
	FallbackGroundY = 0, -- ระดับพื้นเมื่อใช้พิกัดสำรอง
	ClearanceStuds = 4, -- ระยะเว้นจากแปลงฟาร์ม โต๊ะผสม และเตาอบ

	-- ระยะกด (studs) server ยอมให้เกินได้เท่า DistanceTolerance เผื่อ lag
	InteractDistance = 14,
	DistanceTolerance = 6,

	-- ลูกค้า/ออเดอร์ (ของรวมบนเกาะ ไม่ปรับตามจำนวนผู้เล่น)
	MaxCustomers = 3, -- ไม่เกินจำนวน Seats
	FirstSpawnDelaySeconds = 3,
	SpawnIntervalMin = 8,
	SpawnIntervalMax = 15,
	ItemsPerOrderMin = 1,
	ItemsPerOrderMax = 3,
	RecipeIds = { "CloudBread", "Croissant", "StrawberryCake" } :: { string },
	OrderTimeSeconds = 180,
	WarnSecondsBeforeExpire = 30,

	-- รางวัล: เหรียญ = SellPrice x จำนวน x ตัวคูณตามหัวใจ (ปัดเป็นจำนวนเต็ม)
	HeartTiers = HeartTiers,
	HeartCoinMultiplier = { [1] = 1.0, [2] = 1.25, [3] = 1.5 } :: { [number]: number },
	ReputationBase = 1,
	ReputationHeartBonus = { [1] = 0, [2] = 1, [3] = 2 } :: { [number]: number },
	ExpirePenaltyReputation = 0, -- หักจากผู้เล่นทุกคนบนเกาะเมื่อออเดอร์หมดเวลา (0 = ไม่หัก)

	-- server: รอข้อมูลผู้เล่นโหลดก่อนส่ง snapshot
	SyncWaitSeconds = 30,
	SyncPollSeconds = 0.25,

	-- client
	ClientWaitSeconds = 15,
	UiRefreshSeconds = 0.25,
	PromptHoldSeconds = 0,
	PromptKeyCode = Enum.KeyCode.E,
	FadeSeconds = 0.5,
	CustomerHeadSize = 2,
	CustomerHeadOffsetStuds = 0.5,
	BubbleWidthPixels = 200,
	BubbleHeightPixels = 84,
	BubbleOffsetStuds = 3,
	BubbleMaxDistanceStuds = 80,
	BubbleTextSize = 18,
	BubbleBackgroundTransparency = 0.2,
	BubbleBackgroundColor = Color3.fromRGB(255, 245, 235),
	BubbleTextColor = Color3.fromRGB(60, 40, 70),
	BubbleCornerRadiusPixels = 12,
	NameTagHeightPixels = 22,
	HeartFull = "♥",
	HeartEmpty = "♡",
	UrgentColor = Color3.fromRGB(200, 60, 70),
	UrgentSeconds = 30,
	Font = Enum.Font.GothamMedium,
	TextColor = Color3.fromRGB(255, 255, 255),

	GuiName = "ServeGui",
	GuiDisplayOrder = 12,
	CurrencyWidthPixels = 180,
	CurrencyOffsetPixels = 12,
	CurrencyTextSize = 20,
	CurrencyBackgroundColor = Color3.fromRGB(40, 30, 60),
	CurrencyBackgroundTransparency = 0.25,
	CurrencyPaddingPixels = 8,
	CornerRadiusPixels = 10,
}
