--!strict
-- DayNightService: วงจรกลางวัน/กลางคืนของรอบ (server เป็นผู้ตัดสินเวลาและ phase)
-- Day -> Dusk -> Night -> Dawn -> Day (ช่วงเปลี่ยนที่ยาว 0 วินาทีถูกข้าม)
-- เริ่มนับเมื่อผู้เล่นคนแรกเข้า หยุดเมื่อไม่มีผู้เล่น และนับต่อจากเวลาที่เหลือเดิม (เลขวันไม่รีเซ็ต)
-- สถานะอยู่ในหน่วยความจำของ server เท่านั้น ไม่บันทึก DataStore
-- sync ไป client ด้วย Attributes บน ReplicatedStorage (ชื่อใน Config/DayNight)
-- เลขคืน = เลขวันเดียวกัน: Dusk/Night/Dawn ของ "วันที่ N" คือ "คืนที่ N"
-- API สำหรับระบบอื่น: GetPhase, GetDayNumber, GetNightNumber, GetTimeRemaining, IsNight, IsRunning
-- สัญญาณภายใน (BindableEvent ไม่ส่งให้ client): OnPhaseChanged(phase, dayNumber),
--   OnNightStarted(nightNumber) ตอนเริ่ม Night, OnMorningStarted(dayNumber) ตอนเริ่ม Day หลัง Dawn
-- วันที่ 1 ตอนเริ่มรอบยิงเฉพาะ OnPhaseChanged (ไม่ใช่ OnMorningStarted)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DayNight = require(ReplicatedStorage.Shared.Config.DayNight)
local NotifyConfig = require(ReplicatedStorage.Shared.Config.Notify)
local DayNightRules = require(ReplicatedStorage.Shared.DayNightRules)
local NotifyService = require(script.Parent.NotifyService)

local LOG = "[DayNightService]"

type Phase = DayNight.Phase
type Durations = DayNight.Durations

local phaseChanged = Instance.new("BindableEvent")
local nightStarted = Instance.new("BindableEvent")
local morningStarted = Instance.new("BindableEvent")

local DayNightService = {}

DayNightService.OnPhaseChanged = phaseChanged.Event
DayNightService.OnNightStarted = nightStarted.Event
DayNightService.OnMorningStarted = morningStarted.Event

local durations: Durations = DayNight.Fallback
local configProblems: { DayNightRules.Problem } = {}

local started = false -- เริ่มรอบแล้ว (มี phase)
local running = false -- กำลังนับเวลา
local phase: Phase = "Day"
local day = 1
local remaining = 0 -- วินาทีที่เหลือตอนหยุดนับ
local endsAt = 0 -- เวลา server ที่ phase จะจบ (ใช้ตอนกำลังนับ)
local warned = false
local phaseThread: thread? = nil
local warnThread: thread? = nil

local function playerCount(excluding: Player?): number
	local count = 0
	for _, player in Players:GetPlayers() do
		if player ~= excluding then
			count += 1
		end
	end
	return count
end

local function broadcast(key: string, kind: NotifyConfig.Kind, args: { [string]: string | number }?)
	for _, player in Players:GetPlayers() do
		NotifyService.Notify(player, key, kind, args)
	end
end

local function publish()
	ReplicatedStorage:SetAttribute(DayNight.AttributePhase, phase)
	ReplicatedStorage:SetAttribute(DayNight.AttributeDay, day)
	ReplicatedStorage:SetAttribute(DayNight.AttributePhaseSeconds, DayNightRules.DurationFor(phase, durations))
	ReplicatedStorage:SetAttribute(DayNight.AttributePhaseEndsAt, if running then endsAt else nil)
end

local function cancelThreads()
	if phaseThread ~= nil then
		task.cancel(phaseThread)
		phaseThread = nil
	end
	if warnThread ~= nil then
		task.cancel(warnThread)
		warnThread = nil
	end
end

local advance: () -> ()

-- ตั้งตัวจับเวลาของ phase ปัจจุบันจากเวลาที่เหลือ
local function schedule()
	cancelThreads()
	endsAt = Workspace:GetServerTimeNow() + remaining
	phaseThread = task.delay(remaining, advance)
	if phase == "Day" and not warned then
		local untilWarning = remaining - durations.WarningSeconds
		-- เข้ามาตอนเหลือเวลาน้อยกว่าค่าเตือน (หรือปิดการเตือน) ไม่ยิงย้อนหลัง
		if durations.WarningSeconds <= 0 or untilWarning <= 0 then
			warned = true
		else
			warnThread = task.delay(untilWarning, function()
				warnThread = nil
				warned = true
				broadcast("DayNightDuskWarning", "info", { seconds = math.round(durations.WarningSeconds) })
			end)
		end
	end
	publish()
end

local function enterPhase(nextState: DayNightRules.State, announce: boolean)
	local previousPhase = phase
	phase = nextState.Phase
	day = nextState.Day
	remaining = DayNightRules.DurationFor(phase, durations)
	if phase == "Day" then
		warned = false
	end
	schedule()
	phaseChanged:Fire(phase, day)
	if not announce then
		return
	end
	if phase == "Night" then
		broadcast("DayNightNightStarted", "info", { night = day })
		nightStarted:Fire(day)
	elseif phase == "Day" and previousPhase ~= "Day" then
		broadcast("DayNightMorningStarted", "success", { day = day })
		morningStarted:Fire(day)
	end
end

advance = function()
	phaseThread = nil
	enterPhase(DayNightRules.Step({ Phase = phase, Day = day }, durations), true)
end

local function pause()
	if not running then
		return
	end
	remaining = DayNightRules.Remaining(endsAt, Workspace:GetServerTimeNow())
	running = false
	cancelThreads()
	publish()
end

local function resume()
	if running then
		return
	end
	running = true
	if not started then
		started = true
		enterPhase({ Phase = "Day", Day = day }, false)
		return
	end
	schedule()
end

local function notifyConfigProblems(player: Player)
	if not RunService:IsStudio() then
		return
	end
	for _, problem in configProblems do
		NotifyService.Notify(player, "DayNightConfigInvalid", "error", {
			field = problem.Field,
			value = string.sub(problem.Value, 1, NotifyConfig.MaxArgLength),
			used = problem.Used,
		})
	end
end

local function onPlayerAdded(player: Player)
	notifyConfigProblems(player)
	resume()
end

local function onPlayerRemoving(player: Player)
	if playerCount(player) == 0 then
		pause()
	end
end

function DayNightService.GetPhase(): Phase
	return phase
end

function DayNightService.GetDayNumber(): number
	return day
end

function DayNightService.GetNightNumber(): number
	return day
end

function DayNightService.IsNight(): boolean
	return phase == "Night"
end

function DayNightService.IsRunning(): boolean
	return running
end

function DayNightService.GetTimeRemaining(): number
	if running then
		return DayNightRules.Remaining(endsAt, Workspace:GetServerTimeNow())
	end
	return remaining
end

function DayNightService.Start()
	local chosen = if RunService:IsStudio() then DayNight.Studio else DayNight.Production
	local validated, problems = DayNightRules.Validate(DayNightRules.ToMap(chosen), DayNight.Fallback)
	durations = validated
	configProblems = problems
	for _, problem in problems do
		warn(
			`{LOG} Config/DayNight ช่อง {problem.Field} ไม่ถูกต้อง (ค่า {problem.Value}) ใช้ค่าสำรอง {problem.Used}`
		)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return DayNightService
