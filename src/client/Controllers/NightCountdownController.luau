--!strict
-- NightCountdownController: แถบนับถอยหลัง "เช้าในอีก N วินาที" เมื่อลูกค้ากลางคืนครบแล้วจบคืนเร็ว (ScreenGui ใหม่ NightCountdownGui)
-- อ่านเวลาจบ (เวลา server) จาก attribute บน ReplicatedStorage (Config/Report.CountdownAttribute) ซึ่ง server ตั้ง/ล้าง client แค่แสดงผล
-- วางใต้แถบสติ (SanityGui) กลางบนจอ

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ClientLanguage = require(ReplicatedStorage.Shared.ClientLanguage)
local DayNight = require(ReplicatedStorage.Shared.Config.DayNight)
local Report = require(ReplicatedStorage.Shared.Config.Report)
local Sanity = require(ReplicatedStorage.Shared.Config.Sanity)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)

local LOG = "[NightCountdownController]"

local NightCountdownController = {}

local connections: { RBXScriptConnection } = {}
local frame: Frame? = nil
local label: TextLabel? = nil
local running = false

local function createGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not playerGui:IsA("PlayerGui") then
		warn(`{LOG} ไม่พบ PlayerGui ไม่สามารถสร้างแถบนับถอยหลังได้`)
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = Report.CountdownGuiName
	gui.ResetOnSpawn = false
	gui.DisplayOrder = Report.CountdownGuiDisplayOrder

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(
		0.5,
		0,
		0,
		DayNight.TopOffsetPixels + DayNight.HeightPixels + Sanity.TopGapPixels + Sanity.HeightPixels + Report.CountdownGapPixels
	)
	root.Size = UDim2.new(Report.CountdownWidthScale, 0, 0, Report.CountdownHeightPixels)
	root.BackgroundColor3 = Report.CountdownBackgroundColor
	root.BackgroundTransparency = Report.CountdownBackgroundTransparency
	root.BorderSizePixel = 0
	root.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Report.CountdownCornerRadiusPixels)
	corner.Parent = root
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(Report.CountdownMinWidthPixels, Report.CountdownHeightPixels)
	sizeLimit.MaxSize = Vector2.new(Report.CountdownMaxWidthPixels, Report.CountdownHeightPixels)
	sizeLimit.Parent = root
	root.Parent = gui

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Report.Font
	text.TextColor3 = Report.CountdownTextColor
	text.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = Report.MaxTextSize
	limit.MinTextSize = Report.MinTextSize
	limit.Parent = text
	text.Parent = root

	gui.Parent = playerGui
	frame = root
	label = text
end

local function refresh()
	local root = frame
	local text = label
	if root == nil or text == nil then
		return
	end
	local endsAt = ReplicatedStorage:GetAttribute(Report.CountdownAttribute)
	if type(endsAt) ~= "number" then
		root.Visible = false
		return
	end
	local remaining = endsAt - Workspace:GetServerTimeNow()
	if remaining <= 0 then
		root.Visible = false
		return
	end
	local args: { [string]: string | number } = { seconds = math.ceil(remaining) }
	text.Text = Strings.Format("NightEndingCountdown", ClientLanguage.Get(), args)
	root.Visible = true
end

-- วนอัปเดตเฉพาะตอนมีการนับถอยหลัง (ไม่ทำงานตลอดเวลา)
local function loop()
	if running then
		return
	end
	running = true
	task.spawn(function()
		while type(ReplicatedStorage:GetAttribute(Report.CountdownAttribute)) == "number" do
			refresh()
			task.wait(Report.CountdownRefreshSeconds)
		end
		refresh()
		running = false
	end)
end

local function cleanup()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

function NightCountdownController.Start()
	local player = Players.LocalPlayer
	createGui()
	table.insert(connections, ReplicatedStorage:GetAttributeChangedSignal(Report.CountdownAttribute):Connect(loop))
	table.insert(
		connections,
		player.AncestryChanged:Connect(function()
			if player.Parent == nil then
				cleanup()
			end
		end)
	)
	loop()
end

return NightCountdownController
