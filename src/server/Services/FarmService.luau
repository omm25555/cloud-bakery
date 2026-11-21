--!strict
-- FarmService: แปลงปลูกรวมบนเกาะ (co-op) ปลูก → โต → เก็บ
-- server ตัดสินทุกอย่าง: เวลาโต (GetServerTimeNow), ระยะ, ความจุกระเป๋า, ของที่ได้
-- client ส่งได้แค่ "ขอปลูก (แปลง, พืช)" / "ขอเก็บ (แปลง)" / "ขอ snapshot"
-- สถานะแปลงไม่ถูกบันทึก (รีเซ็ตเมื่อเซิร์ฟเวอร์ปิด) แต่ Inventory บันทึกผ่าน DataService

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Crops = require(ReplicatedStorage.Shared.Config.Crops)
local Farm = require(ReplicatedStorage.Shared.Config.Farm)
local Ingredients = require(ReplicatedStorage.Shared.Config.Ingredients)
local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local RateLimits = require(ReplicatedStorage.Shared.Config.RateLimits)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local NotifyService = require(script.Parent.NotifyService)

local LOG = "[FarmService]"

type PlayerData = PlayerDataConfig.PlayerData

type Plot = {
	Id: number,
	CropId: string?,
	PlantedAt: number?,
	ReadyAt: number?,
	PlantedBy: number?, -- UserId ผู้ปลูก
}

type PlotEntry = {
	PlotId: number,
	CropId: string?,
	ReadyAt: number?,
}

-- สร้าง remote ตอน require เพื่อให้ client หาเจอเสมอ ไม่ขึ้นกับลำดับ Start
local plantEvent = Remotes.GetEvent("FarmPlant")
local harvestEvent = Remotes.GetEvent("FarmHarvest")
local syncEvent = Remotes.GetEvent("FarmSync")
local stateEvent = Remotes.GetEvent("FarmState")
local inventoryEvent = Remotes.GetEvent("InventoryUpdate")

local FarmService = {}

local plots: { Plot } = {}
local plotParts: { [number]: BasePart } = {}
local syncing: { [Player]: boolean } = {}

local limiter = RateLimiter.new(RateLimits, function(player: Player, _remoteName: string)
	NotifyService.NotifyRateLimited(player)
end)

local function languageOf(player: Player): string
	local data = DataService.GetData(player)
	if data then
		return data.Settings.Language
	end
	return PlayerDataConfig.DefaultLanguage
end

local function cropName(player: Player, cropId: string): string
	local crop = Crops[cropId]
	local ingredient = if crop then Ingredients[crop.IngredientId] else nil
	if ingredient == nil then
		return cropId
	end
	if languageOf(player) == "en" then
		return ingredient.DisplayNameEn
	end
	return ingredient.DisplayNameTh
end

-- ปฏิเสธคำขอ: warn ฝั่ง dev + แจ้งผู้เล่น
local function reject(
	player: Player,
	remoteName: string,
	reason: string,
	key: string,
	args: { [string]: string | number }?
)
	warn(`{LOG} {player.Name} {remoteName} ปฏิเสธ: {reason}`)
	NotifyService.Notify(player, key, "error", args)
end

local function toPlotEntry(plot: Plot): PlotEntry
	return { PlotId = plot.Id, CropId = plot.CropId, ReadyAt = plot.ReadyAt }
end

local function broadcastPlot(plot: Plot)
	stateEvent:FireAllClients({ Plots = { toPlotEntry(plot) } })
end

local function inventoryTotal(data: PlayerData): number
	local total = 0
	for _, count in data.Inventory do
		total += count
	end
	return total
end

local function sendInventory(player: Player, data: PlayerData)
	local copy: { [string]: number } = {}
	for id, count in data.Inventory do
		copy[id] = count
	end
	inventoryEvent:FireClient(player, { Inventory = copy, Language = data.Settings.Language })
end

local function readPlotId(raw: unknown): Plot?
	if type(raw) ~= "number" then
		return nil
	end
	local id = raw :: number
	if id ~= id or id ~= math.floor(id) then
		return nil
	end
	return plots[id]
end

local function isNearPlot(player: Player, plot: Plot): boolean
	local part: BasePart? = plotParts[plot.Id]
	local character = player.Character
	if part == nil or character == nil then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - part.Position).Magnitude <= Farm.InteractDistance + Farm.DistanceTolerance
end

-- ตรวจแปลง/ข้อมูลผู้เล่น/ระยะ ร่วมกันของปลูกและเก็บ คืน nil ถ้าปฏิเสธแล้ว
local function checkContext(player: Player, remoteName: string, plotIdRaw: unknown): (Plot?, PlayerData?)
	local plot = readPlotId(plotIdRaw)
	if plot == nil then
		reject(player, remoteName, `plotId ไม่ถูกต้อง ({tostring(plotIdRaw)})`, "InvalidRequest", nil)
		return nil, nil
	end
	local data = DataService.GetData(player)
	if data == nil then
		reject(player, remoteName, "ข้อมูลผู้เล่นยังโหลดไม่เสร็จ", "DataNotReady", nil)
		return nil, nil
	end
	if not isNearPlot(player, plot) then
		reject(player, remoteName, `อยู่ไกลแปลง {plot.Id} เกินระยะ หรือไม่มีตัวละคร`, "TooFar", nil)
		return nil, nil
	end
	return plot, data
end

local function onPlant(player: Player, plotIdRaw: unknown, cropIdRaw: unknown)
	if not limiter:Check(player, "FarmPlant") then
		return
	end
	if type(cropIdRaw) ~= "string" then
		reject(player, "FarmPlant", "cropId ไม่ใช่ string", "InvalidRequest", nil)
		return
	end
	local crop = Crops[cropIdRaw :: string]
	if crop == nil then
		reject(player, "FarmPlant", `ไม่มีพืช {cropIdRaw :: string} ใน Config`, "InvalidRequest", nil)
		return
	end
	local plot, data = checkContext(player, "FarmPlant", plotIdRaw)
	if plot == nil or data == nil then
		return
	end
	if plot.CropId ~= nil then
		reject(player, "FarmPlant", `แปลง {plot.Id} ไม่ว่าง`, "PlotOccupied", nil)
		return
	end
	if Farm.PlantCost > 0 then
		if data.Coins < Farm.PlantCost then
			local args: { [string]: string | number } = { cost = Farm.PlantCost }
			reject(player, "FarmPlant", `เหรียญไม่พอ ({data.Coins}/{Farm.PlantCost})`, "NotEnoughCoins", args)
			return
		end
		data.Coins -= Farm.PlantCost
	end

	local now = Workspace:GetServerTimeNow()
	plot.CropId = crop.Id
	plot.PlantedAt = now
	plot.ReadyAt = now + crop.GrowTimeSeconds
	plot.PlantedBy = player.UserId

	broadcastPlot(plot)
	local okArgs: { [string]: string | number } = { crop = cropName(player, crop.Id) }
	NotifyService.Notify(player, "PlantOk", "success", okArgs)
end

local function onHarvest(player: Player, plotIdRaw: unknown)
	if not limiter:Check(player, "FarmHarvest") then
		return
	end
	local plot, data = checkContext(player, "FarmHarvest", plotIdRaw)
	if plot == nil or data == nil then
		return
	end

	local cropId = plot.CropId
	local readyAt = plot.ReadyAt
	local crop = if cropId then Crops[cropId] else nil
	if cropId == nil or readyAt == nil or crop == nil then
		reject(player, "FarmHarvest", `แปลง {plot.Id} ว่าง`, "PlotEmpty", nil)
		return
	end

	local plantedBy = plot.PlantedBy
	if Farm.OnlyPlanterCanHarvest and plantedBy ~= player.UserId and plantedBy ~= nil then
		if Players:GetPlayerByUserId(plantedBy) ~= nil then
			reject(player, "FarmHarvest", `แปลง {plot.Id} เก็บได้เฉพาะผู้ปลูก ({plantedBy})`, "NoPermission", nil)
			return
		end
	end

	local remaining = readyAt - Workspace:GetServerTimeNow()
	if remaining > 0 then
		local args: { [string]: string | number } = { crop = cropName(player, cropId), seconds = math.ceil(remaining) }
		reject(
			player,
			"FarmHarvest",
			`แปลง {plot.Id} ยังไม่โต (เหลือ {string.format("%.1f", remaining)} วินาที)`,
			"NotReady",
			args
		)
		return
	end

	local amount = crop.YieldAmount
	local current = data.Inventory[crop.IngredientId] or 0
	if inventoryTotal(data) + amount > Farm.InventoryCapacity or current + amount > PlayerDataConfig.Limits.MaxItemCount then
		reject(
			player,
			"FarmHarvest",
			`กระเป๋าเต็ม (รวม {inventoryTotal(data)}/{Farm.InventoryCapacity}, {crop.IngredientId} {current})`,
			"InventoryFull",
			nil
		)
		return
	end

	-- ไม่มี yield ตั้งแต่ตรวจถึงเขียน จึงเก็บซ้อนสองครั้งไม่ได้
	data.Inventory[crop.IngredientId] = current + amount
	plot.CropId = nil
	plot.PlantedAt = nil
	plot.ReadyAt = nil
	plot.PlantedBy = nil

	broadcastPlot(plot)
	sendInventory(player, data)
	local okArgs: { [string]: string | number } = { crop = cropName(player, cropId), amount = amount }
	NotifyService.Notify(player, "HarvestOk", "success", okArgs)

	if plantedBy ~= nil and plantedBy ~= player.UserId then
		local planter = Players:GetPlayerByUserId(plantedBy)
		if planter then
			local otherArgs: { [string]: string | number } =
				{ player = player.DisplayName, crop = cropName(planter, cropId), amount = amount }
			NotifyService.Notify(planter, "HarvestByOther", "info", otherArgs)
		end
	end
end

local function onSync(player: Player)
	if not limiter:Check(player, "FarmSync") then
		return
	end
	if syncing[player] then
		return
	end
	syncing[player] = true
	task.spawn(function()
		local waited = 0
		while DataService.GetData(player) == nil and waited < Farm.SyncWaitSeconds and player.Parent == Players do
			task.wait(PlayerDataConfig.PollSeconds)
			waited += PlayerDataConfig.PollSeconds
		end
		syncing[player] = nil
		if player.Parent ~= Players then
			return
		end

		local entries: { PlotEntry } = {}
		for _, plot in plots do
			table.insert(entries, toPlotEntry(plot))
		end
		stateEvent:FireClient(player, { Plots = entries, Language = languageOf(player) })

		local data = DataService.GetData(player)
		if data then
			sendInventory(player, data)
		else
			warn(`{LOG} {player.Name} FarmSync: ข้อมูลผู้เล่นยังโหลดไม่เสร็จหลังรอ {Farm.SyncWaitSeconds} วินาที ไม่ส่งกระเป๋า`)
			NotifyService.Notify(player, "DataNotReady", "error")
		end
	end)
end

local function createPlotParts()
	local existing = Workspace:FindFirstChild(Farm.FolderName)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = Farm.FolderName

	for index, config in Farm.Plots do
		local part = Instance.new("Part")
		part.Name = `{Farm.PlotNamePrefix}{index}`
		part.Anchored = true
		part.Size = Farm.PlotSize
		part.Position = config.Position
		part.Color = Farm.PlotColor
		part.Material = Farm.PlotMaterial
		part:SetAttribute(Farm.PlotIdAttribute, index)
		part.Parent = folder

		plotParts[index] = part
		plots[index] = { Id = index }
	end
	folder.Parent = Workspace
end

function FarmService.Start()
	createPlotParts()
	plantEvent.OnServerEvent:Connect(onPlant)
	harvestEvent.OnServerEvent:Connect(onHarvest)
	syncEvent.OnServerEvent:Connect(onSync)
	Players.PlayerRemoving:Connect(function(player: Player)
		syncing[player] = nil
	end)
end

return FarmService
