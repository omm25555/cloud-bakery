--!strict
-- QuestService: Daily Quest 3 ข้อ (ตายตัวทุกวัน) server ตัดสินความคืบหน้า/ครบ/รับรางวัล/รีเซ็ตวันทั้งหมด
-- client ส่งได้แค่ "ขอ snapshot" (QuestSync) และ "ขอรับรางวัล (questId)" (QuestClaim)
-- ความคืบหน้านับจาก QuestService.Record ที่ Farm/Bake/ServeService เรียกหลังเหตุการณ์สำเร็จจริงเท่านั้น
-- ข้อมูลอยู่ใน PlayerData.Quests เซฟพร้อมเหรียญด้วย DataService (รับรางวัล = ตั้ง Claimed + บวกเหรียญในจังหวะเดียว ไม่มี yield)
-- ตอน require ไม่มี side effect (ไม่สร้าง remote ไม่ต่อ event ไม่ yield) ทุกอย่างเริ่มใน Start

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local QuestsConfig = require(ReplicatedStorage.Shared.Config.Quests)
local RateLimits = require(ReplicatedStorage.Shared.Config.RateLimits)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local QuestRules = require(ReplicatedStorage.Shared.QuestRules)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local NotifyService = require(script.Parent.NotifyService)

local LOG = "[QuestService]"

type PlayerData = PlayerDataConfig.PlayerData
type QuestConfig = QuestsConfig.QuestConfig

type StateEntry = {
	Id: string,
	Progress: number,
	Target: number,
	Claimed: boolean,
	RewardCoins: number,
	RewardReputation: number,
}

local QuestService = {}

-- ชื่อชนิดเหตุการณ์ที่ Service อื่นส่งให้ Record
QuestService.Kinds = QuestsConfig.Kinds

local started = false
local limiter: RateLimiter.RateLimiter? = nil
local stateEvent: RemoteEvent? = nil
local currencyEvent: RemoteEvent? = nil
local connections: { RBXScriptConnection } = {}
local syncing: { [Player]: boolean } = {}
local expiryWarned: { [Player]: number } = {}
local temporaryWarned: { [Player]: boolean } = {}

local function questName(quest: QuestConfig, language: string): string
	local args: { [string]: string | number } = { target = quest.Target }
	return Strings.Format(quest.NameKey, language, args)
end

local function sendState(player: Player, data: PlayerData)
	local event = stateEvent
	if event == nil then
		return
	end
	local quests = data.Quests
	local entries: { StateEntry } = {}
	for _, quest in QuestsConfig.List do
		table.insert(entries, {
			Id = quest.Id,
			Progress = QuestRules.ClampProgress(quests.Progress[quest.Id] or 0, quest.Target),
			Target = quest.Target,
			Claimed = quests.Claimed[quest.Id] == true,
			RewardCoins = quest.RewardCoins,
			RewardReputation = quest.RewardReputation,
		})
	end
	event:FireClient(player, {
		Quests = entries,
		ResetAt = QuestRules.ResetAt(quests.Day),
		Language = data.Settings.Language,
	})
end

-- เปลี่ยนวันถ้าถึงวันใหม่: ล้างความคืบหน้า/สถานะรับ แจ้งผู้เล่น คืน true ถ้ารีเซ็ต
-- Day ที่มากกว่าวันนี้ (นาฬิกาเซิร์ฟเวอร์เหลื่อมกัน) ไม่รีเซ็ต เพื่อไม่ให้รับรางวัลซ้ำข้ามเซิร์ฟเวอร์
local function refreshDay(player: Player, data: PlayerData): boolean
	local today = QuestRules.DayIndex(os.time())
	local quests = data.Quests
	if quests.Day >= today then
		return false
	end
	quests.Day = today
	table.clear(quests.Progress)
	table.clear(quests.Claimed)
	expiryWarned[player] = nil
	NotifyService.Notify(player, "QuestNewDay", "info", nil)
	return true
end

local function reject(
	player: Player,
	remoteName: string,
	reason: string,
	key: string,
	args: { [string]: string | number }?
)
	warn(`{LOG} {player.Name} {remoteName} ปฏิเสธ: {reason}`)
	NotifyService.Notify(player, key, "error", args)
end

local function isValidAmount(amount: unknown): boolean
	return type(amount) == "number"
		and amount == amount
		and amount == math.floor(amount)
		and amount > 0
		and amount <= PlayerDataConfig.Limits.MaxQuestProgress
end

local function recordUnsafe(player: Player, kind: string, id: string, amount: number)
	local data = DataService.GetData(player)
	if data == nil then
		warn(`{LOG} Record ({kind} {id} x{amount}) ของ {player.Name}: ข้อมูลผู้เล่นยังไม่พร้อม ข้าม`)
		return
	end
	local changed = refreshDay(player, data)
	local quests = data.Quests
	local language = data.Settings.Language
	for _, quest in QuestsConfig.List do
		if quest.Kind == kind and (quest.ItemId == nil or quest.ItemId == id) then
			local current = QuestRules.ClampProgress(quests.Progress[quest.Id] or 0, quest.Target)
			if current < quest.Target then
				local updated = math.min(current + amount, quest.Target)
				quests.Progress[quest.Id] = updated
				changed = true
				if updated >= quest.Target then
					local args: { [string]: string | number } = { quest = questName(quest, language) }
					NotifyService.Notify(player, "QuestComplete", "success", args)
				end
			end
		end
	end
	if changed then
		sendState(player, data)
	end
end

-- นับความคืบหน้าหลังเหตุการณ์สำเร็จจริง (เก็บเกี่ยว/ใส่ขนมเข้ากระเป๋า/เสิร์ฟ) ไม่ throw ไม่ yield
-- เรียกผิดจังหวะ/ค่าผิด = warn แล้วข้าม
function QuestService.Record(player: Player, kind: string, id: string, amount: number)
	if not started then
		warn(`{LOG} Record ถูกเรียกก่อน Start ({tostring(kind)} {tostring(id)}) ข้าม`)
		return
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		warn(`{LOG} Record ({tostring(kind)} {tostring(id)}) ผู้เล่นไม่อยู่ในเกมแล้ว ข้าม`)
		return
	end
	if type(kind) ~= "string" or QuestsConfig.Kinds[kind] ~= kind then
		warn(`{LOG} Record ของ {player.Name}: kind "{tostring(kind)}" ไม่อยู่ในรายการ ข้าม`)
		return
	end
	if type(id) ~= "string" or #id > QuestsConfig.MaxIdLength then
		warn(`{LOG} Record ({kind}) ของ {player.Name}: id ไม่ถูกต้อง ข้าม`)
		return
	end
	if not isValidAmount(amount) then
		warn(`{LOG} Record ({kind} {id}) ของ {player.Name}: amount "{tostring(amount)}" ไม่ใช่จำนวนเต็มบวกในช่วงที่รับได้ ข้าม`)
		return
	end
	local ok, err = pcall(function()
		recordUnsafe(player, kind, id, amount)
	end)
	if not ok then
		warn(`{LOG} Record ({kind} {id} x{amount}) ของ {player.Name} error: {tostring(err)}`)
	end
end

local function onSync(player: Player)
	local current = limiter
	if current == nil or not current:Check(player, "QuestSync") then
		return
	end
	if syncing[player] then
		return
	end
	syncing[player] = true
	task.spawn(function()
		local waited = 0
		local data = DataService.GetData(player)
		while data == nil and waited < QuestsConfig.SyncWaitSeconds and player.Parent == Players do
			task.wait(QuestsConfig.SyncPollSeconds)
			waited += QuestsConfig.SyncPollSeconds
			data = DataService.GetData(player)
		end
		syncing[player] = nil
		if player.Parent ~= Players then
			return
		end
		if data == nil then
			reject(player, "QuestSync", `ข้อมูลผู้เล่นยังโหลดไม่เสร็จหลังรอ {QuestsConfig.SyncWaitSeconds} วินาที`, "DataNotReady", nil)
			return
		end
		refreshDay(player, data)
		if DataService.IsTemporary(player) and not temporaryWarned[player] then
			temporaryWarned[player] = true
			warn(`{LOG} {player.Name} อยู่ในโหมดชั่วคราว ความคืบหน้าเควสจะไม่ถูกบันทึก`)
			NotifyService.Notify(player, "TemporaryMode", "error", nil)
		end
		sendState(player, data)
	end)
end

local function onClaim(player: Player, raw: unknown)
	local current = limiter
	if current == nil or not current:Check(player, "QuestClaim") then
		return
	end
	if type(raw) ~= "string" then
		reject(player, "QuestClaim", `questId ไม่ใช่ string ({typeof(raw)})`, "InvalidRequest", nil)
		return
	end
	local questId = raw :: string
	if #questId > QuestsConfig.MaxIdLength then
		reject(player, "QuestClaim", `questId ยาวเกิน {QuestsConfig.MaxIdLength} ตัวอักษร`, "InvalidRequest", nil)
		return
	end
	local quest = QuestsConfig.ById[questId]
	if quest == nil then
		local shown = string.sub(questId, 1, QuestsConfig.MaxLogIdLength)
		reject(player, "QuestClaim", `questId "{shown}" ไม่อยู่ในรายการเควส`, "InvalidRequest", nil)
		return
	end
	local data = DataService.GetData(player)
	if data == nil then
		reject(player, "QuestClaim", "ข้อมูลผู้เล่นยังโหลดไม่เสร็จ", "DataNotReady", nil)
		return
	end

	-- จากตรงนี้ถึงจบการให้รางวัลไม่มี yield: กดรับซ้อนสองครั้งไม่ได้
	if refreshDay(player, data) then
		sendState(player, data)
		reject(player, "QuestClaim", `ข้ามวันระหว่างเล่น เควส {quest.Id} ถูกรีเซ็ตก่อนรับ`, "QuestDayChanged", nil)
		return
	end
	local language = data.Settings.Language
	local quests = data.Quests
	local progress = QuestRules.ClampProgress(quests.Progress[quest.Id] or 0, quest.Target)
	local nameArgs: { [string]: string | number } = {
		quest = questName(quest, language),
		progress = progress,
		target = quest.Target,
	}
	if quests.Claimed[quest.Id] == true then
		reject(player, "QuestClaim", `เควส {quest.Id} รับรางวัลไปแล้ว`, "QuestAlreadyClaimed", nameArgs)
		return
	end
	if progress < quest.Target then
		reject(player, "QuestClaim", `เควส {quest.Id} ยังไม่ครบ ({progress}/{quest.Target})`, "QuestNotComplete", nameArgs)
		return
	end

	local limits = PlayerDataConfig.Limits
	local newCoins = math.min(data.Coins + quest.RewardCoins, limits.MaxCoins)
	local newReputation = math.min(data.Reputation + quest.RewardReputation, limits.MaxReputation)
	local coinsAdded = newCoins - data.Coins
	local repAdded = newReputation - data.Reputation
	quests.Claimed[quest.Id] = true
	data.Coins = newCoins
	data.Reputation = newReputation

	local event = currencyEvent
	if event ~= nil then
		event:FireClient(player, { Coins = data.Coins, Reputation = data.Reputation })
	end
	sendState(player, data)
	local okArgs: { [string]: string | number } = {
		quest = nameArgs.quest,
		coins = coinsAdded,
		reputation = repAdded,
	}
	local okKey = if quest.RewardReputation > 0 then "QuestClaimOkRep" else "QuestClaimOk"
	NotifyService.Notify(player, okKey, "success", okArgs)
	if coinsAdded < quest.RewardCoins or repAdded < quest.RewardReputation then
		warn(`{LOG} {player.Name} รางวัลเควส {quest.Id} ติดเพดาน ได้ {coinsAdded}/{quest.RewardCoins} เหรียญ {repAdded}/{quest.RewardReputation} Reputation`)
		NotifyService.Notify(player, "QuestRewardCapped", "info", nil)
	end
	print(`{LOG} {player.Name} รับรางวัลเควส {quest.Id} +{coinsAdded} เหรียญ +{repAdded} Reputation`)
end

-- เตือนเควสที่ครบแล้วแต่ยังไม่รับ เมื่อใกล้รีเซ็ต (ครั้งเดียวต่อวันต่อผู้เล่น)
local function warnExpiring(player: Player, data: PlayerData)
	local quests = data.Quests
	if expiryWarned[player] == quests.Day then
		return
	end
	local remaining = QuestRules.ResetAt(quests.Day) - os.time()
	if remaining > QuestsConfig.ExpiryWarnSeconds then
		return
	end
	for _, quest in QuestsConfig.List do
		local progress = QuestRules.ClampProgress(quests.Progress[quest.Id] or 0, quest.Target)
		if progress >= quest.Target and quests.Claimed[quest.Id] ~= true then
			expiryWarned[player] = quests.Day
			local args: { [string]: string | number } = { minutes = math.max(1, math.ceil(remaining / QuestsConfig.SecondsPerMinute)) }
			NotifyService.Notify(player, "QuestExpiring", "info", args)
			return
		end
	end
end

local function checkPlayer(player: Player)
	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	if refreshDay(player, data) then
		sendState(player, data)
		return
	end
	warnExpiring(player, data)
end

local function tickLoop()
	while true do
		task.wait(QuestsConfig.TickSeconds)
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(function()
				checkPlayer(player)
			end)
			if not ok then
				warn(`{LOG} ตรวจวันใหม่ของ {player.Name} error: {tostring(err)}`)
			end
		end
	end
end

local function onPlayerRemoving(player: Player)
	syncing[player] = nil
	expiryWarned[player] = nil
	temporaryWarned[player] = nil
	local current = limiter
	if current ~= nil then
		current:Remove(player)
	end
end

function QuestService.Start()
	if started then
		return
	end
	limiter = RateLimiter.new(RateLimits, function(player: Player, _remoteName: string)
		NotifyService.NotifyRateLimited(player)
	end)
	stateEvent = Remotes.GetEvent("QuestState")
	currencyEvent = Remotes.GetEvent("CurrencyUpdate")
	table.insert(connections, Remotes.GetEvent("QuestSync").OnServerEvent:Connect(onSync))
	table.insert(connections, Remotes.GetEvent("QuestClaim").OnServerEvent:Connect(onClaim))
	table.insert(connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
	started = true
	task.spawn(tickLoop)
end

return QuestService
