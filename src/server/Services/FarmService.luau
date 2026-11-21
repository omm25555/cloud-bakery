--!strict
-- เก็บเกี่ยว: แปลงข้าวสาลี พุ่มสตรอว์เบอรี และวัวน้ำนมดาว
-- แปลงใช้ร่วมกันทั้งเซิร์ฟเวอร์ (co-op แบบเบา) ใครเก็บก่อนได้ของ เวลาโตนับที่ server เท่านั้น

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = Shared.Config
local GameConfig = require(Config.Game)
local Crops = require(Config.Crops)
local Locale = require(Shared.Locale)
local Formulas = require(Shared.Formulas)

local NotifyService = require(script.Parent.NotifyService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local QuestService = require(script.Parent.QuestService)
local WorldService = require(script.Parent.WorldService)
local RateLimiter = require(script.Parent.Parent.Modules.RateLimiter)

local SOURCE = "FarmService"

type Plot = {
	cropId: string,
	anchor: BasePart,
	readyAt: number,
	prompt: ProximityPrompt,
	label: TextLabel,
	visuals: { BasePart },
	style: "Wheat" | "Berry" | "Milk",
}

local FarmService = {}

local plots: { Plot } = {}
local promptLimit = GameConfig.RateLimits.Prompt
local promptLimiter = RateLimiter.new(promptLimit.MaxCalls, promptLimit.WindowSeconds)

local GROWING_COLOR = Color3.fromRGB(140, 200, 100)
local WHEAT_COLOR = Color3.fromRGB(245, 205, 90)
local BERRY_COLOR = Color3.fromRGB(235, 60, 85)

local function bilingual(key: string): string
	return `{Locale.get("th", key)} ({Locale.get("en", key)})`
end

local function makeVisual(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, shape: Enum.PartType): Part
	local p = Instance.new("Part")
	p.Name = "Crop"
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Shape = shape
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function makeBillboard(anchor: BasePart, offsetY: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "CropTimer"
	gui.Size = UDim2.fromOffset(110, 34)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = 70
	gui.AlwaysOnTop = false
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(255, 248, 238)
	label.BackgroundTransparency = 0.1
	label.TextColor3 = Color3.fromRGB(110, 70, 110)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = ""
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = label
	return label
end

local function makePrompt(anchor: BasePart, cropId: string): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HarvestPrompt"
	prompt.ActionText = bilingual("hud.harvest")
	prompt.ObjectText = `{Locale.icon(cropId)} {bilingual(`item.{Crops[cropId].IngredientId}`)}`
	prompt.HoldDuration = GameConfig.HarvestHoldSeconds
	prompt.MaxActivationDistance = GameConfig.PromptMaxActivationDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	return prompt
end

local function buildWheatVisuals(anchor: BasePart): { BasePart }
	local visuals: { BasePart } = {}
	local top = anchor.Position + Vector3.new(0, anchor.Size.Y / 2, 0)
	for x = -1, 1 do
		for z = -1, 1 do
			local pos = top + Vector3.new(x * 2.2, 1, z * 2.2)
			table.insert(visuals, makeVisual(anchor, Vector3.new(0.5, 2, 0.5), CFrame.new(pos), WHEAT_COLOR, Enum.PartType.Block))
		end
	end
	return visuals
end

local function buildBerryVisuals(anchor: BasePart): { BasePart }
	local visuals: { BasePart } = {}
	local radius = anchor.Size.X / 2
	for i = 1, 7 do
		local angle = (i / 7) * math.pi * 2
		local pos = anchor.Position + Vector3.new(math.cos(angle) * radius * 0.85, (i % 3 - 1) * 0.9, math.sin(angle) * radius * 0.85)
		table.insert(visuals, makeVisual(anchor, Vector3.new(0.9, 0.9, 0.9), CFrame.new(pos), BERRY_COLOR, Enum.PartType.Ball))
	end
	return visuals
end

local function buildMilkVisuals(anchor: BasePart): { BasePart }
	local bottle = makeVisual(anchor, Vector3.new(1.2, 1.8, 1.2), CFrame.new(anchor.Position + Vector3.new(0, 3.4, 0)), Color3.fromRGB(245, 250, 255), Enum.PartType.Cylinder)
	bottle.CFrame = CFrame.new(anchor.Position + Vector3.new(0, 3.4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	bottle.Material = Enum.Material.Neon
	local star = makeVisual(anchor, Vector3.new(0.7, 0.7, 0.7), CFrame.new(anchor.Position + Vector3.new(0, 4.6, 0)), Color3.fromRGB(255, 214, 90), Enum.PartType.Ball)
	star.Material = Enum.Material.Neon
	return { bottle, star }
end

local function refreshPlot(plot: Plot, now: number)
	local crop = Crops[plot.cropId]
	local remaining = plot.readyAt - now
	local ready = remaining <= 0
	plot.prompt.Enabled = ready
	if ready then
		plot.label.Text = `{Locale.icon(plot.cropId)} ✔`
	else
		plot.label.Text = `{Locale.icon(plot.cropId)} {Locale.formatTime(remaining)}`
	end
	local progress = if ready then 1 else math.clamp(1 - remaining / crop.GrowTimeSeconds, 0, 1)
	for _, visual in plot.visuals do
		if plot.style == "Wheat" then
			local height = 0.4 + progress * 2.6
			local base = plot.anchor.Position.Y + plot.anchor.Size.Y / 2
			visual.Size = Vector3.new(0.5, height, 0.5)
			visual.Position = Vector3.new(visual.Position.X, base + height / 2, visual.Position.Z)
			visual.Color = GROWING_COLOR:Lerp(WHEAT_COLOR, progress)
		else
			visual.Transparency = if ready then 0 else 1
		end
	end
end

local function harvest(player: Player, plot: Plot)
	if not promptLimiter.allow(player) then
		NotifyService.blocked(player, "n.tooFast")
		return
	end
	local data = PlayerDataService.get(player)
	if data == nil then
		NotifyService.blocked(player, "n.loading")
		return
	end
	local crop = Crops[plot.cropId]
	local itemKey = `item.{crop.IngredientId}`
	local now = os.clock()
	if plot.readyAt > now then
		NotifyService.blocked(player, "n.notReady", { item = itemKey, seconds = math.ceil(plot.readyAt - now) })
		return
	end
	if WorldService.distanceTo(player, plot.anchor) > GameConfig.InteractMaxDistance then
		NotifyService.rejected(SOURCE, player, "เก็บเกี่ยวจากระยะไกลเกินไป", "n.tooFar")
		return
	end
	local current = data.ingredients[crop.IngredientId] or 0
	local room = GameConfig.MaxStackPerItem - current
	if room <= 0 then
		NotifyService.blocked(player, "n.bagFull", { item = itemKey })
		return
	end
	local amount = math.min(room, Formulas.harvestYield(crop.YieldAmount, Formulas.upgradeLevel(data.upgrades, "Garden")))
	plot.readyAt = now + crop.GrowTimeSeconds
	refreshPlot(plot, now)
	PlayerDataService.update(player, function(saved)
		saved.ingredients[crop.IngredientId] = (saved.ingredients[crop.IngredientId] or 0) + amount
	end)
	QuestService.addProgress(player, "Harvest", crop.IngredientId, amount)
	NotifyService.success(player, "n.harvested", { item = itemKey, amount = amount })
end

local function addPlot(anchor: BasePart, cropId: string, style: "Wheat" | "Berry" | "Milk", billboardOffset: number)
	local visuals = if style == "Wheat"
		then buildWheatVisuals(anchor)
		elseif style == "Berry" then buildBerryVisuals(anchor)
		else buildMilkVisuals(anchor)
	local plot: Plot = {
		cropId = cropId,
		anchor = anchor,
		readyAt = 0,
		prompt = makePrompt(anchor, cropId),
		label = makeBillboard(anchor, billboardOffset),
		visuals = visuals,
		style = style,
	}
	plot.prompt.Triggered:Connect(function(player: Player)
		local ok, err = pcall(function()
			harvest(player, plot)
		end)
		if not ok then
			NotifyService.unexpected(SOURCE, player, `เก็บเกี่ยว {cropId} ล้มเหลว: {err}`)
		end
	end)
	table.insert(plots, plot)
	refreshPlot(plot, os.clock())
end

function FarmService.Start()
	local stations = WorldService.getStations()
	for _, anchor in stations.wheatPlots do
		addPlot(anchor, "Wheat", "Wheat", 5)
	end
	for _, anchor in stations.strawberryBushes do
		addPlot(anchor, "Strawberry", "Berry", 4.5)
	end
	for _, anchor in stations.cows do
		addPlot(anchor, "StarMilk", "Milk", 6)
	end

	task.spawn(function()
		while true do
			task.wait(GameConfig.WorldTimerRefreshSeconds)
			local now = os.clock()
			for _, plot in plots do
				refreshPlot(plot, now)
			end
		end
	end)
end

return FarmService
