--!strict
-- จำกัดความถี่การเรียกต่อผู้เล่น (fixed window) และล้างข้อมูลเมื่อผู้เล่นออก
-- ใช้: local limiter = RateLimiter.new(5, 2); if not limiter.allow(player) then ... end

local Players = game:GetService("Players")

type Bucket = { windowStart: number, count: number }

export type RateLimiter = {
	allow: (player: Player) -> boolean,
}

local RateLimiter = {}

local allBuckets: { { [Player]: Bucket } } = {}

function RateLimiter.new(maxCalls: number, windowSeconds: number): RateLimiter
	local buckets: { [Player]: Bucket } = {}
	table.insert(allBuckets, buckets)

	local function allow(player: Player): boolean
		local now = os.clock()
		local bucket = buckets[player]
		if bucket == nil or now - bucket.windowStart >= windowSeconds then
			buckets[player] = { windowStart = now, count = 1 }
			return true
		end
		if bucket.count >= maxCalls then
			return false
		end
		bucket.count += 1
		return true
	end

	return { allow = allow }
end

Players.PlayerRemoving:Connect(function(player: Player)
	for _, buckets in allBuckets do
		buckets[player] = nil
	end
end)

return RateLimiter
