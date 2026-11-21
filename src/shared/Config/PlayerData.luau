--!strict
-- ค่าเริ่มต้นและค่าตั้งของระบบข้อมูลผู้เล่น (DataService)

export type Language = "th" | "en"

export type PlayerData = {
	Version: number,
	Coins: number,
	Reputation: number,
	Inventory: { [string]: number },
	Upgrades: { [string]: number },
	Settings: { Language: Language },
}

export type RetryConfig = {
	MaxAttempts: number,
	InitialDelaySeconds: number,
	BackoffMultiplier: number,
	MaxDelaySeconds: number,
}

local DataVersion = 1

local Defaults: PlayerData = {
	Version = DataVersion,
	Coins = 100, -- ค่าชั่วคราว รอปรับบาลานซ์
	Reputation = 0,
	Inventory = {},
	Upgrades = {}, -- เติม id ตอนมี Config ของอัปเกรดจริง
	Settings = { Language = "th" },
}

local Load: RetryConfig = {
	MaxAttempts = 5,
	InitialDelaySeconds = 1,
	BackoffMultiplier = 2,
	MaxDelaySeconds = 16,
}

local Save: RetryConfig = {
	MaxAttempts = 5,
	InitialDelaySeconds = 1,
	BackoffMultiplier = 2,
	MaxDelaySeconds = 16,
}

-- ใช้ตอน BindToClose (เวลาจำกัด ~30 วินาที) จึงลองสั้นกว่า
local CloseSave: RetryConfig = {
	MaxAttempts = 3,
	InitialDelaySeconds = 0.5,
	BackoffMultiplier = 2,
	MaxDelaySeconds = 2,
}

return {
	DataVersion = DataVersion,
	DataStoreName = "PlayerData_v1",
	KeyPrefix = "Player_",
	DefaultLanguage = "th" :: Language,
	Defaults = Defaults,

	Load = Load,
	Save = Save,
	CloseSave = CloseSave,

	AutosaveIntervalSeconds = 120,
	AutosaveJitterSeconds = 15,
	LockExpirySeconds = 600,
	PollSeconds = 0.1,
	ShutdownMaxWaitSeconds = 25,

	-- ขอบเขตค่าที่ยอมรับตอนโหลด (ค่านอกช่วงถือว่าเสียและใช้ค่าเริ่มต้นแทน)
	Limits = {
		MaxCoins = 1000000000,
		MaxReputation = 1000000,
		MaxItemCount = 1000000,
		MaxUpgradeLevel = 100,
	},

	-- ข้อความ error ของ Studio เมื่อไม่ได้เปิด API Services (ตัวพิมพ์เล็ก)
	StudioApiDisabledMarkers = {
		"studio access to apis is not allowed",
		"studioaccesstoapisnotallowed",
		"must publish this place",
	},
}
