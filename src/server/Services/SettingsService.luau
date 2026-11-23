--!strict
-- SettingsService: เปลี่ยนภาษา (th/en) และรับคลิกปุ่มล็อก Pets/Decor
-- client ส่งได้แค่ "ภาษาที่เลือก" / "id ปุ่มที่ล็อก" server ตรวจชนิด ค่า สิทธิ์ และ rate limit ทุกครั้ง
-- ภาษาเก็บใน PlayerData.Settings.Language (เซฟผ่าน DataService เดิม)
-- หลังเปลี่ยนสำเร็จ ยิง remote เดิมของระบบอื่นซ้ำด้วยรูปแบบเดิมเป๊ะ เพื่อให้ UI เดิมเปลี่ยนภาษาทันที:
--   InventoryUpdate { Inventory, Language }  (เทียบ FarmService.sendInventory)
--   UpgradeState { Levels, Language }        (เทียบ UpgradeService.sendState / buildLevels)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MenuConfig = require(ReplicatedStorage.Shared.Config.Menu)
local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local RateLimits = require(ReplicatedStorage.Shared.Config.RateLimits)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UpgradeRules = require(ReplicatedStorage.Shared.UpgradeRules)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local NotifyService = require(script.Parent.NotifyService)

local LOG = "[SettingsService]"

type PlayerData = PlayerDataConfig.PlayerData
type Language = PlayerDataConfig.Language

-- สร้าง remote ตอน require เพื่อให้ client หาเจอเสมอ ไม่ขึ้นกับลำดับ Start
local languageEvent = Remotes.GetEvent("SettingsSetLanguage")
local settingsStateEvent = Remotes.GetEvent("SettingsState")
local lockedEvent = Remotes.GetEvent("MenuLockedClick")
local upgradeStateEvent = Remotes.GetEvent("UpgradeState")

local SettingsService = {}

local limiter = RateLimiter.new(RateLimits, function(player: Player, _remoteName: string)
	NotifyService.NotifyRateLimited(player)
end)

local connections: { RBXScriptConnection } = {}

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

local function toLanguage(value: string): Language?
	if value == "th" then
		return "th"
	elseif value == "en" then
		return "en"
	end
	return nil
end

-- สร้างเลเวลอัปเกรดจากข้อมูลที่ server ถือ (รูปแบบเดียวกับ UpgradeService.buildLevels)
local function buildLevels(data: PlayerData): { [string]: number }
	local levels: { [string]: number } = {}
	for _, id in Upgrades.Order do
		local line = Upgrades.Lines[id]
		if line then
			levels[id] = UpgradeRules.SanitizeLevel(data.Upgrades[id], line)
		end
	end
	return levels
end

local function onSetLanguage(player: Player, raw: unknown)
	if not limiter:Check(player, "SettingsSetLanguage") then
		return
	end
	if type(raw) ~= "string" then
		reject(player, "SettingsSetLanguage", `ภาษาไม่ใช่ string ({typeof(raw)})`, "InvalidRequest", nil)
		return
	end
	local language = toLanguage(raw :: string)
	if language == nil then
		local shown = string.sub(raw :: string, 1, MenuConfig.MaxLogIdLength)
		reject(player, "SettingsSetLanguage", `ภาษา "{shown}" ไม่อยู่ในรายการที่รองรับ`, "InvalidRequest", nil)
		return
	end
	local data = DataService.GetData(player)
	if data == nil then
		reject(player, "SettingsSetLanguage", "ข้อมูลผู้เล่นยังโหลดไม่เสร็จ", "DataNotReady", nil)
		return
	end

	local name = MenuConfig.LanguageNames[language] or language
	if data.Settings.Language == language then
		local sameArgs: { [string]: string | number } = { language = name }
		NotifyService.Notify(player, "LanguageSame", "info", sameArgs)
		settingsStateEvent:FireClient(player, { Language = language })
		return
	end

	-- จากตรงนี้ถึงเขียนข้อมูลไม่มี yield
	local chosen: Language = if language == "en" then "en" else "th"
	data.Settings.Language = chosen
	settingsStateEvent:FireClient(player, { Language = language })
	InventoryService.Send(player, data)
	upgradeStateEvent:FireClient(player, { Levels = buildLevels(data), Language = language })

	local okArgs: { [string]: string | number } = { language = name }
	NotifyService.Notify(player, "LanguageChanged", "success", okArgs)
	print(`{LOG} {player.Name} เปลี่ยนภาษาเป็น {language}`)
end

local function onLockedClick(player: Player, raw: unknown)
	if not limiter:Check(player, "MenuLockedClick") then
		return
	end
	if type(raw) ~= "string" then
		reject(player, "MenuLockedClick", `id ไม่ใช่ string ({typeof(raw)})`, "InvalidRequest", nil)
		return
	end
	local id = raw :: string
	if MenuConfig.LockedIds[id] ~= true then
		local shown = string.sub(id, 1, MenuConfig.MaxLogIdLength)
		reject(player, "MenuLockedClick", `id "{shown}" ไม่อยู่ในรายการปุ่มล็อก`, "InvalidRequest", nil)
		return
	end
	NotifyService.Notify(player, "ComingSoon", "info", nil)
end

local function onPlayerRemoving(player: Player)
	limiter:Remove(player)
end

function SettingsService.Start()
	table.insert(connections, languageEvent.OnServerEvent:Connect(onSetLanguage))
	table.insert(connections, lockedEvent.OnServerEvent:Connect(onLockedClick))
	table.insert(connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
end

return SettingsService
