--!strict
-- CoopService: co-op แบบเบา ผู้เล่นให้วัตถุดิบ/ขนมกันได้ (ผู้รับต้องกดรับ)
-- และผู้ให้ได้โบนัสผู้ช่วยเมื่อขนมที่ให้ไปถูกใช้เสิร์ฟออเดอร์จริง
--
-- การย้ายของ: เมื่อผู้รับกดรับ server ตรวจซ้ำทุกอย่าง (ผู้ให้ยังอยู่/มีของครบ ผู้รับมีที่ว่าง ทั้งคู่อยู่ในระยะ)
-- แล้วหักจาก data ผู้ให้และเพิ่มให้ data ผู้รับในช่วงเดียวกันโดยไม่มี yield (ของย้ายที่ ไม่เกิด/ไม่หาย)
-- data ทั้งสองคนเป็น table เดียวกับที่ DataService เซฟ (autosave + ตอนออกเกม + BindToClose) จึงถูกบันทึกตามกลไกเดิม
-- กระเป๋าของทั้งสองฝั่งอัปเดตด้วย InventoryService.Send (ยิง InventoryUpdate ให้ผู้เล่นคนนั้นคนเดียว)
-- ของยังอยู่กับผู้ให้จนกว่าจะกดรับ ผู้ออกกลางคันจึงไม่มีของค้างระหว่างทาง
--
-- โบนัสผู้ช่วย: ขนมที่ได้รับสร้างเครดิต (ต่อผู้รับ ต่อสูตร) ServeService เรียก CoopService.OnServed หลังเสิร์ฟสำเร็จ
-- เครดิตหมดอายุตาม GiftCreditSeconds มีเพดานต่อวันต่อผู้ให้ และต่อคู่ เหรียญโบนัสเป็นเหรียญใหม่ (ไม่หักจากผู้เสิร์ฟ)
-- เพดานต่อวันเก็บใน memory ของเซิร์ฟเวอร์ตาม userId (ไม่ล้างตอนออกเกม) ไม่เซฟลง DataStore

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Coop = require(ReplicatedStorage.Shared.Config.Coop)
local Farm = require(ReplicatedStorage.Shared.Config.Farm)
local Ingredients = require(ReplicatedStorage.Shared.Config.Ingredients)
local PlayerDataConfig = require(ReplicatedStorage.Shared.Config.PlayerData)
local RateLimits = require(ReplicatedStorage.Shared.Config.RateLimits)
local Recipes = require(ReplicatedStorage.Shared.Config.Recipes)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local NotifyService = require(script.Parent.NotifyService)

local LOG = "[CoopService]"

type PlayerData = PlayerDataConfig.PlayerData

type Offer = {
	Id: number,
	From: Player,
	To: Player,
	ItemId: string,
	Amount: number,
	ExpiresAt: number,
}

type Credit = {
	GiverUserId: number,
	GiverName: string,
	RecipeId: string,
	Amount: number,
	ExpiresAt: number,
}

type BonusDay = {
	Day: number,
	Total: number,
	Pairs: { [string]: number },
}

-- สร้าง remote ตอน require เพื่อให้ client หาเจอเสมอ ไม่ขึ้นกับลำดับ Start
local offerEvent = Remotes.GetEvent("CoopOffer")
local respondEvent = Remotes.GetEvent("CoopRespond")
local stateEvent = Remotes.GetEvent("CoopState")
local currencyEvent = Remotes.GetEvent("CurrencyUpdate")

local CoopService = {}

local limiter = RateLimiter.new(RateLimits, function(player: Player, _remoteName: string)
	NotifyService.NotifyRateLimited(player)
end)

local connections: { RBXScriptConnection } = {}
local offers: { [number]: Offer } = {}
local offerCounter = 0
local credits: { [Player]: { Credit } } = {}
local bonusDays: { [number]: BonusDay } = {}

local function languageOf(player: Player): string
	local data = DataService.GetData(player)
	if data then
		return data.Settings.Language
	end
	return PlayerDataConfig.DefaultLanguage
end

local function itemName(language: string, itemId: string): string
	local ingredient = Ingredients[itemId]
	if ingredient then
		return if language == "en" then ingredient.DisplayNameEn else ingredient.DisplayNameTh
	end
	local recipe = Recipes[itemId]
	if recipe then
		return if language == "en" then recipe.DisplayNameEn else recipe.DisplayNameTh
	end
	return itemId
end

local function isKnownItem(itemId: string): boolean
	return Ingredients[itemId] ~= nil or Recipes[itemId] ~= nil
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

local function inventoryTotal(data: PlayerData): number
	local total = 0
	for _, count in data.Inventory do
		total += count
	end
	return total
end

local function hasRoom(data: PlayerData, itemId: string, amount: number): boolean
	local current = data.Inventory[itemId] or 0
	if inventoryTotal(data) + amount > Farm.InventoryCapacity then
		return false
	end
	return current + amount <= PlayerDataConfig.Limits.MaxItemCount
end

local function isNearEachOther(a: Player, b: Player): boolean
	local charA = a.Character
	local charB = b.Character
	if charA == nil or charB == nil then
		return false
	end
	local rootA = charA:FindFirstChild("HumanoidRootPart")
	local rootB = charB:FindFirstChild("HumanoidRootPart")
	if rootA == nil or rootB == nil or not rootA:IsA("BasePart") or not rootB:IsA("BasePart") then
		return false
	end
	return (rootA.Position - rootB.Position).Magnitude <= Coop.MaxGiveDistance + Coop.DistanceTolerance
end

local function readInteger(value: unknown, min: number, max: number): number?
	if type(value) ~= "number" then
		return nil
	end
	local number = value :: number
	if number ~= number or number < min or number > max or number ~= math.floor(number) then
		return nil
	end
	return number
end

local function offerArgs(language: string, otherName: string, offer: Offer): { [string]: string | number }
	return { player = otherName, item = itemName(language, offer.ItemId), count = offer.Amount }
end

local function closeOffer(offer: Offer)
	offers[offer.Id] = nil
	if offer.To.Parent == Players then
		stateEvent:FireClient(offer.To, { Type = Coop.OfferTypes.Closed, OfferId = offer.Id })
	end
end

local function countOffers(player: Player, asSender: boolean): number
	local count = 0
	for _, offer in offers do
		if (if asSender then offer.From else offer.To) == player then
			count += 1
		end
	end
	return count
end

local function playerArgs(name: string): { [string]: string | number }
	return { player = name }
end

local function currentDay(): number
	return math.floor((os.time() + Coop.ResetOffsetSeconds) / Coop.DaySeconds)
end

local function bonusDayOf(userId: number): BonusDay
	local day = currentDay()
	local record = bonusDays[userId]
	if record == nil or record.Day ~= day then
		record = { Day = day, Total = 0, Pairs = {} }
		bonusDays[userId] = record
	end
	return record
end

local function pruneCredits(list: { Credit }, now: number)
	for index = #list, 1, -1 do
		if list[index].ExpiresAt <= now or list[index].Amount <= 0 then
			table.remove(list, index)
		end
	end
end

-- ลดเครดิตของผู้เล่นสำหรับสูตรหนึ่ง (FIFO) คืนจำนวนที่ลดได้จริง
-- onTaken ถูกเรียกต่อเครดิตที่ถูกใช้ (ใช้จ่ายโบนัสตอนเสิร์ฟ)
local function takeCredits(player: Player, recipeId: string, amount: number, onTaken: ((Credit, number) -> ())?): number
	local list = credits[player]
	if list == nil then
		return 0
	end
	pruneCredits(list, Workspace:GetServerTimeNow())
	local remaining = amount
	for _, credit in list do
		if remaining <= 0 then
			break
		end
		if credit.RecipeId == recipeId then
			local used = math.min(credit.Amount, remaining)
			credit.Amount -= used
			remaining -= used
			if onTaken then
				onTaken(credit, used)
			end
		end
	end
	pruneCredits(list, Workspace:GetServerTimeNow())
	return amount - remaining
end

local function addCredit(receiver: Player, giver: Player, recipeId: string, amount: number)
	local list = credits[receiver]
	if list == nil then
		list = {}
		credits[receiver] = list
	end
	local now = Workspace:GetServerTimeNow()
	pruneCredits(list, now)
	while #list >= Coop.MaxCreditsPerPlayer do
		table.remove(list, 1)
	end
	table.insert(list, {
		GiverUserId = giver.UserId,
		GiverName = giver.DisplayName,
		RecipeId = recipeId,
		Amount = amount,
		ExpiresAt = now + Coop.GiftCreditSeconds,
	})
end

local function dropCreditsOf(giverUserId: number)
	for _, list in credits do
		for index = #list, 1, -1 do
			if list[index].GiverUserId == giverUserId then
				table.remove(list, index)
			end
		end
	end
end

local function notifyExpired(offer: Offer)
	if offer.From.Parent == Players then
		NotifyService.Notify(offer.From, "CoopExpiredGiver", "info", offerArgs(languageOf(offer.From), offer.To.DisplayName, offer))
	end
	if offer.To.Parent == Players then
		NotifyService.Notify(offer.To, "CoopExpiredReceiver", "info", offerArgs(languageOf(offer.To), offer.From.DisplayName, offer))
	end
end

local function onOffer(player: Player, targetRaw: unknown, itemRaw: unknown, amountRaw: unknown)
	if not limiter:Check(player, "CoopOffer") then
		return
	end
	local targetUserId = readInteger(targetRaw, 1, Coop.MaxRemoteIdValue)
	local amount = readInteger(amountRaw, 1, Coop.MaxItemsPerGift)
	if targetUserId == nil or amount == nil then
		reject(player, "CoopOffer", `targetUserId/amount ไม่ถูกต้อง ({typeof(targetRaw)}, {typeof(amountRaw)})`, "CoopInvalid", nil)
		return
	end
	if type(itemRaw) ~= "string" or #(itemRaw :: string) == 0 or #(itemRaw :: string) > Coop.MaxItemIdLength then
		reject(player, "CoopOffer", `itemId ไม่ถูกต้อง ({typeof(itemRaw)})`, "CoopInvalid", nil)
		return
	end
	local itemId = itemRaw :: string
	if not isKnownItem(itemId) then
		reject(player, "CoopOffer", `ไม่รู้จัก itemId {itemId}`, "CoopInvalid", nil)
		return
	end
	if targetUserId == player.UserId then
		reject(player, "CoopOffer", "ส่งให้ตัวเอง", "CoopSelf", nil)
		return
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if target == nil or target.Parent ~= Players then
		reject(player, "CoopOffer", `ไม่พบผู้เล่น userId {targetUserId}`, "CoopTargetGone", nil)
		return
	end
	local data = DataService.GetData(player)
	local targetData = DataService.GetData(target)
	if data == nil or targetData == nil then
		reject(player, "CoopOffer", "ข้อมูลผู้เล่น (ผู้ให้หรือผู้รับ) ยังโหลดไม่เสร็จ", "CoopDataNotReady", nil)
		return
	end
	local language = data.Settings.Language
	if not isNearEachOther(player, target) then
		local args: { [string]: string | number } = { player = target.DisplayName }
		reject(player, "CoopOffer", `อยู่ไกล {target.Name} เกินระยะ หรือไม่มีตัวละคร`, "CoopTooFar", args)
		return
	end
	local have = data.Inventory[itemId] or 0
	if have < amount then
		local args: { [string]: string | number } = { item = itemName(language, itemId), count = amount }
		reject(player, "CoopOffer", `ของไม่พอ {itemId}: ต้องการ {amount} มี {have}`, "CoopNotEnough", args)
		return
	end
	if countOffers(player, true) >= Coop.MaxPendingOffersPerPlayer then
		reject(player, "CoopOffer", "คำขอที่รอคำตอบเกินจำนวนสูงสุด", "CoopTooManyPending", nil)
		return
	end
	if countOffers(target, false) >= Coop.MaxIncomingOffersPerPlayer then
		local args: { [string]: string | number } = { player = target.DisplayName }
		reject(player, "CoopOffer", `{target.Name} มีคำขอค้างเกินจำนวนสูงสุด`, "CoopTargetBusy", args)
		return
	end
	if not hasRoom(targetData, itemId, amount) then
		local args: { [string]: string | number } = { player = target.DisplayName }
		reject(player, "CoopOffer", `กระเป๋า {target.Name} เต็มสำหรับ {itemId} x{amount}`, "CoopReceiverFull", args)
		return
	end

	offerCounter += 1
	local offer: Offer = {
		Id = offerCounter,
		From = player,
		To = target,
		ItemId = itemId,
		Amount = amount,
		ExpiresAt = Workspace:GetServerTimeNow() + Coop.OfferTimeoutSeconds,
	}
	offers[offer.Id] = offer

	local targetLanguage = targetData.Settings.Language
	stateEvent:FireClient(target, {
		Type = Coop.OfferTypes.Offer,
		OfferId = offer.Id,
		FromName = player.DisplayName,
		ItemId = itemId,
		Amount = amount,
		ExpiresAt = offer.ExpiresAt,
		Language = targetLanguage,
	})
	NotifyService.Notify(player, "CoopOfferSent", "info", offerArgs(language, target.DisplayName, offer))
	NotifyService.Notify(target, "CoopOfferReceived", "info", offerArgs(targetLanguage, player.DisplayName, offer))

	task.delay(Coop.OfferTimeoutSeconds, function()
		if offers[offer.Id] ~= offer then
			return
		end
		closeOffer(offer)
		warn(`{LOG} คำขอ {offer.Id} ({player.Name} -> {target.Name}) หมดเวลา`)
		notifyExpired(offer)
	end)
	print(`{LOG} {player.Name} ส่งคำขอ {offer.Id}: {itemId} x{amount} ให้ {target.Name}`)
end

local function payHelperBonuses(receiver: Player, recipeId: string, amount: number, coinsAdded: number)
	local perGiver: { [number]: { Name: string, Taken: number } } = {}
	local taken = takeCredits(receiver, recipeId, amount, function(credit: Credit, used: number)
		local entry = perGiver[credit.GiverUserId]
		if entry == nil then
			entry = { Name = credit.GiverName, Taken = 0 }
			perGiver[credit.GiverUserId] = entry
		end
		entry.Taken += used
	end)
	if taken <= 0 or coinsAdded <= 0 then
		return
	end
	for giverUserId, entry in perGiver do
		local giver = Players:GetPlayerByUserId(giverUserId)
		local giverData = if giver then DataService.GetData(giver) else nil
		if giver == nil or giver.Parent ~= Players or giverData == nil then
			warn(`{LOG} ไม่จ่ายโบนัสผู้ช่วยให้ {entry.Name} (userId {giverUserId}): ออกจากเกมแล้วหรือข้อมูลไม่พร้อม`)
			continue
		end
		local wanted = math.floor(coinsAdded * Coop.HelperBonusRatio * entry.Taken / amount)
		if wanted <= 0 then
			continue
		end
		local day = bonusDayOf(giverUserId)
		local pairKey = tostring(receiver.UserId)
		local pairUsed = day.Pairs[pairKey] or 0
		local room = math.min(Coop.HelperBonusDailyCap - day.Total, Coop.HelperBonusPerPairDailyCap - pairUsed)
		local limits = PlayerDataConfig.Limits
		local bonus = math.max(0, math.min(wanted, room, limits.MaxCoins - giverData.Coins))
		if bonus > 0 then
			giverData.Coins += bonus
			day.Total += bonus
			day.Pairs[pairKey] = pairUsed + bonus
			currencyEvent:FireClient(giver, { Coins = giverData.Coins, Reputation = giverData.Reputation })
			local args: { [string]: string | number } = { coins = bonus, player = receiver.DisplayName }
			NotifyService.Notify(giver, "CoopBonusEarned", "success", args)
			if receiver.Parent == Players then
				local thanks: { [string]: string | number } = { player = giver.DisplayName }
				NotifyService.Notify(receiver, "CoopHelperThanks", "info", thanks)
			end
			print(`{LOG} โบนัสผู้ช่วย {giver.Name} +{bonus} เหรียญ จากการเสิร์ฟของ {receiver.Name} ({recipeId})`)
		end
		if bonus < wanted then
			warn(`{LOG} โบนัสผู้ช่วย {giver.Name} ถูกจำกัด ได้ {bonus}/{wanted} (วันนี้รวม {day.Total}, คู่ {day.Pairs[pairKey] or 0})`)
			local args: { [string]: string | number } = { coins = bonus }
			NotifyService.Notify(giver, "CoopBonusCapped", "info", args)
		end
	end
end

local function onRespond(player: Player, offerIdRaw: unknown, acceptRaw: unknown)
	if not limiter:Check(player, "CoopRespond") then
		return
	end
	local offerId = readInteger(offerIdRaw, 1, Coop.MaxRemoteIdValue)
	if offerId == nil or type(acceptRaw) ~= "boolean" then
		reject(player, "CoopRespond", `offerId/accept ไม่ถูกต้อง ({typeof(offerIdRaw)}, {typeof(acceptRaw)})`, "CoopInvalid", nil)
		return
	end
	local offer = offers[offerId]
	if offer == nil or offer.To ~= player then
		reject(player, "CoopRespond", `ไม่มีคำขอ {offerId} สำหรับผู้เล่นนี้`, "CoopOfferGone", nil)
		return
	end
	closeOffer(offer)
	local giver = offer.From
	local language = languageOf(player)

	if acceptRaw == false then
		NotifyService.Notify(player, "CoopDeclinedSelf", "info", playerArgs(giver.DisplayName))
		if giver.Parent == Players then
			NotifyService.Notify(giver, "CoopDeclinedGiver", "info", offerArgs(languageOf(giver), player.DisplayName, offer))
		end
		return
	end

	if Workspace:GetServerTimeNow() >= offer.ExpiresAt then
		warn(`{LOG} {player.Name} กดรับคำขอ {offer.Id} หลังหมดเวลา`)
		notifyExpired(offer)
		return
	end
	local giverData = if giver.Parent == Players then DataService.GetData(giver) else nil
	local data = DataService.GetData(player)
	if giverData == nil then
		warn(`{LOG} คำขอ {offer.Id} ยกเลิก: ผู้ให้ {giver.Name} ออกจากเกมหรือข้อมูลไม่พร้อม`)
		NotifyService.Notify(player, "CoopGiverLeft", "error", playerArgs(giver.DisplayName))
		return
	end
	if data == nil then
		reject(player, "CoopRespond", "ข้อมูลผู้รับยังโหลดไม่เสร็จ", "CoopDataNotReady", nil)
		return
	end
	if not isNearEachOther(player, giver) then
		local args: { [string]: string | number } = { player = giver.DisplayName }
		reject(player, "CoopRespond", `อยู่ไกล {giver.Name} เกินระยะตอนกดรับ`, "CoopTooFar", args)
		NotifyService.Notify(giver, "CoopTooFar", "error", playerArgs(player.DisplayName))
		return
	end
	local have = giverData.Inventory[offer.ItemId] or 0
	if have < offer.Amount then
		warn(`{LOG} คำขอ {offer.Id} ล้มเหลว: {giver.Name} มี {offer.ItemId} {have}/{offer.Amount}`)
		local selfArgs: { [string]: string | number } = {
			player = giver.DisplayName,
			item = itemName(language, offer.ItemId),
		}
		local giverArgs: { [string]: string | number } = {
			item = itemName(languageOf(giver), offer.ItemId),
			count = offer.Amount,
		}
		NotifyService.Notify(player, "CoopGiverNotEnough", "error", selfArgs)
		NotifyService.Notify(giver, "CoopNotEnough", "error", giverArgs)
		return
	end
	if not hasRoom(data, offer.ItemId, offer.Amount) then
		warn(`{LOG} คำขอ {offer.Id} ล้มเหลว: กระเป๋า {player.Name} เต็ม`)
		NotifyService.Notify(player, "CoopReceiverFullSelf", "error", offerArgs(language, giver.DisplayName, offer))
		NotifyService.Notify(giver, "CoopReceiverFull", "error", playerArgs(player.DisplayName))
		return
	end

	-- จากตรงนี้ถึงจบการย้ายของไม่มี yield: หักจากผู้ให้และเพิ่มให้ผู้รับพร้อมกันเสมอ
	local left = have - offer.Amount
	if left > 0 then
		giverData.Inventory[offer.ItemId] = left
	else
		giverData.Inventory[offer.ItemId] = nil
	end
	data.Inventory[offer.ItemId] = (data.Inventory[offer.ItemId] or 0) + offer.Amount
	if Recipes[offer.ItemId] ~= nil then
		-- ขนมที่ผู้ให้ถือพร้อมเครดิตของตัวเองถูกย้ายออก เครดิตเดิมที่ผู้ให้ได้รับมาต้องลดตามนี้
		takeCredits(giver, offer.ItemId, offer.Amount, nil)
		addCredit(player, giver, offer.ItemId, offer.Amount)
	end

	InventoryService.Send(giver, giverData)
	InventoryService.Send(player, data)
	NotifyService.Notify(player, "CoopAcceptedReceiver", "success", offerArgs(language, giver.DisplayName, offer))
	NotifyService.Notify(giver, "CoopAcceptedGiver", "success", offerArgs(languageOf(giver), player.DisplayName, offer))
	print(`{LOG} {giver.Name} -> {player.Name}: {offer.ItemId} x{offer.Amount} (คำขอ {offer.Id})`)
end

-- ServeService เรียกหลังเสิร์ฟสำเร็จ (ห้าม yield) จ่ายโบนัสผู้ช่วยให้ผู้ที่ให้ขนมชนิดนี้แก่ผู้เสิร์ฟ
function CoopService.OnServed(player: Player, recipeId: string, amount: number, coinsAdded: number)
	if amount <= 0 then
		return
	end
	payHelperBonuses(player, recipeId, amount, coinsAdded)
end

local function onPlayerRemoving(player: Player)
	local affected: { Offer } = {}
	for _, offer in offers do
		if offer.From == player or offer.To == player then
			table.insert(affected, offer)
		end
	end
	for _, offer in affected do
		closeOffer(offer)
		if offer.From == player then
			warn(`{LOG} {player.Name} (ผู้ให้) ออกจากเกม ยกเลิกคำขอ {offer.Id}`)
			if offer.To.Parent == Players then
				NotifyService.Notify(offer.To, "CoopGiverLeft", "info", playerArgs(player.DisplayName))
			end
		else
			warn(`{LOG} {player.Name} (ผู้รับ) ออกจากเกม ยกเลิกคำขอ {offer.Id}`)
			if offer.From.Parent == Players then
				NotifyService.Notify(offer.From, "CoopTargetLeft", "info", playerArgs(player.DisplayName))
			end
		end
	end
	limiter:Remove(player)
	if credits[player] ~= nil then
		credits[player] = nil
	end
	-- ผู้ให้ออกแล้วไม่จ่ายโบนัส (ไม่มีข้อมูลให้เซฟ) ล้างเครดิตที่ผูกกับเขา
	dropCreditsOf(player.UserId)
end

function CoopService.Start()
	table.insert(connections, offerEvent.OnServerEvent:Connect(onOffer))
	table.insert(connections, respondEvent.OnServerEvent:Connect(onRespond))
	table.insert(connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
end

return CoopService
