--!strict
-- SanityController: แถบ/ตัวเลขสติของผู้เล่น (ScreenGui ใหม่ SanityGui) กลางบนจอ ใต้กล่องวัน/คืน (DayNightGui)
-- อ่านจาก Attributes บน LocalPlayer (server เขียน) client แค่แสดงผล ไม่ส่งอะไรกลับ

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ClientLanguage = require(ReplicatedStorage.Shared.ClientLanguage)
local DayNight = require(ReplicatedStorage.Shared.Config.DayNight)
local Sanity = require(ReplicatedStorage.Shared.Config.Sanity)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local SanityRules = require(ReplicatedStorage.Shared.SanityRules)

local LOG = "[SanityController]"

type Views = {
	Label: TextLabel,
	Fill: Frame,
}

local SanityController = {}

local connections: { RBXScriptConnection } = {}
local views: Views? = nil

local function round(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function createGui(): Views?
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not playerGui:IsA("PlayerGui") then
		warn(`{LOG} ไม่พบ PlayerGui ไม่สามารถสร้างแถบสติได้`)
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = Sanity.GuiName
	gui.ResetOnSpawn = false
	gui.DisplayOrder = Sanity.GuiDisplayOrder

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, DayNight.TopOffsetPixels + DayNight.HeightPixels + Sanity.TopGapPixels)
	root.Size = UDim2.new(Sanity.WidthScale, 0, 0, Sanity.HeightPixels)
	root.BackgroundColor3 = Sanity.BackgroundColor
	root.BackgroundTransparency = Sanity.BackgroundTransparency
	root.BorderSizePixel = 0
	round(root, Sanity.CornerRadiusPixels)
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(Sanity.MinWidthPixels, Sanity.HeightPixels)
	sizeLimit.MaxSize = Vector2.new(Sanity.MaxWidthPixels, Sanity.HeightPixels)
	sizeLimit.Parent = root
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, Sanity.PaddingPixels)
	padding.PaddingBottom = UDim.new(0, Sanity.PaddingPixels)
	padding.PaddingLeft = UDim.new(0, Sanity.PaddingPixels)
	padding.PaddingRight = UDim.new(0, Sanity.PaddingPixels)
	padding.Parent = root
	root.Parent = gui

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Font = Sanity.Font
	label.TextColor3 = Sanity.TextColor
	label.TextScaled = true
	label.Size = UDim2.fromScale(1, 1 - Sanity.BarHeightScale)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = Sanity.MaxTextSize
	limit.MinTextSize = Sanity.MinTextSize
	limit.Parent = label
	label.Parent = root

	local barBack = Instance.new("Frame")
	barBack.Name = "BarBack"
	barBack.AnchorPoint = Vector2.new(0, 1)
	barBack.Position = UDim2.fromScale(0, 1)
	barBack.Size = UDim2.fromScale(1, Sanity.BarHeightScale)
	barBack.BackgroundColor3 = Sanity.BarBackgroundColor
	barBack.BorderSizePixel = 0
	round(barBack, Sanity.CornerRadiusPixels)
	barBack.Parent = root
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Sanity.BarColorHigh
	fill.BorderSizePixel = 0
	round(fill, Sanity.CornerRadiusPixels)
	fill.Parent = barBack

	gui.Parent = playerGui
	return { Label = label, Fill = fill }
end

local function readNumber(name: string): number?
	local value = Players.LocalPlayer:GetAttribute(name)
	if type(value) == "number" and value == value and math.abs(value) ~= math.huge then
		return value
	end
	return nil
end

local function refresh()
	local ui = views
	if ui == nil then
		return
	end
	local value = readNumber(Sanity.AttributeSanity)
	local max = readNumber(Sanity.AttributeMax)
	if value == nil or max == nil or max <= 0 then
		ui.Label.Text = ""
		ui.Fill.Size = UDim2.fromScale(0, 1)
		return
	end
	local ratio = SanityRules.Ratio(value, max)
	local args: { [string]: string | number } = { sanity = math.round(value), max = math.round(max) }
	ui.Label.Text = Strings.Format("SanityLabel", ClientLanguage.Get(), args)
	local color = Sanity.BarColorHigh
	if ratio < Sanity.LowRatio then
		color = Sanity.BarColorLow
	elseif ratio < Sanity.MidRatio then
		color = Sanity.BarColorMid
	end
	TweenService:Create(
		ui.Fill,
		TweenInfo.new(Sanity.TweenSeconds),
		{ Size = UDim2.fromScale(ratio, 1), BackgroundColor3 = color }
	):Play()
end

local function cleanup()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

function SanityController.Start()
	local player = Players.LocalPlayer
	views = createGui()
	table.insert(connections, player:GetAttributeChangedSignal(Sanity.AttributeSanity):Connect(refresh))
	table.insert(connections, player:GetAttributeChangedSignal(Sanity.AttributeMax):Connect(refresh))
	ClientLanguage.OnChanged(function(_language: string)
		refresh()
	end)
	table.insert(
		connections,
		player.AncestryChanged:Connect(function()
			if player.Parent == nil then
				cleanup()
			end
		end)
	)
	refresh()
end

return SanityController
