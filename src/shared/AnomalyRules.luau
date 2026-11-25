--!strict
-- AnomalyRules: ฟังก์ชันล้วน (ไม่แตะ Workspace) ของระบบ anomaly
-- ตรวจ config, สุ่มตาม weight, คำนวณโควตาลูกค้ากลางคืน และนับ roster
-- ค่าสุ่ม (roll) ส่งเข้ามาจากผู้เรียกเพื่อให้ทดสอบได้

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Anomalies = require(ReplicatedStorage.Shared.Config.Anomalies)

export type SlotState = "Pending" | "Served" | "Reported" | "Missed"

export type Slot = {
	SlotId: number,
	State: SlotState,
	IsAnomalous: boolean,
	CustomerId: string?, -- id จาก Config/Customers (ถ้ามี)
}

-- ตัวช่วยที่ AnomalyService ให้โมดูลพฤติกรรม (<Id>.luau) เพื่อให้คืนสภาพได้แม้โมดูลเขียนพลาด
export type Context = {
	Entry: Anomalies.Entry,
	Target: Instance,
	Container: Folder, -- ของที่สร้างเพิ่มต้องวางในนี้ (ล้างตอนเช้า)
	Rng: Random,
	SetColor: (part: BasePart, color: Color3) -> (), -- จำสีเดิมไว้คืนตอนเช้า
	SetCFrame: (part: BasePart, cframe: CFrame) -> (), -- จำ CFrame เดิมไว้คืนตอนเช้า
	Track: (instance: Instance) -> (), -- ลงทะเบียนของที่สร้างเพิ่ม ถูก Destroy ตอนคืนสภาพ
}

export type Handle = {
	Description: string, -- ข้อความ log เช่น "OrderCounter เปลี่ยนสี"
	CustomerId: string?, -- เฉพาะหมวด customer
	Revert: (() -> ())?, -- งานคืนสภาพเพิ่มเติม (ไม่บังคับ)
}

export type Behavior = {
	Spawn: (context: Context) -> (Handle?, string?), -- (handle, nil) หรือ (nil, เหตุผลที่ทำไม่ได้)
}

local AnomalyRules = {}

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value :: number) ~= math.huge
end

local function isInteger(value: unknown): boolean
	return isFiniteNumber(value) and (value :: number) == math.floor(value :: number)
end

local function contains(list: { string }, value: string): boolean
	for _, item in list do
		if item == value then
			return true
		end
	end
	return false
end

function AnomalyRules.EntryToMap(entry: Anomalies.Entry): { [string]: unknown }
	return {
		Id = entry.Id,
		NameKey = entry.NameKey,
		Category = entry.Category,
		Weight = entry.Weight,
		Subtlety = entry.Subtlety,
		Folder = entry.Folder,
		Targets = entry.Targets,
	}
end

-- ตรวจ entry หนึ่งตัว คืนเหตุผลที่ใช้ไม่ได้ (nil = ผ่าน) seenIds ใช้ตรวจ id ซ้ำ (ผู้เรียกเป็นคนเพิ่ม id ที่ผ่านแล้ว)
function AnomalyRules.ValidateEntry(
	map: { [string]: unknown },
	categories: { string },
	hasString: (key: string) -> boolean,
	seenIds: { [string]: boolean }
): string?
	local id = map.Id
	if type(id) ~= "string" or id == "" then
		return `Id ต้องเป็นข้อความที่ไม่ว่าง (ค่า {tostring(id)})`
	end
	if seenIds[id] then
		return `Id ซ้ำ ({id})`
	end
	local weight = map.Weight
	if not isFiniteNumber(weight) or (weight :: number) <= 0 then
		return `Weight ต้องเป็นตัวเลขมากกว่า 0 (ค่า {tostring(weight)})`
	end
	local subtlety = map.Subtlety
	if not isFiniteNumber(subtlety) or (subtlety :: number) <= 0 then
		return `Subtlety ต้องเป็นตัวเลขมากกว่า 0 (ค่า {tostring(subtlety)})`
	end
	local category = map.Category
	if type(category) ~= "string" or not contains(categories, category) then
		return `Category ไม่อยู่ใน Categories (ค่า {tostring(category)})`
	end
	local nameKey = map.NameKey
	if type(nameKey) ~= "string" or not hasString(nameKey) then
		return `NameKey ไม่มีใน Config/Strings (ค่า {tostring(nameKey)})`
	end
	local folder = map.Folder
	if type(folder) ~= "string" or folder == "" then
		return `Folder ต้องเป็นข้อความที่ไม่ว่าง (ค่า {tostring(folder)})`
	end
	local targets = map.Targets
	if type(targets) ~= "table" or #(targets :: { unknown }) == 0 then
		return "Targets ว่างหรือไม่ใช่รายการ"
	end
	for _, target in targets :: { unknown } do
		if type(target) ~= "string" or target == "" then
			return `Targets มีค่าที่ไม่ใช่ข้อความ ({tostring(target)})`
		end
	end
	return nil
end

-- ตรวจค่าโหมด คืนเหตุผลที่ผิด (nil = ผ่าน)
function AnomalyRules.ValidateMode(settings: Anomalies.ModeSettings, nightTypes: { string }): string?
	local total = 0
	for name, weight in settings.NightTypeWeights do
		if not contains(nightTypes, name) then
			return `NightTypeWeights มีชนิดคืนที่ไม่รู้จัก ({name})`
		end
		if not isFiniteNumber(weight) or weight < 0 then
			return `NightTypeWeights.{name} ต้องเป็นตัวเลข >= 0 (ค่า {tostring(weight)})`
		end
		total += weight
	end
	if total <= 0 then
		return "NightTypeWeights รวมต้องมากกว่า 0"
	end
	if not isFiniteNumber(settings.MaxSubtlety) or settings.MaxSubtlety <= 0 then
		return `MaxSubtlety ต้องเป็นตัวเลขมากกว่า 0 (ค่า {tostring(settings.MaxSubtlety)})`
	end
	if not isInteger(settings.AnomaliesMin) or not isInteger(settings.AnomaliesMax) then
		return "AnomaliesMin/AnomaliesMax ต้องเป็นจำนวนเต็ม"
	end
	if settings.AnomaliesMin < 1 or settings.AnomaliesMin > settings.AnomaliesMax then
		return `AnomaliesMin/Max ไม่สมเหตุสมผล ({settings.AnomaliesMin}..{settings.AnomaliesMax})`
	end
	local low, high = settings.SpawnWindowMin, settings.SpawnWindowMax
	if not isFiniteNumber(low) or not isFiniteNumber(high) or low < 0 or high > 1 or low > high then
		return `SpawnWindow ต้องอยู่ใน 0..1 และ Min <= Max (ค่า {tostring(low)}..{tostring(high)})`
	end
	return nil
end

-- ตรวจค่าโควตาลูกค้ากลางคืน คืนเหตุผลที่ผิด (nil = ผ่าน)
function AnomalyRules.ValidateNightCustomers(config: Anomalies.NightCustomers): string?
	local fields: { [string]: number } = {
		BaseMin = config.BaseMin,
		BaseMax = config.BaseMax,
		GrowthEveryNights = config.GrowthEveryNights,
		GrowthAmount = config.GrowthAmount,
		HardMin = config.HardMin,
		HardMax = config.HardMax,
	}
	for name, value in fields do
		if not isInteger(value) or value < 0 then
			return `{name} ต้องเป็นจำนวนเต็ม >= 0 (ค่า {tostring(value)})`
		end
	end
	if config.GrowthEveryNights < 1 then
		return "GrowthEveryNights ต้อง >= 1"
	end
	if config.HardMin < 1 or config.HardMin > config.HardMax then
		return `HardMin/HardMax ไม่สมเหตุสมผล ({config.HardMin}..{config.HardMax})`
	end
	if config.BaseMin > config.BaseMax then
		return "BaseMin ต้อง <= BaseMax"
	end
	return nil
end

-- ช่วงจำนวนลูกค้ากลางคืนของคืนที่ night: Min/Max เพิ่มทุก GrowthEveryNights คืน แล้ว clamp ที่ HardMin..HardMax
function AnomalyRules.NightCustomerRange(config: Anomalies.NightCustomers, night: number): (number, number)
	local steps = math.max(0, (night - 1) // config.GrowthEveryNights)
	local growth = steps * config.GrowthAmount
	local low = math.clamp(config.BaseMin + growth, config.HardMin, config.HardMax)
	local high = math.clamp(config.BaseMax + growth, config.HardMin, config.HardMax)
	return low, math.max(low, high)
end

-- สุ่มตาม weight: roll อยู่ใน [0,1) คืน index ของ item ที่ถูกเลือก (nil ถ้าไม่มี weight รวม > 0)
function AnomalyRules.PickIndex<T>(items: { T }, weightOf: (item: T) -> number, roll: number): number?
	local total = 0
	for _, item in items do
		total += math.max(0, weightOf(item))
	end
	if total <= 0 then
		return nil
	end
	local target = math.clamp(roll, 0, 1) * total
	local accumulated = 0
	local lastPositive: number? = nil
	for index, item in items do
		local weight = math.max(0, weightOf(item))
		if weight > 0 then
			lastPositive = index
			accumulated += weight
			if target < accumulated then
				return index
			end
		end
	end
	return lastPositive
end

-- สุ่มชนิดคืนจากตาราง weight (เรียงตาม nightTypes เพื่อให้ผลคงที่เมื่อ roll เท่าเดิม)
function AnomalyRules.PickNightType(weights: { [string]: number }, nightTypes: { string }, roll: number): string?
	local index = AnomalyRules.PickIndex(nightTypes, function(name: string): number
		return weights[name] or 0
	end, roll)
	if index == nil then
		return nil
	end
	return nightTypes[index]
end

-- แปลงค่า attribute "A,B" เป็นรายการ id (ตัดช่องว่าง ข้ามค่าว่าง ไม่ใช่ข้อความ = ว่าง)
function AnomalyRules.ParseIds(raw: unknown): { string }
	local result: { string } = {}
	if type(raw) ~= "string" then
		return result
	end
	for part in string.gmatch(raw :: string, "[^,]+") do
		local trimmed = string.match(part, "^%s*(.-)%s*$")
		if trimmed ~= nil and trimmed ~= "" then
			table.insert(result, trimmed)
		end
	end
	return result
end

function AnomalyRules.CountPending(roster: { Slot }): number
	local count = 0
	for _, slot in roster do
		if slot.State == "Pending" then
			count += 1
		end
	end
	return count
end

return AnomalyRules
