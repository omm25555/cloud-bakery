--!strict
-- UpgradeController: ปุ่ม Upgrade (ล่างขวา) + แผงอัปเกรด 3 สาย + จุดแดงเมื่อมีสายที่ซื้อได้
-- client แสดงผลและส่งได้แค่ "อัปเกรดสายไหน" ราคา/เลเวล/เหรียญที่แท้จริง server เป็นผู้ตัดสิน
-- ปุ่มซื้อที่ปิดอยู่เป็นแค่ตัวช่วยผู้เล่น server ตรวจซ้ำทุกคำขอ

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UpgradeRules = require(ReplicatedStorage.Shared.UpgradeRules)

local LOG = "[UpgradeController]"

type Row = {
	LineId: string,
	Frame: Frame,
	NameLabel: TextLabel,
	DescLabel: TextLabel,
	LevelLabel: TextLabel,
	EffectLabel: TextLabel,
	BuyButton: TextButton,
}

local UpgradeController = {}

local connections: { RBXScriptConnection } = {}
local rows: { Row } = {}
local levels: { [string]: number } = {}
local coins = 0
local language = "th"
local stateKnown = false

local openButton: TextButton? = nil
local badge: Frame? = nil
local coinsLabel: TextLabel? = nil
local titleLabel: TextLabel? = nil
local closeButton: TextButton? = nil
local buyEvent: RemoteEvent? = nil

local function text(key: string, args: { [string]: string | number }?): string
	return Strings.Format(key, language, args)
end

local function addCorner(parent: Instance)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Upgrades.CornerRadiusPixels)
	corner.Parent = parent
end

local function addPadding(parent: Instance, pixels: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, pixels)
	padding.PaddingBottom = UDim.new(0, pixels)
	padding.PaddingLeft = UDim.new(0, pixels)
	padding.PaddingRight = UDim.new(0, pixels)
	padding.Parent = parent
end

local function makeLabel(parent: Instance, textSize: number, color: Color3, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Upgrades.Font
	label.TextSize = textSize
	label.TextColor3 = color
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

local function levelOf(lineId: string): number
	return levels[lineId] or 0
end

local function isBuyable(line: Upgrades.Line): boolean
	local cost = UpgradeRules.Cost(line, levelOf(line.Id) + 1)
	return stateKnown and cost ~= nil and coins >= cost
end

local function refresh()
	local anyBuyable = false
	for _, row in rows do
		local line = Upgrades.Lines[row.LineId]
		if line == nil then
			continue
		end
		local level = levelOf(row.LineId)
		local maxLevel = UpgradeRules.MaxLevel(line)
		local cost = UpgradeRules.Cost(line, level + 1)
		local buyable = isBuyable(line)
		if buyable then
			anyBuyable = true
		end

		row.NameLabel.Text = UpgradeRules.Name(line, language)
		row.DescLabel.Text = UpgradeRules.Desc(line, language)
		local levelArgs: { [string]: string | number } = { level = level, max = maxLevel }
		row.LevelLabel.Text = text("UiUpgradeLevel", levelArgs)
		local nowText = UpgradeRules.EffectText(line, level, language)
		if cost == nil then
			local maxArgs: { [string]: string | number } = { now = nowText }
			row.EffectLabel.Text = text("UiUpgradeEffectMax", maxArgs)
			row.BuyButton.Text = text("UiUpgradeMaxedButton", nil)
		else
			local changeArgs: { [string]: string | number } =
				{ now = nowText, next = UpgradeRules.EffectText(line, level + 1, language) }
			row.EffectLabel.Text = text("UiUpgradeEffectChange", changeArgs)
			local buyArgs: { [string]: string | number } = { cost = cost }
			row.BuyButton.Text = text("UiUpgradeBuy", buyArgs)
		end
		if not stateKnown then
			row.BuyButton.Text = text("UiUpgradeLoading", nil)
		end
		row.BuyButton.Active = buyable
		row.BuyButton.AutoButtonColor = buyable
		row.BuyButton.BackgroundColor3 = if buyable then Upgrades.BuyEnabledColor else Upgrades.BuyDisabledColor
	end

	local button = openButton
	if button then
		button.Text = text("UiUpgradeButton", nil)
	end
	local dot = badge
	if dot then
		dot.Visible = anyBuyable
	end
	local title = titleLabel
	if title then
		title.Text = text("UiUpgradeTitle", nil)
	end
	local close = closeButton
	if close then
		close.Text = text("UiUpgradeClose", nil)
	end
	local label = coinsLabel
	if label then
		local coinArgs: { [string]: string | number } = { coins = coins }
		label.Text = text("UiUpgradeCoins", coinArgs)
	end
end

local function onBuyClicked(lineId: string)
	local event = buyEvent
	if event == nil then
		return
	end
	local line = Upgrades.Lines[lineId]
	if line == nil or not isBuyable(line) then
		return
	end
	event:FireServer(lineId)
end

local function createRow(parent: Instance, line: Upgrades.Line, order: number): Row
	local frame = Instance.new("Frame")
	frame.Name = line.Id
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Upgrades.RowBackgroundColor
	frame.BorderSizePixel = 0
	addCorner(frame)
	addPadding(frame, Upgrades.RowPaddingPixels)
	frame.Parent = parent

	local buyButton = Instance.new("TextButton")
	buyButton.Name = "Buy"
	buyButton.AnchorPoint = Vector2.new(1, 0.5)
	buyButton.Position = UDim2.new(1, 0, 0.5, 0)
	buyButton.Size = UDim2.new(0, Upgrades.BuyButtonWidthPixels, 0, Upgrades.BuyButtonHeightPixels)
	buyButton.Font = Upgrades.Font
	buyButton.TextSize = Upgrades.BodyTextSize
	buyButton.TextColor3 = Upgrades.TextColor
	buyButton.BorderSizePixel = 0
	buyButton.Parent = frame
	addCorner(buyButton)

	local info = Instance.new("Frame")
	info.Name = "Info"
	info.BackgroundTransparency = 1
	info.Size = UDim2.new(1, -(Upgrades.BuyButtonWidthPixels + Upgrades.RowPaddingPixels), 0, 0)
	info.AutomaticSize = Enum.AutomaticSize.Y
	info.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Upgrades.RowSpacingPixels)
	layout.Parent = info

	local nameLabel = makeLabel(info, Upgrades.NameTextSize, Upgrades.TextColor, 1)
	local descLabel = makeLabel(info, Upgrades.BodyTextSize, Upgrades.SubTextColor, 2)
	local levelLabel = makeLabel(info, Upgrades.BodyTextSize, Upgrades.TextColor, 3)
	local effectLabel = makeLabel(info, Upgrades.BodyTextSize, Upgrades.SubTextColor, 4)

	local lineId = line.Id
	table.insert(
		connections,
		buyButton.Activated:Connect(function()
			onBuyClicked(lineId)
		end)
	)

	return {
		LineId = lineId,
		Frame = frame,
		NameLabel = nameLabel,
		DescLabel = descLabel,
		LevelLabel = levelLabel,
		EffectLabel = effectLabel,
		BuyButton = buyButton,
	}
end

local function createGui(playerGui: PlayerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name = Upgrades.GuiName
	gui.ResetOnSpawn = false
	gui.DisplayOrder = Upgrades.GuiDisplayOrder
	gui.Parent = playerGui

	-- ปุ่มอยู่ช่องที่ ButtonSlot จากซ้ายของแถวล่างขวา (ช่องทางขวาเว้นไว้ให้ปุ่มอื่นของ HUD)
	local slotsToRight = Upgrades.ButtonSlotCount - Upgrades.ButtonSlot
	local stride = Upgrades.ButtonWidthPixels + Upgrades.ButtonSpacingPixels
	local button = Instance.new("TextButton")
	button.Name = "UpgradeButton"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -(Upgrades.ButtonMarginPixels + slotsToRight * stride), 1, -Upgrades.ButtonMarginPixels)
	button.Size = UDim2.new(0, Upgrades.ButtonWidthPixels, 0, Upgrades.ButtonHeightPixels)
	button.BackgroundColor3 = Upgrades.ButtonColor
	button.BorderSizePixel = 0
	button.Font = Upgrades.Font
	button.TextSize = Upgrades.ButtonTextSize
	button.TextColor3 = Upgrades.TextColor
	button.Parent = gui
	addCorner(button)
	openButton = button

	local dot = Instance.new("Frame")
	dot.Name = "Badge"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.new(1, 0, 0, 0)
	dot.Size = UDim2.new(0, Upgrades.BadgeSizePixels, 0, Upgrades.BadgeSizePixels)
	dot.BackgroundColor3 = Upgrades.BadgeColor
	dot.BorderSizePixel = 0
	dot.Visible = false
	dot.ZIndex = 2
	dot.Parent = button
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot
	badge = dot

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -(Upgrades.ButtonMarginPixels + Upgrades.PanelBottomOffsetPixels))
	frame.Size = UDim2.new(Upgrades.PanelWidthScale, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Upgrades.PanelBackgroundColor
	frame.BackgroundTransparency = Upgrades.PanelBackgroundTransparency
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui
	addCorner(frame)
	addPadding(frame, Upgrades.PanelPaddingPixels)
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(Upgrades.PanelWidthPixels, math.huge)
	sizeLimit.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, Upgrades.PanelSpacingPixels)
	layout.Parent = frame

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, Upgrades.CloseButtonSizePixels)
	header.LayoutOrder = 0
	header.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -Upgrades.CloseButtonSizePixels, 1, 0)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Font = Upgrades.Font
	title.TextSize = Upgrades.TitleTextSize
	title.TextColor3 = Upgrades.TextColor
	title.Parent = header

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.Size = UDim2.new(0, Upgrades.CloseButtonSizePixels, 0, Upgrades.CloseButtonSizePixels)
	close.BackgroundColor3 = Upgrades.BuyDisabledColor
	close.BorderSizePixel = 0
	close.Font = Upgrades.Font
	close.TextSize = Upgrades.BodyTextSize
	close.TextColor3 = Upgrades.TextColor
	close.Parent = header
	addCorner(close)

	local coinsText = makeLabel(frame, Upgrades.BodyTextSize, Upgrades.SubTextColor, 1)
	coinsLabel = coinsText

	for index, id in Upgrades.Order do
		local line = Upgrades.Lines[id]
		if line then
			table.insert(rows, createRow(frame, line, index + 1))
		else
			warn(`{LOG} Config Order มี id ที่ไม่มีใน Lines: {id}`)
		end
	end

	table.insert(
		connections,
		button.Activated:Connect(function()
			frame.Visible = not frame.Visible
		end)
	)
	table.insert(
		connections,
		close.Activated:Connect(function()
			frame.Visible = false
		end)
	)

	titleLabel = title
	closeButton = close
end

local function onState(payload: unknown)
	if type(payload) ~= "table" then
		warn(`{LOG} UpgradeState ไม่ใช่ table ข้าม`)
		return
	end
	local data = payload :: { [string]: unknown }
	local incoming = data.Levels
	if type(incoming) == "table" then
		local clean: { [string]: number } = {}
		for key, value in incoming :: { [string]: unknown } do
			if type(key) == "string" and type(value) == "number" then
				clean[key] = value
			end
		end
		levels = clean
		stateKnown = true
	end
	if type(data.Language) == "string" then
		language = data.Language :: string
	end
	refresh()
end

local function onCurrency(payload: unknown)
	if type(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	if type(data.Coins) == "number" then
		coins = data.Coins :: number
		refresh()
	end
end

function UpgradeController.Start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	if not playerGui:IsA("PlayerGui") then
		warn(`{LOG} ไม่พบ PlayerGui ไม่สามารถแสดงแผงอัปเกรดได้`)
		return
	end

	buyEvent = Remotes.GetEvent("UpgradeBuy")
	createGui(playerGui)
	refresh()

	table.insert(connections, Remotes.GetEvent("UpgradeState").OnClientEvent:Connect(onState))
	table.insert(connections, Remotes.GetEvent("CurrencyUpdate").OnClientEvent:Connect(onCurrency))
	table.insert(
		connections,
		player.AncestryChanged:Connect(function()
			if player.Parent == nil then
				for _, connection in connections do
					connection:Disconnect()
				end
				table.clear(connections)
			end
		end)
	)

	-- ขอ snapshot (ไม่ส่ง argument) server รอข้อมูลโหลดแล้วส่งเลเวลและเหรียญมา
	Remotes.GetEvent("UpgradeSync"):FireServer()
end

return UpgradeController
