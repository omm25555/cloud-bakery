--!strict
-- ค่าตั้งของระบบอบ (BakeService / BakeController): โต๊ะผสม เตาอบ มินิเกมจังหวะ และผลของคะแนน
-- สูตร วัตถุดิบ และ BakeTimeSeconds อยู่ใน Config/Recipes.luau

export type StationSpec = {
	Name: string,
	Size: Vector3,
	Color: Color3,
	Material: Enum.Material,
	SpawnOffsetXZ: Vector2, -- ระยะจาก SpawnLocation ในแกน X/Z (studs)
	FallbackXZ: Vector2, -- ตำแหน่ง X/Z เมื่อไม่มี SpawnLocation หรือทับแปลงฟาร์ม
}

local Mixing: StationSpec = {
	Name = "MixingTable",
	Size = Vector3.new(8, 4, 5),
	Color = Color3.fromRGB(205, 160, 110),
	Material = Enum.Material.Wood,
	SpawnOffsetXZ = Vector2.new(-10, -16),
	FallbackXZ = Vector2.new(-10, -16),
}

-- จำนวนเตา = จำนวนรายการในลิสต์นี้ (เตาร่วมกันทั้งเกาะ)
local Ovens: { StationSpec } = {
	{
		Name = "Oven1",
		Size = Vector3.new(6, 6, 6),
		Color = Color3.fromRGB(120, 120, 130),
		Material = Enum.Material.Metal,
		SpawnOffsetXZ = Vector2.new(4, -16),
		FallbackXZ = Vector2.new(4, -16),
	},
	{
		Name = "Oven2",
		Size = Vector3.new(6, 6, 6),
		Color = Color3.fromRGB(120, 120, 130),
		Material = Enum.Material.Metal,
		SpawnOffsetXZ = Vector2.new(14, -16),
		FallbackXZ = Vector2.new(14, -16),
	},
}

-- จำนวนขนมที่ได้ต่อการอบหนึ่งครั้งตามระดับรวม (ค่าชั่วคราว รอปรับบาลานซ์)
local ScoreRewards: { [string]: number } = {
	Perfect = 2,
	Good = 1,
	Miss = 1,
}

local JudgementColors: { [string]: Color3 } = {
	Perfect = Color3.fromRGB(110, 220, 140),
	Good = Color3.fromRGB(255, 220, 120),
	Miss = Color3.fromRGB(235, 110, 120),
}

return {
	-- สถานีในโลก (สร้างจากโค้ดใน Workspace.BakeStations)
	FolderName = "BakeStations",
	KindAttribute = "StationKind",
	OvenIdAttribute = "OvenId",
	KindMixing = "Mixing",
	KindOven = "Oven",
	Mixing = Mixing,
	Ovens = Ovens,
	FallbackGroundY = 0, -- ระดับพื้นเมื่อใช้พิกัดสำรอง
	PlotClearanceStuds = 4, -- ระยะเว้นจากแปลงฟาร์ม
	HighlightFillColor = Color3.fromRGB(255, 240, 150),
	HighlightOutlineColor = Color3.fromRGB(255, 255, 255),
	HighlightFillTransparency = 0.8,

	-- ระยะกด (studs) server ยอมให้เกินได้เท่า DistanceTolerance เผื่อ lag
	InteractDistance = 14,
	DistanceTolerance = 6,

	-- ถ้าเจ้าของออกแล้ว DataService ไม่ได้เรียก OnBeforeSave (เช่น โหมดชั่วคราว) รอเท่านี้แล้วเคลียร์เตา
	OrphanCleanupSeconds = 2,

	ScoreRewards = ScoreRewards,
	RecipeOrder = { "CloudBread", "Croissant", "StrawberryCake" },

	Minigame = {
		TapCount = 3,
		LineSpeed = 0.8, -- ความกว้างแถบต่อวินาที (เส้นวิ่งไป-กลับ)
		PerfectHalfWidth = 0.06, -- ครึ่งความกว้างโซน Perfect (สัดส่วนของแถบ 0-1)
		GoodHalfWidth = 0.15,
		ZoneMin = 0.2, -- ช่วงที่ server สุ่มกึ่งกลางโซน
		ZoneMax = 0.8,
		MinFirstTapSeconds = 0.25, -- กดครั้งแรกเร็วกว่านี้ถือว่าเป็นไปไม่ได้
		MinTapGapSeconds = 0.3, -- เว้นระยะขั้นต่ำระหว่างการกด
		MaxDurationSeconds = 12, -- หมดเวลาแล้ว server สรุปผลเอง (ครั้งที่ไม่ได้กดนับเป็น Miss)
		TimeoutGraceSeconds = 1,
		LatencyToleranceSeconds = 0.5, -- เวลาที่ client ส่งมาล้ำหน้าเวลาจริงบน server ได้เท่านี้
		MaxTapLagSeconds = 2, -- เวลาที่ client ส่งมาช้ากว่าเวลาจริงบน server เกินนี้ถือว่าเก่าเกินไป
		PerfectGradeMinPerfectTaps = 3,
		MissGradeMinMissTaps = 2,
	},

	-- client
	ClientWaitSeconds = 15,
	UiRefreshSeconds = 0.25,
	PromptHoldSeconds = 0,
	PromptKeyCode = Enum.KeyCode.E,
	TapKeyCode = Enum.KeyCode.Space,
	LabelWidthPixels = 200,
	LabelHeightPixels = 76,
	LabelOffsetStuds = 4,
	LabelMaxDistanceStuds = 70,
	LabelTextSize = 18,
	LabelBackgroundTransparency = 0.25,
	LabelBackgroundColor = Color3.fromRGB(40, 30, 60),
	LabelCornerRadiusPixels = 10,
	Font = Enum.Font.GothamMedium,
	TextColor = Color3.fromRGB(255, 255, 255),
	StateColors = {
		Idle = Color3.fromRGB(220, 220, 230),
		Baking = Color3.fromRGB(255, 220, 120),
		Ready = Color3.fromRGB(140, 235, 160),
		Minigame = Color3.fromRGB(150, 200, 255),
		Done = Color3.fromRGB(255, 190, 120),
	},

	GuiName = "BakeGui",
	GuiDisplayOrder = 20,
	CornerRadiusPixels = 10,
	MenuWidthPixels = 360,
	MenuPaddingPixels = 10,
	MenuSpacingPixels = 8,
	MenuTitleHeightPixels = 30,
	MenuButtonHeightPixels = 64,
	MenuTextSize = 18,
	MenuBackgroundColor = Color3.fromRGB(40, 30, 60),
	MenuBackgroundTransparency = 0.1,
	MenuButtonColor = Color3.fromRGB(80, 70, 120),
	MenuButtonDisabledColor = Color3.fromRGB(110, 70, 80),
	MenuCloseButtonColor = Color3.fromRGB(150, 80, 90),
	MinigameWidthPixels = 480,
	MinigameBarHeightPixels = 44,
	MinigameBottomOffsetPixels = 90,
	MinigamePaddingPixels = 12,
	MinigameSpacingPixels = 8,
	MinigameTextSize = 22,
	MinigameLineWidthPixels = 6,
	MinigameBarColor = Color3.fromRGB(70, 60, 100),
	MinigameGoodColor = Color3.fromRGB(255, 220, 120),
	MinigamePerfectColor = Color3.fromRGB(110, 220, 140),
	MinigameLineColor = Color3.fromRGB(255, 255, 255),
	TapButtonHeightPixels = 44,
	TapButtonColor = Color3.fromRGB(90, 170, 120),
	JudgementColors = JudgementColors,
}
