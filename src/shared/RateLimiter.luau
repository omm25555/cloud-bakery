--!strict
-- จำกัดคำขอต่อผู้เล่นต่อ remote แบบ token bucket
-- ใช้: local limiter = RateLimiter.new(RateLimits, onLimited)
--      if not limiter:Check(player, "RemoteName") then return end

local Players = game:GetService("Players")

export type Limit = { Capacity: number, RefillPerSecond: number }

export type LimiterConfig = {
	Default: Limit,
	Remotes: { [string]: Limit },
	WarnCooldownSeconds: number,
}

type Bucket = {
	Tokens: number,
	LastRefill: number,
	LastWarn: number,
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable(
	{} :: {
		_config: LimiterConfig,
		_buckets: { [Player]: { [string]: Bucket } },
		_onLimited: ((Player, string) -> ())?,
		_connection: RBXScriptConnection?,
	},
	RateLimiter
))

-- onLimited ถูกเรียกเมื่อเกินลิมิต (ไม่เกินหนึ่งครั้งต่อ WarnCooldownSeconds ต่อ remote ต่อผู้เล่น)
function RateLimiter.new(config: LimiterConfig, onLimited: ((Player, string) -> ())?): RateLimiter
	local self = setmetatable({
		_config = config,
		_buckets = {} :: { [Player]: { [string]: Bucket } },
		_onLimited = onLimited,
		_connection = nil :: RBXScriptConnection?,
	}, RateLimiter)
	self._connection = Players.PlayerRemoving:Connect(function(player: Player)
		self._buckets[player] = nil
	end)
	return self
end

-- คืน true ถ้าอนุญาต, false ถ้าเกินลิมิต (ผู้เรียกต้องปฏิเสธคำขอ)
function RateLimiter.Check(self: RateLimiter, player: Player, remoteName: string): boolean
	if player.Parent == nil then
		return false
	end
	local limit = self._config.Remotes[remoteName] or self._config.Default
	local now = os.clock()

	local perPlayer = self._buckets[player]
	if perPlayer == nil then
		perPlayer = {}
		self._buckets[player] = perPlayer
	end
	local bucket = perPlayer[remoteName]
	if bucket == nil then
		bucket = { Tokens = limit.Capacity, LastRefill = now, LastWarn = -math.huge }
		perPlayer[remoteName] = bucket
	end

	local elapsed = now - bucket.LastRefill
	bucket.Tokens = math.min(limit.Capacity, bucket.Tokens + elapsed * limit.RefillPerSecond)
	bucket.LastRefill = now

	if bucket.Tokens >= 1 then
		bucket.Tokens -= 1
		return true
	end

	if now - bucket.LastWarn >= self._config.WarnCooldownSeconds then
		bucket.LastWarn = now
		warn(`[RateLimiter] {player.Name} ส่ง {remoteName} เกินลิมิต ปฏิเสธคำขอ`)
		local onLimited = self._onLimited
		if onLimited then
			onLimited(player, remoteName)
		end
	end
	return false
end

function RateLimiter.Remove(self: RateLimiter, player: Player)
	self._buckets[player] = nil
end

function RateLimiter.Destroy(self: RateLimiter)
	local connection = self._connection
	if connection then
		connection:Disconnect()
		self._connection = nil
	end
	table.clear(self._buckets)
end

return RateLimiter
