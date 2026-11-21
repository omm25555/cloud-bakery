--!strict
-- ข้อมูลผู้เล่น: โหลด/บันทึก DataStore (ลองใหม่เมื่อล้มเหลว), autosave, บันทึกตอนออกและ BindToClose
-- Service อื่นแก้ข้อมูลผ่าน PlayerDataService.update() เท่านั้น แล้ว state จะถูกส่งให้ client เอง

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = Shared.Config
local GameConfig = require(Config.Game)
local Progression = require(Config.Progression)
local Recipes = require(Config.Recipes)
local Upgrades = require(Config.Upgrades)
local Quests = require(Config.Quests)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local NotifyService = require(script.Parent.NotifyService)
local RateLimiter = require(script.Parent.Parent.Modules.RateLimiter)

local SOURCE = "PlayerDataService"

type Profile = {
	data: Types.SaveData,
	canSave: boolean,
	dirty: boolean,
	saving: boolean,
	pushQueued: boolean,
}

local PlayerDataService = {}

local profiles: { [Player]: Profile } = {}
local loadedCallbacks: { (player: Player, data: Types.SaveData) -> () } = {}

local stateEvent = Remotes.GetEvent("StateChanged")
local getStateFunction = Remotes.GetFunction("GetState")
local setLanguageEvent = Remotes.GetEvent("SetLanguage")

local getStateLimit = GameConfig.RateLimits.GetState
local getStateLimiter = RateLimiter.new(getStateLimit.MaxCalls, getStateLimit.WindowSeconds)
local languageLimit = GameConfig.RateLimits.SetLanguage
local languageLimiter = RateLimiter.new(languageLimit.MaxCalls, languageLimit.WindowSeconds)

-- Studio ที่ไม่ได้เปิด API Services หรือ place ที่ยังไม่ publish ใช้ DataStore ไม่ได้
local function isStudioApiError(message: string): boolean
	return string.find(message, "StudioAccessToApisNotAllowed", 1, true) ~= nil
		or string.find(message, "Studio access to APIs is not allowed", 1, true) ~= nil
		or string.find(message, "publish", 1, true) ~= nil
end

local dataStore: DataStore? = nil
local dataStoreNoticeKey = "n.dataLoadFailed"
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStoreName)
	end)
	if ok then
		dataStore = result
	else
		warn(`[{SOURCE}] เปิด DataStore ไม่ได้ ({result}) รอบนี้จะไม่บันทึกข้อมูล`)
		if isStudioApiError(tostring(result)) then
			dataStoreNoticeKey = "n.dataStudioNoApi"
		end
	end
end

local function dataKey(player: Player): string
	return `{GameConfig.DataKeyPrefix}{player.UserId}`
end

local function newCounts(source: { [string]: number }): Types.Counts
	local counts: Types.Counts = {}
	for id, amount in source do
		counts[id] = amount
	end
	return counts
end

local function defaultData(): Types.SaveData
	local upgrades: Types.Counts = {}
	for _, lineId in Upgrades.Order do
		upgrades[lineId] = 0
	end
	return {
		version = GameConfig.DataVersion,
		coins = GameConfig.StartingCoins,
		reputation = 0,
		ingredients = newCounts(GameConfig.StartingIngredients),
		goods = {},
		upgrades = upgrades,
		questDay = Formulas.questDay(os.time(), Quests.SecondsPerDay),
		questProgress = {},
		questClaimed = false,
		oven = {},
		settings = { language = "th" },
		totalServed = 0,
		totalBaked = 0,
	}
end

local function readNumber(value: any, fallback: number, minValue: number, maxValue: number): number
	if typeof(value) ~= "number" or value ~= value then
		return fallback
	end
	return math.clamp(math.floor(value), minValue, maxValue)
end

local function readCounts(value: any, allowed: { [string]: any }, maxValue: number): Types.Counts
	local counts: Types.Counts = {}
	if typeof(value) ~= "table" then
		return counts
	end
	for id, amount in value do
		if typeof(id) == "string" and allowed[id] ~= nil then
			local clean = readNumber(amount, 0, 0, maxValue)
			if clean > 0 then
				counts[id] = clean
			end
		end
	end
	return counts
end

-- ตรวจและเติมค่าที่ขาดจากข้อมูลที่โหลดมา (กันข้อมูลเสีย/เวอร์ชันเก่า)
local function sanitize(raw: any): Types.SaveData
	local data = defaultData()
	if typeof(raw) ~= "table" then
		return data
	end
	local ingredientIds: { [string]: any } = {}
	for _, id in Progression.IngredientOrder do
		ingredientIds[id] = true
	end
	local maxStack = GameConfig.MaxStackPerItem

	data.coins = readNumber(raw.coins, data.coins, 0, GameConfig.MaxCoins)
	data.reputation = readNumber(raw.reputation, 0, 0, GameConfig.MaxCoins)
	if raw.ingredients ~= nil then
		data.ingredients = readCounts(raw.ingredients, ingredientIds, maxStack)
	end
	data.goods = readCounts(raw.goods, Recipes, maxStack)
	for _, lineId in Upgrades.Order do
		local line = Upgrades.Lines[lineId]
		local stored = if typeof(raw.upgrades) == "table" then raw.upgrades[lineId] else nil
		data.upgrades[lineId] = readNumber(stored, 0, 0, #line.Costs)
	end
	data.questDay = readNumber(raw.questDay, data.questDay, 0, math.huge)
	local questIds: { [string]: any } = {}
	for _, quest in Quests.Daily do
		questIds[quest.Id] = true
	end
	data.questProgress = readCounts(raw.questProgress, questIds, maxStack)
	data.questClaimed = raw.questClaimed == true
	if typeof(raw.oven) == "table" then
		for _, slot in raw.oven do
			if typeof(slot) == "table" and typeof(slot.recipeId) == "string" and Recipes[slot.recipeId] ~= nil then
				table.insert(data.oven, {
					recipeId = slot.recipeId,
					pieces = readNumber(slot.pieces, 1, 1, maxStack),
					readyAt = readNumber(slot.readyAt, os.time(), 0, math.huge),
				})
			end
		end
	end
	if typeof(raw.settings) == "table" and (raw.settings.language == "th" or raw.settings.language == "en") then
		data.settings.language = raw.settings.language
	end
	data.totalServed = readNumber(raw.totalServed, 0, 0, math.huge)
	data.totalBaked = readNumber(raw.totalBaked, 0, 0, math.huge)
	return data
end

local function buildState(profile: Profile): Types.PlayerState
	local data = profile.data
	local info = Formulas.levelInfo(data.reputation)
	return {
		coins = data.coins,
		reputation = data.reputation,
		level = info.level,
		levelFloor = info.floor,
		levelCeil = info.ceil,
		ingredients = data.ingredients,
		goods = data.goods,
		upgrades = data.upgrades,
		questProgress = data.questProgress,
		questClaimed = data.questClaimed,
		oven = data.oven,
		ovenSlots = Formulas.ovenSlots(Formulas.upgradeLevel(data.upgrades, "Oven")),
		settings = data.settings,
		dataSaving = profile.canSave,
		serverTime = os.time(),
	}
end

local function queuePush(player: Player, profile: Profile)
	if profile.pushQueued then
		return
	end
	profile.pushQueued = true
	task.delay(GameConfig.StatePushDebounceSeconds, function()
		profile.pushQueued = false
		if profiles[player] == profile and player.Parent == Players then
			stateEvent:FireClient(player, buildState(profile))
		end
	end)
end

local function loadData(player: Player): (Types.SaveData, boolean, string?)
	local store = dataStore
	if store == nil then
		return defaultData(), false, dataStoreNoticeKey
	end
	local lastError = ""
	for attempt = 1, GameConfig.DataRetryAttempts do
		local ok, result = pcall(function()
			return store:GetAsync(dataKey(player))
		end)
		if ok then
			return sanitize(result), true, nil
		end
		lastError = tostring(result)
		if isStudioApiError(lastError) then
			warn(`[{SOURCE}] Studio ไม่ได้เปิด API Services: โหลดข้อมูล {player.Name} ไม่ได้ รอบนี้จะไม่บันทึก`)
			return defaultData(), false, "n.dataStudioNoApi"
		end
		warn(`[{SOURCE}] โหลดข้อมูล {player.Name} ไม่สำเร็จ (ครั้งที่ {attempt}/{GameConfig.DataRetryAttempts}): {lastError}`)
		if attempt < GameConfig.DataRetryAttempts then
			task.wait(GameConfig.DataRetryDelaySeconds * attempt)
		end
	end
	task.spawn(error, `[{SOURCE}] โหลดข้อมูล {player.Name} ล้มเหลวครบทุกครั้ง: {lastError}`, 0)
	return defaultData(), false, "n.dataLoadFailed"
end

local function saveProfile(player: Player, profile: Profile, notifyPlayer: boolean): boolean
	local store = dataStore
	if store == nil or not profile.canSave then
		return false
	end
	if profile.saving then
		-- มีการบันทึกอยู่แล้ว (เช่น ตอนออก + BindToClose พร้อมกัน) รอให้รอบนั้นจบ
		while profile.saving do
			task.wait(GameConfig.SavePollSeconds)
		end
		if not profile.dirty then
			return true
		end
	end
	profile.saving = true
	-- ล้าง dirty ก่อนเริ่มบันทึก ถ้ามี update() ระหว่างรอ UpdateAsync จะตั้ง dirty ใหม่ และรอบถัดไปจะบันทึกให้
	profile.dirty = false
	local snapshot = profile.data
	local maxAttempts = GameConfig.DataRetryAttempts
	local saved = false
	local lastError = ""
	for attempt = 1, maxAttempts do
		local ok, result = pcall(function()
			return store:UpdateAsync(dataKey(player), function(_old: any): any
				return snapshot
			end)
		end)
		if ok then
			saved = true
			break
		end
		lastError = tostring(result)
		warn(`[{SOURCE}] บันทึกข้อมูล {player.Name} ไม่สำเร็จ (ครั้งที่ {attempt}/{maxAttempts}): {lastError}`)
		if notifyPlayer and player.Parent == Players then
			NotifyService.blocked(player, "n.saveRetry", { attempt = attempt, max = maxAttempts })
		end
		if attempt < maxAttempts then
			task.wait(GameConfig.DataRetryDelaySeconds * attempt)
		end
	end
	profile.saving = false
	if not saved then
		profile.dirty = true
		task.spawn(error, `[{SOURCE}] บันทึกข้อมูล {player.Name} ล้มเหลวครบทุกครั้ง: {lastError}`, 0)
		if notifyPlayer and player.Parent == Players then
			NotifyService.blocked(player, "n.saveFailed")
		end
	end
	return saved
end

local function onPlayerAdded(player: Player)
	local data, canSave, noticeKey = loadData(player)
	if player.Parent ~= Players then
		return
	end
	local profile: Profile = {
		data = data,
		canSave = canSave,
		dirty = false,
		saving = false,
		pushQueued = false,
	}
	profiles[player] = profile
	for _, callback in loadedCallbacks do
		local ok, err = pcall(function()
			callback(player, data)
		end)
		if not ok then
			NotifyService.unexpected(SOURCE, player, `callback ตอนโหลดข้อมูลล้มเหลว: {err}`)
		end
	end
	stateEvent:FireClient(player, buildState(profile))
	if noticeKey then
		NotifyService.blocked(player, noticeKey)
	end
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile == nil then
		return
	end
	saveProfile(player, profile, false)
	profiles[player] = nil
end

-- API ----------------------------------------------------------------

function PlayerDataService.get(player: Player): Types.SaveData?
	local profile = profiles[player]
	return if profile then profile.data else nil
end

function PlayerDataService.isLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

-- แก้ข้อมูลผู้เล่น: fn ได้รับ data จริง (แก้ได้ทันที) ตรวจเลเวลอัปให้ และส่ง state ให้ client
function PlayerDataService.update(player: Player, fn: (data: Types.SaveData) -> ()): boolean
	local profile = profiles[player]
	if profile == nil then
		return false
	end
	local before = Formulas.levelInfo(profile.data.reputation).level
	fn(profile.data)
	profile.data.coins = math.clamp(math.floor(profile.data.coins), 0, GameConfig.MaxCoins)
	profile.dirty = true
	local after = Formulas.levelInfo(profile.data.reputation).level
	if after > before then
		NotifyService.success(player, "n.levelUp", { level = after })
		for recipeId, unlockLevel in Progression.RecipeUnlockLevel do
			if unlockLevel > before and unlockLevel <= after then
				NotifyService.success(player, "n.recipeUnlocked", { recipe = `item.{recipeId}` })
			end
		end
	end
	queuePush(player, profile)
	return true
end

function PlayerDataService.onLoaded(callback: (player: Player, data: Types.SaveData) -> ())
	table.insert(loadedCallbacks, callback)
	for player, profile in profiles do
		task.spawn(callback, player, profile.data)
	end
end

function PlayerDataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	getStateFunction.OnServerInvoke = function(player: Player): Types.PlayerState?
		if not getStateLimiter.allow(player) then
			return nil
		end
		local profile = profiles[player]
		return if profile then buildState(profile) else nil
	end

	setLanguageEvent.OnServerEvent:Connect(function(player: Player, language: any)
		if not languageLimiter.allow(player) then
			NotifyService.blocked(player, "n.tooFast")
			return
		end
		if language ~= "th" and language ~= "en" then
			NotifyService.rejected(SOURCE, player, `ภาษาไม่ถูกต้อง: {tostring(language)}`)
			return
		end
		local chosen: string = language
		local updated = PlayerDataService.update(player, function(data)
			data.settings.language = chosen
		end)
		if updated then
			NotifyService.success(player, "n.languageSet")
		else
			NotifyService.blocked(player, "n.loading")
		end
	end)

	task.spawn(function()
		while true do
			task.wait(GameConfig.AutosaveIntervalSeconds)
			for player, profile in profiles do
				if profile.dirty then
					task.spawn(saveProfile, player, profile, true)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player, profile in profiles do
			pending += 1
			task.spawn(function()
				saveProfile(player, profile, false)
				pending -= 1
			end)
		end
		local deadline = os.clock() + GameConfig.BindToCloseTimeoutSeconds
		while pending > 0 and os.clock() < deadline do
			task.wait(GameConfig.SavePollSeconds)
		end
		if pending > 0 then
			task.spawn(error, `[{SOURCE}] ปิดเซิร์ฟเวอร์ก่อนบันทึกครบ เหลือ {pending} คน`, 0)
		end
	end)
end

return PlayerDataService
