--!strict
-- ManagerController: ท่าทางของผู้จัดการร้าน (ชม / หลอนระดับ 1-3+) + bubble บทพูด + ข้อความ ProximityPrompt ตามภาษา
-- server ตั้ง attributes บนโมเดลผู้จัดการ (Config/Report.Reaction*) ทุก client เล่นท่าเดียวกันจาก attribute
-- bubble บทพูดขึ้นเฉพาะผู้รายงาน (จาก ReportResult) ไม่มีแสงวาบ/เสียง/ไล่ตาม/ความเสียหาย และกลับเป็นปกติเองเมื่อจบท่า
-- client ไม่ตัดสินอะไร: แค่แสดงผลสิ่งที่ server สั่ง

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClientLanguage = require(ReplicatedStorage.Shared.ClientLanguage)
local Report = require(ReplicatedStorage.Shared.Config.Report)
local Strings = require(ReplicatedStorage.Shared.Config.Strings)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LOG = "[ManagerController]"

type Rig = {
	Model: Model,
	Body: BasePart,
	Head: BasePart,
	EyeL: BasePart,
	EyeR: BasePart,
	Mouth: BasePart,
	Hat: BasePart,
	BaseBody: CFrame,
	BaseHead: CFrame,
	RelEyeL: CFrame,
	RelEyeR: CFrame,
	RelMouth: CFrame,
	RelHat: CFrame,
	EyeSize: Vector3,
	MouthSize: Vector3,
	Prompt: ProximityPrompt?,
}

type Pose = {
	Hop: number,
	Yaw: number,
	Tilt: number,
	Shake: number,
	MouthX: number,
	MouthY: number,
	EyeX: number,
	EyeY: number,
}

local ManagerController = {}

local connections: { RBXScriptConnection } = {}
local rig: Rig? = nil
local animation: RBXScriptConnection? = nil
local bubble: BillboardGui? = nil
local bubbleToken = 0
local lastSeq = 0

local function smooth(value: number): number
	local x = math.clamp(value, 0, 1)
	return x * x * (3 - 2 * x)
end

local function findPart(model: Model, name: string): BasePart?
	local child = model:FindFirstChild(name)
	if child ~= nil and child:IsA("BasePart") then
		return child
	end
	return nil
end

local function buildRig(model: Model): Rig?
	local body = findPart(model, "Body")
	local head = findPart(model, "Head")
	local eyeL = findPart(model, "EyeL")
	local eyeR = findPart(model, "EyeR")
	local mouth = findPart(model, "Mouth")
	local hat = findPart(model, "Hat")
	if body == nil or head == nil or eyeL == nil or eyeR == nil or mouth == nil or hat == nil then
		warn(`{LOG} โมเดล {model.Name} ไม่ครบชิ้นส่วน (Body/Head/EyeL/EyeR/Mouth/Hat) ไม่เล่นท่าทาง`)
		return nil
	end
	local prompt = body:FindFirstChild(Report.ManagerPromptName)
	return {
		Model = model,
		Body = body,
		Head = head,
		EyeL = eyeL,
		EyeR = eyeR,
		Mouth = mouth,
		Hat = hat,
		BaseBody = body.CFrame,
		BaseHead = head.CFrame,
		RelEyeL = head.CFrame:ToObjectSpace(eyeL.CFrame),
		RelEyeR = head.CFrame:ToObjectSpace(eyeR.CFrame),
		RelMouth = head.CFrame:ToObjectSpace(mouth.CFrame),
		RelHat = head.CFrame:ToObjectSpace(hat.CFrame),
		EyeSize = eyeL.Size,
		MouthSize = mouth.Size,
		Prompt = if prompt ~= nil and prompt:IsA("ProximityPrompt") then prompt else nil,
	}
end

local function applyPose(target: Rig, pose: Pose)
	local offset = CFrame.new(0, pose.Hop, 0)
	target.Body.CFrame = offset * target.BaseBody
	local headCFrame = offset
		* target.BaseHead
		* CFrame.new(pose.Shake, 0, 0)
		* CFrame.Angles(0, pose.Yaw, 0)
		* CFrame.Angles(0, 0, pose.Tilt)
	target.Head.CFrame = headCFrame
	target.EyeL.CFrame = headCFrame * target.RelEyeL
	target.EyeR.CFrame = headCFrame * target.RelEyeR
	target.Mouth.CFrame = headCFrame * target.RelMouth
	target.Hat.CFrame = headCFrame * target.RelHat
	local eyeSize = target.EyeSize * Vector3.new(pose.EyeX, pose.EyeY, pose.EyeX)
	target.EyeL.Size = eyeSize
	target.EyeR.Size = eyeSize
	target.Mouth.Size = target.MouthSize * Vector3.new(pose.MouthX, pose.MouthY, 1)
end

local NEUTRAL: Pose = { Hop = 0, Yaw = 0, Tilt = 0, Shake = 0, MouthX = 1, MouthY = 1, EyeX = 1, EyeY = 1 }

local function stopAnimation()
	local connection = animation
	animation = nil
	if connection ~= nil then
		connection:Disconnect()
	end
	local current = rig
	if current ~= nil and current.Model.Parent ~= nil then
		applyPose(current, NEUTRAL)
	end
end

local function playPraise(target: Rig)
	local started = os.clock()
	animation = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - started
		if elapsed >= Report.PraiseHopSeconds then
			stopAnimation()
			return
		end
		local fade = 1 - smooth((elapsed - (Report.PraiseHopSeconds - Report.ReturnSeconds)) / Report.ReturnSeconds)
		local hop = math.abs(math.sin(math.pi * Report.PraiseHops * elapsed / Report.PraiseHopSeconds)) * Report.PraiseHopStuds
		applyPose(target, {
			Hop = hop,
			Yaw = 0,
			Tilt = 0,
			Shake = 0,
			MouthX = 1 + (Report.PraiseMouthScaleX - 1) * fade,
			MouthY = 1,
			EyeX = 1,
			EyeY = 1 + (Report.PraiseEyeScaleY - 1) * fade,
		})
	end)
end

local function playHaunt(target: Rig, level: number, userId: number)
	local styles = Report.HauntStyles
	local style = styles[math.clamp(level, 1, #styles)]
	if style == nil then
		warn(`{LOG} Config/Report.HauntStyles ว่าง ไม่เล่นท่าหลอน`)
		return
	end
	local maxYaw = math.rad(style.MaxYawDegrees)
	local tilt = math.rad(style.TiltDegrees)
	local started = os.clock()
	animation = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - started
		if elapsed >= style.Seconds then
			stopAnimation()
			return
		end
		local fade = 1 - smooth((elapsed - (style.Seconds - Report.ReturnSeconds)) / Report.ReturnSeconds)
		local turn = smooth(elapsed / style.TurnSeconds) * fade
		local yaw = 0
		local watched = Players:GetPlayerByUserId(userId)
		local character = if watched ~= nil then watched.Character else nil
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if root ~= nil and root:IsA("BasePart") then
			local localPosition = target.BaseHead:PointToObjectSpace(root.Position)
			yaw = math.clamp(math.atan2(-localPosition.X, -localPosition.Z), -maxYaw, maxYaw)
		end
		applyPose(target, {
			Hop = 0,
			Yaw = yaw * turn,
			Tilt = tilt * turn,
			Shake = math.sin(elapsed * 40) * style.ShakeStuds * turn,
			MouthX = 1 + (style.MouthScaleX - 1) * turn,
			MouthY = 1 + (style.MouthScaleY - 1) * turn,
			EyeX = 1 + (style.EyeScale - 1) * turn,
			EyeY = 1 + (style.EyeScale - 1) * turn,
		})
	end)
end

local function onReaction()
	local current = rig
	if current == nil then
		return
	end
	local seq = current.Model:GetAttribute(Report.ReactionSeqAttribute)
	if type(seq) ~= "number" or seq == lastSeq then
		return
	end
	lastSeq = seq
	local kind = current.Model:GetAttribute(Report.ReactionKindAttribute)
	local level = current.Model:GetAttribute(Report.ReactionLevelAttribute)
	local userId = current.Model:GetAttribute(Report.ReactionUserIdAttribute)
	stopAnimation()
	if kind == "Praise" then
		playPraise(current)
	elseif kind == "Haunt" and type(level) == "number" and type(userId) == "number" then
		playHaunt(current, level, userId)
	else
		warn(`{LOG} attribute ท่าทางไม่ถูกต้อง (kind {tostring(kind)}) ข้าม`)
	end
end

local function showBubble(line: string)
	local current = rig
	if current == nil then
		return
	end
	if bubble ~= nil then
		bubble:Destroy()
		bubble = nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "ManagerBubble"
	gui.Adornee = current.Head
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(Report.BubbleWidthPixels, Report.BubbleHeightPixels)
	gui.StudsOffset = Vector3.new(0, Report.BubbleOffsetStuds, 0)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Report.BubbleBackgroundColor
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Report.BubbleCornerRadiusPixels)
	corner.Parent = frame
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Report.Font
	label.TextColor3 = Report.BubbleTextColor
	label.TextSize = Report.BubbleTextSize
	label.TextWrapped = true
	label.Text = line
	label.Parent = frame
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	bubble = gui
	bubbleToken += 1
	local token = bubbleToken
	task.delay(Report.BubbleSeconds, function()
		if bubbleToken == token and bubble == gui then
			gui:Destroy()
			bubble = nil
		end
	end)
end

local function onResult(payload: unknown)
	if type(payload) ~= "table" then
		warn(`{LOG} ReportResult payload ไม่ถูกต้อง ข้าม`)
		return
	end
	local line = (payload :: { [string]: unknown }).Line
	if type(line) ~= "string" or #line == 0 then
		warn(`{LOG} ReportResult ไม่มีบทพูด ข้าม`)
		return
	end
	showBubble(line)
end

local function refreshPrompt(language: string)
	local current = rig
	if current == nil or current.Prompt == nil then
		return
	end
	current.Prompt.ActionText = Strings.Format("ReportPromptAction", language, nil)
	current.Prompt.ObjectText = Strings.Format("ReportPromptObject", language, nil)
end

local function attach(model: Model)
	local built = buildRig(model)
	if built == nil then
		return
	end
	rig = built
	lastSeq = 0
	local seq = model:GetAttribute(Report.ReactionSeqAttribute)
	if type(seq) == "number" then
		lastSeq = seq
	end
	table.insert(connections, model:GetAttributeChangedSignal(Report.ReactionSeqAttribute):Connect(onReaction))
	refreshPrompt(ClientLanguage.Get())
end

local function cleanup()
	stopAnimation()
	if bubble ~= nil then
		bubble:Destroy()
		bubble = nil
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

function ManagerController.Start()
	local player = Players.LocalPlayer
	table.insert(connections, Remotes.GetEvent("ReportResult").OnClientEvent:Connect(onResult))
	ClientLanguage.OnChanged(refreshPrompt)

	local existing = Workspace:FindFirstChild(Report.ManagerModelName)
	if existing ~= nil and existing:IsA("Model") then
		attach(existing)
	else
		table.insert(
			connections,
			Workspace.ChildAdded:Connect(function(child: Instance)
				if child.Name == Report.ManagerModelName and child:IsA("Model") and rig == nil then
					attach(child)
				end
			end)
		)
	end
	table.insert(
		connections,
		player.AncestryChanged:Connect(function()
			if player.Parent == nil then
				cleanup()
			end
		end)
	)
end

return ManagerController
