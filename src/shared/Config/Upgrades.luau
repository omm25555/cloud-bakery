--!strict
-- ค่าตั้งของระบบอัปเกรดร้าน 3 สาย (UpgradeService / UpgradeController)
-- ตัวเลขทั้งหมดเป็นค่าชั่วคราว รอบาลานซ์เฟส 8
-- MaxLevel ต้องไม่เกิน PlayerData.Limits.MaxUpgradeLevel (UpgradeRules.MaxLevel ตัดให้อัตโนมัติ)

export type EffectKind = "TimeMultiplier" | "CoinMultiplier"

export type Line = {
	Id: string,
	NameTh: string,
	NameEn: string,
	DescTh: string,
	DescEn: string,
	MaxLevel: number,
	Costs: { number }, -- ราคาซื้อเลเวล 1..MaxLevel (ตำแหน่งที่ n = ราคาซื้อเลเวล n)
	Effects: { [number]: number }, -- ตัวคูณที่เลเวล 0..MaxLevel
	EffectKind: EffectKind,
}

local Ids = {
	GrowthSpeed = "GrowthSpeed",
	OvenSpeed = "OvenSpeed",
	CoinBonus = "CoinBonus",
}

local Lines: { [string]: Line } = {
	[Ids.GrowthSpeed] = {
		Id = Ids.GrowthSpeed,
		NameTh = "ปุ๋ยเมฆ",
		NameEn = "Cloud Fertilizer",
		DescTh = "พืชที่คุณปลูกโตเร็วขึ้น",
		DescEn = "Crops you plant grow faster.",
		MaxLevel = 5,
		Costs = { 50, 100, 200, 400, 800 },
		Effects = { [0] = 1, 0.92, 0.84, 0.76, 0.68, 0.6 },
		EffectKind = "TimeMultiplier",
	},
	[Ids.OvenSpeed] = {
		Id = Ids.OvenSpeed,
		NameTh = "เตาอบเร่งความร้อน",
		NameEn = "Hot Oven",
		DescTh = "ขนมที่คุณสั่งอบสุกเร็วขึ้น",
		DescEn = "Treats you start baking finish sooner.",
		MaxLevel = 5,
		Costs = { 50, 100, 200, 400, 800 },
		Effects = { [0] = 1, 0.92, 0.84, 0.76, 0.68, 0.6 },
		EffectKind = "TimeMultiplier",
	},
	[Ids.CoinBonus] = {
		Id = Ids.CoinBonus,
		NameTh = "ป้ายร้านดัง",
		NameEn = "Popular Sign",
		DescTh = "ได้เหรียญเพิ่มทุกครั้งที่คุณเสิร์ฟ",
		DescEn = "Earn bonus coins every time you serve.",
		MaxLevel = 5,
		Costs = { 50, 100, 200, 400, 800 },
		Effects = { [0] = 1, 1.1, 1.2, 1.3, 1.4, 1.5 },
		EffectKind = "CoinMultiplier",
	},
}

return {
	Ids = Ids,
	Lines = Lines,
	-- ลำดับที่แสดงในแผง
	Order = { Ids.GrowthSpeed, Ids.OvenSpeed, Ids.CoinBonus } :: { string },

	-- server
	MaxLogIdLength = 32,
	SyncWaitSeconds = 30,
	SyncPollSeconds = 0.5,

	-- client: ปุ่มวางในแถวล่างขวาที่เว้นไว้ให้ 6 ปุ่มตาม GDD (Upgrade เป็นช่องที่ 3 จากซ้าย)
	GuiName = "UpgradeGui",
	GuiDisplayOrder = 30,
	ButtonSlotCount = 6,
	ButtonSlot = 3,
	ButtonWidthPixels = 96,
	ButtonHeightPixels = 44,
	ButtonSpacingPixels = 8,
	ButtonMarginPixels = 12,
	ButtonColor = Color3.fromRGB(120, 100, 180),
	ButtonTextSize = 18,
	BadgeSizePixels = 16,
	BadgeColor = Color3.fromRGB(220, 50, 60),

	PanelWidthPixels = 440,
	PanelWidthScale = 0.94,
	PanelPaddingPixels = 12,
	PanelSpacingPixels = 8,
	PanelBackgroundColor = Color3.fromRGB(40, 30, 60),
	PanelBackgroundTransparency = 0.1,
	PanelBottomOffsetPixels = 70,
	TitleTextSize = 22,
	CloseButtonSizePixels = 32,
	RowBackgroundColor = Color3.fromRGB(70, 55, 100),
	RowPaddingPixels = 8,
	RowSpacingPixels = 2,
	BuyButtonWidthPixels = 110,
	BuyButtonHeightPixels = 36,
	BuyEnabledColor = Color3.fromRGB(90, 170, 120),
	BuyDisabledColor = Color3.fromRGB(110, 110, 120),
	NameTextSize = 18,
	BodyTextSize = 15,
	CornerRadiusPixels = 10,
	Font = Enum.Font.GothamMedium,
	TextColor = Color3.fromRGB(255, 255, 255),
	SubTextColor = Color3.fromRGB(215, 205, 235),
}
