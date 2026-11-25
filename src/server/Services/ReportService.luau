--!strict
-- ReportService: ผู้จัดการร้าน (NPC) + รับ/ตรวจ/ตัดสินรายงานสิ่งผิดปกติจากผู้เล่น (server เป็นผู้ตัดสินทั้งหมด)
-- ผู้เล่นต้องเดินไปหา NPC เอง: ProximityPrompt (server รับ Triggered) -> server เปิด "เมนูรายงาน" ให้ผู้เล่นคนนั้น (เก็บ session ที่ server)
-- ReportSubmit(category, customerId?) ตรวจตามลำดับ: rate limit, ชนิด/ค่า, session เมนู, ระยะ, ช่วงคืน, cooldown, ข้อมูลผู้เล่น
-- ถูก: ResolveAnomaly + เหรียญ (เฉพาะผู้รายงาน) + ตัวนับสูตรต่อรอบ + MarkCustomerHandled(Reported) ของลูกค้า anomaly
-- ผิด: ผู้รายงานเสียสติ + ผู้จัดการตอบแบบหลอนขึ้นตามจำนวนครั้งที่ผิดของคืนนั้น (ไม่ทำร้ายใคร)
-- ตัวเลข: Config/Report, Config/Sanity บท: Config/ManagerLines ข้อความผู้เล่น: Config/Strings
-- API: GetRecipeProgress, GetWrongCount, OnReported(player, category, correct, anomalyId?)
-- ท่าทางผู้จัดการ: server ตั้ง attributes บนโมเดล client (ManagerController) เล่นท่าจากนั้น

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CustomersConfig = require(ReplicatedStorage.Shared.Config.Customers)
local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local RateLimits = require(ReplicatedStorage.Shared.Config.RateLimits)
local Report = require(ReplicatedStorage.Shared.Config.Report)
local Sanity = require(ReplicatedStorage.Shared.Config.Sanity)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ReportRules = require(ReplicatedStorage.Shared.ReportRules)
local AnomalyService = require(script.Parent.AnomalyService)
local DataService = require(script.Parent.DataService)
local DayNightService = require(script.Parent.DayNightService)
local NotifyService = require(script.Parent.NotifyService)
local SanityService = require(script.Parent.SanityService)
local ServeService = require(script.Parent.ServeService)

local LOG = "[ReportService]"

type Session = {
	ExpiresAt: number, -- เวลา server
	Customers: { [string]: boolean }, -- customerId ที่ server ส่งให้เมนูของผู้เล่นคนนี้
}

type CustomerEntry = { Id: string, Name: string }

-- สร้าง remote ตอน require เพื่อให้ client หาเจอเสมอ ไม่ขึ้นกับลำดับ Start
local submitEvent = Remotes.GetEvent("ReportSubmit")
local menuEvent = Remotes.GetEvent("ReportMenu")
local resultEvent = Remotes.GetEvent("ReportResult")
local currencyEvent = Remotes.GetEvent("CurrencyUpdate")

local reportedEvent = Instance.new("BindableEvent")

local ReportService = {}

function ReportService.OnReported(callback: (player: Player, category: string, correct: boolean, anomalyId: string?) -> ()): RBXScriptConnection
	return reportedEvent.Event:Connect(callback)
end

local random = Random.new()
local sessions: { [Player]: Session } = {}
local lastReportAt: { [Player]: number } = {}
local wrongCounts: { [Player]: number } = {}
local recipeProgress = 0
local reactionSeq = 0
local managerModel: Model? = nil
local managerBody: BasePart? = nil

local limiter = RateLimiter.new(RateLimits, function(player: Player, remoteName: string)
	warn(`{LOG} {player.Name} {remoteName} ปฏิเสธ: เกิน rate limit`)
	NotifyService.Notify(player, "ReportRateLimited", "error", nil)
end)

local function languageOf(player: Player): string
	local data = DataService.GetData(player)
	if data then
		return data.Settings.Language
	end
	return PlayerDataConfig.DefaultLanguage
end

-- ปฏิเสธคำขอ: warn ฝั่ง dev + แจ้งผู้เล่น
local function reject(player: Player, source: string, reason: string, key: string)
	warn(`{LOG} {player.Name} {source} ปฏิเสธ: {reason}`)
	NotifyService.Notify(player, key, "error", nil)
end

local function pickLine(situation: string, language: string): string
	local line = ReportRules.PickLine(situation, language, random:NextNumber())
	if line == nil then
		warn(`{LOG} Config/ManagerLines: สถานการณ์ {situation} ({language}) ไม่มีบรรทัด ใช้บรรทัดสำรอง`)
		return ReportRules.FallbackLine(language)
	end
	return line
end

local function closeMenu(player: Player)
	sessions[player] = nil
	if player.Parent == Players then
		menuEvent:FireClient(player, { Open = false })
	end
end

local function isNightActive(): boolean
	return DayNightService.IsNight() and DayNightService.IsRunning()
end

local function isNear(player: Player): boolean
	local body = managerBody
	local character = player.Character
	if body == nil or body.Parent == nil or character == nil then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return false
	end
	return ReportRules.WithinDistance(root.Position, body.Position, Report.ReportMaxDistance + Report.DistanceTolerance)
end

local function setReaction(kind: string, level: number, userId: number)
	local model = managerModel
	if model == nil then
		return
	end
	reactionSeq += 1
	model:SetAttribute(Report.ReactionKindAttribute, kind)
	model:SetAttribute(Report.ReactionLevelAttribute, level)
	model:SetAttribute(Report.ReactionUserIdAttribute, userId)
	model:SetAttribute(Report.ReactionSeqAttribute, reactionSeq)
end

local function customerName(language: string, customerId: string): string
	local customer = CustomersConfig.Customers[customerId]
	if customer == nil then
		return customerId
	end
	return if language == "en" then customer.DisplayNameEn else customer.DisplayNameTh
end

-- รายชื่อลูกค้าในร้านตอนนี้ (จาก ServeService) ไม่ซ้ำ id จำกัดจำนวนตาม Config
local function buildCustomerList(language: string): ({ CustomerEntry }, { [string]: boolean })
	local list: { CustomerEntry } = {}
	local ids: { [string]: boolean } = {}
	for _, customer in ServeService.GetActiveCustomers() do
		if #list >= Report.CustomerMenuMax then
			break
		end
		if not ids[customer.CustomerId] then
			ids[customer.CustomerId] = true
			table.insert(list, { Id = customer.CustomerId, Name = customerName(language, customer.CustomerId) })
		end
	end
	return list, ids
end

local function openMenu(player: Player)
	if not limiter:Check(player, "ReportPrompt") then
		return
	end
	if not isNightActive() then
		reject(player, "ReportPrompt", "ไม่ใช่ช่วงคืนที่กำลังนับเวลา", "ReportNotNight")
		return
	end
	if not isNear(player) then
		reject(player, "ReportPrompt", "อยู่ไกลผู้จัดการเกินระยะหรือไม่มีตัวละคร", "ReportTooFar")
		return
	end
	local language = languageOf(player)
	local customers, ids = buildCustomerList(language)
	sessions[player] = { ExpiresAt = Workspace:GetServerTimeNow() + Report.MenuSessionSeconds, Customers = ids }
	menuEvent:FireClient(player, {
		Open = true,
		Language = language,
		Categories = AnomalyService.GetCategories(),
		Customers = customers,
		Line = pickLine("MenuOpen", language),
	})
	print(`{LOG} {player.Name} เปิดเมนูรายงาน (ลูกค้าในร้าน {#customers} คน)`)
end

-- ให้เหรียญผู้รายงาน (จำกัดเพดาน) คืนจำนวนที่ได้จริง
local function grantCoins(player: Player, amount: number): number
	local data = DataService.GetData(player)
	if data == nil then
		return 0
	end
	local limits = PlayerDataConfig.Limits
	local newCoins = math.min(data.Coins + amount, limits.MaxCoins)
	local added = newCoins - data.Coins
	data.Coins = newCoins
	currencyEvent:FireClient(player, { Coins = data.Coins, Reputation = data.Reputation })
	if added < amount then
		warn(`{LOG} {player.Name} เหรียญเต็มเพดาน {limits.MaxCoins} ได้ {added}/{amount}`)
		local args: { [string]: string | number } = { coins = added }
		NotifyService.Notify(player, "ServeCoinsCapped", "info", args)
	end
	return added
end

-- ลูกค้า anomaly ที่ถูกรายงาน: ปิด slot ของลูกค้านั้นใน roster เป็น Reported (ผูก slot กับลูกค้าจริงเป็น TASK-015)
local function markCustomerReported(customerId: string?)
	if customerId == nil then
		return
	end
	for _, slot in AnomalyService.GetNightRoster().Slots do
		if slot.State == "Pending" and slot.CustomerId == customerId then
			AnomalyService.MarkCustomerHandled(slot.SlotId, "Reported")
			return
		end
	end
	print(`{LOG} ไม่พบ slot ที่ยังค้างของลูกค้า {customerId} ใน roster ไม่ปิด slot`)
end

local function sendResult(player: Player, correct: boolean, level: number, line: string, language: string)
	resultEvent:FireClient(player, { Correct = correct, Level = level, Line = line, Language = language })
end

local function handleCorrect(player: Player, category: string, customerId: string?)
	local language = languageOf(player)
	local coins = 0
	local resolved = 0
	local firstId: string? = nil
	for _, info in AnomalyService.GetActiveOfCategory(category) do
		if category ~= "customer" or info.CustomerId == customerId then
			if AnomalyService.ResolveAnomaly(info.InstanceId) then
				resolved += 1
				coins += Report.CoinReward + Report.CoinPerSubtlety * info.Subtlety
				firstId = firstId or info.Id
				if category == "customer" then
					markCustomerReported(info.CustomerId)
				end
			else
				warn(`{LOG} {player.Name} รายงานถูกแต่คืนสภาพ anomaly #{info.InstanceId} ({info.Id}) ไม่สำเร็จ ไม่ให้รางวัลของตัวนี้`)
			end
		end
	end
	if resolved == 0 then
		warn(`{LOG} {player.Name} รายงานหมวด {category} ถูก แต่แก้ anomaly ไม่ได้เลย (ไม่ลงโทษ)`)
		NotifyService.Notify(player, "UnknownError", "error", nil)
		return
	end
	local added = grantCoins(player, coins)
	recipeProgress += Report.RecipeProgressPerCorrect * resolved
	local line = pickLine("Praise", language)
	local coinArgs: { [string]: string | number } = { coins = added }
	NotifyService.Notify(player, "ReportCorrect", "success", coinArgs)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local args: { [string]: string | number } = { player = player.DisplayName }
			NotifyService.Notify(other, "ReportCorrectByOther", "info", args)
		end
	end
	sendResult(player, true, 0, line, language)
	setReaction("Praise", 0, player.UserId)
	print(`{LOG} {player.Name} รายงานหมวด {category} ถูก: แก้ {resolved} ตัว +{added} เหรียญ ตัวนับสูตรรวม {recipeProgress}`)
	reportedEvent:Fire(player, category, true, firstId)
end

local function handleWrong(player: Player, category: string)
	local language = languageOf(player)
	local wrong = (wrongCounts[player] or 0) + 1
	wrongCounts[player] = wrong
	local level = ReportRules.HauntLevel(wrong, Report.WrongHauntLevels)
	local nothingActive = #AnomalyService.GetActiveAnomalies() == 0
	local before = SanityService.Get(player) or 0
	local after = SanityService.Change(player, -Sanity.Values.WrongReport, "WrongReport") or before
	local args: { [string]: string | number } = { lost = before - after, sanity = after }
	NotifyService.Notify(player, if nothingActive then "ReportWrongNone" else "ReportWrong", "error", args)
	local situation = if nothingActive and level == 1 then "WrongNone" else ReportRules.WrongSituation(level)
	sendResult(player, false, level, pickLine(situation, language), language)
	setReaction("Haunt", level, player.UserId)
	print(`{LOG} {player.Name} รายงานหมวด {category} ผิด (ครั้งที่ {wrong} ของคืน ระดับหลอน {level}) สติ {before} -> {after}`)
	reportedEvent:Fire(player, category, false, nil)
end

local function onSubmit(player: Player, categoryRaw: unknown, customerRaw: unknown)
	if not limiter:Check(player, "ReportSubmit") then
		return
	end
	local category, customerId, problem = ReportRules.ParseSubmit(
		categoryRaw,
		customerRaw,
		AnomalyService.GetCategories(),
		Report.MaxPayloadStringLength
	)
	if category == nil then
		reject(player, "ReportSubmit", `payload ไม่ถูกต้อง: {tostring(problem)}`, "ReportInvalid")
		return
	end
	local now = Workspace:GetServerTimeNow()
	local session = sessions[player]
	if session == nil or now > session.ExpiresAt then
		reject(player, "ReportSubmit", "ไม่มีเมนูรายงานที่เปิดอยู่ (ไม่ได้เปิดผ่านผู้จัดการ หรือหมดอายุ)", "ReportMenuExpired")
		closeMenu(player)
		return
	end
	if customerId ~= nil and session.Customers[customerId] ~= true then
		reject(player, "ReportSubmit", `customerId {customerId} ไม่อยู่ในรายชื่อที่ server ส่งให้เมนู`, "ReportInvalid")
		return
	end
	if not isNear(player) then
		reject(player, "ReportSubmit", "อยู่ไกลผู้จัดการเกินระยะหรือไม่มีตัวละคร", "ReportTooFar")
		closeMenu(player)
		return
	end
	if not isNightActive() then
		reject(player, "ReportSubmit", "ไม่ใช่ช่วงคืนที่กำลังนับเวลา", "ReportNotNight")
		closeMenu(player)
		return
	end
	local last = lastReportAt[player]
	if last ~= nil and now - last < Report.ReportCooldownSeconds then
		reject(player, "ReportSubmit", `อยู่ในช่วง cooldown ({Report.ReportCooldownSeconds} วินาที)`, "ReportCooldown")
		return
	end
	if DataService.GetData(player) == nil then
		reject(player, "ReportSubmit", "ข้อมูลผู้เล่นยังโหลดไม่เสร็จ", "DataNotReady")
		return
	end

	lastReportAt[player] = now
	closeMenu(player)
	if AnomalyService.HasActiveOfCategory(category, customerId) then
		handleCorrect(player, category, customerId)
	else
		handleWrong(player, category)
	end
end

local function resetNight()
	table.clear(wrongCounts)
	table.clear(lastReportAt)
	for player in sessions do
		closeMenu(player)
	end
	print(`{LOG} เริ่มคืนใหม่: ล้างจำนวนครั้งที่ผิด/cooldown/เมนูที่ค้าง`)
end

-- ตรวจเมนูที่เปิดค้าง: หมดอายุ/เดินห่าง/หมดช่วงคืน -> ปิดพร้อมบอกเหตุผล
local function sweepSessions()
	local now = Workspace:GetServerTimeNow()
	for player, session in table.clone(sessions) do
		if player.Parent ~= Players then
			sessions[player] = nil
		elseif now > session.ExpiresAt then
			closeMenu(player)
			NotifyService.Notify(player, "ReportMenuExpired", "info", nil)
		elseif not isNear(player) then
			closeMenu(player)
			NotifyService.Notify(player, "ReportTooFar", "info", nil)
		elseif not isNightActive() then
			closeMenu(player)
			NotifyService.Notify(player, "ReportNotNight", "info", nil)
		end
	end
end

local function part(name: string, size: Vector3, shape: Enum.PartType, color: Color3, parent: Instance): Part
	local created = Instance.new("Part")
	created.Name = name
	created.Anchored = true
	created.CanCollide = false
	created.CanQuery = false
	created.CanTouch = false
	created.Shape = shape
	created.Size = size
	created.Color = color
	created.Material = Enum.Material.SmoothPlastic
	created.Parent = parent
	return created
end

-- สร้างผู้จัดการจาก Part พื้นฐาน (ตัวกลม หัว ตา ปาก หมวกเชฟ) ตำแหน่งอิง SpawnLocation เหมือน ServeService
local function createManager()
	local stale = Workspace:FindFirstChild(Report.ManagerModelName)
	if stale ~= nil then
		stale:Destroy()
	end
	local groundY = Report.FallbackGroundY
	local x, z = Report.FallbackXZ.X, Report.FallbackXZ.Y
	local spawnLocation = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawnLocation ~= nil then
		groundY = spawnLocation.Position.Y - spawnLocation.Size.Y / 2
		x = spawnLocation.Position.X + Report.SpawnOffsetXZ.X
		z = spawnLocation.Position.Z + Report.SpawnOffsetXZ.Y
	else
		warn(`{LOG} ไม่พบ SpawnLocation ใน Workspace ใช้พิกัดสำรองของผู้จัดการ`)
	end

	local model = Instance.new("Model")
	model.Name = Report.ManagerModelName
	local bodyCenter = Vector3.new(x, groundY + Report.BodySize.Y / 2, z)
	local facing = CFrame.lookAt(bodyCenter, bodyCenter + Report.FacingDirection)
	local body = part("Body", Report.BodySize, Enum.PartType.Ball, Report.BodyColor, model)
	body.CFrame = facing
	local headSize = Vector3.one * Report.HeadSize
	local headOffset = Report.BodySize.Y / 2 + Report.HeadSize / 2 - Report.HeadOverlapStuds
	local head = part("Head", headSize, Enum.PartType.Ball, Report.HeadColor, model)
	head.CFrame = facing * CFrame.new(0, headOffset, 0)
	local eyeLeft = part("EyeL", Report.EyeSize, Enum.PartType.Ball, Report.EyeColor, model)
	eyeLeft.CFrame = head.CFrame * CFrame.new(-Report.EyeOffset.X, Report.EyeOffset.Y, Report.EyeOffset.Z)
	local eyeRight = part("EyeR", Report.EyeSize, Enum.PartType.Ball, Report.EyeColor, model)
	eyeRight.CFrame = head.CFrame * CFrame.new(Report.EyeOffset)
	local mouth = part("Mouth", Report.MouthSize, Enum.PartType.Block, Report.MouthColor, model)
	mouth.CFrame = head.CFrame * CFrame.new(Report.MouthOffset)
	local hat = part("Hat", Report.HatSize, Enum.PartType.Block, Report.HatColor, model)
	hat.CFrame = head.CFrame * CFrame.new(0, Report.HatOffsetY, 0)
	model.PrimaryPart = body

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = Report.ManagerPromptName
	prompt.ActionText = Strings.Format("ReportPromptAction", PlayerDataConfig.DefaultLanguage, nil)
	prompt.ObjectText = Strings.Format("ReportPromptObject", PlayerDataConfig.DefaultLanguage, nil)
	prompt.MaxActivationDistance = Report.PromptDistance
	prompt.HoldDuration = Report.PromptHoldSeconds
	prompt.KeyboardKeyCode = Report.PromptKeyCode
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	prompt.Triggered:Connect(openMenu)

	model.Parent = Workspace
	managerModel = model
	managerBody = body
	print(`{LOG} สร้างผู้จัดการที่ ({bodyCenter.X}, {bodyCenter.Y}, {bodyCenter.Z}) อิง {if spawnLocation ~= nil then "SpawnLocation" else "Fallback"}`)
end

function ReportService.GetRecipeProgress(): number
	return recipeProgress
end

function ReportService.GetWrongCount(player: Player): number
	return wrongCounts[player] or 0
end

local function onPlayerRemoving(player: Player)
	sessions[player] = nil
	lastReportAt[player] = nil
	wrongCounts[player] = nil
end

function ReportService.Start()
	for _, problem in ReportRules.ValidateSetup(Report.WrongHauntLevels, #Report.HauntStyles) do
		warn(`{LOG} ตั้งค่าไม่ถูกต้อง: {problem}`)
	end
	createManager()
	submitEvent.OnServerEvent:Connect(onSubmit)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	DayNightService.OnNightStarted(resetNight)
	DayNightService.OnPhaseChanged(function(phase: string, _day: number)
		if phase ~= "Night" then
			for player in table.clone(sessions) do
				closeMenu(player)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Report.SessionCheckSeconds)
			sweepSessions()
		end
	end)
end

return ReportService
