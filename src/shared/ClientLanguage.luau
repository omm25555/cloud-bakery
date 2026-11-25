--!strict
-- ClientLanguage (ใช้ฝั่ง client เท่านั้น): ติดตามภาษาผู้เล่นจาก payload ที่ server ส่งมาอยู่แล้ว (ServeState/InventoryUpdate/SettingsState)
-- แบบเดียวกับ DayNightController เพื่อให้ controller ใหม่ไม่ต้องมี remote เพิ่ม

local Remotes = require(script.Parent.Remotes)
local PlayerDataConfig = require(script.Parent.Config.PlayerData)

local SOURCES = { "ServeState", "InventoryUpdate", "SettingsState" }

local ClientLanguage = {}

local language: string = PlayerDataConfig.DefaultLanguage
local listeners: { (language: string) -> () } = {}
local connected = false

local function onPayload(payload: unknown)
	if type(payload) ~= "table" then
		return
	end
	local value = (payload :: { [string]: unknown }).Language
	if (value == "th" or value == "en") and value ~= language then
		language = value :: string
		for _, listener in listeners do
			listener(language)
		end
	end
end

local function ensureConnected()
	if connected then
		return
	end
	connected = true
	for _, name in SOURCES do
		Remotes.GetEvent(name).OnClientEvent:Connect(onPayload)
	end
end

function ClientLanguage.Get(): string
	ensureConnected()
	return language
end

-- เรียก callback ทุกครั้งที่ภาษาเปลี่ยน
function ClientLanguage.OnChanged(callback: (language: string) -> ())
	ensureConnected()
	table.insert(listeners, callback)
end

return ClientLanguage
