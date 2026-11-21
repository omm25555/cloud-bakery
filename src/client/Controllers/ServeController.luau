--!strict
-- ServeController: ลูกค้า NPC (บล็อก), speech bubble, ProximityPrompt เสิร์ฟ และเหรียญ/Reputation แบบง่าย
-- client ส่งได้แค่ "เสิร์ฟออเดอร์ไหน" server ตัดสินทุกอย่าง เวลาที่แสดงคำนวณจาก ExpiresAt (เวลา server) ใช้แสดงผลเท่านั้น

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CustomersConfig = require(ReplicatedStorage.Shared.Config.Customers)
local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local Recipes = require(ReplicatedStorage.Shared.Config.Recipes)
local Serve = require(ReplicatedStorage.Shared.Config.Serve)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LOG = "[ServeController]"

type OrderData = {
	OrderId: number,
	CustomerId: string,
	RecipeId: string,
	Amount: number,
	ExpiresAt: number,
	Seat: number,
}

type CustomerView = {
	Order: OrderData,
	Model: Model,
	Parts: { BasePart },
	Prompt: ProximityPrompt,
	Trigger: RBXScriptConnection,
	Bubble: TextLabel,
	Leaving: boolean,
}

local ServeController = {}

local views: { [number]: CustomerView } = {}
local pendingOrders: { [number]: OrderData } = {}
local seatParts: { [number]: BasePart } = {}
local stationsReady = false
local connections: { RBXScriptConnection } = {}
local tickConnection: RBXScriptConnection? = nil
local language: string = PlayerDataConfig.DefaultLanguage
local currencyLabel: TextLabel? = nil
local coins = 0
local reputation = 0
local customersFolder: Folder? = nil
local serveEvent: RemoteEvent

local function dishName(recipeId: string): string
	local recipe = Recipes[recipeId]
	if recipe == nil then
		return recipeId
	end
	return if language == "en" then recipe.DisplayNameEn else recipe.DisplayNameTh
end

local function customerName(customerId: string): string
	local customer = CustomersConfig.Customers[customerId]
	if customer == nil then
		return customerId
	end
	return if language == "en" then customer.DisplayNameEn else customer.DisplayNameTh
end

local function heartsFor(ratio: number): number
	for _, tier in Serve.HeartTiers do
		if ratio >= tier.MinRatio then
			return tier.Hearts
		end
	end
	return 1
end

local function heartsText(hearts: number): string
	local maxHearts = 1
	for _, tier in Serve.HeartTiers do
		maxHearts = math.max(maxHearts, tier.Hearts)
	end
	return string.rep(Serve.HeartFull, hearts) .. string.rep(Serve.HeartEmpty, maxHearts - hearts)
end

local function formatTime(seconds: number): string
	local total = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", total // 60, total % 60)
end

local function refreshCurrency()
	local label = currencyLabel
	if label then
		local args: { [string]: string | number } = { coins = coins, reputation = reputation }
		label.Text = Strings.Format("UiServeCurrency", language, args)
	end
end

local function refreshView(view: CustomerView)
	local order = view.Order
	local remaining = order.ExpiresAt - Workspace:GetServerTimeNow()
	local ratio = math.clamp(remaining / Serve.OrderTimeSeconds, 0, 1)
	local args: { [string]: string | number } = {
		dish = dishName(order.RecipeId),
		amount = order.Amount,
		hearts = heartsText(heartsFor(ratio)),
		time = formatTime(remaining),
	}
	view.Bubble.Text = Strings.Format("UiServeBubble", language, args)
	view.Bubble.TextColor3 = if remaining <= Serve.UrgentSeconds then Serve.UrgentColor else Serve.BubbleTextColor
	view.Prompt.ObjectText = customerName(order.CustomerId)
	view.Prompt.ActionText = Strings.Format("UiServePromptAction", language, nil)
end

local function refreshAll()
	for _, view in views do
		refreshView(view)
	end
	refreshCurrency()
end

local function hasViews(): boolean
	return next(views) ~= nil
end

-- นับถอยหลังเฉพาะตอนมีลูกค้า เลิกฟัง Heartbeat เมื่อไม่มี
local function ensureTicker()
	if tickConnection ~= nil or not hasViews() then
		return
	end
	local elapsed = 0
	tickConnection = RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < Serve.UiRefreshSeconds then
			return
		end
		elapsed = 0
		for _, view in views do
			if not view.Leaving then
				refreshView(view)
			end
		end
		if not hasViews() then
			local connection = tickConnection
			if connection then
				connection:Disconnect()
				tickConnection = nil
			end
		end
	end)
end

local function fadeParts(parts: { BasePart }, target: number): Tween?
	local first: Tween? = nil
	local info = TweenInfo.new(Serve.FadeSeconds)
	for _, part in parts do
		local tween = TweenService:Create(part, info, { Transparency = target })
		tween:Play()
		if first == nil then
			first = tween
		end
	end
	return first
end

local function createBubble(adornee: BasePart): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "OrderBubble"
	gui.Adornee = adornee
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(Serve.BubbleWidthPixels, Serve.BubbleHeightPixels)
	gui.StudsOffsetWorldSpace = Vector3.new(0, adornee.Size.Y / 2 + Serve.BubbleOffsetStuds, 0)
	gui.MaxDistance = Serve.BubbleMaxDistanceStuds
	gui.ResetOnSpawn = false

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Serve.BubbleBackgroundColor
	label.BackgroundTransparency = Serve.BubbleBackgroundTransparency
	label.TextWrapped = true
	label.Font = Serve.Font
	label.TextSize = Serve.BubbleTextSize
	label.TextColor3 = Serve.BubbleTextColor
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Serve.BubbleCornerRadiusPixels)
	corner.Parent = label
	gui.Parent = adornee
	return label
end

local function createView(order: OrderData)
	local folder = customersFolder
	local seat = seatParts[order.Seat]
	local customer = CustomersConfig.Customers[order.CustomerId]
	if folder == nil or seat == nil or customer == nil or views[order.OrderId] ~= nil then
		warn(`{LOG} สร้างลูกค้าออเดอร์ {order.OrderId} ไม่ได้ (ช่อง {order.Seat} / ลูกค้า {order.CustomerId} ไม่พบ)`)
		return
	end

	local model = Instance.new("Model")
	model.Name = `{order.CustomerId}_{order.OrderId}`
	local baseY = seat.Position.Y + seat.Size.Y / 2

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Anchored = true
	body.CanCollide = false
	body.Size = customer.BodySize
	body.Color = customer.Color
	body.Material = Enum.Material.SmoothPlastic
	body.Position = Vector3.new(seat.Position.X, baseY + customer.BodySize.Y / 2, seat.Position.Z)
	body.Transparency = 1
	body.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Anchored = true
	head.CanCollide = false
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.one * Serve.CustomerHeadSize
	head.Color = customer.Color
	head.Material = Enum.Material.SmoothPlastic
	head.Position = body.Position + Vector3.new(0, customer.BodySize.Y / 2 + Serve.CustomerHeadOffsetStuds, 0)
	head.Transparency = 1
	head.Parent = model
	model.PrimaryPart = body

	local prompt = Instance.new("ProximityPrompt")
	prompt.MaxActivationDistance = Serve.InteractDistance
	prompt.HoldDuration = Serve.PromptHoldSeconds
	prompt.KeyboardKeyCode = Serve.PromptKeyCode
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	local orderId = order.OrderId
	local trigger = prompt.Triggered:Connect(function()
		serveEvent:FireServer(orderId)
	end)

	local bubble = createBubble(head)
	model.Parent = folder

	local parts: { BasePart } = { body, head }
	local view: CustomerView = {
		Order = order,
		Model = model,
		Parts = parts,
		Prompt = prompt,
		Trigger = trigger,
		Bubble = bubble,
		Leaving = false,
	}
	views[orderId] = view
	refreshView(view)
	fadeParts(parts, 0)
	ensureTicker()
end

local function removeView(orderId: number)
	pendingOrders[orderId] = nil
	local view = views[orderId]
	if view == nil then
		return
	end
	view.Leaving = true
	view.Trigger:Disconnect()
	view.Prompt.Enabled = false
	views[orderId] = nil
	local tween = fadeParts(view.Parts, 1)
	view.Bubble.Visible = false
	if tween then
		tween.Completed:Once(function()
			view.Model:Destroy()
		end)
	else
		view.Model:Destroy()
	end
end

local function readOrder(raw: unknown): OrderData?
	if type(raw) ~= "table" then
		return nil
	end
	local entry = raw :: { [string]: unknown }
	local orderId = entry.OrderId
	local customerId = entry.CustomerId
	local recipeId = entry.RecipeId
	local amount = entry.Amount
	local expiresAt = entry.ExpiresAt
	local seat = entry.Seat
	if
		type(orderId) ~= "number"
		or type(customerId) ~= "string"
		or type(recipeId) ~= "string"
		or type(amount) ~= "number"
		or type(expiresAt) ~= "number"
		or type(seat) ~= "number"
	then
		return nil
	end
	return {
		OrderId = orderId :: number,
		CustomerId = customerId :: string,
		RecipeId = recipeId :: string,
		Amount = amount :: number,
		ExpiresAt = expiresAt :: number,
		Seat = seat :: number,
	}
end

local function addOrder(order: OrderData)
	if views[order.OrderId] ~= nil then
		return
	end
	if stationsReady then
		createView(order)
	else
		pendingOrders[order.OrderId] = order
	end
end

local function onServeState(payload: unknown)
	if type(payload) ~= "table" then
		warn(`{LOG} ServeState payload ไม่ถูกต้อง ข้าม`)
		return
	end
	local data = payload :: { [string]: unknown }
	if type(data.Language) == "string" and data.Language ~= language then
		language = data.Language :: string
		refreshAll()
	end
	local kind = data.Type
	if kind == "Snapshot" then
		local entries = data.Orders
		if type(entries) ~= "table" then
			warn(`{LOG} ServeState Snapshot ไม่มี Orders ข้าม`)
			return
		end
		local seen: { [number]: boolean } = {}
		for _, raw in entries :: { unknown } do
			local order = readOrder(raw)
			if order then
				seen[order.OrderId] = true
				addOrder(order)
			end
		end
		local stale: { number } = {}
		for orderId in views do
			if not seen[orderId] then
				table.insert(stale, orderId)
			end
		end
		for _, orderId in stale do
			removeView(orderId)
		end
	elseif kind == "Add" then
		local order = readOrder(data.Order)
		if order then
			addOrder(order)
		end
	elseif kind == "Remove" then
		if type(data.OrderId) == "number" then
			removeView(data.OrderId :: number)
		end
	end
end

local function onCurrencyUpdate(payload: unknown)
	if type(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	if type(data.Coins) == "number" then
		coins = data.Coins :: number
	end
	if type(data.Reputation) == "number" then
		reputation = data.Reputation :: number
	end
	refreshCurrency()
end

local function onInventoryUpdate(payload: unknown)
	if type(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	if type(data.Language) == "string" and data.Language ~= language then
		language = data.Language :: string
		refreshAll()
	end
end

local function labelStation(part: BasePart, key: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "StationLabel"
	gui.Adornee = part
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(Serve.BubbleWidthPixels, Serve.NameTagHeightPixels)
	gui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + Serve.BubbleOffsetStuds, 0)
	gui.MaxDistance = Serve.BubbleMaxDistanceStuds
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Serve.BubbleBackgroundColor
	label.BackgroundTransparency = Serve.BubbleBackgroundTransparency
	label.Font = Serve.Font
	label.TextSize = Serve.BubbleTextSize
	label.TextColor3 = Serve.BubbleTextColor
	label.Text = Strings.Format(key, language, nil)
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Serve.BubbleCornerRadiusPixels)
	corner.Parent = label
	gui.Parent = part
end

local function registerStation(part: BasePart)
	local kind = part:GetAttribute(Serve.KindAttribute)
	if kind == Serve.KindCounter then
		labelStation(part, "UiServeCounterLabel")
	elseif kind == Serve.KindTable then
		labelStation(part, "UiServeTableLabel")
	elseif kind == Serve.KindSeat then
		local index = part:GetAttribute(Serve.SeatIndexAttribute)
		if type(index) == "number" then
			seatParts[index :: number] = part
		end
	end
end

local function watchStations()
	local folder = Workspace:WaitForChild(Serve.FolderName, Serve.ClientWaitSeconds)
	if folder == nil then
		warn(`{LOG} ไม่พบ Workspace.{Serve.FolderName} ไม่สามารถแสดงเคาน์เตอร์/ลูกค้าได้`)
		return
	end
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			registerStation(child)
		end
	end
	stationsReady = true
	local ready: { OrderData } = {}
	for _, order in pendingOrders do
		table.insert(ready, order)
	end
	table.clear(pendingOrders)
	for _, order in ready do
		createView(order)
	end
end

local function createGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not playerGui:IsA("PlayerGui") then
		warn(`{LOG} ไม่พบ PlayerGui ไม่สามารถแสดงเหรียญ/Reputation ได้`)
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = Serve.GuiName
	gui.ResetOnSpawn = false
	gui.DisplayOrder = Serve.GuiDisplayOrder

	local label = Instance.new("TextLabel")
	label.Name = "Currency"
	label.AnchorPoint = Vector2.new(1, 0)
	label.Position = UDim2.new(1, -Serve.CurrencyOffsetPixels, 0, Serve.CurrencyOffsetPixels)
	label.Size = UDim2.fromOffset(Serve.CurrencyWidthPixels, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundColor3 = Serve.CurrencyBackgroundColor
	label.BackgroundTransparency = Serve.CurrencyBackgroundTransparency
	label.Font = Serve.Font
	label.TextSize = Serve.CurrencyTextSize
	label.TextColor3 = Serve.TextColor
	label.TextWrapped = true
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Serve.CornerRadiusPixels)
	corner.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, Serve.CurrencyPaddingPixels)
	padding.PaddingBottom = UDim.new(0, Serve.CurrencyPaddingPixels)
	padding.PaddingLeft = UDim.new(0, Serve.CurrencyPaddingPixels)
	padding.PaddingRight = UDim.new(0, Serve.CurrencyPaddingPixels)
	padding.Parent = label

	gui.Parent = playerGui
	currencyLabel = label
	refreshCurrency()
end

local function cleanup()
	for _, view in views do
		view.Trigger:Disconnect()
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	local ticker = tickConnection
	if ticker then
		ticker:Disconnect()
		tickConnection = nil
	end
end

function ServeController.Start()
	serveEvent = Remotes.GetEvent("ServeOrder")

	local folder = Instance.new("Folder")
	folder.Name = "ServeCustomers"
	folder.Parent = Workspace
	customersFolder = folder

	createGui()
	table.insert(connections, Remotes.GetEvent("ServeState").OnClientEvent:Connect(onServeState))
	table.insert(connections, Remotes.GetEvent("CurrencyUpdate").OnClientEvent:Connect(onCurrencyUpdate))
	table.insert(connections, Remotes.GetEvent("InventoryUpdate").OnClientEvent:Connect(onInventoryUpdate))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player: Player)
			if player == Players.LocalPlayer then
				cleanup()
			end
		end)
	)

	-- Start ต้องไม่บล็อก bootstrap: รอสถานีใน thread แยก แล้วค่อยขอ snapshot
	task.spawn(function()
		watchStations()
		Remotes.GetEvent("ServeSync"):FireServer()
	end)
end

return ServeController
