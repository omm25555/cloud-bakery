--!strict
-- BakeService: โต๊ะผสม + เตาอบรวมบนเกาะ (co-op) ผสม → อบ → มินิเกมจังหวะ → ได้ขนมเข้ากระเป๋า
-- server ตัดสินทุกอย่าง: การหักวัตถุดิบ เวลาอบ (GetServerTimeNow) ผลมินิเกม และของที่ได้
-- client ส่งได้แค่ "ขออบสูตรไหน" / "ขอเก็บ (เตา)" / "เวลาที่กด" / "ขอ snapshot"
-- สถานะเตาไม่ถูกบันทึก: ถ้าเจ้าของออกกลางคัน DataService เรียก OnBeforeSave ก่อนเซฟ
-- เพื่อคืนวัตถุดิบ (ยังอบไม่เสร็จ) หรือให้ขนมระดับ Good (อบเสร็จ/กำลังเล่นมินิเกม)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Bake = require(ReplicatedStorage.Shared.Config.Bake)
local Farm = require(ReplicatedStorage.Shared.Config.Farm)
local Ingredients = require(ReplicatedStorage.Shared.Config.Ingredients)
local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local RateLimits = require(ReplicatedStorage.Shared.Config.RateLimits)
local Recipes = require(ReplicatedStorage.Shared.Config.Recipes)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local BakeRhythm = require(ReplicatedStorage.Shared.BakeRhythm)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local NotifyService = require(script.Parent.NotifyService)
local UpgradeService = require(script.Parent.UpgradeService)

local LOG = "[BakeService]"

type PlayerData = PlayerDataConfig.PlayerData
type Judgement = BakeRhythm.Judgement
type OvenState = "Idle" | "Baking" | "Minigame" | "Done"

type MinigameRun = {
	StartedAt: number,
	Zones: { number },
	Judgements: { Judgement },
	LastOffset: number?,
}

type Oven = {
	Id: number,
	State: OvenState,
	RecipeId: string?,
	OwnerUserId: number?,
	OwnerName: string?,
	ReadyAt: number?,
	Minigame: MinigameRun?,
	Grade: Judgement?,
	Amount: number?,
	WaitId: number, -- รหัสรอบการรอเก็บ 0 = ไม่ได้รอ (ใช้ยกเลิก timer ที่ค้างอยู่)
}

type OvenEntry = {
	OvenId: number,
	State: string,
	RecipeId: string?,
	ReadyAt: number?,
	OwnerUserId: number?,
	OwnerName: string?,
	Amount: number?,
}

-- สร้าง remote ตอน require เพื่อให้ client หาเจอเสมอ ไม่ขึ้นกับลำดับ Start
-- (GetEvent คืน instance เดิมเมื่อเรียกชื่อซ้ำ จึงใช้ InventoryUpdate ร่วมกับ FarmService ได้)
local startEvent = Remotes.GetEvent("BakeStart")
local collectEvent = Remotes.GetEvent("BakeCollect")
local tapEvent = Remotes.GetEvent("BakeTap")
local syncEvent = Remotes.GetEvent("BakeSync")
local stateEvent = Remotes.GetEvent("BakeState")
local minigameEvent = Remotes.GetEvent("BakeMinigame")
local tapResultEvent = Remotes.GetEvent("BakeTapResult")
local inventoryEvent = Remotes.GetEvent("InventoryUpdate")

local BakeService = {}

local ovens: { Oven } = {}
local ovenParts: { [number]: BasePart } = {}
local mixingPart: BasePart? = nil
local random = Random.new()
local waitCounter = 0

local maxReward = 0
for _, amount in Bake.ScoreRewards do
	maxReward = math.max(maxReward, amount)
end

local limiter = RateLimiter.new(RateLimits, function(player: Player, _remoteName: string)
	NotifyService.NotifyRateLimited(player)
end)

local function languageOf(player: Player): string
	local data = DataService.GetData(player)
	if data then
		return data.Settings.Language
	end
	return PlayerDataConfig.DefaultLanguage
end

local function dishName(player: Player, recipeId: string): string
	local recipe = Recipes[recipeId]
	if recipe == nil then
		return recipeId
	end
	return if languageOf(player) == "en" then recipe.DisplayNameEn else recipe.DisplayNameTh
end

local function ingredientName(player: Player, ingredientId: string): string
	local ingredient = Ingredients[ingredientId]
	if ingredient == nil then
		return ingredientId
	end
	return if languageOf(player) == "en" then ingredient.DisplayNameEn else ingredient.DisplayNameTh
end

-- ปฏิเสธคำขอ: warn ฝั่ง dev + แจ้งผู้เล่น
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

local function inventoryTotal(data: PlayerData): number
	local total = 0
	for _, count in data.Inventory do
		total += count
	end
	return total
end

local function sendInventory(player: Player, data: PlayerData)
	local copy: { [string]: number } = {}
	for id, count in data.Inventory do
		copy[id] = count
	end
	inventoryEvent:FireClient(player, { Inventory = copy, Language = data.Settings.Language })
end

local function toEntry(oven: Oven): OvenEntry
	return {
		OvenId = oven.Id,
		State = oven.State,
		RecipeId = oven.RecipeId,
		ReadyAt = oven.ReadyAt,
		OwnerUserId = oven.OwnerUserId,
		OwnerName = oven.OwnerName,
		Amount = oven.Amount,
	}
end

local function broadcastOven(oven: Oven)
	stateEvent:FireAllClients({ Ovens = { toEntry(oven) } })
end

local function resetOven(oven: Oven)
	oven.State = "Idle"
	oven.RecipeId = nil
	oven.OwnerUserId = nil
	oven.OwnerName = nil
	oven.ReadyAt = nil
	oven.Minigame = nil
	oven.Grade = nil
	oven.Amount = nil
	oven.WaitId = 0
end

local function readOven(raw: unknown): Oven?
	if type(raw) ~= "number" then
		return nil
	end
	local id = raw :: number
	if id ~= id or id ~= math.floor(id) then
		return nil
	end
	return ovens[id]
end

local function isNear(player: Player, part: BasePart?): boolean
	local character = player.Character
	if part == nil or character == nil then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - part.Position).Magnitude <= Bake.InteractDistance + Bake.DistanceTolerance
end

-- เพิ่มของเข้ากระเป๋าตอนผู้เล่นออก: ห้ามให้ของหาย จึงเกินความจุได้ (warn) แต่ไม่เกิน MaxItemCount
local function grantOnLeave(player: Player, data: PlayerData, itemId: string, amount: number, reason: string)
	local current = data.Inventory[itemId] or 0
	local limit = PlayerDataConfig.Limits.MaxItemCount
	local granted = math.min(amount, math.max(0, limit - current))
	if granted < amount then
		warn(`{LOG} {player.Name} {reason}: {itemId} เกิน MaxItemCount ({limit}) ให้ {granted}/{amount}`)
	end
	data.Inventory[itemId] = current + granted
	if inventoryTotal(data) > Farm.InventoryCapacity then
		warn(`{LOG} {player.Name} {reason}: กระเป๋าเกินความจุ {Farm.InventoryCapacity} หลังใส่ {itemId} x{granted} (ใส่ให้เพื่อไม่ให้ของหาย)`)
	end
end

-- ลองใส่ขนมที่อบเสร็จเข้ากระเป๋า คืน true เมื่อสำเร็จ (ไม่ yield ตั้งแต่ตรวจถึงเขียน)
local function tryDeliver(player: Player, data: PlayerData, oven: Oven, remoteName: string): boolean
	local recipeId = oven.RecipeId
	local amount = oven.Amount
	if recipeId == nil or amount == nil then
		return false
	end
	local total = inventoryTotal(data)
	local current = data.Inventory[recipeId] or 0
	local free = math.max(0, Farm.InventoryCapacity - total)
	if total + amount > Farm.InventoryCapacity or current + amount > PlayerDataConfig.Limits.MaxItemCount then
		local args: { [string]: string | number } = { free = free, need = amount }
		reject(player, remoteName, `กระเป๋าเต็ม (รวม {total}/{Farm.InventoryCapacity}, {recipeId} {current}) ขนมค้างในเตา {oven.Id}`, "BakeCollectFull", args)
		return false
	end
	data.Inventory[recipeId] = current + amount
	local grade = oven.Grade
	local okArgs: { [string]: string | number } = { dish = dishName(player, recipeId), amount = amount }
	resetOven(oven)
	sendInventory(player, data)
	NotifyService.Notify(player, "BakeCollected", "success", okArgs)
	if grade ~= nil then
		print(`{LOG} {player.Name} ได้ {recipeId} x{amount} (ระดับ {grade})`)
	end
	return true
end

-- หมดเวลารอเก็บ: ใส่กระเป๋าเท่าที่ใส่ได้ (ตามระดับที่ทำได้ ถ้ายังไม่ได้เล่นมินิเกมนับเป็น Good) ที่เหลือหาย แล้วคืนเตา
local function expireOven(oven: Oven, waitId: number)
	if oven.WaitId ~= waitId or (oven.State ~= "Baking" and oven.State ~= "Done") then
		return
	end
	local recipeId = oven.RecipeId
	local ownerId = oven.OwnerUserId
	local player = if ownerId then Players:GetPlayerByUserId(ownerId) else nil
	local data = if player then DataService.GetData(player) else nil
	if recipeId == nil or player == nil or data == nil then
		warn(`{LOG} เตา {oven.Id} หมดเวลารอเก็บแต่ไม่มีเจ้าของ/ข้อมูล เคลียร์เตาโดยไม่ให้ของ`)
		resetOven(oven)
		broadcastOven(oven)
		return
	end
	local amount = if oven.State == "Done" and oven.Amount ~= nil
		then oven.Amount :: number
		else (Bake.ScoreRewards.Good or 0)
	local free = math.max(0, Farm.InventoryCapacity - inventoryTotal(data))
	local current = data.Inventory[recipeId] or 0
	local room = math.max(0, PlayerDataConfig.Limits.MaxItemCount - current)
	local put = math.min(amount, free, room)
	local lost = amount - put
	if put > 0 then
		data.Inventory[recipeId] = current + put
	end
	resetOven(oven)
	broadcastOven(oven)
	sendInventory(player, data)

	local args: { [string]: string | number } = { dish = dishName(player, recipeId), amount = put, lost = lost }
	if lost == 0 then
		NotifyService.Notify(player, "BakeAutoCollected", "success", args)
	elseif put > 0 then
		warn(`{LOG} {player.Name} เตา {oven.Id} หมดเวลารอเก็บ กระเป๋าเต็ม ใส่ {recipeId} ได้ {put}/{amount} เสียไป {lost}`)
		NotifyService.Notify(player, "BakeAutoCollectedPartial", "error", args)
	else
		warn(`{LOG} {player.Name} เตา {oven.Id} หมดเวลารอเก็บ กระเป๋าเต็ม {recipeId} x{amount} หายทั้งหมด`)
		NotifyService.Notify(player, "BakeAutoCollectedLost", "error", args)
	end
	print(`{LOG} {player.Name} เตา {oven.Id} หมดเวลารอเก็บ ใส่ {recipeId} x{put} เสีย x{lost}`)
end

-- เริ่มนับเวลารอเก็บ (startAt = เวลา server ที่เตาเข้าสถานะรอเก็บ) เตือนก่อนหมดเวลาแล้วค่อยหมดเวลา
local function beginWait(oven: Oven, startAt: number)
	waitCounter += 1
	local waitId = waitCounter
	oven.WaitId = waitId
	local deadline = startAt + Bake.CollectTimeoutSeconds
	local now = Workspace:GetServerTimeNow()
	local warnDelay = math.max(0, deadline - Bake.CollectWarnSeconds - now)
	task.delay(warnDelay, function()
		if oven.WaitId ~= waitId then
			return
		end
		local ownerId = oven.OwnerUserId
		local recipeId = oven.RecipeId
		local player = if ownerId then Players:GetPlayerByUserId(ownerId) else nil
		if player and recipeId then
			local seconds = math.max(1, math.ceil(deadline - Workspace:GetServerTimeNow()))
			local args: { [string]: string | number } = { dish = dishName(player, recipeId), seconds = seconds }
			NotifyService.Notify(player, "BakeCollectWarn", "info", args)
		end
	end)
	task.delay(math.max(0, deadline - now), function()
		expireOven(oven, waitId)
	end)
end

local function finishMinigame(oven: Oven, run: MinigameRun, timedOut: boolean)
	if oven.Minigame ~= run or oven.State ~= "Minigame" then
		return
	end
	local grade: Judgement = BakeRhythm.Grade(run.Judgements)
	local amount = Bake.ScoreRewards[grade] or 0
	oven.Minigame = nil
	oven.State = "Done"
	oven.Grade = grade
	oven.Amount = amount
	beginWait(oven, Workspace:GetServerTimeNow()) -- ใส่กระเป๋าสำเร็จด้านล่างจะ reset เตาและยกเลิกการรอนี้เอง

	local ownerId = oven.OwnerUserId
	local recipeId = oven.RecipeId
	local player = if ownerId then Players:GetPlayerByUserId(ownerId) else nil
	if player and recipeId then
		if timedOut then
			NotifyService.Notify(player, "MinigameTimeout", "info")
		end
		NotifyService.Notify(player, `MinigameGrade{grade}`, if grade == "Miss" then "info" else "success", nil)
		local data = DataService.GetData(player)
		if data then
			tryDeliver(player, data, oven, if timedOut then "BakeTimeout" else "BakeTap")
		else
			warn(`{LOG} {player.Name} จบมินิเกมแต่ข้อมูลไม่พร้อม ขนมค้างในเตา {oven.Id}`)
			NotifyService.Notify(player, "DataNotReady", "error")
		end
	end
	broadcastOven(oven)
end

local function validateOffset(run: MinigameRun, raw: unknown, now: number): (number?, string?)
	if type(raw) ~= "number" then
		return nil, `offset ไม่ใช่ number ({typeof(raw)})`
	end
	local offset = raw :: number
	if offset ~= offset or offset == math.huge or offset == -math.huge then
		return nil, "offset เป็น NaN/inf"
	end
	local mg = Bake.Minigame
	if offset < 0 or offset > mg.MaxDurationSeconds then
		return nil, `offset นอกช่วง 0-{mg.MaxDurationSeconds} ({offset})`
	end
	local last = run.LastOffset
	local minOffset = if last then last + mg.MinTapGapSeconds else mg.MinFirstTapSeconds
	if offset < minOffset then
		return nil, `กดเร็วเกินเป็นไปได้ (offset {offset} < {minOffset})`
	end
	local elapsed = now - run.StartedAt
	if offset > elapsed + mg.LatencyToleranceSeconds then
		return nil, `offset ล้ำหน้าเวลาจริงบน server (offset {offset}, server {elapsed})`
	end
	if offset < elapsed - mg.MaxTapLagSeconds then
		return nil, `offset เก่าเกินไปเทียบเวลาจริงบน server (offset {offset}, server {elapsed})`
	end
	return offset, nil
end

local function onTap(player: Player, ovenIdRaw: unknown, offsetRaw: unknown)
	if not limiter:Check(player, "BakeTap") then
		return
	end
	local oven = readOven(ovenIdRaw)
	if oven == nil then
		reject(player, "BakeTap", `ovenId ไม่ถูกต้อง ({tostring(ovenIdRaw)})`, "InvalidRequest", nil)
		return
	end
	if oven.OwnerUserId ~= player.UserId then
		local args: { [string]: string | number } = { owner = oven.OwnerName or "-" }
		local key = if oven.State == "Idle" then "MinigameNotActive" else "OvenNotYours"
		reject(player, "BakeTap", `เตา {oven.Id} ไม่ใช่ของผู้เล่น (เจ้าของ {tostring(oven.OwnerUserId)})`, key, args)
		return
	end
	local run = oven.Minigame
	if oven.State ~= "Minigame" or run == nil then
		reject(player, "BakeTap", `เตา {oven.Id} ไม่ได้อยู่ในมินิเกม (สถานะ {oven.State})`, "MinigameNotActive", nil)
		return
	end

	local index = #run.Judgements + 1
	local offset, problem = validateOffset(run, offsetRaw, Workspace:GetServerTimeNow())
	local judgement: Judgement = "Miss"
	if offset ~= nil then
		run.LastOffset = offset
		judgement = BakeRhythm.Judge(BakeRhythm.LinePosition(offset), run.Zones[index])
	else
		warn(`{LOG} {player.Name} BakeTap ผลมินิเกมถูกปฏิเสธ นับเป็น Miss: {tostring(problem)}`)
		NotifyService.Notify(player, "MinigameRejected", "error")
	end
	table.insert(run.Judgements, judgement)
	tapResultEvent:FireClient(player, { OvenId = oven.Id, Index = index, Judgement = judgement })

	if #run.Judgements >= Bake.Minigame.TapCount then
		finishMinigame(oven, run, false)
	end
end

local function startMinigame(player: Player, oven: Oven)
	local mg = Bake.Minigame
	local zones: { number } = {}
	for _ = 1, mg.TapCount do
		table.insert(zones, random:NextNumber(mg.ZoneMin, mg.ZoneMax))
	end
	local run: MinigameRun = {
		StartedAt = Workspace:GetServerTimeNow(),
		Zones = zones,
		Judgements = {},
		LastOffset = nil,
	}
	oven.State = "Minigame"
	oven.WaitId = 0 -- ยกเลิกการนับเวลารอเก็บระหว่างเล่นมินิเกม
	oven.Minigame = run
	broadcastOven(oven)
	minigameEvent:FireClient(player, { OvenId = oven.Id, StartedAt = run.StartedAt, Zones = table.clone(zones) })
	local startArgs: { [string]: string | number } = { count = mg.TapCount }
	NotifyService.Notify(player, "MinigameStart", "info", startArgs)

	task.delay(mg.MaxDurationSeconds + mg.TimeoutGraceSeconds, function()
		finishMinigame(oven, run, true)
	end)
end

local function onCollect(player: Player, ovenIdRaw: unknown)
	if not limiter:Check(player, "BakeCollect") then
		return
	end
	local oven = readOven(ovenIdRaw)
	if oven == nil then
		reject(player, "BakeCollect", `ovenId ไม่ถูกต้อง ({tostring(ovenIdRaw)})`, "InvalidRequest", nil)
		return
	end
	local data = DataService.GetData(player)
	if data == nil then
		reject(player, "BakeCollect", "ข้อมูลผู้เล่นยังโหลดไม่เสร็จ", "DataNotReady", nil)
		return
	end
	if not isNear(player, ovenParts[oven.Id]) then
		reject(player, "BakeCollect", `อยู่ไกลเตา {oven.Id} เกินระยะ หรือไม่มีตัวละคร`, "BakeTooFar", nil)
		return
	end
	if oven.State == "Idle" then
		reject(player, "BakeCollect", `เตา {oven.Id} ว่าง`, "OvenIdle", nil)
		return
	end
	if oven.OwnerUserId ~= player.UserId then
		local args: { [string]: string | number } = { owner = oven.OwnerName or "-" }
		reject(player, "BakeCollect", `เตา {oven.Id} เป็นของ {tostring(oven.OwnerUserId)}`, "OvenNotYours", args)
		return
	end

	if oven.State == "Minigame" then
		-- ส่งมินิเกมเดิมให้ใหม่ เผื่อ UI ฝั่ง client หาย (ไม่เริ่มใหม่ ไม่รีเซ็ตเวลา)
		local run = oven.Minigame
		if run then
			minigameEvent:FireClient(player, { OvenId = oven.Id, StartedAt = run.StartedAt, Zones = table.clone(run.Zones) })
		end
		return
	end

	if oven.State == "Done" then
		if tryDeliver(player, data, oven, "BakeCollect") then
			broadcastOven(oven)
		end
		return
	end

	local recipeId = oven.RecipeId
	local readyAt = oven.ReadyAt
	if recipeId == nil or readyAt == nil then
		warn(`{LOG} เตา {oven.Id} สถานะ Baking แต่ไม่มีข้อมูลสูตร/เวลา รีเซ็ตเตา`)
		resetOven(oven)
		broadcastOven(oven)
		NotifyService.Notify(player, "UnknownError", "error")
		return
	end
	local remaining = readyAt - Workspace:GetServerTimeNow()
	if remaining > 0 then
		local args: { [string]: string | number } = { dish = dishName(player, recipeId), seconds = math.ceil(remaining) }
		reject(player, "BakeCollect", `เตา {oven.Id} ยังอบไม่เสร็จ (เหลือ {string.format("%.1f", remaining)} วินาที)`, "BakeNotReady", args)
		return
	end
	startMinigame(player, oven)
end

local function onStart(player: Player, recipeIdRaw: unknown)
	if not limiter:Check(player, "BakeStart") then
		return
	end
	if type(recipeIdRaw) ~= "string" then
		reject(player, "BakeStart", `recipeId ไม่ใช่ string ({typeof(recipeIdRaw)})`, "InvalidRequest", nil)
		return
	end
	local recipe = Recipes[recipeIdRaw :: string]
	if recipe == nil then
		reject(player, "BakeStart", `ไม่มีสูตร {recipeIdRaw :: string} ใน Config`, "InvalidRequest", nil)
		return
	end
	local data = DataService.GetData(player)
	if data == nil then
		reject(player, "BakeStart", "ข้อมูลผู้เล่นยังโหลดไม่เสร็จ", "DataNotReady", nil)
		return
	end
	if not isNear(player, mixingPart) then
		reject(player, "BakeStart", "อยู่ไกลโต๊ะผสมเกินระยะ หรือไม่มีตัวละคร", "BakeTooFar", nil)
		return
	end

	-- จากตรงนี้ถึงตั้งสถานะเตาไม่มี yield: สองคนจองเตาเดียวกันพร้อมกันไม่ได้
	local now = Workspace:GetServerTimeNow()
	local freeOven: Oven? = nil
	local soonest: number? = nil
	for _, oven in ovens do
		if oven.State == "Idle" then
			freeOven = oven
			break
		elseif oven.State == "Baking" and oven.ReadyAt ~= nil then
			local left = (oven.ReadyAt :: number) - now
			if left > 0 and (soonest == nil or left < soonest) then
				soonest = left
			end
		end
	end
	if freeOven == nil then
		if soonest ~= nil then
			local args: { [string]: string | number } = { seconds = math.ceil(soonest) }
			reject(player, "BakeStart", `เตาไม่ว่างทุกเตา (เตาที่ว่างเร็วสุดอีก {string.format("%.1f", soonest)} วินาที)`, "OvensBusy", args)
		else
			reject(player, "BakeStart", "เตาไม่ว่างทุกเตา (รอเก็บ/กำลังเล่นมินิเกม)", "OvensBusyWaiting", nil)
		end
		return
	end

	local ingredientIds: { string } = {}
	for id in recipe.Ingredients do
		table.insert(ingredientIds, id)
	end
	table.sort(ingredientIds)

	local missingParts: { string } = {}
	local missingArgs: { { [string]: string | number } } = {}
	local ingredientTotal = 0
	for _, id in ingredientIds do
		local need = recipe.Ingredients[id]
		local have = data.Inventory[id] or 0
		ingredientTotal += need
		if have < need then
			local partArgs: { [string]: string | number } = { name = ingredientName(player, id), count = need - have }
			table.insert(missingParts, Strings.Format("UiInventoryItem", languageOf(player), partArgs))
			table.insert(missingArgs, partArgs)
		end
	end
	if #missingParts > 0 then
		-- แจ้งทีละวัตถุดิบ: arg ยาวเกิน Notify.MaxArgLength จะถูกทิ้ง
		warn(`{LOG} {player.Name} BakeStart ปฏิเสธ: วัตถุดิบไม่พอสำหรับ {recipe.Id}: {table.concat(missingParts, ", ")}`)
		for _, partArgs in missingArgs do
			NotifyService.Notify(player, "BakeMissingIngredients", "error", partArgs)
		end
		return
	end

	local totalAfter = inventoryTotal(data) - ingredientTotal
	local currentDish = data.Inventory[recipe.Id] or 0
	if totalAfter + maxReward > Farm.InventoryCapacity or currentDish + maxReward > PlayerDataConfig.Limits.MaxItemCount then
		local args: { [string]: string | number } = { free = math.max(0, Farm.InventoryCapacity - totalAfter), need = maxReward }
		reject(player, "BakeStart", `กระเป๋าไม่พอรับขนม (หลังหัก {totalAfter}/{Farm.InventoryCapacity}, ต้องการ {maxReward})`, "BakeNoRoom", args)
		return
	end

	for _, id in ingredientIds do
		local left = (data.Inventory[id] or 0) - recipe.Ingredients[id]
		if left > 0 then
			data.Inventory[id] = left
		else
			data.Inventory[id] = nil
		end
	end
	freeOven.State = "Baking"
	freeOven.RecipeId = recipe.Id
	freeOven.OwnerUserId = player.UserId
	freeOven.OwnerName = player.DisplayName
	local bakeSeconds = recipe.BakeTimeSeconds * UpgradeService.GetMultiplier(player, UpgradeService.Ids.OvenSpeed)
	freeOven.ReadyAt = now + bakeSeconds
	freeOven.Minigame = nil
	freeOven.Grade = nil
	freeOven.Amount = nil
	beginWait(freeOven, now + bakeSeconds)

	broadcastOven(freeOven)
	sendInventory(player, data)
	local okArgs: { [string]: string | number } = { dish = dishName(player, recipe.Id), seconds = math.ceil(bakeSeconds) }
	NotifyService.Notify(player, "BakeStartOk", "success", okArgs)
end

local function onSync(player: Player)
	if not limiter:Check(player, "BakeSync") then
		return
	end
	local entries: { OvenEntry } = {}
	for _, oven in ovens do
		table.insert(entries, toEntry(oven))
	end
	stateEvent:FireClient(player, { Ovens = entries, Language = languageOf(player) })
end

-- DataService เรียกก่อนเซฟครั้งสุดท้ายของผู้เล่น (synchronous, ก่อน copyData) ทั้งตอนออกและ BindToClose
local function onBeforeSave(player: Player, data: PlayerData)
	local now = Workspace:GetServerTimeNow()
	for _, oven in ovens do
		if oven.State == "Idle" or oven.OwnerUserId ~= player.UserId then
			continue
		end
		local recipeId = oven.RecipeId
		local recipe = if recipeId then Recipes[recipeId] else nil
		if recipe == nil then
			warn(`{LOG} {player.Name} ออกขณะเตา {oven.Id} มีสูตรที่ไม่รู้จัก ({tostring(recipeId)}) เคลียร์เตาโดยไม่ให้ของ`)
		elseif oven.State == "Baking" and (oven.ReadyAt or 0) > now then
			for id, need in recipe.Ingredients do
				grantOnLeave(player, data, id, need, `ออกระหว่างอบ เตา {oven.Id}: คืนวัตถุดิบ`)
			end
		else
			-- เจ้าของโปรเจกต์ยืนยันแทนข้อ 7.1 เดิม: ออกตอนอบเสร็จ/Done ได้ตามระดับที่ทำได้จริง (Done ใช้ Amount ของระดับนั้น) ไม่ใช่ Good เสมอ
			local amount = if oven.State == "Done" and oven.Amount ~= nil
				then oven.Amount :: number
				else (Bake.ScoreRewards.Good or 0)
			grantOnLeave(player, data, recipe.Id, amount, `ออกหลังอบเสร็จ เตา {oven.Id}: ให้ขนม`)
		end
		resetOven(oven)
		broadcastOven(oven)
	end
end

-- ถ้า DataService ไม่ได้เรียก OnBeforeSave (โหมดชั่วคราว/เซสชันไม่ Active) เตาของคนที่ออกจะค้าง จึงเคลียร์ให้
local function onPlayerRemoving(player: Player)
	local userId = player.UserId
	task.delay(Bake.OrphanCleanupSeconds, function()
		if Players:GetPlayerByUserId(userId) ~= nil then
			return
		end
		for _, oven in ovens do
			if oven.OwnerUserId == userId and oven.State ~= "Idle" then
				warn(`{LOG} เตา {oven.Id} ของผู้เล่น {userId} ที่ออกไปไม่ได้ถูกเคลียร์ตอนเซฟ (ไม่มีข้อมูลให้เซฟ) เคลียร์เตาโดยไม่คืนของ`)
				resetOven(oven)
				broadcastOven(oven)
			end
		end
	end)
end

local function overlapsPlots(center: Vector3, size: Vector3): boolean
	local clearance = Bake.PlotClearanceStuds
	for _, plot in Farm.Plots do
		local overlapX = math.abs(center.X - plot.Position.X) < (size.X + Farm.PlotSize.X) / 2 + clearance
		local overlapZ = math.abs(center.Z - plot.Position.Z) < (size.Z + Farm.PlotSize.Z) / 2 + clearance
		if overlapX and overlapZ then
			return true
		end
	end
	return false
end

-- ตำแหน่งสถานี: อิง SpawnLocation ถ้าไม่มีหรือทับแปลงฟาร์มใช้พิกัดสำรอง (warn ทุกครั้ง)
local function placeStation(spec: Bake.StationSpec, anchor: Vector3?): (Vector3, string)
	if anchor then
		local position = Vector3.new(anchor.X + spec.SpawnOffsetXZ.X, anchor.Y + spec.Size.Y / 2, anchor.Z + spec.SpawnOffsetXZ.Y)
		if not overlapsPlots(position, spec.Size) then
			return position, "SpawnLocation"
		end
		warn(`{LOG} {spec.Name} ทับแปลงฟาร์มเมื่ออิง SpawnLocation ใช้พิกัดสำรอง`)
	end
	local fallback = Vector3.new(spec.FallbackXZ.X, Bake.FallbackGroundY + spec.Size.Y / 2, spec.FallbackXZ.Y)
	if overlapsPlots(fallback, spec.Size) then
		warn(`{LOG} {spec.Name} พิกัดสำรองทับแปลงฟาร์ม ตรวจ Config/Bake.luau`)
	end
	return fallback, "Fallback"
end

local function createStationPart(spec: Bake.StationSpec, anchor: Vector3?, kind: string, folder: Folder): (BasePart, string)
	local position, source = placeStation(spec, anchor)
	local part = Instance.new("Part")
	part.Name = spec.Name
	part.Anchored = true
	part.Size = spec.Size
	part.Position = position
	part.Color = spec.Color
	part.Material = spec.Material
	part:SetAttribute(Bake.KindAttribute, kind)

	local highlight = Instance.new("Highlight")
	highlight.FillColor = Bake.HighlightFillColor
	highlight.OutlineColor = Bake.HighlightOutlineColor
	highlight.FillTransparency = Bake.HighlightFillTransparency
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = part

	part.Parent = folder
	return part, `{spec.Name} ที่ ({position.X}, {position.Y}, {position.Z}) อิง {source}`
end

local function createStations()
	local existing = Workspace:FindFirstChild(Bake.FolderName)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = Bake.FolderName

	local anchor: Vector3? = nil
	local spawnLocation = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawnLocation then
		anchor = Vector3.new(spawnLocation.Position.X, spawnLocation.Position.Y - spawnLocation.Size.Y / 2, spawnLocation.Position.Z)
	else
		warn(`{LOG} ไม่พบ SpawnLocation ใน Workspace ใช้พิกัดสำรองของสถานี`)
	end

	local logLines: { string } = {}
	local mixing, mixingLog = createStationPart(Bake.Mixing, anchor, Bake.KindMixing, folder)
	mixingPart = mixing
	table.insert(logLines, mixingLog)

	for index, spec in Bake.Ovens do
		local part, line = createStationPart(spec, anchor, Bake.KindOven, folder)
		part:SetAttribute(Bake.OvenIdAttribute, index)
		ovenParts[index] = part
		ovens[index] = { Id = index, State = "Idle", WaitId = 0 }
		table.insert(logLines, line)
	end
	folder.Parent = Workspace
	print(`{LOG} สร้างสถานีแล้ว: {table.concat(logLines, " | ")}`)
end

function BakeService.Start()
	createStations()
	startEvent.OnServerEvent:Connect(onStart)
	collectEvent.OnServerEvent:Connect(onCollect)
	tapEvent.OnServerEvent:Connect(onTap)
	syncEvent.OnServerEvent:Connect(onSync)
	DataService.OnBeforeSave(onBeforeSave)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return BakeService
