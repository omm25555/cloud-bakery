--!strict
-- ภารกิจรายวัน: นับความคืบหน้า รีเซ็ตเมื่อขึ้นวันใหม่ (UTC) และให้รางวัลเมื่อครบทั้ง 3 ข้อ

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = Shared.Config
local GameConfig = require(Config.Game)
local Quests = require(Config.Quests)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local NotifyService = require(script.Parent.NotifyService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RateLimiter = require(script.Parent.Parent.Modules.RateLimiter)

local SOURCE = "QuestService"

local QuestService = {}

local claimFunction = Remotes.GetFunction("ClaimQuest")
local claimLimit = GameConfig.RateLimits.ClaimQuest
local claimLimiter = RateLimiter.new(claimLimit.MaxCalls, claimLimit.WindowSeconds)

local function today(): number
	return Formulas.questDay(os.time(), Quests.SecondsPerDay)
end

-- เรียกภายใน PlayerDataService.update เท่านั้น
local function refreshDay(data: Types.SaveData)
	local day = today()
	if data.questDay ~= day then
		data.questDay = day
		data.questProgress = {}
		data.questClaimed = false
	end
end

local function allComplete(data: Types.SaveData): boolean
	for _, quest in Quests.Daily do
		if (data.questProgress[quest.Id] or 0) < quest.Goal then
			return false
		end
	end
	return true
end

function QuestService.addProgress(player: Player, kind: Quests.QuestKind, target: string, amount: number)
	if amount <= 0 then
		return
	end
	PlayerDataService.update(player, function(data)
		refreshDay(data)
		for _, quest in Quests.Daily do
			if quest.Kind == kind and (quest.Target == "Any" or quest.Target == target) then
				local current = data.questProgress[quest.Id] or 0
				if current < quest.Goal then
					local nextValue = math.min(quest.Goal, current + amount)
					data.questProgress[quest.Id] = nextValue
					if nextValue >= quest.Goal then
						NotifyService.success(player, "n.questComplete", { quest = `quest.{quest.Id}`, goal = quest.Goal })
					end
				end
			end
		end
	end)
end

local function claim(player: Player): Types.SimpleResult
	if not claimLimiter.allow(player) then
		NotifyService.blocked(player, "n.tooFast")
		return { ok = false, reason = "n.tooFast" }
	end
	local data = PlayerDataService.get(player)
	if data == nil then
		NotifyService.blocked(player, "n.loading")
		return { ok = false, reason = "n.loading" }
	end
	local result: Types.SimpleResult = { ok = false, reason = "n.rejected" }
	PlayerDataService.update(player, function(current)
		refreshDay(current)
		if current.questClaimed then
			result = { ok = false, reason = "n.questsClaimed" }
			return
		end
		if not allComplete(current) then
			result = { ok = false, reason = "n.questsIncomplete" }
			return
		end
		current.questClaimed = true
		current.coins += Quests.RewardCoins
		current.reputation += Quests.RewardReputation
		result = { ok = true }
	end)
	if result.ok then
		NotifyService.success(player, "n.questReward", { coins = Quests.RewardCoins, rep = Quests.RewardReputation })
	else
		NotifyService.blocked(player, result.reason or "n.rejected")
	end
	return result
end

function QuestService.Start()
	PlayerDataService.onLoaded(function(player: Player, _data: Types.SaveData)
		PlayerDataService.update(player, refreshDay)
	end)

	-- ผู้เล่นที่ออนไลน์ข้ามเที่ยงคืน (UTC) ต้องเห็นภารกิจวันใหม่ทันที ไม่ใช่ค้างของเมื่อวาน
	task.spawn(function()
		local lastDay = today()
		while true do
			task.wait(GameConfig.QuestDayCheckSeconds)
			local day = today()
			if day ~= lastDay then
				lastDay = day
				for _, player in Players:GetPlayers() do
					if PlayerDataService.isLoaded(player) then
						PlayerDataService.update(player, refreshDay)
					end
				end
			end
		end
	end)

	claimFunction.OnServerInvoke = function(player: Player): Types.SimpleResult
		local ok, result = pcall(claim, player)
		if ok then
			return result
		end
		NotifyService.unexpected(SOURCE, player, `รับรางวัลภารกิจล้มเหลว: {result}`)
		return { ok = false, reason = "n.unexpected" }
	end
end

return QuestService
