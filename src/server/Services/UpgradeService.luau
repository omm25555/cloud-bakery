--!strict
-- อัปเกรดร้าน 3 สาย (สวน / เตาอบ / หน้าร้าน) ราคาและผลอยู่ใน Config/Upgrades

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = Shared.Config
local GameConfig = require(Config.Game)
local Upgrades = require(Config.Upgrades)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local NotifyService = require(script.Parent.NotifyService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RateLimiter = require(script.Parent.Parent.Modules.RateLimiter)

local SOURCE = "UpgradeService"

local UpgradeService = {}

local upgradeFunction = Remotes.GetFunction("RequestUpgrade")
local limit = GameConfig.RateLimits.Upgrade
local limiter = RateLimiter.new(limit.MaxCalls, limit.WindowSeconds)

local function requestUpgrade(player: Player, lineId: any): Types.SimpleResult
	if not limiter.allow(player) then
		NotifyService.blocked(player, "n.tooFast")
		return { ok = false, reason = "n.tooFast" }
	end
	if typeof(lineId) ~= "string" or Upgrades.Lines[lineId] == nil then
		NotifyService.rejected(SOURCE, player, `สายอัปเกรดไม่ถูกต้อง: {tostring(lineId)}`)
		return { ok = false, reason = "n.rejected" }
	end
	local id: string = lineId
	local data = PlayerDataService.get(player)
	if data == nil then
		NotifyService.blocked(player, "n.loading")
		return { ok = false, reason = "n.loading" }
	end
	local lineKey = `upgrade.{id}`
	local level = Formulas.upgradeLevel(data.upgrades, id)
	local cost = Formulas.upgradeCost(id, level)
	if cost == nil then
		NotifyService.blocked(player, "n.upgradeMax", { line = lineKey })
		return { ok = false, reason = "n.upgradeMax" }
	end
	if data.coins < cost then
		NotifyService.blocked(player, "n.notEnoughCoins", { cost = cost, have = data.coins })
		return { ok = false, reason = "n.notEnoughCoins" }
	end
	PlayerDataService.update(player, function(saved)
		saved.coins -= cost
		saved.upgrades[id] = level + 1
	end)
	NotifyService.success(player, "n.upgraded", { line = lineKey, level = level + 1 })
	return { ok = true }
end

function UpgradeService.Start()
	upgradeFunction.OnServerInvoke = function(player: Player, lineId: any): Types.SimpleResult
		local ok, result = pcall(requestUpgrade, player, lineId)
		if ok then
			return result
		end
		NotifyService.unexpected(SOURCE, player, `อัปเกรดล้มเหลว: {result}`)
		return { ok = false, reason = "n.unexpected" }
	end
end

return UpgradeService
