--!strict
-- InventoryService: ตอบคำขอ snapshot กระเป๋าให้แผง Bag/Recipes
-- client ส่งได้แค่ "ขอ snapshot" (ไม่มี argument) ข้อมูลมาจาก server เท่านั้น
-- ตอบด้วย InventoryUpdate รูปแบบเดิม { Inventory, Language } ให้ผู้เล่นคนนั้นคนเดียว
-- (รูปแบบเดียวกับ FarmService.sendInventory) ระบบที่เปลี่ยนกระเป๋าต้องยิง InventoryUpdate เองเหมือนเดิม

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MenuConfig = require(ReplicatedStorage.Shared.Config.Menu)
local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local RateLimits = require(ReplicatedStorage.Shared.Config.RateLimits)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local NotifyService = require(script.Parent.NotifyService)

local LOG = "[InventoryService]"

type PlayerData = PlayerDataConfig.PlayerData

-- สร้าง remote ตอน require เพื่อให้ client หาเจอเสมอ ไม่ขึ้นกับลำดับ Start
local syncEvent = Remotes.GetEvent("InventorySync")
local inventoryEvent = Remotes.GetEvent("InventoryUpdate")

local InventoryService = {}

local limiter = RateLimiter.new(RateLimits, function(player: Player, _remoteName: string)
	NotifyService.NotifyRateLimited(player)
end)

local connections: { RBXScriptConnection } = {}

local function sendInventory(player: Player, data: PlayerData)
	local copy: { [string]: number } = {}
	for id, count in data.Inventory do
		copy[id] = count
	end
	inventoryEvent:FireClient(player, { Inventory = copy, Language = data.Settings.Language })
end

-- ใช้ซ้ำโดย SettingsService ตอนเปลี่ยนภาษา
function InventoryService.Send(player: Player, data: PlayerData)
	sendInventory(player, data)
end

local function onSync(player: Player)
	if not limiter:Check(player, "InventorySync") then
		return
	end
	task.spawn(function()
		local waited = 0
		local data = DataService.GetData(player)
		while data == nil and waited < MenuConfig.SyncWaitSeconds and player.Parent == Players do
			task.wait(MenuConfig.SyncPollSeconds)
			waited += MenuConfig.SyncPollSeconds
			data = DataService.GetData(player)
		end
		if data == nil then
			if player.Parent == Players then
				warn(`{LOG} {player.Name} InventorySync หมดเวลารอข้อมูลผู้เล่น`)
				NotifyService.Notify(player, "DataNotReady", "error", nil)
			end
			return
		end
		if player.Parent ~= Players then
			return
		end
		sendInventory(player, data)
	end)
end

function InventoryService.Start()
	table.insert(connections, syncEvent.OnServerEvent:Connect(onSync))
end

return InventoryService
