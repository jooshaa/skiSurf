--!strict
-- MapProps: постройки и украшения карты из простых деталей (свой стиль, без чужих моделей).
-- Каждая функция получает CFrame точки на земле: -Z это «лицо» постройки, Y вверх.
-- Все детали закреплены и не ловят касания; мелкие украшения не мешают ходить.
local MapProps = {}

local WHITE = Color3.fromRGB(245, 248, 255)
local SNOW = Color3.fromRGB(235, 242, 252)
local DARK_WOOD = Color3.fromRGB(84, 56, 40)
local WOOD = Color3.fromRGB(130, 90, 60)
local STONE = Color3.fromRGB(120, 124, 135)
local WARM = Color3.fromRGB(255, 214, 120)
local PINE = Color3.fromRGB(38, 96, 62)
local PINE_DARK = Color3.fromRGB(28, 78, 52)

local LIGHT_COLORS = {
	Color3.fromRGB(255, 70, 70),
	Color3.fromRGB(90, 220, 110),
	Color3.fromRGB(255, 205, 70),
	Color3.fromRGB(90, 160, 255),
}

-- Цвета стен: в основном красные лапландские домики, изредка другие
local HOUSE_COLORS = {
	Color3.fromRGB(170, 44, 40),
	Color3.fromRGB(150, 36, 36),
	Color3.fromRGB(186, 58, 44),
	Color3.fromRGB(170, 44, 40),
	Color3.fromRGB(52, 98, 74),
	Color3.fromRGB(206, 160, 70),
	Color3.fromRGB(70, 104, 140),
}

export type HouseOptions = { width: number, depth: number, height: number, colorIndex: number }

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local created = Instance.new("Part")
	created.Name = name
	created.Size = size
	created.CFrame = cframe
	created.Color = color
	created.Material = material or Enum.Material.SmoothPlastic
	created.Anchored = true
	created.CanTouch = false
	created.TopSurface = Enum.SurfaceType.Smooth
	created.BottomSurface = Enum.SurfaceType.Smooth
	created.Parent = parent
	return created
end

-- Мелкое украшение: сквозь него ходят, лучи его не видят
local function decor(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local created = part(parent, name, size, cframe, color, material)
	created.CanCollide = false
	created.CanQuery = false
	created.CastShadow = false
	return created
end

-- Вертикальный цилиндр: центр на высоте y над точкой base
local function cylinder(
	parent: Instance,
	name: string,
	diameter: number,
	height: number,
	base: CFrame,
	y: number,
	color: Color3,
	material: Enum.Material?
): Part
	local created = part(
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		base * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		material
	)
	created.Shape = Enum.PartType.Cylinder
	return created
end

local function ball(
	parent: Instance,
	name: string,
	diameter: number,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local created =
		part(parent, name, Vector3.new(diameter, diameter, diameter), cframe, color, material)
	created.Shape = Enum.PartType.Ball
	return created
end

local function wedge(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): WedgePart
	local created = Instance.new("WedgePart")
	created.Name = name
	created.Size = size
	created.CFrame = cframe
	created.Color = color
	created.Material = material
	created.Anchored = true
	created.CanTouch = false
	created.TopSurface = Enum.SurfaceType.Smooth
	created.BottomSurface = Enum.SurfaceType.Smooth
	created.Parent = parent
	return created
end

local function glow(parent: Instance, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = parent
end

-- Модель собирается без родителя и ставится в мир целиком, одним событием (см. конец строителей)
local function model(name: string): Model
	local created = Instance.new("Model")
	created.Name = name
	return created
end

-- Ярус-пирамида из четырёх угловых клиньев: side это сторона основания, y высота центра яруса
local function pyramid(
	parent: Instance,
	name: string,
	side: number,
	height: number,
	base: CFrame,
	y: number,
	color: Color3,
	material: Enum.Material
)
	for quarter = 0, 3 do
		local piece = Instance.new("CornerWedgePart")
		piece.Name = name
		piece.Size = Vector3.new(side / 2, height, side / 2)
		-- Вершина углового клина в углу (+X, -Z): сдвигаем его так, чтобы вершины сошлись в центре
		piece.CFrame = base
			* CFrame.new(0, y, 0)
			* CFrame.Angles(0, quarter * math.pi / 2, 0)
			* CFrame.new(-side / 4, 0, side / 4)
		piece.Color = color
		piece.Material = material
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanTouch = false
		piece.CanQuery = false
		piece.CastShadow = false -- тысячи ярусов елей без теней: дешевле для телефона
		piece.Parent = parent
	end
end

-- Ель: ствол и три яруса-пирамиды, верхний под снегом. Сталкивается только ствол.
function MapProps.Pine(parent: Instance, base: CFrame, scale: number, dark: boolean): Model
	local pine = model("Pine")
	local color = if dark then PINE_DARK else PINE
	cylinder(pine, "Trunk", 1.6 * scale, 6 * scale, base, 2 * scale, DARK_WOOD, Enum.Material.Wood)
	pyramid(pine, "Tier", 13 * scale, 8 * scale, base, 8 * scale, color, Enum.Material.Grass)
	pyramid(pine, "Tier", 10 * scale, 7.5 * scale, base, 12.5 * scale, color, Enum.Material.Grass)
	pyramid(pine, "Snow", 7 * scale, 7 * scale, base, 17 * scale, SNOW, Enum.Material.Snow)
	pine.Parent = parent
	return pine
end

-- Лапландский домик: каменный цоколь, деревянные стены, белые углы, двускатная крыша под снегом,
-- светящиеся окна, труба и гирлянда огоньков под крышей
function MapProps.House(parent: Instance, base: CFrame, options: HouseOptions): Model
	local house = model("House")
	local w, d, h = options.width, options.depth, options.height
	local wall = HOUSE_COLORS[(options.colorIndex - 1) % #HOUSE_COLORS + 1]
	local floor = 1.2 -- высота цоколя над землёй
	local front = -d / 2

	-- Цоколь уходит глубоко вниз, чтобы на склоне под домом не было щели
	part(
		house,
		"Foundation",
		Vector3.new(w + 1.4, 18, d + 1.4),
		base * CFrame.new(0, floor - 9, 0),
		STONE,
		Enum.Material.Slate
	)
	local body = part(
		house,
		"Walls",
		Vector3.new(w, h, d),
		base * CFrame.new(0, floor + h / 2, 0),
		wall,
		Enum.Material.WoodPlanks
	)
	house.PrimaryPart = body
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			decor(
				house,
				"Corner",
				Vector3.new(0.9, h, 0.9),
				base * CFrame.new(x * (w / 2 - 0.2), floor + h / 2, z * (d / 2 - 0.2)),
				WHITE
			)
		end
	end

	-- Крыша: конёк вдоль ширины дома, два ската. Снизу тёмный скат, сверху слой снега.
	local roofHeight = d * 0.42
	local roofDepth = d / 2 + 2
	local top = floor + h
	for _, side in { 0, math.pi } do
		local turn = base * CFrame.Angles(0, side, 0)
		wedge(
			house,
			"Roof",
			Vector3.new(w + 2.4, roofHeight, roofDepth),
			turn * CFrame.new(0, top + roofHeight / 2, -roofDepth / 2),
			DARK_WOOD,
			Enum.Material.Wood
		)
		wedge(
			house,
			"RoofSnow",
			Vector3.new(w + 3.2, roofHeight, roofDepth + 0.6),
			turn * CFrame.new(0, top + roofHeight / 2 + 0.7, -roofDepth / 2 - 0.1),
			SNOW,
			Enum.Material.Snow
		)
	end

	-- Дверь с белой рамой и ступенькой
	decor(
		house,
		"DoorFrame",
		Vector3.new(4.4, 7, 0.3),
		base * CFrame.new(0, floor + 3.5, front - 0.1),
		WHITE
	)
	decor(
		house,
		"Door",
		Vector3.new(3.4, 6.4, 0.3),
		base * CFrame.new(0, floor + 3.2, front - 0.25),
		DARK_WOOD,
		Enum.Material.Wood
	)
	part(
		house,
		"Step",
		Vector3.new(5.5, floor, 3),
		base * CFrame.new(0, floor / 2, front - 1.5),
		STONE,
		Enum.Material.Slate
	)

	-- Окна: тёплый свет в белой раме. Два спереди, по одному на боковых стенах.
	local windowY = floor + h * 0.55
	local function window(cframe: CFrame, lit: boolean)
		decor(house, "WindowFrame", Vector3.new(4, 4, 0.3), cframe, WHITE)
		local glass = decor(
			house,
			"Window",
			Vector3.new(3.2, 3.2, 0.3),
			cframe * CFrame.new(0, 0, -0.12),
			WARM,
			Enum.Material.Neon
		)
		decor(
			house,
			"WindowBar",
			Vector3.new(0.3, 3.2, 0.3),
			cframe * CFrame.new(0, 0, -0.2),
			WHITE
		)
		if lit then
			glow(glass, WARM, 18, 1.2)
		end
	end
	local windowX = w / 2 - 4
	window(base * CFrame.new(-windowX, windowY, front - 0.1), true)
	window(base * CFrame.new(windowX, windowY, front - 0.1), false)
	for _, x in { -1, 1 } do
		window(
			base * CFrame.new(x * (w / 2 + 0.1), windowY, 0) * CFrame.Angles(0, -x * math.pi / 2, 0),
			false
		)
	end

	-- Труба со снежной шапкой
	part(
		house,
		"Chimney",
		Vector3.new(2.6, roofHeight + 2, 2.6),
		base * CFrame.new(w / 4, top + roofHeight / 2 + 1, d / 5),
		Color3.fromRGB(150, 80, 66),
		Enum.Material.Brick
	)
	decor(
		house,
		"ChimneySnow",
		Vector3.new(3.2, 0.7, 3.2),
		base * CFrame.new(w / 4, top + roofHeight + 2.3, d / 5),
		SNOW,
		Enum.Material.Snow
	)

	-- Гирлянда под передним скатом
	local bulbs = math.max(4, math.floor(w / 3.5))
	for index = 1, bulbs do
		local x = -w / 2 + (index - 0.5) * w / bulbs
		local bulb = ball(
			house,
			"Bulb",
			0.9,
			base * CFrame.new(x, top - 0.4, front - 1.2),
			LIGHT_COLORS[(index + options.colorIndex) % #LIGHT_COLORS + 1],
			Enum.Material.Neon
		)
		bulb.CanCollide = false
		bulb.CanQuery = false
		bulb.CastShadow = false
	end
	house.Parent = parent
	return house
end

-- Фонарь: столб, светящийся плафон, крышка со снегом
function MapProps.Lamp(parent: Instance, base: CFrame): Model
	local lamp = model("Lamp")
	local dark = Color3.fromRGB(40, 44, 54)
	cylinder(lamp, "Pole", 0.7, 11, base, 5.5, dark, Enum.Material.Metal)
	local lantern = decor(
		lamp,
		"Lantern",
		Vector3.new(1.8, 2, 1.8),
		base * CFrame.new(0, 12, 0),
		WARM,
		Enum.Material.Neon
	)
	glow(lantern, WARM, 26, 1.4)
	decor(lamp, "Cap", Vector3.new(2.6, 0.4, 2.6), base * CFrame.new(0, 13.2, 0), dark)
	decor(
		lamp,
		"CapSnow",
		Vector3.new(2.4, 0.5, 2.4),
		base * CFrame.new(0, 13.6, 0),
		SNOW,
		Enum.Material.Snow
	)
	lamp.Parent = parent
	return lamp
end

-- Снеговик: три шара, морковка, шляпа, шарф
function MapProps.Snowman(parent: Instance, base: CFrame): Model
	local snowman = model("Snowman")
	ball(snowman, "Bottom", 5, base * CFrame.new(0, 2.2, 0), WHITE, Enum.Material.Snow)
	ball(snowman, "Middle", 3.8, base * CFrame.new(0, 5.6, 0), WHITE, Enum.Material.Snow)
	ball(snowman, "Head", 2.8, base * CFrame.new(0, 8.2, 0), WHITE, Enum.Material.Snow)
	decor(
		snowman,
		"Nose",
		Vector3.new(0.5, 0.5, 1.6),
		base * CFrame.new(0, 8.2, -1.8),
		Color3.fromRGB(255, 140, 40)
	)
	for _, x in { -0.6, 0.6 } do
		decor(
			snowman,
			"Eye",
			Vector3.new(0.35, 0.35, 0.3),
			base * CFrame.new(x, 8.8, -1.25),
			Color3.fromRGB(25, 25, 30)
		)
	end
	local hat = Color3.fromRGB(30, 30, 38)
	cylinder(snowman, "HatBrim", 3.2, 0.3, base, 9.5, hat).CanCollide = false
	cylinder(snowman, "Hat", 2, 1.8, base, 10.5, hat).CanCollide = false
	cylinder(snowman, "Scarf", 3, 0.7, base, 7, Color3.fromRGB(200, 40, 45)).CanCollide = false
	snowman.Parent = parent
	return snowman
end

-- Скамейка под снегом
function MapProps.Bench(parent: Instance, base: CFrame): Model
	local bench = model("Bench")
	part(
		bench,
		"Seat",
		Vector3.new(7, 0.5, 2.2),
		base * CFrame.new(0, 1.8, 0),
		WOOD,
		Enum.Material.WoodPlanks
	)
	part(
		bench,
		"Back",
		Vector3.new(7, 2, 0.5),
		base * CFrame.new(0, 3, 1),
		WOOD,
		Enum.Material.WoodPlanks
	)
	for _, x in { -3, 3 } do
		part(
			bench,
			"Leg",
			Vector3.new(0.5, 1.6, 2),
			base * CFrame.new(x, 0.8, 0),
			Color3.fromRGB(40, 44, 54),
			Enum.Material.Metal
		)
	end
	decor(
		bench,
		"Snow",
		Vector3.new(6.6, 0.4, 0.7),
		base * CFrame.new(0, 4.2, 1),
		SNOW,
		Enum.Material.Snow
	)
	bench.Parent = parent
	return bench
end

-- Полосатый столб-леденец
local function candyPole(parent: Instance, base: CFrame, height: number, diameter: number)
	local segments = math.max(2, math.floor(height / 2))
	local segmentHeight = height / segments
	for index = 1, segments do
		cylinder(
			parent,
			"Stripe",
			diameter,
			segmentHeight,
			base,
			(index - 0.5) * segmentHeight,
			if index % 2 == 0 then WHITE else Color3.fromRGB(215, 40, 50)
		)
	end
end

-- Ворота района: два столба-леденца, полосатая перекладина и значок без текста
function MapProps.Gate(parent: Instance, base: CFrame, width: number, icon: string): Model
	local gate = model("Gate")
	local height = 16
	for _, x in { -1, 1 } do
		candyPole(gate, base * CFrame.new(x * width / 2, 0, 0), height, 2)
		ball(
			gate,
			"Top",
			3,
			base * CFrame.new(x * width / 2, height + 1, 0),
			WARM,
			Enum.Material.Neon
		)
	end
	local stripes = 8
	for index = 1, stripes do
		decor(
			gate,
			"Bar",
			Vector3.new(width / stripes, 1.6, 1.6),
			base * CFrame.new(-width / 2 + (index - 0.5) * width / stripes, height - 1, 0),
			if index % 2 == 0 then WHITE else Color3.fromRGB(215, 40, 50)
		)
	end
	local anchor =
		decor(gate, "Sign", Vector3.new(1, 1, 1), base * CFrame.new(0, height + 4, 0), WHITE)
	anchor.Transparency = 1
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Icon"
	billboard.Size = UDim2.fromScale(8, 8)
	billboard.MaxDistance = 400
	billboard.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = icon
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard
	gate.Parent = parent
	return gate
end

-- Ярмарочный прилавок: стойка, столбики, полосатый навес под снегом
function MapProps.Stall(parent: Instance, base: CFrame, colorIndex: number): Model
	local stall = model("Stall")
	part(
		stall,
		"Counter",
		Vector3.new(10, 3.4, 3.4),
		base * CFrame.new(0, 1.7, 0),
		WOOD,
		Enum.Material.WoodPlanks
	)
	for _, x in { -4.6, 4.6 } do
		for _, z in { -1.6, 2.6 } do
			part(
				stall,
				"Post",
				Vector3.new(0.6, 9, 0.6),
				base * CFrame.new(x, 4.5, z),
				DARK_WOOD,
				Enum.Material.Wood
			)
		end
	end
	local tilt = base * CFrame.new(0, 9.2, 0.5) * CFrame.Angles(math.rad(-10), 0, 0)
	local stripes = 5
	for index = 1, stripes do
		decor(
			stall,
			"Canopy",
			Vector3.new(11 / stripes, 0.4, 6.4),
			tilt * CFrame.new(-5.5 + (index - 0.5) * 11 / stripes, 0, 0),
			if index % 2 == 0 then WHITE else LIGHT_COLORS[(colorIndex - 1) % #LIGHT_COLORS + 1]
		)
	end
	decor(
		stall,
		"CanopySnow",
		Vector3.new(10.4, 0.5, 4),
		tilt * CFrame.new(0, 0.45, 1),
		SNOW,
		Enum.Material.Snow
	)
	-- Товар на прилавке: ёлочные шары
	for index = 1, 4 do
		local toy = ball(
			stall,
			"Toy",
			1.3,
			base * CFrame.new(-3.6 + (index - 1) * 2.4, 4.05, -0.4),
			LIGHT_COLORS[(index + colorIndex) % #LIGHT_COLORS + 1],
			Enum.Material.Neon
		)
		toy.CanCollide = false
		toy.CanQuery = false
	end
	stall.Parent = parent
	return stall
end

-- Главная ёлка площади: ярусы-пирамиды, огни по краям и звезда. height: полная высота в студах.
function MapProps.ChristmasTree(parent: Instance, base: CFrame, height: number): Model
	local tree = model("ChristmasTree")
	local unit = height / 46
	cylinder(tree, "Trunk", 4 * unit, 7 * unit, base, 3.5 * unit, DARK_WOOD, Enum.Material.Wood)
	local tierCount = 5
	local tierHeight = 12 * unit
	for index = 1, tierCount do
		local alpha = (index - 1) / (tierCount - 1)
		local side = (30 - 20 * alpha) * unit
		local y = (10 + (index - 1) * 7) * unit
		-- Соседние ярусы повёрнуты на восьмую оборота: силуэт получается пышнее
		local turned = base * CFrame.Angles(0, index * math.pi / 4, 0)
		pyramid(
			tree,
			"Tier" .. index,
			side,
			tierHeight,
			turned,
			y,
			if index % 2 == 0 then PINE else PINE_DARK,
			Enum.Material.Grass
		)
		-- Огни вдоль нижнего края яруса, по три на сторону
		local bulbIndex = 0
		for quarter = 0, 3 do
			local edge = turned * CFrame.Angles(0, quarter * math.pi / 2, 0)
			for _, along in { -0.5, 0, 0.5 } do
				bulbIndex += 1
				local bulb = ball(
					tree,
					"Bulb",
					1.7 * unit,
					edge
						* CFrame.new(
							along * side * 0.85,
							y - tierHeight / 2 + 0.6 * unit,
							-side / 2
						),
					LIGHT_COLORS[(bulbIndex + index) % #LIGHT_COLORS + 1],
					Enum.Material.Neon
				)
				bulb.CanCollide = false
				bulb.CanQuery = false
				bulb.CastShadow = false
			end
		end
	end
	-- Звезда: два повёрнутых бруска и свет
	local starY = (10 + (tierCount - 1) * 7) * unit + tierHeight / 2 + 1.5 * unit
	local gold = Color3.fromRGB(255, 220, 70)
	for index = 0, 1 do
		local star = decor(
			tree,
			"Star",
			Vector3.new(4.5 * unit, 4.5 * unit, 1.2 * unit),
			base * CFrame.new(0, starY, 0) * CFrame.Angles(0, 0, index * math.pi / 4),
			gold,
			Enum.Material.Neon
		)
		if index == 0 then
			glow(star, gold, 60, 2)
		end
	end
	tree.Parent = parent
	return tree
end

-- Валун под снегом
function MapProps.Rock(parent: Instance, base: CFrame, diameter: number): Part
	return ball(
		parent,
		"Rock",
		diameter,
		base * CFrame.new(0, diameter * 0.15, 0),
		STONE,
		Enum.Material.Slate
	)
end

return MapProps
