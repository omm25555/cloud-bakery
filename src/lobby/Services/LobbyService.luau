--!strict
-- LobbyService: lobby ฝั่ง server จัดกลุ่มผู้เล่นที่แท่น (pad) นับถอยหลัง แล้ว teleport ทั้งกลุ่มไป reserved server ของเกาะ
-- server ตัดสินทุกอย่าง: ใครอยู่ในกลุ่ม เวลานับ และการ teleport client ไม่มี remote ส่งคำขอเลย (ใช้ ProximityPrompt ที่ server ฟังเอง)
-- lobby ไม่แตะ DataService / PlayerData (ใช้เฉพาะค่าภาษาเริ่มต้นจาก Config)

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local Lobby = require(ReplicatedStorage.Shared.Config.Lobby)
local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local Places = require(ReplicatedStorage.Shared.Config.Places)
local RateLimits = require(ReplicatedStorage.Shared.Config.RateLimits)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local LobbyRules = require(ReplicatedStorage.Shared.LobbyRules)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local NotifyService = require(script.Parent.NotifyService)

local LOG = "[LobbyService]"

type PadState = "Idle" | "Counting" | "Teleporting"

type Pad = {
	Index: number,
	State: PadState,
	Members: { Player },
	EndsAt: number,
	Generation: number,
	Label: TextLabel,
}

-- สร้าง remote ตอน require เพื่อให้ client หาเจอเสมอ ไม่ขึ้นกับลำดับ Start
local stateEvent = Remotes.GetEvent("LobbyState")
local readyEvent = Remotes.GetEvent("LobbyReady")

local LobbyService = {}

local pads: { Pad } = {}
local padOf: { [Player]: Pad } = {}
local readyPlayers: { [Player]: boolean } = {}

local limiter = RateLimiter.new(RateLimits, function(player: Player, _remoteName: string)
	NotifyService.NotifyRateLimited(player)
end)

local function notifyMembers(pad: Pad, key: string, kind: "info" | "success" | "error", args: { [string]: string | number }?)
	for _, member in pad.Members do
		NotifyService.Notify(member, key, kind, args)
	end
end

local function secondsLeft(pad: Pad): number
	return math.max(0, math.ceil(pad.EndsAt - os.clock()))
end

local function sendState(player: Player)
	if not readyPlayers[player] or player.Parent ~= Players then
		return
	end
	local pad = padOf[player]
	if pad == nil then
		stateEvent:FireClient(player, { InGroup = false })
		return
	end
	local names: { string } = {}
	for _, member in pad.Members do
		table.insert(names, member.Name)
	end
	stateEvent:FireClient(player, {
		InGroup = true,
		Members = names,
		MaxSize = Lobby.MaxGroupSize,
		SecondsLeft = if pad.State == "Counting" then secondsLeft(pad) else nil,
		Teleporting = pad.State == "Teleporting",
	})
end

local function refreshPad(pad: Pad)
	pad.Label.Text = `{#pad.Members}/{Lobby.MaxGroupSize}`
	for _, member in pad.Members do
		sendState(member)
	end
end

local function removeMember(pad: Pad, player: Player)
	local index = table.find(pad.Members, player)
	if index then
		table.remove(pad.Members, index)
	end
	if padOf[player] == pad then
		padOf[player] = nil
	end
end

-- เคลียร์กลุ่มทั้งหมดกลับเป็นว่าง (ใช้เมื่อ teleport ไม่สำเร็จ ผู้เล่นกดแท่นเพื่อลองใหม่เอง)
local function resetPad(pad: Pad)
	pad.Generation += 1
	pad.State = "Idle"
	local former = table.clone(pad.Members)
	for _, member in former do
		removeMember(pad, member)
		sendState(member)
	end
	refreshPad(pad)
end

local function failTeleport(pad: Pad, key: string, reason: string)
	if pad.State ~= "Teleporting" then
		return
	end
	warn(`{LOG} teleport กลุ่มที่แท่น {pad.Index} ไม่สำเร็จ: {reason}`)
	notifyMembers(pad, key, "error", nil)
	resetPad(pad)
end

local function teleportGroup(pad: Pad)
	pad.Generation += 1
	local generation = pad.Generation
	pad.State = "Teleporting"
	notifyMembers(pad, "LobbyTeleporting", "info", nil)
	refreshPad(pad)

	local placeId = Places.IslandPlaceId
	if not Places.IsSet(placeId) then
		-- ไม่ retry: Place ID เป็น 0 จนกว่าเจ้าของจะกรอก
		failTeleport(pad, "LobbyPlaceNotSet", "ยังไม่ได้ตั้ง IslandPlaceId ใน Config/Places ยกเลิกการ teleport")
		return
	end

	local travelers: { Player } = {}
	local userIds: { number } = {}
	for _, member in pad.Members do
		if member.Parent == Players then
			table.insert(travelers, member)
			table.insert(userIds, member.UserId)
		end
	end
	if #travelers == 0 then
		resetPad(pad)
		return
	end

	-- reserved server สร้างจาก GUID ที่เราสร้างเอง ทุกครั้งที่ retry ใช้ GUID เดิม
	local options = Instance.new("TeleportOptions")
	options.ReservedServerId = HttpService:GenerateGUID(false)
	options:SetTeleportData(LobbyRules.BuildTeleportData(HttpService:GenerateGUID(false), userIds))

	local attempts = 1 + Lobby.TeleportRetries
	local lastError = ""
	for attempt = 1, attempts do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(placeId, travelers, options)
		end)
		if ok then
			break
		end
		lastError = tostring(err)
		warn(`{LOG} TeleportAsync ล้มเหลว (ครั้งที่ {attempt}/{attempts}): {lastError}`)
		if attempt >= attempts then
			failTeleport(pad, "LobbyReserveFailed", `TeleportAsync error หลัง retry ครบ: {lastError}`)
			return
		end
		task.wait(Lobby.RetryDelaySeconds)
		if pad.Generation ~= generation or pad.State ~= "Teleporting" then
			return
		end
	end

	-- ถ้าหลังรอแล้วยังมีคนค้างในกลุ่ม แปลว่า teleport ไม่เกิด ปล่อยให้ลองใหม่ได้
	task.delay(Lobby.TeleportSettleSeconds, function()
		if pad.Generation == generation and pad.State == "Teleporting" then
			if #pad.Members == 0 then
				resetPad(pad)
			else
				failTeleport(pad, "LobbyTeleportFailed", "ผู้เล่นยังอยู่ใน lobby หลังรอ teleport")
			end
		end
	end)
end

local function startCountdown(pad: Pad, seconds: number)
	pad.Generation += 1
	local generation = pad.Generation
	pad.State = "Counting"
	pad.EndsAt = os.clock() + seconds
	local args: { [string]: string | number } = { seconds = seconds }
	notifyMembers(pad, "LobbyCountdownStarted", "info", args)

	task.spawn(function()
		while pad.State == "Counting" and pad.Generation == generation and secondsLeft(pad) > 0 do
			refreshPad(pad)
			task.wait(Lobby.TickSeconds)
		end
		if pad.State == "Counting" and pad.Generation == generation then
			teleportGroup(pad)
		end
	end)
end

local function cancelCountdown(pad: Pad)
	pad.Generation += 1
	pad.State = "Idle"
end

local function leaveGroup(pad: Pad, player: Player, voluntary: boolean)
	removeMember(pad, player)
	if voluntary then
		NotifyService.Notify(player, "LobbyLeftGroup", "info", nil)
	end
	sendState(player)

	if pad.State == "Counting" then
		if #pad.Members < Lobby.MinGroupSize then
			cancelCountdown(pad)
			notifyMembers(pad, "LobbyCountdownCancelled", "info", nil)
		else
			local args: { [string]: string | number } = { name = player.Name }
			notifyMembers(pad, "LobbyMemberLeft", "info", args)
		end
	end
	refreshPad(pad)
end

local function joinGroup(pad: Pad, player: Player)
	table.insert(pad.Members, player)
	padOf[player] = pad
	local joinedArgs: { [string]: string | number } = { count = #pad.Members, max = Lobby.MaxGroupSize }
	NotifyService.Notify(player, "LobbyJoinedGroup", "success", joinedArgs)

	if not Places.IsSet(Places.IslandPlaceId) then
		warn(`{LOG} {player.Name} เข้ากลุ่ม แต่ยังไม่ได้ตั้ง IslandPlaceId ใน Config/Places จะ teleport ไม่ได้`)
		NotifyService.Notify(player, "LobbyPlaceNotSet", "error", nil)
	end

	local full = #pad.Members >= Lobby.MaxGroupSize
	if pad.State == "Idle" and #pad.Members >= Lobby.MinGroupSize then
		startCountdown(pad, if full then Lobby.FullGroupCountdownSeconds else Lobby.CountdownSeconds)
	elseif pad.State == "Counting" and full and secondsLeft(pad) > Lobby.FullGroupCountdownSeconds then
		pad.EndsAt = os.clock() + Lobby.FullGroupCountdownSeconds
		local args: { [string]: string | number } = { seconds = Lobby.FullGroupCountdownSeconds }
		notifyMembers(pad, "LobbyCountdownStarted", "info", args)
	end
	refreshPad(pad)
end

local function onPadTriggered(pad: Pad, player: Player)
	if player.Parent ~= Players then
		return
	end
	if not limiter:Check(player, "LobbyPrompt") then
		return
	end

	local current = padOf[player]
	local decision = LobbyRules.DecideJoin(#pad.Members, current == pad, pad.State == "Teleporting")
	if decision == "Busy" then
		warn(`{LOG} {player.Name} กดแท่น {pad.Index} ขณะกลุ่มกำลัง teleport`)
		NotifyService.Notify(player, "LobbyTeleportBusy", "error", nil)
	elseif decision == "Full" then
		warn(`{LOG} {player.Name} เข้าแท่น {pad.Index} ไม่ได้ กลุ่มเต็ม`)
		local args: { [string]: string | number } = { max = Lobby.MaxGroupSize }
		NotifyService.Notify(player, "LobbyGroupFull", "error", args)
	elseif decision == "Leave" then
		leaveGroup(pad, player, true)
	else
		if current ~= nil then
			if current.State == "Teleporting" then
				warn(`{LOG} {player.Name} ย้ายแท่นไม่ได้ กลุ่มเดิมกำลัง teleport`)
				NotifyService.Notify(player, "LobbyTeleportBusy", "error", nil)
				return
			end
			leaveGroup(current, player, false)
		end
		joinGroup(pad, player)
	end
end

local function buildPad(folder: Folder, index: number): Pad
	local offset = (index - (Lobby.PadCount + 1) / 2) * Lobby.PadSpacing
	local part = Instance.new("Part")
	part.Name = `Pad{index}`
	part.Anchored = true
	part.Size = Lobby.PadSize
	part.Position = Lobby.PadBasePosition + Vector3.new(offset, 0, 0)
	part.Color = Lobby.PadColor
	part.Parent = folder

	local billboard = Instance.new("BillboardGui")
	billboard.Size = Lobby.PadLabelSize
	billboard.StudsOffset = Lobby.PadLabelOffset
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextSize = Lobby.PadLabelTextSize
	label.TextColor3 = Lobby.PadLabelTextColor
	label.Font = Lobby.UiFont
	label.Text = `0/{Lobby.MaxGroupSize}`
	label.Parent = billboard

	local language = PlayerDataConfig.DefaultLanguage
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = Strings.Format("UiLobbyPadAction", language, nil)
	prompt.ObjectText = Strings.Format("UiLobbyPadObject", language, nil)
	prompt.HoldDuration = Lobby.PromptHoldSeconds
	prompt.MaxActivationDistance = Lobby.PromptMaxDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	local pad: Pad = {
		Index = index,
		State = "Idle",
		Members = {},
		EndsAt = 0,
		Generation = 0,
		Label = label,
	}
	prompt.Triggered:Connect(function(player: Player)
		onPadTriggered(pad, player)
	end)
	return pad
end

local function buildWorld()
	local folder = Instance.new("Folder")
	folder.Name = "LobbyWorld"
	folder.Parent = Workspace

	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = Lobby.FloorSize
	floor.Position = Lobby.FloorPosition
	floor.Color = Lobby.FloorColor
	floor.Parent = folder

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = Lobby.SpawnSize
	spawn.Position = Lobby.SpawnPosition
	spawn.Parent = folder

	for index = 1, Lobby.PadCount do
		table.insert(pads, buildPad(folder, index))
	end
end

local function onPlayerRemoving(player: Player)
	local pad = padOf[player]
	readyPlayers[player] = nil
	limiter:Remove(player)
	if pad then
		leaveGroup(pad, player, false)
	end
end

-- client บอกว่าพร้อมรับ state แล้ว (ไม่รับ argument ใด ๆ จาก client)
local function onClientReady(player: Player)
	if not limiter:Check(player, "LobbyReady") then
		return
	end
	readyPlayers[player] = true
	sendState(player)
end

local function onTeleportInitFailed(player: Player, result: Enum.TeleportResult, message: string)
	local pad = padOf[player]
	if pad == nil or pad.State ~= "Teleporting" then
		return
	end
	warn(`{LOG} TeleportInitFailed ของ {player.Name}: {result.Name} {message}`)
	NotifyService.Notify(player, "LobbyTeleportFailed", "error", nil)
	removeMember(pad, player)
	sendState(player)
	if #pad.Members == 0 then
		resetPad(pad)
	else
		refreshPad(pad)
	end
end

function LobbyService.Start()
	buildWorld()
	readyEvent.OnServerEvent:Connect(onClientReady)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	TeleportService.TeleportInitFailed:Connect(onTeleportInitFailed)
	if not Places.IsSet(Places.IslandPlaceId) then
		warn(`{LOG} ยังไม่ได้ตั้ง IslandPlaceId ใน Config/Places ผู้เล่นจะ teleport ไม่ได้จนกว่าเจ้าของจะกรอก`)
	end
end

return LobbyService
