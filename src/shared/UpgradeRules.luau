--!strict
-- กติกาอัปเกรดที่ server และ client ใช้ร่วมกัน (เลเวลสูงสุด ราคา ตัวคูณ ข้อความ)
-- ค่าทั้งหมดอ่านจาก Config/Upgrades ที่นี่ไม่มีตัวเลขของตัวเอง

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)

type Line = Upgrades.Line

local UpgradeRules = {}

-- เลเวลสูงสุดที่ใช้จริง: ไม่เกิน MaxLevel, จำนวนราคาที่มี และเพดานของ PlayerData
function UpgradeRules.MaxLevel(line: Line): number
	return math.max(0, math.min(line.MaxLevel, #line.Costs, PlayerDataConfig.Limits.MaxUpgradeLevel))
end

-- ราคาซื้อเลเวล targetLevel (nil ถ้าเลเวลนั้นซื้อไม่ได้)
function UpgradeRules.Cost(line: Line, targetLevel: number): number?
	if targetLevel < 1 or targetLevel > UpgradeRules.MaxLevel(line) then
		return nil
	end
	return line.Costs[targetLevel]
end

-- ตัวคูณที่เลเวลนั้น ถ้าค่าใน Config เสียให้เป็น 1 (ไม่มีผล)
function UpgradeRules.Multiplier(line: Line, level: number): number
	local value = line.Effects[level]
	if type(value) == "number" and value > 0 and value == value then
		return value
	end
	return 1
end

-- ค่าที่อ่านจากข้อมูลเซฟ: ไม่ใช่ตัวเลข/ไม่ใช่จำนวนเต็ม/ติดลบ = 0, เกินเพดาน = เพดาน
function UpgradeRules.SanitizeLevel(raw: unknown, line: Line): number
	if type(raw) ~= "number" then
		return 0
	end
	local number = raw :: number
	if number ~= number or number < 0 or number % 1 ~= 0 then
		return 0
	end
	return math.min(number, UpgradeRules.MaxLevel(line))
end

function UpgradeRules.EffectPercent(line: Line, level: number): number
	local multiplier = UpgradeRules.Multiplier(line, level)
	if line.EffectKind == "CoinMultiplier" then
		return math.round((multiplier - 1) * 100)
	end
	return math.round((1 - multiplier) * 100)
end

function UpgradeRules.EffectText(line: Line, level: number, language: string): string
	local key = if line.EffectKind == "CoinMultiplier" then "UpgradeEffectCoin" else "UpgradeEffectTime"
	local args: { [string]: string | number } = { percent = UpgradeRules.EffectPercent(line, level) }
	return Strings.Format(key, language, args)
end

function UpgradeRules.Name(line: Line, language: string): string
	return if language == "en" then line.NameEn else line.NameTh
end

function UpgradeRules.Desc(line: Line, language: string): string
	return if language == "en" then line.DescEn else line.DescTh
end

return UpgradeRules
