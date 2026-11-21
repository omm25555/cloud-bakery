--!strict
-- ระบบแจ้งเตือนกลาง: ทุก Service ส่งข้อความหาผู้เล่นผ่านที่นี่ที่เดียว
-- ส่งเป็น key ของ Locale เพื่อให้ client แสดงตามภาษาที่ผู้เล่นเลือก

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local NotifyService = {}

local notifyEvent = Remotes.GetEvent("Notify")

type Args = { [string]: string | number }

local function send(player: Player, kind: Types.NotifyKind, key: string, args: Args?)
	local payload: Types.NotifyPayload = { kind = kind, key = key, args = args }
	notifyEvent:FireClient(player, payload)
end

function NotifyService.success(player: Player, key: string, args: Args?)
	send(player, "success", key, args)
end

function NotifyService.info(player: Player, key: string, args: Args?)
	send(player, "info", key, args)
end

-- เงื่อนไขไม่ครบ: บอกผู้เล่นว่าต้องทำอะไร (ไม่ใช่ข้อผิดพลาดของระบบ ไม่ต้อง warn)
function NotifyService.blocked(player: Player, key: string, args: Args?)
	send(player, "warn", key, args)
end

-- server ปฏิเสธคำขอ: แจ้งผู้เล่นแบบสุภาพ + warn ให้ dev เห็นว่าใครและเพราะอะไร
function NotifyService.rejected(source: string, player: Player, reason: string, key: string?, args: Args?)
	warn(`[{source}] ปฏิเสธคำขอของ {player.Name} ({player.UserId}): {reason}`)
	send(player, "warn", key or "n.rejected", args)
end

-- ข้อผิดพลาดไม่คาดคิด: ข้อความกลาง ๆ ให้ผู้เล่น + error log (ไม่หยุด thread ของผู้เรียก)
function NotifyService.unexpected(source: string, player: Player?, detail: string)
	local who = if player then ` ผู้เล่น {player.Name} ({player.UserId})` else ""
	task.spawn(error, `[{source}] ข้อผิดพลาดไม่คาดคิด{who}: {detail}`, 0)
	if player and player.Parent == Players then
		send(player, "error", "n.unexpected")
	end
end

function NotifyService.raw(player: Player, kind: Types.NotifyKind, key: string, args: Args?)
	send(player, kind, key, args)
end

function NotifyService.all(kind: Types.NotifyKind, key: string, args: Args?, except: Player?)
	for _, player in Players:GetPlayers() do
		if player ~= except then
			send(player, kind, key, args)
		end
	end
end

return NotifyService
