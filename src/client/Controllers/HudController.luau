--!strict
-- HUD ตาม concept: เหรียญ + ชื่อเสียง (ขวาบน), ภารกิจวันนี้ (ซ้ายบน), ออเดอร์ (ขวา), สถานะเตาอบ (ซ้ายล่าง)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = Shared.Config
local Customers = require(Config.Customers)
local Quests = require(Config.Quests)
local Formulas = require(Shared.Formulas)
local Locale = require(Shared.Locale)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local UI = require(script.Parent.Parent.Modules.UI)
local StateController = require(script.Parent.StateController)
local NotifyController = require(script.Parent.NotifyController)

local HudController = {}

local REFRESH_SECONDS = 0.25
local ANIMAL_COLORS: { [string]: Color3 } = {
	Panda = Color3.fromRGB(235, 235, 245),
	Fox = Color3.fromRGB(255, 214, 180),
	Bunny = Color3.fromRGB(255, 220, 232),
}

type QuestRow = { check: TextLabel, title: TextLabel, sub: TextLabel, progress: TextLabel }

local gui: ScreenGui
local coinsLabel: TextLabel
local repLabel: TextLabel
local repLevel: TextLabel
local repSub: TextLabel
local repFill: Frame
local questTitle: TextLabel
local questSub: TextLabel
local questRows: { [string]: QuestRow } = {}
local rewardTitle: TextLabel
local claimButton: TextButton
local ordersTitle: TextLabel
local ordersSub: TextLabel
local ordersList: Frame
local ovenLabel: TextLabel
local unsavedLabel: TextLabel

local function buildCoins()
	local pill = UI.frame({
		name = "Coins",
		parent = gui,
		size = UDim2.fromOffset(210, 52),
		position = UDim2.new(1, -470, 0, 10),
		color = UI.Colors.Cream,
		radius = 26,
		stroke = UI.Colors.PurpleLight,
		strokeThickness = 3,
	})
	local coin = UI.frame({ name = "CoinIcon", parent = pill, size = UDim2.fromOffset(40, 40), position = UDim2.fromOffset(6, 6), color = UI.Colors.Gold, radius = 20, stroke = UI.Colors.GoldDark, strokeThickness = 3 })
	UI.label({ parent = coin, text = "★", size = UDim2.fromScale(1, 1), textSize = 22, color = UI.Colors.White, alignX = Enum.TextXAlignment.Center })
	coinsLabel = UI.label({ parent = pill, text = "0", size = UDim2.new(1, -100, 1, 0), position = UDim2.fromOffset(52, 0), textSize = 26 })
	local plus = UI.button({ parent = pill, text = "+", size = UDim2.fromOffset(38, 38), position = UDim2.new(1, -44, 0, 7), color = UI.Colors.Green, textSize = 28, radius = 19 })
	plus.Activated:Connect(function()
		NotifyController.show("info", "coming.soon")
	end)
end

local function buildReputation()
	local card = UI.frame({
		name = "Reputation",
		parent = gui,
		size = UDim2.fromOffset(240, 64),
		position = UDim2.new(1, -250, 0, 6),
		color = UI.Colors.Purple,
		radius = 18,
		stroke = UI.Colors.PurpleLight,
		strokeThickness = 3,
	})
	UI.label({ parent = card, text = Locale.icon("Star"), size = UDim2.fromOffset(46, 46), position = UDim2.fromOffset(6, 2), textSize = 34, alignX = Enum.TextXAlignment.Center })
	repLabel = UI.label({ parent = card, text = "0", size = UDim2.new(1, -60, 0, 26), position = UDim2.fromOffset(56, 2), textSize = 24, color = UI.Colors.White })
	repSub = UI.label({ parent = card, text = "", size = UDim2.new(1, -60, 0, 16), position = UDim2.fromOffset(56, 26), textSize = 13, color = UI.Colors.PinkLight, font = UI.FontBody })
	repLevel = UI.label({ parent = card, text = "Lv. 1", size = UDim2.fromOffset(56, 18), position = UDim2.fromOffset(6, 44), textSize = 15, color = UI.Colors.White, alignX = Enum.TextXAlignment.Center })
	local bar = UI.frame({ name = "Bar", parent = card, size = UDim2.new(1, -72, 0, 10), position = UDim2.fromOffset(62, 48), color = UI.Colors.Shadow, radius = 5 })
	repFill = UI.frame({ name = "Fill", parent = bar, size = UDim2.fromScale(0, 1), color = UI.Colors.Gold, radius = 5 })
end

local function buildQuests()
	local panel = UI.frame({
		name = "Quests",
		parent = gui,
		size = UDim2.fromOffset(310, 0),
		position = UDim2.fromOffset(12, 60),
		color = UI.Colors.Cream,
		radius = 18,
		stroke = UI.Colors.PurpleLight,
		strokeThickness = 3,
	})
	panel.AutomaticSize = Enum.AutomaticSize.Y
	UI.list(panel, 6)
	UI.padding(panel, 6)
	local header, title, sub = UI.header(panel, 46, "📋")
	header.LayoutOrder = 0
	questTitle = title
	questSub = sub
	for index, quest in Quests.Daily do
		local row = UI.frame({ name = quest.Id, parent = panel, size = UDim2.new(1, 0, 0, 44), color = UI.Colors.White, radius = 10 })
		row.LayoutOrder = index
		local box = UI.frame({ name = "Box", parent = row, size = UDim2.fromOffset(28, 28), position = UDim2.fromOffset(8, 8), color = UI.Colors.White, radius = 7, stroke = UI.Colors.PurpleLight, strokeThickness = 2 })
		local check = UI.label({ parent = box, text = "", size = UDim2.fromScale(1, 1), textSize = 20, color = UI.Colors.White, alignX = Enum.TextXAlignment.Center })
		local rowTitle = UI.label({ parent = row, text = "", size = UDim2.new(1, -110, 0, 24), position = UDim2.fromOffset(44, 2), textSize = 16, scaled = false })
		local rowSub = UI.label({ parent = row, text = "", size = UDim2.new(1, -110, 0, 14), position = UDim2.fromOffset(44, 25), textSize = 12, color = UI.Colors.TextSoft, font = UI.FontBody })
		local progress = UI.label({ parent = row, text = "0/0", size = UDim2.fromOffset(60, 44), position = UDim2.new(1, -64, 0, 0), textSize = 17, color = UI.Colors.Purple, alignX = Enum.TextXAlignment.Right })
		questRows[quest.Id] = { check = check, title = rowTitle, sub = rowSub, progress = progress }
	end
	local reward = UI.frame({ name = "Reward", parent = panel, size = UDim2.new(1, 0, 0, 44), color = UI.Colors.PinkLight, radius = 10 })
	reward.LayoutOrder = #Quests.Daily + 1
	rewardTitle = UI.label({ parent = reward, text = "", size = UDim2.new(1, -120, 1, 0), position = UDim2.fromOffset(10, 0), textSize = 16 })
	claimButton = UI.button({ parent = reward, text = "", size = UDim2.fromOffset(104, 34), position = UDim2.new(1, -110, 0, 5), color = UI.Colors.Green, textSize = 15 })
	claimButton.Activated:Connect(function()
		local ok, result = pcall(function()
			return Remotes.GetFunction("ClaimQuest"):InvokeServer()
		end)
		if not ok then
			warn(`[HudController] ขอรับรางวัลภารกิจไม่สำเร็จ: {result}`)
			NotifyController.show("error", "n.unexpected")
		end
	end)
end

local function buildOrders()
	local panel = UI.frame({
		name = "Orders",
		parent = gui,
		size = UDim2.fromOffset(290, 0),
		position = UDim2.new(1, -302, 0, 82),
		color = UI.Colors.Cream,
		radius = 18,
		stroke = UI.Colors.PurpleLight,
		strokeThickness = 3,
	})
	panel.AutomaticSize = Enum.AutomaticSize.Y
	UI.list(panel, 6)
	UI.padding(panel, 6)
	local header, title, sub = UI.header(panel, 46, "🛎️")
	header.LayoutOrder = 0
	ordersTitle = title
	ordersSub = sub
	ordersList = UI.frame({ name = "List", parent = panel, size = UDim2.new(1, 0, 0, 0), transparency = 1, radius = 0 })
	ordersList.AutomaticSize = Enum.AutomaticSize.Y
	ordersList.LayoutOrder = 1
	UI.list(ordersList, 6)
end

local function buildOvenChip()
	local chip = UI.frame({
		name = "OvenChip",
		parent = gui,
		size = UDim2.fromOffset(300, 44),
		position = UDim2.new(0, 12, 1, -56),
		color = UI.Colors.Cream,
		radius = 22,
		stroke = UI.Colors.Pink,
		strokeThickness = 3,
	})
	ovenLabel = UI.label({ parent = chip, text = "", size = UDim2.new(1, -20, 1, 0), position = UDim2.fromOffset(12, 0), textSize = 16 })
	unsavedLabel = UI.label({
		name = "Unsaved",
		parent = gui,
		text = "",
		size = UDim2.fromOffset(300, 20),
		position = UDim2.new(0, 14, 1, -80),
		textSize = 14,
		color = UI.Colors.Red,
	})
end

local function renderState(state: Types.PlayerState)
	local t = StateController.t
	coinsLabel.Text = UI.formatNumber(state.coins)
	repLabel.Text = UI.formatNumber(state.reputation)
	repSub.Text = t("hud.reputation")
	repLevel.Text = t("hud.level", { level = state.level })
	local progress = if state.levelCeil > 0
		then (state.reputation - state.levelFloor) / math.max(1, state.levelCeil - state.levelFloor)
		else 1
	repFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)

	questTitle.Text = t("hud.quests")
	questSub.Text = StateController.tOther("hud.quests")
	local allDone = true
	for _, quest in Quests.Daily do
		local row = questRows[quest.Id]
		local value = state.questProgress[quest.Id] or 0
		local done = value >= quest.Goal
		allDone = allDone and done
		row.title.Text = t(`quest.{quest.Id}`, { goal = quest.Goal })
		row.sub.Text = StateController.tOther(`quest.{quest.Id}`, { goal = quest.Goal })
		row.progress.Text = `{value}/{quest.Goal}`
		row.check.Text = if done then Locale.icon("Check") else ""
		local box = row.check.Parent
		if box and box:IsA("Frame") then
			box.BackgroundColor3 = if done then UI.Colors.Green else UI.Colors.White
		end
	end
	rewardTitle.Text = `{t("hud.reward")}: {Locale.icon("Coin")}x{Quests.RewardCoins}  {Locale.icon("Star")}x{Quests.RewardReputation}`
	if state.questClaimed then
		claimButton.Text = Locale.icon("Check")
		claimButton.BackgroundColor3 = UI.Colors.Disabled
	else
		claimButton.Text = t("hud.claim")
		claimButton.BackgroundColor3 = if allDone then UI.Colors.Green else UI.Colors.Disabled
	end

	ordersTitle.Text = t("hud.orders")
	ordersSub.Text = StateController.tOther("hud.orders")
	unsavedLabel.Text = if state.dataSaving then "" else `⚠️ {t("hud.unsaved")}`
end

local function heartsText(hearts: number): string
	local text = ""
	for i = 1, Customers.HeartCount do
		text ..= if i <= hearts then Locale.icon("Heart") else Locale.icon("HeartEmpty")
	end
	return text
end

type OrderCard = { frame: Frame, timer: TextLabel, hearts: TextLabel, order: Types.Order }
local orderCards: { OrderCard } = {}

local function renderOrders(orders: { Types.Order })
	UI.clear(ordersList)
	table.clear(orderCards)
	local t = StateController.t
	if #orders == 0 then
		local empty = UI.label({ parent = ordersList, text = t("hud.noOrders"), size = UDim2.new(1, 0, 0, 36), textSize = 15, color = UI.Colors.TextSoft, alignX = Enum.TextXAlignment.Center })
		empty.LayoutOrder = 1
		return
	end
	for index, order in orders do
		local card = UI.frame({ name = `Order{order.id}`, parent = ordersList, size = UDim2.new(1, 0, 0, 70), color = UI.Colors.White, radius = 12 })
		card.LayoutOrder = index
		local face = UI.frame({ parent = card, size = UDim2.fromOffset(58, 58), position = UDim2.fromOffset(6, 6), color = ANIMAL_COLORS[order.animalId] or UI.Colors.PinkLight, radius = 14 })
		UI.label({ parent = face, text = Locale.icon(order.animalId), size = UDim2.fromScale(1, 1), textSize = 38, alignX = Enum.TextXAlignment.Center })
		UI.label({ parent = card, text = t(`animal.{order.animalId}`), size = UDim2.new(1, -150, 0, 24), position = UDim2.fromOffset(72, 4), textSize = 17 })
		UI.label({ parent = card, text = `{Locale.icon(order.recipeId)} x{order.amount}  {t(`item.{order.recipeId}`)}`, size = UDim2.new(1, -80, 0, 22), position = UDim2.fromOffset(72, 28), textSize = 14, font = UI.FontBody })
		local hearts = UI.label({ parent = card, text = "", size = UDim2.fromOffset(80, 22), position = UDim2.new(1, -86, 0, 4), textSize = 14, alignX = Enum.TextXAlignment.Right })
		local timer = UI.label({ parent = card, text = "", size = UDim2.new(1, -80, 0, 18), position = UDim2.fromOffset(72, 50), textSize = 14, color = UI.Colors.Purple })
		table.insert(orderCards, { frame = card, timer = timer, hearts = hearts, order = order })
	end
end

local function tickOrders()
	local now = StateController.serverNow()
	local t = StateController.t
	for _, card in orderCards do
		local order = card.order
		card.hearts.Text = heartsText(Formulas.hearts(now, order.createdAt, order.expiresAt))
		if order.seated then
			card.timer.Text = `{Locale.icon("Timer")} {Locale.formatTime(order.expiresAt - now)}`
		else
			card.timer.Text = `🚶 {t("hud.walking")} · {Locale.icon("Timer")} {Locale.formatTime(order.expiresAt - now)}`
		end
	end
end

local function tickOven()
	local state = StateController.get()
	if state == nil then
		ovenLabel.Text = `{Locale.icon("Oven")} ...`
		return
	end
	local t = StateController.t
	local header = `{Locale.icon("Oven")} {t("station.Oven")} {#state.oven}/{state.ovenSlots}`
	if #state.oven == 0 then
		ovenLabel.Text = `{header} · {t("bag.ovenEmpty")}`
		ovenLabel.TextScaled = true
		return
	end
	ovenLabel.TextScaled = false
	local now = StateController.serverUnixTime()
	local soonest = math.huge
	local ready = 0
	for _, slot in state.oven do
		if slot.readyAt <= now then
			ready += 1
		else
			soonest = math.min(soonest, slot.readyAt - now)
		end
	end
	if ready > 0 then
		ovenLabel.Text = `{header} · ✅ {t("bag.ovenReady")}`
		ovenLabel.TextScaled = true
	else
		ovenLabel.Text = `{header} · {t("bag.ovenTime", { time = Locale.formatTime(soonest) })}`
	end
end

function HudController.Start()
	-- ซ่อนรายชื่อผู้เล่นของ Roblox ที่มุมขวาบน เพราะทับแผงเหรียญ/ชื่อเสียงตาม concept
	local ok, err = pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
	if not ok then
		warn(`[HudController] ซ่อน PlayerList ไม่สำเร็จ: {err}`)
	end
	gui = UI.screenGui("CloudBakeryHud", 5)
	buildCoins()
	buildReputation()
	buildQuests()
	buildOrders()
	buildOvenChip()

	StateController.onState(function(state: Types.PlayerState)
		renderState(state)
		renderOrders(StateController.getOrders())
		tickOven()
	end)
	StateController.onOrders(function(orders: { Types.Order })
		renderOrders(orders)
		tickOrders()
	end)

	task.spawn(function()
		while true do
			tickOrders()
			tickOven()
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return HudController
