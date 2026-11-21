--!strict
-- แถบปุ่มล่างขวา 6 ปุ่ม (Bag, Recipes, Upgrade, Pets, Decor, Settings) และหน้าต่างของแต่ละปุ่ม
-- Pets/Decor แสดงแต่ล็อกไว้ "เร็วๆ นี้" ตาม GDD

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = Shared.Config
local Progression = require(Config.Progression)
local Recipes = require(Config.Recipes)
local Upgrades = require(Config.Upgrades)
local Formulas = require(Shared.Formulas)
local Locale = require(Shared.Locale)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local UI = require(script.Parent.Parent.Modules.UI)
local StateController = require(script.Parent.StateController)
local NotifyController = require(script.Parent.NotifyController)

local MenuController = {}

local MENU_ITEMS = { "Bag", "Recipes", "Upgrade", "Pets", "Decor", "Settings" }
local LOCKED: { [string]: boolean } = { Pets = true, Decor = true }

local gui: ScreenGui
local menuLabels: { [string]: TextLabel } = {}
local upgradeDot: Frame
local openPanel: string? = nil
local panelFrame: Frame? = nil
local panelBody: ScrollingFrame? = nil
local panelTitle: TextLabel? = nil
local panelSub: TextLabel? = nil

local renderers: { [string]: (body: ScrollingFrame, state: Types.PlayerState) -> () } = {}

local function closePanel()
	local frame = panelFrame
	if frame then
		frame.Visible = false
	end
	openPanel = nil
end

local function ensurePanel(): (Frame, ScrollingFrame, TextLabel, TextLabel)
	local frame, body, title, sub = panelFrame, panelBody, panelTitle, panelSub
	if frame and body and title and sub then
		return frame, body, title, sub
	end
	local newFrame = UI.frame({
		name = "Panel",
		parent = gui,
		size = UDim2.fromOffset(560, 470),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = UI.Colors.Cream,
		radius = 22,
		stroke = UI.Colors.PurpleLight,
		strokeThickness = 4,
		zindex = 10,
	})
	UI.padding(newFrame, 8)
	local _, newTitle, newSub = UI.header(newFrame, 52, "")
	local close = UI.button({ parent = newFrame, text = "X", size = UDim2.fromOffset(40, 40), position = UDim2.new(1, -46, 0, 6), color = UI.Colors.Pink, textSize = 22, radius = 20 })
	close.Activated:Connect(closePanel)
	local newBody = Instance.new("ScrollingFrame")
	newBody.Name = "Body"
	newBody.Size = UDim2.new(1, 0, 1, -62)
	newBody.Position = UDim2.fromOffset(0, 60)
	newBody.BackgroundTransparency = 1
	newBody.BorderSizePixel = 0
	newBody.ScrollBarThickness = 6
	newBody.ScrollBarImageColor3 = UI.Colors.PurpleLight
	newBody.AutomaticCanvasSize = Enum.AutomaticSize.Y
	newBody.CanvasSize = UDim2.new()
	newBody.Parent = newFrame
	newFrame.Visible = false
	panelFrame, panelBody, panelTitle, panelSub = newFrame, newBody, newTitle, newSub
	return newFrame, newBody, newTitle, newSub
end

local function renderOpenPanel()
	local name = openPanel
	local state = StateController.get()
	if name == nil or state == nil then
		return
	end
	local frame, body, title, sub = ensurePanel()
	local header = frame:FindFirstChild("Header")
	local icon = if header then header:FindFirstChild("Icon") else nil
	if icon and icon:IsA("TextLabel") then
		icon.Text = Locale.icon(name)
	end
	title.Text = StateController.t(`menu.{name}`)
	sub.Text = StateController.tOther(`menu.{name}`)
	UI.clear(body)
	local layout = body:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout:Destroy()
	end
	UI.list(body, 8)
	local renderer = renderers[name]
	if renderer then
		renderer(body, state)
	end
end

local function open(name: string)
	if LOCKED[name] then
		NotifyController.show("info", "coming.soon")
		return
	end
	if openPanel == name then
		closePanel()
		return
	end
	openPanel = name
	local frame = ensurePanel()
	frame.Visible = true
	renderOpenPanel()
end

local function sectionTitle(body: ScrollingFrame, order: number, key: string)
	local label = UI.label({
		parent = body,
		text = `{StateController.t(key)}  {StateController.tOther(key)}`,
		size = UDim2.new(1, -10, 0, 28),
		textSize = 20,
		color = UI.Colors.Purple,
	})
	label.LayoutOrder = order
end

local function itemGrid(body: ScrollingFrame, order: number, ids: { string }, counts: Types.Counts)
	local grid = UI.frame({ name = "Grid", parent = body, size = UDim2.new(1, -10, 0, 0), transparency = 1, radius = 0 })
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = order
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(160, 64)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for index, id in ids do
		local cell = UI.frame({ parent = grid, size = UDim2.fromOffset(160, 64), color = UI.Colors.White, radius = 12 })
		cell.LayoutOrder = index
		UI.label({ parent = cell, text = Locale.icon(id), size = UDim2.fromOffset(54, 64), textSize = 32, alignX = Enum.TextXAlignment.Center })
		UI.label({ parent = cell, text = StateController.t(`item.{id}`), size = UDim2.new(1, -60, 0, 30), position = UDim2.fromOffset(54, 4), textSize = 14, wrap = true })
		UI.label({ parent = cell, text = `x{counts[id] or 0}`, size = UDim2.new(1, -60, 0, 26), position = UDim2.fromOffset(54, 34), textSize = 20, color = UI.Colors.Purple })
	end
end

renderers.Bag = function(body: ScrollingFrame, state: Types.PlayerState)
	sectionTitle(body, 1, "bag.ingredients")
	itemGrid(body, 2, Progression.IngredientOrder, state.ingredients)
	sectionTitle(body, 3, "bag.goods")
	itemGrid(body, 4, Progression.RecipeOrder, state.goods)
	sectionTitle(body, 5, "bag.oven")
	local now = StateController.serverUnixTime()
	if #state.oven == 0 then
		local empty = UI.label({ parent = body, text = StateController.t("bag.ovenEmpty"), size = UDim2.new(1, -10, 0, 28), textSize = 16, color = UI.Colors.TextSoft })
		empty.LayoutOrder = 6
	end
	for index, slot in state.oven do
		local remaining = slot.readyAt - now
		local status = if remaining <= 0 then StateController.t("bag.ovenReady") else StateController.t("bag.ovenTime", { time = Locale.formatTime(remaining) })
		local row = UI.label({
			parent = body,
			text = `{Locale.icon(slot.recipeId)} {StateController.t(`item.{slot.recipeId}`)} x{slot.pieces} · {status}`,
			size = UDim2.new(1, -10, 0, 28),
			textSize = 16,
		})
		row.LayoutOrder = 6 + index
	end
end

renderers.Recipes = function(body: ScrollingFrame, state: Types.PlayerState)
	for index, recipeId in Progression.RecipeOrder do
		local recipe = Recipes[recipeId]
		local unlocked = Formulas.isRecipeUnlocked(recipeId, state.level)
		local card = UI.frame({ parent = body, size = UDim2.new(1, -10, 0, 92), color = if unlocked then UI.Colors.White else UI.Colors.CreamDark, radius = 14 })
		card.LayoutOrder = index
		UI.label({ parent = card, text = if unlocked then Locale.icon(recipeId) else Locale.icon("Lock"), size = UDim2.fromOffset(80, 92), textSize = 46, alignX = Enum.TextXAlignment.Center })
		UI.label({ parent = card, text = `{StateController.t(`item.{recipeId}`)}  {StateController.tOther(`item.{recipeId}`)}`, size = UDim2.new(1, -90, 0, 26), position = UDim2.fromOffset(84, 6), textSize = 19 })
		local needs: { string } = {}
		for _, ingredientId in Progression.IngredientOrder do
			local need = recipe.Ingredients[ingredientId]
			if need then
				local have = state.ingredients[ingredientId] or 0
				local mark = if have >= need then "" else "❗"
				table.insert(needs, `{Locale.icon(ingredientId)} {have}/{need}{mark}`)
			end
		end
		UI.label({ parent = card, text = `{StateController.t("recipes.needs")}: {table.concat(needs, "   ")}`, size = UDim2.new(1, -90, 0, 22), position = UDim2.fromOffset(84, 34), textSize = 15, font = UI.FontBody })
		local info = if unlocked
			then `{StateController.t("recipes.price", { coins = recipe.SellPrice })} · {StateController.t("recipes.bakeTime", { seconds = Formulas.bakeSeconds(recipeId, Formulas.upgradeLevel(state.upgrades, "Oven")) })}`
			else StateController.t("recipes.locked", { level = Progression.RecipeUnlockLevel[recipeId] })
		UI.label({ parent = card, text = info, size = UDim2.new(1, -90, 0, 22), position = UDim2.fromOffset(84, 60), textSize = 14, color = UI.Colors.Purple, font = UI.FontBody })
	end
end

local function upgradeEffect(lineId: string, level: number): string
	if lineId == "Garden" then
		return StateController.t("upgrade.GardenEffect", { value = level * Upgrades.GardenYieldBonusPerLevel })
	elseif lineId == "Oven" then
		local percent = math.floor((1 - math.max(Upgrades.OvenMinTimeMultiplier, 1 - level * Upgrades.OvenSpeedBonusPerLevel)) * 100 + 0.5)
		return StateController.t("upgrade.OvenEffect", { value = percent, slots = Formulas.ovenSlots(level) })
	end
	return StateController.t("upgrade.CounterEffect", { value = math.floor(level * Upgrades.CounterTipBonusPerLevel * 100 + 0.5) })
end

renderers.Upgrade = function(body: ScrollingFrame, state: Types.PlayerState)
	for index, lineId in Upgrades.Order do
		local line = Upgrades.Lines[lineId]
		local level = Formulas.upgradeLevel(state.upgrades, lineId)
		local cost = Formulas.upgradeCost(lineId, level)
		local card = UI.frame({ parent = body, size = UDim2.new(1, -10, 0, 100), color = UI.Colors.White, radius = 14 })
		card.LayoutOrder = index
		UI.label({ parent = card, text = Locale.icon(lineId), size = UDim2.fromOffset(80, 100), textSize = 44, alignX = Enum.TextXAlignment.Center })
		UI.label({ parent = card, text = `{StateController.t(`upgrade.{lineId}`)}  {StateController.tOther(`upgrade.{lineId}`)}`, size = UDim2.new(1, -250, 0, 26), position = UDim2.fromOffset(84, 6), textSize = 18 })
		UI.label({ parent = card, text = StateController.t("upgrade.level", { level = level, max = #line.Costs }), size = UDim2.new(1, -250, 0, 20), position = UDim2.fromOffset(84, 34), textSize = 15, color = UI.Colors.Purple, font = UI.FontBody })
		local nextText = if cost then `→ {upgradeEffect(lineId, level + 1)}` else upgradeEffect(lineId, level)
		UI.label({ parent = card, text = nextText, size = UDim2.new(1, -250, 0, 36), position = UDim2.fromOffset(84, 56), textSize = 14, wrap = true, font = UI.FontBody, alignY = Enum.TextYAlignment.Top })
		local affordable = cost ~= nil and state.coins >= cost
		local buy = UI.button({
			parent = card,
			text = if cost then StateController.t("upgrade.buy", { coins = UI.formatNumber(cost) }) else StateController.t("upgrade.max"),
			size = UDim2.fromOffset(150, 50),
			position = UDim2.new(1, -160, 0.5, -25),
			color = if affordable then UI.Colors.Green else UI.Colors.Disabled,
			textSize = 16,
		})
		buy.Activated:Connect(function()
			local ok, result = pcall(function()
				return Remotes.GetFunction("RequestUpgrade"):InvokeServer(lineId)
			end)
			if not ok then
				warn(`[MenuController] ขออัปเกรด {lineId} ไม่สำเร็จ: {result}`)
				NotifyController.show("error", "n.unexpected")
			end
		end)
	end
end

renderers.Settings = function(body: ScrollingFrame, state: Types.PlayerState)
	sectionTitle(body, 1, "settings.language")
	local row = UI.frame({ parent = body, size = UDim2.new(1, -10, 0, 56), transparency = 1, radius = 0 })
	row.LayoutOrder = 2
	UI.list(row, 12, Enum.FillDirection.Horizontal)
	for index, info in { { id = "th", text = "ไทย" }, { id = "en", text = "English" } } do
		local selected = state.settings.language == info.id
		local button = UI.button({
			parent = row,
			text = if selected then `✔ {info.text}` else info.text,
			size = UDim2.fromOffset(170, 52),
			color = if selected then UI.Colors.Purple else UI.Colors.PurpleLight,
			textSize = 20,
		})
		button.LayoutOrder = index
		button.Activated:Connect(function()
			if not selected then
				Remotes.GetEvent("SetLanguage"):FireServer(info.id)
			end
		end)
	end
	local status = UI.label({
		parent = body,
		text = if state.dataSaving then `💾 {StateController.t("settings.saveOk")}` else `⚠️ {StateController.t("settings.saveOff")}`,
		size = UDim2.new(1, -10, 0, 50),
		textSize = 16,
		wrap = true,
		color = if state.dataSaving then UI.Colors.Text else UI.Colors.Red,
	})
	status.LayoutOrder = 3
end

local function buildMenuBar()
	local bar = UI.frame({
		name = "MenuBar",
		parent = gui,
		size = UDim2.fromOffset(6 * 84 + 5 * 8, 92),
		position = UDim2.new(1, -12, 1, -12),
		anchor = Vector2.new(1, 1),
		transparency = 1,
		radius = 0,
	})
	UI.list(bar, 8, Enum.FillDirection.Horizontal)
	for index, name in MENU_ITEMS do
		local button = UI.button({
			name = name,
			parent = bar,
			text = "",
			size = UDim2.fromOffset(84, 92),
			color = UI.Colors.Cream,
			radius = 22,
		})
		button.LayoutOrder = index
		UI.stroke(button, UI.Colors.PurpleLight, 3)
		UI.label({ parent = button, text = Locale.icon(name), size = UDim2.new(1, 0, 0, 52), position = UDim2.fromOffset(0, 4), textSize = 36, alignX = Enum.TextXAlignment.Center })
		menuLabels[name] = UI.label({ parent = button, text = name, size = UDim2.new(1, -4, 0, 30), position = UDim2.fromOffset(2, 56), textSize = 14, alignX = Enum.TextXAlignment.Center, wrap = true })
		if LOCKED[name] then
			button.BackgroundColor3 = UI.Colors.CreamDark
			UI.label({ parent = button, text = Locale.icon("Lock"), size = UDim2.fromOffset(26, 26), position = UDim2.new(1, -28, 0, 2), textSize = 16, alignX = Enum.TextXAlignment.Center })
		end
		if name == "Upgrade" then
			upgradeDot = UI.frame({ name = "Dot", parent = button, size = UDim2.fromOffset(22, 22), position = UDim2.new(1, -16, 0, -6), color = UI.Colors.Red, radius = 11, stroke = UI.Colors.White, strokeThickness = 2 })
			UI.label({ parent = upgradeDot, text = "!", size = UDim2.fromScale(1, 1), textSize = 16, color = UI.Colors.White, alignX = Enum.TextXAlignment.Center })
			upgradeDot.Visible = false
		end
		button.Activated:Connect(function()
			open(name)
		end)
	end
end

local function renderMenu(state: Types.PlayerState)
	for name, label in menuLabels do
		label.Text = StateController.t(`menu.{name}`)
	end
	local canUpgrade = false
	for _, lineId in Upgrades.Order do
		local cost = Formulas.upgradeCost(lineId, Formulas.upgradeLevel(state.upgrades, lineId))
		if cost and state.coins >= cost then
			canUpgrade = true
		end
	end
	upgradeDot.Visible = canUpgrade
	renderOpenPanel()
end

function MenuController.Start()
	gui = UI.screenGui("CloudBakeryMenu", 8)
	buildMenuBar()
	StateController.onState(renderMenu)
	-- รีเฟรชเวลาเตาอบในหน้ากระเป๋าขณะเปิดอยู่
	task.spawn(function()
		while true do
			task.wait(1)
			if openPanel == "Bag" then
				renderOpenPanel()
			end
		end
	end)
end

return MenuController
