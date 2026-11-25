--!strict
-- SanityService: สติต่อผู้เล่น (server เป็นผู้ตัดสิน) เก็บใน memory ไม่บันทึก DataStore รีเซ็ตทุกคืน (OnNightStarted)
-- sync ไป client ด้วย Attributes บน Player (ชื่อใน Config/Sanity) ไม่มี remote
-- ค่าตั้งทั้งหมดอยู่ใน Config/Sanity ผู้เรียกเป็นผู้แจ้งเตือนผู้เล่นว่าสติลดเพราะอะไร (service นี้แจ้งเฉพาะตอนสติหมด)
-- API: Get, GetMax, Change, Set, ResetAll สัญญาณ: OnChanged(player, new, old, reason), OnDepleted(player)
--   OnDepleted ยิงครั้งเดียวตอนสติข้ามลงมาถึง 0 และยิงใหม่ได้เมื่อสติกลับมา > 0 (ผี/ฟื้นเป็น TASK-016)
-- เครื่องมือ Studio (เฉพาะ RunService:IsStudio()): ตั้ง attribute Config/Sanity.DebugSetAttribute บน ServerStorage เป็นตัวเลข

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Sanity = require(ReplicatedStorage.Shared.Config.Sanity)
local SanityRules = require(ReplicatedStorage.Shared.SanityRules)
local DayNightService = require(script.Parent.DayNightService)
local NotifyService = require(script.Parent.NotifyService)

local LOG = "[SanityService]"

local changedEvent = Instance.new("BindableEvent")
local depletedEvent = Instance.new("BindableEvent")

local SanityService = {}

function SanityService.OnChanged(callback: (player: Player, newValue: number, oldValue: number, reason: string) -> ()): RBXScriptConnection
	return changedEvent.Event:Connect(callback)
end

function SanityService.OnDepleted(callback: (player: Player) -> ()): RBXScriptConnection
	return depletedEvent.Event:Connect(callback)
end

local values: Sanity.Values = Sanity.Values
local current: { [Player]: number } = {}

local function validateConfig()
	local map: { [string]: unknown } = {
		Max = Sanity.Values.Max,
		Start = Sanity.Values.Start,
		WrongReport = Sanity.Values.WrongReport,
		MissedAnomaly = Sanity.Values.MissedAnomaly,
		LeftoverCustomer = Sanity.Values.LeftoverCustomer,
	}
	local problem = SanityRules.Validate(map)
	if problem ~= nil then
		warn(`{LOG} Config/Sanity.Values ไม่ถูกต้อง ใช้ค่าสำรอง: {problem}`)
		values = Sanity.Fallback
	end
end

local function publish(player: Player, value: number)
	player:SetAttribute(Sanity.AttributeSanity, value)
	player:SetAttribute(Sanity.AttributeMax, values.Max)
end

function SanityService.GetMax(): number
	return values.Max
end

-- ค่าสติปัจจุบัน (nil ถ้าผู้เล่นไม่ได้อยู่ในเกมแล้ว)
function SanityService.Get(player: Player): number?
	return current[player]
end

local function apply(player: Player, newValue: number, reason: string): number?
	local old = current[player]
	if old == nil then
		warn(`{LOG} {player.Name}: ไม่มีข้อมูลสติ (ออกจากเกมแล้ว?) ข้ามเหตุผล {reason}`)
		return nil
	end
	local clamped = math.clamp(newValue, 0, values.Max)
	current[player] = clamped
	publish(player, clamped)
	if clamped ~= old then
		print(`{LOG} {player.Name} สติ {old} -> {clamped} (เหตุผล {reason})`)
		changedEvent:Fire(player, clamped, old, reason)
	end
	if SanityRules.IsDepleted(clamped) and not SanityRules.IsDepleted(old) then
		warn(`{LOG} {player.Name} สติหมด (เหตุผล {reason})`)
		NotifyService.Notify(player, "SanityDepleted", "error", nil)
		depletedEvent:Fire(player)
	end
	return clamped
end

-- เปลี่ยนสติ (delta ติดลบ = ลด) คืนค่าใหม่หลัง clamp หรือ nil ถ้าทำไม่ได้ (warn แล้ว)
function SanityService.Change(player: Player, delta: number, reason: string): number?
	if not SanityRules.IsValidDelta(delta) then
		warn(`{LOG} Change: delta ไม่ถูกต้อง ({tostring(delta)}) เหตุผล {reason}`)
		return nil
	end
	local old = current[player]
	if old == nil then
		warn(`{LOG} {player.Name}: ไม่มีข้อมูลสติ (ออกจากเกมแล้ว?) ข้ามเหตุผล {reason}`)
		return nil
	end
	return apply(player, SanityRules.Apply(old, delta, values.Max), reason)
end

function SanityService.Set(player: Player, value: number, reason: string): number?
	if not SanityRules.IsValidDelta(value) then
		warn(`{LOG} Set: ค่าไม่ถูกต้อง ({tostring(value)}) เหตุผล {reason}`)
		return nil
	end
	return apply(player, SanityRules.Apply(0, value, values.Max), reason)
end

-- รีเซ็ตทุกคนเป็นค่าเริ่ม (เรียกตอนเริ่มคืน)
function SanityService.ResetAll()
	for _, player in Players:GetPlayers() do
		SanityService.Set(player, values.Start, "NightReset")
	end
end

local function onPlayerAdded(player: Player)
	current[player] = values.Start
	publish(player, values.Start)
	print(`{LOG} {player.Name} เริ่มด้วยสติ {values.Start}/{values.Max}`)
end

local function onPlayerRemoving(player: Player)
	current[player] = nil
end

-- Studio เท่านั้น: ตั้งสติทุกคนด้วย attribute แล้วล้างค่า
local function connectDebugSet()
	ServerStorage:GetAttributeChangedSignal(Sanity.DebugSetAttribute):Connect(function()
		local raw = ServerStorage:GetAttribute(Sanity.DebugSetAttribute)
		if raw == nil then
			return
		end
		ServerStorage:SetAttribute(Sanity.DebugSetAttribute, nil)
		if type(raw) ~= "number" or not SanityRules.IsValidDelta(raw) then
			warn(`{LOG} โหมดทดสอบ: {Sanity.DebugSetAttribute} ต้องเป็นตัวเลข (ค่า {tostring(raw)})`)
			return
		end
		warn(`{LOG} โหมดทดสอบ: ตั้งสติผู้เล่นทุกคนเป็น {raw}`)
		for _, player in Players:GetPlayers() do
			SanityService.Set(player, raw :: number, "DebugSet")
		end
	end)
end

function SanityService.Start()
	validateConfig()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	DayNightService.OnNightStarted(function(night: number)
		print(`{LOG} เริ่มคืนที่ {night}: รีเซ็ตสติทุกคน`)
		SanityService.ResetAll()
	end)
	if RunService:IsStudio() then
		connectDebugSet()
	end
end

return SanityService
