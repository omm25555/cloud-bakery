--!strict
-- NotifyService: ระบบแจ้งเตือนกลางฝั่ง server
-- Service อื่นเรียก NotifyService.Notify(player, key, kind, args?) เท่านั้น
-- ข้อความจริงอยู่ใน Config/Strings client แปลงเองตามภาษาที่ server ส่งไปให้

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NotifyConfig = require(ReplicatedStorage.Shared.Config.Notify)
local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local RateLimits = require(ReplicatedStorage.Shared.Config.RateLimits)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

type Payload = NotifyConfig.Payload

-- สร้าง remote ตอน require เพื่อให้ client หาเจอเสมอ ไม่ขึ้นกับลำดับ Start
local notifyEvent = Remotes.GetEvent("Notify")
local readyEvent = Remotes.GetEvent("NotifyReady")

local NotifyService = {}

local readyPlayers: { [Player]: boolean } = {}
local pending: { [Player]: { Payload } } = {}
local lastRateNotice: { [Player]: number } = {}
local languageProvider: (Player) -> string = function(_player: Player): string
	return PlayerDataConfig.DefaultLanguage
end

local limiter = RateLimiter.new(RateLimits)

-- DataService ตั้งให้ เพื่อให้ NotifyService ไม่ต้อง require DataService (กันพึ่งกันเป็นวง)
function NotifyService.SetLanguageProvider(provider: (Player) -> string)
	languageProvider = provider
end

local function sanitizeArgs(player: Player, key: string, args: { [string]: string | number }?): { [string]: string | number }?
	if args == nil then
		return nil
	end
	if type(args) ~= "table" then
		warn(`[NotifyService] args ของ {key} (ผู้เล่น {player.Name}) ไม่ใช่ table ข้าม args`)
		return nil
	end
	local clean: { [string]: string | number } = {}
	local count = 0
	for name, value in args do
		local valueType = type(value)
		local valid = type(name) == "string" and string.match(name, "^%w+$") ~= nil
		if valid and valueType == "string" then
			valid = #(value :: string) <= NotifyConfig.MaxArgLength
		elseif valid and valueType == "number" then
			local number = value :: number
			valid = number == number and math.abs(number) ~= math.huge
		else
			valid = false
		end
		if valid and count < NotifyConfig.MaxArgCount then
			clean[name] = value
			count += 1
		else
			warn(`[NotifyService] args ของ {key} (ผู้เล่น {player.Name}) ไม่ผ่านการตรวจ ข้ามค่า {tostring(name)}`)
		end
	end
	return clean
end

local function deliver(player: Player, payload: Payload)
	if readyPlayers[player] then
		notifyEvent:FireClient(player, payload)
		return
	end
	-- client ยังไม่พร้อมรับ เก็บไว้ก่อน (จำกัดจำนวน ทิ้งอันเก่าสุดก่อน)
	local queue = pending[player]
	if queue == nil then
		queue = {}
		pending[player] = queue
	end
	table.insert(queue, payload)
	while #queue > NotifyConfig.MaxPendingPerPlayer do
		table.remove(queue, 1)
	end
end

function NotifyService.Notify(player: Player, key: string, kind: string, args: { [string]: string | number }?)
	if player.Parent ~= Players then
		return
	end
	local safeKey = key
	local safeKind = kind
	if type(key) ~= "string" or not Strings.Has(key) then
		warn(`[NotifyService] ไม่พบ key ข้อความ "{tostring(key)}" (ผู้เล่น {player.Name}) ใช้ข้อความกลางแทน`)
		safeKey = "UnknownError"
		safeKind = "error"
	end
	if not NotifyConfig.Kinds[safeKind] then
		warn(`[NotifyService] kind "{tostring(kind)}" ไม่ถูกต้อง (ผู้เล่น {player.Name}) ใช้ info แทน`)
		safeKind = "info"
	end
	deliver(player, {
		Key = safeKey,
		Kind = safeKind,
		Language = languageProvider(player),
		Args = sanitizeArgs(player, safeKey, args),
	})
end

-- ใช้เป็น onLimited ของ RateLimiter ใน Service อื่น (มี cooldown ไม่ให้ toast ท่วมจอ)
function NotifyService.NotifyRateLimited(player: Player)
	local now = os.clock()
	local last = lastRateNotice[player]
	if last ~= nil and now - last < RateLimits.NotifyCooldownSeconds then
		return
	end
	lastRateNotice[player] = now
	NotifyService.Notify(player, "RateLimited", "error")
end

local function onPlayerRemoving(player: Player)
	readyPlayers[player] = nil
	pending[player] = nil
	lastRateNotice[player] = nil
end

-- client บอกว่าพร้อมรับ toast แล้ว (ไม่รับ argument ใด ๆ จาก client)
local function onClientReady(player: Player)
	if not limiter:Check(player, "NotifyReady") then
		return
	end
	if readyPlayers[player] then
		return
	end
	readyPlayers[player] = true
	local queue = pending[player]
	pending[player] = nil
	if queue then
		for _, payload in queue do
			notifyEvent:FireClient(player, payload)
		end
	end
end

function NotifyService.Start()
	readyEvent.OnServerEvent:Connect(onClientReady)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return NotifyService
