--!strict
-- ReportRules: ฟังก์ชันล้วนของระบบรายงานผู้จัดการ (ตรวจ payload, ระดับหลอน, เลือกบรรทัดบท, ระยะ)
-- ค่าสุ่ม (roll 0-1) ส่งเข้ามาจากผู้เรียกเพื่อให้ทดสอบได้

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ManagerLines = require(ReplicatedStorage.Shared.Config.ManagerLines)

local ReportRules = {}

local function contains(list: { string }, value: string): boolean
	return table.find(list, value) ~= nil
end

-- ตรวจ payload ของ ReportSubmit คืน (category, customerId, nil) หรือ (nil, nil, เหตุผลที่ไม่ผ่าน)
function ReportRules.ParseSubmit(
	categoryRaw: unknown,
	customerRaw: unknown,
	categories: { string },
	maxLength: number
): (string?, string?, string?)
	if type(categoryRaw) ~= "string" then
		return nil, nil, `category ไม่ใช่ string ({typeof(categoryRaw)})`
	end
	local category = categoryRaw :: string
	if #category == 0 or #category > maxLength then
		return nil, nil, `category ยาว {#category} ตัวอักษร (ต้อง 1-{maxLength})`
	end
	if not contains(categories, category) then
		return nil, nil, `ไม่รู้จักหมวด "{category}"`
	end
	local customerId: string? = nil
	if customerRaw ~= nil then
		if type(customerRaw) ~= "string" then
			return nil, nil, `customerId ไม่ใช่ string ({typeof(customerRaw)})`
		end
		local rawId = customerRaw :: string
		if #rawId == 0 or #rawId > maxLength then
			return nil, nil, `customerId ยาว {#rawId} ตัวอักษร (ต้อง 1-{maxLength})`
		end
		customerId = rawId
	end
	if category == "customer" and customerId == nil then
		return nil, nil, "หมวด customer ต้องระบุ customerId"
	end
	if category ~= "customer" and customerId ~= nil then
		return nil, nil, `customerId ใช้ได้เฉพาะหมวด customer (หมวด {category})`
	end
	return category, customerId, nil
end

-- ระดับหลอน 1..#thresholds จากจำนวนครั้งที่ผิด (thresholds เรียงน้อยไปมาก) คืน 1 ขั้นต่ำเสมอ
function ReportRules.HauntLevel(wrongCount: number, thresholds: { number }): number
	local level = 0
	for index, threshold in thresholds do
		if wrongCount >= threshold then
			level = index
		end
	end
	return math.max(level, 1)
end

function ReportRules.WrongSituation(level: number): string
	return `Wrong{level}`
end

-- สุ่มบรรทัดบท คืน nil ถ้าสถานการณ์นั้นไม่มีบรรทัด (ผู้เรียกใช้ FallbackLine และ warn)
function ReportRules.PickLine(situation: string, language: string, roll: number): string?
	local entry = ManagerLines.Situations[situation]
	if entry == nil then
		return nil
	end
	local list = if language == "en" then entry.en else entry.th
	if #list == 0 then
		return nil
	end
	local index = math.clamp(math.floor(roll * #list) + 1, 1, #list)
	return list[index]
end

function ReportRules.FallbackLine(language: string): string
	return if language == "en" then ManagerLines.FallbackLine.en else ManagerLines.FallbackLine.th
end

function ReportRules.WithinDistance(a: Vector3, b: Vector3, maxDistance: number): boolean
	return (a - b).Magnitude <= maxDistance
end

-- ตรวจค่าตั้ง/บท คืนรายการปัญหา (ว่าง = ผ่าน)
function ReportRules.ValidateSetup(thresholds: { number }, styleCount: number): { string }
	local problems: { string } = {}
	if #thresholds == 0 or thresholds[1] ~= 1 then
		table.insert(problems, "WrongHauntLevels ต้องมีอย่างน้อย 1 ตัวและตัวแรกเป็น 1")
	end
	for index = 2, #thresholds do
		if thresholds[index] <= thresholds[index - 1] then
			table.insert(problems, "WrongHauntLevels ต้องเรียงจากน้อยไปมากและไม่ซ้ำ")
			break
		end
	end
	if styleCount ~= #thresholds then
		table.insert(problems, `HauntStyles ({styleCount}) ต้องมีจำนวนเท่า WrongHauntLevels ({#thresholds})`)
	end
	local needed: { string } = { "Praise", "MenuOpen", "WrongNone" }
	for level = 1, #thresholds do
		table.insert(needed, ReportRules.WrongSituation(level))
	end
	for _, situation in needed do
		for _, language in { "th", "en" } do
			if ReportRules.PickLine(situation, language, 0) == nil then
				table.insert(problems, `Config/ManagerLines: {situation} ({language}) ไม่มีบรรทัด`)
			end
		end
	end
	return problems
end

return ReportRules
