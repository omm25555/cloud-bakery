--!strict
-- SanityRules: ฟังก์ชันล้วนของสติ (ไม่แตะ Workspace/Players)

local SanityRules = {}

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value :: number) ~= math.huge
end

function SanityRules.IsValidDelta(delta: unknown): boolean
	return isFiniteNumber(delta)
end

-- คืนสติใหม่หลังบวก delta (จำกัด 0..max ปัดเป็นจำนวนเต็ม)
function SanityRules.Apply(current: number, delta: number, max: number): number
	return math.clamp(math.round(current + delta), 0, max)
end

function SanityRules.IsDepleted(value: number): boolean
	return value <= 0
end

function SanityRules.Ratio(value: number, max: number): number
	if max <= 0 then
		return 0
	end
	return math.clamp(value / max, 0, 1)
end

-- ตรวจค่าตั้ง คืนเหตุผลที่ผิด (nil = ผ่าน)
function SanityRules.Validate(values: { [string]: unknown }): string?
	local max = values.Max
	local start = values.Start
	if not isFiniteNumber(max) or (max :: number) <= 0 then
		return "Max ต้องเป็นตัวเลข > 0"
	end
	if not isFiniteNumber(start) or (start :: number) <= 0 or (start :: number) > (max :: number) then
		return "Start ต้องเป็นตัวเลข > 0 และไม่เกิน Max"
	end
	for _, name in { "WrongReport", "MissedAnomaly", "LeftoverCustomer" } do
		local value = values[name]
		if not isFiniteNumber(value) or (value :: number) < 0 then
			return `{name} ต้องเป็นตัวเลข >= 0`
		end
	end
	return nil
end

return SanityRules
