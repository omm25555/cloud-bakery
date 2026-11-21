--!strict
-- ค่าตั้งของแปลงปลูก (FarmService / FarmController) และความจุกระเป๋า
-- ใช้ Config/Crops.luau สำหรับเวลาโตและจำนวนที่ได้

export type PlotConfig = {
	Position: Vector3,
}

local Plots: { PlotConfig } = {
	{ Position = Vector3.new(-10, 0.5, 12) },
	{ Position = Vector3.new(0, 0.5, 12) },
	{ Position = Vector3.new(10, 0.5, 12) },
	{ Position = Vector3.new(-10, 0.5, 22) },
	{ Position = Vector3.new(0, 0.5, 22) },
	{ Position = Vector3.new(10, 0.5, 22) },
}

return {
	-- แปลงในโลก (สร้างจากโค้ดใน Workspace.FarmPlots)
	Plots = Plots,
	PlotSize = Vector3.new(8, 1, 8),
	PlotColor = Color3.fromRGB(121, 85, 61),
	PlotMaterial = Enum.Material.Ground,
	FolderName = "FarmPlots",
	PlotIdAttribute = "PlotId",
	PlotNamePrefix = "Plot",

	-- ระยะกดแปลง (studs) server ยอมให้เกินได้เท่า DistanceTolerance เผื่อ lag
	InteractDistance = 12,
	DistanceTolerance = 6,

	-- ปลูก/เก็บ
	PlantCost = 0, -- เหรียญต่อการปลูกหนึ่งครั้ง (0 = ปลูกฟรี)
	OnlyPlanterCanHarvest = false, -- true = เฉพาะคนปลูกเก็บได้ (ถ้าผู้ปลูกออกจากเซิร์ฟเวอร์แล้ว ใครก็เก็บได้)

	-- กระเป๋า: จำนวนรวมทุกชนิดไม่เกินค่านี้
	InventoryCapacity = 50,

	-- ลำดับพืชที่แสดงในแถบเลือก (ตัวแรกเป็นค่าเริ่มต้น)
	CropOrder = { "Wheat", "StarMilk", "Strawberry" },

	-- server: รอข้อมูลผู้เล่นโหลดก่อนส่ง snapshot ให้ client
	SyncWaitSeconds = 30,

	-- client
	ClientWaitSeconds = 15,
	UiRefreshSeconds = 0.25,
	PromptHoldSeconds = 0,
	PromptKeyCode = Enum.KeyCode.E,
	LabelWidthPixels = 180,
	LabelHeightPixels = 56,
	LabelOffsetStuds = 3,
	LabelMaxDistanceStuds = 60,
	LabelTextSize = 18,
	LabelBackgroundTransparency = 0.25,
	LabelBackgroundColor = Color3.fromRGB(40, 30, 60),
	LabelCornerRadiusPixels = 10,
	Font = Enum.Font.GothamMedium,
	StateColors = {
		Empty = Color3.fromRGB(220, 220, 230),
		Growing = Color3.fromRGB(255, 220, 120),
		Ready = Color3.fromRGB(140, 235, 160),
	},
	TextColor = Color3.fromRGB(255, 255, 255),

	GuiName = "FarmGui",
	GuiDisplayOrder = 10,
	CropBarBottomOffsetPixels = 16,
	CropButtonWidthPixels = 110,
	CropButtonHeightPixels = 40,
	CropButtonSpacingPixels = 8,
	CropButtonTextSize = 18,
	CropButtonColor = Color3.fromRGB(80, 70, 120),
	CropButtonSelectedColor = Color3.fromRGB(90, 170, 120),
	InventoryWidthPixels = 200,
	InventoryOffsetPixels = 12,
	InventoryTextSize = 18,
	InventoryBackgroundTransparency = 0.25,
	InventoryBackgroundColor = Color3.fromRGB(40, 30, 60),
	InventoryPaddingPixels = 8,
	CornerRadiusPixels = 10,
}
