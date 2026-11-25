--!strict
-- ค่าตั้งของวงจรกลางวัน/กลางคืน (ตัวเลขทั้งหมดของระบบนี้อยู่ที่นี่)
-- Production = ค่าจริง, Studio = ค่าสั้นสำหรับทดสอบ (DayNightService เลือกด้วย RunService:IsStudio())
-- Fallback = ค่าสำรองที่ปลอดภัย ใช้เมื่อค่าที่เลือกไม่ผ่านการตรวจ

local NotifyConfig = require(script.Parent.Notify)

export type Phase ="Day" | "Dusk" | "Night" | "Dawn"

export type Durations = {
	DaySeconds: number,
	DuskSeconds: number,
	NightSeconds: number,
	DawnSeconds: number,
	WarningSeconds: number,
}

export type Look = {
	ClockTime: number,
	Brightness: number,
	ExposureCompensation: number,
	Ambient: Color3,
	OutdoorAmbient: Color3,
	ColorShiftTop: Color3,
	AtmosphereColor: Color3,
	AtmosphereDecay: Color3,
	AtmosphereDensity: number,
	AtmosphereHaze: number,
}

-- ความยาวช่วงตามโหมด (วินาที) โหมดยากมี anomaly แนบเนียนกว่า จึงมีกลางคืนยาวขึ้น
-- Production = ค่าจริง, Studio = ค่าสั้นสำหรับทดสอบ (DayNightService เลือกด้วย RunService:IsStudio())
local Production: { [string]: Durations } = {
	Easy = { DaySeconds = 180, DuskSeconds = 60, NightSeconds = 180, DawnSeconds = 60, WarningSeconds = 30 },
	Hard = { DaySeconds = 180, DuskSeconds = 60, NightSeconds = 240, DawnSeconds = 60, WarningSeconds = 30 },
	Nightmare = { DaySeconds = 180, DuskSeconds = 60, NightSeconds = 300, DawnSeconds = 60, WarningSeconds = 30 },
}

local Studio: { [string]: Durations } = {
	Easy = { DaySeconds = 40, DuskSeconds = 6, NightSeconds = 40, DawnSeconds = 6, WarningSeconds = 10 },
	Hard = { DaySeconds = 40, DuskSeconds = 6, NightSeconds = 55, DawnSeconds = 6, WarningSeconds = 10 },
	Nightmare = { DaySeconds = 40, DuskSeconds = 6, NightSeconds = 70, DawnSeconds = 6, WarningSeconds = 10 },
}

-- ค่าสำรองที่ปลอดภัย (เท่ากับ Easy ของ Production) ใช้เมื่อค่าที่เลือกไม่ผ่านการตรวจ
local Fallback: Durations = {
	DaySeconds = 180,
	DuskSeconds = 60,
	NightSeconds = 180,
	DawnSeconds = 60,
	WarningSeconds = 30,
}

local PhaseOrder: { Phase } = { "Day", "Dusk", "Night", "Dawn" }

local DayLook: Look = {
	ClockTime = 14,
	Brightness = 3,
	ExposureCompensation = 0,
	Ambient = Color3.fromRGB(150, 140, 150),
	OutdoorAmbient = Color3.fromRGB(170, 165, 175),
	ColorShiftTop = Color3.fromRGB(255, 240, 220),
	AtmosphereColor = Color3.fromRGB(199, 215, 235),
	AtmosphereDecay = Color3.fromRGB(255, 230, 210),
	AtmosphereDensity = 0.25,
	AtmosphereHaze = 0.5,
}

-- กลางคืนสว่างพอเห็นร้าน สถานี และ ProximityPrompt ชัด (Ambient สูง ไม่มืดสนิท)
local NightLook: Look = {
	ClockTime = 0,
	Brightness = 2,
	ExposureCompensation = 0.4,
	Ambient = Color3.fromRGB(120, 105, 165),
	OutdoorAmbient = Color3.fromRGB(135, 115, 180),
	ColorShiftTop = Color3.fromRGB(190, 150, 230),
	AtmosphereColor = Color3.fromRGB(150, 120, 190),
	AtmosphereDecay = Color3.fromRGB(235, 140, 190),
	AtmosphereDensity = 0.35,
	AtmosphereHaze = 1,
}

return {
	Production = Production,
	Studio = Studio,
	Fallback = Fallback,

	-- โหมด: ตอนนี้ยังไม่มีระบบเลือก (TASK-019) ระบบนั้นตั้ง attribute นี้บน ReplicatedStorage ก่อนผู้เล่นคนแรกเข้า
	-- ไม่มี attribute = DefaultMode, ค่าที่ไม่รู้จัก = DefaultMode พร้อม warn
	DefaultMode = "Easy",
	AttributeMode = "DayNightMode",

	-- ลำดับ phase ในหนึ่งรอบ
	PhaseOrder = PhaseOrder,
	-- ช่องที่ตั้งเป็น 0 ได้ (ช่วงเปลี่ยนถูกข้าม / ปิดการเตือน) ช่องอื่นต้อง > 0
	ZeroAllowed = { DuskSeconds = true, DawnSeconds = true, WarningSeconds = true } :: { [string]: boolean },

	-- Attributes บน ReplicatedStorage (server เขียน, client อ่านอย่างเดียว)
	AttributePhase = "DayNightPhase",
	AttributeDay = "DayNightDay",
	AttributePhaseEndsAt = "DayNightPhaseEndsAt",
	AttributePhaseSeconds = "DayNightPhaseSeconds",

	-- Lighting: Dusk ไล่จาก Day ไป Night ตลอดช่วง, Dawn ไล่กลับ
	DayLook = DayLook,
	NightLook = NightLook,
	HoursPerDay = 24,
	AtmosphereName = "DayNightAtmosphere",

	-- UI: กลางบนจอ ใต้ toast แถวแรก (ซ้ายบน = Quest, ขวาบน = HUD/Orders, ซ้ายกลาง = ป้ายกระเป๋า,
	-- ล่างกลาง = แถบพืช/เมนู, ขวาล่าง = ปุ่มเมนู) toast สูงสุด 3 แถวอาจทับกล่องนี้ชั่วคราว 4 วินาที (toast อยู่ชั้นบนสุด)
	-- TopOffsetPixels = Notify.TopOffsetPixels + ความสูง toast 1 แถว (TextSize + Padding บน/ล่าง) + Notify.SpacingPixels
	GuiName = "DayNightGui",
	GuiDisplayOrder = 15,
	SecondsPerMinute = 60,
	RefreshSeconds = 0.25,
	TopOffsetPixels = NotifyConfig.TopOffsetPixels
		+ NotifyConfig.TextSize
		+ NotifyConfig.PaddingPixels * 2
		+ NotifyConfig.SpacingPixels,
	WidthScale = 0.22,
	MinWidthPixels = 150,
	MaxWidthPixels = 230,
	HeightPixels = 56,
	PaddingPixels = 6,
	CornerRadiusPixels = 10,
	BackgroundColor = Color3.fromRGB(40, 30, 60),
	BackgroundTransparency = 0.15,
	Font = Enum.Font.GothamMedium,
	TextColor = Color3.fromRGB(255, 255, 255),
	SubTextColor = Color3.fromRGB(215, 205, 235),
	MaxTextSize = 18,
	MinTextSize = 8,
	DayAccentColor = Color3.fromRGB(255, 210, 90),
	NightAccentColor = Color3.fromRGB(190, 150, 240),
	TitleHeightScale = 0.5,
	CounterWidthScale = 0.5,
	TimeWidthScale = 0.5,
}
