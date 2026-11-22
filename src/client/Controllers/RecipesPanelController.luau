--!strict
-- RecipesPanelController: แผง Recipes (อ่านอย่างเดียว) แสดงสูตรจาก Config/Recipes เทียบกับกระเป๋าของผู้เล่น
-- "มีพอ/ไม่พอ" เป็นแค่ตัวช่วยแสดงผล server ตรวจจริงตอนสั่งอบ เวลาอบเป็นค่า base (ยังไม่รวมอัปเกรด)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ingredients = require(ReplicatedStorage.Shared.Config.Ingredients)
local MenuConfig = require(ReplicatedStorage.Shared.Config.Menu)
local Recipes = require(ReplicatedStorage.Shared.Config.Recipes)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local MenuController = require(script.Parent.MenuController)

local LOG = "[RecipesPanelController]"

local RecipesPanelController = {}

local list: Frame? = nil

local function ingredientName(id: string, language: string): string
	local ingredient = Ingredients[id]
	if ingredient == nil then
		return id
	end
	return if language == "en" then ingredient.DisplayNameEn else ingredient.DisplayNameTh
end

-- เรียงวัตถุดิบตามลำดับใน Config/Menu เพื่อให้ลำดับคงที่ (id ที่ไม่อยู่ในลำดับไปท้ายสุดตามตัวอักษร)
local function sortedNeeds(needs: { [string]: number }): { string }
	local ids: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, id in MenuConfig.IngredientOrder do
		if needs[id] ~= nil then
			table.insert(ids, id)
			seen[id] = true
		end
	end
	local rest: { string } = {}
	for id in needs do
		if not seen[id] then
			table.insert(rest, id)
		end
	end
	table.sort(rest)
	for _, id in rest do
		table.insert(ids, id)
	end
	return ids
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
	if not state.InventoryKnown then
		local loading = MenuController.CreateLabel(container, MenuConfig.BodyTextSize, MenuConfig.TextColor, 1)
		loading.Text = Strings.Format("UiMenuLoading", state.Language, nil)
		return
	end

	for index, recipeId in MenuController.OrderIds(Recipes, MenuConfig.RecipeOrder) do
		local recipe = Recipes[recipeId]
		if recipe == nil then
			warn(`{LOG} ไม่พบสูตร {recipeId} ใน Config/Recipes`)
			continue
		end
		local card = MenuController.CreateColumn(container, index, true)
		local nameArgs: { [string]: string | number } = { nameTh = recipe.DisplayNameTh, nameEn = recipe.DisplayNameEn }
		local title = MenuController.CreateLabel(card, MenuConfig.BodyTextSize, MenuConfig.TextColor, 1)
		title.Text = Strings.Format("UiRecipeNameBoth", state.Language, nameArgs)

		local enough = true
		local order = 2
		for _, ingredientId in sortedNeeds(recipe.Ingredients) do
			local need = recipe.Ingredients[ingredientId] or 0
			local have = state.Inventory[ingredientId] or 0
			local ok = have >= need
			if not ok then
				enough = false
			end
			local needArgs: { [string]: string | number } =
				{ name = ingredientName(ingredientId, state.Language), need = need, have = have }
			local line = MenuController.CreateLabel(
				card,
				MenuConfig.SmallTextSize,
				if ok then MenuConfig.EnoughColor else MenuConfig.ShortColor,
				order
			)
			line.Text = Strings.Format("UiRecipeNeed", state.Language, needArgs)
			order += 1
		end

		local status = MenuController.CreateLabel(
			card,
			MenuConfig.BodyTextSize,
			if enough then MenuConfig.EnoughColor else MenuConfig.ShortColor,
			order
		)
		status.Text = Strings.Format(if enough then "UiRecipeEnough" else "UiRecipeShort", state.Language, nil)
		local timeArgs: { [string]: string | number } = { seconds = recipe.BakeTimeSeconds }
		local time = MenuController.CreateLabel(card, MenuConfig.SmallTextSize, MenuConfig.SubTextColor, order + 1)
		time.Text = Strings.Format("UiRecipeTime", state.Language, timeArgs)
	end
end

local function build(content: Frame)
	list = MenuController.CreateColumn(content, 1, false)
end

function RecipesPanelController.Start()
	MenuController.RegisterPanel({
		Id = MenuConfig.Ids.Recipes,
		TitleKey = "UiRecipesTitle",
		Build = build,
		Refresh = refresh,
	})
end

return RecipesPanelController
