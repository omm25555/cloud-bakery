--!strict
-- สูตรคำนวณที่ server ใช้ตัดสิน และ client ใช้แสดงผล (ต้องตรงกันเสมอ)

-- ใช้ path ตรง (ไม่ใช้ WaitForChild) เพื่อให้ type checker ตามชนิดได้
-- โฟลเดอร์ Shared replicate มาพร้อมกันทั้งก้อน จึงมีครบเมื่อโมดูลนี้รัน
local Config = script.Parent.Config
local Progression = require(Config.Progression)
local Upgrades = require(Config.Upgrades)
local Customers = require(Config.Customers)
local Recipes = require(Config.Recipes)

local Formulas = {}

export type LevelInfo = {
	level: number,
	floor: number,
	ceil: number, -- 0 = เลเวลสูงสุด
}

function Formulas.levelInfo(reputation: number): LevelInfo
	local thresholds = Progression.LevelReputation
	local level = 1
	for index, needed in thresholds do
		if reputation >= needed then
			level = index
		end
	end
	local ceil = thresholds[level + 1] or 0
	return { level = level, floor = thresholds[level], ceil = ceil }
end

function Formulas.isRecipeUnlocked(recipeId: string, level: number): boolean
	local needed = Progression.RecipeUnlockLevel[recipeId]
	return needed ~= nil and level >= needed
end

function Formulas.upgradeLevel(upgrades: { [string]: number }, lineId: string): number
	return upgrades[lineId] or 0
end

function Formulas.upgradeCost(lineId: string, currentLevel: number): number?
	local line = Upgrades.Lines[lineId]
	if line == nil then
		return nil
	end
	return line.Costs[currentLevel + 1]
end

function Formulas.harvestYield(baseYield: number, gardenLevel: number): number
	return baseYield + gardenLevel * Upgrades.GardenYieldBonusPerLevel
end

function Formulas.ovenSlots(ovenLevel: number): number
	local slots = Upgrades.OvenBaseSlots
	for _, atLevel in Upgrades.OvenExtraSlotAtLevels do
		if ovenLevel >= atLevel then
			slots += 1
		end
	end
	return slots
end

function Formulas.bakeSeconds(recipeId: string, ovenLevel: number): number
	local recipe = Recipes[recipeId]
	if recipe == nil then
		return 0
	end
	local multiplier = math.max(Upgrades.OvenMinTimeMultiplier, 1 - ovenLevel * Upgrades.OvenSpeedBonusPerLevel)
	return math.ceil(recipe.BakeTimeSeconds * multiplier)
end

function Formulas.hearts(now: number, createdAt: number, expiresAt: number): number
	local total = expiresAt - createdAt
	if total <= 0 then
		return 0
	end
	local remaining = math.clamp(expiresAt - now, 0, total)
	if remaining <= 0 then
		return 0
	end
	return math.clamp(math.ceil(remaining / total * Customers.HeartCount), 1, Customers.HeartCount)
end

function Formulas.serveCoins(recipeId: string, amount: number, hearts: number, counterLevel: number): number
	local recipe = Recipes[recipeId]
	if recipe == nil then
		return 0
	end
	local heartMultiplier = Customers.HeartCoinMultiplier[hearts] or Customers.HeartCoinMultiplier[1]
	local tip = 1 + counterLevel * Upgrades.CounterTipBonusPerLevel
	return math.floor(recipe.SellPrice * amount * heartMultiplier * tip)
end

function Formulas.questDay(unixTime: number, secondsPerDay: number): number
	return math.floor(unixTime / secondsPerDay)
end

return Formulas
