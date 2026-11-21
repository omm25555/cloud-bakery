--!strict
-- กติกามินิเกมจังหวะที่ใช้ร่วมกัน: server ใช้ตัดสินผล, client ใช้วาดเส้นให้ตรงกับที่ server คิด

local Bake = require(script.Parent.Config.Bake)

export type Judgement = "Perfect" | "Good" | "Miss"

local BakeRhythm = {}

-- ตำแหน่งเส้น (0-1) ที่เวลา seconds นับจากเริ่มมินิเกม เส้นวิ่งไป-กลับ
function BakeRhythm.LinePosition(seconds: number): number
	local phase = (seconds * Bake.Minigame.LineSpeed) % 2
	if phase <= 1 then
		return phase
	end
	return 2 - phase
end

function BakeRhythm.Judge(position: number, zoneCenter: number): Judgement
	local distance = math.abs(position - zoneCenter)
	if distance <= Bake.Minigame.PerfectHalfWidth then
		return "Perfect"
	elseif distance <= Bake.Minigame.GoodHalfWidth then
		return "Good"
	end
	return "Miss"
end

-- ระดับรวม: ครั้งที่ไม่ได้กด (ไม่มีใน judgements) นับเป็น Miss
function BakeRhythm.Grade(judgements: { Judgement }): Judgement
	local perfect = 0
	local miss = 0
	for index = 1, Bake.Minigame.TapCount do
		local judgement = judgements[index] or "Miss"
		if judgement == "Perfect" then
			perfect += 1
		elseif judgement == "Miss" then
			miss += 1
		end
	end
	if perfect >= Bake.Minigame.PerfectGradeMinPerfectTaps then
		return "Perfect"
	elseif miss >= Bake.Minigame.MissGradeMinMissTaps then
		return "Miss"
	end
	return "Good"
end

return BakeRhythm
