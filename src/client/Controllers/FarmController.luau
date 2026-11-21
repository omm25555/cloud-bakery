--!strict
-- FarmController: แสดงสถานะแปลง (ว่าง / กำลังโต + เวลาเหลือ / พร้อมเก็บ), ProximityPrompt,
-- แถบเลือกพืช และป้ายกระเป๋าแบบเรียบง่าย
-- client ส่งได้แค่ "ขอปลูก/ขอเก็บ" server ตัดสินเสมอ เวลาที่แสดงคำนวณจาก ReadyAt ที่ server ส่งมา

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Crops = require(ReplicatedStorage.Shared.Config.Crops)
local Farm = require(ReplicatedStorage.Shared.Config.Farm)
local Ingredients = require(ReplicatedStorage.Shared.Config.Ingredients)
local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LOG = "[FarmController]"

type PlotView = {
	Id: number,
	Prompt: ProximityPrompt,
	Label: TextLabel,
	CropId: string?,
	ReadyAt: number?,
}

local FarmController = {}

local views: { [number]: PlotView } = {}
local connections: { RBXScriptConnection } = {}
local tickConnection: RBXScriptConnection? = nil
local cropButtons: { [string]: TextButton } = {}
local inventoryLabel: TextLabel? = nil
local inventory: { [string]: number } = {}
local language: string = PlayerDataConfig.DefaultLanguage
local selectedCrop: string = Farm.CropOrder[1]

local plantEvent: RemoteEvent
local harvestEvent: RemoteEvent

local function ingredientName(ingredientId: string): string
	local ingredient = Ingredients[ingredientId]
	if ingredient == nil then
		return ingredientId
	end
	return if language == "en" then ingredient.DisplayNameEn else ingredient.DisplayNameTh
end

local function cropName(cropId: string): string
	local crop = Crops[cropId]
	return ingredientName(if crop then crop.IngredientId else cropId)
end

local function refreshView(view: PlotView)
	local cropId = view.CropId
	local readyAt = view.ReadyAt
	local prompt = view.Prompt
	prompt.ObjectText = Strings.Format("UiPromptObject", language, nil)

	if cropId == nil or readyAt == nil then
		view.Label.Text = Strings.Format("UiPlotEmpty", language, nil)
		view.Label.TextColor3 = Farm.StateColors.Empty
		prompt.ActionText = Strings.Format("UiPromptPlant", language, { crop = cropName(selectedCrop) })
		return
	end

	prompt.ActionText = Strings.Format("UiPromptHarvest", language, nil)
	local remaining = readyAt - Workspace:GetServerTimeNow()
	if remaining > 0 then
		view.Label.Text = Strings.Format("UiPlotGrowing", language, { crop = cropName(cropId), seconds = math.ceil(remaining) })
		view.Label.TextColor3 = Farm.StateColors.Growing
	else
		view.Label.Text = Strings.Format("UiPlotReady", language, { crop = cropName(cropId) })
		view.Label.TextColor3 = Farm.StateColors.Ready
	end
end

local function hasGrowingPlot(): boolean
	local now = Workspace:GetServerTimeNow()
	for _, view in views do
		local readyAt = view.ReadyAt
		if view.CropId ~= nil and readyAt ~= nil and readyAt > now then
			return true
		end
	end
	return false
end

local function refreshAllViews()
	for _, view in views do
		refreshView(view)
	end
end

-- นับถอยหลังเฉพาะตอนมีแปลงกำลังโต เลิกฟัง Heartbeat เมื่อไม่มี
local function ensureTicker()
	if tickConnection ~= nil or not hasGrowingPlot() then
		return
	end
	local elapsed = 0
	tickConnection = RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < Farm.UiRefreshSeconds then
			return
		end
		elapsed = 0
		refreshAllViews()
		if not hasGrowingPlot() then
			local connection = tickConnection
			if connection then
				connection:Disconnect()
				tickConnection = nil
			end
		end
	end)
end

local function refreshInventory()
	local label = inventoryLabel
	if label == nil then
		return
	end
	local used = 0
	for _, count in inventory do
		used += count
	end
	local lines = { Strings.Format("UiInventoryTitle", language, { used = used, capacity = Farm.InventoryCapacity }) }
	local hasItems = false
	for _, cropId in Farm.CropOrder do
		local crop = Crops[cropId]
		local count = if crop then inventory[crop.IngredientId] else nil
		if crop and count and count > 0 then
			hasItems = true
			table.insert(lines, Strings.Format("UiInventoryItem", language, { name = ingredientName(crop.IngredientId), count = count }))
		end
	end
	if not hasItems then
		table.insert(lines, Strings.Format("UiInventoryEmpty", language, nil))
	end
	label.Text = table.concat(lines, "\n")
end

local function refreshCropButtons()
	for cropId, button in cropButtons do
		button.Text = cropName(cropId)
		button.BackgroundColor3 = if cropId == selectedCrop then Farm.CropButtonSelectedColor else Farm.CropButtonColor
	end
end

local function setLanguage(value: unknown)
	if type(value) == "string" and value ~= language then
		language = value :: string
		refreshAllViews()
		refreshInventory()
		refreshCropButtons()
	end
end

local function onFarmState(payload: unknown)
	if type(payload) ~= "table" then
		warn(`{LOG} FarmState payload ไม่ถูกต้อง ข้าม`)
		return
	end
	local data = payload :: { [string]: unknown }
	setLanguage(data.Language)

	local entries = data.Plots
	if type(entries) ~= "table" then
		warn(`{LOG} FarmState ไม่มี Plots ข้าม`)
		return
	end
	for _, rawEntry in entries :: { unknown } do
		if type(rawEntry) ~= "table" then
			continue
		end
		local entry = rawEntry :: { [string]: unknown }
		local plotId = entry.PlotId
		local cropId = entry.CropId
		local readyAt = entry.ReadyAt
		if type(plotId) ~= "number" then
			continue
		end
		local view = views[plotId :: number]
		if view == nil then
			continue
		end
		if type(cropId) == "string" and Crops[cropId :: string] ~= nil and type(readyAt) == "number" then
			view.CropId = cropId :: string
			view.ReadyAt = readyAt :: number
		else
			view.CropId = nil
			view.ReadyAt = nil
		end
		refreshView(view)
	end
	ensureTicker()
end

local function onInventoryUpdate(payload: unknown)
	if type(payload) ~= "table" then
		warn(`{LOG} InventoryUpdate payload ไม่ถูกต้อง ข้าม`)
		return
	end
	local data = payload :: { [string]: unknown }
	setLanguage(data.Language)
	local raw = data.Inventory
	if type(raw) ~= "table" then
		warn(`{LOG} InventoryUpdate ไม่มี Inventory ข้าม`)
		return
	end
	local clean: { [string]: number } = {}
	for id, count in raw :: { [unknown]: unknown } do
		if type(id) == "string" and type(count) == "number" then
			clean[id :: string] = count :: number
		end
	end
	inventory = clean
	refreshInventory()
end

local function createView(part: BasePart)
	local plotId = part:GetAttribute(Farm.PlotIdAttribute)
	if type(plotId) ~= "number" or views[plotId :: number] ~= nil then
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "PlotStatus"
	gui.Adornee = part
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(Farm.LabelWidthPixels, Farm.LabelHeightPixels)
	gui.StudsOffsetWorldSpace = Vector3.new(0, Farm.LabelOffsetStuds, 0)
	gui.MaxDistance = Farm.LabelMaxDistanceStuds
	gui.ResetOnSpawn = false

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Farm.LabelBackgroundColor
	label.BackgroundTransparency = Farm.LabelBackgroundTransparency
	label.TextWrapped = true
	label.Font = Farm.Font
	label.TextSize = Farm.LabelTextSize
	label.TextColor3 = Farm.TextColor
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Farm.LabelCornerRadiusPixels)
	corner.Parent = label

	local prompt = Instance.new("ProximityPrompt")
	prompt.MaxActivationDistance = Farm.InteractDistance
	prompt.HoldDuration = Farm.PromptHoldSeconds
	prompt.KeyboardKeyCode = Farm.PromptKeyCode
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	local id = plotId :: number
	local view: PlotView = { Id = id, Prompt = prompt, Label = label, CropId = nil, ReadyAt = nil }
	views[id] = view

	table.insert(
		connections,
		prompt.Triggered:Connect(function()
			if view.CropId == nil then
				plantEvent:FireServer(id, selectedCrop)
			else
				harvestEvent:FireServer(id)
			end
		end)
	)

	gui.Parent = part
	refreshView(view)
end

local function watchPlots()
	local folder = Workspace:WaitForChild(Farm.FolderName, Farm.ClientWaitSeconds)
	if folder == nil then
		warn(`{LOG} ไม่พบ Workspace.{Farm.FolderName} ไม่สามารถแสดงแปลงได้`)
		return
	end
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			createView(child)
		end
	end
	table.insert(
		connections,
		folder.ChildAdded:Connect(function(child: Instance)
			if child:IsA("BasePart") then
				createView(child)
			end
		end)
	)
end

local function createGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not playerGui:IsA("PlayerGui") then
		warn(`{LOG} ไม่พบ PlayerGui ไม่สามารถแสดงแถบเลือกพืชได้`)
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = Farm.GuiName
	gui.ResetOnSpawn = false
	gui.DisplayOrder = Farm.GuiDisplayOrder

	local bar = Instance.new("Frame")
	bar.Name = "CropBar"
	bar.BackgroundTransparency = 1
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -Farm.CropBarBottomOffsetPixels)
	bar.Size = UDim2.fromOffset(0, Farm.CropButtonHeightPixels)
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Farm.CropButtonSpacingPixels)
	layout.Parent = bar

	for order, cropId in Farm.CropOrder do
		local button = Instance.new("TextButton")
		button.Name = cropId
		button.LayoutOrder = order
		button.Size = UDim2.fromOffset(Farm.CropButtonWidthPixels, Farm.CropButtonHeightPixels)
		button.Font = Farm.Font
		button.TextSize = Farm.CropButtonTextSize
		button.TextColor3 = Farm.TextColor
		button.AutoButtonColor = true
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, Farm.CornerRadiusPixels)
		corner.Parent = button
		button.Parent = bar
		cropButtons[cropId] = button
		table.insert(
			connections,
			button.Activated:Connect(function()
				selectedCrop = cropId
				refreshCropButtons()
				refreshAllViews()
			end)
		)
	end

	local label = Instance.new("TextLabel")
	label.Name = "Inventory"
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0, Farm.InventoryOffsetPixels, 0.5, 0)
	label.Size = UDim2.fromOffset(Farm.InventoryWidthPixels, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundColor3 = Farm.InventoryBackgroundColor
	label.BackgroundTransparency = Farm.InventoryBackgroundTransparency
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Font = Farm.Font
	label.TextSize = Farm.InventoryTextSize
	label.TextColor3 = Farm.TextColor
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Farm.CornerRadiusPixels)
	corner.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, Farm.InventoryPaddingPixels)
	padding.PaddingBottom = UDim.new(0, Farm.InventoryPaddingPixels)
	padding.PaddingLeft = UDim.new(0, Farm.InventoryPaddingPixels)
	padding.PaddingRight = UDim.new(0, Farm.InventoryPaddingPixels)
	padding.Parent = label
	label.Parent = gui
	inventoryLabel = label

	gui.Parent = playerGui
	refreshCropButtons()
	refreshInventory()
end

local function cleanup()
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

function FarmController.Start()
	plantEvent = Remotes.GetEvent("FarmPlant")
	harvestEvent = Remotes.GetEvent("FarmHarvest")

	createGui()
	table.insert(connections, Remotes.GetEvent("FarmState").OnClientEvent:Connect(onFarmState))
	table.insert(connections, Remotes.GetEvent("InventoryUpdate").OnClientEvent:Connect(onInventoryUpdate))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player: Player)
			if player == Players.LocalPlayer then
				cleanup()
			end
		end)
	)

	-- Start ต้องไม่บล็อก bootstrap: รอแปลงใน thread แยก แล้วค่อยขอ snapshot
	task.spawn(function()
		watchPlots()
		Remotes.GetEvent("FarmSync"):FireServer()
	end)
end

return FarmController
