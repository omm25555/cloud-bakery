--!strict
-- QuestPanelController: แผง Daily Quest ซ้ายบน (3 แถว: checkbox, ชื่อ, progress, แถบ, รางวัล, ปุ่มรับ)
-- ข้อมูลมาจาก server เท่านั้น: QuestState (ความคืบหน้า/รางวัล/เวลารีเซ็ต) และ SettingsState (ภาษา)
-- client ส่งได้แค่ QuestSync (ขอ snapshot) และ QuestClaim (ขอรับรางวัล questId) server เป็นผู้ตัดสินและแจ้งผลผ่าน Notify
-- เวลาที่เหลือคำนวณจาก ResetAt (เวลา server) เทียบ GetServerTimeNow

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local QuestsConfig = require(ReplicatedStorage.Shared.Config.Quests)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local QuestRules = require(ReplicatedStorage.Shared.QuestRules)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LOG = "[QuestPanelController]"

type QuestEntry = {
	Id: string,
	Progress: number,
	Target: number,
	Claimed: boolean,
	RewardCoins: number,
	RewardReputation: number,
}

type Row = {
	Id: string,
	NameKey: string,
	Frame: Frame,
	Check: TextLabel,
	Name: TextLabel,
	Progress: TextLabel,
	BarFill: Frame,
	Reward: TextLabel,
	Button: TextButton,
}

type PanelViews = {
	Gui: ScreenGui,
	Title: TextLabel,
	Timer: TextLabel,
	Toggle: TextButton,
	Status: TextLabel,
	Scroll: ScrollingFrame,
	Layout: UIListLayout,
	Rows: { [string]: Row },
}

local QuestPanelController = {}

local connections: { RBXScriptConnection } = {}
local ui: PanelViews? = nil
local entries: { [string]: QuestEntry } = {}
local resetAt: number? = nil
local loaded = false
local loadFailed = false
local language: string = PlayerDataConfig.DefaultLanguage
local collapsed = false
local tickConnection: RBXScriptConnection? = nil
local loadThread: thread? = nil
local claimEvent: RemoteEvent? = nil

local function parseLanguage(value: unknown): string?
	if value == "th" or value == "en" then
		return value :: string
	end
	return nil
end

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value :: number) ~= math.huge
end

local function updateScrollSize()
	local views = ui
	if views == nil then
		return
	end
	local available = views.Gui.AbsoluteSize.Y * QuestsConfig.MaxBottomScale
		- QuestsConfig.TopOffsetPixels
		- QuestsConfig.HeaderHeightPixels
		- QuestsConfig.PaddingPixels * 3
	local maxHeight = math.max(QuestsConfig.MinScrollHeightPixels, available)
	local wanted = math.min(views.Layout.AbsoluteContentSize.Y, maxHeight)
	views.Scroll.Size = UDim2.new(1, 0, 0, wanted)
end

local function refreshTimer()
	local views = ui
	if views == nil then
		return
	end
	local target = resetAt
	if not loaded or target == nil then
		views.Timer.Text = ""
		return
	end
	local args: { [string]: string | number } =
		{ time = QuestRules.FormatCountdown(target - Workspace:GetServerTimeNow()) }
	views.Timer.Text = Strings.Format("UiQuestReset", language, args)
end

local function refreshRow(row: Row)
	local entry = entries[row.Id]
	row.Frame.Visible = loaded and entry ~= nil
	if entry == nil then
		return
	end
	local progress = QuestRules.ClampProgress(entry.Progress, entry.Target)
	local done = progress >= entry.Target
	local nameArgs: { [string]: string | number } = { target = entry.Target }
	row.Name.Text = Strings.Format(row.NameKey, language, nameArgs)
	local progressArgs: { [string]: string | number } = { progress = progress, target = entry.Target }
	row.Progress.Text = Strings.Format("UiQuestProgress", language, progressArgs)
	row.BarFill.Size = UDim2.fromScale(math.clamp(progress / math.max(1, entry.Target), 0, 1), 1)
	row.Check.Text = if done then QuestsConfig.CheckGlyph else ""
	row.Check.BackgroundColor3 = if done then QuestsConfig.CheckDoneColor else QuestsConfig.CheckEmptyColor

	local rewardArgs: { [string]: string | number } =
		{ coins = entry.RewardCoins, reputation = entry.RewardReputation }
	local rewardKey = if entry.RewardReputation > 0 then "UiQuestRewardRep" else "UiQuestReward"
	row.Reward.Text = Strings.Format(rewardKey, language, rewardArgs)

	row.Button.Text = Strings.Format(if entry.Claimed then "UiQuestClaimed" else "UiQuestClaim", language, nil)
	local claimable = done and not entry.Claimed
	row.Button.BackgroundColor3 = if claimable then QuestsConfig.ClaimEnabledColor else QuestsConfig.ClaimDisabledColor
end

local function refreshAll()
	local views = ui
	if views == nil then
		return
	end
	if loaded then
		local done = 0
		local total = 0
		for _, quest in QuestsConfig.List do
			local entry = entries[quest.Id]
			if entry ~= nil then
				total += 1
				if QuestRules.ClampProgress(entry.Progress, entry.Target) >= entry.Target then
					done += 1
				end
			end
		end
		local args: { [string]: string | number } = { done = done, total = total }
		views.Title.Text = Strings.Format("UiQuestTitleCount", language, args)
	else
		views.Title.Text = Strings.Format("UiQuestTitle", language, nil)
	end
	views.Toggle.Text = if collapsed then QuestsConfig.ExpandGlyph else QuestsConfig.CollapseGlyph
	views.Scroll.Visible = loaded and not collapsed
	views.Status.Visible = not loaded
	if not loaded then
		local key = if loadFailed then "UiQuestLoadFailed" else "UiHudLoading"
		views.Status.Text = Strings.Format(key, language, nil)
		views.Status.TextColor3 = if loadFailed then QuestsConfig.FailColor else QuestsConfig.SubTextColor
	end
	for _, row in views.Rows do
		refreshRow(row)
	end
	refreshTimer()
	updateScrollSize()
end

local function readEntry(raw: unknown): QuestEntry?
	if type(raw) ~= "table" then
		return nil
	end
	local data = raw :: { [string]: unknown }
	local id = data.Id
	local progress = data.Progress
	local target = data.Target
	local claimed = data.Claimed
	local coins = data.RewardCoins
	local reputation = data.RewardReputation
	if
		type(id) ~= "string"
		or not isFiniteNumber(progress)
		or not isFiniteNumber(target)
		or type(claimed) ~= "boolean"
		or not isFiniteNumber(coins)
		or not isFiniteNumber(reputation)
	then
		return nil
	end
	return {
		Id = id :: string,
		Progress = progress :: number,
		Target = math.max(1, target :: number),
		Claimed = claimed :: boolean,
		RewardCoins = coins :: number,
		RewardReputation = reputation :: number,
	}
end

local function onQuestState(payload: unknown)
	if type(payload) ~= "table" then
		warn(`{LOG} QuestState payload ไม่ถูกต้อง ข้าม`)
		return
	end
	local data = payload :: { [string]: unknown }
	local rawList = data.Quests
	local rawReset = data.ResetAt
	if type(rawList) ~= "table" or not isFiniteNumber(rawReset) then
		warn(`{LOG} QuestState ไม่มี Quests/ResetAt ที่ถูกต้อง ข้าม`)
		return
	end
	local newLanguage = parseLanguage(data.Language)
	if newLanguage ~= nil then
		language = newLanguage
	end
	local fresh: { [string]: QuestEntry } = {}
	for _, raw in rawList :: { unknown } do
		local entry = readEntry(raw)
		if entry ~= nil then
			fresh[entry.Id] = entry
		else
			warn(`{LOG} QuestState มีเควสที่รูปแบบไม่ถูกต้อง ข้ามรายการนั้น`)
		end
	end
	entries = fresh
	resetAt = rawReset :: number
	loaded = true
	loadFailed = false
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

local function makeLabel(parent: Instance, name: string, alignment: Enum.TextXAlignment): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = QuestsConfig.Font
	label.TextSize = QuestsConfig.RowTextSize
	label.TextColor3 = QuestsConfig.TextColor
	label.TextXAlignment = alignment
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = parent
	return label
end

local function createRow(questId: string, nameKey: string, order: number, scroll: ScrollingFrame): Row
	local frame = Instance.new("Frame")
	frame.Name = `Quest_{questId}`
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, QuestsConfig.RowHeightPixels)
	frame.BackgroundColor3 = QuestsConfig.RowColor
	frame.BorderSizePixel = 0
	frame.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, QuestsConfig.RowCornerRadiusPixels)
	corner.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, QuestsConfig.RowPaddingPixels)
	padding.PaddingBottom = UDim.new(0, QuestsConfig.RowPaddingPixels)
	padding.PaddingLeft = UDim.new(0, QuestsConfig.RowPaddingPixels)
	padding.PaddingRight = UDim.new(0, QuestsConfig.RowPaddingPixels)
	padding.Parent = frame

	local check = Instance.new("TextLabel")
	check.Name = "Check"
	check.Size = UDim2.fromOffset(QuestsConfig.CheckboxSizePixels, QuestsConfig.CheckboxSizePixels)
	check.BackgroundColor3 = QuestsConfig.CheckEmptyColor
	check.BorderSizePixel = 0
	check.Font = QuestsConfig.Font
	check.TextSize = QuestsConfig.RowTextSize
	check.TextColor3 = QuestsConfig.TextColor
	check.Text = ""
	local checkCorner = Instance.new("UICorner")
	checkCorner.CornerRadius = UDim.new(0, QuestsConfig.RowCornerRadiusPixels)
	checkCorner.Parent = check
	local checkStroke = Instance.new("UIStroke")
	checkStroke.Color = QuestsConfig.SubTextColor
	checkStroke.Thickness = 1
	checkStroke.Parent = check
	check.Parent = frame

	local textX = QuestsConfig.CheckboxSizePixels + QuestsConfig.CheckboxGapPixels
	local line = QuestsConfig.LineHeightPixels

	local nameLabel = makeLabel(frame, "Name", Enum.TextXAlignment.Left)
	nameLabel.Position = UDim2.fromOffset(textX, 0)
	nameLabel.Size = UDim2.new(1 - QuestsConfig.ProgressWidthScale, -textX, 0, line)

	local progressLabel = makeLabel(frame, "Progress", Enum.TextXAlignment.Right)
	progressLabel.AnchorPoint = Vector2.new(1, 0)
	progressLabel.Position = UDim2.fromScale(1, 0)
	progressLabel.Size = UDim2.new(QuestsConfig.ProgressWidthScale, 0, 0, line)

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.fromOffset(textX, QuestsConfig.BarTopPixels)
	bar.Size = UDim2.new(1, -textX, 0, QuestsConfig.BarHeightPixels)
	bar.BackgroundColor3 = QuestsConfig.BarBackgroundColor
	bar.BorderSizePixel = 0
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, QuestsConfig.BarHeightPixels)
	barCorner.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = QuestsConfig.BarFillColor
	fill.BorderSizePixel = 0
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, QuestsConfig.BarHeightPixels)
	fillCorner.Parent = fill
	fill.Parent = bar
	bar.Parent = frame

	local rewardLabel = makeLabel(frame, "Reward", Enum.TextXAlignment.Left)
	rewardLabel.TextColor3 = QuestsConfig.SubTextColor
	rewardLabel.Position = UDim2.fromOffset(textX, QuestsConfig.ThirdLineTopPixels)
	rewardLabel.Size = UDim2.new(1 - QuestsConfig.ButtonWidthScale, -textX, 0, QuestsConfig.ButtonHeightPixels)

	local button = Instance.new("TextButton")
	button.Name = "Claim"
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, 0, 0, QuestsConfig.ThirdLineTopPixels)
	button.Size = UDim2.new(QuestsConfig.ButtonWidthScale, 0, 0, QuestsConfig.ButtonHeightPixels)
	button.BackgroundColor3 = QuestsConfig.ClaimDisabledColor
	button.BorderSizePixel = 0
	button.Font = QuestsConfig.Font
	button.TextSize = QuestsConfig.ButtonTextSize
	button.TextColor3 = QuestsConfig.TextColor
	button.TextTruncate = Enum.TextTruncate.AtEnd
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, QuestsConfig.RowCornerRadiusPixels)
	buttonCorner.Parent = button
	button.Parent = frame

	frame.Parent = scroll
	return {
		Id = questId,
		NameKey = nameKey,
		Frame = frame,
		Check = check,
		Name = nameLabel,
		Progress = progressLabel,
		BarFill = fill,
		Reward = rewardLabel,
		Button = button,
	}
end

local function createGui(): PanelViews?
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not playerGui:IsA("PlayerGui") then
		warn(`{LOG} ไม่พบ PlayerGui ไม่สามารถสร้างแผง Daily Quest ได้`)
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = QuestsConfig.GuiName
	gui.ResetOnSpawn = false
	gui.DisplayOrder = QuestsConfig.GuiDisplayOrder

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Position = UDim2.fromOffset(QuestsConfig.MarginPixels, QuestsConfig.TopOffsetPixels)
	panel.Size = UDim2.new(QuestsConfig.WidthScale, 0, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = QuestsConfig.BackgroundColor
	panel.BackgroundTransparency = QuestsConfig.BackgroundTransparency
	panel.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, QuestsConfig.CornerRadiusPixels)
	corner.Parent = panel
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(QuestsConfig.MinWidthPixels, 0)
	sizeLimit.MaxSize = Vector2.new(QuestsConfig.MaxWidthPixels, math.huge)
	sizeLimit.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, QuestsConfig.PaddingPixels)
	padding.PaddingBottom = UDim.new(0, QuestsConfig.PaddingPixels)
	padding.PaddingLeft = UDim.new(0, QuestsConfig.PaddingPixels)
	padding.PaddingRight = UDim.new(0, QuestsConfig.PaddingPixels)
	padding.Parent = panel
	local panelLayout = Instance.new("UIListLayout")
	panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
	panelLayout.Padding = UDim.new(0, QuestsConfig.PaddingPixels)
	panelLayout.Parent = panel

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.LayoutOrder = 1
	header.Size = UDim2.new(1, 0, 0, QuestsConfig.HeaderHeightPixels)
	header.BackgroundTransparency = 1
	header.Parent = panel

	local halfHeader = QuestsConfig.HeaderHeightPixels // 2
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -(QuestsConfig.ToggleSizePixels + QuestsConfig.SpacingPixels), 0, halfHeader)
	title.Font = QuestsConfig.Font
	title.TextSize = QuestsConfig.TitleTextSize
	title.TextColor3 = QuestsConfig.TextColor
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = header

	local timer = Instance.new("TextLabel")
	timer.Name = "Timer"
	timer.BackgroundTransparency = 1
	timer.Position = UDim2.fromOffset(0, halfHeader)
	timer.Size = UDim2.new(1, 0, 0, halfHeader)
	timer.Font = QuestsConfig.Font
	timer.TextSize = QuestsConfig.TimerTextSize
	timer.TextColor3 = QuestsConfig.SubTextColor
	timer.TextXAlignment = Enum.TextXAlignment.Left
	timer.TextTruncate = Enum.TextTruncate.AtEnd
	timer.Parent = header

	local toggle = Instance.new("TextButton")
	toggle.Name = "Toggle"
	toggle.AnchorPoint = Vector2.new(1, 0)
	toggle.Position = UDim2.fromScale(1, 0)
	toggle.Size = UDim2.fromOffset(QuestsConfig.ToggleSizePixels, QuestsConfig.ToggleSizePixels)
	toggle.BackgroundColor3 = QuestsConfig.ToggleColor
	toggle.BorderSizePixel = 0
	toggle.Font = QuestsConfig.Font
	toggle.TextSize = QuestsConfig.TitleTextSize
	toggle.TextColor3 = QuestsConfig.TextColor
	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(0, QuestsConfig.CornerRadiusPixels)
	toggleCorner.Parent = toggle
	toggle.Parent = header

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.LayoutOrder = 2
	status.Size = UDim2.new(1, 0, 0, QuestsConfig.StatusHeightPixels)
	status.BackgroundTransparency = 1
	status.Font = QuestsConfig.Font
	status.TextSize = QuestsConfig.StatusTextSize
	status.TextColor3 = QuestsConfig.SubTextColor
	status.TextWrapped = true
	status.Parent = panel

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.LayoutOrder = 3
	scroll.Size = UDim2.new(1, 0, 0, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = QuestsConfig.ScrollBarThicknessPixels
	scroll.Visible = false
	scroll.Parent = panel
	local scrollLayout = Instance.new("UIListLayout")
	scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
	scrollLayout.Padding = UDim.new(0, QuestsConfig.SpacingPixels)
	scrollLayout.Parent = scroll

	local rows: { [string]: Row } = {}
	for index, quest in QuestsConfig.List do
		rows[quest.Id] = createRow(quest.Id, quest.NameKey, index, scroll)
	end

	panel.Parent = gui
	gui.Parent = playerGui
	return {
		Gui = gui,
		Title = title,
		Timer = timer,
		Toggle = toggle,
		Status = status,
		Scroll = scroll,
		Layout = scrollLayout,
		Rows = rows,
	}
end

local function stopTicker()
	local connection = tickConnection
	if connection ~= nil then
		connection:Disconnect()
		tickConnection = nil
	end
end

local function startTicker()
	local elapsed = 0
	tickConnection = RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < QuestsConfig.UiRefreshSeconds then
			return
		end
		elapsed = 0
		refreshTimer()
	end)
end

local function cleanup()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	stopTicker()
	local thread = loadThread
	if thread ~= nil then
		task.cancel(thread)
		loadThread = nil
	end
end

-- ยังไม่ได้ QuestState: ขอซ้ำ 1 ครั้งที่ LoadRetrySeconds แล้วขึ้น "โหลดไม่สำเร็จ" ที่ LoadTimeoutSeconds (กลับเป็นปกติเองถ้า state มาทีหลัง)
local function watchLoading(syncEvent: RemoteEvent)
	loadThread = task.delay(QuestsConfig.LoadRetrySeconds, function()
		loadThread = nil
		if loaded then
			return
		end
		warn(`{LOG} ยังไม่ได้ QuestState ภายใน {QuestsConfig.LoadRetrySeconds} วินาที ส่ง QuestSync ใหม่ 1 ครั้ง`)
		syncEvent:FireServer()
		loadThread = task.delay(QuestsConfig.LoadTimeoutSeconds - QuestsConfig.LoadRetrySeconds, function()
			loadThread = nil
			if loaded then
				return
			end
			warn(`{LOG} ไม่ได้รับข้อมูลเควสจาก server ภายใน {QuestsConfig.LoadTimeoutSeconds} วินาที`)
			loadFailed = true
			refreshAll()
		end)
	end)
end

function QuestPanelController.Start()
	local views = createGui()
	if views == nil then
		return
	end
	ui = views
	local player = Players.LocalPlayer
	local syncEvent = Remotes.GetEvent("QuestSync")
	claimEvent = Remotes.GetEvent("QuestClaim")

	for _, row in views.Rows do
		local questId = row.Id
		table.insert(
			connections,
			row.Button.Activated:Connect(function()
				local event = claimEvent
				if event ~= nil then
					event:FireServer(questId)
				end
			end)
		)
	end
	table.insert(connections, views.Toggle.Activated:Connect(function()
		collapsed = not collapsed
		refreshAll()
	end))
	table.insert(connections, views.Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateScrollSize))
	table.insert(connections, views.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScrollSize))
	table.insert(connections, Remotes.GetEvent("QuestState").OnClientEvent:Connect(onQuestState))
	table.insert(connections, Remotes.GetEvent("SettingsState").OnClientEvent:Connect(onSettingsState))
	table.insert(
		connections,
		player.AncestryChanged:Connect(function()
			if player.Parent == nil then
				cleanup()
			end
		end)
	)
	startTicker()
	refreshAll()
	watchLoading(syncEvent)

	-- ต่อ listener ครบแล้วค่อยขอ snapshot
	task.defer(function()
		syncEvent:FireServer()
	end)
end

return QuestPanelController
