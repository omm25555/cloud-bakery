--!strict
-- BakeController: ProximityPrompt ที่โต๊ะผสม/เตาอบ, เมนูเลือกสูตร, มินิเกมจังหวะ และป้ายสถานะเตา
-- client ส่งได้แค่ "ขออบสูตรไหน" / "ขอเก็บ (เตา)" / "เวลาที่กด" server ตัดสินผลทั้งหมด
-- เวลาที่แสดงคำนวณจาก ReadyAt / StartedAt ที่ server ส่งมา

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Bake = require(ReplicatedStorage.Shared.Config.Bake)
local Ingredients = require(ReplicatedStorage.Shared.Config.Ingredients)
local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local Recipes = require(ReplicatedStorage.Shared.Config.Recipes)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local BakeRhythm = require(ReplicatedStorage.Shared.BakeRhythm)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LOG = "[BakeController]"

type OvenView = {
	Id: number,
	Prompt: ProximityPrompt,
	Label: TextLabel,
	State: string,
	RecipeId: string?,
	ReadyAt: number?,
	OwnerName: string?,
	Amount: number?,
}

type MinigameView = {
	Frame: Frame,
	Title: TextLabel,
	Result: TextLabel,
	GoodZone: Frame,
	PerfectZone: Frame,
	Line: Frame,
}

type ActiveMinigame = {
	OvenId: number,
	StartedAt: number,
	Zones: { number },
	TapsSent: number,
	Heartbeat: RBXScriptConnection,
	ActionName: string,
}

local BakeController = {}

local ovenViews: { [number]: OvenView } = {}
local mixingLabel: TextLabel? = nil
local mixingPrompt: ProximityPrompt? = nil
local connections: { RBXScriptConnection } = {}
local tickConnection: RBXScriptConnection? = nil
local inventory: { [string]: number } = {}
local language: string = PlayerDataConfig.DefaultLanguage

local menuFrame: Frame? = nil
local recipeButtons: { [string]: TextButton } = {}
local menuTitle: TextLabel? = nil
local menuClose: TextButton? = nil
local minigameView: MinigameView? = nil
local tapButton: TextButton? = nil
local active: ActiveMinigame? = nil

local startEvent: RemoteEvent
local collectEvent: RemoteEvent
local tapEvent: RemoteEvent

local function ingredientName(ingredientId: string): string
	local ingredient = Ingredients[ingredientId]
	if ingredient == nil then
		return ingredientId
	end
	return if language == "en" then ingredient.DisplayNameEn else ingredient.DisplayNameTh
end

local function dishName(recipeId: string): string
	local recipe = Recipes[recipeId]
	if recipe == nil then
		return recipeId
	end
	return if language == "en" then recipe.DisplayNameEn else recipe.DisplayNameTh
end

local function hasBakingOven(): boolean
	local now = Workspace:GetServerTimeNow()
	for _, view in ovenViews do
		local readyAt = view.ReadyAt
		if view.State == "Baking" and readyAt ~= nil and readyAt > now then
			return true
		end
	end
	return false
end

local function refreshOven(view: OvenView)
	local prompt = view.Prompt
	local label = view.Label
	prompt.ObjectText = Strings.Format("UiOvenObject", language, nil)
	local owner = view.OwnerName or "-"
	local recipeId = view.RecipeId
	local dish = if recipeId then dishName(recipeId) else "-"

	if view.State == "Baking" and recipeId ~= nil and view.ReadyAt ~= nil then
		local remaining = (view.ReadyAt :: number) - Workspace:GetServerTimeNow()
		if remaining > 0 then
			local args: { [string]: string | number } = { dish = dish, seconds = math.ceil(remaining), owner = owner }
			label.Text = Strings.Format("UiOvenBaking", language, args)
			label.TextColor3 = Bake.StateColors.Baking
			prompt.ActionText = Strings.Format("UiOvenPromptCheck", language, nil)
		else
			local args: { [string]: string | number } = { dish = dish, owner = owner }
			label.Text = Strings.Format("UiOvenReady", language, args)
			label.TextColor3 = Bake.StateColors.Ready
			prompt.ActionText = Strings.Format("UiOvenPromptCollect", language, nil)
		end
	elseif view.State == "Minigame" then
		local args: { [string]: string | number } = { owner = owner }
		label.Text = Strings.Format("UiOvenMinigame", language, args)
		label.TextColor3 = Bake.StateColors.Minigame
		prompt.ActionText = Strings.Format("UiOvenPromptCheck", language, nil)
	elseif view.State == "Done" and recipeId ~= nil then
		local args: { [string]: string | number } = { dish = dish, amount = view.Amount or 0, owner = owner }
		label.Text = Strings.Format("UiOvenDone", language, args)
		label.TextColor3 = Bake.StateColors.Done
		prompt.ActionText = Strings.Format("UiOvenPromptCollect", language, nil)
	else
		label.Text = Strings.Format("UiOvenIdle", language, nil)
		label.TextColor3 = Bake.StateColors.Idle
		prompt.ActionText = Strings.Format("UiOvenPromptCheck", language, nil)
	end
end

local function refreshMixing()
	local label = mixingLabel
	if label then
		label.Text = Strings.Format("UiBakeMixLabel", language, nil)
		label.TextColor3 = Bake.TextColor
	end
	local prompt = mixingPrompt
	if prompt then
		prompt.ObjectText = Strings.Format("UiBakeMixObject", language, nil)
		prompt.ActionText = Strings.Format("UiBakeMixPrompt", language, nil)
	end
end

local function refreshAllOvens()
	for _, view in ovenViews do
		refreshOven(view)
	end
end

-- นับถอยหลังเฉพาะตอนมีเตากำลังอบ เลิกฟัง Heartbeat เมื่อไม่มี
local function ensureTicker()
	if tickConnection ~= nil or not hasBakingOven() then
		return
	end
	local elapsed = 0
	tickConnection = RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < Bake.UiRefreshSeconds then
			return
		end
		elapsed = 0
		refreshAllOvens()
		if not hasBakingOven() then
			local connection = tickConnection
			if connection then
				connection:Disconnect()
				tickConnection = nil
			end
		end
	end)
end

local function refreshMenu()
	local title = menuTitle
	if title then
		title.Text = Strings.Format("UiMixTitle", language, nil)
	end
	local close = menuClose
	if close then
		close.Text = Strings.Format("UiMixClose", language, nil)
	end
	local tap = tapButton
	if tap then
		tap.Text = Strings.Format("UiMinigameTap", language, nil)
	end
	for recipeId, button in recipeButtons do
		local recipe = Recipes[recipeId]
		if recipe == nil then
			continue
		end
		local ids: { string } = {}
		for id in recipe.Ingredients do
			table.insert(ids, id)
		end
		table.sort(ids)
		local parts: { string } = {}
		local enough = true
		for _, id in ids do
			local need = recipe.Ingredients[id]
			local have = inventory[id] or 0
			if have < need then
				enough = false
			end
			local args: { [string]: string | number } = { name = ingredientName(id), have = have, need = need }
			table.insert(parts, Strings.Format("UiMixNeedItem", language, args))
		end
		local textArgs: { [string]: string | number } = { dish = dishName(recipeId), needs = table.concat(parts, ", ") }
		button.Text = Strings.Format("UiMixRecipe", language, textArgs)
		button.BackgroundColor3 = if enough then Bake.MenuButtonColor else Bake.MenuButtonDisabledColor
	end
end

local function setLanguage(value: unknown)
	if type(value) == "string" and value ~= language then
		language = value :: string
		refreshAllOvens()
		refreshMixing()
		refreshMenu()
	end
end

local function setMenuVisible(visible: boolean)
	local frame = menuFrame
	if frame then
		frame.Visible = visible
	end
	if visible then
		refreshMenu()
	end
end

local function setZone(view: MinigameView, center: number)
	local mg = Bake.Minigame
	view.GoodZone.Position = UDim2.fromScale(center - mg.GoodHalfWidth, 0)
	view.GoodZone.Size = UDim2.fromScale(mg.GoodHalfWidth * 2, 1)
	view.PerfectZone.Position = UDim2.fromScale(center - mg.PerfectHalfWidth, 0)
	view.PerfectZone.Size = UDim2.fromScale(mg.PerfectHalfWidth * 2, 1)
end

local function refreshMinigameTitle(view: MinigameView, session: ActiveMinigame)
	local args: { [string]: string | number } =
		{ index = math.min(session.TapsSent + 1, Bake.Minigame.TapCount), count = Bake.Minigame.TapCount }
	view.Title.Text = Strings.Format("UiMinigameTitle", language, args)
end

local function closeMinigame()
	local session = active
	active = nil
	if session then
		session.Heartbeat:Disconnect()
		ContextActionService:UnbindAction(session.ActionName)
	end
	local view = minigameView
	if view then
		view.Frame.Visible = false
	end
end

local function sendTap()
	local session = active
	local view = minigameView
	if session == nil or view == nil or session.TapsSent >= Bake.Minigame.TapCount then
		return
	end
	local offset = Workspace:GetServerTimeNow() - session.StartedAt
	session.TapsSent += 1
	tapEvent:FireServer(session.OvenId, offset)
	local nextZone = session.Zones[session.TapsSent + 1]
	if nextZone ~= nil then
		setZone(view, nextZone)
	end
	refreshMinigameTitle(view, session)
end

local function openMinigame(ovenId: number, startedAt: number, zones: { number })
	local view = minigameView
	if view == nil or #zones < Bake.Minigame.TapCount then
		warn(`{LOG} เปิดมินิเกมไม่ได้ (ไม่มี UI หรือโซนไม่ครบ)`)
		return
	end
	closeMinigame()
	setMenuVisible(false)

	local expireAt = startedAt + Bake.Minigame.MaxDurationSeconds + Bake.Minigame.TimeoutGraceSeconds
	local heartbeat = RunService.Heartbeat:Connect(function()
		local now = Workspace:GetServerTimeNow()
		if now >= expireAt then
			closeMinigame()
			return
		end
		view.Line.Position = UDim2.fromScale(BakeRhythm.LinePosition(now - startedAt), 0)
	end)
	-- Sink ปุ่มกด เพื่อไม่ให้ตัวละครกระโดดตอนกด Space
	ContextActionService:BindActionAtPriority(
		Bake.TapActionName,
		function(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult?
			if state == Enum.UserInputState.Begin then
				sendTap()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Bake.TapActionPriority,
		Bake.TapKeyCode
	)
	local session: ActiveMinigame = {
		OvenId = ovenId,
		StartedAt = startedAt,
		Zones = zones,
		TapsSent = 0,
		Heartbeat = heartbeat,
		ActionName = Bake.TapActionName,
	}
	active = session
	view.Result.Text = ""
	setZone(view, zones[1])
	refreshMinigameTitle(view, session)
	view.Frame.Visible = true
end

local function onBakeState(payload: unknown)
	if type(payload) ~= "table" then
		warn(`{LOG} BakeState payload ไม่ถูกต้อง ข้าม`)
		return
	end
	local data = payload :: { [string]: unknown }
	setLanguage(data.Language)
	local entries = data.Ovens
	if type(entries) ~= "table" then
		warn(`{LOG} BakeState ไม่มี Ovens ข้าม`)
		return
	end
	for _, rawEntry in entries :: { unknown } do
		if type(rawEntry) ~= "table" then
			continue
		end
		local entry = rawEntry :: { [string]: unknown }
		local ovenId = entry.OvenId
		local state = entry.State
		if type(ovenId) ~= "number" or type(state) ~= "string" then
			continue
		end
		local view = ovenViews[ovenId :: number]
		if view == nil then
			continue
		end
		view.State = state :: string
		view.RecipeId = if type(entry.RecipeId) == "string" and Recipes[entry.RecipeId :: string] ~= nil
			then entry.RecipeId :: string
			else nil
		view.ReadyAt = if type(entry.ReadyAt) == "number" then entry.ReadyAt :: number else nil
		view.OwnerName = if type(entry.OwnerName) == "string" then entry.OwnerName :: string else nil
		view.Amount = if type(entry.Amount) == "number" then entry.Amount :: number else nil
		refreshOven(view)
		local session = active
		if session and session.OvenId == ovenId and state ~= "Minigame" then
			closeMinigame()
		end
	end
	ensureTicker()
end

local function onBakeMinigame(payload: unknown)
	if type(payload) ~= "table" then
		warn(`{LOG} BakeMinigame payload ไม่ถูกต้อง ข้าม`)
		return
	end
	local data = payload :: { [string]: unknown }
	local ovenId = data.OvenId
	local startedAt = data.StartedAt
	local rawZones = data.Zones
	if type(ovenId) ~= "number" or type(startedAt) ~= "number" or type(rawZones) ~= "table" then
		warn(`{LOG} BakeMinigame ข้อมูลไม่ครบ ข้าม`)
		return
	end
	local zones: { number } = {}
	for _, zone in rawZones :: { unknown } do
		if type(zone) == "number" then
			table.insert(zones, zone :: number)
		end
	end
	openMinigame(ovenId :: number, startedAt :: number, zones)
end

local function onTapResult(payload: unknown)
	if type(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local session = active
	local view = minigameView
	local judgement = data.Judgement
	if session == nil or view == nil or data.OvenId ~= session.OvenId or type(judgement) ~= "string" then
		return
	end
	local key = `UiJudge{judgement :: string}`
	if not Strings.Has(key) then
		return
	end
	view.Result.Text = Strings.Format(key, language, nil)
	view.Result.TextColor3 = Bake.JudgementColors[judgement :: string] or Bake.TextColor
end

local function onInventoryUpdate(payload: unknown)
	if type(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	setLanguage(data.Language)
	local raw = data.Inventory
	if type(raw) ~= "table" then
		return
	end
	local clean: { [string]: number } = {}
	for id, count in raw :: { [unknown]: unknown } do
		if type(id) == "string" and type(count) == "number" then
			clean[id :: string] = count :: number
		end
	end
	inventory = clean
	refreshMenu()
end

local function createLabel(part: BasePart): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "StationStatus"
	gui.Adornee = part
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(Bake.LabelWidthPixels, Bake.LabelHeightPixels)
	gui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + Bake.LabelOffsetStuds, 0)
	gui.MaxDistance = Bake.LabelMaxDistanceStuds
	gui.ResetOnSpawn = false

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Bake.LabelBackgroundColor
	label.BackgroundTransparency = Bake.LabelBackgroundTransparency
	label.TextWrapped = true
	label.Font = Bake.Font
	label.TextSize = Bake.LabelTextSize
	label.TextColor3 = Bake.TextColor
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Bake.LabelCornerRadiusPixels)
	corner.Parent = label
	gui.Parent = part
	return label
end

local function createPrompt(part: BasePart): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.MaxActivationDistance = Bake.InteractDistance
	prompt.HoldDuration = Bake.PromptHoldSeconds
	prompt.KeyboardKeyCode = Bake.PromptKeyCode
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	return prompt
end

local function createStation(part: BasePart)
	local kind = part:GetAttribute(Bake.KindAttribute)
	if kind == Bake.KindMixing and mixingPrompt == nil then
		mixingLabel = createLabel(part)
		local prompt = createPrompt(part)
		mixingPrompt = prompt
		table.insert(
			connections,
			prompt.Triggered:Connect(function()
				setMenuVisible(true)
			end)
		)
		refreshMixing()
	elseif kind == Bake.KindOven then
		local ovenId = part:GetAttribute(Bake.OvenIdAttribute)
		if type(ovenId) ~= "number" or ovenViews[ovenId :: number] ~= nil then
			return
		end
		local id = ovenId :: number
		local prompt = createPrompt(part)
		local view: OvenView = {
			Id = id,
			Prompt = prompt,
			Label = createLabel(part),
			State = "Idle",
			RecipeId = nil,
			ReadyAt = nil,
			OwnerName = nil,
			Amount = nil,
		}
		ovenViews[id] = view
		table.insert(
			connections,
			prompt.Triggered:Connect(function()
				collectEvent:FireServer(id)
			end)
		)
		refreshOven(view)
	end
end

local function watchStations()
	local folder = Workspace:WaitForChild(Bake.FolderName, Bake.ClientWaitSeconds)
	if folder == nil then
		warn(`{LOG} ไม่พบ Workspace.{Bake.FolderName} ไม่สามารถแสดงโต๊ะ/เตาได้`)
		return
	end
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			createStation(child)
		end
	end
	table.insert(
		connections,
		folder.ChildAdded:Connect(function(child: Instance)
			if child:IsA("BasePart") then
				createStation(child)
			end
		end)
	)
end

local function roundCorners(instance: Instance)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Bake.CornerRadiusPixels)
	corner.Parent = instance
end

local function styleText(label: TextLabel | TextButton, size: number)
	if label:IsA("TextLabel") then
		label.Font = Bake.Font
		label.TextSize = size
		label.TextColor3 = Bake.TextColor
		label.TextWrapped = true
	elseif label:IsA("TextButton") then
		label.Font = Bake.Font
		label.TextSize = size
		label.TextColor3 = Bake.TextColor
		label.TextWrapped = true
	end
end

local function createMenu(gui: ScreenGui)
	local frame = Instance.new("Frame")
	frame.Name = "RecipeMenu"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(Bake.MenuWidthPixels, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Bake.MenuBackgroundColor
	frame.BackgroundTransparency = Bake.MenuBackgroundTransparency
	frame.Visible = false
	roundCorners(frame)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, Bake.MenuPaddingPixels)
	padding.PaddingBottom = UDim.new(0, Bake.MenuPaddingPixels)
	padding.PaddingLeft = UDim.new(0, Bake.MenuPaddingPixels)
	padding.PaddingRight = UDim.new(0, Bake.MenuPaddingPixels)
	padding.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Bake.MenuSpacingPixels)
	layout.Parent = frame

	local title = Instance.new("TextLabel")
	title.LayoutOrder = 0
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, Bake.MenuTitleHeightPixels)
	styleText(title, Bake.MenuTextSize)
	title.Parent = frame
	menuTitle = title

	for order, recipeId in Bake.RecipeOrder do
		local button = Instance.new("TextButton")
		button.Name = recipeId
		button.LayoutOrder = order
		button.Size = UDim2.new(1, 0, 0, Bake.MenuButtonHeightPixels)
		button.AutoButtonColor = true
		styleText(button, Bake.MenuTextSize)
		roundCorners(button)
		button.Parent = frame
		recipeButtons[recipeId] = button
		table.insert(
			connections,
			button.Activated:Connect(function()
				startEvent:FireServer(recipeId)
				setMenuVisible(false)
			end)
		)
	end

	local close = Instance.new("TextButton")
	close.LayoutOrder = #Bake.RecipeOrder + 1
	close.Size = UDim2.new(1, 0, 0, Bake.MenuTitleHeightPixels)
	close.BackgroundColor3 = Bake.MenuCloseButtonColor
	styleText(close, Bake.MenuTextSize)
	roundCorners(close)
	close.Parent = frame
	menuClose = close
	table.insert(
		connections,
		close.Activated:Connect(function()
			setMenuVisible(false)
		end)
	)

	frame.Parent = gui
	menuFrame = frame
end

local function createMinigame(gui: ScreenGui)
	local frame = Instance.new("Frame")
	frame.Name = "Minigame"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -Bake.MinigameBottomOffsetPixels)
	frame.Size = UDim2.fromOffset(Bake.MinigameWidthPixels, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Bake.MenuBackgroundColor
	frame.BackgroundTransparency = Bake.MenuBackgroundTransparency
	frame.Visible = false
	roundCorners(frame)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, Bake.MinigamePaddingPixels)
	padding.PaddingBottom = UDim.new(0, Bake.MinigamePaddingPixels)
	padding.PaddingLeft = UDim.new(0, Bake.MinigamePaddingPixels)
	padding.PaddingRight = UDim.new(0, Bake.MinigamePaddingPixels)
	padding.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Bake.MinigameSpacingPixels)
	layout.Parent = frame

	local title = Instance.new("TextLabel")
	title.LayoutOrder = 1
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, Bake.MenuTitleHeightPixels)
	styleText(title, Bake.MinigameTextSize)
	title.Parent = frame

	local bar = Instance.new("Frame")
	bar.LayoutOrder = 2
	bar.Size = UDim2.new(1, 0, 0, Bake.MinigameBarHeightPixels)
	bar.BackgroundColor3 = Bake.MinigameBarColor
	bar.BorderSizePixel = 0
	bar.ClipsDescendants = true
	bar.Parent = frame

	local goodZone = Instance.new("Frame")
	goodZone.BackgroundColor3 = Bake.MinigameGoodColor
	goodZone.BorderSizePixel = 0
	goodZone.Parent = bar
	local perfectZone = Instance.new("Frame")
	perfectZone.BackgroundColor3 = Bake.MinigamePerfectColor
	perfectZone.BorderSizePixel = 0
	perfectZone.ZIndex = 2
	perfectZone.Parent = bar
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Size = UDim2.new(0, Bake.MinigameLineWidthPixels, 1, 0)
	line.BackgroundColor3 = Bake.MinigameLineColor
	line.BorderSizePixel = 0
	line.ZIndex = 3
	line.Parent = bar

	local result = Instance.new("TextLabel")
	result.LayoutOrder = 3
	result.BackgroundTransparency = 1
	result.Size = UDim2.new(1, 0, 0, Bake.MenuTitleHeightPixels)
	styleText(result, Bake.MinigameTextSize)
	result.Text = ""
	result.Parent = frame

	local tap = Instance.new("TextButton")
	tap.LayoutOrder = 4
	tap.Size = UDim2.new(1, 0, 0, Bake.TapButtonHeightPixels)
	tap.BackgroundColor3 = Bake.TapButtonColor
	styleText(tap, Bake.MinigameTextSize)
	roundCorners(tap)
	tap.Parent = frame
	tapButton = tap
	table.insert(connections, tap.Activated:Connect(sendTap))

	frame.Parent = gui
	minigameView = {
		Frame = frame,
		Title = title,
		Result = result,
		GoodZone = goodZone,
		PerfectZone = perfectZone,
		Line = line,
	}
end

local function createGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not playerGui:IsA("PlayerGui") then
		warn(`{LOG} ไม่พบ PlayerGui ไม่สามารถแสดงเมนูอบได้`)
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = Bake.GuiName
	gui.ResetOnSpawn = false
	gui.DisplayOrder = Bake.GuiDisplayOrder
	createMenu(gui)
	createMinigame(gui)
	gui.Parent = playerGui
	refreshMenu()
end

local function cleanup()
	closeMinigame()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	local ticker = tickConnection
	if ticker then
		ticker:Disconnect()
		tickConnection = nil
	end
end

function BakeController.Start()
	startEvent = Remotes.GetEvent("BakeStart")
	collectEvent = Remotes.GetEvent("BakeCollect")
	tapEvent = Remotes.GetEvent("BakeTap")

	createGui()
	table.insert(connections, Remotes.GetEvent("BakeState").OnClientEvent:Connect(onBakeState))
	table.insert(connections, Remotes.GetEvent("BakeMinigame").OnClientEvent:Connect(onBakeMinigame))
	table.insert(connections, Remotes.GetEvent("BakeTapResult").OnClientEvent:Connect(onTapResult))
	table.insert(connections, Remotes.GetEvent("InventoryUpdate").OnClientEvent:Connect(onInventoryUpdate))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player: Player)
			if player == Players.LocalPlayer then
				cleanup()
			end
		end)
	)

	-- Start ต้องไม่บล็อก bootstrap: รอสถานีใน thread แยก แล้วค่อยขอ snapshot
	task.spawn(function()
		watchStations()
		Remotes.GetEvent("BakeSync"):FireServer()
	end)
end

return BakeController
