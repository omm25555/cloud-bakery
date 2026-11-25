--!strict
-- ColorShift: ชิ้นส่วนหนึ่งของร้านเปลี่ยนเป็นสีสดผิดปกติ (หมวด shop)
-- คืนสภาพโดย AnomalyService ผ่าน context.SetColor ที่จำสีเดิมไว้

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnomalyRules = require(ReplicatedStorage.Shared.AnomalyRules)

local ColorShift: AnomalyRules.Behavior = {
	Spawn = function(context: AnomalyRules.Context): (AnomalyRules.Handle?, string?)
		local target = context.Target
		if not target:IsA("BasePart") then
			return nil, `เป้าหมาย {target.Name} ไม่ใช่ BasePart`
		end
		local color = context.Entry.Params.Color
		if color == nil then
			return nil, "Params.Color หายไปจาก config"
		end
		context.SetColor(target, color)
		return { Description = `{target.Name} เปลี่ยนสีเป็น {tostring(color)}` }, nil
	end,
}

return ColorShift
