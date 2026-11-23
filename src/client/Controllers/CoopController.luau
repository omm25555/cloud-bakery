--!strict
-- CoopController: UI co-op แบบเบา
-- กด ProximityPrompt ที่ตัวผู้เล่นอื่น -> แผงเลือกของ/จำนวน -> ส่งคำขอ (CoopOffer)
-- คำขอที่ได้รับ (CoopState) แสดงกล่อง รับ/ปฏิเสธ -> CoopRespond
-- client ส่งได้แค่คำขอ ผลทั้งหมด (ของ โบนัส ความเป็นเจ้าของ) server ตัดสินและแจ้งผ่าน Notify
-- กระเป๋าและภาษามาจาก InventoryUpdate (server ยิงหลังย้ายของ)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Coop = require(ReplicatedStorage.Shared.Config.Coop)
local Ingredients = require(ReplicatedStorage.Shared.Config.Ingredients)
local MenuConfig = require(ReplicatedStorage.Shared.Config.Menu)
local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local Recipes = require(ReplicatedStorage.Shared.Config.Recipes)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LOG = "[CoopController]"

type IncomingOffer = {
	OfferId: number,
	FromName: string,
	ItemId: string,
	Amount: number,
	ExpiresAt: number,
}

local CoopController = {}

local localPlayer = Players.LocalPlayer
local language: string = PlayerDataConfig.DefaultLanguage
local inventory: { [string]: number } = {}
local connections: { RBXScriptConnection } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local prompts: { [Player]: ProximityPrompt } = {}

local offerEvent: RemoteEvent? = nil
local respondEvent: RemoteEvent? = nil

local sendFrame: Frame? = nil
local itemList: ScrollingFrame? = nil
local sendTitle: TextLabel? = nil
local amountLabel: TextLabel? = nil
local sendButton: TextButton? = nil
local cancelButton: TextButton? = nil
local noItemsLabel: TextLabel? = nil
local offerFrame: Frame? = nil
local offerTitle: TextLabel? = nil
local offerBody: TextLabel? = nil

local sendTarget: Player? = nil
local selectedItem: string? = nil
local selectedAmount = 1
local incoming: { IncomingOffer } = {}

local function text(key: string, args: { [string]: string | number }?): string
	return Strings.Format(key, language, args)
end

local function itemName(id: string): string
	local ingredient = Ingredients[id]
	if ingredient then
		return if language == "en" then ingredient.DisplayNameEn else ingredient.DisplayNameTh
	end
	local recipe = Recipes[id]
	if recipe then
		return if language == "en" then recipe.DisplayNameEn else recipe.DisplayNameTh
	end
	return id
end

local function styleLabel(label: TextLabel, size: number, color: Color3)
	label.BackgroundTransparency = 1
	label.Font = Coop.Font
	label.TextSize = size
	label.TextColor3 = color
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center
end

local function makeButton(parent: Instance, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.AutoButtonColor = true
	button.BackgroundColor3 = color
	button.Font = Coop.Font
	button.TextSize = Coop.ButtonTextSize
	button.TextColor3 = Coop.TextColor
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Coop.CornerRadiusPixels)
	corner.Parent = button
	return button
end

local function makePanel(parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Coop.PanelColor
	frame.BackgroundTransparency = Coop.PanelTransparency
	frame.Visible = false
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Coop.CornerRadiusPixels)
	corner.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, Coop.PaddingPixels)
	padding.PaddingBottom = UDim.new(0, Coop.PaddingPixels)
	padding.PaddingLeft = UDim.new(0, Coop.PaddingPixels)
	padding.PaddingRight = UDim.new(0, Coop.PaddingPixels)
	padding.Parent = frame
	return frame
end

local function closeSendPanel()
	sendTarget = nil
	selectedItem = nil
	selectedAmount = 1
	local frame = sendFrame
	if frame then
		frame.Visible = false
	end
end

local function refreshSend()
	local frame = sendFrame
	local list = itemList
	local title = sendTitle
	local amountText = amountLabel
	local send = sendButton
	local cancel = cancelButton
	local empty = noItemsLabel
	if frame == nil or list == nil or title == nil or amountText == nil or send == nil or cancel == nil or empty == nil then
		return
	end
	local target = sendTarget
	if target == nil then
		return
	end
	local titleArgs: { [string]: string | number } = { player = target.DisplayName }
	title.Text = text("UiCoopTitle", titleArgs)

	for _, child in list:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	local ids: { string } = {}
	local ordered: { string } = {}
	for _, id in MenuConfig.IngredientOrder do
		table.insert(ordered, id)
	end
	for _, id in MenuConfig.RecipeOrder do
		table.insert(ordered, id)
	end
	for _, id in ordered do
		local count = inventory[id]
		if count ~= nil and count > 0 then
			table.insert(ids, id)
		end
	end

	local current = selectedItem
	if current ~= nil and (inventory[current] or 0) <= 0 then
		selectedItem = nil
		current = nil
	end
	for index, id in ids do
		local button = makeButton(list, if id == current then Coop.ButtonSelectedColor else Coop.ButtonColor)
		button.LayoutOrder = index
		button.Size = UDim2.new(1, 0, 0, Coop.RowHeightPixels)
		local itemArgs: { [string]: string | number } = { name = itemName(id), count = inventory[id] or 0 }
		button.Text = text("UiCoopItem", itemArgs)
		-- ปุ่มถูก Destroy ตอนวาดใหม่ การเชื่อมต่อจึงถูกตัดอัตโนมัติ
		button.Activated:Connect(function()
			selectedItem = id
			selectedAmount = 1
			refreshSend()
		end)
	end
	empty.Visible = #ids == 0
	empty.Text = text("UiCoopNoItems", nil)

	local maxAmount = if current then math.min(Coop.MaxItemsPerGift, inventory[current] or 0) else 0
	selectedAmount = math.clamp(selectedAmount, 1, math.max(1, maxAmount))
	local amountArgs: { [string]: string | number } = { count = selectedAmount }
	amountText.Text = if current == nil then text("UiCoopSelectItem", nil) else text("UiCoopAmount", amountArgs)
	send.Visible = current ~= nil
	send.Text = text("UiCoopSend", nil)
	cancel.Text = text("UiCoopCancel", nil)
end

local function openSendPanel(target: Player)
	if sendFrame == nil then
		return
	end
	sendTarget = target
	selectedItem = nil
	selectedAmount = 1
	local frame = sendFrame
	if frame then
		frame.Visible = true
	end
	refreshSend()
end

local function buildSendPanel(root: ScreenGui)
	local frame = makePanel(root)
	frame.Name = "CoopSendPanel"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(Coop.SendPanelWidthScale, Coop.SendPanelHeightScale)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(Coop.SendPanelMaxWidthPixels, Coop.SendPanelMaxHeightPixels)
	constraint.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Coop.SpacingPixels)
	layout.Parent = frame

	local title = Instance.new("TextLabel")
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, Coop.TitleHeightPixels)
	styleLabel(title, Coop.TitleTextSize, Coop.TextColor)
	title.Parent = frame

	local list = Instance.new("ScrollingFrame")
	list.LayoutOrder = 2
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	-- ความสูงที่เหลือ = ทั้งแผง ลบหัว แถวจำนวน และแถวปุ่ม
	local fixed = Coop.TitleHeightPixels + Coop.RowHeightPixels + Coop.ButtonHeightPixels + Coop.SpacingPixels * 3
	list.Size = UDim2.new(1, 0, 1, -fixed)
	list.Parent = frame
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, Coop.SpacingPixels)
	listLayout.Parent = list

	local empty = Instance.new("TextLabel")
	empty.Size = UDim2.new(1, 0, 0, Coop.RowHeightPixels)
	styleLabel(empty, Coop.BodyTextSize, Coop.SubTextColor)
	empty.Visible = false
	empty.Parent = list

	local amountRow = Instance.new("Frame")
	amountRow.LayoutOrder = 3
	amountRow.BackgroundTransparency = 1
	amountRow.Size = UDim2.new(1, 0, 0, Coop.RowHeightPixels)
	amountRow.Parent = frame

	local minus = makeButton(amountRow, Coop.ButtonColor)
	minus.Size = UDim2.new(0, Coop.AmountButtonWidthPixels, 1, 0)
	minus.Text = "-"
	local plus = makeButton(amountRow, Coop.ButtonColor)
	plus.AnchorPoint = Vector2.new(1, 0)
	plus.Position = UDim2.fromScale(1, 0)
	plus.Size = UDim2.new(0, Coop.AmountButtonWidthPixels, 1, 0)
	plus.Text = "+"
	local amountText = Instance.new("TextLabel")
	amountText.AnchorPoint = Vector2.new(0.5, 0)
	amountText.Position = UDim2.fromScale(0.5, 0)
	amountText.Size = UDim2.new(1, -(Coop.AmountButtonWidthPixels * 2 + Coop.SpacingPixels * 2), 1, 0)
	styleLabel(amountText, Coop.BodyTextSize, Coop.TextColor)
	amountText.Parent = amountRow

	local buttonRow = Instance.new("Frame")
	buttonRow.LayoutOrder = 4
	buttonRow.BackgroundTransparency = 1
	buttonRow.Size = UDim2.new(1, 0, 0, Coop.ButtonHeightPixels)
	buttonRow.Parent = frame
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, Coop.SpacingPixels)
	rowLayout.Parent = buttonRow

	local send = makeButton(buttonRow, Coop.ButtonSelectedColor)
	send.LayoutOrder = 1
	send.Size = UDim2.new(0.5, -Coop.SpacingPixels / 2, 1, 0)
	local cancel = makeButton(buttonRow, Coop.DeclineColor)
	cancel.LayoutOrder = 2
	cancel.Size = UDim2.new(0.5, -Coop.SpacingPixels / 2, 1, 0)

	sendFrame = frame
	itemList = list
	sendTitle = title
	amountLabel = amountText
	sendButton = send
	cancelButton = cancel
	noItemsLabel = empty

	table.insert(connections, minus.Activated:Connect(function()
		selectedAmount = math.max(1, selectedAmount - 1)
		refreshSend()
	end))
	table.insert(connections, plus.Activated:Connect(function()
		local current = selectedItem
		local limit = if current then math.min(Coop.MaxItemsPerGift, inventory[current] or 0) else 1
		selectedAmount = math.clamp(selectedAmount + 1, 1, math.max(1, limit))
		refreshSend()
	end))
	table.insert(connections, cancel.Activated:Connect(closeSendPanel))
	table.insert(connections, send.Activated:Connect(function()
		local target = sendTarget
		local item = selectedItem
		local remote = offerEvent
		if target == nil or item == nil or remote == nil then
			return
		end
		if target.Parent ~= Players then
			warn(`{LOG} ผู้เล่นปลายทางออกจากเกมแล้ว ปิดแผง`)
			closeSendPanel()
			return
		end
		remote:FireServer(target.UserId, item, selectedAmount)
		closeSendPanel()
	end))
end

local function refreshOffer()
	local frame = offerFrame
	local title = offerTitle
	local body = offerBody
	if frame == nil or title == nil or body == nil then
		return
	end
	local offer = incoming[1]
	if offer == nil then
		frame.Visible = false
		return
	end
	local titleArgs: { [string]: string | number } = { player = offer.FromName }
	local bodyArgs: { [string]: string | number } = { name = itemName(offer.ItemId), count = offer.Amount }
	title.Text = text("UiCoopOfferTitle", titleArgs)
	body.Text = text("UiCoopOfferBody", bodyArgs)
	frame.Visible = true
	for _, child in frame:GetChildren() do
		if child:IsA("Frame") then
			for _, button in child:GetChildren() do
				if button:IsA("TextButton") then
					button.Text = if button.Name == "Accept" then text("UiCoopAccept", nil) else text("UiCoopDecline", nil)
				end
			end
		end
	end
end

local function removeIncoming(offerId: number)
	for index, offer in incoming do
		if offer.OfferId == offerId then
			table.remove(incoming, index)
			break
		end
	end
	refreshOffer()
end

local function respond(accept: boolean)
	local offer = incoming[1]
	local remote = respondEvent
	if offer == nil or remote == nil then
		return
	end
	remote:FireServer(offer.OfferId, accept)
	removeIncoming(offer.OfferId)
end

local function buildOfferBox(root: ScreenGui)
	local frame = makePanel(root)
	frame.Name = "CoopOfferBox"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -Coop.OfferBottomOffsetPixels)
	frame.Size = UDim2.new(Coop.OfferWidthScale, 0, 0, Coop.OfferHeightPixels)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(Coop.OfferMaxWidthPixels, Coop.OfferHeightPixels)
	constraint.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Coop.SpacingPixels)
	layout.Parent = frame

	local title = Instance.new("TextLabel")
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, Coop.TitleHeightPixels)
	styleLabel(title, Coop.TitleTextSize, Coop.TextColor)
	title.Parent = frame

	local body = Instance.new("TextLabel")
	body.LayoutOrder = 2
	body.Size = UDim2.new(1, 0, 0, Coop.RowHeightPixels)
	styleLabel(body, Coop.BodyTextSize, Coop.SubTextColor)
	body.Parent = frame

	local row = Instance.new("Frame")
	row.LayoutOrder = 3
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, Coop.ButtonHeightPixels)
	row.Parent = frame
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, Coop.SpacingPixels)
	rowLayout.Parent = row

	local accept = makeButton(row, Coop.ButtonSelectedColor)
	accept.Name = "Accept"
	accept.LayoutOrder = 1
	accept.Size = UDim2.new(0.5, -Coop.SpacingPixels / 2, 1, 0)
	local decline = makeButton(row, Coop.DeclineColor)
	decline.Name = "Decline"
	decline.LayoutOrder = 2
	decline.Size = UDim2.new(0.5, -Coop.SpacingPixels / 2, 1, 0)

	offerFrame = frame
	offerTitle = title
	offerBody = body
	table.insert(connections, accept.Activated:Connect(function()
		respond(true)
	end))
	table.insert(connections, decline.Activated:Connect(function()
		respond(false)
	end))
end

local function refreshAll()
	for other, prompt in prompts do
		prompt.ActionText = text("UiCoopPrompt", nil)
		prompt.ObjectText = other.DisplayName
	end
	if sendTarget ~= nil then
		refreshSend()
	end
	refreshOffer()
end

local function onInventoryUpdate(payload: unknown)
	if type(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	if type(data.Language) == "string" then
		language = data.Language :: string
	end
	local raw = data.Inventory
	if type(raw) == "table" then
		local clean: { [string]: number } = {}
		for id, count in raw :: { [unknown]: unknown } do
			if type(id) == "string" and type(count) == "number" then
				clean[id :: string] = count :: number
			end
		end
		inventory = clean
	end
	refreshAll()
end

local function onState(payload: unknown)
	if type(payload) ~= "table" then
		warn(`{LOG} CoopState payload ไม่ถูกต้อง ข้าม`)
		return
	end
	local data = payload :: { [string]: unknown }
	local kind = data.Type
	local offerId = data.OfferId
	if type(offerId) ~= "number" then
		warn(`{LOG} CoopState ไม่มี OfferId ข้าม`)
		return
	end
	if kind == Coop.OfferTypes.Closed then
		removeIncoming(offerId :: number)
		return
	end
	if kind ~= Coop.OfferTypes.Offer then
		warn(`{LOG} CoopState Type ไม่รู้จัก ({tostring(kind)}) ข้าม`)
		return
	end
	local fromName = data.FromName
	local itemId = data.ItemId
	local amount = data.Amount
	local expiresAt = data.ExpiresAt
	if type(fromName) ~= "string" or type(itemId) ~= "string" or type(amount) ~= "number" or type(expiresAt) ~= "number" then
		warn(`{LOG} CoopState Offer ขาดฟิลด์ ข้าม`)
		return
	end
	if type(data.Language) == "string" then
		language = data.Language :: string
	end
	table.insert(incoming, {
		OfferId = offerId :: number,
		FromName = fromName :: string,
		ItemId = itemId :: string,
		Amount = amount :: number,
		ExpiresAt = expiresAt :: number,
	})
	refreshOffer()
	local expiry = expiresAt :: number
	local id = offerId :: number
	task.delay(math.max(0, expiry - Workspace:GetServerTimeNow()), function()
		removeIncoming(id)
	end)
end

local function detachPlayer(other: Player)
	local list = playerConnections[other]
	if list then
		for _, connection in list do
			connection:Disconnect()
		end
		playerConnections[other] = nil
	end
	local prompt = prompts[other]
	if prompt then
		prompt:Destroy()
		prompts[other] = nil
	end
	if sendTarget == other then
		closeSendPanel()
	end
end

local function attachPrompt(other: Player, character: Model)
	local old = prompts[other]
	if old then
		old:Destroy()
		prompts[other] = nil
	end
	local root = character:WaitForChild("HumanoidRootPart", Coop.ClientWaitSeconds)
	if root == nil or not root:IsA("BasePart") then
		warn(`{LOG} ไม่พบ HumanoidRootPart ของ {other.Name} ไม่สร้างปุ่มให้ของ`)
		return
	end
	if other.Character ~= character then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = Coop.PromptName
	prompt.ActionText = text("UiCoopPrompt", nil)
	prompt.ObjectText = other.DisplayName
	prompt.KeyboardKeyCode = Coop.PromptKeyCode
	prompt.MaxActivationDistance = Coop.PromptDistance
	prompt.HoldDuration = Coop.PromptHoldSeconds
	prompt.RequiresLineOfSight = Coop.PromptRequiresLineOfSight
	prompt.UIOffset = Vector2.new(0, 0)
	prompt.Parent = root
	prompts[other] = prompt
	local list = playerConnections[other]
	if list then
		table.insert(list, prompt.Triggered:Connect(function()
			openSendPanel(other)
		end))
	end
end

local function attachPlayer(other: Player)
	if other == localPlayer or playerConnections[other] ~= nil then
		return
	end
	local list: { RBXScriptConnection } = {}
	playerConnections[other] = list
	table.insert(list, other.CharacterAdded:Connect(function(character: Model)
		attachPrompt(other, character)
	end))
	table.insert(list, other.CharacterRemoving:Connect(function()
		local prompt = prompts[other]
		if prompt then
			prompt:Destroy()
			prompts[other] = nil
		end
		if sendTarget == other then
			closeSendPanel()
		end
	end))
	local character = other.Character
	if character then
		task.spawn(attachPrompt, other, character)
	end
end

function CoopController.Start()
	local playerGui = localPlayer:WaitForChild("PlayerGui", Coop.ClientWaitSeconds)
	if playerGui == nil then
		warn(`{LOG} ไม่พบ PlayerGui ปิดระบบ co-op ฝั่ง client`)
		return
	end
	offerEvent = Remotes.GetEvent("CoopOffer")
	respondEvent = Remotes.GetEvent("CoopRespond")

	local root = Instance.new("ScreenGui")
	root.Name = Coop.GuiName
	root.DisplayOrder = Coop.GuiDisplayOrder
	root.ResetOnSpawn = false
	root.IgnoreGuiInset = false
	root.Parent = playerGui
	buildSendPanel(root)
	buildOfferBox(root)

	table.insert(connections, Remotes.GetEvent("InventoryUpdate").OnClientEvent:Connect(onInventoryUpdate))
	Remotes.GetEvent("InventorySync"):FireServer()
	table.insert(connections, Remotes.GetEvent("CoopState").OnClientEvent:Connect(onState))
	table.insert(connections, Players.PlayerAdded:Connect(attachPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(detachPlayer))
	for _, other in Players:GetPlayers() do
		attachPlayer(other)
	end
	refreshAll()
end

return CoopController
