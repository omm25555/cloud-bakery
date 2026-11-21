--!strict
-- สร้างเกาะลอยฟ้าจากโค้ด (ทุกอย่างอยู่ใน repo ตามกฎ) และเปิดจุดยึดสถานีให้ Service อื่นใช้
-- ตำแหน่งสถานีมาจาก Config/World ส่วนขนาด/สีของของตกแต่งอยู่ในไฟล์นี้ (งานภาพล้วน)

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local World = require(Shared.Config.World)

local WorldService = {}

-- สีหลักตาม concept (pastel)
local COLORS = {
	Grass = Color3.fromRGB(150, 214, 122),
	GrassDark = Color3.fromRGB(118, 186, 98),
	Rock = Color3.fromRGB(184, 140, 128),
	RockDark = Color3.fromRGB(150, 112, 104),
	Path = Color3.fromRGB(240, 226, 210),
	Cream = Color3.fromRGB(255, 244, 228),
	Pink = Color3.fromRGB(255, 164, 196),
	PinkLight = Color3.fromRGB(255, 214, 228),
	White = Color3.fromRGB(255, 255, 255),
	Wood = Color3.fromRGB(196, 140, 96),
	WoodLight = Color3.fromRGB(226, 186, 140),
	WoodDark = Color3.fromRGB(150, 100, 70),
	Brick = Color3.fromRGB(222, 160, 128),
	Lavender = Color3.fromRGB(196, 170, 236),
	Sky = Color3.fromRGB(170, 220, 255),
	Water = Color3.fromRGB(150, 220, 255),
	Gold = Color3.fromRGB(255, 214, 90),
	Fire = Color3.fromRGB(255, 150, 60),
	Black = Color3.fromRGB(40, 36, 44),
	Glass = Color3.fromRGB(220, 240, 255),
	FlowerColors = {
		Color3.fromRGB(255, 170, 210),
		Color3.fromRGB(214, 170, 255),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(255, 220, 120),
	},
}

type PartSpec = {
	name: string?,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?,
	transparency: number?,
	collide: boolean?,
	parent: Instance,
}

export type Stations = {
	root: Folder,
	mixingTable: BasePart,
	oven: BasePart,
	orderCounter: BasePart,
	servingTable: BasePart,
	wheatPlots: { BasePart },
	strawberryBushes: { BasePart },
	cows: { BasePart },
	seats: { CFrame },
	customerPath: { Vector3 },
	dockEnd: Vector3,
}

local built: Stations? = nil

local function part(spec: PartSpec): Part
	local p = Instance.new("Part")
	p.Name = spec.name or "Part"
	p.Anchored = true
	p.Size = spec.size
	p.CFrame = spec.cframe
	p.Color = spec.color
	p.Material = spec.material or Enum.Material.SmoothPlastic
	p.Shape = spec.shape or Enum.PartType.Block
	p.Transparency = spec.transparency or 0
	p.CanCollide = if spec.collide == nil then true else spec.collide
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = spec.parent
	return p
end

local function wedge(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.Size = size
	w.CFrame = cframe
	w.Color = color
	w.Material = Enum.Material.SmoothPlastic
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Parent = parent
	return w
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Cylinder ของ Roblox วางตามแกน X จึงหมุนให้ตั้งขึ้น
local function upright(position: Vector3): CFrame
	return CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
end

local function cylinder(name: string, radius: number, height: number, position: Vector3, color: Color3, material: Enum.Material, parent: Instance, collide: boolean?): Part
	return part({
		name = name,
		size = Vector3.new(height, radius * 2, radius * 2),
		cframe = upright(position),
		color = color,
		material = material,
		shape = Enum.PartType.Cylinder,
		collide = collide,
		parent = parent,
	})
end

local function ball(name: string, diameter: number, position: Vector3, color: Color3, parent: Instance, material: Enum.Material?, transparency: number?): Part
	return part({
		name = name,
		size = Vector3.new(diameter, diameter, diameter),
		cframe = CFrame.new(position),
		color = color,
		material = material,
		shape = Enum.PartType.Ball,
		transparency = transparency,
		collide = false,
		parent = parent,
	})
end

local function signText(parent: BasePart, face: Enum.NormalId, text: string, textColor: Color3, background: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = background
	label.TextColor3 = textColor
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.Parent = gui
end

local function addLight(parent: BasePart, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Parent = parent
end

-- ส่วนประกอบเกาะ -------------------------------------------------------

local function buildIsland(root: Folder)
	local island = folder("Island", root)
	local r = World.IslandRadius
	cylinder("Grass", r, 4, Vector3.new(0, -2, 0), COLORS.Grass, Enum.Material.Grass, island)
	cylinder("Rim", r + 1, 6, Vector3.new(0, -6, 0), COLORS.Rock, Enum.Material.Rock, island)
	local layers = { { 0.85, 14 }, { 0.62, 26 }, { 0.4, 38 }, { 0.2, 48 } }
	for index, layer in layers do
		local color = if index % 2 == 0 then COLORS.RockDark else COLORS.Rock
		cylinder("Rock", r * layer[1], 12, Vector3.new(0, -layer[2], 0), color, Enum.Material.Rock, island, false)
	end
	-- ทุ่งหญ้าสีเข้มเป็นหย่อม
	local rng = Random.new(7)
	for _ = 1, 14 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(10, r - 14)
		cylinder("GrassPatch", rng:NextNumber(5, 9), 0.2, Vector3.new(math.cos(angle) * dist, 0.05, math.sin(angle) * dist), COLORS.GrassDark, Enum.Material.Grass, island, false)
	end
	-- กำแพงล่องหนกันตกเกาะ (เว้นช่องท่าบอลลูน)
	local walls = folder("EdgeWalls", island)
	local dockAngle = math.atan2(World.Dock.Z, World.Dock.X)
	local segments = 40
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local diff = math.abs(math.atan2(math.sin(angle - dockAngle), math.cos(angle - dockAngle)))
		if diff > 0.16 then
			local pos = Vector3.new(math.cos(angle) * (r - 1), 6, math.sin(angle) * (r - 1))
			local wall = part({
				name = "Wall",
				size = Vector3.new(1, 14, (2 * math.pi * r) / segments + 1),
				cframe = CFrame.lookAt(pos, Vector3.new(0, 6, 0)) * CFrame.Angles(0, math.rad(90), 0),
				color = COLORS.White,
				transparency = 1,
				parent = walls,
			})
			wall.CastShadow = false
		end
	end
end

local function buildPaths(root: Folder)
	local paths = folder("Paths", root)
	local points = {
		World.Dock,
		World.CustomerPath[2],
		World.CustomerPath[3],
		World.ServingTable,
		Vector3.new(0, 0, 4),
		World.Bakery + Vector3.new(0, 0, 12),
	}
	for i = 1, #points - 1 do
		local a = points[i] * Vector3.new(1, 0, 1)
		local b = points[i + 1] * Vector3.new(1, 0, 1)
		local mid = (a + b) / 2
		local length = (b - a).Magnitude
		if length > 0 then
			part({
				name = "Path",
				size = Vector3.new(9, 0.3, length + 9),
				cframe = CFrame.lookAt(mid + Vector3.new(0, 0.1, 0), b + Vector3.new(0, 0.1, 0)),
				color = COLORS.Path,
				material = Enum.Material.Pebble,
				parent = paths,
			})
		end
	end
	-- ลานกลาง
	cylinder("Plaza", 22, 0.3, Vector3.new(0, 0.12, 6), COLORS.Path, Enum.Material.Pebble, paths)
end

local function buildBakery(root: Folder)
	local model = folder("CloudBakery", root)
	local base = World.Bakery
	part({ name = "Walls", size = Vector3.new(34, 16, 18), cframe = CFrame.new(base + Vector3.new(0, 8, 0)), color = COLORS.Cream, parent = model })
	part({ name = "Trim", size = Vector3.new(35, 1, 19), cframe = CFrame.new(base + Vector3.new(0, 16, 0)), color = COLORS.PinkLight, parent = model })
	-- หลังคาจั่วสีชมพู
	local roofHeight = 9
	wedge("RoofFront", Vector3.new(38, roofHeight, 11), CFrame.new(base + Vector3.new(0, 16 + roofHeight / 2, 5.5)), COLORS.Pink, model)
	wedge("RoofBack", Vector3.new(38, roofHeight, 11), CFrame.new(base + Vector3.new(0, 16 + roofHeight / 2, -5.5)) * CFrame.Angles(0, math.rad(180), 0), COLORS.Pink, model)
	-- ปล่องควันรูปหมวกเชฟ
	cylinder("Chimney", 2.2, 8, base + Vector3.new(10, 24, -3), COLORS.Brick, Enum.Material.Brick, model)
	cylinder("ChefHatBand", 2.6, 1.5, base + Vector3.new(10, 28.5, -3), COLORS.White, Enum.Material.SmoothPlastic, model)
	ball("ChefHatTop1", 5, base + Vector3.new(10, 31, -3), COLORS.White, model)
	ball("ChefHatTop2", 4, base + Vector3.new(8.4, 30.5, -3), COLORS.White, model)
	ball("ChefHatTop3", 4, base + Vector3.new(11.6, 30.5, -3), COLORS.White, model)
	-- ประตูและหน้าต่างเรืองแสงอุ่น ๆ
	local front = base.Z + 9.05
	part({ name = "Door", size = Vector3.new(6, 10, 0.4), cframe = CFrame.new(base.X, 5, front), color = COLORS.WoodDark, parent = model })
	for _, x in { -11, 11 } do
		local window = part({ name = "Window", size = Vector3.new(7, 6, 0.3), cframe = CFrame.new(base.X + x, 8, front), color = Color3.fromRGB(255, 226, 150), material = Enum.Material.Neon, parent = model })
		window.Transparency = 0.15
		part({ name = "WindowFrame", size = Vector3.new(7.8, 0.6, 0.5), cframe = CFrame.new(base.X + x, 4.8, front + 0.1), color = COLORS.White, parent = model })
	end
	-- กันสาดลายทาง
	local stripes = 10
	for i = 0, stripes - 1 do
		local color = if i % 2 == 0 then COLORS.Pink else COLORS.White
		local x = base.X - 15 + i * 3 + 1.5
		part({
			name = "Awning",
			size = Vector3.new(3, 0.4, 5),
			cframe = CFrame.new(x, 12.5, front + 2.2) * CFrame.Angles(math.rad(25), 0, 0),
			color = color,
			collide = false,
			parent = model,
		})
	end
	local sign = part({ name = "Sign", size = Vector3.new(18, 3.6, 0.6), cframe = CFrame.new(base.X, 14.2, front + 0.4), color = COLORS.PinkLight, parent = model })
	signText(sign, Enum.NormalId.Front, "Cloud Bakery · เบเกอรี่ลอยฟ้า", Color3.fromRGB(150, 80, 120), COLORS.PinkLight)
end

local function buildFence(parent: Instance, from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	local posts = math.max(2, math.floor(length / 4) + 1)
	for i = 0, posts - 1 do
		local p = from:Lerp(to, i / (posts - 1))
		part({ name = "Post", size = Vector3.new(0.6, 3, 0.6), cframe = CFrame.new(p + Vector3.new(0, 1.5, 0)), color = COLORS.White, parent = parent })
	end
	local mid = (from + to) / 2
	for _, h in { 1.2, 2.3 } do
		part({
			name = "Rail",
			size = Vector3.new(0.3, 0.3, length),
			cframe = CFrame.lookAt(mid + Vector3.new(0, h, 0), to + Vector3.new(0, h, 0)),
			color = COLORS.White,
			collide = false,
			parent = parent,
		})
	end
end

local function buildGarden(root: Folder): ({ BasePart }, { BasePart })
	local garden = folder("SkyGarden", root)
	local plots: { BasePart } = {}
	for index, pos in World.WheatPlots do
		local box = part({ name = `WheatPlot{index}`, size = Vector3.new(8, 1, 8), cframe = CFrame.new(pos + Vector3.new(0, 0.5, 0)), color = COLORS.WoodDark, material = Enum.Material.Wood, parent = garden })
		part({ name = "Soil", size = Vector3.new(7, 0.2, 7), cframe = CFrame.new(pos + Vector3.new(0, 1.05, 0)), color = Color3.fromRGB(120, 84, 62), material = Enum.Material.Ground, collide = false, parent = garden })
		table.insert(plots, box)
	end
	local bushes: { BasePart } = {}
	for index, pos in World.StrawberryBushes do
		local bush = ball(`StrawberryBush{index}`, 5, pos + Vector3.new(0, 2.2, 0), Color3.fromRGB(96, 170, 90), garden, Enum.Material.Grass)
		bush.CanCollide = true
		table.insert(bushes, bush)
	end
	-- รั้วขาวรอบสวน
	local minX, maxX, minZ, maxZ = -69, -34, -47, -10
	buildFence(garden, Vector3.new(minX, 0, minZ), Vector3.new(maxX, 0, minZ))
	buildFence(garden, Vector3.new(minX, 0, minZ), Vector3.new(minX, 0, maxZ))
	buildFence(garden, Vector3.new(maxX, 0, minZ), Vector3.new(maxX, 0, minZ + 14))
	-- ต้นไม้ผลเวทมนตร์ (ผลสีม่วงเรืองแสง)
	local treePos = Vector3.new(-30, 0, -44)
	cylinder("Trunk", 1.4, 10, treePos + Vector3.new(0, 5, 0), COLORS.WoodDark, Enum.Material.Wood, garden)
	ball("Leaves", 12, treePos + Vector3.new(0, 13, 0), Color3.fromRGB(110, 190, 100), garden, Enum.Material.Grass)
	ball("Leaves2", 8, treePos + Vector3.new(4, 11, 3), Color3.fromRGB(130, 200, 110), garden, Enum.Material.Grass)
	local rng = Random.new(11)
	for _ = 1, 7 do
		local offset = Vector3.new(rng:NextNumber(-5, 5), rng:NextNumber(-3, 4), rng:NextNumber(-5, 5)).Unit * 6
		local fruit = ball("MagicFruit", 1.4, treePos + Vector3.new(0, 13, 0) + offset, Color3.fromRGB(190, 120, 255), garden, Enum.Material.Neon)
		addLight(fruit, Color3.fromRGB(200, 140, 255), 6, 0.8)
	end
	return plots, bushes
end

local function buildCowPen(root: Folder): { BasePart }
	local pen = folder("StarMilkPen", root)
	local c = World.CowPen
	buildFence(pen, c + Vector3.new(-12, 0, -8), c + Vector3.new(12, 0, -8))
	buildFence(pen, c + Vector3.new(-12, 0, -8), c + Vector3.new(-12, 0, 10))
	buildFence(pen, c + Vector3.new(-12, 0, 10), c + Vector3.new(4, 0, 10))
	local cows: { BasePart } = {}
	for index, pos in World.CowSpots do
		local body = part({ name = `Cow{index}`, size = Vector3.new(5, 3.4, 3), cframe = CFrame.new(pos + Vector3.new(0, 2.6, 0)), color = COLORS.White, parent = pen })
		for _, offset in { Vector3.new(1, 0.6, 1.55), Vector3.new(-1.2, -0.2, -1.55), Vector3.new(0.2, 1.71, 0) } do
			part({ name = "Spot", size = Vector3.new(1.4, 1.2, 0.1), cframe = CFrame.new(body.Position + offset), color = COLORS.Black, collide = false, parent = pen })
		end
		local head = part({ name = "Head", size = Vector3.new(2, 2, 2.2), cframe = CFrame.new(pos + Vector3.new(3.2, 3.6, 0)), color = COLORS.White, collide = false, parent = pen })
		part({ name = "Nose", size = Vector3.new(0.6, 1, 1.6), cframe = CFrame.new(head.Position + Vector3.new(1.2, -0.3, 0)), color = Color3.fromRGB(255, 180, 190), collide = false, parent = pen })
		for _, z in { -0.5, 0.5 } do
			ball("Eye", 0.4, head.Position + Vector3.new(1.05, 0.4, z), COLORS.Black, pen)
		end
		for _, x in { -1.8, 1.8 } do
			for _, z in { -1, 1 } do
				part({ name = "Leg", size = Vector3.new(0.7, 1.6, 0.7), cframe = CFrame.new(pos + Vector3.new(x, 0.8, z)), color = COLORS.White, parent = pen })
			end
		end
		table.insert(cows, body)
	end
	-- ถังนมดาวเรืองแสง
	local tank = cylinder("MilkTank", 2.2, 6, c + Vector3.new(8, 3, -3), COLORS.Glass, Enum.Material.Glass, pen)
	tank.Transparency = 0.3
	local milk = cylinder("Milk", 1.9, 4, c + Vector3.new(8, 2.2, -3), Color3.fromRGB(240, 250, 255), Enum.Material.Neon, pen, false)
	addLight(milk, Color3.fromRGB(220, 240, 255), 10, 0.8)
	for i = 0, 2 do
		local bottle = cylinder("StarMilkBottle", 0.6, 1.6, c + Vector3.new(5 + i * 1.6, 0.8, 4), COLORS.White, Enum.Material.Glass, pen, false)
		bottle.Transparency = 0.1
		ball("Star", 0.5, bottle.Position + Vector3.new(0, 0.2, 0.62), COLORS.Gold, pen, Enum.Material.Neon)
	end
	return cows
end

local function buildMixingTable(root: Folder): BasePart
	local model = folder("MixingTable", root)
	local p = World.MixingTable
	local top = part({ name = "TableTop", size = Vector3.new(10, 0.8, 5), cframe = CFrame.new(p + Vector3.new(0, 3.4, 0)), color = COLORS.WoodLight, material = Enum.Material.Wood, parent = model })
	for _, x in { -4.4, 4.4 } do
		for _, z in { -2, 2 } do
			part({ name = "Leg", size = Vector3.new(0.6, 3, 0.6), cframe = CFrame.new(p + Vector3.new(x, 1.5, z)), color = COLORS.Wood, parent = model })
		end
	end
	local bowl = ball("Bowl", 2.6, p + Vector3.new(0, 4.1, 0), Color3.fromRGB(190, 225, 255), model)
	bowl.Size = Vector3.new(2.8, 1.6, 2.8)
	ball("Dough", 2, p + Vector3.new(0, 4.5, 0), COLORS.Cream, model)
	local jarColors = { Color3.fromRGB(255, 240, 200), Color3.fromRGB(255, 200, 220), Color3.fromRGB(210, 200, 255) }
	for i, color in jarColors do
		local jar = cylinder("Jar", 0.7, 1.8, p + Vector3.new(-4 + i * 1.6, 4.7, -1.5), COLORS.Glass, Enum.Material.Glass, model, false)
		jar.Transparency = 0.35
		cylinder("JarFill", 0.6, 1.1, p + Vector3.new(-4 + i * 1.6, 4.35, -1.5), color, Enum.Material.SmoothPlastic, model, false)
	end
	local sign = part({ name = "Sign", size = Vector3.new(6, 2, 0.3), cframe = CFrame.new(p + Vector3.new(0, 6.6, -2.4)), color = COLORS.WoodLight, collide = false, parent = model })
	signText(sign, Enum.NormalId.Front, "โต๊ะผสม (Mixing Table)", Color3.fromRGB(110, 70, 50), COLORS.Cream)
	return top
end

local function buildOven(root: Folder): BasePart
	local model = folder("Oven", root)
	local p = World.Oven
	part({ name = "OvenBase", size = Vector3.new(12, 3, 11), cframe = CFrame.new(p + Vector3.new(0, 1.5, 0)), color = COLORS.Brick, material = Enum.Material.Brick, parent = model })
	local dome = part({
		name = "OvenDome",
		size = Vector3.new(11, 9, 10),
		cframe = CFrame.new(p + Vector3.new(0, 5, 0)),
		color = COLORS.Brick,
		material = Enum.Material.Brick,
		shape = Enum.PartType.Ball,
		parent = model,
	})
	local fire = part({ name = "Fire", size = Vector3.new(4.5, 3, 0.4), cframe = CFrame.new(p + Vector3.new(0, 4.4, 4.9)), color = COLORS.Fire, material = Enum.Material.Neon, collide = false, parent = model })
	addLight(fire, COLORS.Fire, 16, 2)
	part({ name = "Arch", size = Vector3.new(5.6, 0.8, 0.6), cframe = CFrame.new(p + Vector3.new(0, 6.2, 5)), color = COLORS.WoodDark, collide = false, parent = model })
	cylinder("Chimney", 1, 5, p + Vector3.new(0, 11, -2), COLORS.Brick, Enum.Material.Brick, model)
	for i = 0, 3 do
		ball("Bread", 1.4, p + Vector3.new(-6.5 + i * 0.1, 3.4 + i * 0.4, 3 - i * 1.4), Color3.fromRGB(230, 170, 100), model)
	end
	local sign = part({ name = "Sign", size = Vector3.new(5, 1.6, 0.3), cframe = CFrame.new(p + Vector3.new(0, 10.4, 3.6)), color = COLORS.WoodLight, collide = false, parent = model })
	signText(sign, Enum.NormalId.Front, "เตาอบ (Oven)", Color3.fromRGB(110, 70, 50), COLORS.Cream)
	return dome
end

local function buildOrderCounter(root: Folder): BasePart
	local model = folder("OrderCounter", root)
	local p = World.OrderCounter
	local counter = part({ name = "Counter", size = Vector3.new(14, 4, 4), cframe = CFrame.new(p + Vector3.new(0, 2, 0)), color = COLORS.WoodLight, material = Enum.Material.Wood, parent = model })
	part({ name = "CounterTop", size = Vector3.new(14.6, 0.5, 4.6), cframe = CFrame.new(p + Vector3.new(0, 4.25, 0)), color = COLORS.PinkLight, parent = model })
	for _, x in { -7, 7 } do
		for _, z in { -3, 3 } do
			part({ name = "Post", size = Vector3.new(0.6, 9, 0.6), cframe = CFrame.new(p + Vector3.new(x, 4.5, z)), color = COLORS.White, parent = model })
		end
	end
	for i = 0, 6 do
		local color = if i % 2 == 0 then COLORS.Pink else COLORS.White
		part({ name = "Awning", size = Vector3.new(2.2, 0.4, 7.6), cframe = CFrame.new(p + Vector3.new(-6.6 + i * 2.2, 9.2, 0)), color = color, collide = false, parent = model })
	end
	local register = part({ name = "Register", size = Vector3.new(2.4, 1.6, 1.6), cframe = CFrame.new(p + Vector3.new(3.5, 5.3, 0)), color = COLORS.Lavender, parent = model })
	local screen = part({ name = "Screen", size = Vector3.new(2, 1.2, 0.2), cframe = CFrame.new(register.Position + Vector3.new(0, 1.2, 0.3)), color = COLORS.Sky, material = Enum.Material.Neon, collide = false, parent = model })
	screen.Transparency = 0.1
	local case = part({ name = "DisplayCase", size = Vector3.new(5, 2.4, 2.4), cframe = CFrame.new(p + Vector3.new(-3.5, 5.7, 0)), color = COLORS.Glass, material = Enum.Material.Glass, collide = false, parent = model })
	case.Transparency = 0.5
	for i = 0, 3 do
		ball("Pastry", 1, p + Vector3.new(-5 + i, 5.1, 0), Color3.fromRGB(235, 175, 100), model)
	end
	local board = part({ name = "MenuBoard", size = Vector3.new(4, 5, 0.3), cframe = CFrame.new(p + Vector3.new(9.5, 2.8, 2)) * CFrame.Angles(math.rad(-10), math.rad(-20), 0), color = Color3.fromRGB(60, 70, 64), parent = model })
	signText(board, Enum.NormalId.Front, "MENU\n🍞 🥐 🍰", COLORS.White, Color3.fromRGB(60, 70, 64))
	local sign = part({ name = "Sign", size = Vector3.new(9, 1.6, 0.3), cframe = CFrame.new(p + Vector3.new(0, 10.4, 3.9)), color = COLORS.PinkLight, collide = false, parent = model })
	signText(sign, Enum.NormalId.Front, "จุดรับออเดอร์ (Order Counter)", Color3.fromRGB(150, 80, 120), COLORS.PinkLight)
	return counter
end

local function buildServingTable(root: Folder): (BasePart, { CFrame })
	local model = folder("ServingTable", root)
	local p = World.ServingTable
	local top = part({ name = "TableTop", size = Vector3.new(10, 0.6, 6), cframe = CFrame.new(p + Vector3.new(0, 3, 0)), color = COLORS.White, parent = model })
	-- ผ้าปูลายสก็อตชมพู
	for x = 0, 4 do
		for z = 0, 2 do
			if (x + z) % 2 == 0 then
				part({ name = "Check", size = Vector3.new(2, 0.05, 2), cframe = CFrame.new(p + Vector3.new(-4 + x * 2, 3.32, -2 + z * 2)), color = COLORS.Pink, collide = false, parent = model })
			end
		end
	end
	for _, x in { -4.4, 4.4 } do
		for _, z in { -2.4, 2.4 } do
			part({ name = "Leg", size = Vector3.new(0.5, 3, 0.5), cframe = CFrame.new(p + Vector3.new(x, 1.5, z)), color = COLORS.WoodLight, parent = model })
		end
	end
	ball("Cake", 1.8, p + Vector3.new(-1.5, 3.9, 0), Color3.fromRGB(255, 225, 235), model)
	ball("Berry", 0.5, p + Vector3.new(-1.5, 4.8, 0), Color3.fromRGB(230, 60, 80), model)
	cylinder("Vase", 0.4, 1.2, p + Vector3.new(2, 3.9, 0), COLORS.Lavender, Enum.Material.SmoothPlastic, model, false)
	ball("Flower", 0.8, p + Vector3.new(2, 4.8, 0), COLORS.Pink, model)
	local seats: { CFrame } = {}
	for index, offset in World.SeatOffsets do
		local seatPos = p + offset
		cylinder(`Stool{index}`, 1.3, 1.8, seatPos + Vector3.new(0, 0.9, 0), COLORS.Wood, Enum.Material.Wood, model)
		table.insert(seats, CFrame.lookAt(seatPos + Vector3.new(0, 1.8, 0), p * Vector3.new(1, 0, 1) + Vector3.new(0, 1.8, 0)))
	end
	local sign = part({ name = "Sign", size = Vector3.new(6, 1.4, 0.3), cframe = CFrame.new(p + Vector3.new(0, 7, -3.2)), color = COLORS.Cream, collide = false, parent = model })
	signText(sign, Enum.NormalId.Front, "โต๊ะเสิร์ฟ (Serving Table)", Color3.fromRGB(150, 80, 120), COLORS.Cream)
	return top, seats
end

local function buildDock(root: Folder): Vector3
	local dock = folder("BalloonDock", root)
	local from = World.Dock * Vector3.new(1, 0, 1)
	local direction = (from * Vector3.new(1, 0, 1)).Unit
	local to = from + direction * 26
	local mid = (from + to) / 2
	local length = (to - from).Magnitude
	part({ name = "Deck", size = Vector3.new(10, 1, length), cframe = CFrame.lookAt(mid + Vector3.new(0, -0.4, 0), to + Vector3.new(0, -0.4, 0)), color = COLORS.WoodLight, material = Enum.Material.WoodPlanks, parent = dock })
	local right = direction:Cross(Vector3.yAxis)
	for i = 0, 6 do
		local along = from:Lerp(to, i / 6)
		for _, side in { -1, 1 } do
			local postPos = along + right * side * 5
			part({ name = "RopePost", size = Vector3.new(0.7, 4, 0.7), cframe = CFrame.new(postPos + Vector3.new(0, 1.6, 0)), color = COLORS.Wood, parent = dock })
			if i % 3 == 0 then
				local lamp = ball("Lantern", 1.2, postPos + Vector3.new(0, 4.2, 0), COLORS.Gold, dock, Enum.Material.Neon)
				addLight(lamp, COLORS.Gold, 10, 0.8)
			end
		end
	end
	-- กำแพงล่องหนกันตกข้างท่า
	for _, side in { -1, 1 } do
		local wall = part({ name = "DockWall", size = Vector3.new(1, 10, length), cframe = CFrame.lookAt(mid + right * side * 5.5 + Vector3.new(0, 4, 0), to + right * side * 5.5 + Vector3.new(0, 4, 0)), color = COLORS.White, transparency = 1, parent = dock })
		wall.CastShadow = false
	end
	local endWall = part({ name = "DockEndWall", size = Vector3.new(11, 10, 1), cframe = CFrame.lookAt(to + direction * 0.5 + Vector3.new(0, 4, 0), to + direction * 2 + Vector3.new(0, 4, 0)), color = COLORS.White, transparency = 1, parent = dock })
	endWall.CastShadow = false
	-- บอลลูนลายรุ้งพาสเทลหน้าเมฆยิ้ม
	local balloonPos = to + right * 12 + Vector3.new(0, 16, 0)
	local stripeColors = { COLORS.Pink, COLORS.Gold, COLORS.Sky, COLORS.Lavender }
	for i, color in stripeColors do
		local s = ball("Balloon", 16 - i * 0.01, balloonPos, color, dock)
		s.Size = Vector3.new(16 - (i - 1) * 4, 18, 16 - (4 - i) * 4)
	end
	local cloud = folder("CloudFace", dock)
	local facing = (to - balloonPos) * Vector3.new(1, 0, 1)
	local faceDir = if facing.Magnitude > 0 then facing.Unit else direction
	local faceCenter = balloonPos + faceDir * 7.6
	for _, offset in { Vector3.new(0, 0, 0), Vector3.new(2.2, 0.6, 0), Vector3.new(-2.2, 0.6, 0) } do
		ball("Cloud", 4.4, faceCenter + right * offset.X + Vector3.new(0, offset.Y, 0), COLORS.White, cloud)
	end
	for _, side in { -0.8, 0.8 } do
		ball("Eye", 0.6, faceCenter + faceDir * 2.1 + right * side + Vector3.new(0, 0.5, 0), COLORS.Black, cloud)
	end
	part({ name = "Basket", size = Vector3.new(6, 3.5, 6), cframe = CFrame.new(balloonPos + Vector3.new(0, -14, 0)), color = COLORS.Wood, material = Enum.Material.Fabric, parent = dock })
	for _, x in { -2.6, 2.6 } do
		for _, z in { -2.6, 2.6 } do
			part({ name = "Rope", size = Vector3.new(0.2, 6, 0.2), cframe = CFrame.new(balloonPos + Vector3.new(x, -9.5, z)), color = COLORS.WoodDark, collide = false, parent = dock })
		end
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = CFrame.new(World.SpawnPosition - Vector3.new(0, 0.9, 0))
	spawn.Color = COLORS.PinkLight
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Transparency = 0.2
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = dock
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	return to
end

local function buildWaterfalls(root: Folder)
	local falls = folder("Waterfalls", root)
	local r = World.IslandRadius
	for _, angleDeg in { 70, 125, 300 } do
		local angle = math.rad(angleDeg)
		local edge = Vector3.new(math.cos(angle) * (r + 1.5), 0, math.sin(angle) * (r + 1.5))
		local inward = -edge.Unit
		local water = part({
			name = "Waterfall",
			size = Vector3.new(7, 50, 1.2),
			cframe = CFrame.lookAt(edge + Vector3.new(0, -24, 0), edge + inward + Vector3.new(0, -24, 0)),
			color = COLORS.Water,
			material = Enum.Material.Neon,
			transparency = 0.35,
			collide = false,
			parent = falls,
		})
		water.CastShadow = false
		part({ name = "Stream", size = Vector3.new(6, 0.25, 16), cframe = CFrame.lookAt(edge + inward * 8 + Vector3.new(0, 0.15, 0), edge + Vector3.new(0, 0.15, 0)), color = COLORS.Water, material = Enum.Material.Glass, transparency = 0.2, collide = false, parent = falls })
		for i = 0, 4 do
			ball("Foam", 3, edge + inward * (i * 0.4) + Vector3.new(0, -50 + i * 0.3, 0) + edge.Unit:Cross(Vector3.yAxis) * (i - 2) * 1.4, COLORS.White, falls)
		end
	end
end

local function buildFlowersAndLamps(root: Folder)
	local decor = folder("Decor", root)
	local avoid = { World.Bakery, World.MixingTable, World.Oven, World.OrderCounter, World.ServingTable, World.CowPen, Vector3.new(-50, 0, -28), Vector3.new(0, 0, 6) }
	local avoidRadius = { 24, 9, 10, 12, 10, 16, 24, 22 }
	local rng = Random.new(42)
	local placed = 0
	local tries = 0
	while placed < 130 and tries < 2000 do
		tries += 1
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = math.sqrt(rng:NextNumber(0.05, 1)) * (World.IslandRadius - 4)
		local pos = Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		local ok = true
		for i, center in avoid do
			if ((pos - center) * Vector3.new(1, 0, 1)).Magnitude < avoidRadius[i] then
				ok = false
				break
			end
		end
		if ok then
			local color = COLORS.FlowerColors[rng:NextInteger(1, #COLORS.FlowerColors)]
			part({ name = "Stem", size = Vector3.new(0.2, 1, 0.2), cframe = CFrame.new(pos + Vector3.new(0, 0.5, 0)), color = COLORS.GrassDark, collide = false, parent = decor })
			ball("Flower", rng:NextNumber(0.8, 1.4), pos + Vector3.new(0, 1.1, 0), color, decor)
			placed += 1
		end
	end
	-- พุ่มดอกไม้ใหญ่ขอบเกาะ
	for i = 1, 16 do
		local angle = (i / 16) * math.pi * 2 + 0.2
		local pos = Vector3.new(math.cos(angle) * (World.IslandRadius - 3), 1.5, math.sin(angle) * (World.IslandRadius - 3))
		ball("Bush", 4, pos, COLORS.GrassDark, decor, Enum.Material.Grass)
		ball("Blossom", 1.6, pos + Vector3.new(0, 1.8, 0), COLORS.FlowerColors[(i % #COLORS.FlowerColors) + 1], decor)
	end
	-- โคมไฟริมทาง
	for _, pos in { Vector3.new(-20, 0, 38), Vector3.new(-8, 0, 20), Vector3.new(18, 0, 8), Vector3.new(-22, 0, -14), Vector3.new(22, 0, -18) } do
		part({ name = "LampPost", size = Vector3.new(0.6, 7, 0.6), cframe = CFrame.new(pos + Vector3.new(0, 3.5, 0)), color = COLORS.Black, parent = decor })
		local lamp = ball("LampLight", 1.4, pos + Vector3.new(0, 7.4, 0), COLORS.Gold, decor, Enum.Material.Neon)
		addLight(lamp, COLORS.Gold, 14, 1)
	end
end

local function buildSky(root: Folder)
	local sky = folder("Sky", root)
	local rng = Random.new(3)
	-- ทะเลเมฆด้านล่าง
	for _ = 1, 70 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(30, 260)
		local pos = Vector3.new(math.cos(angle) * dist, rng:NextNumber(-90, -55), math.sin(angle) * dist)
		local cloud = ball("Cloud", rng:NextNumber(18, 40), pos, COLORS.White, sky, Enum.Material.SmoothPlastic, 0.05)
		cloud.CastShadow = false
	end
	-- เมฆลอยรอบเกาะ
	for _ = 1, 18 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(120, 220)
		local center = Vector3.new(math.cos(angle) * dist, rng:NextNumber(-10, 40), math.sin(angle) * dist)
		for k = 0, 3 do
			local puff = ball("Cloud", rng:NextNumber(10, 18), center + Vector3.new(k * 7 - 10, rng:NextNumber(-2, 3), rng:NextNumber(-4, 4)), COLORS.White, sky, Enum.Material.SmoothPlastic, 0.1)
			puff.CastShadow = false
		end
	end
	-- เกาะปราสาทไกล ๆ
	local farIslands: { { center: Vector3, color: Color3 } } = {
		{ center = Vector3.new(-200, 30, -180), color = COLORS.PinkLight },
		{ center = Vector3.new(220, 50, -120), color = COLORS.Lavender },
		{ center = Vector3.new(180, 10, 200), color = COLORS.PinkLight },
	}
	for _, info in farIslands do
		local center = info.center
		local color = info.color
		cylinder("FarIsland", 18, 5, center, COLORS.Grass, Enum.Material.Grass, sky, false)
		cylinder("FarRock", 12, 16, center - Vector3.new(0, 10, 0), COLORS.Rock, Enum.Material.Rock, sky, false)
		for t = 0, 2 do
			local towerPos = center + Vector3.new(-8 + t * 8, 10 + (t % 2) * 4, 0)
			cylinder("Tower", 2.4, 16 + (t % 2) * 8, towerPos, color, Enum.Material.SmoothPlastic, sky, false)
			ball("Roof", 5, towerPos + Vector3.new(0, 9 + (t % 2) * 4, 0), COLORS.Lavender, sky)
		end
		local fall = part({ name = "FarWaterfall", size = Vector3.new(3, 40, 0.5), cframe = CFrame.new(center + Vector3.new(14, -22, 8)), color = COLORS.Water, material = Enum.Material.Neon, transparency = 0.4, collide = false, parent = sky })
		fall.CastShadow = false
	end
end

local function setupLighting()
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(150, 130, 160)
	Lighting.OutdoorAmbient = Color3.fromRGB(200, 180, 210)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.GlobalShadows = true
	Lighting.FogEnd = 100000

	local function ensure(className: string, name: string): Instance
		local existing = Lighting:FindFirstChild(name)
		if existing and existing.ClassName == className then
			return existing
		end
		local created = Instance.new(className)
		created.Name = name
		created.Parent = Lighting
		return created
	end

	local atmosphere = ensure("Atmosphere", "CloudBakeryAtmosphere")
	if atmosphere:IsA("Atmosphere") then
		atmosphere.Density = 0.32
		atmosphere.Offset = 0.2
		atmosphere.Color = Color3.fromRGB(255, 222, 240)
		atmosphere.Decay = Color3.fromRGB(200, 180, 255)
		atmosphere.Glare = 0.2
		atmosphere.Haze = 1.4
	end
	local color = ensure("ColorCorrectionEffect", "CloudBakeryColor")
	if color:IsA("ColorCorrectionEffect") then
		color.Saturation = 0.12
		color.Brightness = 0.03
		color.Contrast = 0.02
		color.TintColor = Color3.fromRGB(255, 246, 250)
	end
	local bloom = ensure("BloomEffect", "CloudBakeryBloom")
	if bloom:IsA("BloomEffect") then
		bloom.Intensity = 0.6
		bloom.Size = 30
		bloom.Threshold = 1.6
	end
end

-- API ----------------------------------------------------------------

function WorldService.getStations(): Stations
	local existing = built
	if existing then
		return existing
	end
	local old = Workspace:FindFirstChild("CloudBakeryWorld")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "CloudBakeryWorld"

	buildIsland(root)
	buildPaths(root)
	buildBakery(root)
	local wheatPlots, bushes = buildGarden(root)
	local cows = buildCowPen(root)
	local mixingTable = buildMixingTable(root)
	local oven = buildOven(root)
	local orderCounter = buildOrderCounter(root)
	local servingTable, seats = buildServingTable(root)
	local dockEnd = buildDock(root)
	buildWaterfalls(root)
	buildFlowersAndLamps(root)
	buildSky(root)
	setupLighting()

	root.Parent = Workspace

	local path = table.clone(World.CustomerPath)
	path[1] = dockEnd
	local stations: Stations = {
		root = root,
		mixingTable = mixingTable,
		oven = oven,
		orderCounter = orderCounter,
		servingTable = servingTable,
		wheatPlots = wheatPlots,
		strawberryBushes = bushes,
		cows = cows,
		seats = seats,
		customerPath = path,
		dockEnd = dockEnd,
	}
	built = stations
	return stations
end

-- ระยะจากตัวละครถึงสถานี (ใช้ตรวจคำขอฝั่ง server)
function WorldService.distanceTo(player: Player, target: BasePart): number
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return math.huge
	end
	return (root.Position - target.Position).Magnitude
end

function WorldService.Start()
	WorldService.getStations()
end

return WorldService
