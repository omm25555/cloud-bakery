--!strict
-- ค่าตั้งของวงจรกลางวัน/กลางคืน (ตัวเลขทั้งหมดของระบบนี้อยู่ที่นี่)
-- Production = ค่าจริง, Studio = ค่าสั้นสำหรับทดสอบ (DayNightService เลือกด้วย RunService:IsStudio())
-- Fallback = ค่าสำรองที่ปลอดภัย ใช้เมื่อค่าที่เลือกไม่ผ่านการตรวจ

export type Phase = "Day" | "Dusk" | "Night" | "Dawn"

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

local Production: Durations = {
	DaySeconds = 180,
	DuskSeconds = 60,
	NightSeconds = 180,
	DawnSeconds = 60,
	WarningSeconds = 30,
}

local Studio: Durations = {
	DaySeconds = 40,
	DuskSeconds = 6,
	NightSeconds = 40,
	DawnSeconds = 6,
	WarningSeconds = 10,
}

local Fallback: Durations = {
	DaySeconds = 180,
	DuskSeconds = 60,
	NightSeconds = 180,
	DawnSeconds = 60,
	WarningSeconds = 30,
}

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

	-- ลำดับ phase ในหนึ่งรอบ และรายชื่อช่องที่ต้องตรวจ
	PhaseOrder = { "Day", "Dusk", "Night", "Dawn" } :: { Phase },
	DurationFields = { "DaySeconds", "DuskSeconds", "NightSeconds", "DawnSeconds", "WarningSeconds" } :: { string },
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

	-- UI (มุมซ้ายบน ใต้แถบเมนู Roblox ไม่ทับ HUD ขวาบน/toast กลางบน)
	GuiName = "DayNightGui",
	GuiDisplayOrder = 15,
	SecondsPerMinute = 60,
	RefreshSeconds = 0.25,
	MarginPixels = 10,
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
}
