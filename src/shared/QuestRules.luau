--!strict
-- กติกาล้วนของ Daily Quest ที่ใช้ร่วมกัน (QuestService / QuestPanelController / DataService)
-- วันคำนวณจากเวลา epoch + offset ใน Config/Quests เท่านั้น ไม่เก็บสถานะ ไม่ yield

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local Quests = require(ReplicatedStorage.Shared.Config.Quests)

type QuestData = PlayerDataConfig.QuestData

local SECONDS_PER_HOUR = 3600
local SECONDS_PER_MINUTE = 60

local QuestRules = {}

-- ดัชนีวัน (เริ่มที่ 1 เพื่อให้ 0 = ยังไม่เคยเริ่ม)
function QuestRules.DayIndex(now: number): number
	return math.floor((now + Quests.ResetOffsetSeconds) / Quests.DayLengthSeconds) + 1
end

-- เวลา epoch ที่วันนี้สิ้นสุด (เริ่มวันถัดไป)
function QuestRules.ResetAt(day: number): number
	return day * Quests.DayLengthSeconds - Quests.ResetOffsetSeconds
end

-- ความคืบหน้าที่ใช้ได้: จำนวนเต็ม 0..target (ค่าเสีย/NaN = 0)
function QuestRules.ClampProgress(progress: number, target: number): number
	if progress ~= progress then
		return 0
	end
	return math.floor(math.clamp(progress, 0, target))
end

function QuestRules.FormatCountdown(seconds: number): string
	local total = math.max(0, math.ceil(seconds))
	return string.format(
		"%d:%02d:%02d",
		total // SECONDS_PER_HOUR,
		(total % SECONDS_PER_HOUR) // SECONDS_PER_MINUTE,
		total % SECONDS_PER_MINUTE
	)
end

function QuestRules.Copy(source: QuestData): QuestData
	local progress: { [string]: number } = {}
	for id, value in source.Progress do
		progress[id] = value
	end
	local claimed: { [string]: boolean } = {}
	for id, value in source.Claimed do
		claimed[id] = value
	end
	return { Day = source.Day, Progress = progress, Claimed = claimed }
end

-- แปลงข้อมูลดิบจาก DataStore เป็น QuestData ที่ปลอดภัย
-- key ที่ไม่อยู่ในรายการเควสถูกทิ้งเงียบ ๆ, ค่าผิดชนิดเรียก onWarn, ความคืบหน้าเกินขอบเขตถูก clamp
function QuestRules.Sanitize(raw: unknown, onWarn: (string) -> ()): QuestData
	local result: QuestData = { Day = 0, Progress = {}, Claimed = {} }
	if raw == nil then
		return result
	end
	if type(raw) ~= "table" then
		onWarn("ไม่ใช่ table ใช้ค่าเริ่มต้น")
		return result
	end
	local data = raw :: { [string]: unknown }
	local limits = PlayerDataConfig.Limits

	local day = data.Day
	if type(day) == "number" then
		local maxDay = QuestRules.DayIndex(os.time()) + Quests.MaxFutureDays
		if day == day and day >= 0 and day <= maxDay and day == math.floor(day) then
			result.Day = day
		else
			onWarn(`Day ไม่ถูกต้อง ({day}) ใช้ค่าเริ่มต้น`)
		end
	elseif day ~= nil then
		onWarn("Day ไม่ใช่ number ใช้ค่าเริ่มต้น")
	end

	local progress = data.Progress
	if type(progress) == "table" then
		for id, value in progress :: { [unknown]: unknown } do
			if type(id) == "string" and Quests.ById[id] ~= nil then
				if type(value) == "number" and value == value then
					result.Progress[id] = math.floor(math.clamp(value, 0, limits.MaxQuestProgress))
				else
					onWarn(`Progress.{id} ไม่ถูกต้อง ข้ามค่านี้`)
				end
			end
		end
	elseif progress ~= nil then
		onWarn("Progress ไม่ใช่ table ใช้ค่าเริ่มต้น")
	end

	local claimed = data.Claimed
	if type(claimed) == "table" then
		for id, value in claimed :: { [unknown]: unknown } do
			if type(id) == "string" and Quests.ById[id] ~= nil then
				if value == true then
					result.Claimed[id] = true
				elseif value ~= false then
					onWarn(`Claimed.{id} ไม่ใช่ boolean ข้ามค่านี้`)
				end
			end
		end
	elseif claimed ~= nil then
		onWarn("Claimed ไม่ใช่ table ใช้ค่าเริ่มต้น")
	end

	return result
end

return QuestRules
