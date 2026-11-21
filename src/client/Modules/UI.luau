--!strict
-- ตัวช่วยสร้าง UI สไตล์ Cloud Bakery: กรอบมนสีครีม หัวการ์ดสีม่วง ปุ่มกลมมน

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UI = {}

UI.Colors = {
	Cream = Color3.fromRGB(255, 249, 240),
	CreamDark = Color3.fromRGB(245, 232, 218),
	Purple = Color3.fromRGB(128, 84, 156),
	PurpleLight = Color3.fromRGB(196, 168, 226),
	Pink = Color3.fromRGB(255, 160, 196),
	PinkLight = Color3.fromRGB(255, 222, 234),
	Text = Color3.fromRGB(92, 60, 84),
	TextSoft = Color3.fromRGB(150, 120, 140),
	White = Color3.fromRGB(255, 255, 255),
	Gold = Color3.fromRGB(255, 200, 60),
	GoldDark = Color3.fromRGB(220, 150, 30),
	Green = Color3.fromRGB(110, 200, 120),
	Red = Color3.fromRGB(240, 90, 100),
	Sky = Color3.fromRGB(150, 210, 255),
	Shadow = Color3.fromRGB(120, 80, 120),
	Disabled = Color3.fromRGB(205, 195, 205),
}

UI.Font = Enum.Font.FredokaOne
UI.FontBody = Enum.Font.GothamMedium
UI.BaseResolution = Vector2.new(1280, 760)
UI.MinScale = 0.55
UI.MaxScale = 1.15
UI.TweenSeconds = 0.15

export type FrameProps = {
	name: string?,
	parent: Instance,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	transparency: number?,
	radius: number?,
	stroke: Color3?,
	strokeThickness: number?,
	zindex: number?,
}

export type LabelProps = {
	name: string?,
	parent: Instance,
	text: string,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	textSize: number?,
	color: Color3?,
	font: Enum.Font?,
	alignX: Enum.TextXAlignment?,
	alignY: Enum.TextYAlignment?,
	scaled: boolean?,
	wrap: boolean?,
	zindex: number?,
}

export type ButtonProps = {
	name: string?,
	parent: Instance,
	text: string,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	textColor: Color3?,
	textSize: number?,
	radius: number?,
	zindex: number?,
}

function UI.corner(parent: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 14)
	corner.Parent = parent
end

function UI.stroke(parent: GuiObject, color: Color3, thickness: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness or 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
end

function UI.padding(parent: GuiObject, pixels: number)
	local padding = Instance.new("UIPadding")
	local value = UDim.new(0, pixels)
	padding.PaddingTop = value
	padding.PaddingBottom = value
	padding.PaddingLeft = value
	padding.PaddingRight = value
	padding.Parent = parent
end

function UI.list(parent: GuiObject, spacing: number, direction: Enum.FillDirection?, alignX: Enum.HorizontalAlignment?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, spacing)
	layout.FillDirection = direction or Enum.FillDirection.Vertical
	layout.HorizontalAlignment = alignX or Enum.HorizontalAlignment.Left
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

function UI.frame(props: FrameProps): Frame
	local frame = Instance.new("Frame")
	frame.Name = props.name or "Frame"
	frame.Size = props.size
	frame.Position = props.position or UDim2.new()
	frame.AnchorPoint = props.anchor or Vector2.zero
	frame.BackgroundColor3 = props.color or UI.Colors.Cream
	frame.BackgroundTransparency = props.transparency or 0
	frame.BorderSizePixel = 0
	frame.ZIndex = props.zindex or 1
	if props.radius ~= 0 then
		UI.corner(frame, props.radius)
	end
	if props.stroke then
		UI.stroke(frame, props.stroke, props.strokeThickness)
	end
	frame.Parent = props.parent
	return frame
end

function UI.label(props: LabelProps): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = props.name or "Label"
	label.Size = props.size
	label.Position = props.position or UDim2.new()
	label.AnchorPoint = props.anchor or Vector2.zero
	label.BackgroundTransparency = 1
	label.Text = props.text
	label.TextColor3 = props.color or UI.Colors.Text
	label.Font = props.font or UI.Font
	label.TextSize = props.textSize or 18
	label.TextScaled = props.scaled == true
	label.TextWrapped = props.wrap == true or props.scaled == true
	label.TextXAlignment = props.alignX or Enum.TextXAlignment.Left
	label.TextYAlignment = props.alignY or Enum.TextYAlignment.Center
	label.ZIndex = props.zindex or 1
	label.Parent = props.parent
	return label
end

function UI.button(props: ButtonProps): TextButton
	local button = Instance.new("TextButton")
	button.Name = props.name or "Button"
	button.Size = props.size
	button.Position = props.position or UDim2.new()
	button.AnchorPoint = props.anchor or Vector2.zero
	button.BackgroundColor3 = props.color or UI.Colors.Pink
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Text = props.text
	button.TextColor3 = props.textColor or UI.Colors.White
	button.Font = UI.Font
	button.TextSize = props.textSize or 18
	button.TextWrapped = true
	button.ZIndex = props.zindex or 1
	UI.corner(button, props.radius)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(UI.TweenSeconds), { Scale = 0.93 }):Play()
	end)
	local function release()
		TweenService:Create(scale, TweenInfo.new(UI.TweenSeconds), { Scale = 1 }):Play()
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	button.Parent = props.parent
	return button
end

-- หัวการ์ดสีม่วง: ข้อความหลักตัวใหญ่ + ภาษารองตัวเล็กในวงเล็บ
function UI.header(parent: Instance, height: number, icon: string): (Frame, TextLabel, TextLabel)
	local bar = UI.frame({ name = "Header", parent = parent, size = UDim2.new(1, 0, 0, height), color = UI.Colors.Purple, radius = 14 })
	UI.label({ name = "Icon", parent = bar, text = icon, size = UDim2.fromOffset(height, height), textSize = math.floor(height * 0.6), alignX = Enum.TextXAlignment.Center })
	local title = UI.label({
		name = "Title",
		parent = bar,
		text = "",
		size = UDim2.new(1, -height - 8, 0.6, 0),
		position = UDim2.fromOffset(height, 2),
		textSize = math.floor(height * 0.42),
		color = UI.Colors.White,
	})
	local subtitle = UI.label({
		name = "Subtitle",
		parent = bar,
		text = "",
		size = UDim2.new(1, -height - 8, 0.4, -2),
		position = UDim2.new(0, height, 0.6, -2),
		textSize = math.floor(height * 0.28),
		color = UI.Colors.PinkLight,
		font = UI.FontBody,
	})
	return bar, title, subtitle
end

function UI.screenGui(name: string, displayOrder: number): ScreenGui
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = displayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local function rescale()
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return
		end
		local viewport = camera.ViewportSize
		local value = math.min(viewport.X / UI.BaseResolution.X, viewport.Y / UI.BaseResolution.Y)
		scale.Scale = math.clamp(value, UI.MinScale, UI.MaxScale)
	end
	rescale()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end
	gui.Parent = playerGui
	return gui
end

function UI.clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function UI.formatNumber(value: number): string
	local text = tostring(math.floor(value))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	if string.sub(formatted, 1, 1) == "," then
		formatted = string.sub(formatted, 2)
	end
	return formatted
end

return UI
