--!strict
-- SettingsPanelController: แผง Settings เลือกภาษา ไทย/อังกฤษ
-- client ส่งได้แค่ค่าภาษาที่เลือก server ตรวจและเขียนข้อมูลเอง ผลจริงกลับมาทาง SettingsState
-- ระหว่างรอคำตอบปุ่มจะถูกปิดชั่วคราว และกลับมากดได้เสมอเมื่อครบเวลา (กรณี server ปฏิเสธหรือไม่ตอบ)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MenuConfig = require(ReplicatedStorage.Shared.Config.Menu)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local MenuController = require(script.Parent.MenuController)

local SettingsPanelController = {}

local languageButtons: { [string]: TextButton } = {}
local headingLabel: TextLabel? = nil
local pendingLanguage: string? = nil
local requestToken = 0

local function applyButtons(language: string)
	local waiting = pendingLanguage ~= nil
	for id, button in languageButtons do
		local active = id == language
		button.BackgroundColor3 = if active then MenuConfig.LanguageActiveColor else MenuConfig.LanguageIdleColor
		button.Active = not waiting
		button.AutoButtonColor = not waiting
	end
end

local function refresh(state: MenuController.State)
	-- ภาษาที่ server ยืนยันแล้วเท่ากับที่ขอ = จบการรอ
	if pendingLanguage ~= nil and pendingLanguage == state.Language then
		pendingLanguage = nil
	end
	local heading = headingLabel
	if heading then
		heading.Text = Strings.Format("UiSettingsLanguage", state.Language, nil)
	end
	applyButtons(state.Language)
end

local function onLanguageClicked(id: string)
	if pendingLanguage ~= nil then
		return
	end
	local event = Remotes.GetEvent("SettingsSetLanguage")
	pendingLanguage = id
	requestToken += 1
	local token = requestToken
	applyButtons(MenuController.GetState().Language)
	event:FireServer(id)
	task.delay(MenuConfig.LanguageRequestTimeoutSeconds, function()
		if requestToken == token and pendingLanguage ~= nil then
			pendingLanguage = nil
			applyButtons(MenuController.GetState().Language)
		end
	end)
end

local function build(content: Frame)
	local column = MenuController.CreateColumn(content, 1, false)
	local heading = MenuController.CreateLabel(column, MenuConfig.BodyTextSize, MenuConfig.TextColor, 1)
	headingLabel = heading
	for index, id in MenuConfig.LanguageOrder do
		local button = Instance.new("TextButton")
		button.Name = id
		button.LayoutOrder = index + 1
		button.Size = UDim2.new(1, 0, 0, MenuConfig.LanguageButtonHeightPixels)
		button.BorderSizePixel = 0
		button.Font = MenuConfig.Font
		button.TextSize = MenuConfig.BodyTextSize
		button.TextColor3 = MenuConfig.LanguageButtonTextColor
		button.Text = MenuConfig.LanguageNames[id] or id
		button.Parent = column
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, MenuConfig.CornerRadiusPixels)
		corner.Parent = button
		languageButtons[id] = button
		button.Activated:Connect(function()
			onLanguageClicked(id)
		end)
	end
end

function SettingsPanelController.Start()
	MenuController.RegisterPanel({
		Id = MenuConfig.Ids.Settings,
		TitleKey = "UiSettingsTitle",
		Build = build,
		Refresh = refresh,
	})
end

return SettingsPanelController
