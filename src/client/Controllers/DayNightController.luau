--!strict
-- DayNightController: แสดง phase/เลขวัน-คืน/เวลาที่เหลือ (DayNightGui มุมซ้ายบน) และปรับ Lighting ตามสถานะจาก server
-- อ่านจาก Attributes บน ReplicatedStorage เท่านั้น (server เป็นผู้ตัดสิน) client แค่แสดงผล ไม่ส่งอะไรกลับ
-- ถ้ายังไม่มีสถานะ (ยังไม่เริ่ม/หยุดนับ) แสดงข้อความ "กำลังเตรียมวัน" และไม่แตะ Lighting

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DayNight = require(ReplicatedStorage.Shared.Config.DayNight)
local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local DayNightRules = require(ReplicatedStorage.Shared.DayNightRules)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LOG = "[DayNightController]"

type Phase = DayNight.Phase

type View = {
	Phase: Phase,
	Day: number,
	PhaseSeconds: number,
	EndsAt: number?,
}

type Views = {
	Title: TextLabel,
	Counter: TextLabel,
	Time: TextLabel,
}

local LABEL_KEYS: { [string]: string } = {
	Day = "DayNightLabelDay",
	Dusk = "DayNightLabelDusk",
	Night = "DayNightLabelNight",
	Dawn = "DayNightLabelDawn",
}

local DayNightController = {}

local connections: { RBXScriptConnection } = {}
local views: Views? = nil
local atmosphere: Atmosphere? = nil
local language: string = PlayerDataConfig.DefaultLanguage
local lastUiAt = -math.huge
local lastSteadyPhase: Phase? = nil
local dirty = true

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value :: number) ~= math.huge
end

local function readView(): View?
	local phaseValue = ReplicatedStorage:GetAttribute(DayNight.AttributePhase)
	local dayValue = ReplicatedStorage:GetAttribute(DayNight.AttributeDay)
	local secondsValue = ReplicatedStorage:GetAttribute(DayNight.AttributePhaseSeconds)
	if not DayNightRules.IsPhase(phaseValue) or not isFiniteNumber(dayValue) or not isFiniteNumber(secondsValue) then
		return nil
	end
	local endsAtValue = ReplicatedStorage:GetAttribute(DayNight.AttributePhaseEndsAt)
	return {
		Phase = phaseValue :: Phase,
		Day = dayValue :: number,
		PhaseSeconds = secondsValue :: number,
		EndsAt = if isFiniteNumber(endsAtValue) then endsAtValue :: number else nil,
	}
end

local function round(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function makeLabel(parent: Instance, name: string, alignment: Enum.TextXAlignment): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = DayNight.Font
	label.TextColor3 = DayNight.TextColor
	label.TextSize = DayNight.MaxTextSize
	label.TextScaled = true
	label.TextXAlignment = alignment
	label.TextTruncate = Enum.TextTruncate.AtEnd
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = DayNight.MaxTextSize
	limit.MinTextSize = DayNight.MinTextSize
	limit.Parent = label
	label.Parent = parent
	return label
end

local function createGui(): Views?
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not playerGui:IsA("PlayerGui") then
		warn(`{LOG} ไม่พบ PlayerGui ไม่สามารถสร้างหน้าจอวัน/คืนได้`)
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = DayNight.GuiName
	gui.ResetOnSpawn = false
	gui.DisplayOrder = DayNight.GuiDisplayOrder

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(0, 0)
	root.Position = UDim2.fromOffset(DayNight.MarginPixels, DayNight.MarginPixels)
	root.Size = UDim2.new(DayNight.WidthScale, 0, 0, DayNight.HeightPixels)
	root.BackgroundColor3 = DayNight.BackgroundColor
	root.BackgroundTransparency = DayNight.BackgroundTransparency
	root.BorderSizePixel = 0
	round(root, DayNight.CornerRadiusPixels)
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(DayNight.MinWidthPixels, DayNight.HeightPixels)
	sizeLimit.MaxSize = Vector2.new(DayNight.MaxWidthPixels, DayNight.HeightPixels)
	sizeLimit.Parent = root
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, DayNight.PaddingPixels)
	padding.PaddingBottom = UDim.new(0, DayNight.PaddingPixels)
	padding.PaddingLeft = UDim.new(0, DayNight.PaddingPixels)
	padding.PaddingRight = UDim.new(0, DayNight.PaddingPixels)
	padding.Parent = root
	root.Parent = gui

	local title = makeLabel(root, "Title", Enum.TextXAlignment.Left)
	title.Size = UDim2.fromScale(1, DayNight.TitleHeightScale)
	title.TextColor3 = DayNight.DayAccentColor

	local counter = makeLabel(root, "Counter", Enum.TextXAlignment.Left)
	counter.AnchorPoint = Vector2.new(0, 1)
	counter.Position = UDim2.fromScale(0, 1)
	counter.Size = UDim2.fromScale(0.5, 1 - DayNight.TitleHeightScale)
	counter.TextColor3 = DayNight.SubTextColor

	local time = makeLabel(root, "Time", Enum.TextXAlignment.Right)
	time.AnchorPoint = Vector2.new(1, 1)
	time.Position = UDim2.fromScale(1, 1)
	time.Size = UDim2.fromScale(0.5, 1 - DayNight.TitleHeightScale)

	gui.Parent = playerGui
	return { Title = title, Counter = counter, Time = time }
end

local function refreshUi(view: View?)
	local ui = views
	if ui == nil then
		return
	end
	local endsAt = if view ~= nil then view.EndsAt else nil
	if view == nil or endsAt == nil then
		ui.Title.Text = Strings.Format("DayNightPreparing", language, nil)
		ui.Title.TextColor3 = DayNight.SubTextColor
		ui.Counter.Text = ""
		ui.Time.Text = ""
		return
	end
	local isDayLike = view.Phase == "Day" or view.Phase == "Dawn"
	local counterKey = if view.Phase == "Day" then "DayNightCounterDay" else "DayNightCounterNight"
	ui.Title.Text = Strings.Format(LABEL_KEYS[view.Phase], language, nil)
	ui.Title.TextColor3 = if isDayLike then DayNight.DayAccentColor else DayNight.NightAccentColor
	local counterArgs: { [string]: number | string } = { day = view.Day }
	ui.Counter.Text = Strings.Format(counterKey, language, counterArgs)
	local remaining = DayNightRules.Remaining(endsAt, Workspace:GetServerTimeNow())
	ui.Time.Text = DayNightRules.FormatClock(remaining)
end

local function getAtmosphere(): Atmosphere
	local existing = atmosphere
	if existing ~= nil and existing.Parent == Lighting then
		return existing
	end
	local found = Lighting:FindFirstChildOfClass("Atmosphere")
	if found == nil then
		found = Instance.new("Atmosphere")
		found.Name = DayNight.AtmosphereName
		found.Parent = Lighting
	end
	atmosphere = found
	return found
end

local function applyLighting(view: View)
	local fraction = 0
	local endsAt = view.EndsAt
	if endsAt ~= nil then
		local remaining = DayNightRules.Remaining(endsAt, Workspace:GetServerTimeNow())
		fraction = DayNightRules.Fraction(remaining, view.PhaseSeconds)
	end
	local alpha = DayNightRules.NightAlpha(view.Phase, fraction)
	local dayLook = DayNight.DayLook
	local nightLook = DayNight.NightLook
	Lighting.ClockTime = DayNightRules.ClockTime(view.Phase, fraction)
	Lighting.Brightness = DayNightRules.Lerp(dayLook.Brightness, nightLook.Brightness, alpha)
	Lighting.ExposureCompensation =
		DayNightRules.Lerp(dayLook.ExposureCompensation, nightLook.ExposureCompensation, alpha)
	Lighting.Ambient = dayLook.Ambient:Lerp(nightLook.Ambient, alpha)
	Lighting.OutdoorAmbient = dayLook.OutdoorAmbient:Lerp(nightLook.OutdoorAmbient, alpha)
	Lighting.ColorShift_Top = dayLook.ColorShiftTop:Lerp(nightLook.ColorShiftTop, alpha)
	local sky = getAtmosphere()
	sky.Color = dayLook.AtmosphereColor:Lerp(nightLook.AtmosphereColor, alpha)
	sky.Decay = dayLook.AtmosphereDecay:Lerp(nightLook.AtmosphereDecay, alpha)
	sky.Density = DayNightRules.Lerp(dayLook.AtmosphereDensity, nightLook.AtmosphereDensity, alpha)
	sky.Haze = DayNightRules.Lerp(dayLook.AtmosphereHaze, nightLook.AtmosphereHaze, alpha)
end

local function onHeartbeat()
	local view = readView()
	local now = os.clock()
	if dirty or now - lastUiAt >= DayNight.RefreshSeconds then
		lastUiAt = now
		refreshUi(view)
	end
	if view == nil then
		lastSteadyPhase = nil
		dirty = false
		return
	end
	-- Dusk/Dawn ไล่ lighting ทุกเฟรม ส่วน Day/Night ตั้งครั้งเดียวต่อ phase
	local transitional = view.Phase == "Dusk" or view.Phase == "Dawn"
	if transitional or dirty or lastSteadyPhase ~= view.Phase then
		applyLighting(view)
		lastSteadyPhase = if transitional then nil else view.Phase
	end
	dirty = false
end

local function parseLanguage(value: unknown): string?
	if value == "th" or value == "en" then
		return value :: string
	end
	return nil
end

local function onLanguagePayload(payload: unknown)
	if type(payload) ~= "table" then
		return
	end
	local valid = parseLanguage((payload :: { [string]: unknown }).Language)
	if valid ~= nil and valid ~= language then
		language = valid
		dirty = true
	end
end

local function cleanup()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

function DayNightController.Start()
	local player = Players.LocalPlayer
	views = createGui()
	dirty = true

	table.insert(connections, Remotes.GetEvent("ServeState").OnClientEvent:Connect(onLanguagePayload))
	table.insert(connections, Remotes.GetEvent("InventoryUpdate").OnClientEvent:Connect(onLanguagePayload))
	table.insert(connections, Remotes.GetEvent("SettingsState").OnClientEvent:Connect(onLanguagePayload))
	table.insert(connections, RunService.Heartbeat:Connect(onHeartbeat))
	table.insert(
		connections,
		player.AncestryChanged:Connect(function()
			if player.Parent == nil then
				cleanup()
			end
		end)
	)
end

return DayNightController
