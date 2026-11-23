--!strict
-- DataService: โหลด/เซฟข้อมูลผู้เล่นด้วย DataStore
-- รูปแบบเรคคอร์ด: { Data = PlayerData, SessionId = string?, LockedAt = number? }
-- ทุกการเขียนใช้ UpdateAsync และตรวจ session lock ใน transform เดียวกับการอ่าน

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local QuestRules = require(ReplicatedStorage.Shared.QuestRules)
local NotifyService = require(script.Parent.NotifyService)

type PlayerData = PlayerDataConfig.PlayerData
type RetryConfig = PlayerDataConfig.RetryConfig
type Outcome = "Ok" | "Retry" | "Fatal" | "Aborted"
type FailReason = "Newer" | "Corrupt" | "Locked" | "Error"
type BeforeSaveHandler = (player: Player, data: PlayerData) -> ()

type Session = {
	Player: Player,
	Data: PlayerData?,
	State: "Loading" | "Active" | "Failed",
	Temporary: boolean,
	LockHeld: boolean,
	Left: boolean,
	Saving: boolean,
	Finalizing: boolean,
	LockLost: boolean,
	FailReason: FailReason,
	AutosaveThread: thread?,
}

type AttemptState = {
	Data: PlayerData?,
	Reason: FailReason?,
	Lost: boolean,
}

local cfg = PlayerDataConfig
local LOG = "[DataService]"

local sessionId: string = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)

local DataService = {}

local loadedEvent = Instance.new("BindableEvent")
-- ยิงเมื่อข้อมูลผู้เล่นพร้อมใช้: (player: Player) ส่งแค่ player เพราะ BindableEvent copy table
-- ผู้ฟังต้องเรียก DataService.GetData(player) เพื่อได้ table จริงที่ถูกเซฟ
DataService.Loaded = loadedEvent.Event

local sessions: { [Player]: Session } = {}
local closingUserIds: { [number]: boolean } = {}
local busy = 0
local temporaryMode = false
local dataStore: DataStore? = nil

local random = Random.new()

local beforeSaveHandlers: { BeforeSaveHandler } = {}

-- migrations[v] แปลงข้อมูล Version v ให้เป็น v + 1 (แก้ raw ตรง ๆ)
local migrations: { [number]: ({ [string]: any }) -> () } = {}

local function logError(message: string)
	task.spawn(error, message, 0)
end

local function copyCounts(source: { [string]: number }): { [string]: number }
	local copy: { [string]: number } = {}
	for id, count in source do
		copy[id] = count
	end
	return copy
end

local function copyData(source: PlayerData): PlayerData
	return {
		Version = source.Version,
		Coins = source.Coins,
		Reputation = source.Reputation,
		Inventory = copyCounts(source.Inventory),
		Upgrades = copyCounts(source.Upgrades),
		Settings = { Language = source.Settings.Language },
		Quests = QuestRules.Copy(source.Quests),
	}
end

local function readNumber(value: unknown, min: number, max: number, integerOnly: boolean): number?
	if type(value) ~= "number" then
		return nil
	end
	if value ~= value or value < min or value > max then
		return nil
	end
	if integerOnly and value ~= math.floor(value) then
		return nil
	end
	return value
end

local function readCounts(
	raw: any, -- ข้อมูลดิบจาก DataStore ตรวจชนิดทุกค่าด้านล่าง
	fieldName: string,
	max: number,
	playerName: string,
	into: { [string]: number }
)
	if raw == nil then
		return
	end
	if type(raw) ~= "table" then
		warn(`{LOG} {fieldName} ของ {playerName} ไม่ใช่ table ใช้ค่าเริ่มต้น`)
		return
	end
	for id, count in raw do
		local valid = readNumber(count, 0, max, true)
		if type(id) == "string" and valid ~= nil then
			into[id] = valid
		else
			warn(`{LOG} {fieldName}.{tostring(id)} ของ {playerName} ไม่ถูกต้อง ข้ามค่านี้`)
		end
	end
end

-- แปลงข้อมูลดิบจาก DataStore เป็น PlayerData ที่ปลอดภัย (เติมฟิลด์ที่ขาด, ตรวจชนิด/ช่วงค่า)
local function sanitize(raw: { [string]: any }, playerName: string): PlayerData
	local version = readNumber(raw.Version, 1, cfg.DataVersion, true) or cfg.DataVersion
	for from = version, cfg.DataVersion - 1 do
		local migrate = migrations[from]
		if migrate then
			migrate(raw)
		else
			warn(`{LOG} ไม่มี migration จาก Version {from} ของ {playerName} ใช้ข้อมูลเท่าที่มี`)
		end
	end

	local data = copyData(cfg.Defaults)
	data.Version = cfg.DataVersion

	local coins = readNumber(raw.Coins, 0, cfg.Limits.MaxCoins, true)
	if coins ~= nil then
		data.Coins = coins
	elseif raw.Coins ~= nil then
		warn(`{LOG} Coins ของ {playerName} ไม่ถูกต้อง ใช้ค่าเริ่มต้น`)
	end

	local reputation = readNumber(raw.Reputation, 0, cfg.Limits.MaxReputation, true)
	if reputation ~= nil then
		data.Reputation = reputation
	elseif raw.Reputation ~= nil then
		warn(`{LOG} Reputation ของ {playerName} ไม่ถูกต้อง ใช้ค่าเริ่มต้น`)
	end

	readCounts(raw.Inventory, "Inventory", cfg.Limits.MaxItemCount, playerName, data.Inventory)
	readCounts(raw.Upgrades, "Upgrades", cfg.Limits.MaxUpgradeLevel, playerName, data.Upgrades)

	local settings = raw.Settings
	if type(settings) == "table" then
		local language = settings.Language
		if language == "th" or language == "en" then
			data.Settings.Language = language
		elseif language ~= nil then
			warn(`{LOG} Settings.Language ของ {playerName} ไม่ถูกต้อง ใช้ค่าเริ่มต้น`)
		end
	elseif settings ~= nil then
		warn(`{LOG} Settings ของ {playerName} ไม่ถูกต้อง ใช้ค่าเริ่มต้น`)
	end

	data.Quests = QuestRules.Sanitize(raw.Quests, function(reason: string)
		warn(`{LOG} Quests ของ {playerName} {reason}`)
	end)

	return data
end

local function isStudioApiDisabled(err: string): boolean
	if not RunService:IsStudio() then
		return false
	end
	local lowered = string.lower(err)
	for _, marker in cfg.StudioApiDisabledMarkers do
		if string.find(lowered, marker, 1, true) then
			return true
		end
	end
	return false
end

local function enterTemporaryMode()
	if temporaryMode then
		return
	end
	temporaryMode = true
	warn(`{LOG} Studio ไม่ได้เปิด API Services เข้าโหมดชั่วคราว: ใช้ข้อมูลในหน่วยความจำและจะไม่บันทึก`)
end

-- ถ้า GetDataStore throw และเป็น error ของ Studio (ไม่เปิด API/ยังไม่ publish) เข้าโหมดชั่วคราว
local function getStore(): DataStore?
	if dataStore then
		return dataStore
	end
	local holder: { Store: DataStore? } = { Store = nil }
	local ok, err = pcall(function()
		holder.Store = DataStoreService:GetDataStore(cfg.DataStoreName)
	end)
	if not ok then
		local message = tostring(err)
		warn(`{LOG} เรียก DataStore ไม่สำเร็จ: {message}`)
		if isStudioApiDisabled(message) then
			enterTemporaryMode()
		end
		return nil
	end
	dataStore = holder.Store
	return dataStore
end

-- ลองซ้ำแบบ backoff คืนผลสุดท้าย (ผู้เรียกเป็นคนตัดสินใจว่าจะ log error/kick ต่อ)
local function runWithBackoff(
	retryCfg: RetryConfig,
	description: string,
	attempt: () -> (Outcome, string?),
	shouldAbort: () -> boolean,
	onRetry: ((number) -> ())?
): (Outcome, string?)
	local delaySeconds = retryCfg.InitialDelaySeconds
	local lastMessage: string? = nil
	for attemptNumber = 1, retryCfg.MaxAttempts do
		if shouldAbort() then
			return "Aborted", nil
		end
		local outcome, message = attempt()
		if outcome == "Ok" then
			return "Ok", nil
		end
		lastMessage = message
		warn(`{LOG} {description} ล้มเหลว (ครั้งที่ {attemptNumber}/{retryCfg.MaxAttempts}): {tostring(message)}`)
		if outcome == "Fatal" then
			return "Fatal", message
		end
		if attemptNumber < retryCfg.MaxAttempts then
			if onRetry then
				onRetry(attemptNumber)
			end
			task.wait(delaySeconds)
			delaySeconds = math.min(delaySeconds * retryCfg.BackoffMultiplier, retryCfg.MaxDelaySeconds)
		end
	end
	return "Retry", lastMessage
end

local function keyFor(player: Player): string
	return cfg.KeyPrefix .. tostring(player.UserId)
end

-- ขอ lock + อ่านข้อมูลใน UpdateAsync เดียว
local function attemptLoad(session: Session): (Outcome, string?)
	local store = getStore()
	if store == nil then
		if temporaryMode then
			return "Fatal", "Studio ไม่เปิด API Services"
		end
		return "Retry", "DataStore ยังไม่พร้อม"
	end
	local player = session.Player
	local state: AttemptState = { Data = nil, Reason = nil, Lost = false }

	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(player), function(old: any)
			state.Data = nil
			state.Reason = nil
			local now = os.time()

			if old == nil then
				local fresh = copyData(cfg.Defaults)
				state.Data = fresh
				return { Data = copyData(fresh), SessionId = sessionId, LockedAt = now }
			end
			if type(old) ~= "table" then
				state.Reason = "Corrupt"
				return nil
			end
			local record: { [string]: any } = old
			local rawData = record.Data
			if type(rawData) ~= "table" or type(rawData.Version) ~= "number" then
				state.Reason = "Corrupt"
				return nil
			end
			if rawData.Version > cfg.DataVersion then
				state.Reason = "Newer"
				return nil
			end

			local owner = record.SessionId
			if type(owner) == "string" and owner ~= sessionId then
				local lockedAt = record.LockedAt
				local age = if type(lockedAt) == "number" then now - lockedAt else math.huge
				if age < cfg.LockExpirySeconds then
					state.Reason = "Locked"
					return nil
				end
			end

			state.Data = sanitize(rawData, player.Name)
			record.SessionId = sessionId
			record.LockedAt = now
			return record
		end)
	end)

	if not ok then
		local message = tostring(err)
		session.FailReason = "Error"
		if isStudioApiDisabled(message) then
			enterTemporaryMode()
			return "Fatal", message
		end
		return "Retry", message
	end

	local reason = state.Reason
	if reason == "Locked" then
		session.FailReason = "Locked"
		return "Retry", "ข้อมูลถูกล็อกโดยเซิร์ฟเวอร์อื่น"
	elseif reason == "Newer" or reason == "Corrupt" then
		session.FailReason = reason
		return "Fatal", if reason == "Newer" then "ข้อมูลเป็น Version ที่ใหม่กว่าเซิร์ฟเวอร์รู้จัก" else "ข้อมูลเสียหาย/รูปแบบผิด"
	end

	local data = state.Data
	if data == nil then
		session.FailReason = "Error"
		return "Retry", "UpdateAsync ไม่คืนข้อมูล"
	end
	session.Data = data
	session.LockHeld = true
	return "Ok", nil
end

-- เซฟข้อมูลปัจจุบัน ถ้า release = true จะปล่อย lock ด้วย
local function attemptSave(session: Session, release: boolean): (Outcome, string?)
	local store = getStore()
	if store == nil then
		return "Retry", "DataStore ยังไม่พร้อม"
	end
	local data = session.Data
	if data == nil then
		return "Fatal", "ไม่มีข้อมูลให้เซฟ"
	end
	local snapshot = copyData(data)
	local state: AttemptState = { Data = nil, Reason = nil, Lost = false }

	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(session.Player), function(old: any)
			state.Lost = false
			if old ~= nil then
				if type(old) ~= "table" then
					state.Lost = true
					return nil
				end
				local record: { [string]: any } = old
				if record.SessionId ~= sessionId then
					state.Lost = true
					return nil
				end
			end
			if release then
				return { Data = snapshot }
			end
			return { Data = snapshot, SessionId = sessionId, LockedAt = os.time() }
		end)
	end)

	if not ok then
		return "Retry", tostring(err)
	end
	if state.Lost then
		session.LockLost = true
		return "Fatal", "lock ไม่ตรงกับเซิร์ฟเวอร์นี้ ยกเลิกการเขียนเพื่อไม่ทับข้อมูลของเซิร์ฟเวอร์อื่น"
	end
	if release then
		session.LockHeld = false
	end
	return "Ok", nil
end

-- ปล่อย lock อย่างเดียว ไม่แตะข้อมูล (ใช้เมื่อผู้เล่นออกระหว่างโหลด)
local function attemptReleaseOnly(session: Session): (Outcome, string?)
	local store = getStore()
	if store == nil then
		return "Retry", "DataStore ยังไม่พร้อม"
	end
	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(session.Player), function(old: any)
			if type(old) ~= "table" then
				return nil
			end
			local record: { [string]: any } = old
			if record.SessionId ~= sessionId then
				return nil
			end
			record.SessionId = nil
			record.LockedAt = nil
			return record
		end)
	end)
	if not ok then
		return "Retry", tostring(err)
	end
	session.LockHeld = false
	return "Ok", nil
end

local function saveSession(session: Session, release: boolean, retryCfg: RetryConfig): boolean
	-- กันเซฟซ้อน: รอรอบที่กำลังเซฟอยู่ให้จบก่อน
	local waited = false
	while session.Saving do
		waited = true
		task.wait(cfg.PollSeconds)
	end
	if waited and not release then
		return true
	end

	session.Saving = true
	local player = session.Player
	local notified = false
	local outcome, message = runWithBackoff(retryCfg, `บันทึกข้อมูล {player.Name}`, function()
		return attemptSave(session, release)
	end, function()
		return false
	end, function(_attemptNumber: number)
		if not notified then
			notified = true
			NotifyService.Notify(player, "SaveRetrying", "info")
		end
	end)
	session.Saving = false

	if outcome == "Ok" then
		return true
	end
	if session.LockLost then
		-- lock ถูกเซิร์ฟเวอร์อื่นเอาไป: หยุด autosave (State ไม่ใช่ Active แล้ว) และ kick ถ้ายังอยู่ในเกม
		session.State = "Failed"
		logError(`{LOG} lock ของ {player.Name} ถูกเซิร์ฟเวอร์อื่นเอาไป หยุดบันทึกของ session นี้เพื่อไม่ทับข้อมูล: {tostring(message)}`)
		if not release and player.Parent == Players then
			player:Kick(Strings.Bilingual("KickLockLost"))
		end
		return false
	end
	logError(`{LOG} บันทึกข้อมูล {player.Name} ล้มเหลวถาวร: {tostring(message)}`)
	NotifyService.Notify(player, "SaveFailed", "error")
	return false
end

local function releaseLockOnly(session: Session)
	if not session.LockHeld then
		return
	end
	local outcome, message = runWithBackoff(cfg.CloseSave, `ปล่อย lock {session.Player.Name}`, function()
		return attemptReleaseOnly(session)
	end, function()
		return false
	end, nil)
	if outcome ~= "Ok" then
		logError(`{LOG} ปล่อย lock ของ {session.Player.Name} ไม่สำเร็จ (จะหมดอายุเองใน {cfg.LockExpirySeconds} วินาที): {tostring(message)}`)
	end
end

local function cancelAutosave(session: Session)
	local thread = session.AutosaveThread
	session.AutosaveThread = nil
	if thread and not session.Saving then
		pcall(task.cancel, thread)
	end
end

local function startAutosave(session: Session)
	session.AutosaveThread = task.spawn(function()
		task.wait(random:NextNumber(0, cfg.AutosaveJitterSeconds))
		while session.State == "Active" and not session.Left do
			task.wait(cfg.AutosaveIntervalSeconds)
			if session.Left or session.Finalizing then
				break
			end
			saveSession(session, false, cfg.Save)
		end
	end)
end

local function activateTemporary(session: Session)
	session.Data = copyData(cfg.Defaults)
	session.Temporary = true
	session.State = "Active"
	NotifyService.Notify(session.Player, "TemporaryMode", "error")
	loadedEvent:Fire(session.Player)
end

local function kickFor(session: Session)
	local messageKey = "KickLoadFailed"
	if session.FailReason == "Newer" then
		messageKey = "KickDataNewer"
	elseif session.FailReason == "Corrupt" then
		messageKey = "KickDataCorrupt"
	elseif session.FailReason == "Locked" then
		messageKey = "KickDataLocked"
	end
	if session.Player.Parent == Players then
		session.Player:Kick(Strings.Bilingual(messageKey))
	end
end

local function loadSession(session: Session)
	busy += 1
	local player = session.Player

	-- ถ้าผู้เล่นคนเดียวกันเพิ่งออกและกำลังเซฟอยู่ รอให้ปล่อย lock ก่อน
	while closingUserIds[player.UserId] and not session.Left do
		task.wait(cfg.PollSeconds)
	end

	local outcome: Outcome = "Aborted"
	local message: string? = nil
	if not session.Left and not temporaryMode then
		outcome, message = runWithBackoff(cfg.Load, `โหลดข้อมูล {player.Name}`, function()
			return attemptLoad(session)
		end, function()
			return session.Left or temporaryMode
		end, nil)
	end

	if session.Left then
		-- ผู้เล่นออกระหว่างโหลด: ห้ามเซฟ ปล่อย lock อย่างเดียว
		releaseLockOnly(session)
		sessions[player] = nil
	elseif temporaryMode then
		activateTemporary(session)
	elseif outcome == "Ok" and session.Data then
		session.State = "Active"
		startAutosave(session)
		NotifyService.Notify(player, "DataLoaded", "success")
		loadedEvent:Fire(player)
	else
		session.State = "Failed"
		logError(`{LOG} โหลดข้อมูล {player.Name} ไม่สำเร็จ ({session.FailReason}) kick ผู้เล่นและไม่เขียนทับข้อมูลเดิม: {tostring(message)}`)
		kickFor(session)
	end

	busy -= 1
end

-- เรียก handler ของ OnBeforeSave แบบ synchronous (ก่อน copyData ของการเซฟสุดท้าย)
-- แต่ละตัวครอบ pcall: ถ้า error จะ warn แล้วเซฟต่อตามปกติ
local function runBeforeSave(player: Player, data: PlayerData)
	for _, handler in table.clone(beforeSaveHandlers) do
		local ok, err = pcall(function(): string?
			handler(player, data)
			return nil
		end)
		if not ok then
			warn(`{LOG} OnBeforeSave handler ของ {player.Name} error (เซฟต่อตามปกติ): {tostring(err)}`)
		end
	end
end

local function finalizeSession(session: Session, retryCfg: RetryConfig)
	if session.Finalizing then
		return
	end
	session.Finalizing = true
	busy += 1
	cancelAutosave(session)
	if session.State == "Active" and not session.Temporary and session.Data then
		local userId = session.Player.UserId
		closingUserIds[userId] = true
		runBeforeSave(session.Player, session.Data)
		saveSession(session, true, retryCfg)
		closingUserIds[userId] = nil
	end
	busy -= 1
end

local function onPlayerAdded(player: Player)
	if sessions[player] then
		return
	end
	local session: Session = {
		Player = player,
		Data = nil,
		State = "Loading",
		Temporary = false,
		LockHeld = false,
		Left = false,
		Saving = false,
		Finalizing = false,
		LockLost = false,
		FailReason = "Error",
		AutosaveThread = nil,
	}
	sessions[player] = session
	task.spawn(loadSession, session)
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if session == nil then
		return
	end
	session.Left = true
	if session.State == "Loading" then
		return -- loadSession จัดการปล่อย lock และล้างเอง
	end
	task.spawn(function()
		finalizeSession(session, cfg.Save)
		sessions[player] = nil
	end)
end

local function onClose()
	local active: { Session } = {}
	for _, session in sessions do
		if session.State == "Loading" then
			session.Left = true
		elseif session.State == "Active" and not session.Finalizing then
			table.insert(active, session)
		end
	end
	for _, session in active do
		task.spawn(finalizeSession, session, cfg.CloseSave)
	end
	local deadline = os.clock() + cfg.ShutdownMaxWaitSeconds
	while busy > 0 and os.clock() < deadline do
		task.wait(cfg.PollSeconds)
	end
	if busy > 0 then
		logError(`{LOG} ปิดเซิร์ฟเวอร์: ยังบันทึกไม่เสร็จ {busy} งาน เมื่อหมดเวลา`)
	end
end

-- ข้อมูลของผู้เล่น (table จริงใน memory) หรือ nil ถ้ายังโหลดไม่เสร็จ/โหลดไม่สำเร็จ
function DataService.GetData(player: Player): PlayerData?
	local session = sessions[player]
	if session and session.State == "Active" then
		return session.Data
	end
	return nil
end

-- ลงทะเบียน handler ที่ถูกเรียกแบบ synchronous ก่อนเซฟครั้งสุดท้ายของผู้เล่น (ตอนออกเกมและ BindToClose)
-- handler แก้ data ได้และต้องไม่ yield คืนฟังก์ชันสำหรับยกเลิกการลงทะเบียน
function DataService.OnBeforeSave(handler: BeforeSaveHandler): () -> ()
	table.insert(beforeSaveHandlers, handler)
	return function()
		local index = table.find(beforeSaveHandlers, handler)
		if index then
			table.remove(beforeSaveHandlers, index)
		end
	end
end

function DataService.IsLoaded(player: Player): boolean
	return DataService.GetData(player) ~= nil
end

-- true ถ้าผู้เล่นอยู่ในโหมดชั่วคราว (ไม่บันทึก)
function DataService.IsTemporary(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.Temporary
end

function DataService.Start()
	NotifyService.SetLanguageProvider(function(player: Player): string
		local session = sessions[player]
		if session and session.Data then
			return session.Data.Settings.Language
		end
		return cfg.DefaultLanguage
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	game:BindToClose(onClose)

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return DataService
