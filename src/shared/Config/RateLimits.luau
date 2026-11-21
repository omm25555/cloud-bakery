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
	},
	WarnCooldownSeconds = 5,
	NotifyCooldownSeconds = 5,
}

return Config
