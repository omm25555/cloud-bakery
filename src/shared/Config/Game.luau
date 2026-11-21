--!strict
-- ค่าทั่วไปของเกม: เริ่มเกม, DataStore, rate limit, ระยะโต้ตอบ, แจ้งเตือน

export type RateLimitConfig = {
	MaxCalls: number,
	WindowSeconds: number,
}

local Game = {
	StartingCoins = 100,
	StartingIngredients = { Wheat = 6, StarMilk = 3, Strawberry = 0 } :: { [string]: number },
	MaxStackPerItem = 999,
	MaxCoins = 1_000_000_000,

	DataStoreName = "CloudBakery_PlayerData_v1",
	DataKeyPrefix = "Player_",
	DataVersion = 1,
	DataRetryAttempts = 3,
	DataRetryDelaySeconds = 2,
	AutosaveIntervalSeconds = 120,
	BindToCloseTimeoutSeconds = 25,
	SavePollSeconds = 0.1,

	-- ระยะสูงสุด (studs) ระหว่างตัวละครกับสถานีที่ server ยอมรับคำขอ
	InteractMaxDistance = 18,
	PromptMaxActivationDistance = 10,
	HarvestHoldSeconds = 0.25,

	RateLimits = {
		StartMix = { MaxCalls = 4, WindowSeconds = 5 },
		FinishMix = { MaxCalls = 4, WindowSeconds = 5 },
		Upgrade = { MaxCalls = 6, WindowSeconds = 5 },
		ClaimQuest = { MaxCalls = 3, WindowSeconds = 5 },
		SetLanguage = { MaxCalls = 5, WindowSeconds = 5 },
		GetState = { MaxCalls = 10, WindowSeconds = 5 },
		Prompt = { MaxCalls = 8, WindowSeconds = 2 },
	} :: { [string]: RateLimitConfig },

	NotifyDurationSeconds = 3.5,
	NotifyMaxVisible = 4,
	StatePushDebounceSeconds = 0.1,
	WorldTimerRefreshSeconds = 1,
	-- กันดับเบิลคลิกปุ่มอัปเกรด
	UpgradeClickCooldownSeconds = 0.4,
	-- ความถี่ตรวจว่าขึ้นวันใหม่ (UTC) เพื่อรีเซ็ตภารกิจของคนที่ออนไลน์อยู่
	QuestDayCheckSeconds = 30,
}

return Game
