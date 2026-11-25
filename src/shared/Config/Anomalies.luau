--!strict
-- ค่าตั้งของระบบ anomaly (AnomalyService / AnomalyRules) ตัวเลขทั้งหมดของระบบนี้อยู่ที่นี่
-- เพิ่ม anomaly ใหม่ = เพิ่ม Entry ใน Entries + ไฟล์พฤติกรรม src/server/Anomalies/<Id>.luau (ไม่ต้องแก้ AnomalyService)
-- Subtlety สเกล 1-5: 1 = เห็นชัดมาก, 5 = แนบเนียนมาก
-- ค่า Hard/Nightmare เป็นค่าชั่วคราว รอปรับบาลานซ์ใน TASK-025

export type NightType = "Normal" | "Anomaly"

export type Params = {
	Color: Color3?, -- สีที่เปลี่ยนไป
	OffsetStuds: Vector3?, -- ระยะที่ย้ายจากตำแหน่งเดิม (studs)
}

export type Entry = {
	Id: string,
	NameKey: string, -- key ใน Config/Strings
	Category: string, -- ต้องอยู่ใน Categories
	Weight: number, -- > 0 ยิ่งมากยิ่งถูกสุ่มบ่อย
	Subtlety: number, -- > 0 (สเกล 1-5)
	Folder: string, -- ชื่อ Folder ใน Workspace ที่เป้าหมายอยู่
	Targets: { string }, -- ชื่อเป้าหมายใน Folder (สุ่มเลือก 1 ต่อการเกิด)
	Params: Params,
}

export type ModeSettings = {
	NightTypeWeights: { [string]: number }, -- ชนิดคืน -> weight (>= 0, รวม > 0)
	MaxSubtlety: number, -- anomaly ที่ Subtlety สูงกว่านี้ไม่ออกในโหมดนี้
	AnomaliesMin: number, -- จำนวน anomaly ต่อคืน anomaly (จำนวนเต็ม >= 1)
	AnomaliesMax: number,
	SpawnWindowMin: number, -- ช่วงเวลาเกิด เป็นสัดส่วน 0-1 ของเวลาคืนที่นับจริง
	SpawnWindowMax: number,
}

export type NightCustomers = {
	BaseMin: number, -- จำนวนลูกค้ากลางคืนต่ำสุด/สูงสุดของคืนแรก
	BaseMax: number,
	GrowthEveryNights: number, -- ทุกกี่คืนเพิ่มหนึ่งครั้ง
	GrowthAmount: number, -- เพิ่มครั้งละเท่าไร (ทั้ง Min และ Max)
	HardMin: number, -- เพดานล่าง/บนของจำนวนลูกค้า
	HardMax: number,
}

local Categories: { string } = { "customer", "oven", "farm", "shop", "sky", "sound" }

local Entries: { Entry } = {
	{
		Id = "ColorShift",
		NameKey = "AnomalyNameColorShift",
		Category = "shop",
		Weight = 10,
		Subtlety = 2,
		Folder = "ServeStations",
		Targets = { "OrderCounter", "ServingTable" },
		Params = { Color = Color3.fromRGB(200, 90, 255) },
	},
	{
		Id = "Relocate",
		NameKey = "AnomalyNameRelocate",
		Category = "shop",
		Weight = 6,
		Subtlety = 2,
		Folder = "ServeStations",
		Targets = { "Seat1", "Seat2", "Seat3" },
		Params = { OffsetStuds = Vector3.new(0, 0, 3) },
	},
}

local Modes: { [string]: ModeSettings } = {
	Easy = {
		NightTypeWeights = { Normal = 65, Anomaly = 35 },
		MaxSubtlety = 2,
		AnomaliesMin = 1,
		AnomaliesMax = 1,
		SpawnWindowMin = 0.1,
		SpawnWindowMax = 0.6,
	},
	Hard = {
		NightTypeWeights = { Normal = 45, Anomaly = 55 },
		MaxSubtlety = 4,
		AnomaliesMin = 1,
		AnomaliesMax = 2,
		SpawnWindowMin = 0.1,
		SpawnWindowMax = 0.7,
	},
	Nightmare = {
		NightTypeWeights = { Normal = 25, Anomaly = 75 },
		MaxSubtlety = 5,
		AnomaliesMin = 2,
		AnomaliesMax = 3,
		SpawnWindowMin = 0.05,
		SpawnWindowMax = 0.8,
	},
}

local NightCustomersConfig: NightCustomers = {
	BaseMin = 1,
	BaseMax = 3,
	GrowthEveryNights = 3,
	GrowthAmount = 1,
	HardMin = 1,
	HardMax = 5,
}

-- ใช้เมื่อ NightCustomers ข้างบนไม่ผ่านการตรวจ
local NightCustomersFallback: NightCustomers = {
	BaseMin = 1,
	BaseMax = 3,
	GrowthEveryNights = 3,
	GrowthAmount = 1,
	HardMin = 1,
	HardMax = 5,
}

return {
	Categories = Categories,
	Entries = Entries,
	Modes = Modes,
	DefaultMode = "Easy", -- ใช้เมื่อโหมดจาก DayNightService ไม่มีในตาราง Modes (และเป็นค่าสำรองเมื่อค่าโหมดผิด)
	NightTypes = { "Normal", "Anomaly" } :: { NightType },
	GuaranteedNormalNights = 1, -- คืนที่ 1..N เป็นคืนปกติเสมอ (0 = ปิด)
	NightCustomers = NightCustomersConfig,
	NightCustomersFallback = NightCustomersFallback,
	FolderName = "AnomalyProps", -- Folder ใน Workspace ที่เก็บของที่ anomaly สร้างเพิ่ม
	SpawnPollSeconds = 0.5, -- ความถี่ตรวจเวลาเกิดของ anomaly
	-- เครื่องมือทดสอบ (attribute บน ServerStorage ใช้เฉพาะ RunService:IsStudio())
	ForceNightAttribute = "AnomalyForceNight", -- "Anomaly" | "Normal"
	ForceIdsAttribute = "AnomalyForceIds", -- id คั่นด้วย comma เกิดทันทีตอนเริ่มคืน
	DebugHandleAttribute = "AnomalyDebugHandle", -- จำนวนลูกค้าที่ให้ถือว่าเสิร์ฟแล้ว (ล้างค่าหลังใช้)
}
