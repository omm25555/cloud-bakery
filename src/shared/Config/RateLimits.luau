--!strict
-- ลิมิตคำขอต่อผู้เล่นต่อ remote (token bucket)
-- Capacity = จำนวนคำขอสูงสุดที่ส่งติดกันได้, RefillPerSecond = อัตราเติมต่อวินาที

export type Limit = { Capacity: number, RefillPerSecond: number }

export type RateLimitsConfig = {
	Default: Limit,
	Remotes: { [string]: Limit },
	WarnCooldownSeconds: number,
	NotifyCooldownSeconds: number,
}

local Config: RateLimitsConfig = {
	Default = { Capacity = 10, RefillPerSecond = 10 },
	Remotes = {
		NotifyReady = { Capacity = 2, RefillPerSecond = 0.2 },
		FarmPlant = { Capacity = 4, RefillPerSecond = 2 },
		FarmHarvest = { Capacity = 4, RefillPerSecond = 2 },
		FarmSync = { Capacity = 2, RefillPerSecond = 0.2 },
		BakeStart = { Capacity = 3, RefillPerSecond = 1 },
		BakeCollect = { Capacity = 4, RefillPerSecond = 2 },
		BakeTap = { Capacity = 6, RefillPerSecond = 4 },
		BakeSync = { Capacity = 2, RefillPerSecond = 0.2 },
		ServeOrder = { Capacity = 3, RefillPerSecond = 1 },
		ServeSync = { Capacity = 2, RefillPerSecond = 0.2 },
		UpgradeBuy = { Capacity = 3, RefillPerSecond = 1 },
		UpgradeSync = { Capacity = 2, RefillPerSecond = 0.2 },
		InventorySync = { Capacity = 2, RefillPerSecond = 0.2 },
		SettingsSetLanguage = { Capacity = 3, RefillPerSecond = 1 },
		MenuLockedClick = { Capacity = 3, RefillPerSecond = 1 },
		HudShopClick = { Capacity = 2, RefillPerSecond = 0.5 },
		HudLevelCheck = { Capacity = 4, RefillPerSecond = 1 },
		HudLoadTimeout = { Capacity = 1, RefillPerSecond = 0.05 },
		HudInvalid = { Capacity = 3, RefillPerSecond = 0.5 },
		QuestSync = { Capacity = 2, RefillPerSecond = 0.2 },
		QuestClaim = { Capacity = 3, RefillPerSecond = 1 },
		CoopOffer = { Capacity = 3, RefillPerSecond = 1 },
		CoopRespond = { Capacity = 4, RefillPerSecond = 2 },
		LobbyPrompt = { Capacity = 3, RefillPerSecond = 1 },
		LobbyReady = { Capacity = 2, RefillPerSecond = 0.2 },
		ReportPrompt = { Capacity = 2, RefillPerSecond = 0.5 },
		ReportSubmit = { Capacity = 2, RefillPerSecond = 0.5 },
	},
	WarnCooldownSeconds = 5,
	NotifyCooldownSeconds = 5,
}

return Config
