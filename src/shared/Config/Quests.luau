--!strict
-- ค่าตั้งของ Daily Quest (QuestService / QuestPanelController / QuestRules)
-- เควสตายตัว 3 ข้อทุกวัน ตัวเลขเป้าหมาย/รางวัลเป็นค่าชั่วคราว รอบาลานซ์เฟส 8
-- ห้ามใส่สวิตช์ทดสอบ/โกงในไฟล์นี้ ถ้าแก้ DayLengthSeconds หรือ ResetOffsetSeconds เพื่อทดสอบในเครื่อง ต้องคืนค่าก่อน merge

export type Kind = "Harvest" | "Bake" | "Serve"

export type QuestConfig = {
	Id: string,
	Kind: Kind,
	ItemId: string?, -- nil = นับทุกไอเท็มของ Kind นี้ (เก็บ: id วัตถุดิบ, อบ/เสิร์ฟ: id สูตร)
	Target: number,
	RewardCoins: number,
	RewardReputation: number,
	NameKey: string, -- key ใน Strings (ใช้ {target})
}

local Kinds = {
	Harvest = "Harvest",
	Bake = "Bake",
	Serve = "Serve",
} :: { [string]: string }

local List: { QuestConfig } = {
	{
		Id = "HarvestWheat",
		Kind = "Harvest",
		ItemId = "Wheat",
		Target = 30,
		RewardCoins = 60,
		RewardReputation = 0,
		NameKey = "QuestHarvestWheat",
	},
	{
		Id = "BakeCloudBread",
		Kind = "Bake",
		ItemId = "CloudBread",
		Target = 10,
		RewardCoins = 100,
		RewardReputation = 3,
		NameKey = "QuestBakeCloudBread",
	},
	{
		Id = "ServeOrders",
		Kind = "Serve",
		ItemId = nil,
		Target = 8,
		RewardCoins = 150,
		RewardReputation = 5,
		NameKey = "QuestServeOrders",
	},
}

local ById: { [string]: QuestConfig } = {}
for _, quest in List do
	ById[quest.Id] = quest
end

return {
	Kinds = Kinds,
	List = List,
	ById = ById,

	-- วัน: รีเซ็ตเที่ยงคืนเวลาไทย (UTC+7) คำนวณจาก os.time() ของ server เท่านั้น
	DayLengthSeconds = 86400,
	ResetOffsetSeconds = 25200,
	-- ตอนโหลดข้อมูล: Day ที่เกินวันปัจจุบันเกินกี่วันถือว่าเสีย (เผื่อนาฬิกาเซิร์ฟเวอร์เหลื่อมกัน)
	MaxFutureDays = 1,

	-- server
	MaxIdLength = 32,
	MaxLogIdLength = 24,
	SyncWaitSeconds = 30,
	SyncPollSeconds = 0.5,
	TickSeconds = 15,
	SecondsPerMinute = 60,
	ExpiryWarnSeconds = 300, -- เตือนเควสที่ครบแล้วแต่ยังไม่รับ เมื่อเหลือเวลาก่อนรีเซ็ตเท่านี้

	-- client: ขอข้อมูลซ้ำ 1 ครั้งที่ LoadRetrySeconds แล้วขึ้น "โหลดไม่สำเร็จ" ที่ LoadTimeoutSeconds
	-- (LoadTimeoutSeconds ต้องมากกว่า SyncWaitSeconds ที่ server รอข้อมูลผู้เล่น)
	LoadRetrySeconds = 15,
	LoadTimeoutSeconds = 35,
	UiRefreshSeconds = 1,

	-- gui (ซ้ายบน; Farm = 10, Serve = 12, Hud = 13, Orders = 14, Upgrade = 30, Menu = 31, Notify = 100)
	GuiName = "QuestGui",
	GuiDisplayOrder = 11,
	MarginPixels = 10,
	TopOffsetPixels = 10,
	WidthScale = 0.26,
	MinWidthPixels = 200,
	MaxWidthPixels = 300,
	-- ขอบล่างสุดของแผงเป็นสัดส่วนความสูงจอ (เว้นป้ายกระเป๋าฝั่งซ้ายกลางจอของ Farm) เกินนี้ให้เลื่อน
	MaxBottomScale = 0.42,
	MinScrollHeightPixels = 50,
	PaddingPixels = 6,
	SpacingPixels = 6,
	ScrollBarThicknessPixels = 4,
	CornerRadiusPixels = 10,
	HeaderHeightPixels = 40,
	ToggleSizePixels = 22,
	CollapseGlyph = "-",
	ExpandGlyph = "+",
	TitleTextSize = 15,
	TimerTextSize = 12,
	StatusHeightPixels = 40,
	StatusTextSize = 14,

	-- แถวเควส
	RowHeightPixels = 66,
	RowCornerRadiusPixels = 8,
	RowPaddingPixels = 5,
	CheckboxSizePixels = 22,
	CheckboxGapPixels = 6,
	CheckStrokeThicknessPixels = 1,
	LineHeightPixels = 18,
	BarTopPixels = 22,
	BarHeightPixels = 8,
	ThirdLineTopPixels = 34,
	ButtonHeightPixels = 24,
	ButtonWidthScale = 0.38,
	ProgressWidthScale = 0.3,
	RowTextSize = 13,
	ButtonTextSize = 13,
	CheckGlyph = "✓",

	Font = Enum.Font.GothamMedium,
	BackgroundColor = Color3.fromRGB(40, 30, 60),
	BackgroundTransparency = 0.15,
	RowColor = Color3.fromRGB(70, 55, 100),
	TextColor = Color3.fromRGB(255, 255, 255),
	SubTextColor = Color3.fromRGB(215, 205, 235),
	ToggleColor = Color3.fromRGB(120, 100, 180),
	BarBackgroundColor = Color3.fromRGB(45, 35, 70),
	BarFillColor = Color3.fromRGB(255, 210, 70),
	CheckEmptyColor = Color3.fromRGB(45, 35, 70),
	CheckDoneColor = Color3.fromRGB(90, 170, 120),
	ClaimEnabledColor = Color3.fromRGB(90, 170, 120),
	ClaimDisabledColor = Color3.fromRGB(110, 110, 120),
	FailColor = Color3.fromRGB(255, 190, 190),
}
