--!strict
-- ค่าตั้งของระบบรายงานผู้จัดการร้าน (ReportService / ReportMenuController / ManagerController / NightFlowService)
-- ตัวเลขทั้งหมดเป็นค่าชั่วคราว รอปรับบาลานซ์ใน TASK-025 บทพูดผู้จัดการอยู่ใน Config/ManagerLines

export type HauntStyle = {
	Seconds: number, -- เวลาแสดงท่าทั้งหมด (รวมช่วงกลับเป็นปกติ)
	TurnSeconds: number, -- เวลาหันหัวมามองผู้เล่นช้าๆ
	MaxYawDegrees: number, -- หันหัวได้มากสุดกี่องศาจากทิศเดิม
	TiltDegrees: number, -- เอียงหัวค้าง
	MouthScaleX: number, -- ขยายปากแนวกว้าง (1 = ปกติ)
	MouthScaleY: number,
	EyeScale: number, -- ขยายตา (1 = ปกติ)
	ShakeStuds: number, -- สั่นเล็กน้อย (0 = นิ่ง)
}

local HauntStyles: { HauntStyle } = {
	{ Seconds = 4, TurnSeconds = 2.5, MaxYawDegrees = 80, TiltDegrees = 0, MouthScaleX = 1, MouthScaleY = 1, EyeScale = 1, ShakeStuds = 0 },
	{ Seconds = 5, TurnSeconds = 2, MaxYawDegrees = 80, TiltDegrees = 0, MouthScaleX = 1.6, MouthScaleY = 1.2, EyeScale = 1.1, ShakeStuds = 0.04 },
	{ Seconds = 6, TurnSeconds = 1.5, MaxYawDegrees = 80, TiltDegrees = 22, MouthScaleX = 2.4, MouthScaleY = 1.6, EyeScale = 1.7, ShakeStuds = 0.06 },
}

return {
	-- ผู้จัดการในโลก (สร้างจากโค้ดใน Workspace ตำแหน่งอิง SpawnLocation เหมือน ServeService)
	ManagerModelName = "ShopManager",
	ManagerPromptName = "ReportPrompt",
	SpawnOffsetXZ = Vector2.new(-30, 20),
	FallbackXZ = Vector2.new(-30, 20),
	FallbackGroundY = 0,
	FacingDirection = Vector3.new(1, 0, 0), -- ทิศที่ผู้จัดการหันหน้า
	BodySize = Vector3.new(4, 4.4, 4),
	BodyColor = Color3.fromRGB(255, 220, 230),
	HeadSize = 2.8,
	HeadColor = Color3.fromRGB(255, 235, 220),
	HeadOverlapStuds = 0.7, -- หัวซ้อนบนตัวเท่านี้
	EyeSize = Vector3.new(0.5, 0.6, 0.3),
	EyeColor = Color3.fromRGB(40, 30, 50),
	EyeOffset = Vector3.new(0.6, 0.25, -1.3), -- เทียบจุดกึ่งกลางหัว (ตาซ้ายใช้ X ติดลบ)
	MouthSize = Vector3.new(1, 0.2, 0.3),
	MouthColor = Color3.fromRGB(230, 90, 120),
	MouthOffset = Vector3.new(0, -0.55, -1.35),
	HatSize = Vector3.new(2.2, 1.3, 2.2),
	HatColor = Color3.fromRGB(255, 255, 255),
	HatOffsetY = 1.8,

	-- รายงาน (ระยะ studs เวลา วินาที)
	PromptDistance = 10,
	PromptKeyCode = Enum.KeyCode.E,
	PromptHoldSeconds = 0,
	ReportMaxDistance = 12,
	DistanceTolerance = 6,
	ReportCooldownSeconds = 2,
	MenuSessionSeconds = 30, -- เมนูที่เปิดค้างหมดอายุที่ server
	SessionCheckSeconds = 0.5,
	MaxPayloadStringLength = 32,
	CustomerMenuMax = 6,

	-- รางวัล (เฉพาะผู้รายงานที่ถูก) เหรียญ = CoinReward + CoinPerSubtlety x Subtlety ต่อ anomaly ที่แก้ได้
	CoinReward = 50,
	CoinPerSubtlety = 10,
	RecipeProgressPerCorrect = 1, -- ตัวนับความคืบหน้าสูตรต่อ anomaly ที่รายงานถูก (หน้าสูตรจริงเป็น TASK-018)

	-- ผิดซ้ำ: จำนวนครั้งที่ผิดในคืนนั้นที่ถึงระดับ 1..N (เรียงจากน้อยไปมาก ตัวแรกต้องเป็น 1) ผิดเกินตัวสุดท้ายใช้ระดับสูงสุด
	WrongHauntLevels = { 1, 2, 3 } :: { number },
	HauntStyles = HauntStyles,
	PraiseHopSeconds = 1.2,
	PraiseHops = 2,
	PraiseHopStuds = 1.2,
	PraiseEyeScaleY = 0.35,
	PraiseMouthScaleX = 1.5,
	ReturnSeconds = 0.8, -- ช่วงกลับเป็นปกติท้ายท่า
	BubbleSeconds = 5,
	BubbleWidthPixels = 220,
	BubbleHeightPixels = 70,
	BubbleOffsetStuds = 3,
	BubbleTextSize = 18,
	BubbleBackgroundColor = Color3.fromRGB(255, 245, 235),
	BubbleTextColor = Color3.fromRGB(60, 40, 70),
	BubbleCornerRadiusPixels = 12,

	-- จบคืนเร็วเมื่อลูกค้ากลางคืนครบ
	EndNightCountdownSeconds = 10,
	CountdownAttribute = "NightEndCountdownEndsAt", -- ReplicatedStorage เวลา server ที่คืนจะจบ (nil = ไม่มีการนับถอยหลัง)

	-- attributes ที่ server ตั้งบนโมเดลผู้จัดการให้ทุก client เล่นท่าเดียวกัน
	ReactionSeqAttribute = "ReactionSeq",
	ReactionKindAttribute = "ReactionKind",
	ReactionLevelAttribute = "ReactionLevel",
	ReactionUserIdAttribute = "ReactionUserId",

	-- เครื่องมือ Studio (เฉพาะ RunService:IsStudio()): attribute บน ServerStorage ตั้งเป็น true = ทำให้ roster ครบทันที แล้วล้างค่า
	DebugRosterCompleteAttribute = "NightDebugRosterComplete",

	-- client: เมนูรายงาน (modal กลางจอ สูงไม่เกิน 60% ไม่ทับแถบเลือกเมล็ดล่างจอ)
	MenuGuiName = "ReportGui",
	MenuGuiDisplayOrder = 25,
	CategoryIcons = {
		customer = "🧸",
		oven = "🔥",
		farm = "🌾",
		shop = "🏪",
		sky = "🌙",
		sound = "🔊",
	} :: { [string]: string },
	DefaultIcon = "❓",
	PanelWidthScale = 0.85,
	PanelMaxWidthPixels = 440,
	PanelHeightScale = 0.6,
	PanelMaxHeightPixels = 320,
	PanelPaddingPixels = 8,
	PanelCornerRadiusPixels = 14,
	PanelColor = Color3.fromRGB(255, 245, 235),
	ButtonColor = Color3.fromRGB(245, 170, 190),
	ButtonTextColor = Color3.fromRGB(60, 40, 70),
	CloseColor = Color3.fromRGB(200, 90, 100),
	CloseTextColor = Color3.fromRGB(255, 255, 255),
	TitleHeightPixels = 40,
	LineHeightPixels = 34,
	FooterHeightPixels = 40,
	GridColumns = 3,
	GridGapPixels = 8,
	ButtonMinHeightPixels = 64, -- ปุ่มใหญ่พอแตะบนมือถือ
	CustomerButtonHeightPixels = 84, -- ปุ่มลูกค้า (รูป + ชื่อ)

	-- จอเตี้ย (ความสูง viewport ต่ำกว่าค่านี้ เช่นมือถือแนวนอน 640x360): แผงสูงขึ้นแต่ไม่เกินจอ บีบหัว/ท้าย/ปุ่มให้เตี้ยลง
	CompactViewportHeightPixels = 480,
	CompactPanelHeightScale = 0.92,
	CompactPanelMaxHeightPixels = 360,
	CompactPanelPaddingPixels = 6,
	CompactTitleHeightPixels = 24,
	CompactLineHeightPixels = 22,
	CompactFooterHeightPixels = 34,
	CompactGridGapPixels = 6,
	CompactButtonMinHeightPixels = 44,
	CompactCustomerButtonHeightPixels = 76,

	-- รูปลูกค้าในเมนู (ViewportFrame โคลนโมเดลลูกค้าที่ ServeController สร้างฝั่ง client)
	CustomerFolderName = "ServeCustomers",
	CustomerViewportHeightScale = 0.66, -- สัดส่วนความสูงปุ่มที่เป็นรูป ส่วนที่เหลือเป็นชื่อ
	CustomerViewportDistanceFactor = 1.6, -- ระยะกล้อง = ขนาดโมเดล x ค่านี้
	CustomerViewportBackgroundColor = Color3.fromRGB(255, 225, 235),
	CustomerViewportLightColor = Color3.fromRGB(255, 255, 255),
	CustomerViewportAmbientColor = Color3.fromRGB(200, 190, 210),
	Font = Enum.Font.GothamMedium,
	MaxTextSize = 20,
	MinTextSize = 8,

	-- client: นับถอยหลังจบคืน (ใต้แถบสติ)
	CountdownGuiName = "NightCountdownGui",
	CountdownGuiDisplayOrder = 17,
	CountdownGapPixels = 6,
	CountdownWidthScale = 0.3,
	CountdownMinWidthPixels = 150,
	CountdownMaxWidthPixels = 220,
	CountdownHeightPixels = 30,
	CountdownCornerRadiusPixels = 10,
	CountdownBackgroundColor = Color3.fromRGB(120, 100, 180),
	CountdownBackgroundTransparency = 0.1,
	CountdownTextColor = Color3.fromRGB(255, 255, 255),
	CountdownRefreshSeconds = 0.2,
}
