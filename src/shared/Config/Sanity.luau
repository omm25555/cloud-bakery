--!strict
-- ค่าตั้งของสติ (SanityService / SanityController) ตัวเลขทั้งหมดเป็นค่าชั่วคราว รอปรับบาลานซ์ใน TASK-025
-- สติเก็บใน memory ต่อผู้เล่น รีเซ็ตทุกคืน (ไม่บันทึก DataStore)

export type Values = {
	Max: number, -- สติสูงสุด (> 0)
	Start: number, -- สติตอนเริ่มคืน/ตอนเข้าเกม (0 < Start <= Max)
	WrongReport: number, -- ลดเมื่อรายงานผิด (>= 0)
	MissedAnomaly: number, -- ลดต่อ anomaly ที่ไม่ถูกรายงานจนเช้า (ผู้เล่นทุกคน)
	LeftoverCustomer: number, -- ลดต่อลูกค้ากลางคืนที่เหลือตอนหมดเวลา (ผู้เล่นทุกคน)
}

local Values: Values = {
	Max = 100,
	Start = 100,
	WrongReport = 8,
	MissedAnomaly = 10,
	LeftoverCustomer = 5,
}

-- ใช้เมื่อ Values ข้างบนไม่ผ่านการตรวจ
local Fallback: Values = {
	Max = 100,
	Start = 100,
	WrongReport = 8,
	MissedAnomaly = 10,
	LeftoverCustomer = 5,
}

return {
	Values = Values,
	Fallback = Fallback,

	-- Attributes บน Player (server เขียน, client อ่านอย่างเดียว)
	AttributeSanity = "Sanity",
	AttributeMax = "SanityMax",

	-- เครื่องมือ Studio (เฉพาะ RunService:IsStudio()): attribute บน ServerStorage ตั้งเป็นตัวเลข = ตั้งสติผู้เล่นทุกคน แล้วล้างค่า
	DebugSetAttribute = "SanityDebugSet",

	-- client: แถบสติกลางบนจอ ใต้กล่องวัน/คืน (DayNightGui) ความกว้างแคบกว่ากล่อง HUD ขวาบนบนมือถือ
	GuiName = "SanityGui",
	GuiDisplayOrder = 16,
	TopGapPixels = 6,
	WidthScale = 0.22,
	MinWidthPixels = 120,
	MaxWidthPixels = 150,
	HeightPixels = 34,
	PaddingPixels = 5,
	CornerRadiusPixels = 10,
	BackgroundColor = Color3.fromRGB(40, 30, 60),
	BackgroundTransparency = 0.15,
	BarBackgroundColor = Color3.fromRGB(80, 70, 100),
	BarHeightScale = 0.3,
	BarColorHigh = Color3.fromRGB(110, 200, 140),
	BarColorMid = Color3.fromRGB(240, 200, 80),
	BarColorLow = Color3.fromRGB(220, 80, 90),
	MidRatio = 0.6, -- ต่ำกว่านี้ใช้สีกลาง
	LowRatio = 0.3, -- ต่ำกว่านี้ใช้สีแดง
	TweenSeconds = 0.3,
	Font = Enum.Font.GothamMedium,
	TextColor = Color3.fromRGB(255, 255, 255),
	MaxTextSize = 16,
	MinTextSize = 8,
}
