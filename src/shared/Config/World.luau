--!strict
-- ตำแหน่งสถานีบนเกาะ (studs) ผิวเกาะอยู่ที่ Y = 0
-- ขนาดของของตกแต่งอยู่ใน WorldService (เป็นงานภาพล้วน ไม่มีผลกับ gameplay)

local World = {
	IslandRadius = 78,
	SpawnPosition = Vector3.new(-30, 1, 52),

	Bakery = Vector3.new(0, 0, -34),
	MixingTable = Vector3.new(-14, 0, -2),
	Oven = Vector3.new(10, 0, -10),
	OrderCounter = Vector3.new(34, 0, 4),
	ServingTable = Vector3.new(10, 0, 24),
	CowPen = Vector3.new(-50, 0, 10),
	Dock = Vector3.new(-38, 0, 58),

	WheatPlots = {
		Vector3.new(-62, 0, -40),
		Vector3.new(-52, 0, -40),
		Vector3.new(-42, 0, -40),
		Vector3.new(-62, 0, -30),
		Vector3.new(-52, 0, -30),
		Vector3.new(-42, 0, -30),
	},
	StrawberryBushes = {
		Vector3.new(-64, 0, -16),
		Vector3.new(-56, 0, -16),
		Vector3.new(-48, 0, -16),
		Vector3.new(-40, 0, -16),
	},
	CowSpots = {
		Vector3.new(-54, 0, 10),
		Vector3.new(-44, 0, 12),
	},

	-- ที่นั่งลูกค้ารอบโต๊ะเสิร์ฟ (สัมพัทธ์กับ ServingTable)
	SeatOffsets = {
		Vector3.new(-7, 0, 0),
		Vector3.new(7, 0, 0),
		Vector3.new(0, 0, 7),
	},
	-- ทางเดินลูกค้า: จากปลายท่าบอลลูนเข้ามาที่โต๊ะ
	CustomerPath = {
		Vector3.new(-46, 0, 70),
		Vector3.new(-32, 0, 46),
		Vector3.new(-6, 0, 34),
	},
}

return World
