--!strict
-- กติกาแสดงผลที่ใช้ร่วมกันของ HUD / แผง Orders / HudService (เลเวล Reputation, รูปแบบตัวเลข/เวลา/หัวใจ)
-- เลเวลคำนวณจากตาราง Config/Hud เท่านั้น ไม่ให้รางวัลและไม่บันทึก

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hud = require(ReplicatedStorage.Shared.Config.Hud)
local Serve = require(ReplicatedStorage.Shared.Config.Serve)

export type Progress = {
	Level: number,
	Current: number, -- Reputation ที่สะสมในเลเวลนี้
	Needed: number, -- Reputation ที่ต้องใช้ในเลเวลนี้ (เลเวลสูงสุด = 0)
	Ratio: number, -- 0-1
	IsMax: boolean,
}

local HudRules = {}

local function sanitize(reputation: number): number
	if reputation ~= reputation or reputation < 0 then
		return 0
	end
	return math.floor(reputation)
end

function HudRules.LevelFor(reputation: number): number
	local value = sanitize(reputation)
	local level = 1
	for index, threshold in Hud.LevelThresholds do
		if value >= threshold then
			level = index
		end
	end
	return level
end

function HudRules.ProgressFor(reputation: number): Progress
	local value = sanitize(reputation)
	local level = HudRules.LevelFor(value)
	local floorValue = Hud.LevelThresholds[level] or 0
	local nextValue = Hud.LevelThresholds[level + 1]
	if nextValue == nil then
		return { Level = level, Current = value - floorValue, Needed = 0, Ratio = 1, IsMax = true }
	end
	local needed = math.max(1, nextValue - floorValue)
	local current = value - floorValue
	return {
		Level = level,
		Current = current,
		Needed = needed,
		Ratio = math.clamp(current / needed, 0, 1),
		IsMax = false,
	}
end

-- 1234567 -> "1,234,567"
function HudRules.FormatNumber(value: number): string
	local formatted = tostring(math.floor(value))
	local count = 0
	repeat
		formatted, count = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
	until count == 0
	return formatted
end

function HudRules.HeartsFor(ratio: number): number
	for _, tier in Serve.HeartTiers do
		if ratio >= tier.MinRatio then
			return tier.Hearts
		end
	end
	return 1
end

function HudRules.HeartsText(hearts: number): string
	local maxHearts = 1
	for _, tier in Serve.HeartTiers do
		maxHearts = math.max(maxHearts, tier.Hearts)
	end
	local filled = math.clamp(hearts, 0, maxHearts)
	return string.rep(Serve.HeartFull, filled) .. string.rep(Serve.HeartEmpty, maxHearts - filled)
end

function HudRules.FormatTime(seconds: number): string
	local total = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", total // 60, total % 60)
end

return HudRules
