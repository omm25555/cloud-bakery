--!strict
-- NotifyController: แสดง toast กลางบนจอตามที่ NotifyService (server) ส่งมา
-- client รับอย่างเดียว ไม่มีทางสั่ง server ให้แจ้งเตือน

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local NotifyConfig = require(ReplicatedStorage.Shared.Config.Notify)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local NotifyController = {}

local container: Frame? = nil
local toasts: { Frame } = {}
local nextOrder = 0

local function colorFor(kind: string): Color3
	if kind == "success" then
		return NotifyConfig.Colors.success
	elseif kind == "error" then
		return NotifyConfig.Colors.error
	end
	return NotifyConfig.Colors.info
end

local function createContainer(): Frame?
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not playerGui:IsA("PlayerGui") then
		warn("[NotifyController] ไม่พบ PlayerGui ไม่สามารถแสดง toast ได้")
		return nil
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "NotifyGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = NotifyConfig.DisplayOrder
	gui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Name = "Toasts"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, NotifyConfig.TopOffsetPixels)
	frame.Size = UDim2.new(NotifyConfig.WidthScale, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Parent = gui

	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(NotifyConfig.WidthMaxPixels, math.huge)
	sizeLimit.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, NotifyConfig.SpacingPixels)
	layout.Parent = frame

	return frame
end

local function removeToast(toast: Frame)
	local index = table.find(toasts, toast)
	if index == nil then
		return
	end
	table.remove(toasts, index)

	local info = TweenInfo.new(NotifyConfig.FadeSeconds)
	local label = toast:FindFirstChildOfClass("TextLabel")
	if label then
		TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	end
	local tween = TweenService:Create(toast, info, { BackgroundTransparency = 1 })
	tween.Completed:Once(function()
		toast:Destroy()
	end)
	tween:Play()
end

local function showToast(text: string, kind: string)
	local parent = container
	if parent == nil then
		return
	end

	nextOrder += 1
	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.LayoutOrder = nextOrder
	toast.Size = UDim2.new(1, 0, 0, 0)
	toast.AutomaticSize = Enum.AutomaticSize.Y
	toast.BackgroundColor3 = colorFor(kind)
	toast.BackgroundTransparency = NotifyConfig.BackgroundTransparency
	toast.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, NotifyConfig.CornerRadiusPixels)
	corner.Parent = toast

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, NotifyConfig.PaddingPixels)
	padding.PaddingBottom = UDim.new(0, NotifyConfig.PaddingPixels)
	padding.PaddingLeft = UDim.new(0, NotifyConfig.PaddingPixels)
	padding.PaddingRight = UDim.new(0, NotifyConfig.PaddingPixels)
	padding.Parent = toast

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.Font = NotifyConfig.Font
	label.TextSize = NotifyConfig.TextSize
	label.TextColor3 = NotifyConfig.TextColor
	label.Text = text
	label.Parent = toast

	toast.Parent = parent
	table.insert(toasts, toast)

	while #toasts > NotifyConfig.MaxVisible do
		removeToast(toasts[1])
	end

	task.delay(NotifyConfig.DisplaySeconds, function()
		removeToast(toast)
	end)
end

local function onNotify(payload: any)
	if type(payload) ~= "table" then
		warn("[NotifyController] payload ไม่ถูกต้อง ข้าม")
		return
	end
	local data: { [string]: any } = payload
	local key = data.Key
	local kind = data.Kind
	local language = data.Language
	local args = data.Args
	if type(key) ~= "string" or type(kind) ~= "string" or type(language) ~= "string" then
		warn("[NotifyController] payload ขาดฟิลด์ที่จำเป็น ข้าม")
		return
	end

	local cleanArgs: { [string]: string | number }? = nil
	if type(args) == "table" then
		local collected: { [string]: string | number } = {}
		for name, value in args do
			if type(name) == "string" and (type(value) == "string" or type(value) == "number") then
				collected[name] = value
			end
		end
		cleanArgs = collected
	end

	showToast(Strings.Format(key, language, cleanArgs), kind)
end

function NotifyController.Start()
	container = createContainer()
	Remotes.GetEvent("Notify").OnClientEvent:Connect(onNotify)
	-- บอก server ว่าพร้อมรับ toast แล้ว (ไม่ส่ง argument) server จะส่งที่ค้างอยู่มาให้
	Remotes.GetEvent("NotifyReady"):FireServer()
end

return NotifyController
