--!strict
-- NightFlowService: ต่อสัญญาณของ AnomalyService / ServeService / DayNightService เข้ากับสติและการจบคืน (TASK-014)
--  - ออเดอร์ที่เสิร์ฟตอนคืน 1 ออเดอร์ = ปิด roster 1 slot ที่ยัง Pending เป็น Served (ออเดอร์หมดเวลาไม่นับ)
--  - roster ครบ (OnRosterComplete) -> แจ้งทุกคน + นับถอยหลัง + DayNightService.RequestEndNight
--  - จบคืนแล้วลูกค้าเหลือ (OnNightEnded missed > 0) -> ทุกคนเสียสติตาม Config/Sanity.LeftoverCustomer
--  - anomaly ที่ยัง active ตอนเช้า (OnAnomalyResolved byPlayer = false) -> ทุกคนเสียสติตาม Config/Sanity.MissedAnomaly
-- การนับถอยหลังส่งให้ client ด้วย attribute บน ReplicatedStorage (Config/Report.CountdownAttribute) ไม่มี remote
-- เครื่องมือ Studio (เฉพาะ RunService:IsStudio()): attribute บน ServerStorage ชื่อ Config/Report.DebugRosterCompleteAttribute = true
--   ทำให้ roster ครบทันที (สติใช้ Config/Sanity.DebugSetAttribute ใน SanityService) ไม่มี remote

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Report = require(ReplicatedStorage.Shared.Config.Report)
local Sanity = require(ReplicatedStorage.Shared.Config.Sanity)
local AnomalyService = require(script.Parent.AnomalyService)
local DayNightService = require(script.Parent.DayNightService)
local NotifyService = require(script.Parent.NotifyService)
local SanityService = require(script.Parent.SanityService)
local ServeService = require(script.Parent.ServeService)

local LOG = "[NightFlowService]"

local NightFlowService = {}

local missedAnomalies = 0
local flushScheduled = false

local function clearCountdown()
	if ReplicatedStorage:GetAttribute(Report.CountdownAttribute) ~= nil then
		ReplicatedStorage:SetAttribute(Report.CountdownAttribute, nil)
	end
end

-- ทุกคนเสียสติ amount (ต่อคน) พร้อมแจ้งเหตุผลผ่าน key ที่ส่งมา (args ได้ lost ต่อคน)
local function drainAll(amount: number, reason: string, key: string, extra: { [string]: string | number }?)
	for _, player in Players:GetPlayers() do
		local before = SanityService.Get(player) or 0
		local after = SanityService.Change(player, -amount, reason) or before
		local args: { [string]: string | number } = { lost = before - after }
		if extra ~= nil then
			for name, value in extra do
				args[name] = value
			end
		end
		NotifyService.Notify(player, key, "error", args)
	end
end

local function onOrderServed(player: Player, orderId: number, customerId: string)
	if not DayNightService.IsNight() then
		return
	end
	local roster = AnomalyService.GetNightRoster()
	if roster.Pending == 0 then
		return
	end
	for _, slot in roster.Slots do
		if slot.State == "Pending" then
			print(`{LOG} {player.Name} เสิร์ฟออเดอร์ {orderId} ({customerId}) ตอนคืน ปิด slot {slot.SlotId} เป็น Served`)
			AnomalyService.MarkCustomerHandled(slot.SlotId, "Served")
			return
		end
	end
end

local function onRosterComplete(night: number)
	local seconds = math.min(Report.EndNightCountdownSeconds, DayNightService.GetTimeRemaining())
	if not DayNightService.RequestEndNight(Report.EndNightCountdownSeconds) then
		warn(`{LOG} คืนที่ {night}: จัดการลูกค้าครบแต่จบคืนเร็วไม่ได้ (ไม่ได้อยู่ในช่วงคืนที่กำลังนับเวลา)`)
		return
	end
	ReplicatedStorage:SetAttribute(Report.CountdownAttribute, Workspace:GetServerTimeNow() + seconds)
	local shown = math.max(1, math.round(seconds))
	print(`{LOG} คืนที่ {night}: จัดการลูกค้ากลางคืนครบ จบคืนเร็วใน {shown} วินาที`)
	for _, player in Players:GetPlayers() do
		local args: { [string]: string | number } = { seconds = shown }
		NotifyService.Notify(player, "NightServedAll", "success", args)
	end
end

local function onNightEnded(night: number, missed: number)
	if missed <= 0 then
		return
	end
	local amount = Sanity.Values.LeftoverCustomer * missed
	warn(`{LOG} คืนที่ {night} หมดเวลา ลูกค้าเหลือ {missed} คน ทุกคนเสียสติ {amount}`)
	drainAll(amount, "LeftoverCustomers", "NightLeftover", { count = missed })
end

-- anomaly หลายตัวที่ถูกล้างพร้อมกันตอนเช้ารวมเป็นการหักสติและ toast ครั้งเดียว
local function flushMissed()
	flushScheduled = false
	local count = missedAnomalies
	missedAnomalies = 0
	if count <= 0 then
		return
	end
	local amount = Sanity.Values.MissedAnomaly * count
	warn(`{LOG} anomaly {count} ตัวไม่ถูกรายงานจนเช้า ทุกคนเสียสติ {amount}`)
	drainAll(amount, "MissedAnomaly", "SanityLostMissed", nil)
end

local function onAnomalyResolved(anomaly: AnomalyService.ActiveAnomaly, byPlayer: boolean)
	if byPlayer then
		return
	end
	print(`{LOG} anomaly #{anomaly.InstanceId} ({anomaly.Id}) ไม่ถูกรายงานจนเช้า`)
	missedAnomalies += 1
	if not flushScheduled then
		flushScheduled = true
		task.defer(flushMissed)
	end
end

-- Studio เท่านั้น: ทำให้ roster ครบทันทีเพื่อทดสอบเส้นทางจบคืนเร็ว
local function connectDebugRoster()
	ServerStorage:GetAttributeChangedSignal(Report.DebugRosterCompleteAttribute):Connect(function()
		local raw = ServerStorage:GetAttribute(Report.DebugRosterCompleteAttribute)
		if raw == nil then
			return
		end
		ServerStorage:SetAttribute(Report.DebugRosterCompleteAttribute, nil)
		if raw ~= true then
			warn(`{LOG} โหมดทดสอบ: {Report.DebugRosterCompleteAttribute} ต้องเป็น true (ค่า {tostring(raw)})`)
			return
		end
		warn(`{LOG} โหมดทดสอบ: ทำให้ roster ครบทันที`)
		for _, slot in AnomalyService.GetNightRoster().Slots do
			if slot.State == "Pending" then
				AnomalyService.MarkCustomerHandled(slot.SlotId, "Served")
			end
		end
	end)
end

function NightFlowService.Start()
	ServeService.OnOrderServed(onOrderServed)
	AnomalyService.OnRosterComplete(onRosterComplete)
	AnomalyService.OnNightEnded(onNightEnded)
	AnomalyService.OnAnomalyResolved(onAnomalyResolved)
	DayNightService.OnNightStarted(function(_night: number)
		clearCountdown()
	end)
	DayNightService.OnPhaseChanged(function(phase: string, _day: number)
		if phase ~= "Night" then
			clearCountdown()
		end
	end)
	clearCountdown()
	if RunService:IsStudio() then
		connectDebugRoster()
	end
end

return NightFlowService
