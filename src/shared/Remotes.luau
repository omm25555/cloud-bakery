--!strict
-- จุดรวมสร้าง/ดึง RemoteEvent และ RemoteFunction
-- Server: Remotes.GetEvent(name) สร้างถ้ายังไม่มี
-- Client: Remotes.GetEvent(name) รอจนกว่า server จะสร้าง (timeout แล้ว warn)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"
local WAIT_TIMEOUT_SECONDS = 10

local Remotes = {}

local function getFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if RunService:IsServer() then
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	local waited = ReplicatedStorage:WaitForChild(FOLDER_NAME, WAIT_TIMEOUT_SECONDS)
	assert(waited and waited:IsA("Folder"), `[Remotes] ไม่พบโฟลเดอร์ {FOLDER_NAME} (server ยังไม่ได้สร้าง?)`)
	return waited
end

local function getRemote(className: string, name: string): Instance
	local folder = getFolder()
	local found = folder:FindFirstChild(name)
	if found == nil then
		if RunService:IsServer() then
			local created = Instance.new(className)
			created.Name = name
			created.Parent = folder
			found = created
		else
			found = folder:WaitForChild(name, WAIT_TIMEOUT_SECONDS)
		end
	end
	assert(found and found.ClassName == className, `[Remotes] ไม่พบ {className} ชื่อ {name}`)
	return found
end

function Remotes.GetEvent(name: string): RemoteEvent
	local remote = getRemote("RemoteEvent", name)
	assert(remote:IsA("RemoteEvent"), `[Remotes] {name} ไม่ใช่ RemoteEvent`)
	return remote
end

function Remotes.GetFunction(name: string): RemoteFunction
	local remote = getRemote("RemoteFunction", name)
	assert(remote:IsA("RemoteFunction"), `[Remotes] {name} ไม่ใช่ RemoteFunction`)
	return remote
end

return Remotes
