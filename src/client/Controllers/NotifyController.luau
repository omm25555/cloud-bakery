--!strict
-- แสดงแจ้งเตือนแบบ toast ด้านบนกลางจอ (ระบบเดียวทั้งเกม รับจาก NotifyService และจาก client เอง)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.Game)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local UI = require(script.Parent.Parent.Modules.UI)
local StateController = require(script.Parent.StateController)

local NotifyController = {}

local KIND_STYLE: { [string]: { color: Color3, icon: string } } = {
	success = { color = Color3.fromRGB(120, 200, 140), icon = "✨" },
	info = { color = Color3.fromRGB(150, 190, 240), icon = "💬" },
	warn = { color = Color3.fromRGB(255, 180, 110), icon = "💡" },
	error = { color = Color3.fromRGB(240, 110, 120), icon = "⚠️" },
}

local container: Frame? = nil

local function ensureContainer(): Frame
	local existing = container
	if existing then
		return existing
	end
	local gui = UI.screenGui("CloudBakeryNotify", 20)
	local frame = UI.frame({
		name = "Toasts",
		parent = gui,
		size = UDim2.new(0, 520, 1, 0),
		position = UDim2.new(0.5, 0, 0, 70),
		anchor = Vector2.new(0.5, 0),
		transparency = 1,
		radius = 0,
	})
	UI.list(frame, 8, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center)
	container = frame
	return frame
end

function NotifyController.show(kind: Types.NotifyKind, key: string, args: { [string]: string | number }?)
	local frame = ensureContainer()
	local style = KIND_STYLE[kind] or KIND_STYLE.info
	local text = StateController.t(key, args)

	local toasts: { Frame } = {}
	for _, child in frame:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts >= GameConfig.NotifyMaxVisible then
		toasts[1]:Destroy()
	end

	local toast = UI.frame({
		name = "Toast",
		parent = frame,
		size = UDim2.new(1, 0, 0, 0),
		color = UI.Colors.Cream,
		radius = 16,
		stroke = style.color,
		strokeThickness = 3,
	})
	toast.AutomaticSize = Enum.AutomaticSize.Y
	UI.padding(toast, 10)
	local label = UI.label({
		parent = toast,
		text = `{style.icon}  {text}`,
		size = UDim2.new(1, 0, 0, 0),
		textSize = 19,
		wrap = true,
		alignX = Enum.TextXAlignment.Center,
	})
	label.AutomaticSize = Enum.AutomaticSize.Y

	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = toast
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()

	task.delay(GameConfig.NotifyDurationSeconds, function()
		if toast.Parent == nil then
			return
		end
		local fade = TweenService:Create(scale, TweenInfo.new(0.2), { Scale = 0.01 })
		fade:Play()
		fade.Completed:Wait()
		toast:Destroy()
	end)
end

function NotifyController.Start()
	ensureContainer()
	Remotes.GetEvent("Notify").OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" or typeof(payload.key) ~= "string" then
			warn("[NotifyController] ได้รับแจ้งเตือนรูปแบบไม่ถูกต้อง ข้ามไป")
			return
		end
		local kind: Types.NotifyKind = if payload.kind == "success" or payload.kind == "warn" or payload.kind == "error"
			then payload.kind
			else "info"
		local args: { [string]: string | number }? = if typeof(payload.args) == "table" then payload.args else nil
		NotifyController.show(kind, payload.key, args)
	end)
end

return NotifyController
