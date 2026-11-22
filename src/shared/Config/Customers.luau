--!strict
-- ลูกค้า NPC (ServeService / ServeController) โมเดลเป็นบล็อกง่าย ๆ ยังไม่มี asset

export type CustomerConfig = {
	Id: string,
	DisplayNameTh: string,
	DisplayNameEn: string,
	Color: Color3,
	BodySize: Vector3,
}

local Customers: { [string]: CustomerConfig } = {
	Panda = {
		Id = "Panda",
		DisplayNameTh = "แพนด้า",
		DisplayNameEn = "Panda",
		Color = Color3.fromRGB(235, 235, 235),
		BodySize = Vector3.new(3, 4, 3),
	},
	Fox = {
		Id = "Fox",
		DisplayNameTh = "สุนัขจิ้งจอก",
		DisplayNameEn = "Fox",
		Color = Color3.fromRGB(240, 140, 60),
		BodySize = Vector3.new(2.6, 4, 2.6),
	},
	Bunny = {
		Id = "Bunny",
		DisplayNameTh = "กระต่าย",
		DisplayNameEn = "Bunny",
		Color = Color3.fromRGB(250, 205, 220),
		BodySize = Vector3.new(2.4, 4.4, 2.4),
	},
}

return {
	Customers = Customers,
	-- ลำดับลูกค้าที่ server สุ่มเลือก
	Order = { "Panda", "Fox", "Bunny" } :: { string },
}
