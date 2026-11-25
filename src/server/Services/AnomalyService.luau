--!strict
-- AnomalyService: ตัดสินชนิดคืน (Normal/Anomaly) และเกิด/ล้าง anomaly ตาม Config/Anomalies (server ตัดสินทั้งหมด)
-- ฟัง DayNightService: OnNightStarted สุ่มชนิดคืน + anomaly, OnPhaseChanged(Dawn) ปิด roster, OnMorningStarted ล้างทุกอย่าง
-- ไม่รู้จักชื่อ anomaly ใดเลย: พฤติกรรมอยู่ใน src/server/Anomalies/<Id>.luau (Spawn คืน Handle) เพิ่มตัวใหม่ = config + ไฟล์
-- สถานะอยู่ใน memory ต่อรอบ ไม่บันทึก DataStore ไม่มี remote: client ไม่รู้ว่ามี anomaly (Workspace replicate เอง)
-- ชนิดคืนเพิ่มได้ (เช่น Special ใน TASK-019): เพิ่มชนิดใน Config/Anomalies + แถวใน nightTypeHandlers
-- ทุกฟังก์ชันด้านล่างเรียกจาก server เท่านั้น (TASK-014 ตรวจคำขอของผู้เล่นแล้วค่อยเรียก)
--
-- API: GetNightType, GetActiveAnomalies, ResolveAnomaly, GetCategories, HasActiveOfCategory, GetActiveOfCategory,
--   GetNightRoster, MarkCustomerHandled
-- สัญญาณ: OnNightType, OnAnomalySpawned, OnAnomalyResolved, OnRosterComplete, OnNightEnded
-- เครื่องมือ Studio (เฉพาะ RunService:IsStudio()): attribute บน ServerStorage ชื่ออยู่ใน Config/Anomalies
--   AnomalyForceNight = "Anomaly"|"Normal", AnomalyForceIds = "ColorShift,Relocate", AnomalyDebugHandle = จำนวนลูกค้าที่จัดการแล้ว

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local AnomalyRules = require(ReplicatedStorage.Shared.AnomalyRules)
local Anomalies = require(ReplicatedStorage.Shared.Config.Anomalies)
local Customers = require(ReplicatedStorage.Shared.Config.Customers)
local NotifyConfig = require(ReplicatedStorage.Shared.Config.Notify)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local DayNightService = require(script.Parent.DayNightService)
local NotifyService = require(script.Parent.NotifyService)

local LOG = "[AnomalyService]"

export type NightType = Anomalies.NightType
export type ActiveAnomaly = {
	Id: string,
	InstanceId: number,
	Category: string,
	Subtlety: number,
	Target: string,
	CustomerId: string?, -- เฉพาะหมวด customer (id จาก Config/Customers)
	SpawnedAt: number, -- เวลา server
	Resolved: boolean,
}
export type RosterSummary = {
	NightNumber: number,
	Total: number,
	Pending: number,
	Slots: { AnomalyRules.Slot }, -- copy
}
export type Outcome = "Served" | "Reported"

type Record = {
	Info: ActiveAnomaly,
	Handle: AnomalyRules.Handle,
	Changes: { () -> () },
	Tracked: { Instance },
}

type PendingSpawn = { Entry: Anomalies.Entry, At: number }

type NightPlanContext = {
	Night: number,
	Settings: Anomalies.ModeSettings?,
	ForcedIds: { string },
	NightSeconds: number,
}

type Problem = { Id: string, Reason: string }

local nightTypeEvent = Instance.new("BindableEvent")
local spawnedEvent = Instance.new("BindableEvent")
local resolvedEvent = Instance.new("BindableEvent")
local rosterCompleteEvent = Instance.new("BindableEvent")
local nightEndedEvent = Instance.new("BindableEvent")

local AnomalyService = {}

function AnomalyService.OnNightType(callback: (nightNumber: number, nightType: NightType) -> ()): RBXScriptConnection
	return nightTypeEvent.Event:Connect(callback)
end

function AnomalyService.OnAnomalySpawned(callback: (anomaly: ActiveAnomaly) -> ()): RBXScriptConnection
	return spawnedEvent.Event:Connect(callback)
end

-- byPlayer = true เมื่อถูก ResolveAnomaly, false เมื่อถูกล้างตอนเช้า
function AnomalyService.OnAnomalyResolved(callback: (anomaly: ActiveAnomaly, byPlayer: boolean) -> ()): RBXScriptConnection
	return resolvedEvent.Event:Connect(callback)
end

-- ยิงครั้งเดียวต่อคืน เมื่อ roster ไม่เหลือ Pending
function AnomalyService.OnRosterComplete(callback: (nightNumber: number) -> ()): RBXScriptConnection
	return rosterCompleteEvent.Event:Connect(callback)
end

-- ยิงตอนเข้า Dawn หลังตั้ง slot ที่ค้างเป็น Missed
function AnomalyService.OnNightEnded(callback: (nightNumber: number, missed: number) -> ()): RBXScriptConnection
	return nightEndedEvent.Event:Connect(callback)
end

local rng = Random.new()
local validEntries: { Anomalies.Entry } = {}
local behaviors: { [string]: AnomalyRules.Behavior } = {}
local modeSettings: { [string]: Anomalies.ModeSettings } = {}
local nightCustomers: Anomalies.NightCustomers = Anomalies.NightCustomers
local problems: { Problem } = {}

local nightType: NightType? = nil
local currentNight = 0
local records: { Record } = {}
local nextInstanceId = 0
local container: Folder? = nil
local spawnThread: thread? = nil

local roster: { AnomalyRules.Slot } = {}
local rosterActive = false
local rosterCompleteFired = false

local function reportProblem(id: string, reason: string)
	table.insert(problems, { Id = id, Reason = reason })
	warn(`{LOG} anomaly {id} ใช้ไม่ได้ ข้าม: {reason}`)
end

local function findEntry(id: string): Anomalies.Entry?
	for _, entry in validEntries do
		if entry.Id == id then
			return entry
		end
	end
	return nil
end

local function loadBehavior(entry: Anomalies.Entry): string?
	local folder = script.Parent.Parent:FindFirstChild("Anomalies")
	local module = if folder ~= nil then folder:FindFirstChild(entry.Id) else nil
	if module == nil or not module:IsA("ModuleScript") then
		return `ไม่พบโมดูลพฤติกรรม src/server/Anomalies/{entry.Id}`
	end
	local ok, loaded = pcall(require, module)
	if not ok then
		return `โหลดโมดูลพฤติกรรมไม่สำเร็จ: {tostring(loaded)}`
	end
	if type(loaded) ~= "table" or type((loaded :: AnomalyRules.Behavior).Spawn) ~= "function" then
		return "โมดูลพฤติกรรมต้องคืนตารางที่มีฟังก์ชัน Spawn"
	end
	behaviors[entry.Id] = loaded :: AnomalyRules.Behavior
	return nil
end

-- ตรวจ config ทั้งหมดครั้งเดียวตอน Start: ตัวที่ผิดถูกข้ามพร้อม warn ไม่ทำให้ระบบอื่นพัง
local function validateConfig()
	local nightProblem = AnomalyRules.ValidateNightCustomers(Anomalies.NightCustomers)
	if nightProblem ~= nil then
		table.insert(problems, { Id = "NightCustomers", Reason = nightProblem })
		warn(`{LOG} Config/Anomalies.NightCustomers ไม่ถูกต้อง ใช้ค่าสำรอง: {nightProblem}`)
		nightCustomers = Anomalies.NightCustomersFallback
	end
	for name, settings in Anomalies.Modes do
		local reason = AnomalyRules.ValidateMode(settings, Anomalies.NightTypes)
		if reason ~= nil then
			table.insert(problems, { Id = `Mode {name}`, Reason = reason })
			warn(`{LOG} Config/Anomalies โหมด {name} ไม่ถูกต้อง ไม่ใช้โหมดนี้: {reason}`)
		else
			modeSettings[name] = settings
		end
	end
	local seen: { [string]: boolean } = {}
	local skipped = 0
	for index, entry in Anomalies.Entries do
		local map = AnomalyRules.EntryToMap(entry)
		local reason = AnomalyRules.ValidateEntry(map, Anomalies.Categories, Strings.Has, seen)
		if reason == nil then
			reason = loadBehavior(entry)
		end
		if reason ~= nil then
			skipped += 1
			local label = if type(map.Id) == "string" and map.Id ~= "" then (map.Id :: string) else `#{index}`
			reportProblem(label, reason)
		else
			seen[entry.Id] = true
			table.insert(validEntries, entry)
		end
	end
	local usableModes = 0
	for _ in modeSettings do
		usableModes += 1
	end
	print(`{LOG} ตรวจ config แล้ว: anomaly ใช้ได้ {#validEntries} / ข้าม {skipped}, โหมดที่ใช้ได้ {usableModes}`)
end

local function settingsFor(mode: string): Anomalies.ModeSettings?
	local settings = modeSettings[mode]
	if settings ~= nil then
		return settings
	end
	warn(`{LOG} โหมด {mode} ไม่มีค่าที่ใช้ได้ใน Config/Anomalies ใช้ {Anomalies.DefaultMode} แทน`)
	return modeSettings[Anomalies.DefaultMode]
end

local function getContainer(): Folder
	local existing = container
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = Anomalies.FolderName
	folder.Parent = Workspace
	container = folder
	return folder
end

local function findTargets(entry: Anomalies.Entry): { Instance }
	local found: { Instance } = {}
	local folder = Workspace:FindFirstChild(entry.Folder)
	if folder == nil then
		return found
	end
	for _, name in entry.Targets do
		local child = folder:FindFirstChild(name)
		if child ~= nil then
			table.insert(found, child)
		end
	end
	return found
end

-- ย้อนการเปลี่ยนแปลงที่ track ไว้ คืนจำนวนขั้นที่ล้มเหลว
local function rollback(changes: { () -> () }, tracked: { Instance }): number
	local failed = 0
	for index = #changes, 1, -1 do
		local undo = changes[index]
		local ok, err = pcall(function()
			undo()
		end)
		if not ok then
			failed += 1
			warn(`{LOG} คืนค่าเดิมไม่สำเร็จ: {tostring(err)}`)
		end
	end
	for _, instance in tracked do
		local ok, err = pcall(function()
			instance:Destroy()
		end)
		if not ok then
			failed += 1
			warn(`{LOG} ลบของที่ anomaly สร้างไม่สำเร็จ: {tostring(err)}`)
		end
	end
	return failed
end

-- คืนสภาพ 1 ตัว (pcall ทุกขั้น) คืน true ถ้าสะอาด
local function revertRecord(record: Record): boolean
	local failed = 0
	local revert = record.Handle.Revert
	if revert ~= nil then
		local ok, err = pcall(function()
			revert()
		end)
		if not ok then
			failed += 1
			warn(`{LOG} {record.Info.Id}: Revert ของโมดูลล้มเหลว {tostring(err)} (ใช้การคืนค่าสำรองต่อ)`)
		end
	end
	failed += rollback(record.Changes, record.Tracked)
	return failed == 0
end

local function spawnAnomaly(entry: Anomalies.Entry)
	local behavior = behaviors[entry.Id]
	if behavior == nil then
		warn(`{LOG} anomaly {entry.Id} ข้าม: ไม่มีโมดูลพฤติกรรม`)
		return
	end
	local targets = findTargets(entry)
	if #targets == 0 then
		warn(`{LOG} anomaly {entry.Id} ข้าม: ไม่พบเป้าหมายใน Workspace.{entry.Folder} ({table.concat(entry.Targets, ", ")})`)
		return
	end
	local target = targets[rng:NextInteger(1, #targets)]
	local changes: { () -> () } = {}
	local tracked: { Instance } = {}
	local context: AnomalyRules.Context = {
		Entry = entry,
		Target = target,
		Container = getContainer(),
		Rng = rng,
		SetColor = function(part: BasePart, color: Color3)
			local original = part.Color
			table.insert(changes, function()
				part.Color = original
			end)
			part.Color = color
		end,
		SetCFrame = function(part: BasePart, cframe: CFrame)
			local original = part.CFrame
			table.insert(changes, function()
				part.CFrame = original
			end)
			part.CFrame = cframe
		end,
		Track = function(instance: Instance)
			table.insert(tracked, instance)
		end,
	}
	local ok, result, reason = pcall(behavior.Spawn, context)
	if not ok then
		rollback(changes, tracked)
		warn(`{LOG} anomaly {entry.Id} ข้าม: โมดูลพฤติกรรม error: {tostring(result)}`)
		return
	end
	local handle = result :: AnomalyRules.Handle?
	if handle == nil then
		rollback(changes, tracked)
		warn(`{LOG} anomaly {entry.Id} ข้าม: {tostring(reason)}`)
		return
	end
	local customerId = handle.CustomerId
	if customerId ~= nil and (entry.Category ~= "customer" or Customers.Customers[customerId] == nil) then
		warn(`{LOG} anomaly {entry.Id}: CustomerId {customerId} ใช้ไม่ได้ (ต้องเป็นหมวด customer และมีใน Config/Customers) ไม่ใส่ค่า`)
		customerId = nil
	end
	nextInstanceId += 1
	local info: ActiveAnomaly = {
		Id = entry.Id,
		InstanceId = nextInstanceId,
		Category = entry.Category,
		Subtlety = entry.Subtlety,
		Target = target.Name,
		CustomerId = customerId,
		SpawnedAt = Workspace:GetServerTimeNow(),
		Resolved = false,
	}
	table.insert(records, { Info = info, Handle = handle, Changes = changes, Tracked = tracked })
	print(`{LOG} คืนที่ {currentNight}: spawn {entry.Id} #{info.InstanceId} (หมวด {entry.Category}, subtlety {entry.Subtlety}, เป้าหมาย {target.Name}) {handle.Description}`)
	spawnedEvent:Fire(table.clone(info))
end

local function cancelSpawnThread()
	local thread = spawnThread
	spawnThread = nil
	if thread ~= nil and coroutine.status(thread) ~= "dead" then
		task.cancel(thread)
	end
end

local function safeSpawn(entry: Anomalies.Entry)
	local ok, err = pcall(function()
		spawnAnomaly(entry)
	end)
	if not ok then
		warn(`{LOG} anomaly {entry.Id} ข้าม: error ที่ไม่คาดคิด {tostring(err)}`)
	end
end

-- เวลาเกิดนับเฉพาะตอน DayNight กำลังนับ (หยุดเมื่อไม่มีผู้เล่น) ตัวที่ At = 0 เกิดทันที
local function runSpawnLoop(pending: { PendingSpawn })
	local function dispatch(elapsed: number)
		local index = 1
		while index <= #pending do
			if pending[index].At <= elapsed then
				local item = table.remove(pending, index)
				if item ~= nil then
					safeSpawn(item.Entry)
				end
			else
				index += 1
			end
		end
	end
	spawnThread = task.spawn(function()
		local elapsed = 0
		dispatch(elapsed)
		while #pending > 0 do
			local step = task.wait(Anomalies.SpawnPollSeconds)
			if DayNightService.GetPhase() ~= "Night" then
				warn(`{LOG} คืนที่ {currentNight} จบก่อน spawn ครบ ({#pending} ตัวไม่ทันเกิด)`)
				return
			end
			if DayNightService.IsRunning() then
				elapsed += step
			end
			dispatch(elapsed)
		end
	end)
end

local function clearAll()
	cancelSpawnThread()
	local cleared, dirty = 0, 0
	for _, record in records do
		if not record.Info.Resolved then
			if not revertRecord(record) then
				dirty += 1
			end
			record.Info.Resolved = true
			cleared += 1
			resolvedEvent:Fire(table.clone(record.Info), false)
		end
	end
	records = {}
	local leftover = 0
	local folder = container
	container = nil
	if folder ~= nil then
		leftover = #folder:GetChildren()
		folder:Destroy()
	end
	nightType = nil
	print(`{LOG} ล้าง anomaly ตอนเช้า: คืนสภาพ {cleared} ตัว (ล้มเหลว {dirty}), ของค้างใน {Anomalies.FolderName} = {leftover}`)
	if leftover > 0 or dirty > 0 then
		warn(`{LOG} ล้างไม่สะอาด: ของค้าง {leftover} ชิ้น, คืนสภาพไม่สำเร็จ {dirty} ตัว (ถูกลบ folder แล้ว)`)
	end
end

-- ===== ชนิดคืน: เพิ่มชนิดใหม่ = เพิ่มชนิดใน Config + แถวที่นี่ (คืน nil = ทำไม่ได้ ถือเป็นคืนปกติ) =====

local function selectAnomalies(plan: NightPlanContext): { PendingSpawn }?
	local chosen: { PendingSpawn } = {}
	if #plan.ForcedIds > 0 then
		for _, id in plan.ForcedIds do
			local entry = findEntry(id)
			if entry == nil then
				warn(`{LOG} โหมดทดสอบ: ไม่รู้จัก anomaly id "{id}" หรือ config ใช้ไม่ได้ ข้าม`)
			elseif #findTargets(entry) == 0 then
				warn(`{LOG} anomaly {id} ข้าม: ไม่พบเป้าหมายใน Workspace.{entry.Folder}`)
			else
				table.insert(chosen, { Entry = entry, At = 0 })
			end
		end
	else
		local settings = plan.Settings
		if settings == nil then
			warn(`{LOG} ไม่มีค่าโหมดที่ใช้ได้ ถือเป็นคืนปกติ`)
			return nil
		end
		local candidates: { Anomalies.Entry } = {}
		for _, entry in validEntries do
			if entry.Subtlety <= settings.MaxSubtlety then
				table.insert(candidates, entry)
			end
		end
		local count = rng:NextInteger(settings.AnomaliesMin, settings.AnomaliesMax)
		while #chosen < count and #candidates > 0 do
			local index = AnomalyRules.PickIndex(candidates, function(entry: Anomalies.Entry): number
				return entry.Weight
			end, rng:NextNumber())
			if index == nil then
				break
			end
			local entry = table.remove(candidates, index)
			if entry ~= nil then
				if #findTargets(entry) == 0 then
					warn(`{LOG} anomaly {entry.Id} ข้าม: ไม่พบเป้าหมายใน Workspace.{entry.Folder} ({table.concat(entry.Targets, ", ")})`)
				else
					local fraction = settings.SpawnWindowMin + (settings.SpawnWindowMax - settings.SpawnWindowMin) * rng:NextNumber()
					table.insert(chosen, { Entry = entry, At = plan.NightSeconds * fraction })
				end
			end
		end
	end
	if #chosen == 0 then
		warn(`{LOG} คืนที่ {plan.Night}: ไม่มี anomaly ที่ใช้ได้เลย ถือเป็นคืนปกติ`)
		return nil
	end
	return chosen
end

local nightTypeHandlers: { [string]: (plan: NightPlanContext) -> { PendingSpawn }? } = {
	Normal = function(_plan: NightPlanContext): { PendingSpawn }?
		return {}
	end,
	Anomaly = selectAnomalies,
}

-- ===== Roster ลูกค้ากลางคืน =====

local function buildRoster(night: number)
	local low, high = AnomalyRules.NightCustomerRange(nightCustomers, night)
	local count = rng:NextInteger(low, high)
	roster = {}
	for slotId = 1, count do
		table.insert(roster, { SlotId = slotId, State = "Pending", IsAnomalous = false, CustomerId = nil })
	end
	rosterActive = true
	rosterCompleteFired = false
	print(`{LOG} คืนที่ {night}: roster ลูกค้ากลางคืน {count} คน (ช่วงสุ่ม {low}..{high})`)
end

local function readForce(): (string?, { string })
	if not RunService:IsStudio() then
		return nil, {}
	end
	local forceNight: string? = nil
	local rawNight = ServerStorage:GetAttribute(Anomalies.ForceNightAttribute)
	if rawNight ~= nil then
		if rawNight == "Normal" or rawNight == "Anomaly" then
			forceNight = rawNight :: string
		else
			warn(`{LOG} โหมดทดสอบ: {Anomalies.ForceNightAttribute} ต้องเป็น "Anomaly" หรือ "Normal" (ค่า {tostring(rawNight)}) ไม่สนใจ`)
		end
	end
	local ids = AnomalyRules.ParseIds(ServerStorage:GetAttribute(Anomalies.ForceIdsAttribute))
	if forceNight == "Normal" and #ids > 0 then
		warn(`{LOG} โหมดทดสอบ: {Anomalies.ForceNightAttribute} = Normal ชนะ {Anomalies.ForceIdsAttribute} ไม่สนใจรายการ id`)
		ids = {}
	end
	return forceNight, ids
end

local function startNight(night: number)
	if #records > 0 or container ~= nil then
		warn(`{LOG} พบ anomaly ค้างจากรอบก่อนตอนเริ่มคืนที่ {night} ล้างก่อน`)
		clearAll()
	end
	cancelSpawnThread()
	currentNight = night
	buildRoster(night)

	local mode = DayNightService.GetMode()
	local settings = settingsFor(mode)
	local forceNight, forceIds = readForce()
	local chosenType: string
	if forceNight ~= nil then
		chosenType = forceNight
		warn(`{LOG} โหมดทดสอบ: บังคับคืนที่ {night} เป็น {forceNight}`)
	elseif #forceIds > 0 then
		chosenType = "Anomaly"
		warn(`{LOG} โหมดทดสอบ: บังคับ anomaly {table.concat(forceIds, ", ")} คืนที่ {night}`)
	elseif night <= Anomalies.GuaranteedNormalNights then
		chosenType = "Normal"
		print(`{LOG} คืนที่ {night}: เป็นคืนปกติเสมอ (GuaranteedNormalNights = {Anomalies.GuaranteedNormalNights})`)
	elseif settings == nil then
		chosenType = "Normal"
		warn(`{LOG} ไม่มีค่าโหมดที่ใช้ได้ ถือเป็นคืนปกติ`)
	else
		chosenType = AnomalyRules.PickNightType(settings.NightTypeWeights, Anomalies.NightTypes, rng:NextNumber()) or "Normal"
	end

	local handler = nightTypeHandlers[chosenType]
	local pending: { PendingSpawn }? = nil
	if handler == nil then
		warn(`{LOG} ไม่มี handler ของชนิดคืน {chosenType} ถือเป็นคืนปกติ`)
	else
		pending = handler({
			Night = night,
			Settings = settings,
			ForcedIds = forceIds,
			NightSeconds = DayNightService.GetTimeRemaining(),
		})
	end
	local finalType: NightType = if pending ~= nil and chosenType == "Anomaly" then "Anomaly" else "Normal"
	nightType = finalType
	print(`{LOG} คืนที่ {night}: ชนิดคืน = {finalType} (โหมด {mode}, anomaly {if pending ~= nil then #pending else 0} ตัว)`)
	nightTypeEvent:Fire(night, finalType)
	if pending ~= nil and #pending > 0 then
		runSpawnLoop(pending)
	end
end

local function finishNight()
	cancelSpawnThread()
	if not rosterActive then
		return
	end
	rosterActive = false
	local missed = 0
	for _, slot in roster do
		if slot.State == "Pending" then
			slot.State = "Missed"
			missed += 1
		end
	end
	print(`{LOG} คืนที่ {currentNight} จบ: ลูกค้า {#roster} คน, พลาด {missed} คน`)
	nightEndedEvent:Fire(currentNight, missed)
end

local function guarded(label: string, fn: () -> ())
	local ok, err = pcall(function()
		fn()
	end)
	if not ok then
		warn(`{LOG} {label} error (ระบบวัน/คืนและร้านเล่นต่อได้): {tostring(err)}`)
	end
end

local function onNightStarted(night: number)
	guarded(`เริ่มคืนที่ {night}`, function()
		startNight(night)
	end)
end

local function onPhaseChanged(phase: string, _day: number)
	if phase == "Dawn" then
		guarded("จบคืน", finishNight)
	end
end

local function onMorningStarted(day: number)
	guarded(`เช้าวันที่ {day}`, function()
		finishNight()
		clearAll()
	end)
end

-- ===== API =====

function AnomalyService.GetNightType(): NightType?
	return nightType
end

function AnomalyService.GetCategories(): { string }
	return table.clone(Anomalies.Categories)
end

function AnomalyService.GetActiveAnomalies(): { ActiveAnomaly }
	local result: { ActiveAnomaly } = {}
	for _, record in records do
		if not record.Info.Resolved then
			table.insert(result, table.clone(record.Info))
		end
	end
	return result
end

local function isCategory(category: string): boolean
	return table.find(Anomalies.Categories, category) ~= nil
end

function AnomalyService.GetActiveOfCategory(category: string): { ActiveAnomaly }
	local result: { ActiveAnomaly } = {}
	if not isCategory(category) then
		warn(`{LOG} GetActiveOfCategory: ไม่รู้จักหมวด "{tostring(category)}"`)
		return result
	end
	for _, info in AnomalyService.GetActiveAnomalies() do
		if info.Category == category then
			table.insert(result, info)
		end
	end
	return result
end

-- customerId ใช้ได้เฉพาะหมวด customer (หมวดอื่นจะ warn และไม่สนใจ)
function AnomalyService.HasActiveOfCategory(category: string, customerId: string?): boolean
	local matches = AnomalyService.GetActiveOfCategory(category)
	if customerId ~= nil and category ~= "customer" then
		warn(`{LOG} HasActiveOfCategory: customerId ใช้ได้เฉพาะหมวด customer (หมวด {category}) ไม่สนใจ customerId`)
		customerId = nil
	end
	for _, info in matches do
		if customerId == nil or info.CustomerId == customerId then
			return true
		end
	end
	return false
end

-- แก้ anomaly แล้วคืนสภาพทันที คืน false (พร้อม warn) ถ้าไม่พบ/แก้ไปแล้ว/คืนสภาพไม่สะอาด
function AnomalyService.ResolveAnomaly(instanceId: number): boolean
	for _, record in records do
		if record.Info.InstanceId == instanceId then
			if record.Info.Resolved then
				warn(`{LOG} ResolveAnomaly: anomaly #{instanceId} ({record.Info.Id}) ถูกแก้ไปแล้ว`)
				return false
			end
			local clean = revertRecord(record)
			record.Info.Resolved = true
			print(`{LOG} anomaly #{instanceId} ({record.Info.Id}) ถูกแก้และคืนสภาพแล้ว (สะอาด: {clean})`)
			resolvedEvent:Fire(table.clone(record.Info), true)
			return clean
		end
	end
	warn(`{LOG} ResolveAnomaly: ไม่พบ anomaly #{tostring(instanceId)} ที่ active อยู่`)
	return false
end

function AnomalyService.GetNightRoster(): RosterSummary
	local slots: { AnomalyRules.Slot } = {}
	for _, slot in roster do
		table.insert(slots, table.clone(slot))
	end
	return {
		NightNumber = currentNight,
		Total = #roster,
		Pending = AnomalyRules.CountPending(roster),
		Slots = slots,
	}
end

-- ทำเครื่องหมายว่าจัดการลูกค้า slot นี้แล้ว (idempotent: จัดการแล้ว/ไม่มี slot/ไม่ใช่ช่วงคืน = false + warn)
function AnomalyService.MarkCustomerHandled(slotId: number, outcome: Outcome): boolean
	if outcome ~= "Served" and outcome ~= "Reported" then
		warn(`{LOG} MarkCustomerHandled: outcome ไม่ถูกต้อง ({tostring(outcome)})`)
		return false
	end
	if not rosterActive then
		warn(`{LOG} MarkCustomerHandled: ไม่มี roster ของคืนที่กำลังเล่นอยู่`)
		return false
	end
	for _, slot in roster do
		if slot.SlotId == slotId then
			if slot.State ~= "Pending" then
				warn(`{LOG} MarkCustomerHandled: slot {slotId} ถูกจัดการแล้ว ({slot.State}) ไม่นับซ้ำ`)
				return false
			end
			slot.State = outcome
			local pending = AnomalyRules.CountPending(roster)
			print(`{LOG} คืนที่ {currentNight}: slot {slotId} = {outcome} (เหลือ {pending}/{#roster})`)
			if pending == 0 and not rosterCompleteFired then
				rosterCompleteFired = true
				print(`{LOG} คืนที่ {currentNight}: จัดการลูกค้าครบทุกคน`)
				rosterCompleteEvent:Fire(currentNight)
			end
			return true
		end
	end
	warn(`{LOG} MarkCustomerHandled: ไม่พบ slot {tostring(slotId)}`)
	return false
end

-- ===== Start =====

local function notifyProblems(player: Player)
	if not RunService:IsStudio() then
		return
	end
	for _, problem in problems do
		local args: { [string]: string | number } = {
			id = string.sub(problem.Id, 1, NotifyConfig.MaxArgLength),
			reason = string.sub(problem.Reason, 1, NotifyConfig.MaxArgLength),
		}
		NotifyService.Notify(player, "AnomalyConfigInvalid", "error", args)
	end
end

local function removeStaleContainer()
	local stale = Workspace:FindFirstChild(Anomalies.FolderName)
	if stale ~= nil then
		warn(`{LOG} พบ {Anomalies.FolderName} ค้างใน Workspace ตอนเริ่ม ลบทิ้ง`)
		stale:Destroy()
	end
end

-- Studio เท่านั้น: ตั้ง attribute เป็นจำนวนลูกค้าเพื่อทดสอบเส้นทาง "จัดการครบ" แล้วล้างค่า
local function connectDebugHandle()
	ServerStorage:GetAttributeChangedSignal(Anomalies.DebugHandleAttribute):Connect(function()
		local raw = ServerStorage:GetAttribute(Anomalies.DebugHandleAttribute)
		if raw == nil then
			return
		end
		ServerStorage:SetAttribute(Anomalies.DebugHandleAttribute, nil)
		if type(raw) ~= "number" or raw < 1 or raw ~= math.floor(raw) then
			warn(`{LOG} โหมดทดสอบ: {Anomalies.DebugHandleAttribute} ต้องเป็นจำนวนเต็ม >= 1 (ค่า {tostring(raw)})`)
			return
		end
		warn(`{LOG} โหมดทดสอบ: ทำเครื่องหมายลูกค้าที่จัดการแล้ว {raw} คน`)
		local remaining = raw :: number
		for _, slot in table.clone(roster) do
			if remaining <= 0 then
				break
			end
			if slot.State == "Pending" and AnomalyService.MarkCustomerHandled(slot.SlotId, "Served") then
				remaining -= 1
			end
		end
	end)
end

function AnomalyService.Start()
	removeStaleContainer()
	validateConfig()
	DayNightService.OnNightStarted(onNightStarted)
	DayNightService.OnPhaseChanged(onPhaseChanged)
	DayNightService.OnMorningStarted(onMorningStarted)
	Players.PlayerAdded:Connect(notifyProblems)
	for _, player in Players:GetPlayers() do
		notifyProblems(player)
	end
	if RunService:IsStudio() then
		connectDebugHandle()
	end
end

return AnomalyService
