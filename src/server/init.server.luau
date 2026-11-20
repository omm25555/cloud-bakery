--!strict
-- Server bootstrap: loads every ModuleScript in Services, calls Init() on all,
-- then Start() on all. Services are optional to define either function.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

type Service = {
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
}

local servicesFolder = script:WaitForChild("Services")

-- Server owns remote creation; clients only wait for them.
Remotes.init()

local services: { [string]: Service } = {}
for _, child in servicesFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		services[child.Name] = (require :: any)(child) :: Service
	end
end

for name, service in services do
	if service.Init then
		local ok, err = pcall(service.Init, service)
		if not ok then
			warn(`[Server] {name}:Init failed: {err}`)
		end
	end
end

for name, service in services do
	if service.Start then
		task.spawn(function()
			local ok, err = pcall(service.Start, service)
			if not ok then
				warn(`[Server] {name}:Start failed: {err}`)
			end
		end)
	end
end

local count = 0
for _ in services do
	count += 1
end
print(`[Server] Cloud Bakery bootstrap complete ({count} services)`)
