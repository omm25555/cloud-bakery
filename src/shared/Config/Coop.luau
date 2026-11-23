--!strict
-- ค่าตั้งของ Co-op แบบเบา (CoopService / CoopController)
-- ผู้เล่นส่งวัตถุดิบ/ขนมให้กันได้ (ผู้รับต้องกดรับ) ถ้าขนมที่ได้รับถูกใช้เสิร์ฟออเดอร์จริง ผู้ให้ได้โบนัสผู้ช่วย
-- ตัวเลขทั้งหมดเป็นค่าชั่วคราว รอปรับบาลานซ์ (TASK-012)

local OfferTypes = {
	Offer = "Offer",
	Closed = "Closed",
}

return {
	OfferTypes = OfferTypes,

	-- การให้ของ
	MaxItemsPerGift = 10, -- จำนวนสูงสุดต่อหนึ่งคำขอ
	MaxItemIdLength = 32,
	MaxGiveDistance = 20, -- studs ระหว่างผู้ให้กับผู้รับ (ตอนส่งคำขอและตอนกดรับ)
	DistanceTolerance = 6, -- เผื่อ lag ฝั่ง server
	OfferTimeoutSeconds = 30,
	MaxPendingOffersPerPlayer = 3, -- คำขอที่ผู้เล่นส่งแล้วยังไม่มีคำตอบ
	MaxIncomingOffersPerPlayer = 3, -- คำขอที่ผู้เล่นได้รับแล้วยังไม่ตอบ

	-- โบนัสผู้ช่วย (จ่ายเป็นเหรียญใหม่จาก server ไม่หักจากผู้เสิร์ฟ)
	HelperBonusRatio = 0.1, -- สัดส่วนของเหรียญที่ผู้เสิร์ฟได้ เฉพาะส่วนของขนมที่มีเครดิต
	HelperBonusDailyCap = 300, -- เหรียญโบนัสสูงสุดต่อผู้ให้ต่อวัน (ต่อเซิร์ฟเวอร์)
	HelperBonusPerPairDailyCap = 100, -- เหรียญโบนัสสูงสุดต่อคู่ (ผู้ให้ -> ผู้เสิร์ฟ) ต่อวัน
	GiftCreditSeconds = 600, -- เครดิตขนมที่ได้รับหมดอายุเมื่อไม่ถูกใช้เสิร์ฟ
	MaxCreditsPerPlayer = 20, -- จำนวนเครดิตสูงสุดที่เก็บต่อผู้รับ
	DaySeconds = 86400,

	-- client: ปุ่มกดที่ตัวผู้เล่นอื่น (ProximityPrompt) เพื่อเปิดแผงให้ของ
	PromptName = "CoopGivePrompt",
	PromptKeyCode = Enum.KeyCode.F,
	PromptDistance = 14,
	PromptHoldSeconds = 0,
	PromptRequiresLineOfSight = false,
	ClientWaitSeconds = 15,

	-- client: UI (ไม่ทับ HUD ขวาบน, Orders, Quest ซ้ายบน, ปุ่มล่างขวา, แถบพืชล่างกลาง)
	GuiName = "CoopGui",
	GuiDisplayOrder = 16,
	Font = Enum.Font.GothamMedium,
	TextColor = Color3.fromRGB(255, 255, 255),
	SubTextColor = Color3.fromRGB(215, 205, 235),
	PanelColor = Color3.fromRGB(40, 30, 60),
	PanelTransparency = 0.05,
	ButtonColor = Color3.fromRGB(120, 100, 180),
	ButtonSelectedColor = Color3.fromRGB(90, 170, 120),
	DeclineColor = Color3.fromRGB(200, 90, 100),
	CornerRadiusPixels = 12,
	PaddingPixels = 8,
	SpacingPixels = 6,
	TitleTextSize = 18,
	BodyTextSize = 16,
	ButtonTextSize = 16,
	ButtonHeightPixels = 34,
	TitleHeightPixels = 26,
	RowHeightPixels = 32,

	-- แผงเลือกของ (กลางจอ)
	SendPanelWidthScale = 0.5,
	SendPanelHeightScale = 0.8,
	SendPanelMaxWidthPixels = 380,
	SendPanelMaxHeightPixels = 330,
	AmountButtonWidthPixels = 40,

	-- กล่องคำขอที่ได้รับ (กลางล่าง เหนือแถบพืช)
	OfferBottomOffsetPixels = 76,
	OfferWidthScale = 0.5,
	OfferMaxWidthPixels = 340,
	OfferHeightPixels = 120,
}
