--!strict
-- ค่าตั้งของ lobby และการ teleport ไปเกาะ

return {
	-- กลุ่ม/นับถอยหลัง
	MaxGroupSize = 4,
	MinGroupSize = 1,
	CountdownSeconds = 15,
	FullGroupCountdownSeconds = 5,
	TickSeconds = 1,

	-- teleport
	TeleportRetries = 2,
	RetryDelaySeconds = 2,
	TeleportSettleSeconds = 10,
	TeleportDataVersion = 1,
	MaxGroupIdLength = 64,

	-- โลกของ lobby (สร้างจากสคริปต์ตอนรัน)
	FloorSize = Vector3.new(160, 1, 120),
	FloorPosition = Vector3.new(0, -0.5, 0),
	FloorColor = Color3.fromRGB(235, 214, 180),
	SpawnSize = Vector3.new(12, 1, 12),
	SpawnPosition = Vector3.new(0, 0.5, 35),
	PadCount = 4,
	PadSize = Vector3.new(14, 1, 14),
	PadSpacing = 24,
	PadBasePosition = Vector3.new(0, 0.5, -10),
	PadColor = Color3.fromRGB(255, 170, 90),
	PadLabelSize = UDim2.fromOffset(120, 40),
	PadLabelOffset = Vector3.new(0, 4, 0),
	PadLabelTextSize = 28,
	PadLabelTextColor = Color3.fromRGB(255, 255, 255),
	PromptHoldSeconds = 0.3,
	PromptMaxDistance = 10,

	-- UI ฝั่ง client
	UiDisplayOrder = 50,
	UiWidthPixels = 260,
	UiBottomOffsetPixels = 24,
	UiPaddingPixels = 10,
	UiCornerRadiusPixels = 10,
	UiBackgroundColor = Color3.fromRGB(40, 30, 25),
	UiBackgroundTransparency = 0.2,
	UiTextColor = Color3.fromRGB(255, 245, 230),
	UiTitleTextSize = 20,
	UiBodyTextSize = 16,
	UiCountdownTextSize = 24,
	UiFont = Enum.Font.GothamMedium,
	UiSpacingPixels = 6,
}
