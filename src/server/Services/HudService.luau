--!strict
-- HudService: รับ HudAction จาก HUD ฝั่ง client เพื่อให้แจ้งเตือนผ่านระบบกลาง (NotifyService)
-- client ส่งได้แค่ชื่อ action 3 ค่า (whitelist ใน Config/Hud) ไม่มี argument อื่น
--   ShopClick   -> แจ้ง "เร็วๆ นี้" (ยังไม่มีร้านค้า)
--   LevelCheck  -> server คำนวณเลเวลจาก data.Reputation เอง เทียบกับเลเวลที่จำไว้ ต่างกันจึงแจ้งขึ้น/ลด (client เป็นแค่ตัวกระตุ้น)
--   LoadTimeout -> client รอข้อมูลนานเกินไป แจ้งผู้เล่น
-- HudService ไม่ส่ง CurrencyUpdate (เป็นหน้าที่ของ ServeService) และไม่เขียนข้อมูลผู้เล่น

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudConfig = require(ReplicatedStorage.Shared.Config.Hud)
local RateLimits = require(ReplicatedStorage.Shared.Config.RateLimits)
local HudRules = require(ReplicatedStorage.Shared.HudRules)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local NotifyService = require(script.Parent.NotifyService)

local LOG = "[HudService]"
local RATE_KEY_PREFIX = "Hud"
local RATE_KEY_SHOP = RATE_KEY_PREFIX .. HudConfig.Actions.ShopClick
local RATE_KEY_INVALID = "HudInvalid"

-- สร้าง remote ตอน require เพื่อให้ client หาเจอเสมอ ไม่ขึ้นกับลำดับ Start
local actionEvent = Remotes.GetEvent("HudAction")

local HudService = {}

local connections: { RBXScriptConnection } = {}
-- เลเวลที่แจ้งไปล่าสุดของผู้เล่นแต่ละคน (อยู่ในหน่วยความจำ ไม่บันทึก)
local lastLevel: { [Player]: number } = {}

-- ติดลิมิต: warn เสมอ แจ้งผู้เล่นเฉพาะ ShopClick (LevelCheck ครั้งถัดไปตามทันเอง ไม่ต้องแจ้ง)
local limiter = RateLimiter.new(RateLimits, function(player: Player, remoteName: string)
	warn(`{LOG} {player.Name} {remoteName} เกินลิมิต ปฏิเสธคำขอ`)
	if remoteName == RATE_KEY_SHOP then
		NotifyService.NotifyRateLimited(player)
	end
end)

local function reject(player: Player, reason: string)
	warn(`{LOG} {player.Name} HudAction ปฏิเสธ: {reason}`)
	if limiter:Check(player, RATE_KEY_INVALID) then
		NotifyService.Notify(player, "InvalidRequest", "error", nil)
	end
end

local function onShopClick(player: Player)
	NotifyService.Notify(player, "ComingSoon", "info", nil)
end

local function onLevelCheck(player: Player)
	local data = DataService.GetData(player)
	if data == nil then
		warn(`{LOG} {player.Name} LevelCheck: ข้อมูลผู้เล่นยังโหลดไม่เสร็จ ข้าม`)
		return
	end
	local level = HudRules.LevelFor(data.Reputation)
	local previous = lastLevel[player]
	lastLevel[player] = level
	if previous == nil or previous == level then
		return
	end
	local args: { [string]: string | number } = { level = level }
	if level > previous then
		NotifyService.Notify(player, "HudLevelUp", "success", args)
	else
		NotifyService.Notify(player, "HudLevelDown", "info", args)
	end
	print(`{LOG} {player.Name} เลเวล Reputation {previous} -> {level}`)
end

local function onLoadTimeout(player: Player)
	if DataService.GetData(player) == nil then
		warn(`{LOG} {player.Name} LoadTimeout: ข้อมูลผู้เล่นยังโหลดไม่เสร็จ`)
		NotifyService.Notify(player, "DataNotReady", "error", nil)
		return
	end
	warn(`{LOG} {player.Name} LoadTimeout: ข้อมูลพร้อมแล้วแต่ HUD ยังไม่ได้รับเหรียญ/Reputation`)
	NotifyService.Notify(player, "UnknownError", "error", nil)
end

local function onAction(player: Player, raw: unknown)
	if type(raw) ~= "string" then
		reject(player, `action ไม่ใช่ string ({typeof(raw)})`)
		return
	end
	local action = raw :: string
	if #action > HudConfig.MaxActionLength then
		reject(player, `action ยาวเกิน {HudConfig.MaxActionLength} ตัวอักษร`)
		return
	end
	if HudConfig.AllowedActions[action] ~= true then
		local shown = string.sub(action, 1, HudConfig.MaxLogActionLength)
		reject(player, `action "{shown}" ไม่อยู่ในรายการที่รับได้`)
		return
	end
	if not limiter:Check(player, RATE_KEY_PREFIX .. action) then
		return
	end
	if action == HudConfig.Actions.ShopClick then
		onShopClick(player)
	elseif action == HudConfig.Actions.LevelCheck then
		onLevelCheck(player)
	elseif action == HudConfig.Actions.LoadTimeout then
		onLoadTimeout(player)
	end
end

local function onPlayerRemoving(player: Player)
	lastLevel[player] = nil
	limiter:Remove(player)
end

function HudService.Start()
	table.insert(connections, actionEvent.OnServerEvent:Connect(onAction))
	table.insert(connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
end

return HudService
