--!strict
-- ลูกค้าสัตว์และออเดอร์: เดินจากท่าบอลลูนมานั่งที่โต๊ะเสิร์ฟ มีหัวใจความอดทน ใครเสิร์ฟก่อนได้รางวัล
-- ออเดอร์เป็นของส่วนกลางทั้งเซิร์ฟเวอร์ (co-op แบบเบา)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = Shared.Config
local GameConfig = require(Config.Game)
local Customers = require(Config.Customers)
local Progression = require(Config.Progression)
local Formulas = require(Shared.Formulas)
local Locale = require(Shared.Locale)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local NotifyService = require(script.Parent.NotifyService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local QuestService = require(script.Parent.QuestService)
local WorldService = require(script.Parent.WorldService)
local RateLimiter = require(script.Parent.Parent.Modules.RateLimiter)

local SOURCE = "OrderService"

type Customer = {
	order: Types.Order,
	model: Model,
	root: BasePart,
	seatIndex: number,
	prompt: ProximityPrompt,
	bubble: TextLabel,
	leaving: boolean,
}

local OrderService = {}

local customers: { Customer } = {}
local seatTaken: { [number]: boolean } = {}
local nextOrderId = 0
local rng = Random.new()
local ordersEvent = Remotes.GetEvent("OrdersChanged")
local promptLimit = GameConfig.RateLimits.Prompt
local promptLimiter = RateLimiter.new(promptLimit.MaxCalls, promptLimit.WindowSeconds)
local npcFolder: Folder? = nil

local function bilingual(key: string): string
	return `{Locale.get("th", key)} ({Locale.get("en", key)})`
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function snapshot(): { Types.Order }
	local list: { Types.Order } = {}
	for _, customer in customers do
		if not customer.leaving then
			table.insert(list, customer.order)
		end
	end
	return list
end

local function broadcast()
	ordersEvent:FireAllClients(snapshot())
end

-- โมเดลสัตว์น่ารักจาก Part ล้วน (root anchored ส่วนอื่นเชื่อมด้วย WeldConstraint)
local function buildAnimal(animal: Customers.AnimalConfig, parent: Instance): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = animal.Id

	local function piece(name: string, size: Vector3, offset: Vector3, color: Color3, shape: Enum.PartType, anchorTo: BasePart?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Shape = shape
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CastShadow = true
		p.Anchored = anchorTo == nil
		p.CFrame = CFrame.new(offset)
		p.Parent = model
		if anchorTo then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = anchorTo
			weld.Part1 = p
			weld.Parent = p
		end
		return p
	end

	local body = piece("Body", Vector3.new(3, 3.2, 3), Vector3.new(0, 0, 0), animal.BodyColor, Enum.PartType.Ball, nil)
	piece("Head", Vector3.new(3, 2.8, 2.8), Vector3.new(0, 2.6, 0), animal.BodyColor, Enum.PartType.Ball, body)
	piece("Belly", Vector3.new(2, 2.2, 1), Vector3.new(0, -0.1, -1.1), animal.AccentColor, Enum.PartType.Ball, body)
	for _, side in { -1, 1 } do
		local earSize = if animal.EarShape == "Long" then Vector3.new(0.7, 2.6, 0.5) elseif animal.EarShape == "Pointy" then Vector3.new(0.9, 1.4, 0.4) else Vector3.new(1, 1, 0.5)
		local earY = if animal.EarShape == "Long" then 4.6 else 3.9
		local earShape = if animal.EarShape == "Round" then Enum.PartType.Ball else Enum.PartType.Block
		local earColor = if animal.Id == "Panda" then animal.AccentColor else animal.BodyColor
		piece("Ear", earSize, Vector3.new(side * 0.9, earY, 0), earColor, earShape, body)
		if animal.Id == "Panda" then
			piece("EyePatch", Vector3.new(0.8, 0.9, 0.3), Vector3.new(side * 0.6, 2.8, -1.3), animal.AccentColor, Enum.PartType.Ball, body)
		end
		piece("Eye", Vector3.new(0.35, 0.45, 0.2), Vector3.new(side * 0.55, 2.85, -1.42), Color3.fromRGB(35, 30, 40), Enum.PartType.Ball, body)
		piece("Cheek", Vector3.new(0.5, 0.3, 0.1), Vector3.new(side * 0.95, 2.3, -1.3), Color3.fromRGB(255, 170, 190), Enum.PartType.Ball, body)
		piece("Arm", Vector3.new(0.8, 1.4, 0.8), Vector3.new(side * 1.5, 0.1, -0.3), animal.BodyColor, Enum.PartType.Ball, body)
	end
	piece("Nose", Vector3.new(0.35, 0.25, 0.2), Vector3.new(0, 2.45, -1.45), Color3.fromRGB(60, 45, 50), Enum.PartType.Ball, body)
	if animal.Id == "Fox" then
		-- แว่นนักบิน
		for _, side in { -1, 1 } do
			piece("Goggle", Vector3.new(0.8, 0.8, 0.3), Vector3.new(side * 0.55, 3.55, -1.15), Color3.fromRGB(120, 200, 255), Enum.PartType.Ball, body)
		end
		piece("GoggleStrap", Vector3.new(3.05, 0.3, 2.85), Vector3.new(0, 3.55, 0), Color3.fromRGB(140, 90, 60), Enum.PartType.Block, body)
	elseif animal.Id == "Bunny" then
		-- หมวกฟาง
		local brim = piece("HatBrim", Vector3.new(0.2, 3.8, 3.8), Vector3.new(0, 3.85, 0), Color3.fromRGB(245, 215, 140), Enum.PartType.Cylinder, nil)
		brim.CFrame = CFrame.new(0, 3.85, 0) * CFrame.Angles(0, 0, math.rad(90))
		brim.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = brim
		weld.Parent = brim
		piece("HatTop", Vector3.new(2, 1, 2), Vector3.new(0, 4.3, 0), Color3.fromRGB(245, 215, 140), Enum.PartType.Ball, body)
	end
	model.PrimaryPart = body
	model.Parent = parent
	return model, body
end

local function makeBubble(root: BasePart): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "OrderBubble"
	gui.Size = UDim2.fromOffset(150, 56)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 6.4, 0)
	gui.MaxDistance = 90
	gui.Parent = root
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(255, 252, 245)
	label.TextColor3 = Color3.fromRGB(110, 70, 110)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = ""
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.35, 0)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 170, 205)
	stroke.Thickness = 2
	stroke.Parent = label
	return label
end

local function heartsText(hearts: number): string
	local text = ""
	for i = 1, Customers.HeartCount do
		text ..= if i <= hearts then Locale.icon("Heart") else Locale.icon("HeartEmpty")
	end
	return text
end

local function refreshBubble(customer: Customer, now: number)
	local order = customer.order
	local hearts = Formulas.hearts(now, order.createdAt, order.expiresAt)
	customer.bubble.Text = `{Locale.icon(order.recipeId)} x{order.amount}\n{heartsText(hearts)} {Locale.formatTime(order.expiresAt - now)}`
end

local function walkTo(root: BasePart, target: CFrame): Tween
	local distance = (root.Position - target.Position).Magnitude
	local duration = math.max(0.1, distance / Customers.WalkSpeedStudsPerSecond)
	local tween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = target })
	tween:Play()
	return tween
end

local function facing(from: Vector3, to: Vector3, height: number): CFrame
	local a = Vector3.new(from.X, height, from.Z)
	local b = Vector3.new(to.X, height, to.Z)
	if (b - a).Magnitude < 0.01 then
		return CFrame.new(a)
	end
	-- หน้าของโมเดลหันไปทาง -Z จึงใช้ lookAt ปกติ
	return CFrame.lookAt(a, b)
end

local function removeCustomer(customer: Customer)
	local index = table.find(customers, customer)
	if index then
		table.remove(customers, index)
	end
	seatTaken[customer.seatIndex] = nil
end

local function leave(customer: Customer, happy: boolean)
	if customer.leaving then
		return
	end
	customer.leaving = true
	customer.prompt.Enabled = false
	customer.bubble.Text = if happy then "💖" else "💧"
	broadcast()
	local stations = WorldService.getStations()
	local height = customer.root.Position.Y
	task.spawn(function()
		task.wait(Customers.LeaveDelaySeconds)
		local path = stations.customerPath
		local position = customer.root.Position
		for i = #path, 1, -1 do
			if customer.model.Parent == nil then
				break
			end
			local target = facing(position, path[i], height)
			local tween = walkTo(customer.root, CFrame.new(path[i].X, height, path[i].Z) * target.Rotation)
			tween.Completed:Wait()
			position = path[i]
		end
		removeCustomer(customer)
		customer.model:Destroy()
	end)
end

local function serve(player: Player, customer: Customer)
	if not promptLimiter.allow(player) then
		NotifyService.blocked(player, "n.tooFast")
		return
	end
	if customer.leaving then
		return
	end
	local order = customer.order
	if not order.seated then
		NotifyService.blocked(player, "n.customerNotSeated")
		return
	end
	local data = PlayerDataService.get(player)
	if data == nil then
		NotifyService.blocked(player, "n.loading")
		return
	end
	local have = data.goods[order.recipeId] or 0
	if have < order.amount then
		NotifyService.blocked(player, "n.notEnoughGoods", {
			animal = `animal.{order.animalId}`,
			recipe = `item.{order.recipeId}`,
			amount = order.amount,
			have = have,
		})
		return
	end
	local hearts = Formulas.hearts(serverNow(), order.createdAt, order.expiresAt)
	local coins = Formulas.serveCoins(order.recipeId, order.amount, hearts, Formulas.upgradeLevel(data.upgrades, "Counter"))
	local reputation = Customers.ReputationPerItem * order.amount
	-- กันเสิร์ฟซ้ำ: ตั้งสถานะออกก่อนให้รางวัล
	leave(customer, true)
	PlayerDataService.update(player, function(saved)
		saved.goods[order.recipeId] = math.max(0, (saved.goods[order.recipeId] or 0) - order.amount)
		saved.coins += coins
		saved.reputation += reputation
		saved.totalServed += 1
	end)
	QuestService.addProgress(player, "Serve", order.recipeId, 1)
	NotifyService.success(player, "n.served", { animal = `animal.{order.animalId}`, coins = coins, rep = reputation })
	NotifyService.all("info", "n.servedByOther", { player = player.DisplayName, animal = `animal.{order.animalId}` }, player)
end

local function highestLevel(): number
	local best = 1
	for _, player in Players:GetPlayers() do
		local data = PlayerDataService.get(player)
		if data then
			best = math.max(best, Formulas.levelInfo(data.reputation).level)
		end
	end
	return best
end

local function pickRecipe(): string
	local level = highestLevel()
	local options: { string } = {}
	for _, recipeId in Progression.RecipeOrder do
		if Formulas.isRecipeUnlocked(recipeId, level) then
			table.insert(options, recipeId)
		end
	end
	return options[rng:NextInteger(1, #options)]
end

local function freeSeat(): number?
	local stations = WorldService.getStations()
	local free: { number } = {}
	for index in stations.seats do
		if not seatTaken[index] then
			table.insert(free, index)
		end
	end
	if #free == 0 then
		return nil
	end
	return free[rng:NextInteger(1, #free)]
end

local function spawnCustomer()
	local seatIndex = freeSeat()
	local parent = npcFolder
	if seatIndex == nil or parent == nil then
		return
	end
	local stations = WorldService.getStations()
	local animalId = Customers.Order[rng:NextInteger(1, #Customers.Order)]
	local animal = Customers.Animals[animalId]
	local recipeId = pickRecipe()
	local range = Customers.AmountRange[recipeId] or { 1, 1 }
	local amount = rng:NextInteger(range[1], range[2])
	local createdAt = serverNow()
	local patience = rng:NextNumber(Customers.PatienceMinSeconds, Customers.PatienceMaxSeconds)
	nextOrderId += 1

	local model, root = buildAnimal(animal, parent)
	local height = 1.6 + root.Size.Y / 2
	local path = stations.customerPath
	root.CFrame = facing(path[1], path[2], height)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = bilingual("hud.serve")
	prompt.ObjectText = `{Locale.icon(animalId)} {bilingual(`animal.{animalId}`)} · {Locale.icon(recipeId)} x{amount}`
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = GameConfig.PromptMaxActivationDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = root

	local customer: Customer = {
		order = {
			id = nextOrderId,
			animalId = animalId,
			recipeId = recipeId,
			amount = amount,
			createdAt = createdAt,
			expiresAt = createdAt + patience,
			seated = false,
		},
		model = model,
		root = root,
		seatIndex = seatIndex,
		prompt = prompt,
		bubble = makeBubble(root),
		leaving = false,
	}
	seatTaken[seatIndex] = true
	table.insert(customers, customer)
	refreshBubble(customer, createdAt)

	prompt.Triggered:Connect(function(player: Player)
		local ok, err = pcall(function()
			serve(player, customer)
		end)
		if not ok then
			NotifyService.unexpected(SOURCE, player, `เสิร์ฟล้มเหลว: {err}`)
		end
	end)

	NotifyService.all("info", "n.customerArrived", { animal = `animal.{animalId}`, recipe = `item.{recipeId}`, amount = amount })
	broadcast()

	task.spawn(function()
		local position = path[1]
		for i = 2, #path do
			if customer.leaving then
				return
			end
			local tween = walkTo(root, CFrame.new(path[i].X, height, path[i].Z) * facing(position, path[i], height).Rotation)
			tween.Completed:Wait()
			position = path[i]
		end
		if customer.leaving then
			return
		end
		local seat = stations.seats[seatIndex]
		local seatTarget = CFrame.new(seat.Position.X, height, seat.Position.Z) * facing(position, seat.Position, height).Rotation
		walkTo(root, seatTarget).Completed:Wait()
		if customer.leaving then
			return
		end
		root.CFrame = CFrame.new(seat.Position.X, height + 0.4, seat.Position.Z) * seat.Rotation
		customer.order.seated = true
		prompt.Enabled = true
		broadcast()
	end)
end

function OrderService.Start()
	local stations = WorldService.getStations()
	local folderInstance = Instance.new("Folder")
	folderInstance.Name = "Customers"
	folderInstance.Parent = stations.root
	npcFolder = folderInstance

	Players.PlayerAdded:Connect(function(player: Player)
		ordersEvent:FireClient(player, snapshot())
	end)

	task.spawn(function()
		task.wait(Customers.FirstSpawnDelaySeconds)
		local lastSpawn = -math.huge
		while true do
			local now = os.clock()
			local active = 0
			for _, customer in customers do
				if not customer.leaving then
					active += 1
				end
			end
			if #Players:GetPlayers() > 0 and active < Customers.MaxActiveOrders and now - lastSpawn >= Customers.SpawnIntervalSeconds then
				local ok, err = pcall(function()
					spawnCustomer()
				end)
				if not ok then
					NotifyService.unexpected(SOURCE, nil, `สร้างลูกค้าล้มเหลว: {err}`)
				end
				lastSpawn = now
			end
			task.wait(GameConfig.WorldTimerRefreshSeconds)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(GameConfig.WorldTimerRefreshSeconds)
			local now = serverNow()
			for _, customer in table.clone(customers) do
				if not customer.leaving then
					if now >= customer.order.expiresAt then
						NotifyService.all("warn", "n.customerLeft", { animal = `animal.{customer.order.animalId}` })
						leave(customer, false)
					else
						refreshBubble(customer, now)
					end
				end
			end
		end
	end)
end

return OrderService
