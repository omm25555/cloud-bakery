--!strict
-- UpgradeService: อัปเกรดร้าน 3 สาย (ผลเป็นของผู้เล่นแต่ละคน)
-- server ตัดสินทุกอย่าง: ราคา การหักเหรียญ เลเวล และผลอัปเกรด
-- client ส่งได้แค่ "อัปเกรดสายไหน" (id ของสาย) / "ขอ snapshot"
-- เลเวลเก็บใน PlayerData.Upgrades (เซฟผ่าน DataService เดิม)
-- ระบบอื่นอ่านผลด้วย UpgradeService.GetLevel / GetMultiplier (ไม่มีข้อมูล = เลเวล 0 / ตัวคูณ 1)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local RateLimits = require(ReplicatedStorage.Shared.Config.RateLimits)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UpgradeRules = require(ReplicatedStorage.Shared.UpgradeRules)
local DataService = require(script.Parent.DataService)
local NotifyService = require(script.Parent.NotifyService)

local LOG = "[UpgradeService]"

type PlayerData = PlayerDataConfig.PlayerData

-- สร้าง remote ตอน require เพื่อให้ client หาเจอเสมอ ไม่ขึ้นกับลำดับ Start
local buyEvent = Remotes.GetEvent("UpgradeBuy")
local syncEvent = Remotes.GetEvent("UpgradeSync")
local stateEvent = Remotes.GetEvent("UpgradeState")
local currencyEvent = Remotes.GetEvent("CurrencyUpdate")

local UpgradeService = {}

-- id ของสายอัปเกรด ให้ระบบอื่นใช้อ้างอิง (กันพิมพ์ผิด)
UpgradeService.Ids = Upgrades.Ids

local limiter = RateLimiter.new(RateLimits, function(player: Player, _remoteName: string)
	NotifyService.NotifyRateLimited(player)
end)

local connections: { RBXScriptConnection } = {}
local warnedUnknown: { [Player]: boolean } = {}

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

local function levelOf(data: PlayerData, line: Upgrades.Line): number
	return UpgradeRules.SanitizeLevel(data.Upgrades[line.Id], line)
end

local function buildLevels(data: PlayerData): { [string]: number }
	local levels: { [string]: number } = {}
	for _, id in Upgrades.Order do
		local line = Upgrades.Lines[id]
		if line then
			levels[id] = levelOf(data, line)
		end
	end
	return levels
end

local function sendState(player: Player, data: PlayerData)
	stateEvent:FireClient(player, { Levels = buildLevels(data), Language = data.Settings.Language })
end

local function sendCurrency(player: Player, data: PlayerData)
	currencyEvent:FireClient(player, { Coins = data.Coins, Reputation = data.Reputation })
end

-- แก้ค่าเลเวลที่เสีย/เกินเพดานในหน่วยความจำ และ warn id ที่ไม่รู้จักครั้งเดียว (ไม่ลบ id นั้นทิ้ง)
local function sanitizeData(player: Player, data: PlayerData)
	for _, id in Upgrades.Order do
		local line = Upgrades.Lines[id]
		local raw = data.Upgrades[id]
		if line ~= nil and raw ~= nil then
			local clean = UpgradeRules.SanitizeLevel(raw, line)
			if clean ~= raw then
				warn(`{LOG} {player.Name} เลเวล {id} ในข้อมูลเซฟผิดปกติ ({tostring(raw)}) แก้เป็น {clean}`)
				data.Upgrades[id] = clean
			end
		end
	end
	if warnedUnknown[player] then
		return
	end
	for id in data.Upgrades do
		if Upgrades.Lines[id] == nil then
			warnedUnknown[player] = true
			warn(`{LOG} {player.Name} มี id อัปเกรดที่ไม่รู้จักในข้อมูลเซฟ ({id}) เก็บไว้ไม่ใช้งาน`)
		end
	end
end

function UpgradeService.GetLevel(player: Player, id: string): number
	local line = Upgrades.Lines[id]
	local data = DataService.GetData(player)
	if line == nil or data == nil then
		return 0
	end
	return levelOf(data, line)
end

function UpgradeService.GetMultiplier(player: Player, id: string): number
	local line = Upgrades.Lines[id]
	local data = DataService.GetData(player)
	if line == nil or data == nil then
		return 1
	end
	return UpgradeRules.Multiplier(line, levelOf(data, line))
end

local function onBuy(player: Player, lineIdRaw: unknown)
	if not limiter:Check(player, "UpgradeBuy") then
		return
	end
	if type(lineIdRaw) ~= "string" then
		reject(player, "UpgradeBuy", `lineId ไม่ใช่ string ({typeof(lineIdRaw)})`, "InvalidRequest", nil)
		return
	end
	local lineId = lineIdRaw :: string
	local line = Upgrades.Lines[lineId]
	if line == nil then
		local shown = string.sub(lineId, 1, Upgrades.MaxLogIdLength)
		reject(player, "UpgradeBuy", `ไม่มีสายอัปเกรด "{shown}" ใน Config`, "InvalidRequest", nil)
		return
	end
	local data = DataService.GetData(player)
	if data == nil then
		reject(player, "UpgradeBuy", "ข้อมูลผู้เล่นยังโหลดไม่เสร็จ", "DataNotReady", nil)
		return
	end

	-- จากตรงนี้ถึงเขียนข้อมูลไม่มี yield: กดรัวซื้อซ้ำไม่ได้ และเหรียญไม่ติดลบ
	local level = levelOf(data, line)
	local cost = UpgradeRules.Cost(line, level + 1)
	if cost == nil then
		reject(player, "UpgradeBuy", `{lineId} เลเวลเต็มแล้ว ({level}/{UpgradeRules.MaxLevel(line)})`, "UpgradeMaxed", nil)
		return
	end
	if data.Coins < cost then
		local args: { [string]: string | number } = { missing = cost - data.Coins, cost = cost }
		reject(player, "UpgradeBuy", `เหรียญไม่พอสำหรับ {lineId}: {data.Coins}/{cost}`, "UpgradeShort", args)
		return
	end
	data.Coins -= cost
	data.Upgrades[lineId] = level + 1
	local newLevel = level + 1

	sendState(player, data)
	sendCurrency(player, data)
	local language = data.Settings.Language
	local okArgs: { [string]: string | number } = {
		line = UpgradeRules.Name(line, language),
		level = newLevel,
		max = UpgradeRules.MaxLevel(line),
		effect = UpgradeRules.EffectText(line, newLevel, language),
		coins = data.Coins,
	}
	NotifyService.Notify(player, "UpgradeBuyOk", "success", okArgs)
	print(`{LOG} {player.Name} ซื้อ {lineId} เป็นเลเวล {newLevel} ราคา {cost} เหลือ {data.Coins} เหรียญ`)
end

-- ขอ snapshot ตอนเข้าเกม: รอข้อมูลโหลดก่อนส่งเลเวลและเหรียญ
local function onSync(player: Player)
	if not limiter:Check(player, "UpgradeSync") then
		return
	end
	task.spawn(function()
		local waited = 0
		local data = DataService.GetData(player)
		while data == nil and waited < Upgrades.SyncWaitSeconds and player.Parent == Players do
			task.wait(Upgrades.SyncPollSeconds)
			waited += Upgrades.SyncPollSeconds
			data = DataService.GetData(player)
		end
		if data == nil then
			if player.Parent == Players then
				warn(`{LOG} {player.Name} UpgradeSync หมดเวลารอข้อมูลผู้เล่น`)
				NotifyService.Notify(player, "DataNotReady", "error")
			end
			return
		end
		sendState(player, data)
		sendCurrency(player, data)
	end)
end

local function onLoaded(player: Player)
	local data = DataService.GetData(player)
	if data then
		sanitizeData(player, data)
	end
end

local function onPlayerRemoving(player: Player)
	warnedUnknown[player] = nil
	limiter:Remove(player)
end

function UpgradeService.Start()
	table.insert(connections, buyEvent.OnServerEvent:Connect(onBuy))
	table.insert(connections, syncEvent.OnServerEvent:Connect(onSync))
	table.insert(connections, DataService.Loaded:Connect(onLoaded))
	table.insert(connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
	for _, player in Players:GetPlayers() do
		onLoaded(player)
	end
end

return UpgradeService
