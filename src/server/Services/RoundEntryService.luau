--!strict
-- RoundEntryService: ระบุว่าเกาะถูกเปิดแบบไหน
--   Local    = เปิดตรงใน Studio เริ่มเล่นได้เลย (ไม่ต้อง teleport)
--   Reserved = มาจาก reserved server ที่ lobby สร้าง ตรวจ TeleportData เป็นข้อมูลประกอบเท่านั้น (ไม่ใช้ตัดสินสิทธิ์)
--   Direct   = เปิดตรงใน production ไม่ผ่าน lobby: ถ้าตั้ง LobbyPlaceId แล้วพากลับ lobby ถ้ายังไม่ตั้งให้เล่นต่อพร้อมแจ้งเตือน
-- Service นี้ไม่เปลี่ยนพฤติกรรมลูปเบเกอรี่ Service อื่นอ่านโหมดผ่าน GetEntryMode() เท่านั้น

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Places = require(ReplicatedStorage.Shared.Config.Places)
local LobbyRules = require(ReplicatedStorage.Shared.LobbyRules)
local NotifyService = require(script.Parent.NotifyService)

local LOG = "[RoundEntryService]"

export type EntryMode = "Local" | "Reserved" | "Direct"

local function detectMode(): EntryMode
	if RunService:IsStudio() then
		return "Local"
	end
	if game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then
		return "Reserved"
	end
	return "Direct"
end

local mode: EntryMode = detectMode()
local entries: { [Player]: LobbyRules.TeleportData } = {}
local warnedPlaceNotSet = false

local RoundEntryService = {}

function RoundEntryService.GetEntryMode(): EntryMode
	return mode
end

-- ข้อมูลกลุ่มที่ผ่านการตรวจแล้วของผู้เล่น (nil ถ้าไม่ใช่ Reserved หรือข้อมูลไม่ผ่าน)
function RoundEntryService.GetEntry(player: Player): LobbyRules.TeleportData?
	return entries[player]
end

local function returnToLobby(player: Player)
	local lobbyId = Places.LobbyPlaceId
	if not Places.IsSet(lobbyId) then
		if not warnedPlaceNotSet then
			warnedPlaceNotSet = true
			warn(`{LOG} เกาะถูกเปิดตรงแต่ยังไม่ได้ตั้ง LobbyPlaceId ใน Config/Places ให้เล่นต่อโดยไม่ teleport`)
		end
		NotifyService.Notify(player, "LobbyPlaceNotSet", "error", nil)
		return
	end
	if lobbyId == game.PlaceId then
		return
	end
	warn(`{LOG} {player.Name} เปิดเกาะตรงโดยไม่ผ่าน lobby พากลับ lobby`)
	NotifyService.Notify(player, "IslandDirectEntry", "info", nil)
	task.spawn(function()
		local ok, err = pcall(function()
			TeleportService:Teleport(lobbyId, player)
		end)
		if not ok then
			warn(`{LOG} พา {player.Name} กลับ lobby ไม่สำเร็จ: {tostring(err)}`)
			NotifyService.Notify(player, "LobbyTeleportFailed", "error", nil)
		end
	end)
end

local function onPlayerAdded(player: Player)
	if mode == "Local" then
		return
	end
	if mode == "Direct" then
		returnToLobby(player)
		return
	end

	local joinData = player:GetJoinData()
	local data, reason = LobbyRules.ValidateTeleportData(joinData.TeleportData, player.UserId)
	if data == nil then
		warn(`{LOG} TeleportData ของ {player.Name} ไม่ผ่านการตรวจ: {tostring(reason)} (ให้เล่นต่อ)`)
		NotifyService.Notify(player, "IslandBadEntry", "error", nil)
		return
	end
	entries[player] = data
end

function RoundEntryService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		entries[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return RoundEntryService
