--!strict
-- ค่าตั้งของระบบแจ้งเตือนกลาง (toast)

export type Kind = "info" | "success" | "error"

export type Payload = {
	Key: string,
	Kind: Kind,
	Language: string,
	Args: { [string]: string | number }?,
}

return {
	Kinds = { info = true, success = true, error = true } :: { [string]: boolean },

	-- server
	MaxPendingPerPlayer = 10,
	MaxArgCount = 8,
	MaxArgLength = 64,

	-- client: toast อยู่กลางบนจอ ไม่บัง HUD ขวาบน/ขวาล่าง
	DisplaySeconds = 4,
	FadeSeconds = 0.3,
	MaxVisible = 3,
	DisplayOrder = 100,
	WidthMaxPixels = 380,
	WidthScale = 0.9,
	TopOffsetPixels = 12,
	SpacingPixels = 6,
	PaddingPixels = 10,
	CornerRadiusPixels = 12,
	TextSize = 20,
	BackgroundTransparency = 0.05,
	Font = Enum.Font.GothamMedium,
	TextColor = Color3.fromRGB(255, 255, 255),
	Colors = {
		info = Color3.fromRGB(120, 100, 180),
		success = Color3.fromRGB(90, 170, 120),
		error = Color3.fromRGB(200, 90, 100),
	},
}
