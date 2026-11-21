--!strict
-- โต๊ะผสม: เลือกสูตร แล้วเล่นมินิเกมจังหวะ (แถบแนวนอน เส้นวิ่ง กดตอนถึงดาว)
-- client แค่จับเวลาที่กดแล้วส่งให้ server ตัดสิน ผล Perfect/Good ที่เด้งระหว่างเล่นเป็นแค่ฟีดแบ็ก

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = Shared.Config
local Minigame = require(Config.Minigame)
local Progression = require(Config.Progression)
local Recipes = require(Config.Recipes)
local Formulas = require(Shared.Formulas)
local Locale = require(Shared.Locale)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local UI = require(script.Parent.Parent.Modules.UI)
local StateController = require(script.Parent.StateController)
local NotifyController = require(script.Parent.NotifyController)

local BakeController = {}

local TRACK_WIDTH = 560
local TRACK_HEIGHT = 64
local TAP_ACTION = "CloudBakeryMixTap"

local gui: ScreenGui
local picker: Frame? = nil
local playing = false

local function closePicker()
	local frame = picker
	if frame then
		frame:Destroy()
	end
	picker = nil
end

local function floatText(parent: GuiObject, text: string, color: Color3, x: number)
	local label = UI.label({
		parent = parent,
		text = text,
		size = UDim2.fromOffset(160, 40),
		position = UDim2.new(0, x, 0, -10),
		anchor = Vector2.new(0.5, 1),
		textSize = 28,
		color = color,
		alignX = Enum.TextXAlignment.Center,
		zindex = 30,
	})
	local tween = TweenService:Create(label, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, x, 0, -60),
		TextTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		label:Destroy()
	end)
end

local function runMinigame(result: Types.StartMixResult)
	local beats = result.beats
	local duration = result.duration
	local sessionId = result.sessionId
	local recipeId = result.recipeId
	if beats == nil or duration == nil or sessionId == nil or recipeId == nil then
		warn("[BakeController] ข้อมูลมินิเกมจาก server ไม่ครบ")
		NotifyController.show("error", "n.unexpected")
		return
	end
	playing = true
	local frame = UI.frame({
		name = "Minigame",
		parent = gui,
		size = UDim2.fromOffset(TRACK_WIDTH + 60, 300),
		position = UDim2.new(0.5, 0, 1, -130),
		anchor = Vector2.new(0.5, 1),
		color = UI.Colors.Cream,
		radius = 24,
		stroke = UI.Colors.Pink,
		strokeThickness = 4,
		zindex = 20,
	})
	UI.label({
		parent = frame,
		text = `{Locale.icon(recipeId)} {StateController.t("mix.title", { recipe = `item.{recipeId}` })}`,
		size = UDim2.new(1, -20, 0, 36),
		position = UDim2.fromOffset(10, 8),
		textSize = 24,
		color = UI.Colors.Purple,
		alignX = Enum.TextXAlignment.Center,
		zindex = 21,
	})
	UI.label({
		parent = frame,
		text = StateController.t("mix.hint"),
		size = UDim2.new(1, -20, 0, 22),
		position = UDim2.fromOffset(10, 44),
		textSize = 15,
		font = UI.FontBody,
		color = UI.Colors.TextSoft,
		alignX = Enum.TextXAlignment.Center,
		zindex = 21,
	})
	local track = UI.frame({
		name = "Track",
		parent = frame,
		size = UDim2.fromOffset(TRACK_WIDTH, TRACK_HEIGHT),
		position = UDim2.new(0.5, 0, 0, 110),
		anchor = Vector2.new(0.5, 0),
		color = UI.Colors.PinkLight,
		radius = TRACK_HEIGHT // 2,
		stroke = UI.Colors.PurpleLight,
		strokeThickness = 3,
		zindex = 21,
	})
	local stars: { TextLabel } = {}
	for _, beat in beats do
		local x = beat / duration * TRACK_WIDTH
		local star = UI.label({
			parent = track,
			text = Locale.icon("Star"),
			size = UDim2.fromOffset(44, 44),
			position = UDim2.new(0, x, 0.5, 0),
			anchor = Vector2.new(0.5, 0.5),
			textSize = 34,
			alignX = Enum.TextXAlignment.Center,
			zindex = 22,
		})
		table.insert(stars, star)
	end
	local cursor = UI.frame({
		name = "Cursor",
		parent = track,
		size = UDim2.fromOffset(6, TRACK_HEIGHT + 20),
		position = UDim2.new(0, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		color = UI.Colors.Purple,
		radius = 3,
		zindex = 23,
	})
	local tapButton = UI.button({
		parent = frame,
		text = StateController.t("mix.tap"),
		size = UDim2.fromOffset(220, 60),
		position = UDim2.new(0.5, 0, 1, -14),
		anchor = Vector2.new(0.5, 1),
		color = UI.Colors.Pink,
		textSize = 30,
		radius = 30,
		zindex = 21,
	})
	local closeButton = UI.button({
		parent = frame,
		text = "X",
		size = UDim2.fromOffset(36, 36),
		position = UDim2.new(1, -44, 0, 8),
		color = UI.Colors.PurpleLight,
		textSize = 20,
		radius = 18,
		zindex = 22,
	})

	local taps: { number } = {}
	local judged: { [number]: boolean } = {}
	local startedAt = os.clock()
	local finished = false
	local cancelled = false

	local function tap()
		if finished then
			return
		end
		local t = os.clock() - startedAt
		if #taps >= Minigame.MaxTaps then
			return
		end
		table.insert(taps, t)
		-- ฟีดแบ็กทันที (server จะตัดสินผลจริงอีกครั้ง)
		local bestIndex: number? = nil
		local bestError = math.huge
		for index, beat in beats do
			local err = math.abs(t - beat)
			if not judged[index] and err < bestError then
				bestError = err
				bestIndex = index
			end
		end
		local x = math.clamp(t / duration, 0, 1) * TRACK_WIDTH
		if bestIndex and bestError <= Minigame.PerfectWindowSeconds then
			judged[bestIndex] = true
			stars[bestIndex].TextTransparency = 0.6
			floatText(track, `{StateController.t("mix.Perfect")} {Locale.icon("Note")}`, UI.Colors.GoldDark, x)
		elseif bestIndex and bestError <= Minigame.GoodWindowSeconds then
			judged[bestIndex] = true
			stars[bestIndex].TextTransparency = 0.6
			floatText(track, `{StateController.t("mix.Good")} {Locale.icon("Note")}`, UI.Colors.Green, x)
		else
			floatText(track, StateController.t("mix.Miss"), UI.Colors.TextSoft, x)
		end
	end

	local connections: { RBXScriptConnection } = {}
	table.insert(connections, tapButton.Activated:Connect(tap))
	-- จับ Space ระหว่างมินิเกม (กันตัวละครกระโดด)
	ContextActionService:BindActionAtPriority(TAP_ACTION, function(_name: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
		if inputState == Enum.UserInputState.Begin then
			tap()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space)
	table.insert(connections, closeButton.Activated:Connect(function()
		cancelled = true
		finished = true
	end))
	table.insert(connections, RunService.RenderStepped:Connect(function()
		local t = os.clock() - startedAt
		cursor.Position = UDim2.new(0, math.clamp(t / duration, 0, 1) * TRACK_WIDTH, 0.5, 0)
		if t >= duration then
			finished = true
		end
	end))

	while not finished do
		task.wait()
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	ContextActionService:UnbindAction(TAP_ACTION)

	if cancelled then
		Remotes.GetEvent("CancelMix"):FireServer()
		frame:Destroy()
		playing = false
		return
	end

	tapButton.Text = "..."
	local ok, finish = pcall(function()
		return Remotes.GetFunction("FinishMix"):InvokeServer(sessionId, taps)
	end)
	if not ok then
		warn(`[BakeController] ส่งผลมินิเกมไม่สำเร็จ: {finish}`)
		NotifyController.show("error", "n.unexpected")
	elseif typeof(finish) == "table" and finish.ok == true and typeof(finish.quality) == "string" then
		local quality: string = finish.quality
		tapButton.Text = StateController.t(`mix.{quality}`)
		tapButton.BackgroundColor3 = if quality == "Perfect" then UI.Colors.Gold elseif quality == "Good" then UI.Colors.Green else UI.Colors.PurpleLight
		task.wait(Minigame.ResultDisplaySeconds)
	end
	frame:Destroy()
	playing = false
end

local function startMix(recipeId: string)
	closePicker()
	local ok, result = pcall(function()
		return Remotes.GetFunction("StartMix"):InvokeServer(recipeId)
	end)
	if not ok then
		warn(`[BakeController] ขอเริ่มผสมไม่สำเร็จ: {result}`)
		NotifyController.show("error", "n.unexpected")
		return
	end
	if typeof(result) ~= "table" or result.ok ~= true then
		-- server แจ้งเหตุผลผ่าน NotifyService แล้ว
		return
	end
	local typed: Types.StartMixResult = result
	runMinigame(typed)
end

local function openPicker()
	if playing then
		return
	end
	closePicker()
	local state = StateController.get()
	if state == nil then
		NotifyController.show("warn", "n.loading")
		return
	end
	local frame = UI.frame({
		name = "RecipePicker",
		parent = gui,
		size = UDim2.fromOffset(520, 0),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = UI.Colors.Cream,
		radius = 22,
		stroke = UI.Colors.PurpleLight,
		strokeThickness = 4,
		zindex = 15,
	})
	frame.AutomaticSize = Enum.AutomaticSize.Y
	UI.padding(frame, 8)
	UI.list(frame, 8)
	local header, title, sub = UI.header(frame, 50, "🥣")
	header.LayoutOrder = 0
	title.Text = StateController.t("mix.pick")
	sub.Text = StateController.tOther("mix.pick")
	local close = UI.button({ parent = header, text = "X", size = UDim2.fromOffset(38, 38), position = UDim2.new(1, -44, 0, 6), color = UI.Colors.Pink, textSize = 20, radius = 19 })
	close.Activated:Connect(closePicker)

	for index, recipeId in Progression.RecipeOrder do
		local recipe = Recipes[recipeId]
		local unlocked = Formulas.isRecipeUnlocked(recipeId, state.level)
		local enough = true
		local needs: { string } = {}
		for _, ingredientId in Progression.IngredientOrder do
			local need = recipe.Ingredients[ingredientId]
			if need then
				local have = state.ingredients[ingredientId] or 0
				enough = enough and have >= need
				table.insert(needs, `{Locale.icon(ingredientId)} {have}/{need}`)
			end
		end
		local row = UI.frame({ parent = frame, size = UDim2.new(1, 0, 0, 74), color = if unlocked then UI.Colors.White else UI.Colors.CreamDark, radius = 14 })
		row.LayoutOrder = index
		UI.label({ parent = row, text = if unlocked then Locale.icon(recipeId) else Locale.icon("Lock"), size = UDim2.fromOffset(70, 74), textSize = 40, alignX = Enum.TextXAlignment.Center })
		UI.label({ parent = row, text = StateController.t(`item.{recipeId}`), size = UDim2.new(1, -220, 0, 28), position = UDim2.fromOffset(72, 6), textSize = 19 })
		local detail = if unlocked then table.concat(needs, "   ") else StateController.t("recipes.locked", { level = Progression.RecipeUnlockLevel[recipeId] })
		UI.label({ parent = row, text = detail, size = UDim2.new(1, -220, 0, 26), position = UDim2.fromOffset(72, 38), textSize = 15, font = UI.FontBody, color = if enough or not unlocked then UI.Colors.Text else UI.Colors.Red })
		local mix = UI.button({
			parent = row,
			text = StateController.t("recipes.mix"),
			size = UDim2.fromOffset(130, 50),
			position = UDim2.new(1, -140, 0.5, -25),
			color = if unlocked and enough then UI.Colors.Green else UI.Colors.Disabled,
			textSize = 20,
		})
		-- กดได้เสมอ: ถ้าเงื่อนไขไม่ครบ server จะแจ้งเหตุผลให้ผู้เล่นเห็น
		mix.Activated:Connect(function()
			startMix(recipeId)
		end)
	end
	picker = frame
end

function BakeController.Start()
	gui = UI.screenGui("CloudBakeryBake", 12)
	Remotes.GetEvent("OpenMixing").OnClientEvent:Connect(function()
		openPicker()
	end)
end

return BakeController
