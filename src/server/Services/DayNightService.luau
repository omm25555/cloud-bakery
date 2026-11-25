--!strict
-- DayNightService: วงจรกลางวัน/กลางคืนของรอบ (server เป็นผู้ตัดสินเวลาและ phase)
-- Day -> Dusk -> Night -> Dawn -> Day (ช่วงเปลี่ยนที่ยาว 0 วินาทีถูกข้าม)
-- เริ่มนับเมื่อผู้เล่นคนแรกเข้า หยุดเมื่อไม่มีผู้เล่น และนับต่อจากเวลาที่เหลือเดิม (เลขวันไม่รีเซ็ต)
-- สถานะอยู่ในหน่วยความจำของ server เท่านั้น ไม่บันทึก DataStore
-- sync ไป client ด้วย Attributes บน ReplicatedStorage (ชื่อใน Config/DayNight)
-- เลขคืน = เลขวันเดียวกัน: Dusk/Night/Dawn ของ "วันที่ N" คือ "คืนที่ N"
-- โหมด (Easy/Hard/Nightmare) อ่านจาก attribute DayNightMode บน ReplicatedStorage ตอนเริ่มรอบ (ผู้เล่นคนแรกเข้า)
--   ไม่มี = Easy, ไม่รู้จัก = Easy พร้อม warn ความยาวช่วงตามโหมดอยู่ใน Config/DayNight
-- API สำหรับระบบอื่น: GetMode, GetPhase, GetDayNumber, GetNightNumber, GetTimeRemaining, IsNight, IsRunning
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

-- ยิงทุกครั้งที่เข้า phase ใหม่ (รวม Day วันที่ 1 ตอนเริ่มรอบ)
function DayNightService.OnPhaseChanged(callback: (phase: Phase, dayNumber: number) -> ()): RBXScriptConnection
	return phaseChanged.Event:Connect(callback)
end

-- ยิงตอนเริ่ม Night ส่งเลขคืน (= เลขวันเดียวกัน)
function DayNightService.OnNightStarted(callback: (nightNumber: number) -> ()): RBXScriptConnection
	return nightStarted.Event:Connect(callback)
end

-- ยิงตอนเริ่ม Day หลัง Dawn ส่งเลขวันใหม่ (ไม่ยิงตอนเริ่มรอบวันที่ 1)
function DayNightService.OnMorningStarted(callback: (dayNumber: number) -> ()): RBXScriptConnection
	return morningStarted.Event:Connect(callback)
end

local durations: Durations = DayNight.Fallback
local configProblems: { DayNightRules.Problem } = {}
local mode: string = DayNight.DefaultMode

local started = false -- เริ่มรอบแล้ว (มี phase)
local running = false -- กำลังนับเวลา
local phase: Phase = "Day"
local day = 1
local remaining = 0 -- วินาทีที่เหลือตอนหยุดนับ
local endsAt = 0 -- เวลา server ที่ phase จะจบ (ใช้ตอนกำลังนับ)
local warned = false
local phaseThread: thread? = nil
local warnThread: thread? = nil
local retryThread: thread? = nil

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
				local warningArgs: { [string]: string | number } = { seconds = math.round(durations.WarningSeconds) }
				broadcast("DayNightDuskWarning", "info", warningArgs)
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
		local nightArgs: { [string]: string | number } = { night = day }
		broadcast("DayNightNightStarted", "info", nightArgs)
		nightStarted:Fire(day)
	elseif phase == "Day" and previousPhase ~= "Day" then
		local morningArgs: { [string]: string | number } = { day = day }
		broadcast("DayNightMorningStarted", "success", morningArgs)
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

-- เลือกโหมดและตรวจค่า config ของโหมดนั้น (เรียกครั้งเดียวตอนเริ่มรอบ)
local function loadConfig()
	configProblems = {}
	local sets = if RunService:IsStudio() then DayNight.Studio else DayNight.Production
	local raw = ReplicatedStorage:GetAttribute(DayNight.AttributeMode)
	local resolved, known = DayNightRules.ResolveMode(raw, sets, DayNight.DefaultMode)
	mode = resolved
	if not known then
		table.insert(configProblems, { Field = "Mode", Value = tostring(raw), Used = resolved })
	end
	local chosen = sets[mode]
	local candidate: { [string]: unknown } = if chosen ~= nil then DayNightRules.ToMap(chosen) else {}
	local validated, problems = DayNightRules.Validate(candidate, DayNight.Fallback)
	durations = validated
	for _, problem in problems do
		table.insert(configProblems, problem)
	end
	for _, problem in configProblems do
		warn(`{LOG} Config/DayNight ช่อง {problem.Field} ไม่ถูกต้อง (ค่า {problem.Value}) ใช้ค่าสำรอง {problem.Used}`)
	end
end

local resume: () -> ()

local function cancelRetry()
	if retryThread ~= nil then
		task.cancel(retryThread)
		retryThread = nil
	end
end

-- เริ่มรอบพลาด: คืนสถานะ ไม่ให้ค้าง แจ้งผู้เล่นทุกคนครั้งเดียวต่อการล้ม แล้วลองใหม่อัตโนมัติ (ไม่ซ้อนหลาย thread)
local function onStartFailed(err: string)
	running = false
	cancelThreads()
	cancelRetry()
	publish() -- ล้างเวลาจบ phase ที่อาจถูก publish ไปแล้วก่อน error
	warn(`{LOG} เริ่มวงจรวัน/คืนไม่สำเร็จ ลองใหม่ใน {DayNight.StartRetrySeconds} วินาที: {err}`)
	if playerCount(nil) == 0 then
		return
	end
	broadcast("DayNightStartFailed", "error", nil)
	retryThread = task.delay(DayNight.StartRetrySeconds, function()
		retryThread = nil
		if playerCount(nil) > 0 then
			resume()
		end
	end)
end

resume = function()
	if running then
		return
	end
	cancelRetry()
	running = true
	if not started then
		local ok, err = pcall(function()
			loadConfig()
			enterPhase({ Phase = "Day", Day = day }, false)
		end)
		if not ok then
			onStartFailed(tostring(err))
			return
		end
		started = true
		return
	end
	schedule()
end

local function notifyConfigProblems(player: Player)
	if not RunService:IsStudio() then
		return
	end
	for _, problem in configProblems do
		local args: { [string]: string | number } = {
			field = problem.Field,
			value = string.sub(problem.Value, 1, NotifyConfig.MaxArgLength),
			used = problem.Used,
		}
		NotifyService.Notify(player, "DayNightConfigInvalid", "error", args)
	end
end

local function onPlayerAdded(player: Player)
	resume()
	notifyConfigProblems(player)
end

local function onPlayerRemoving(player: Player)
	if playerCount(player) == 0 then
		cancelRetry()
		pause()
	end
end

function DayNightService.GetMode(): string
	return mode
end

function DayNightService.GetPhase(): Phase
	return phase
end

function DayNightService.GetDayNumber(): number
	return day
end

-- เลขคืน = เลขวันเดียวกัน คืนของ "วันนี้" (คืนที่กำลังจะมาถึงตอน Day/Dusk หรือคืนที่กำลังเป็นอยู่ตอน Night/Dawn)
-- ตอน Day วันที่ N คืนนี้คืน N ยังไม่เกิด ถ้าต้องการรู้ว่าอยู่ในคืนหรือไม่ให้ใช้ IsNight()
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
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return DayNightService
