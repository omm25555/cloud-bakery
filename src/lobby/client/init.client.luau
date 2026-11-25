--!strict
-- Lobby client bootstrap: โหลดทุก Controller ใน Controllers/ แล้วเรียก Start (สำเนาของ bootstrap เกาะ ไม่แก้ไฟล์เกาะ)

local Controllers = script:WaitForChild("Controllers")

type Controller = {
	Start: (() -> ())?,
}

local started = 0
for _, child in Controllers:GetChildren() do
	if not child:IsA("ModuleScript") then
		continue
	end
	local ok, result = pcall(require, child)
	if not ok then
		warn(`[LobbyClient] โหลด {child.Name} ไม่สำเร็จ: {result}`)
		continue
	end
	local controller = result :: Controller
	local startFn = controller.Start
	if startFn then
		local startOk, startErr = pcall(function()
			startFn()
		end)
		if not startOk then
			warn(`[LobbyClient] {child.Name}.Start ล้มเหลว: {startErr}`)
			continue
		end
	end
	started += 1
end

print(`[LobbyClient] Bootstrap ทำงานแล้ว (Controllers ที่เริ่ม: {started})`)
