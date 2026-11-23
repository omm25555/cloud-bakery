--!strict
-- ค่าตั้งของแถบปุ่มล่างขวา + แผง Bag / Recipes / Settings (MenuController และ panel controller)
-- ตำแหน่งปุ่มอ้างสูตรเดียวกับปุ่ม Upgrade (Config/Upgrades) แต่ละปุ่มอยู่คนละช่อง ไม่ทับกัน
-- หมายเหตุสำหรับระบบใหม่: ระบบที่เปลี่ยนกระเป๋าผู้เล่นต้องยิง remote InventoryUpdate ด้วย
-- (รูปแบบ { Inventory, Language }) แผง Bag/Recipes ถึงจะอัปเดต

export type ButtonConfig = {
	Id: string,
	Slot: number, -- ช่องที่ n จากซ้ายของแถวล่างขวา (ช่อง Upgrades.ButtonSlot เป็นของปุ่ม Upgrade)
	ButtonKey: string, -- key ใน Strings
	Locked: boolean, -- true = ปุ่มล็อก "เร็วๆ นี้" ไม่มีแผง
}

local Ids = {
	Bag = "Bag",
	Recipes = "Recipes",
	Pets = "Pets",
	Decor = "Decor",
	Settings = "Settings",
}

local Buttons: { ButtonConfig } = {
	{ Id = Ids.Bag, Slot = 1, ButtonKey = "UiMenuBag", Locked = false },
	{ Id = Ids.Recipes, Slot = 2, ButtonKey = "UiMenuRecipes", Locked = false },
	{ Id = Ids.Pets, Slot = 4, ButtonKey = "UiMenuPets", Locked = true },
	{ Id = Ids.Decor, Slot = 5, ButtonKey = "UiMenuDecor", Locked = true },
	{ Id = Ids.Settings, Slot = 6, ButtonKey = "UiMenuSettings", Locked = false },
}

return {
	Ids = Ids,
	Buttons = Buttons,

	-- ลำดับแสดงของใน Bag / Recipes
	IngredientOrder = { "Wheat", "StarMilk", "Strawberry" } :: { string },
	RecipeOrder = { "CloudBread", "Croissant", "StrawberryCake" } :: { string },

	-- id ที่ client ส่งมากับ MenuLockedClick ได้ (server ตรวจ whitelist จากตารางนี้)
	LockedIds = { Pets = true, Decor = true } :: { [string]: boolean },
	MaxLogIdLength = 32,

	-- ภาษาที่รับได้ (ชื่อที่แสดงในแผง Settings ใช้ได้ทั้งสองภาษาเสมอ)
	LanguageNames = { th = "ไทย", en = "English" } :: { [string]: string },
	LanguageOrder = { "th", "en" } :: { string },

	-- server: รอข้อมูลผู้เล่นก่อนตอบ InventorySync
	SyncWaitSeconds = 30,
	SyncPollSeconds = 0.5,

	-- client
	GuiName = "MenuGui",
	GuiDisplayOrder = 31, -- สูงกว่า UpgradeGui (30) แผงนี้ทับแผง Upgrade ได้
	LanguageRequestTimeoutSeconds = 3, -- ไม่ได้คำตอบใน N วินาทีให้ปุ่มภาษากดได้อีก

	-- ขนาด/ระยะห่าง/จำนวนช่องของปุ่มอ่านจาก Config/Upgrades (ชุดเดียวกับปุ่ม Upgrade)
	ButtonColor = Color3.fromRGB(120, 100, 180),
	ButtonLockedColor = Color3.fromRGB(110, 110, 120),
	ButtonTextSize = 18,

	-- แผง: กรอบมนสีครีม หัวการ์ดม่วงเข้ม
	PanelWidthPixels = 440,
	PanelWidthScale = 0.94,
	PanelMaxHeightPixels = 560, -- เพดานความสูงแผง (จอเล็กใช้ค่าจากความสูงจอแทนถ้าน้อยกว่า)
	PanelTopMarginPixels = 8, -- ระยะเว้นขอบบนจอ
	PanelMinScrollHeightPixels = 80, -- พื้นที่เลื่อนต่ำสุดแม้จอเตี้ยมาก
	ScrollBarThicknessPixels = 6,
	ScrollBarColor = Color3.fromRGB(120, 100, 180),
	PanelBottomOffsetPixels = 70,
	PanelPaddingPixels = 12,
	PanelSpacingPixels = 8,
	PanelBackgroundColor = Color3.fromRGB(255, 244, 222),
	HeaderColor = Color3.fromRGB(70, 45, 110),
	HeaderHeightPixels = 52,
	CloseButtonSizePixels = 32,
	CloseButtonColor = Color3.fromRGB(110, 110, 120),
	CornerRadiusPixels = 14,

	RowBackgroundColor = Color3.fromRGB(240, 226, 196),
	RowPaddingPixels = 8,
	RowSpacingPixels = 4,

	Font = Enum.Font.GothamMedium,
	TitleTextSize = 20,
	SubTitleTextSize = 13,
	BodyTextSize = 16,
	SmallTextSize = 13,
	HeaderTextColor = Color3.fromRGB(255, 255, 255),
	HeaderSubTextColor = Color3.fromRGB(215, 205, 235),
	TextColor = Color3.fromRGB(60, 40, 80),
	SubTextColor = Color3.fromRGB(120, 100, 140),
	EnoughColor = Color3.fromRGB(40, 140, 80),
	ShortColor = Color3.fromRGB(200, 60, 60),

	LanguageButtonHeightPixels = 44,
	LanguageActiveColor = Color3.fromRGB(120, 100, 180),
	LanguageIdleColor = Color3.fromRGB(190, 175, 150),
	LanguageButtonTextColor = Color3.fromRGB(255, 255, 255),
}
