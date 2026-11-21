--!strict
-- ServeService: ลูกค้า NPC + ออเดอร์ + เสิร์ฟ + เหรียญ/Reputation (ของรวมบนเกาะ co-op)
-- server ตัดสินทุกอย่าง: การสร้างออเดอร์ เวลา (GetServerTimeNow) การหักขนม เหรียญ และ Reputation
-- client ส่งได้แค่ "เสิร์ฟออเดอร์ไหน" / "ขอ snapshot" ออเดอร์และลูกค้าไม่ถูกบันทึก (Coins/Reputation เซฟผ่าน DataService)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Bake = require(ReplicatedStorage.Shared.Config.Bake)
local CustomersConfig = require(ReplicatedStorage.Shared.Config.Customers)
local Farm = require(ReplicatedStorage.Shared.Config.Farm)
local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local RateLimits = require(ReplicatedStorage.Shared.Config.RateLimits)
local Recipes = require(ReplicatedStorage.Shared.Config.Recipes)
local Serve = require(ReplicatedStorage.Shared.Config.Serve)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local NotifyService = require(script.Parent.NotifyService)

local LOG = "[ServeService]"

type PlayerData = PlayerDataConfig.PlayerData

type Order = {
	Id: number,
	CustomerId: string,
	RecipeId: string,
	Amount: number,
	CreatedAt: number,
	ExpiresAt: number,
	Served: boolean,
	Seat: number,
}

type OrderEntry = {
	OrderId: number,
	CustomerId: string,
	RecipeId: string,
	Amount: number,
	ExpiresAt: number,
	Seat: number,
}

type Box = { Center: Vector3, Size: Vector3 }

-- สร้าง remote ตอน require เพื่อให้ client หาเจอเสมอ ไม่ขึ้นกับลำดับ Start
-- (GetEvent คืน instance เดิมเมื่อเรียกชื่อซ้ำ จึงใช้ InventoryUpdate ร่วมกับ Farm/Bake ได้)
local orderEvent = Remotes.GetEvent("ServeOrder")
local syncEvent = Remotes.GetEvent("ServeSync")
local stateEvent = Remotes.GetEvent("ServeState")
local currencyEvent = Remotes.GetEvent("CurrencyUpdate")
local inventoryEvent = Remotes.GetEvent("InventoryUpdate")

local ServeService = {}

local orders: { [number]: Order } = {}
local seatOrders: { [number]: Order } = {}
local seatParts: { [number]: BasePart } = {}
local orderCounter = 0
local activeCount = 0
local random = Random.new()
local maxCustomers = math.min(Serve.MaxCustomers, #Serve.Seats)

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

local function dishName(language: string, recipeId: string): string
	local recipe = Recipes[recipeId]
	if recipe == nil then
		return recipeId
	end
	return if language == "en" then recipe.DisplayNameEn else recipe.DisplayNameTh
end

local function customerName(language: string, customerId: string): string
	local customer = CustomersConfig.Customers[customerId]
	if customer == nil then
		return customerId
	end
	return if language == "en" then customer.DisplayNameEn else customer.DisplayNameTh
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

local function sendInventory(player: Player, data: PlayerData)
	local copy: { [string]: number } = {}
	for id, count in data.Inventory do
		copy[id] = count
	end
	inventoryEvent:FireClient(player, { Inventory = copy, Language = data.Settings.Language })
end

local function sendCurrency(player: Player, data: PlayerData)
	currencyEvent:FireClient(player, { Coins = data.Coins, Reputation = data.Reputation })
end

local function toEntry(order: Order): OrderEntry
	return {
		OrderId = order.Id,
		CustomerId = order.CustomerId,
		RecipeId = order.RecipeId,
		Amount = order.Amount,
		ExpiresAt = order.ExpiresAt,
		Seat = order.Seat,
	}
end

-- แจ้งทุกคนบนเกาะ (ข้อความแปลตามภาษาของแต่ละคน)
local function notifyAll(key: string, kind: "info" | "success" | "error", build: (language: string) -> { [string]: string | number })
	for _, player in Players:GetPlayers() do
		NotifyService.Notify(player, key, kind, build(languageOf(player)))
	end
end

local function heartsFor(ratio: number): number
	for _, tier in Serve.HeartTiers do
		if ratio >= tier.MinRatio then
			return tier.Hearts
		end
	end
	return 1
end

local function readOrder(raw: unknown): Order?
	if type(raw) ~= "number" then
		return nil
	end
	local id = raw :: number
	if id ~= id or id ~= math.floor(id) then
		return nil
	end
	return orders[id]
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
	return (root.Position - part.Position).Magnitude <= Serve.InteractDistance + Serve.DistanceTolerance
end

-- เอาออเดอร์ออกจากระบบ (ไม่มี yield) แล้วบอกทุก client
local function removeOrder(order: Order, reason: string, servedBy: string?)
	if orders[order.Id] ~= order then
		return
	end
	orders[order.Id] = nil
	if seatOrders[order.Seat] == order then
		seatOrders[order.Seat] = nil
	end
	activeCount -= 1
	stateEvent:FireAllClients({ Type = "Remove", OrderId = order.Id, Reason = reason, ServedBy = servedBy })
end

local function expireOrder(order: Order)
	if orders[order.Id] ~= order or order.Served then
		return
	end
	removeOrder(order, "Expired", nil)
	print(`{LOG} ออเดอร์ {order.Id} ({order.CustomerId} {order.RecipeId} x{order.Amount}) หมดเวลา`)
	notifyAll("ServeOrderExpired", "error", function(language: string)
		return { customer = customerName(language, order.CustomerId) }
	end)

	local penalty = Serve.ExpirePenaltyReputation
	if penalty > 0 then
		for _, player in Players:GetPlayers() do
			local data = DataService.GetData(player)
			if data then
				data.Reputation = math.max(0, data.Reputation - penalty)
				sendCurrency(player, data)
				local args: { [string]: string | number } = { reputation = penalty }
				NotifyService.Notify(player, "ServeReputationLost", "error", args)
			end
		end
	end
end

local function pickCustomer(): string
	local free: { string } = {}
	for _, id in CustomersConfig.Order do
		local present = false
		for _, order in orders do
			if order.CustomerId == id then
				present = true
				break
			end
		end
		if not present and CustomersConfig.Customers[id] ~= nil then
			table.insert(free, id)
		end
	end
	if #free > 0 then
		return free[random:NextInteger(1, #free)]
	end
	return CustomersConfig.Order[random:NextInteger(1, #CustomersConfig.Order)]
end

local function createOrder(): Order?
	if activeCount >= maxCustomers or #CustomersConfig.Order == 0 or #Serve.RecipeIds == 0 then
		return nil
	end
	local seat: number? = nil
	for index = 1, maxCustomers do
		if seatOrders[index] == nil then
			seat = index
			break
		end
	end
	if seat == nil then
		return nil
	end
	local recipeId = Serve.RecipeIds[random:NextInteger(1, #Serve.RecipeIds)]
	if Recipes[recipeId] == nil then
		warn(`{LOG} สูตร {recipeId} ใน Serve.RecipeIds ไม่มีใน Recipes ข้ามการสร้างออเดอร์`)
		return nil
	end

	orderCounter += 1
	local now = Workspace:GetServerTimeNow()
	local order: Order = {
		Id = orderCounter,
		CustomerId = pickCustomer(),
		RecipeId = recipeId,
		Amount = random:NextInteger(Serve.ItemsPerOrderMin, Serve.ItemsPerOrderMax),
		CreatedAt = now,
		ExpiresAt = now + Serve.OrderTimeSeconds,
		Served = false,
		Seat = seat,
	}
	orders[order.Id] = order
	seatOrders[seat] = order
	activeCount += 1

	stateEvent:FireAllClients({ Type = "Add", Order = toEntry(order) })
	print(`{LOG} ลูกค้าใหม่ ออเดอร์ {order.Id}: {order.CustomerId} สั่ง {order.RecipeId} x{order.Amount} ที่ช่อง {seat}`)
	notifyAll("ServeNewCustomer", "info", function(language: string)
		return {
			customer = customerName(language, order.CustomerId),
			dish = dishName(language, order.RecipeId),
			amount = order.Amount,
		}
	end)

	local warnDelay = math.max(0, Serve.OrderTimeSeconds - Serve.WarnSecondsBeforeExpire)
	task.delay(warnDelay, function()
		if orders[order.Id] ~= order or order.Served then
			return
		end
		local seconds = math.max(1, math.ceil(order.ExpiresAt - Workspace:GetServerTimeNow()))
		notifyAll("ServeOrderWarn", "info", function(language: string)
			return {
				customer = customerName(language, order.CustomerId),
				dish = dishName(language, order.RecipeId),
				seconds = seconds,
			}
		end)
	end)
	task.delay(Serve.OrderTimeSeconds, function()
		expireOrder(order)
	end)
	return order
end

local function spawnLoop()
	task.wait(Serve.FirstSpawnDelaySeconds)
	while true do
		if activeCount < maxCustomers and #Players:GetPlayers() > 0 then
			createOrder()
		end
		task.wait(random:NextNumber(Serve.SpawnIntervalMin, Serve.SpawnIntervalMax))
	end
end

local function onServe(player: Player, orderIdRaw: unknown)
	if not limiter:Check(player, "ServeOrder") then
		return
	end
	if type(orderIdRaw) ~= "number" then
		reject(player, "ServeOrder", `orderId ไม่ใช่ number ({typeof(orderIdRaw)})`, "InvalidRequest", nil)
		return
	end
	local order = readOrder(orderIdRaw)
	if order == nil then
		reject(player, "ServeOrder", `ไม่มีออเดอร์ {tostring(orderIdRaw)} (เสิร์ฟแล้ว/หมดเวลา/id ผิด)`, "ServeOrderGone", nil)
		return
	end
	if order.Served then
		reject(player, "ServeOrder", `ออเดอร์ {order.Id} ถูกเสิร์ฟไปแล้ว`, "ServeOrderGone", nil)
		return
	end
	local now = Workspace:GetServerTimeNow()
	if now >= order.ExpiresAt then
		reject(player, "ServeOrder", `ออเดอร์ {order.Id} หมดเวลาแล้ว`, "ServeOrderGone", nil)
		expireOrder(order)
		return
	end
	local data = DataService.GetData(player)
	if data == nil then
		reject(player, "ServeOrder", "ข้อมูลผู้เล่นยังโหลดไม่เสร็จ", "DataNotReady", nil)
		return
	end
	if not isNear(player, seatParts[order.Seat]) then
		reject(player, "ServeOrder", `อยู่ไกลลูกค้าออเดอร์ {order.Id} เกินระยะ หรือไม่มีตัวละคร`, "ServeTooFar", nil)
		return
	end
	local recipe = Recipes[order.RecipeId]
	if recipe == nil then
		reject(player, "ServeOrder", `ออเดอร์ {order.Id} มีสูตรที่ไม่รู้จัก ({order.RecipeId})`, "UnknownError", nil)
		return
	end
	local have = data.Inventory[order.RecipeId] or 0
	if have < order.Amount then
		local language = data.Settings.Language
		local args: { [string]: string | number } = { dish = dishName(language, order.RecipeId), count = order.Amount - have }
		reject(player, "ServeOrder", `ขนมไม่พอสำหรับออเดอร์ {order.Id}: ต้องการ {order.RecipeId} x{order.Amount} มี {have}`, "ServeMissingItems", args)
		return
	end

	-- จากตรงนี้ถึงจบการให้รางวัลไม่มี yield: สองคนเสิร์ฟออเดอร์เดียวกันพร้อมกันไม่ได้ และเซฟพร้อมกันเสมอ
	local ratio = math.clamp((order.ExpiresAt - now) / Serve.OrderTimeSeconds, 0, 1)
	local hearts = heartsFor(ratio)
	local multiplier = Serve.HeartCoinMultiplier[hearts] or 1
	local coinGain = math.max(0, math.round(recipe.SellPrice * order.Amount * multiplier))
	local repGain = math.max(0, Serve.ReputationBase + (Serve.ReputationHeartBonus[hearts] or 0))

	local limits = PlayerDataConfig.Limits
	local newCoins = math.min(data.Coins + coinGain, limits.MaxCoins)
	local newReputation = math.min(data.Reputation + repGain, limits.MaxReputation)
	local coinsAdded = newCoins - data.Coins
	local repAdded = newReputation - data.Reputation

	order.Served = true
	local left = have - order.Amount
	if left > 0 then
		data.Inventory[order.RecipeId] = left
	else
		data.Inventory[order.RecipeId] = nil
	end
	data.Coins = newCoins
	data.Reputation = newReputation
	removeOrder(order, "Served", player.DisplayName)

	sendInventory(player, data)
	sendCurrency(player, data)
	local language = data.Settings.Language
	local okArgs: { [string]: string | number } = {
		dish = dishName(language, order.RecipeId),
		amount = order.Amount,
		customer = customerName(language, order.CustomerId),
		coins = coinsAdded,
		reputation = repAdded,
		hearts = hearts,
	}
	NotifyService.Notify(player, "ServeOk", "success", okArgs)
	if coinsAdded < coinGain then
		warn(`{LOG} {player.Name} เหรียญเต็มเพดาน {limits.MaxCoins} ได้ {coinsAdded}/{coinGain}`)
		local args: { [string]: string | number } = { coins = coinsAdded }
		NotifyService.Notify(player, "ServeCoinsCapped", "info", args)
	end
	if repAdded < repGain then
		warn(`{LOG} {player.Name} Reputation เต็มเพดาน {limits.MaxReputation} ได้ {repAdded}/{repGain}`)
		local args: { [string]: string | number } = { reputation = repAdded }
		NotifyService.Notify(player, "ServeReputationCapped", "info", args)
	end
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local otherLanguage = languageOf(other)
			local args: { [string]: string | number } =
				{ player = player.DisplayName, customer = customerName(otherLanguage, order.CustomerId) }
			NotifyService.Notify(other, "ServeServedBy", "info", args)
		end
	end
	print(`{LOG} {player.Name} เสิร์ฟออเดอร์ {order.Id} ({order.RecipeId} x{order.Amount}) หัวใจ {hearts} +{coinsAdded} เหรียญ +{repAdded} Reputation`)
end

-- ขอ snapshot ตอนเข้าเกม: ออเดอร์ทั้งหมด + เหรียญ/Reputation (รอข้อมูลโหลดก่อนส่งส่วนเหรียญ)
local function onSync(player: Player)
	if not limiter:Check(player, "ServeSync") then
		return
	end
	local entries: { OrderEntry } = {}
	for _, order in orders do
		table.insert(entries, toEntry(order))
	end
	stateEvent:FireClient(player, { Type = "Snapshot", Orders = entries, Language = languageOf(player) })

	task.spawn(function()
		local waited = 0
		local data = DataService.GetData(player)
		while data == nil and waited < Serve.SyncWaitSeconds and player.Parent == Players do
			task.wait(Serve.SyncPollSeconds)
			waited += Serve.SyncPollSeconds
			data = DataService.GetData(player)
		end
		if data == nil then
			warn(`{LOG} {player.Name} ServeSync: ข้อมูลไม่พร้อมภายใน {Serve.SyncWaitSeconds} วินาที ไม่ส่งเหรียญ/Reputation`)
			if player.Parent == Players then
				NotifyService.Notify(player, "DataNotReady", "error", nil)
			end
			return
		end
		sendCurrency(player, data)
		sendInventory(player, data)
	end)
end

local function boxOf(spec: Serve.StationSpec, anchor: Vector3?, useAnchor: boolean): Box
	if useAnchor and anchor then
		return {
			Center = Vector3.new(anchor.X + spec.SpawnOffsetXZ.X, anchor.Y + spec.Size.Y / 2, anchor.Z + spec.SpawnOffsetXZ.Y),
			Size = spec.Size,
		}
	end
	return {
		Center = Vector3.new(spec.FallbackXZ.X, Serve.FallbackGroundY + spec.Size.Y / 2, spec.FallbackXZ.Y),
		Size = spec.Size,
	}
end

local function boxesOverlap(a: Box, b: Box, clearance: number): boolean
	local overlapX = math.abs(a.Center.X - b.Center.X) < (a.Size.X + b.Size.X) / 2 + clearance
	local overlapZ = math.abs(a.Center.Z - b.Center.Z) < (a.Size.Z + b.Size.Z) / 2 + clearance
	return overlapX and overlapZ
end

-- สิ่งที่เคาน์เตอร์/โต๊ะเสิร์ฟ/ช่องยืนต้องไม่ทับ: แปลงฟาร์ม โต๊ะผสม เตาอบ (อ่านจาก Config เท่านั้น ไม่แตะ BakeService)
local function obstacleBoxes(anchor: Vector3?, useAnchor: boolean): { { Name: string, Box: Box } }
	local result: { { Name: string, Box: Box } } = {}
	for index, plot in Farm.Plots do
		table.insert(result, { Name = `Plot{index}`, Box = { Center = plot.Position, Size = Farm.PlotSize } })
	end
	table.insert(result, { Name = Bake.Mixing.Name, Box = boxOf(Bake.Mixing, anchor, useAnchor) })
	for _, oven in Bake.Ovens do
		table.insert(result, { Name = oven.Name, Box = boxOf(oven, anchor, useAnchor) })
	end
	return result
end

-- ตรวจทุกสถานีของเรา คืนชื่อสิ่งที่ทับ (nil = ไม่ทับ)
local function findOverlap(specs: { Serve.StationSpec }, anchor: Vector3?, useAnchor: boolean): string?
	local obstacles = obstacleBoxes(anchor, useAnchor)
	for _, spec in specs do
		local box = boxOf(spec, anchor, useAnchor)
		for _, obstacle in obstacles do
			if boxesOverlap(box, obstacle.Box, Serve.ClearanceStuds) then
				return `{spec.Name} ทับ {obstacle.Name}`
			end
		end
	end
	return nil
end

local function createPart(spec: Serve.StationSpec, box: Box, kind: string, folder: Folder): BasePart
	local part = Instance.new("Part")
	part.Name = spec.Name
	part.Anchored = true
	part.Size = spec.Size
	part.Position = box.Center
	part.Color = spec.Color
	part.Material = spec.Material
	part:SetAttribute(Serve.KindAttribute, kind)
	part.Parent = folder
	return part
end

local function createStations()
	local existing = Workspace:FindFirstChild(Serve.FolderName)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = Serve.FolderName

	local anchor: Vector3? = nil
	local spawnLocation = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawnLocation then
		anchor = Vector3.new(spawnLocation.Position.X, spawnLocation.Position.Y - spawnLocation.Size.Y / 2, spawnLocation.Position.Z)
	else
		warn(`{LOG} ไม่พบ SpawnLocation ใน Workspace ใช้พิกัดสำรองของสถานี`)
	end

	local specs: { Serve.StationSpec } = { Serve.Counter, Serve.ServingTable }
	for _, seat in Serve.Seats do
		table.insert(specs, seat)
	end

	local useAnchor = anchor ~= nil
	if useAnchor then
		local problem = findOverlap(specs, anchor, true)
		if problem then
			warn(`{LOG} {problem} เมื่ออิง SpawnLocation ใช้พิกัดสำรองทั้งชุด`)
			useAnchor = false
		end
	end
	if not useAnchor then
		local problem = findOverlap(specs, anchor, false)
		if problem then
			warn(`{LOG} พิกัดสำรอง: {problem} ตรวจ Config/Serve.luau`)
		end
	end

	local logLines: { string } = {}
	local function build(spec: Serve.StationSpec, kind: string): BasePart
		local box = boxOf(spec, anchor, useAnchor)
		local part = createPart(spec, box, kind, folder)
		table.insert(
			logLines,
			`{spec.Name} ที่ ({box.Center.X}, {box.Center.Y}, {box.Center.Z}) อิง {if useAnchor then "SpawnLocation" else "Fallback"}`
		)
		return part
	end
	build(Serve.Counter, Serve.KindCounter)
	build(Serve.ServingTable, Serve.KindTable)
	for index, spec in Serve.Seats do
		local part = build(spec, Serve.KindSeat)
		part:SetAttribute(Serve.SeatIndexAttribute, index)
		seatParts[index] = part
	end
	folder.Parent = Workspace
	print(`{LOG} สร้างสถานีแล้ว: {table.concat(logLines, " | ")}`)
end

function ServeService.Start()
	createStations()
	orderEvent.OnServerEvent:Connect(onServe)
	syncEvent.OnServerEvent:Connect(onSync)
	task.spawn(spawnLoop)
end

return ServeService
