--!strict
-- เก็บ state ล่าสุดที่ server ส่งมา (ข้อมูลผู้เล่น + ออเดอร์) และแจ้ง Controller อื่นเมื่อเปลี่ยน
-- client ไม่ตัดสินอะไรเอง ใช้ข้อมูลนี้แสดงผลเท่านั้น

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Locale = require(Shared.Locale)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local StateController = {}

local state: Types.PlayerState? = nil
local orders: { Types.Order } = {}
local clockOffset = 0 -- serverTime - os.time() ตอนได้รับ state
local stateListeners: { (state: Types.PlayerState) -> () } = {}
local orderListeners: { (orders: { Types.Order }) -> () } = {}

local function emitState(newState: Types.PlayerState)
	for _, listener in stateListeners do
		task.spawn(listener, newState)
	end
end

local function applyState(newState: any)
	if typeof(newState) ~= "table" or typeof(newState.coins) ~= "number" then
		warn("[StateController] ได้รับ state ที่รูปแบบไม่ถูกต้อง ข้ามไป")
		return
	end
	local typed: Types.PlayerState = newState
	state = typed
	clockOffset = typed.serverTime - os.time()
	emitState(typed)
end

function StateController.get(): Types.PlayerState?
	return state
end

function StateController.getOrders(): { Types.Order }
	return orders
end

function StateController.language(): string
	local current = state
	return if current then current.settings.language else "th"
end

-- เวลา server (unix) สำหรับนับถอยหลังเตาอบ
function StateController.serverUnixTime(): number
	return os.time() + clockOffset
end

-- เวลา server แบบละเอียด สำหรับนับถอยหลังออเดอร์
function StateController.serverNow(): number
	return Workspace:GetServerTimeNow()
end

-- แปลข้อความ: args ที่เป็น key ของ Locale (เช่น "item.Wheat") จะถูกแปลให้ด้วย
function StateController.t(key: string, args: { [string]: string | number }?, language: string?): string
	local lang = language or StateController.language()
	local translated: { [string]: string | number }? = nil
	if args then
		local copy: { [string]: string | number } = {}
		for name, value in args do
			if typeof(value) == "string" and Locale.has(value) then
				copy[name] = Locale.get(lang, value)
			else
				copy[name] = value
			end
		end
		translated = copy
	end
	return Locale.get(lang, key, translated)
end

-- ภาษารอง (ตัวเล็กในวงเล็บแบบ concept)
function StateController.tOther(key: string, args: { [string]: string | number }?): string
	return `({StateController.t(key, args, Locale.other(StateController.language()))})`
end

function StateController.onState(listener: (state: Types.PlayerState) -> ())
	table.insert(stateListeners, listener)
	local current = state
	if current then
		task.spawn(listener, current)
	end
end

function StateController.onOrders(listener: (orders: { Types.Order }) -> ())
	table.insert(orderListeners, listener)
	task.spawn(listener, orders)
end

function StateController.Start()
	Remotes.GetEvent("StateChanged").OnClientEvent:Connect(applyState)
	Remotes.GetEvent("OrdersChanged").OnClientEvent:Connect(function(newOrders: any)
		if typeof(newOrders) ~= "table" then
			warn("[StateController] ได้รับรายการออเดอร์ที่รูปแบบไม่ถูกต้อง ข้ามไป")
			return
		end
		local typed: { Types.Order } = newOrders
		orders = typed
		for _, listener in orderListeners do
			task.spawn(listener, typed)
		end
	end)
	task.spawn(function()
		if state ~= nil then
			return
		end
		local ok, result = pcall(function()
			return Remotes.GetFunction("GetState"):InvokeServer()
		end)
		if not ok then
			warn(`[StateController] ขอ state เริ่มต้นไม่สำเร็จ: {result}`)
		elseif result ~= nil and state == nil then
			applyState(result)
		end
	end)
end

return StateController
