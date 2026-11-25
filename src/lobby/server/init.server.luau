--!strict
-- Lobby server bootstrap: โหลดทุก Service ใน Services/ แล้วเรียก Start (สำเนาของ bootstrap เกาะ ไม่แก้ไฟล์เกาะ)

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
		warn(`[LobbyServer] โหลด {child.Name} ไม่สำเร็จ: {result}`)
		continue
	end
	local service = result :: Service
	local startFn = service.Start
	if startFn then
		local startOk, startErr = pcall(function()
			startFn()
		end)
		if not startOk then
			warn(`[LobbyServer] {child.Name}.Start ล้มเหลว: {startErr}`)
			continue
		end
	end
	started += 1
end

print(`[LobbyServer] Bootstrap ทำงานแล้ว (Services ที่เริ่ม: {started})`)
