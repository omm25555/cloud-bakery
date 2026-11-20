--!strict
-- Client bootstrap: loads every ModuleScript in Controllers, calls Init() on all,
-- then Start() on all. Controllers are optional to define either function.

type Controller = {
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
}

local controllersFolder = script:WaitForChild("Controllers")

local controllers: { [string]: Controller } = {}
for _, child in controllersFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		controllers[child.Name] = (require :: any)(child) :: Controller
	end
end

for name, controller in controllers do
	if controller.Init then
		local ok, err = pcall(controller.Init, controller)
		if not ok then
			warn(`[Client] {name}:Init failed: {err}`)
		end
	end
end

for name, controller in controllers do
	if controller.Start then
		task.spawn(function()
			local ok, err = pcall(controller.Start, controller)
			if not ok then
				warn(`[Client] {name}:Start failed: {err}`)
			end
		end)
	end
end

local count = 0
for _ in controllers do
	count += 1
end
print(`[Client] Cloud Bakery bootstrap complete ({count} controllers)`)
