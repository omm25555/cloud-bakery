--!strict
-- LobbyController: แสดงสมาชิกกลุ่มและตัวนับถอยหลังตามที่ LobbyService (server) ส่งมา
-- client รับอย่างเดียว ไม่มีทางสั่ง server ได้ (ยกเว้นบอกว่าพร้อมรับ state โดยไม่ส่ง argument)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lobby = require(ReplicatedStorage.Shared.Config.Lobby)
local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LOG = "[LobbyController]"

local LobbyController = {}

local panel: Frame? = nil
local titleLabel: TextLabel? = nil
local membersLabel: TextLabel? = nil
local countdownLabel: TextLabel? = nil

local function createLabel(parent: Frame, name: string, order: number, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.Font = Lobby.UiFont
	label.TextSize = textSize
	label.TextColor3 = Lobby.UiTextColor
	label.Text = ""
	label.Parent = parent
	return label
end

local function createPanel()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not playerGui:IsA("PlayerGui") then
		warn(`{LOG} ไม่พบ PlayerGui ไม่สามารถแสดงสถานะกลุ่มได้`)
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "LobbyGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = Lobby.UiDisplayOrder
	gui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Name = "GroupPanel"
	frame.Visible = false
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -Lobby.UiBottomOffsetPixels)
	frame.Size = UDim2.new(0, Lobby.UiWidthPixels, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Lobby.UiBackgroundColor
	frame.BackgroundTransparency = Lobby.UiBackgroundTransparency
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Lobby.UiCornerRadiusPixels)
	corner.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, Lobby.UiPaddingPixels)
	padding.PaddingBottom = UDim.new(0, Lobby.UiPaddingPixels)
	padding.PaddingLeft = UDim.new(0, Lobby.UiPaddingPixels)
	padding.PaddingRight = UDim.new(0, Lobby.UiPaddingPixels)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Lobby.UiSpacingPixels)
	layout.Parent = frame

	titleLabel = createLabel(frame, "Title", 1, Lobby.UiTitleTextSize)
	membersLabel = createLabel(frame, "Members", 2, Lobby.UiBodyTextSize)
	countdownLabel = createLabel(frame, "Countdown", 3, Lobby.UiCountdownTextSize)
	panel = frame
end

local function onState(payload: any)
	if type(payload) ~= "table" then
		warn(`{LOG} payload ไม่ถูกต้อง ข้าม`)
		return
	end
	local frame, title, members, countdown = panel, titleLabel, membersLabel, countdownLabel
	if frame == nil or title == nil or members == nil or countdown == nil then
		return
	end
	local data: { [string]: any } = payload
	if data.InGroup ~= true then
		frame.Visible = false
		return
	end

	local names = data.Members
	local maxSize = data.MaxSize
	local seconds = data.SecondsLeft
	if type(names) ~= "table" or type(maxSize) ~= "number" or (seconds ~= nil and type(seconds) ~= "number") then
		warn(`{LOG} state ขาดฟิลด์ที่จำเป็น ข้าม`)
		return
	end

	local lines: { string } = {}
	for _, name in names do
		if type(name) == "string" then
			table.insert(lines, name)
		end
	end

	local language = PlayerDataConfig.DefaultLanguage
	title.Text = Strings.Format("UiLobbyGroupTitle", language, { count = #lines, max = maxSize })
	members.Text = table.concat(lines, "\n")
	if type(seconds) == "number" then
		countdown.Text = Strings.Format("UiLobbyCountdown", language, { seconds = seconds })
	else
		countdown.Text = Strings.Format("UiLobbyWaiting", language, nil)
	end
	frame.Visible = true
end

function LobbyController.Start()
	createPanel()
	Remotes.GetEvent("LobbyState").OnClientEvent:Connect(onState)
	-- บอก server ว่าพร้อมรับ state แล้ว (ไม่ส่ง argument)
	Remotes.GetEvent("LobbyReady"):FireServer()
end

return LobbyController
