--!strict
-- ค่าตั้งของ HUD ขวาบน (เหรียญ/Reputation) และแผง Orders (HudController / OrdersPanelController / HudService)
-- เลเวล Reputation เป็นการแสดงผลอย่างเดียว ไม่ให้รางวัลและไม่บันทึก ตัวเลขทั้งหมดเป็นค่าชั่วคราว

local Actions = {
	ShopClick = "ShopClick",
	LevelCheck = "LevelCheck",
	LoadTimeout = "LoadTimeout",
}

return {
	-- remote HudAction (client -> server): ค่าที่ server รับได้
	Actions = Actions,
	AllowedActions = {
		[Actions.ShopClick] = true,
		[Actions.LevelCheck] = true,
		[Actions.LoadTimeout] = true,
	} :: { [string]: boolean },
	MaxActionLength = 32,
	MaxLogActionLength = 24,

	-- Reputation ขั้นต่ำของเลเวล 1..N (ตำแหน่งที่ n = เลเวล n, ตัวแรกต้องเป็น 0, เรียงจากน้อยไปมาก)
	LevelThresholds = { 0, 10, 25, 50, 90, 150, 240, 360, 520, 720 } :: { number },

	-- client: รอข้อมูลจาก server นานเกินนี้ให้แจ้งเตือน (มากกว่า Serve.SyncWaitSeconds ที่ server รอข้อมูลผู้เล่น)
	LoadTimeoutSeconds = 35,
	ShopClickCooldownSeconds = 1,

	-- ชื่อ/ลำดับ gui (Serve = 12, Farm = 10, Bake = 20, Upgrade = 30, Menu = 31, Notify = 100)
	GuiName = "HudGui",
	GuiDisplayOrder = 13,
	OrdersGuiName = "OrdersGui",
	OrdersGuiDisplayOrder = 14,

	-- ป้ายเหรียญเดิมใน ServeGui (ซ่อนทั้ง gui แล้วใช้ HUD นี้แทน)
	ServeCurrencyLabelName = "Currency",

	-- ตำแหน่ง/ขนาด HUD (ชิดขวาบน)
	MarginPixels = 10,
	WidthScale = 0.22,
	MinWidthPixels = 150,
	MaxWidthPixels = 230,
	RowSpacingPixels = 6,
	CoinRowHeightPixels = 34,
	RepRowHeightPixels = 48,
	RowPaddingPixels = 6,
	CornerRadiusPixels = 10,
	BackgroundColor = Color3.fromRGB(40, 30, 60),
	BackgroundTransparency = 0.15,
	Font = Enum.Font.GothamMedium,
	TextColor = Color3.fromRGB(255, 255, 255),
	SubTextColor = Color3.fromRGB(215, 205, 235),
	MaxTextSize = 18,
	MinTextSize = 8,
	LineTextSize = 14,

	-- เหรียญ
	CoinIconSizePixels = 22,
	CoinIconColor = Color3.fromRGB(255, 200, 60),
	PlusButtonSizePixels = 24,
	PlusButtonColor = Color3.fromRGB(90, 170, 120),
	PlusGlyph = "+",
	IconGapPixels = 6,

	-- Reputation
	StarGlyph = "★",
	StarColor = Color3.fromRGB(255, 210, 70),
	StarSizePixels = 22,
	LineHeightPixels = 22,
	BarHeightPixels = 10,
	BarBackgroundColor = Color3.fromRGB(70, 55, 100),
	BarFillColor = Color3.fromRGB(255, 210, 70),

	-- ข้อความโหลดไม่สำเร็จของ ServeController (ย้ายมาแสดงใน HUD แทน)
	FailColor = Color3.fromRGB(255, 190, 190),

	-- แผง Orders: ใต้ HUD ชิดขวา ความสูงถูกจำกัดไม่ให้ชนแถวปุ่มล่างขวา (ขนาดปุ่มอ่านจาก Config/Upgrades)
	OrdersWidthScale = 0.22,
	OrdersBottomGapPixels = 8,
	OrdersMinScrollHeightPixels = 50,
	OrdersHeaderHeightPixels = 28,
	OrdersPaddingPixels = 6,
	OrdersSpacingPixels = 6,
	OrdersScrollBarThicknessPixels = 4,
	OrdersToggleSizePixels = 22,
	OrdersToggleColor = Color3.fromRGB(120, 100, 180),
	OrdersCollapseGlyph = "-",
	OrdersExpandGlyph = "+",
	OrdersTitleTextSize = 15,
	OrdersStatusHeightPixels = 40,
	OrdersStatusTextSize = 14,

	-- การ์ดออเดอร์
	CardHeightPixels = 62,
	CardColor = Color3.fromRGB(70, 55, 100),
	CardCornerRadiusPixels = 8,
	CardPaddingPixels = 5,
	CardBlockSizePixels = 36,
	CardBlockGapPixels = 6,
	CardLineHeightPixels = 17,
	CardTextSize = 13,
	HeartColor = Color3.fromRGB(255, 120, 140),
	EnoughColor = Color3.fromRGB(140, 230, 170),
	ShortColor = Color3.fromRGB(255, 150, 150),
	TimerWidthScale = 0.4,
	HeartsWidthScale = 0.4,
}
