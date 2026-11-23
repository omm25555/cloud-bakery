--!strict
-- MenuController: แถบปุ่มล่างขวา (Bag, Recipes, Pets, Decor, Settings) + ตัวจัดการแผง "เปิดทีละแผง"
-- ปุ่ม Upgrade เป็นของ UpgradeController (ช่อง Upgrades.ButtonSlot) ที่นี่แค่เว้นช่องไว้ ไม่แตะ UpgradeGui
-- เก็บสถานะที่ทุกแผงใช้ร่วมกัน: ภาษา และกระเป๋า (มาจาก server ผ่าน InventoryUpdate เท่านั้น)
-- panel controller เรียก MenuController.RegisterPanel(...) ตอน Start เพื่อลงทะเบียนแผงของตัวเอง

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MenuConfig = require(ReplicatedStorage.Shared.Config.Menu)
local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LOG = "[MenuController]"

export type State = {
	Language: string,
	Inventory: { [string]: number },
	InventoryKnown: boolean, -- true เมื่อได้ข้อมูลกระเป๋าจาก server แล้ว
}

export type Panel = {
	Id: string,
	TitleKey: string,
	-- สร้างเนื้อหาแผง (เรียกครั้งเดียว) ใส่ของลงใน content
	Build: (content: Frame) -> (),
	-- วาดใหม่ตามสถานะล่าสุด (เรียกตอนสถานะเปลี่ยนและตอนเปิดแผง)
	Refresh: (state: State) -> (),
}

type PanelView = {
	Panel: Panel,
	Frame: Frame,
	Scroll: ScrollingFrame,
	Content: Frame,
	TitleLabel: TextLabel,
	SubTitleLabel: TextLabel,
	CloseButton: TextButton,
}

local MenuController = {}

local connections: { RBXScriptConnection } = {}
local state: State = {
	Language = PlayerDataConfig.DefaultLanguage,
	Inventory = {},
	InventoryKnown = false,
}
local root: ScreenGui? = nil
local buttons: { [string]: TextButton } = {}
local panelViews: { [string]: PanelView } = {}
local openPanelId: string? = nil
local lockedEvent: RemoteEvent? = nil

local function parseLanguage(value: string): string?
	if value == "th" or value == "en" then
		return value
	end
	return nil
end

local function text(key: string): string
	return Strings.Format(key, state.Language, nil)
end

local function otherLanguage(): string
	return if state.Language == "en" then "th" else "en"
end

local function addCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

function MenuController.GetState(): State
	return state
end

-- จำกัดความสูงแผงตามความสูงจอ: หัวการ์ดคงที่ เนื้อหาเลื่อนได้ในพื้นที่ที่เหลือ
local function updatePanelHeight(view: PanelView)
	local gui = root
	if gui == nil then
		return
	end
	local available = gui.AbsoluteSize.Y
		- Upgrades.ButtonMarginPixels
		- MenuConfig.PanelBottomOffsetPixels
		- MenuConfig.PanelTopMarginPixels
	local maxPanel = math.min(MenuConfig.PanelMaxHeightPixels, available)
	local maxScroll = math.max(maxPanel - MenuConfig.HeaderHeightPixels, MenuConfig.PanelMinScrollHeightPixels)
	local wanted = math.min(view.Content.AbsoluteSize.Y, maxScroll)
	view.Scroll.Size = UDim2.new(1, 0, 0, wanted)
end

local function refreshPanel(view: PanelView)
	view.TitleLabel.Text = text(view.Panel.TitleKey)
	view.SubTitleLabel.Text = Strings.Format(view.Panel.TitleKey, otherLanguage(), nil)
	view.CloseButton.Text = text("UiMenuClose")
	view.Panel.Refresh(state)
end

local function refreshAll()
	for id, button in buttons do
		for _, config in MenuConfig.Buttons do
			if config.Id == id then
				button.Text = text(config.ButtonKey)
			end
		end
	end
	for _, view in panelViews do
		refreshPanel(view)
	end
end

local function closePanels()
	openPanelId = nil
	for _, view in panelViews do
		view.Frame.Visible = false
	end
end

local function togglePanel(id: string)
	local view = panelViews[id]
	if view == nil then
		warn(`{LOG} ยังไม่มีแผง {id} ลงทะเบียน`)
		return
	end
	local wasOpen = openPanelId == id
	closePanels()
	if not wasOpen then
		openPanelId = id
		view.Frame.Visible = true
		refreshPanel(view)
		updatePanelHeight(view)
	end
end

local function slotPosition(slot: number): UDim2
	local slotsToRight = Upgrades.ButtonSlotCount - slot
	local stride = Upgrades.ButtonWidthPixels + Upgrades.ButtonSpacingPixels
	return UDim2.new(1, -(Upgrades.ButtonMarginPixels + slotsToRight * stride), 1, -Upgrades.ButtonMarginPixels)
end

local function createButtons(gui: ScreenGui)
	for _, config in MenuConfig.Buttons do
		if config.Slot == Upgrades.ButtonSlot then
			warn(`{LOG} ปุ่ม {config.Id} ใช้ช่อง {config.Slot} ซึ่งเป็นช่องของปุ่ม Upgrade ข้ามปุ่มนี้`)
			continue
		end
		local button = Instance.new("TextButton")
		button.Name = config.Id .. "Button"
		button.AnchorPoint = Vector2.new(1, 1)
		button.Position = slotPosition(config.Slot)
		button.Size = UDim2.new(0, Upgrades.ButtonWidthPixels, 0, Upgrades.ButtonHeightPixels)
		button.BackgroundColor3 = if config.Locked then MenuConfig.ButtonLockedColor else MenuConfig.ButtonColor
		button.BorderSizePixel = 0
		button.Font = MenuConfig.Font
		button.TextSize = MenuConfig.ButtonTextSize
		button.TextColor3 = MenuConfig.HeaderTextColor
		button.Text = text(config.ButtonKey)
		button.Parent = gui
		addCorner(button, MenuConfig.CornerRadiusPixels)
		buttons[config.Id] = button

		local id = config.Id
		local locked = config.Locked
		table.insert(
			connections,
			button.Activated:Connect(function()
				if locked then
					local event = lockedEvent
					if event then
						event:FireServer(id)
					end
					return
				end
				togglePanel(id)
			end)
		)
	end
end

-- สร้าง ScreenGui ฐานครั้งเดียว (เรียกซ้ำได้ ไม่ขึ้นกับลำดับ Start ของ controller อื่น)
local function ensureRoot(): ScreenGui?
	local existing = root
	if existing then
		return existing
	end
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	-- WaitForChild อาจ yield: ตรวจซ้ำก่อนสร้างเพื่อไม่ให้สร้างซ้ำ
	local again = root
	if again then
		return again
	end
	if not playerGui:IsA("PlayerGui") then
		warn(`{LOG} ไม่พบ PlayerGui ไม่สามารถแสดงแถบปุ่มได้`)
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = MenuConfig.GuiName
	gui.ResetOnSpawn = false
	gui.DisplayOrder = MenuConfig.GuiDisplayOrder
	gui.Parent = playerGui
	root = gui
	lockedEvent = Remotes.GetEvent("MenuLockedClick")
	createButtons(gui)
	return gui
end

local function createPanelFrame(gui: ScreenGui, panel: Panel): PanelView
	local frame = Instance.new("Frame")
	frame.Name = panel.Id .. "Panel"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -(Upgrades.ButtonMarginPixels + MenuConfig.PanelBottomOffsetPixels))
	frame.Size = UDim2.new(MenuConfig.PanelWidthScale, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = MenuConfig.PanelBackgroundColor
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ClipsDescendants = true
	frame.Parent = gui
	addCorner(frame, MenuConfig.CornerRadiusPixels)
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(MenuConfig.PanelWidthPixels, math.huge)
	sizeLimit.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.LayoutOrder = 0
	header.Size = UDim2.new(1, 0, 0, MenuConfig.HeaderHeightPixels)
	header.BackgroundColor3 = MenuConfig.HeaderColor
	header.BorderSizePixel = 0
	header.Parent = frame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.new(0, MenuConfig.PanelPaddingPixels, 0, 4)
	titleLabel.Size = UDim2.new(1, -(MenuConfig.CloseButtonSizePixels + MenuConfig.PanelPaddingPixels * 2), 0, 26)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Font = MenuConfig.Font
	titleLabel.TextSize = MenuConfig.TitleTextSize
	titleLabel.TextColor3 = MenuConfig.HeaderTextColor
	titleLabel.Parent = header

	local subTitleLabel = Instance.new("TextLabel")
	subTitleLabel.Name = "SubTitle"
	subTitleLabel.BackgroundTransparency = 1
	subTitleLabel.Position = UDim2.new(0, MenuConfig.PanelPaddingPixels, 0, 30)
	subTitleLabel.Size = UDim2.new(1, -(MenuConfig.CloseButtonSizePixels + MenuConfig.PanelPaddingPixels * 2), 0, 18)
	subTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	subTitleLabel.Font = MenuConfig.Font
	subTitleLabel.TextSize = MenuConfig.SubTitleTextSize
	subTitleLabel.TextColor3 = MenuConfig.HeaderSubTextColor
	subTitleLabel.Parent = header

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -MenuConfig.PanelPaddingPixels, 0.5, 0)
	close.Size = UDim2.new(0, MenuConfig.CloseButtonSizePixels, 0, MenuConfig.CloseButtonSizePixels)
	close.BackgroundColor3 = MenuConfig.CloseButtonColor
	close.BorderSizePixel = 0
	close.Font = MenuConfig.Font
	close.TextSize = MenuConfig.BodyTextSize
	close.TextColor3 = MenuConfig.HeaderTextColor
	close.Parent = header
	addCorner(close, MenuConfig.CornerRadiusPixels)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.LayoutOrder = 1
	scroll.Size = UDim2.new(1, 0, 0, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = MenuConfig.ScrollBarThicknessPixels
	scroll.ScrollBarImageColor3 = MenuConfig.ScrollBarColor
	scroll.Parent = frame

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, 0, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.BackgroundTransparency = 1
	content.Parent = scroll
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, MenuConfig.PanelPaddingPixels)
	padding.PaddingBottom = UDim.new(0, MenuConfig.PanelPaddingPixels)
	padding.PaddingLeft = UDim.new(0, MenuConfig.PanelPaddingPixels)
	padding.PaddingRight = UDim.new(0, MenuConfig.PanelPaddingPixels)
	padding.Parent = content

	panel.Build(content)

	local view: PanelView = {
		Panel = panel,
		Frame = frame,
		Scroll = scroll,
		Content = content,
		TitleLabel = titleLabel,
		SubTitleLabel = subTitleLabel,
		CloseButton = close,
	}
	table.insert(
		connections,
		close.Activated:Connect(function()
			closePanels()
		end)
	)
	table.insert(
		connections,
		content:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			updatePanelHeight(view)
		end)
	)
	table.insert(
		connections,
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			updatePanelHeight(view)
		end)
	)
	updatePanelHeight(view)
	return view
end

function MenuController.RegisterPanel(panel: Panel)
	if panelViews[panel.Id] ~= nil then
		warn(`{LOG} แผง {panel.Id} ลงทะเบียนซ้ำ ข้าม`)
		return
	end
	local gui = ensureRoot()
	if gui == nil then
		return
	end
	local view = createPanelFrame(gui, panel)
	panelViews[panel.Id] = view
	refreshPanel(view)
end

-- ตัวช่วยสร้าง UI ที่ทุกแผงใช้ร่วมกัน
function MenuController.CreateLabel(parent: Instance, textSize: number, color: Color3, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = MenuConfig.Font
	label.TextSize = textSize
	label.TextColor3 = color
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

-- กล่องแนวตั้งที่เรียงลูกตาม LayoutOrder (ใช้เป็นพื้นที่ของแผง หรือเป็นการ์ดหนึ่งรายการ)
function MenuController.CreateColumn(parent: Instance, order: number, filled: boolean): Frame
	local frame = Instance.new("Frame")
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BorderSizePixel = 0
	frame.Parent = parent
	if filled then
		frame.BackgroundColor3 = MenuConfig.RowBackgroundColor
		addCorner(frame, MenuConfig.CornerRadiusPixels)
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, MenuConfig.RowPaddingPixels)
		padding.PaddingBottom = UDim.new(0, MenuConfig.RowPaddingPixels)
		padding.PaddingLeft = UDim.new(0, MenuConfig.RowPaddingPixels)
		padding.PaddingRight = UDim.new(0, MenuConfig.RowPaddingPixels)
		padding.Parent = frame
	else
		frame.BackgroundTransparency = 1
	end
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, if filled then MenuConfig.RowSpacingPixels else MenuConfig.PanelSpacingPixels)
	layout.Parent = frame
	return frame
end

-- เรียง id ทั้งหมดใน known: ตาม preferred ก่อน แล้วต่อท้ายตัวที่เหลือเรียงตาม id (ไม่ทิ้ง id ใดเงียบ ๆ)
function MenuController.OrderIds<T>(known: { [string]: T }, preferred: { string }): { string }
	local ids: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, id in preferred do
		if known[id] ~= nil and not seen[id] then
			table.insert(ids, id)
			seen[id] = true
		end
	end
	local rest: { string } = {}
	for id in known do
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

local function onInventoryUpdate(payload: unknown)
	if type(payload) ~= "table" then
		warn(`{LOG} InventoryUpdate payload ไม่ถูกต้อง ข้าม`)
		return
	end
	local data = payload :: { [string]: unknown }
	if type(data.Language) == "string" then
		local language = parseLanguage(data.Language :: string)
		if language then
			state.Language = language
		else
			warn(`{LOG} InventoryUpdate Language ไม่ถูกต้อง ไม่เปลี่ยนภาษา`)
		end
	end
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
	state.Inventory = clean
	state.InventoryKnown = true
	refreshAll()
end

local function onSettingsState(payload: unknown)
	if type(payload) ~= "table" then
		warn(`{LOG} SettingsState payload ไม่ถูกต้อง ข้าม`)
		return
	end
	local language = (payload :: { [string]: unknown }).Language
	if type(language) ~= "string" then
		warn(`{LOG} SettingsState ไม่มี Language ข้าม`)
		return
	end
	local valid = parseLanguage(language :: string)
	if valid == nil then
		warn(`{LOG} SettingsState Language ไม่ถูกต้อง ไม่เปลี่ยนภาษา`)
		return
	end
	state.Language = valid
	refreshAll()
end

function MenuController.Start()
	if ensureRoot() == nil then
		return
	end
	local player = Players.LocalPlayer
	table.insert(connections, Remotes.GetEvent("InventoryUpdate").OnClientEvent:Connect(onInventoryUpdate))
	table.insert(connections, Remotes.GetEvent("SettingsState").OnClientEvent:Connect(onSettingsState))
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
	-- ขอ snapshot กระเป๋า (ไม่ส่ง argument) server รอข้อมูลโหลดแล้วตอบด้วย InventoryUpdate
	Remotes.GetEvent("InventorySync"):FireServer()
end

return MenuController
