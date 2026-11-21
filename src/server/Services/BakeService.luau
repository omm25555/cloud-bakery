--!strict
-- อบขนม: โต๊ะผสม (เลือกสูตร + มินิเกมจังหวะ) แล้วเข้าเตาอบ รอเวลา แล้วเก็บที่เตา
-- server สุ่มจังหวะ จับเวลาเอง และให้คะแนนจากเวลากดที่ client ส่งมา (ตรวจความเป็นไปได้ทุกครั้ง)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = Shared.Config
local GameConfig = require(Config.Game)
local Minigame = require(Config.Minigame)
local Progression = require(Config.Progression)
local Recipes = require(Config.Recipes)
local Formulas = require(Shared.Formulas)
local Locale = require(Shared.Locale)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local NotifyService = require(script.Parent.NotifyService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local QuestService = require(script.Parent.QuestService)
local WorldService = require(script.Parent.WorldService)
local RateLimiter = require(script.Parent.Parent.Modules.RateLimiter)

local SOURCE = "BakeService"

type Session = {
	id: number,
	recipeId: string,
	startedAt: number,
	beats: { number },
	duration: number,
}

local BakeService = {}

local sessions: { [Player]: Session } = {}
local nextSessionId = 0
local rng = Random.new()

local openMixingEvent = Remotes.GetEvent("OpenMixing")
local cancelMixEvent = Remotes.GetEvent("CancelMix")
local startMixFunction = Remotes.GetFunction("StartMix")
local finishMixFunction = Remotes.GetFunction("FinishMix")

local function limiter(name: string): RateLimiter.RateLimiter
	local limit = GameConfig.RateLimits[name]
	return RateLimiter.new(limit.MaxCalls, limit.WindowSeconds)
end
local startLimiter = limiter("StartMix")
local finishLimiter = limiter("FinishMix")
local promptLimiter = limiter("Prompt")

local function bilingual(key: string): string
	return `{Locale.get("th", key)} ({Locale.get("en", key)})`
end

local function fail(player: Player, key: string, args: { [string]: string | number }?): Types.SimpleResult
	NotifyService.blocked(player, key, args)
	return { ok = false, reason = key }
end

local function missingText(data: Types.SaveData, recipeId: string): string?
	local parts: { string } = {}
	for _, ingredientId in Progression.IngredientOrder do
		local need = Recipes[recipeId].Ingredients[ingredientId]
		if need then
			local have = data.ingredients[ingredientId] or 0
			if have < need then
				table.insert(parts, `{Locale.icon(ingredientId)} x{need - have}`)
			end
		end
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, " ")
end

local function ovenFull(data: Types.SaveData): (boolean, number)
	local slots = Formulas.ovenSlots(Formulas.upgradeLevel(data.upgrades, "Oven"))
	return #data.oven >= slots, slots
end

local function activeSession(player: Player): Session?
	local session = sessions[player]
	if session and os.clock() - session.startedAt > Minigame.SessionTimeoutSeconds then
		sessions[player] = nil
		return nil
	end
	return session
end

-- ตรวจเงื่อนไขก่อนผสม (ใช้ทั้งตอนกด prompt และตอนเริ่มมินิเกม)
local function checkCanMix(player: Player, data: Types.SaveData, recipeId: string?): Types.SimpleResult
	if activeSession(player) then
		return fail(player, "n.mixBusy")
	end
	local full, slots = ovenFull(data)
	if full then
		return fail(player, "n.ovenFull", { slots = slots })
	end
	if recipeId then
		local level = Formulas.levelInfo(data.reputation).level
		if not Formulas.isRecipeUnlocked(recipeId, level) then
			return fail(player, "n.recipeLocked", { recipe = `item.{recipeId}`, level = Progression.RecipeUnlockLevel[recipeId] })
		end
		local missing = missingText(data, recipeId)
		if missing then
			return fail(player, "n.missingIngredients", { missing = missing })
		end
	end
	return { ok = true }
end

local function makeBeats(): ({ number }, number)
	local beats: { number } = {}
	local t = Minigame.LeadInSeconds
	for _ = 1, Minigame.BeatCount do
		t += rng:NextNumber(Minigame.BeatIntervalMinSeconds, Minigame.BeatIntervalMaxSeconds)
		table.insert(beats, math.floor(t * 1000) / 1000)
	end
	return beats, t + Minigame.TailSeconds
end

local function startMix(player: Player, recipeId: any): Types.StartMixResult
	if not startLimiter.allow(player) then
		NotifyService.blocked(player, "n.tooFast")
		return { ok = false, reason = "n.tooFast" }
	end
	if typeof(recipeId) ~= "string" or Recipes[recipeId] == nil then
		NotifyService.rejected(SOURCE, player, `สูตรไม่ถูกต้อง: {tostring(recipeId)}`)
		return { ok = false, reason = "n.rejected" }
	end
	local id: string = recipeId
	local data = PlayerDataService.get(player)
	if data == nil then
		NotifyService.blocked(player, "n.loading")
		return { ok = false, reason = "n.loading" }
	end
	local stations = WorldService.getStations()
	if WorldService.distanceTo(player, stations.mixingTable) > GameConfig.InteractMaxDistance then
		NotifyService.rejected(SOURCE, player, "เริ่มผสมจากระยะไกลเกินไป", "n.tooFar")
		return { ok = false, reason = "n.tooFar" }
	end
	local check = checkCanMix(player, data, id)
	if not check.ok then
		return { ok = false, reason = check.reason }
	end
	nextSessionId += 1
	local beats, duration = makeBeats()
	sessions[player] = {
		id = nextSessionId,
		recipeId = id,
		startedAt = os.clock(),
		beats = beats,
		duration = duration,
	}
	return {
		ok = true,
		sessionId = nextSessionId,
		recipeId = id,
		beats = beats,
		leadIn = Minigame.LeadInSeconds,
		duration = duration,
	}
end

-- ตรวจรูปแบบเวลากด: array ของตัวเลขเรียงจากน้อยไปมาก อยู่ในช่วงเวลาของมินิเกม
local function readTaps(raw: any, duration: number): { number }?
	if typeof(raw) ~= "table" then
		return nil
	end
	local taps: { number } = {}
	local count = 0
	for key in raw do
		count += 1
		if typeof(key) ~= "number" or count > Minigame.MaxTaps then
			return nil
		end
	end
	local last = -math.huge
	for index = 1, count do
		local t = raw[index]
		if typeof(t) ~= "number" or t ~= t or t < 0 or t > duration + Minigame.LatencyToleranceSeconds or t < last then
			return nil
		end
		last = t
		table.insert(taps, t)
	end
	return taps
end

local function scoreTaps(beats: { number }, taps: { number }): (number, boolean)
	local used: { [number]: boolean } = {}
	local total = 0
	local hits = 0
	local maxError = 0
	for _, beat in beats do
		local bestIndex: number? = nil
		local bestError = math.huge
		for index, tap in taps do
			local err = math.abs(tap - beat)
			if not used[index] and err < bestError then
				bestError = err
				bestIndex = index
			end
		end
		if bestIndex and bestError <= Minigame.GoodWindowSeconds then
			used[bestIndex] = true
			hits += 1
			maxError = math.max(maxError, bestError)
			total += if bestError <= Minigame.PerfectWindowSeconds then 1 else Minigame.GoodHitScore
		end
	end
	local extra = #taps - hits
	total -= extra * Minigame.GoodHitScore
	local score = math.clamp(total / #beats, 0, 1)
	local suspicious = hits == #beats and #beats >= 4 and maxError < Minigame.SuspiciousErrorSeconds
	return score, suspicious
end

local function finishMix(player: Player, sessionId: any, rawTaps: any): Types.FinishMixResult
	if not finishLimiter.allow(player) then
		NotifyService.blocked(player, "n.tooFast")
		return { ok = false, reason = "n.tooFast" }
	end
	local session = sessions[player]
	if session == nil or typeof(sessionId) ~= "number" or session.id ~= sessionId then
		NotifyService.rejected(SOURCE, player, `ไม่มี session ผสม หรือ id ไม่ตรง ({tostring(sessionId)})`)
		return { ok = false, reason = "n.rejected" }
	end
	local elapsed = os.clock() - session.startedAt
	if elapsed > Minigame.SessionTimeoutSeconds then
		sessions[player] = nil
		NotifyService.blocked(player, "n.mixExpired")
		return { ok = false, reason = "n.mixExpired" }
	end
	local tolerance = Minigame.LatencyToleranceSeconds
	if elapsed < session.duration - tolerance then
		sessions[player] = nil
		NotifyService.rejected(SOURCE, player, `ส่งผลเร็วกว่าความยาวมินิเกม ({string.format("%.2f", elapsed)}s < {session.duration}s)`)
		return { ok = false, reason = "n.rejected" }
	end
	local taps = readTaps(rawTaps, session.duration)
	if taps == nil or (#taps > 0 and taps[#taps] > elapsed + tolerance) then
		sessions[player] = nil
		NotifyService.rejected(SOURCE, player, "ข้อมูลเวลากดไม่ถูกต้อง")
		return { ok = false, reason = "n.rejected" }
	end
	sessions[player] = nil

	local data = PlayerDataService.get(player)
	if data == nil then
		NotifyService.blocked(player, "n.loading")
		return { ok = false, reason = "n.loading" }
	end
	local recipeId = session.recipeId
	-- ตรวจซ้ำตอนหักวัตถุดิบ (ระหว่างเล่นอาจใช้ของไปแล้ว)
	local missing = missingText(data, recipeId)
	if missing then
		NotifyService.blocked(player, "n.missingIngredients", { missing = missing })
		return { ok = false, reason = "n.missingIngredients" }
	end
	local full, slots = ovenFull(data)
	if full then
		NotifyService.blocked(player, "n.ovenFull", { slots = slots })
		return { ok = false, reason = "n.ovenFull" }
	end

	local score, suspicious = scoreTaps(session.beats, taps)
	local quality = if score >= Minigame.PerfectQualityThreshold
		then "Perfect"
		elseif score >= Minigame.GoodQualityThreshold then "Good"
		else "Okay"
	if suspicious and quality == "Perfect" then
		warn(`[{SOURCE}] ผลมินิเกมของ {player.Name} ({player.UserId}) แม่นผิดปกติ ลดเป็น Good`)
		quality = "Good"
	end
	local pieces = Minigame.BasePieces + (if quality == "Perfect" then Minigame.PerfectBonusPieces else 0)
	local seconds = Formulas.bakeSeconds(recipeId, Formulas.upgradeLevel(data.upgrades, "Oven"))
	local reputation = Minigame.QualityReputation[quality] or 0

	PlayerDataService.update(player, function(saved)
		for ingredientId, need in Recipes[recipeId].Ingredients do
			saved.ingredients[ingredientId] = math.max(0, (saved.ingredients[ingredientId] or 0) - need)
		end
		table.insert(saved.oven, { recipeId = recipeId, pieces = pieces, readyAt = os.time() + seconds })
		saved.reputation += reputation
	end)
	NotifyService.success(player, "n.mixDone", {
		quality = `mix.{quality}`,
		recipe = `item.{recipeId}`,
		pieces = pieces,
		seconds = seconds,
	})
	return { ok = true, quality = quality, score = score, pieces = pieces, readyIn = seconds }
end

local function collectOven(player: Player)
	if not promptLimiter.allow(player) then
		NotifyService.blocked(player, "n.tooFast")
		return
	end
	if WorldService.distanceTo(player, WorldService.getStations().oven) > GameConfig.InteractMaxDistance then
		NotifyService.rejected(SOURCE, player, "เก็บขนมจากเตาจากระยะไกลเกินไป", "n.tooFar")
		return
	end
	local data = PlayerDataService.get(player)
	if data == nil then
		NotifyService.blocked(player, "n.loading")
		return
	end
	if #data.oven == 0 then
		NotifyService.blocked(player, "n.ovenEmpty")
		return
	end
	local now = os.time()
	local collected: { [string]: number } = {}
	local anyReady = false
	local soonest = math.huge
	local bagFullItem: string? = nil
	PlayerDataService.update(player, function(saved)
		local remaining: { Types.OvenSlot } = {}
		for _, slot in saved.oven do
			if slot.readyAt <= now then
				anyReady = true
				local have = saved.goods[slot.recipeId] or 0
				if have + slot.pieces > GameConfig.MaxStackPerItem then
					bagFullItem = slot.recipeId
					table.insert(remaining, slot)
				else
					saved.goods[slot.recipeId] = have + slot.pieces
					saved.totalBaked += slot.pieces
					collected[slot.recipeId] = (collected[slot.recipeId] or 0) + slot.pieces
				end
			else
				soonest = math.min(soonest, slot.readyAt - now)
				table.insert(remaining, slot)
			end
		end
		saved.oven = remaining
	end)
	if not anyReady then
		NotifyService.blocked(player, "n.ovenNotReady", { seconds = soonest })
		return
	end
	local parts: { string } = {}
	for _, recipeId in Progression.RecipeOrder do
		local amount = collected[recipeId]
		if amount then
			table.insert(parts, `{Locale.icon(recipeId)} x{amount}`)
			QuestService.addProgress(player, "Bake", recipeId, amount)
		end
	end
	if #parts > 0 then
		NotifyService.success(player, "n.ovenCollected", { list = table.concat(parts, "  ") })
	end
	if bagFullItem then
		NotifyService.blocked(player, "n.bagFull", { item = `item.{bagFullItem}` })
	end
end

local function onMixPrompt(player: Player)
	if not promptLimiter.allow(player) then
		NotifyService.blocked(player, "n.tooFast")
		return
	end
	if WorldService.distanceTo(player, WorldService.getStations().mixingTable) > GameConfig.InteractMaxDistance then
		NotifyService.rejected(SOURCE, player, "เปิดโต๊ะผสมจากระยะไกลเกินไป", "n.tooFar")
		return
	end
	local data = PlayerDataService.get(player)
	if data == nil then
		NotifyService.blocked(player, "n.loading")
		return
	end
	local check = checkCanMix(player, data, nil)
	if check.ok then
		openMixingEvent:FireClient(player)
	end
end

local function makePrompt(anchor: BasePart, actionKey: string, objectKey: string): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = bilingual(actionKey)
	prompt.ObjectText = bilingual(objectKey)
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = GameConfig.PromptMaxActivationDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	return prompt
end

local function guarded(name: string, fn: (player: Player) -> ()): (player: Player) -> ()
	return function(player: Player)
		local ok, err = pcall(function()
			fn(player)
		end)
		if not ok then
			NotifyService.unexpected(SOURCE, player, `{name} ล้มเหลว: {err}`)
		end
	end
end

function BakeService.Start()
	local stations = WorldService.getStations()
	makePrompt(stations.mixingTable, "hud.mix", "station.MixingTable").Triggered:Connect(guarded("Mix prompt", onMixPrompt))
	makePrompt(stations.oven, "hud.collect", "station.Oven").Triggered:Connect(guarded("Oven collect", collectOven))

	startMixFunction.OnServerInvoke = function(player: Player, recipeId: any): Types.StartMixResult
		local ok, result = pcall(startMix, player, recipeId)
		if ok then
			return result
		end
		sessions[player] = nil
		NotifyService.unexpected(SOURCE, player, `StartMix ล้มเหลว: {result}`)
		return { ok = false, reason = "n.unexpected" }
	end

	finishMixFunction.OnServerInvoke = function(player: Player, sessionId: any, taps: any): Types.FinishMixResult
		local ok, result = pcall(finishMix, player, sessionId, taps)
		if ok then
			return result
		end
		sessions[player] = nil
		NotifyService.unexpected(SOURCE, player, `FinishMix ล้มเหลว: {result}`)
		return { ok = false, reason = "n.unexpected" }
	end

	cancelMixEvent.OnServerEvent:Connect(function(player: Player)
		sessions[player] = nil
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		sessions[player] = nil
	end)
end

return BakeService
