--!strict
-- OrdersPanelController: แผง Orders ด้านขวา (อ่านอย่างเดียว) การ์ดต่อออเดอร์ตาม ServeState
-- ข้อมูลมาจาก server เท่านั้น: ServeState (Snapshot/Add/Remove), InventoryUpdate (ขนมในกระเป๋า), SettingsState (ภาษา)
-- เวลาที่เหลือคำนวณจาก ExpiresAt (เวลา server) การเสิร์ฟยังทำที่ ProximityPrompt ของ ServeController
-- ไม่ยิง ServeSync เอง (HudController ยิงให้แล้ว) แค่ฟัง remote ที่ส่งถึง client ทุกตัว

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Bake = require(ReplicatedStorage.Shared.Config.Bake)
local CustomersConfig = require(ReplicatedStorage.Shared.Config.Customers)
local HudConfig = require(ReplicatedStorage.Shared.Config.Hud)
local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local Recipes = require(ReplicatedStorage.Shared.Config.Recipes)
local Serve = require(ReplicatedStorage.Shared.Config.Serve)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local HudRules = require(ReplicatedStorage.Shared.HudRules)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LOG = "[OrdersPanelController]"
local MINIGAME_FRAME_NAME = "Minigame" -- ชื่อ frame มินิเกมเตาอบใน BakeGui (ดูอย่างเดียว ไม่แก้)

type OrderData = {
	OrderId: number,
	CustomerId: string,
	RecipeId: string,
	Amount: number,
	ExpiresAt: number,
	Seat: number,
}

type Card = {
	Order: OrderData,
	Frame: Frame,
	Name: TextLabel,
	Timer: TextLabel,
	Dish: TextLabel,
	Hearts: TextLabel,
	Stock: TextLabel,
}

type PanelViews = {
	Gui: ScreenGui,
	Panel: Frame,
	Title: TextLabel,
	Toggle: TextButton,
	Scroll: ScrollingFrame,
	Layout: UIListLayout,
	Status: TextLabel,
}

local OrdersPanelController = {}

local connections: { RBXScriptConnection } = {}
local ui: PanelViews? = nil
local cards: { [number]: Card } = {}
local ordersLoaded = false
local inventory: { [string]: number }? = nil
local language: string = PlayerDataConfig.DefaultLanguage
local collapsed = false
local minigameVisible = false
local tickConnection: RBXScriptConnection? = nil
local loadWarnThread: thread? = nil

local function parseLanguage(value: unknown): string?
	if value == "th" or value == "en" then
		return value :: string
	end
	return nil
end

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

local function cardCount(): number
	local count = 0
	for _ in cards do
		count += 1
	end
	return count
end

-- ความสูงที่แผงใช้ได้: ไม่เกินพื้นที่เหนือแถวปุ่มล่างขวา (ขนาดปุ่มอ่านจาก Config/Upgrades)
local function updateScrollSize()
	local views = ui
	if views == nil then
		return
	end
	local top = HudConfig.MarginPixels
		+ HudConfig.CoinRowHeightPixels
		+ HudConfig.RowSpacingPixels
		+ HudConfig.RepRowHeightPixels
		+ HudConfig.RowSpacingPixels
	local bottomReserve = Upgrades.ButtonMarginPixels + Upgrades.ButtonHeightPixels + HudConfig.OrdersBottomGapPixels
	local available = views.Gui.AbsoluteSize.Y
		- top
		- HudConfig.OrdersHeaderHeightPixels
		- HudConfig.OrdersPaddingPixels * 3
		- bottomReserve
	local maxHeight = math.max(HudConfig.OrdersMinScrollHeightPixels, available)
	local wanted = math.min(views.Layout.AbsoluteContentSize.Y, maxHeight)
	views.Scroll.Size = UDim2.new(1, 0, 0, wanted)
end

local function refreshCard(card: Card)
	local order = card.Order
	local remaining = order.ExpiresAt - Workspace:GetServerTimeNow()
	local ratio = math.clamp(remaining / Serve.OrderTimeSeconds, 0, 1)
	local dishArgs: { [string]: string | number } = { dish = dishName(order.RecipeId), amount = order.Amount }
	card.Name.Text = customerName(order.CustomerId)
	card.Dish.Text = Strings.Format("UiOrdersDish", language, dishArgs)
	card.Hearts.Text = HudRules.HeartsText(HudRules.HeartsFor(ratio))
	card.Timer.Text = HudRules.FormatTime(remaining)
	card.Timer.TextColor3 = if remaining <= Serve.UrgentSeconds then Serve.UrgentColor else HudConfig.TextColor

	local bag = inventory
	if bag == nil then
		card.Stock.Text = ""
		return
	end
	local missing = order.Amount - (bag[order.RecipeId] or 0)
	if missing <= 0 then
		card.Stock.Text = Strings.Format("UiOrdersEnough", language, nil)
		card.Stock.TextColor3 = HudConfig.EnoughColor
	else
		local args: { [string]: string | number } = { missing = missing }
		card.Stock.Text = Strings.Format("UiOrdersShort", language, args)
		card.Stock.TextColor3 = HudConfig.ShortColor
	end
end

local function refreshChrome()
	local views = ui
	if views == nil then
		return
	end
	local count = cardCount()
	if ordersLoaded then
		local args: { [string]: string | number } = { count = count }
		views.Title.Text = Strings.Format("UiOrdersTitleCount", language, args)
	else
		views.Title.Text = Strings.Format("UiOrdersTitle", language, nil)
	end
	views.Toggle.Text = if collapsed then HudConfig.OrdersExpandGlyph else HudConfig.OrdersCollapseGlyph
	views.Scroll.Visible = not collapsed
	views.Panel.Visible = not minigameVisible

	if not ordersLoaded then
		views.Status.Text = Strings.Format("UiHudLoading", language, nil)
		views.Status.Visible = true
	elseif count == 0 then
		views.Status.Text = Strings.Format("UiOrdersEmpty", language, nil)
		views.Status.Visible = true
	else
		views.Status.Visible = false
	end
	updateScrollSize()
end

local function refreshAll()
	for _, card in cards do
		refreshCard(card)
	end
	refreshChrome()
end

-- เรียงตามเวลาที่เหลือน้อยสุดก่อน เสมอกันเรียงตามที่นั่ง (ExpiresAt คงที่ จึงเรียงใหม่เฉพาะตอนเพิ่ม/ลบ)
local function sortCards()
	local list: { Card } = {}
	for _, card in cards do
		table.insert(list, card)
	end
	table.sort(list, function(a: Card, b: Card): boolean
		if a.Order.ExpiresAt ~= b.Order.ExpiresAt then
			return a.Order.ExpiresAt < b.Order.ExpiresAt
		end
		return a.Order.Seat < b.Order.Seat
	end)
	for index, card in list do
		card.Frame.LayoutOrder = index
	end
end

local function stopTicker()
	local connection = tickConnection
	if connection ~= nil then
		connection:Disconnect()
		tickConnection = nil
	end
end

-- นับถอยหลังเฉพาะตอนมีการ์ด เลิกฟัง Heartbeat เมื่อไม่มี
local function ensureTicker()
	if tickConnection ~= nil or next(cards) == nil then
		return
	end
	local elapsed = 0
	tickConnection = RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < Serve.UiRefreshSeconds then
			return
		end
		elapsed = 0
		for _, card in cards do
			refreshCard(card)
		end
	end)
end

local function makeCardLabel(parent: Instance, name: string, alignment: Enum.TextXAlignment): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = HudConfig.Font
	label.TextSize = HudConfig.CardTextSize
	label.TextColor3 = HudConfig.TextColor
	label.TextXAlignment = alignment
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = parent
	return label
end

local function createCard(order: OrderData, scroll: ScrollingFrame): Card
	local frame = Instance.new("Frame")
	frame.Name = `Order{order.OrderId}`
	frame.Size = UDim2.new(1, 0, 0, HudConfig.CardHeightPixels)
	frame.BackgroundColor3 = HudConfig.CardColor
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, HudConfig.CardCornerRadiusPixels)
	corner.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, HudConfig.CardPaddingPixels)
	padding.PaddingBottom = UDim.new(0, HudConfig.CardPaddingPixels)
	padding.PaddingLeft = UDim.new(0, HudConfig.CardPaddingPixels)
	padding.PaddingRight = UDim.new(0, HudConfig.CardPaddingPixels)
	padding.Parent = frame

	-- บล็อกสีลูกค้า (placeholder ตามแผน art)
	local block = Instance.new("Frame")
	block.Name = "CustomerBlock"
	block.Size = UDim2.fromOffset(HudConfig.CardBlockSizePixels, HudConfig.CardBlockSizePixels)
	block.BorderSizePixel = 0
	local customer = CustomersConfig.Customers[order.CustomerId]
	block.BackgroundColor3 = if customer ~= nil then customer.Color else HudConfig.CardColor
	local blockCorner = Instance.new("UICorner")
	blockCorner.CornerRadius = UDim.new(0, HudConfig.CardCornerRadiusPixels)
	blockCorner.Parent = block
	block.Parent = frame

	local textX = HudConfig.CardBlockSizePixels + HudConfig.CardBlockGapPixels
	local line = HudConfig.CardLineHeightPixels
	local textWidth = UDim2.new(1, -textX, 0, line)

	local nameLabel = makeCardLabel(frame, "Name", Enum.TextXAlignment.Left)
	nameLabel.Position = UDim2.fromOffset(textX, 0)
	nameLabel.Size = UDim2.new(1 - HudConfig.TimerWidthScale, -textX, 0, line)

	local timerLabel = makeCardLabel(frame, "Timer", Enum.TextXAlignment.Right)
	timerLabel.AnchorPoint = Vector2.new(1, 0)
	timerLabel.Position = UDim2.fromScale(1, 0)
	timerLabel.Size = UDim2.new(HudConfig.TimerWidthScale, 0, 0, line)

	local dishLabel = makeCardLabel(frame, "Dish", Enum.TextXAlignment.Left)
	dishLabel.Position = UDim2.fromOffset(textX, line)
	dishLabel.Size = UDim2.new(1 - HudConfig.HeartsWidthScale, -textX, 0, line)

	local heartsLabel = makeCardLabel(frame, "Hearts", Enum.TextXAlignment.Right)
	heartsLabel.AnchorPoint = Vector2.new(1, 0)
	heartsLabel.Position = UDim2.new(1, 0, 0, line)
	heartsLabel.Size = UDim2.new(HudConfig.HeartsWidthScale, 0, 0, line)
	heartsLabel.TextColor3 = HudConfig.HeartColor

	local stockLabel = makeCardLabel(frame, "Stock", Enum.TextXAlignment.Left)
	stockLabel.Position = UDim2.fromOffset(textX, line * 2)
	stockLabel.Size = textWidth

	frame.Parent = scroll
	return {
		Order = order,
		Frame = frame,
		Name = nameLabel,
		Timer = timerLabel,
		Dish = dishLabel,
		Hearts = heartsLabel,
		Stock = stockLabel,
	}
end

local function removeCard(orderId: number)
	local card = cards[orderId]
	if card == nil then
		return
	end
	cards[orderId] = nil
	card.Frame:Destroy()
	if next(cards) == nil then
		stopTicker()
	end
end

local function addOrder(order: OrderData)
	local views = ui
	if views == nil or cards[order.OrderId] ~= nil then
		return
	end
	local card = createCard(order, views.Scroll)
	cards[order.OrderId] = card
	refreshCard(card)
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

local function onServeState(payload: unknown)
	if type(payload) ~= "table" then
		warn(`{LOG} ServeState payload ไม่ถูกต้อง ข้าม`)
		return
	end
	local data = payload :: { [string]: unknown }
	local newLanguage = parseLanguage(data.Language)
	if newLanguage ~= nil then
		language = newLanguage
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
		for orderId in cards do
			if not seen[orderId] then
				table.insert(stale, orderId)
			end
		end
		for _, orderId in stale do
			removeCard(orderId)
		end
		ordersLoaded = true
	elseif kind == "Add" then
		local order = readOrder(data.Order)
		if order then
			addOrder(order)
		end
	elseif kind == "Remove" then
		if type(data.OrderId) == "number" then
			removeCard(data.OrderId :: number)
		end
	end
	sortCards()
	ensureTicker()
	refreshAll()
end

local function onInventoryUpdate(payload: unknown)
	if type(payload) ~= "table" then
		warn(`{LOG} InventoryUpdate payload ไม่ถูกต้อง ข้าม`)
		return
	end
	local data = payload :: { [string]: unknown }
	local newLanguage = parseLanguage(data.Language)
	if newLanguage ~= nil then
		language = newLanguage
	end
	local raw = data.Inventory
	if type(raw) == "table" then
		local clean: { [string]: number } = {}
		for id, count in raw :: { [unknown]: unknown } do
			if type(id) == "string" and type(count) == "number" then
				clean[id :: string] = count :: number
			end
		end
		inventory = clean
	end
	refreshAll()
end

local function onSettingsState(payload: unknown)
	if type(payload) ~= "table" then
		warn(`{LOG} SettingsState payload ไม่ถูกต้อง ข้าม`)
		return
	end
	local newLanguage = parseLanguage((payload :: { [string]: unknown }).Language)
	if newLanguage == nil then
		warn(`{LOG} SettingsState Language ไม่ถูกต้อง ไม่เปลี่ยนภาษา`)
		return
	end
	language = newLanguage
	refreshAll()
end

local function createGui(): PanelViews?
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not playerGui:IsA("PlayerGui") then
		warn(`{LOG} ไม่พบ PlayerGui ไม่สามารถสร้างแผง Orders ได้`)
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = HudConfig.OrdersGuiName
	gui.ResetOnSpawn = false
	gui.DisplayOrder = HudConfig.OrdersGuiDisplayOrder

	local top = HudConfig.MarginPixels
		+ HudConfig.CoinRowHeightPixels
		+ HudConfig.RowSpacingPixels
		+ HudConfig.RepRowHeightPixels
		+ HudConfig.RowSpacingPixels
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -HudConfig.MarginPixels, 0, top)
	panel.Size = UDim2.new(HudConfig.OrdersWidthScale, 0, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = HudConfig.BackgroundColor
	panel.BackgroundTransparency = HudConfig.BackgroundTransparency
	panel.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, HudConfig.CornerRadiusPixels)
	corner.Parent = panel
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(HudConfig.MinWidthPixels, 0)
	sizeLimit.MaxSize = Vector2.new(HudConfig.MaxWidthPixels, math.huge)
	sizeLimit.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, HudConfig.OrdersPaddingPixels)
	padding.PaddingBottom = UDim.new(0, HudConfig.OrdersPaddingPixels)
	padding.PaddingLeft = UDim.new(0, HudConfig.OrdersPaddingPixels)
	padding.PaddingRight = UDim.new(0, HudConfig.OrdersPaddingPixels)
	padding.Parent = panel
	local panelLayout = Instance.new("UIListLayout")
	panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
	panelLayout.Padding = UDim.new(0, HudConfig.OrdersPaddingPixels)
	panelLayout.Parent = panel

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.LayoutOrder = 1
	header.Size = UDim2.new(1, 0, 0, HudConfig.OrdersHeaderHeightPixels)
	header.BackgroundTransparency = 1
	header.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -(HudConfig.OrdersToggleSizePixels + HudConfig.IconGapPixels), 1, 0)
	title.Font = HudConfig.Font
	title.TextSize = HudConfig.OrdersTitleTextSize
	title.TextColor3 = HudConfig.TextColor
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = header

	local toggle = Instance.new("TextButton")
	toggle.Name = "Toggle"
	toggle.AnchorPoint = Vector2.new(1, 0.5)
	toggle.Position = UDim2.fromScale(1, 0.5)
	toggle.Size = UDim2.fromOffset(HudConfig.OrdersToggleSizePixels, HudConfig.OrdersToggleSizePixels)
	toggle.BackgroundColor3 = HudConfig.OrdersToggleColor
	toggle.BorderSizePixel = 0
	toggle.Font = HudConfig.Font
	toggle.TextSize = HudConfig.OrdersTitleTextSize
	toggle.TextColor3 = HudConfig.TextColor
	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(0, HudConfig.CornerRadiusPixels)
	toggleCorner.Parent = toggle
	toggle.Parent = header

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.LayoutOrder = 2
	scroll.Size = UDim2.new(1, 0, 0, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = HudConfig.OrdersScrollBarThicknessPixels
	scroll.Parent = panel
	local scrollLayout = Instance.new("UIListLayout")
	scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
	scrollLayout.Padding = UDim.new(0, HudConfig.OrdersSpacingPixels)
	scrollLayout.Parent = scroll

	-- ข้อความสถานะ (กำลังโหลด / ยังไม่มีลูกค้า) อยู่ในพื้นที่เลื่อนก่อนการ์ดทั้งหมด
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.LayoutOrder = -1
	status.Size = UDim2.new(1, 0, 0, HudConfig.OrdersStatusHeightPixels)
	status.BackgroundTransparency = 1
	status.Font = HudConfig.Font
	status.TextSize = HudConfig.OrdersStatusTextSize
	status.TextColor3 = HudConfig.SubTextColor
	status.TextWrapped = true
	status.Parent = scroll

	panel.Parent = gui
	gui.Parent = playerGui
	return {
		Gui = gui,
		Panel = panel,
		Title = title,
		Toggle = toggle,
		Scroll = scroll,
		Layout = scrollLayout,
		Status = status,
	}
end

-- มินิเกมเตาอบอยู่กลางจอล่าง กว้าง 480px ถ้าจอแคบจะชนแผงนี้ จึงซ่อนแผงตอนมินิเกมเปิด (ดู Visible อย่างเดียว)
local function watchMinigame(playerGui: PlayerGui)
	local function attach(bakeGui: Instance)
		local frame = bakeGui:FindFirstChild(MINIGAME_FRAME_NAME, true)
		if frame == nil or not frame:IsA("GuiObject") then
			warn(`{LOG} ไม่พบ {MINIGAME_FRAME_NAME} ใน {Bake.GuiName} แผงจะไม่ซ่อนตอนอบ`)
			return
		end
		local function sync()
			minigameVisible = frame.Visible
			refreshChrome()
		end
		table.insert(connections, frame:GetPropertyChangedSignal("Visible"):Connect(sync))
		sync()
	end
	table.insert(
		connections,
		playerGui.ChildAdded:Connect(function(child: Instance)
			if child.Name == Bake.GuiName then
				task.defer(attach, child)
			end
		end)
	)
	local existing = playerGui:FindFirstChild(Bake.GuiName)
	if existing ~= nil then
		attach(existing)
	end
end

local function cleanup()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	stopTicker()
	local thread = loadWarnThread
	if thread ~= nil then
		task.cancel(thread)
		loadWarnThread = nil
	end
end

function OrdersPanelController.Start()
	local views = createGui()
	if views == nil then
		return
	end
	ui = views
	local player = Players.LocalPlayer

	table.insert(connections, views.Toggle.Activated:Connect(function()
		collapsed = not collapsed
		refreshChrome()
	end))
	table.insert(connections, views.Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateScrollSize))
	table.insert(connections, views.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScrollSize))
	table.insert(connections, Remotes.GetEvent("ServeState").OnClientEvent:Connect(onServeState))
	table.insert(connections, Remotes.GetEvent("InventoryUpdate").OnClientEvent:Connect(onInventoryUpdate))
	table.insert(connections, Remotes.GetEvent("SettingsState").OnClientEvent:Connect(onSettingsState))
	table.insert(
		connections,
		player.AncestryChanged:Connect(function()
			if player.Parent == nil then
				cleanup()
			end
		end)
	)
	refreshChrome()

	local playerGui = player:WaitForChild("PlayerGui")
	if playerGui:IsA("PlayerGui") then
		watchMinigame(playerGui)
	end

	-- ผู้เล่นแจ้งเตือนเรื่องข้อมูลไม่มาทำที่ HudController แผงนี้แค่ warn ฝั่ง dev
	loadWarnThread = task.delay(HudConfig.LoadTimeoutSeconds, function()
		loadWarnThread = nil
		if not ordersLoaded then
			warn(`{LOG} ไม่ได้รับรายการออเดอร์จาก server ภายใน {HudConfig.LoadTimeoutSeconds} วินาที`)
		end
	end)
end

return OrdersPanelController
