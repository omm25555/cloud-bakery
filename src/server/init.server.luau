--!strict
-- Server bootstrap: โหลดทุก Service ใน Services/ แล้วเรียก Start

local Services = script:WaitForChild("Services")

type Service = {
	Start: (() -> ())?,
}

local started = 0
for _, child in Services:GetChildren() do
	if not child:IsA("ModuleScript") then
		continue
	end
	local ok, result = pcall(require, child)
	if not ok then
		warn(`[Server] โหลด {child.Name} ไม่สำเร็จ: {result}`)
		continue
	end
	local service = result :: Service
	local startFn = service.Start
	if startFn then
		local startOk, startErr = pcall(startFn)
		if not startOk then
			warn(`[Server] {child.Name}.Start ล้มเหลว: {startErr}`)
			continue
		end
	end
	started += 1
end

print(`[Server] Bootstrap ทำงานแล้ว (Services ที่เริ่ม: {started})`)
