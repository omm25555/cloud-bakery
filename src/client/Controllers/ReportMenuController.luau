--!strict
-- ReportMenuController: เมนูรายงานผู้จัดการแบบรูปภาพ (ScreenGui ใหม่ ReportGui) เปิดเมื่อ server ส่ง ReportMenu (หลังผู้เล่นกด prompt ที่ผู้จัดการ)
-- 5-6 หมวดตามที่ server ส่งมา (ไอคอน + ชื่อสั้น) เลือก "ลูกค้า" -> แสดงลูกค้าในร้านที่ server ส่งมาให้เลือก 1 คน
-- client ส่งได้แค่ ReportSubmit(category, customerId?) ผลถูก/ผิดและการปฏิเสธมาจาก server (toast + ผู้จัดการ) ปิดเมนูได้ด้วยปุ่ม/server สั่งปิด
-- เมนูเป็น modal กลางจอ สูงไม่เกิน Config/Report.PanelHeightScale ไม่ทับแถบเลือกเมล็ดล่างจอและกล่องวัน/คืนกลางบน

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CustomersConfig = require(ReplicatedStorage.Shared.Config.Customers)
local Report = require(ReplicatedStorage.Shared.Config.Report)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LOG = "[ReportMenuController]"

type CustomerEntry = { Id: string, Name: string }

type MenuState = {
	Language: string,
	Categories: { string },
	Customers: { CustomerEntry },
	Line: string,
}

type Views = {
	Gui: ScreenGui,
	Panel: Frame,
	Title: TextLabel,
	Line: TextLabel,
	Content: ScrollingFrame,
	BackButton: TextButton,
	CloseButton: TextButton,
}

local ReportMenuController = {}

local connections: { RBXScriptConnection } = {}
local views: Views? = nil
local state: MenuState? = nil
local submitEvent: RemoteEvent? = nil

local function round(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function limitText(instance: Instance)
	if instance:IsA("TextLabel") then
		instance.TextScaled = true
	elseif instance:IsA("TextButton") then
		instance.TextScaled = true
	else
		return
	end
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = Report.MaxTextSize
	limit.MinTextSize = Report.MinTextSize
	limit.Parent = instance
end

local function makeButton(parent: Instance, text: string, color: Color3, textColor: Color3): TextButton
	local button = Instance.new("TextButton")
	button.AutoButtonColor = true
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Font = Report.Font
	button.Text = text
	button.TextColor3 = textColor
	limitText(button)
	round(button, Report.PanelCornerRadiusPixels)
	button.Parent = parent
	return button
end

local function makeLabel(parent: Instance, height: number, textColor: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Report.Font
	label.TextColor3 = textColor
	label.Size = UDim2.new(1, 0, 0, height)
	limitText(label)
	label.Parent = parent
	return label
end

local function createGui(): Views?
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not playerGui:IsA("PlayerGui") then
		warn(`{LOG} ไม่พบ PlayerGui ไม่สามารถสร้างเมนูรายงานได้`)
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = Report.MenuGuiName
	gui.ResetOnSpawn = false
	gui.DisplayOrder = Report.MenuGuiDisplayOrder
	gui.Enabled = false

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(Report.PanelWidthScale, Report.PanelHeightScale)
	panel.BackgroundColor3 = Report.PanelColor
	panel.BorderSizePixel = 0
	round(panel, Report.PanelCornerRadiusPixels)
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(Report.PanelMaxWidthPixels, Report.PanelMaxHeightPixels)
	sizeLimit.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, Report.PanelPaddingPixels)
	padding.PaddingBottom = UDim.new(0, Report.PanelPaddingPixels)
	padding.PaddingLeft = UDim.new(0, Report.PanelPaddingPixels)
	padding.PaddingRight = UDim.new(0, Report.PanelPaddingPixels)
	padding.Parent = panel
	panel.Parent = gui

	local title = makeLabel(panel, Report.TitleHeightPixels, Report.ButtonTextColor)
	title.Name = "Title"
	local line = makeLabel(panel, Report.LineHeightPixels, Report.ButtonTextColor)
	line.Name = "Line"
	line.Position = UDim2.fromOffset(0, Report.TitleHeightPixels)

	local top = Report.TitleHeightPixels + Report.LineHeightPixels
	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Position = UDim2.fromOffset(0, top)
	content.Size = UDim2.new(1, 0, 1, -(top + Report.FooterHeightPixels))
	content.ScrollBarThickness = 6
	content.CanvasSize = UDim2.fromOffset(0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.Parent = panel

	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.fromScale(0, 1)
	footer.Size = UDim2.new(1, 0, 0, Report.FooterHeightPixels)
	footer.BackgroundTransparency = 1
	footer.Parent = panel
	local footerLayout = Instance.new("UIListLayout")
	footerLayout.FillDirection = Enum.FillDirection.Horizontal
	footerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	footerLayout.Padding = UDim.new(0, Report.GridGapPixels)
	footerLayout.Parent = footer

	local back = makeButton(footer, "", Report.ButtonColor, Report.ButtonTextColor)
	back.Name = "Back"
	back.Size = UDim2.new(0.4, 0, 1, 0)
	back.Visible = false
	local close = makeButton(footer, "", Report.CloseColor, Report.CloseTextColor)
	close.Name = "Close"
	close.Size = UDim2.new(0.4, 0, 1, 0)

	gui.Parent = playerGui
	return { Gui = gui, Panel = panel, Title = title, Line = line, Content = content, BackButton = back, CloseButton = close }
end

local function hide()
	local ui = views
	if ui ~= nil then
		ui.Gui.Enabled = false
	end
	state = nil
end

local function clearContent(ui: Views)
	for _, child in ui.Content:GetChildren() do
		child:Destroy()
	end
	ui.Content.CanvasPosition = Vector2.zero
end

local function addGrid(ui: Views)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / Report.GridColumns, -Report.GridGapPixels, 0, Report.ButtonMinHeightPixels)
	grid.CellPadding = UDim2.fromOffset(Report.GridGapPixels, Report.GridGapPixels)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = ui.Content
end

local function submit(category: string, customerId: string?)
	local event = submitEvent
	if event == nil then
		warn(`{LOG} ไม่มี remote ReportSubmit ส่งรายงานไม่ได้`)
		return
	end
	hide()
	event:FireServer(category, customerId)
end

local function showCustomers(ui: Views, current: MenuState)
	clearContent(ui)
	ui.Title.Text = Strings.Format("ReportCustomerPickTitle", current.Language, nil)
	ui.BackButton.Visible = true
	if #current.Customers == 0 then
		local empty = Instance.new("TextLabel")
		empty.BackgroundTransparency = 1
		empty.Font = Report.Font
		empty.TextColor3 = Report.ButtonTextColor
		empty.TextWrapped = true
		empty.TextSize = Report.MaxTextSize
		empty.Size = UDim2.new(1, 0, 0, Report.ButtonMinHeightPixels)
		empty.Text = Strings.Format("ReportNoCustomers", current.Language, nil)
		empty.Parent = ui.Content
		return
	end
	addGrid(ui)
	for index, customer in current.Customers do
		local config = CustomersConfig.Customers[customer.Id]
		local button = makeButton(ui.Content, customer.Name, Report.ButtonColor, Report.ButtonTextColor)
		button.LayoutOrder = index
		button.TextYAlignment = Enum.TextYAlignment.Bottom
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0)
		dot.Position = UDim2.fromScale(0.5, 0.08)
		dot.Size = UDim2.fromScale(0.4, 0.4)
		dot.SizeConstraint = Enum.SizeConstraint.RelativeYY
		dot.BackgroundColor3 = if config ~= nil then config.Color else Report.PanelColor
		dot.BorderSizePixel = 0
		round(dot, Report.PanelMaxHeightPixels)
		dot.Parent = button
		local customerId = customer.Id
		button.Activated:Connect(function()
			submit("customer", customerId)
		end)
	end
end

local function showCategories(ui: Views, current: MenuState)
	clearContent(ui)
	ui.Title.Text = Strings.Format("ReportMenuTitle", current.Language, nil)
	ui.BackButton.Visible = false
	addGrid(ui)
	for index, category in current.Categories do
		local icon = Report.CategoryIcons[category] or Report.DefaultIcon
		local name = Strings.Format(`ReportCategory_{category}`, current.Language, nil)
		local button = makeButton(ui.Content, `{icon}\n{name}`, Report.ButtonColor, Report.ButtonTextColor)
		button.LayoutOrder = index
		button.Activated:Connect(function()
			if category == "customer" then
				showCustomers(ui, current)
			else
				submit(category, nil)
			end
		end)
	end
end

local function parseState(payload: { [string]: unknown }): MenuState?
	local language = payload.Language
	local categories = payload.Categories
	local customers = payload.Customers
	local line = payload.Line
	if (language ~= "th" and language ~= "en") or type(categories) ~= "table" or type(customers) ~= "table" or type(line) ~= "string" then
		return nil
	end
	local parsedCategories: { string } = {}
	for _, value in categories :: { unknown } do
		if type(value) == "string" then
			table.insert(parsedCategories, value)
		end
	end
	local parsedCustomers: { CustomerEntry } = {}
	for _, value in customers :: { unknown } do
		if type(value) == "table" then
			local entry = value :: { [string]: unknown }
			if type(entry.Id) == "string" and type(entry.Name) == "string" then
				table.insert(parsedCustomers, { Id = entry.Id, Name = entry.Name })
			end
		end
	end
	if #parsedCategories == 0 then
		return nil
	end
	return { Language = language :: string, Categories = parsedCategories, Customers = parsedCustomers, Line = line }
end

local function onMenu(payload: unknown)
	local ui = views
	if ui == nil then
		return
	end
	if type(payload) ~= "table" then
		warn(`{LOG} ReportMenu payload ไม่ถูกต้อง ข้าม`)
		return
	end
	local data = payload :: { [string]: unknown }
	if data.Open ~= true then
		hide()
		return
	end
	local parsed = parseState(data)
	if parsed == nil then
		warn(`{LOG} ReportMenu payload เปิดเมนูไม่ครบ/ไม่ถูกต้อง ข้าม`)
		return
	end
	state = parsed
	ui.Line.Text = parsed.Line
	ui.BackButton.Text = Strings.Format("ReportBack", parsed.Language, nil)
	ui.CloseButton.Text = Strings.Format("ReportClose", parsed.Language, nil)
	showCategories(ui, parsed)
	ui.Gui.Enabled = true
end

local function cleanup()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

function ReportMenuController.Start()
	local player = Players.LocalPlayer
	local ui = createGui()
	views = ui
	if ui == nil then
		return
	end
	submitEvent = Remotes.GetEvent("ReportSubmit")
	table.insert(connections, Remotes.GetEvent("ReportMenu").OnClientEvent:Connect(onMenu))
	table.insert(connections, ui.CloseButton.Activated:Connect(hide))
	table.insert(
		connections,
		ui.BackButton.Activated:Connect(function()
			local current = state
			if current ~= nil then
				showCategories(ui, current)
			end
		end)
	)
	table.insert(
		connections,
		player.AncestryChanged:Connect(function()
			if player.Parent == nil then
				cleanup()
			end
		end)
	)
end

return ReportMenuController
