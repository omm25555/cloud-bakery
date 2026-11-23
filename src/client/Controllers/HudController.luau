--!strict
-- HudController: HUD ขวาบน (เหรียญ + ปุ่ม "+" + Reputation เลเวล/แถบความคืบหน้า)
-- ค่ามาจาก server เท่านั้น (CurrencyUpdate) client แค่แสดงผลและส่ง HudAction ให้ server แจ้งเตือน
-- ซ่อน ServeGui เดิม (ป้ายเหรียญของ ServeController) ด้วย Enabled = false โดยไม่แก้ ServeController
-- ตัวเดียวที่ยิง ServeSync เพิ่ม (ServeController ยิงอีก 1 รวม 2 = Capacity ใน RateLimits)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudConfig = require(ReplicatedStorage.Shared.Config.Hud)
local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local Serve = require(ReplicatedStorage.Shared.Config.Serve)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local HudRules = require(ReplicatedStorage.Shared.HudRules)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LOG = "[HudController]"

type HudViews = {
	CoinRow: Frame,
	RepRow: Frame,
	CoinLabel: TextLabel,
	LevelLabel: TextLabel,
	ProgressLabel: TextLabel,
	BarFill: Frame,
	FailLabel: TextLabel,
}

local HudController = {}

local connections: { RBXScriptConnection } = {}
local views: HudViews? = nil
local language: string = PlayerDataConfig.DefaultLanguage
local coins: number? = nil
local reputation: number? = nil
local loadFailed = false
local serveGuiSeen = false
local lastShopClick = -math.huge
local timeoutThread: thread? = nil
local actionEvent: RemoteEvent

local function parseLanguage(value: unknown): string?
	if value == "th" or value == "en" then
		return value :: string
	end
	return nil
end

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value :: number) ~= math.huge
end

local function refresh()
	local ui = views
	if ui == nil then
		return
	end
	ui.CoinRow.Visible = not loadFailed
	ui.RepRow.Visible = not loadFailed
	ui.FailLabel.Visible = loadFailed
	if loadFailed then
		ui.FailLabel.Text = Strings.Format("UiServeLoadFailed", language, nil)
		return
	end
	local loadingText = Strings.Format("UiHudLoading", language, nil)

	if coins == nil then
		ui.CoinLabel.Text = loadingText
	else
		ui.CoinLabel.Text = HudRules.FormatNumber(coins)
	end

	if reputation == nil then
		ui.LevelLabel.Text = loadingText
		ui.ProgressLabel.Text = ""
		ui.BarFill.Size = UDim2.fromScale(0, 1)
		return
	end
	local progress = HudRules.ProgressFor(reputation)
	local levelArgs: { [string]: string | number } = { level = progress.Level }
	if progress.IsMax then
		ui.LevelLabel.Text = Strings.Format("UiHudLevelMax", language, levelArgs)
		ui.ProgressLabel.Text = HudRules.FormatNumber(reputation)
	else
		ui.LevelLabel.Text = Strings.Format("UiHudLevel", language, levelArgs)
		ui.ProgressLabel.Text = `{HudRules.FormatNumber(progress.Current)}/{HudRules.FormatNumber(progress.Needed)}`
	end
	ui.BarFill.Size = UDim2.fromScale(progress.Ratio, 1)
end

local function round(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function pad(instance: Instance, pixels: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, pixels)
	padding.PaddingBottom = UDim.new(0, pixels)
	padding.PaddingLeft = UDim.new(0, pixels)
	padding.PaddingRight = UDim.new(0, pixels)
	padding.Parent = instance
end

local function makeLabel(parent: Instance, name: string, alignment: Enum.TextXAlignment): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = HudConfig.Font
	label.TextColor3 = HudConfig.TextColor
	label.TextSize = HudConfig.MaxTextSize
	label.TextScaled = true
	label.TextXAlignment = alignment
	label.TextTruncate = Enum.TextTruncate.AtEnd
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = HudConfig.MaxTextSize
	limit.MinTextSize = HudConfig.MinTextSize
	limit.Parent = label
	label.Parent = parent
	return label
end

local function makeRow(parent: Instance, name: string, height: number, order: number): Frame
	local row = Instance.new("Frame")
	row.Name = name
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, height)
	row.BackgroundColor3 = HudConfig.BackgroundColor
	row.BackgroundTransparency = HudConfig.BackgroundTransparency
	row.BorderSizePixel = 0
	round(row, HudConfig.CornerRadiusPixels)
	pad(row, HudConfig.RowPaddingPixels)
	row.Parent = parent
	return row
end

local function onShopActivated()
	local now = os.clock()
	if now - lastShopClick < HudConfig.ShopClickCooldownSeconds then
		return
	end
	lastShopClick = now
	actionEvent:FireServer(HudConfig.Actions.ShopClick)
end

local function createGui(): HudViews?
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not playerGui:IsA("PlayerGui") then
		warn(`{LOG} ไม่พบ PlayerGui ไม่สามารถสร้าง HUD ได้`)
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = HudConfig.GuiName
	gui.ResetOnSpawn = false
	gui.DisplayOrder = HudConfig.GuiDisplayOrder

	local totalHeight = HudConfig.CoinRowHeightPixels + HudConfig.RowSpacingPixels + HudConfig.RepRowHeightPixels
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(1, 0)
	root.Position = UDim2.new(1, -HudConfig.MarginPixels, 0, HudConfig.MarginPixels)
	root.Size = UDim2.new(HudConfig.WidthScale, 0, 0, totalHeight)
	root.BackgroundTransparency = 1
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(HudConfig.MinWidthPixels, 0)
	sizeLimit.MaxSize = Vector2.new(HudConfig.MaxWidthPixels, math.huge)
	sizeLimit.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, HudConfig.RowSpacingPixels)
	layout.Parent = root

	-- แถวเหรียญ
	local coinRow = makeRow(root, "CoinRow", HudConfig.CoinRowHeightPixels, 1)
	local icon = Instance.new("Frame")
	icon.Name = "CoinIcon"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.fromScale(0, 0.5)
	icon.Size = UDim2.fromOffset(HudConfig.CoinIconSizePixels, HudConfig.CoinIconSizePixels)
	icon.BackgroundColor3 = HudConfig.CoinIconColor
	icon.BorderSizePixel = 0
	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(1, 0)
	iconCorner.Parent = icon
	icon.Parent = coinRow

	local leftEdge = HudConfig.CoinIconSizePixels + HudConfig.IconGapPixels
	local rightEdge = HudConfig.PlusButtonSizePixels + HudConfig.IconGapPixels
	local coinLabel = makeLabel(coinRow, "CoinAmount", Enum.TextXAlignment.Left)
	coinLabel.Position = UDim2.new(0, leftEdge, 0, 0)
	coinLabel.Size = UDim2.new(1, -(leftEdge + rightEdge), 1, 0)

	local plus = Instance.new("TextButton")
	plus.Name = "PlusButton"
	plus.AnchorPoint = Vector2.new(1, 0.5)
	plus.Position = UDim2.fromScale(1, 0.5)
	plus.Size = UDim2.fromOffset(HudConfig.PlusButtonSizePixels, HudConfig.PlusButtonSizePixels)
	plus.BackgroundColor3 = HudConfig.PlusButtonColor
	plus.BorderSizePixel = 0
	plus.AutoButtonColor = true
	plus.Font = HudConfig.Font
	plus.Text = HudConfig.PlusGlyph
	plus.TextSize = HudConfig.MaxTextSize
	plus.TextColor3 = HudConfig.TextColor
	round(plus, HudConfig.CornerRadiusPixels)
	plus.Parent = coinRow
	table.insert(connections, plus.Activated:Connect(onShopActivated))

	-- แถว Reputation
	local repRow = makeRow(root, "RepRow", HudConfig.RepRowHeightPixels, 2)
	local star = Instance.new("TextLabel")
	star.Name = "Star"
	star.BackgroundTransparency = 1
	star.Size = UDim2.fromOffset(HudConfig.StarSizePixels, HudConfig.LineHeightPixels)
	star.Font = HudConfig.Font
	star.Text = HudConfig.StarGlyph
	star.TextSize = HudConfig.MaxTextSize
	star.TextColor3 = HudConfig.StarColor
	star.Parent = repRow

	local starEdge = HudConfig.StarSizePixels + HudConfig.IconGapPixels
	local levelLabel = makeLabel(repRow, "Level", Enum.TextXAlignment.Left)
	levelLabel.Position = UDim2.fromOffset(starEdge, 0)
	levelLabel.Size = UDim2.new(0.55, -starEdge, 0, HudConfig.LineHeightPixels)

	local progressLabel = makeLabel(repRow, "Progress", Enum.TextXAlignment.Right)
	progressLabel.TextColor3 = HudConfig.SubTextColor
	progressLabel.AnchorPoint = Vector2.new(1, 0)
	progressLabel.Position = UDim2.fromScale(1, 0)
	progressLabel.Size = UDim2.new(0.45, 0, 0, HudConfig.LineHeightPixels)

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.fromScale(0, 1)
	bar.Size = UDim2.new(1, 0, 0, HudConfig.BarHeightPixels)
	bar.BackgroundColor3 = HudConfig.BarBackgroundColor
	bar.BorderSizePixel = 0
	round(bar, HudConfig.BarHeightPixels // 2)
	bar.Parent = repRow
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = HudConfig.BarFillColor
	fill.BorderSizePixel = 0
	round(fill, HudConfig.BarHeightPixels // 2)
	fill.Parent = bar

	-- ข้อความโหลดระบบเสิร์ฟไม่สำเร็จ (แทนป้ายเดิมที่ถูกซ่อน)
	local failLabel = makeLabel(root, "ServeLoadFailed", Enum.TextXAlignment.Left)
	failLabel.LayoutOrder = 3
	failLabel.Size = UDim2.new(1, 0, 0, totalHeight)
	failLabel.TextScaled = false
	failLabel.TextSize = HudConfig.LineTextSize
	failLabel.TextWrapped = true
	failLabel.TextColor3 = HudConfig.FailColor
	failLabel.BackgroundTransparency = HudConfig.BackgroundTransparency
	failLabel.BackgroundColor3 = HudConfig.BackgroundColor
	failLabel.Visible = false
	pad(failLabel, HudConfig.RowPaddingPixels)

	root.Parent = gui
	gui.Parent = playerGui
	return {
		CoinRow = coinRow,
		RepRow = repRow,
		CoinLabel = coinLabel,
		LevelLabel = levelLabel,
		ProgressLabel = progressLabel,
		BarFill = fill,
		FailLabel = failLabel,
	}
end

-- ข้อความ UiServeLoadFailed ในทุกภาษาที่มีใน Strings (ผู้เล่นอาจเปลี่ยนภาษาระหว่างนั้น)
local function isServeLoadFailedText(text: string): boolean
	local entry = Strings.Messages.UiServeLoadFailed
	if entry == nil then
		return false
	end
	return text == entry.th or text == entry.en
end

local function setLoadFailed(value: boolean)
	if loadFailed == value then
		return
	end
	loadFailed = value
	if value then
		warn(`{LOG} ServeController แจ้งว่าระบบเสิร์ฟโหลดไม่สำเร็จ แสดงข้อความใน HUD แทน`)
	end
	refresh()
end

local function hideServeGui(gui: ScreenGui)
	serveGuiSeen = true
	gui.Enabled = false
	table.insert(
		connections,
		gui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if gui.Enabled then
				gui.Enabled = false
			end
		end)
	)
	local label = gui:FindFirstChild(HudConfig.ServeCurrencyLabelName)
	if label == nil or not label:IsA("TextLabel") then
		warn(`{LOG} ไม่พบ {HudConfig.ServeCurrencyLabelName} ใน {Serve.GuiName} ไม่ตามดูข้อความโหลดไม่สำเร็จ`)
		return
	end
	local function check()
		setLoadFailed(isServeLoadFailedText(label.Text))
	end
	table.insert(connections, label:GetPropertyChangedSignal("Text"):Connect(check))
	check()
end

local function watchServeGui(playerGui: PlayerGui)
	table.insert(
		connections,
		playerGui.ChildAdded:Connect(function(child: Instance)
			if child.Name == Serve.GuiName and child:IsA("ScreenGui") then
				hideServeGui(child)
			end
		end)
	)
	local existing = playerGui:FindFirstChild(Serve.GuiName)
	if existing ~= nil and existing:IsA("ScreenGui") then
		hideServeGui(existing)
	end
	task.delay(Serve.ClientWaitSeconds, function()
		if not serveGuiSeen then
			warn(`{LOG} ไม่พบ {Serve.GuiName} ภายใน {Serve.ClientWaitSeconds} วินาที ไม่มีป้ายเดิมให้ซ่อน`)
		end
	end)
end

local function onCurrencyUpdate(payload: unknown)
	if type(payload) ~= "table" then
		warn(`{LOG} CurrencyUpdate payload ไม่ถูกต้อง ข้าม`)
		return
	end
	local data = payload :: { [string]: unknown }
	local newCoins = data.Coins
	local newReputation = data.Reputation
	if isFiniteNumber(newCoins) then
		coins = newCoins :: number
	end
	if isFiniteNumber(newReputation) then
		local value = newReputation :: number
		local changed = reputation ~= value
		reputation = value
		-- Reputation เปลี่ยน (รวมครั้งแรก) ให้ server ตรวจเลเวลเอง client เป็นแค่ตัวกระตุ้น
		if changed then
			actionEvent:FireServer(HudConfig.Actions.LevelCheck)
		end
	end
	refresh()
end

local function onLanguagePayload(payload: unknown)
	if type(payload) ~= "table" then
		return
	end
	local valid = parseLanguage((payload :: { [string]: unknown }).Language)
	if valid ~= nil and valid ~= language then
		language = valid
		refresh()
	end
end

local function cleanup()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	local thread = timeoutThread
	if thread ~= nil then
		task.cancel(thread)
		timeoutThread = nil
	end
end

function HudController.Start()
	actionEvent = Remotes.GetEvent("HudAction")
	local player = Players.LocalPlayer
	views = createGui()
	refresh()

	-- ต่อ listener ทั้งหมดก่อนยิง ServeSync เพื่อไม่ให้พลาด Snapshot
	table.insert(connections, Remotes.GetEvent("CurrencyUpdate").OnClientEvent:Connect(onCurrencyUpdate))
	table.insert(connections, Remotes.GetEvent("ServeState").OnClientEvent:Connect(onLanguagePayload))
	table.insert(connections, Remotes.GetEvent("InventoryUpdate").OnClientEvent:Connect(onLanguagePayload))
	table.insert(connections, Remotes.GetEvent("SettingsState").OnClientEvent:Connect(onLanguagePayload))
	table.insert(
		connections,
		player.AncestryChanged:Connect(function()
			if player.Parent == nil then
				cleanup()
			end
		end)
	)

	local playerGui = player:WaitForChild("PlayerGui")
	if playerGui:IsA("PlayerGui") then
		watchServeGui(playerGui)
	end

	timeoutThread = task.delay(HudConfig.LoadTimeoutSeconds, function()
		timeoutThread = nil
		if coins == nil or reputation == nil then
			warn(`{LOG} ไม่ได้รับเหรียญ/Reputation จาก server ภายใน {HudConfig.LoadTimeoutSeconds} วินาที`)
			actionEvent:FireServer(HudConfig.Actions.LoadTimeout)
		end
	end)

	-- defer เพื่อให้ Controller อื่นต่อ listener เสร็จก่อนยิง (ServeSync ตัวเดียวจาก HUD)
	task.defer(function()
		Remotes.GetEvent("ServeSync"):FireServer()
	end)
end

return HudController
