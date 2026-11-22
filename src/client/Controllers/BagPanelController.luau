--!strict
-- BagPanelController: แผง Bag (อ่านอย่างเดียว) แสดงของในกระเป๋าและความจุ
-- ข้อมูลมาจาก server ผ่าน InventoryUpdate (MenuController เก็บไว้) ความจุอ่านจาก Config/Farm เพื่อแสดงผลเท่านั้น

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Farm = require(ReplicatedStorage.Shared.Config.Farm)
local Ingredients = require(ReplicatedStorage.Shared.Config.Ingredients)
local MenuConfig = require(ReplicatedStorage.Shared.Config.Menu)
local Recipes = require(ReplicatedStorage.Shared.Config.Recipes)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local MenuController = require(script.Parent.MenuController)

local LOG = "[BagPanelController]"

local BagPanelController = {}

local list: Frame? = nil
local warnedUnknown: { [string]: boolean } = {}

local function itemName(id: string, language: string): string?
	local ingredient = Ingredients[id]
	if ingredient then
		return if language == "en" then ingredient.DisplayNameEn else ingredient.DisplayNameTh
	end
	local recipe = Recipes[id]
	if recipe then
		return if language == "en" then recipe.DisplayNameEn else recipe.DisplayNameTh
	end
	return nil
end

local function addSection(parent: Frame, titleKey: string, ids: { string }, state: MenuController.State, order: number): number
	local lines: { string } = {}
	for _, id in ids do
		local count = state.Inventory[id]
		if count ~= nil and count > 0 then
			local args: { [string]: string | number } = { name = itemName(id, state.Language) or id, count = count }
			table.insert(lines, Strings.Format("UiInventoryItem", state.Language, args))
		end
	end
	if #lines == 0 then
		return order
	end
	local header = MenuController.CreateLabel(parent, MenuConfig.SmallTextSize, MenuConfig.SubTextColor, order)
	header.Text = Strings.Format(titleKey, state.Language, nil)
	local card = MenuController.CreateColumn(parent, order + 1, true)
	for index, line in lines do
		local label = MenuController.CreateLabel(card, MenuConfig.BodyTextSize, MenuConfig.TextColor, index)
		label.Text = line
	end
	return order + 2
end

local function refresh(state: MenuController.State)
	local container = list
	if container == nil then
		return
	end
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local summary = MenuController.CreateLabel(container, MenuConfig.BodyTextSize, MenuConfig.TextColor, 1)
	if not state.InventoryKnown then
		summary.Text = Strings.Format("UiMenuLoading", state.Language, nil)
		return
	end

	local used = 0
	local unknown: { string } = {}
	for id, count in state.Inventory do
		used += count
		if Ingredients[id] == nil and Recipes[id] == nil then
			table.insert(unknown, id)
			if not warnedUnknown[id] then
				warnedUnknown[id] = true
				warn(`{LOG} กระเป๋ามี id ที่ไม่รู้จัก ({id}) แสดงเป็น id ดิบ`)
			end
		end
	end
	table.sort(unknown)
	local capacityArgs: { [string]: string | number } = { used = used, capacity = Farm.InventoryCapacity }
	summary.Text = Strings.Format("UiBagCapacity", state.Language, capacityArgs)

	local ingredientIds = MenuController.OrderIds(Ingredients, MenuConfig.IngredientOrder)
	local recipeIds = MenuController.OrderIds(Recipes, MenuConfig.RecipeOrder)
	local order = addSection(container, "UiBagSectionIngredients", ingredientIds, state, 2)
	order = addSection(container, "UiBagSectionBakes", recipeIds, state, order)
	order = addSection(container, "UiBagSectionOther", unknown, state, order)
	if order == 2 then
		local empty = MenuController.CreateLabel(container, MenuConfig.BodyTextSize, MenuConfig.SubTextColor, 2)
		empty.Text = Strings.Format("UiBagEmpty", state.Language, nil)
	end
end

local function build(content: Frame)
	list = MenuController.CreateColumn(content, 1, false)
end

function BagPanelController.Start()
	MenuController.RegisterPanel({
		Id = MenuConfig.Ids.Bag,
		TitleKey = "UiMenuBag",
		Build = build,
		Refresh = refresh,
	})
end

return BagPanelController
