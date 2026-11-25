--!strict
-- DayNightRules: ฟังก์ชันล้วน (ไม่มี side effect) ของวงจรกลางวัน/กลางคืน
-- ตรวจ config, หา phase ถัดไป, เวลาที่เหลือ, สัดส่วน lighting และรูปแบบนาฬิกา

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DayNight = require(ReplicatedStorage.Shared.Config.DayNight)

type Phase = DayNight.Phase
type Durations = DayNight.Durations

export type Problem = {
	Field: string,
	Value: string,
	Used: string | number,
}

export type State = {
	Phase: Phase,
	Day: number,
}

local DayNightRules = {}

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value :: number) ~= math.huge
end

local function isValid(field: string, value: unknown): boolean
	if not isFiniteNumber(value) then
		return false
	end
	local number = value :: number
	if DayNight.ZeroAllowed[field] == true then
		return number >= 0
	end
	return number > 0
end

-- โหมดที่ใช้จริง: ไม่มีค่า = defaultMode (ไม่ใช่ปัญหา), ไม่รู้จัก = defaultMode และ known=false
function DayNightRules.ResolveMode(raw: unknown, modes: { [string]: Durations }, defaultMode: string): (string, boolean)
	if raw == nil then
		return defaultMode, true
	end
	if type(raw) == "string" and modes[raw] ~= nil then
		return raw, true
	end
	return defaultMode, false
end

function DayNightRules.ToMap(durations: Durations): { [string]: unknown }
	return {
		DaySeconds = durations.DaySeconds,
		DuskSeconds = durations.DuskSeconds,
		NightSeconds = durations.NightSeconds,
		DawnSeconds = durations.DawnSeconds,
		WarningSeconds = durations.WarningSeconds,
	}
end

-- ตรวจค่าทีละช่อง ช่องที่ผิดใช้ค่าจาก fallback แล้วรายงานใน problems
function DayNightRules.Validate(candidate: { [string]: unknown }, fallback: Durations): (Durations, { Problem })
	local fallbackMap = DayNightRules.ToMap(fallback)
	local problems: { Problem } = {}
	local function pick(field: string): number
		local value = candidate[field]
		if isValid(field, value) then
			return value :: number
		end
		local used = fallbackMap[field] :: number
		table.insert(problems, { Field = field, Value = tostring(value), Used = used })
		return used
	end
	local result: Durations = {
		DaySeconds = pick("DaySeconds"),
		DuskSeconds = pick("DuskSeconds"),
		NightSeconds = pick("NightSeconds"),
		DawnSeconds = pick("DawnSeconds"),
		WarningSeconds = pick("WarningSeconds"),
	}
	-- เตือนก่อนค่ำต้องสั้นกว่ากลางวัน ถ้าไม่เป็นจริงใช้ทั้งคู่จาก fallback
	if result.WarningSeconds >= result.DaySeconds then
		table.insert(problems, {
			Field = "WarningSeconds",
			Value = tostring(result.WarningSeconds),
			Used = fallback.WarningSeconds,
		})
		table.insert(problems, {
			Field = "DaySeconds",
			Value = tostring(result.DaySeconds),
			Used = fallback.DaySeconds,
		})
		result.WarningSeconds = fallback.WarningSeconds
		result.DaySeconds = fallback.DaySeconds
	end
	return result, problems
end

function DayNightRules.DurationFor(phase: Phase, durations: Durations): number
	if phase == "Day" then
		return durations.DaySeconds
	elseif phase == "Dusk" then
		return durations.DuskSeconds
	elseif phase == "Night" then
		return durations.NightSeconds
	end
	return durations.DawnSeconds
end

local function indexOf(phase: Phase): number
	for index, name in DayNight.PhaseOrder do
		if name == phase then
			return index
		end
	end
	return 1
end

-- phase ถัดไป ข้ามช่วงที่ยาว 0 วินาที เลขวันเพิ่มเมื่อวนกลับมาเริ่ม Day
function DayNightRules.Step(state: State, durations: Durations): State
	local order: { Phase } = DayNight.PhaseOrder
	local count = #order
	local index = indexOf(state.Phase)
	for offset = 1, count do
		local nextIndex = (index - 1 + offset) % count + 1
		local candidate = order[nextIndex]
		if DayNightRules.DurationFor(candidate, durations) > 0 then
			local wrapped = nextIndex <= index
			local result: State = { Phase = candidate, Day = if wrapped then state.Day + 1 else state.Day }
			return result
		end
	end
	return state
end

function DayNightRules.IsPhase(value: unknown): boolean
	for _, name in DayNight.PhaseOrder do
		if name == value then
			return true
		end
	end
	return false
end

function DayNightRules.Remaining(endsAt: number, now: number): number
	return math.max(0, endsAt - now)
end

-- สัดส่วนที่ผ่านไปของ phase (0..1)
function DayNightRules.Fraction(remaining: number, phaseSeconds: number): number
	if phaseSeconds <= 0 then
		return 0
	end
	return math.clamp(1 - remaining / phaseSeconds, 0, 1)
end

-- ความเป็นกลางคืน 0 = Day, 1 = Night
function DayNightRules.NightAlpha(phase: Phase, fraction: number): number
	if phase == "Night" then
		return 1
	elseif phase == "Dusk" then
		return fraction
	elseif phase == "Dawn" then
		return 1 - fraction
	end
	return 0
end

local function forwardDelta(from: number, to: number): number
	return (to - from) % DayNight.HoursPerDay
end

-- ClockTime หมุนไปข้างหน้าเสมอ: Dusk จาก Day ไป Night, Dawn จาก Night ไป Day
function DayNightRules.ClockTime(phase: Phase, fraction: number): number
	local dayClock = DayNight.DayLook.ClockTime
	local nightClock = DayNight.NightLook.ClockTime
	if phase == "Day" then
		return dayClock
	elseif phase == "Night" then
		return nightClock
	elseif phase == "Dusk" then
		return (dayClock + fraction * forwardDelta(dayClock, nightClock)) % DayNight.HoursPerDay
	end
	return (nightClock + fraction * forwardDelta(nightClock, dayClock)) % DayNight.HoursPerDay
end

function DayNightRules.Lerp(from: number, to: number, alpha: number): number
	return from + (to - from) * alpha
end

-- รูปแบบ M:SS
function DayNightRules.FormatClock(seconds: number): string
	local total = math.ceil(math.max(0, seconds))
	local minutes = total // DayNight.SecondsPerMinute
	local rest = total % DayNight.SecondsPerMinute
	return string.format("%d:%02d", minutes, rest)
end

return DayNightRules
