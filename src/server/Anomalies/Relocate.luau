--!strict
-- Relocate: ที่นั่งหนึ่งช่องขยับไปอยู่ผิดตำแหน่งเล็กน้อย (หมวด shop)
-- คืนสภาพโดย AnomalyService ผ่าน context.SetCFrame ที่จำ CFrame เดิมไว้

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnomalyRules = require(ReplicatedStorage.Shared.AnomalyRules)

local Relocate: AnomalyRules.Behavior = {
	Spawn = function(context: AnomalyRules.Context): (AnomalyRules.Handle?, string?)
		local target = context.Target
		if not target:IsA("BasePart") then
			return nil, `เป้าหมาย {target.Name} ไม่ใช่ BasePart`
		end
		local offset = context.Entry.Params.OffsetStuds
		if offset == nil then
			return nil, "Params.OffsetStuds หายไปจาก config"
		end
		context.SetCFrame(target, target.CFrame + offset)
		return { Description = `{target.Name} ขยับไป {tostring(offset)} studs` }, nil
	end,
}

return Relocate
