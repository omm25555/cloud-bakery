--!strict
-- Single place that creates (server) and fetches (client) RemoteEvents and
-- RemoteFunctions. Add a name to EVENTS or FUNCTIONS, then use
-- Remotes.event("Name") / Remotes.func("Name") on either side.
--
-- Remotes carry REQUESTS from the client only. The server validates every
-- request and decides the outcome (see CLAUDE.md).

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOLDER_NAME = "Remotes"
local WAIT_TIMEOUT = 10

-- Names are added by later tasks, e.g. "RequestHarvest", "GetPlayerData".
local EVENTS: { string } = {}
local FUNCTIONS: { string } = {}

local Remotes = {}

local function getFolder(): Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing and existing:IsA("Folder") then
			return existing
		end
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, WAIT_TIMEOUT)
	assert(folder and folder:IsA("Folder"), "[Remotes] Remotes folder not found")
	return folder
end

local function getOrCreate(name: string, className: "RemoteEvent" | "RemoteFunction"): Instance
	local folder = getFolder()
	local existing = folder:FindFirstChild(name)
	if existing then
		assert(existing.ClassName == className, `[Remotes] {name} is not a {className}`)
		return existing
	end
	assert(RunService:IsServer(), `[Remotes] {name} not created yet; client cannot create remotes`)
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = folder
	return remote
end

-- Server only: create every declared remote up front.
function Remotes.init()
	assert(RunService:IsServer(), "[Remotes] init() is server-only")
	for _, name in EVENTS do
		getOrCreate(name, "RemoteEvent")
	end
	for _, name in FUNCTIONS do
		getOrCreate(name, "RemoteFunction")
	end
end

function Remotes.event(name: string): RemoteEvent
	if RunService:IsServer() then
		return getOrCreate(name, "RemoteEvent") :: RemoteEvent
	end
	local remote = getFolder():WaitForChild(name, WAIT_TIMEOUT)
	assert(remote and remote:IsA("RemoteEvent"), `[Remotes] RemoteEvent {name} not found`)
	return remote
end

function Remotes.func(name: string): RemoteFunction
	if RunService:IsServer() then
		return getOrCreate(name, "RemoteFunction") :: RemoteFunction
	end
	local remote = getFolder():WaitForChild(name, WAIT_TIMEOUT)
	assert(remote and remote:IsA("RemoteFunction"), `[Remotes] RemoteFunction {name} not found`)
	return remote
end

return Remotes
