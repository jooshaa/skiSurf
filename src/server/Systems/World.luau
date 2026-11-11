--!strict
-- World: карта строится кодом на сервере, чтобы проект собирался из git без ручной сборки в Studio.
-- Рельеф (холмы, горы, тропинки) пишется в Terrain, поверх ставятся деревня, лес и озеро.
-- Существующие Baseplate и SpawnLocation переиспользуются и только прячутся на время игры.
-- Устаревшие объекты (Bases, BasicEgg) убираются только из запущенного сервера.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Config)
local MapProps = require(script.Parent.Parent.MapProps)
local Relief = require(script.Parent.Parent.Relief)

local W = Config.World
local M = Config.Map

local LEGACY = { "Bases", "BasicEgg" }

local World = {}

local folder: Folder
local workshops: { Part } = {}
local deliverZone: Part? = nil
local deliverPrompt: ProximityPrompt? = nil

-- Круги, занятые постройками: в них не появляются подарки и не растут ели
type Obstacle = { x: number, z: number, radius: number }
local obstacles: { Obstacle } = {}
local rng = Random.new(M.Seed)

local function occupy(position: Vector3, radius: number)
	table.insert(obstacles, { x = position.X, z = position.Z, radius = radius })
end

local function isBlocked(x: number, z: number, margin: number): boolean
	for _, obstacle in obstacles do
		local dx, dz = x - obstacle.x, z - obstacle.z
		local reach = obstacle.radius + margin
		if dx * dx + dz * dz < reach * reach then
			return true
		end
	end
	return false
end

-- Точка на земле: постройки чуть утоплены, чтобы на склоне под ними не было щели
local function onGround(x: number, z: number, sink: number?): Vector3
	return Vector3.new(x, Relief.Height(x, z) - (sink or 0), z)
end

-- CFrame на земле лицом (-Z) к точке target
local function facing(position: Vector3, target: Vector3): CFrame
	local flatTarget = Vector3.new(target.X, position.Y, target.Z)
	if (flatTarget - position).Magnitude < 0.01 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, flatTarget)
end

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className) :: any
	for key, value in props do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function block(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	parent: Instance
): Part
	return make("Part", {
		Name = name,
		Size = size,
		CFrame = cframe,
		Color = color,
		Anchored = true,
		Material = Enum.Material.SmoothPlastic,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	}, parent)
end

-- Земля: рельеф в Terrain. Под ним остаётся невидимая плита как страховка от провала.
local function buildGround()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		-- Только в запущенной игре, в файле места плита не меняется. Плита уходит под снег,
		-- чтобы персонаж стоял на снегу, а не на пластике.
		baseplate.Transparency = 1
		baseplate.CFrame -= Vector3.new(0, M.SafetyPlateDrop, 0)
		baseplate.CastShadow = false
		for _, child in baseplate:GetChildren() do
			if child:IsA("Texture") or child:IsA("Decal") then
				child.Transparency = 1 -- клетка плиты не должна просвечивать сквозь снег
			end
		end
	else
		local ground = block(
			"Ground",
			Vector3.new(W.GroundSize, 4, W.GroundSize),
			CFrame.new(0, -2 - M.SafetyPlateDrop, 0),
			Color3.fromRGB(235, 240, 250),
			folder
		)
		ground.Transparency = 1
		ground.CastShadow = false
	end
	Relief.Build()
end

-- Невидимые стены по границе игровой зоны: в горы уйти нельзя
local function buildWalls()
	local container = make("Folder", { Name = "Walls" }, folder)
	local centerX, centerZ = (M.MinX + M.MaxX) / 2, (M.MinZ + M.MaxZ) / 2
	local spanX, spanZ = M.MaxX - M.MinX, M.MaxZ - M.MinZ
	local sides = {
		{ Vector3.new(M.MinX, 0, centerZ), Vector3.new(M.WallThickness, M.WallHeight, spanZ) },
		{ Vector3.new(M.MaxX, 0, centerZ), Vector3.new(M.WallThickness, M.WallHeight, spanZ) },
		{ Vector3.new(centerX, 0, M.MinZ), Vector3.new(spanX, M.WallHeight, M.WallThickness) },
		{ Vector3.new(centerX, 0, M.MaxZ), Vector3.new(spanX, M.WallHeight, M.WallThickness) },
	}
	for _, side in sides do
		make("Part", {
			Name = "Wall",
			Size = side[2],
			CFrame = CFrame.new(side[1] + Vector3.new(0, M.WallHeight / 2, 0)),
			Transparency = 1,
			Anchored = true,
			CanTouch = false,
			CanQuery = false,
			CastShadow = false,
		}, container)
	end
end

local function buildSpawn()
	local existing = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if existing then
		-- Плита спавна остаётся рабочей, но не видна на брусчатке (только в запущенной игре)
		existing.Transparency = 1
		existing.CanCollide = false
		for _, child in existing:GetChildren() do
			if child:IsA("Decal") then
				child.Transparency = 1
			end
		end
		return
	end
	make("SpawnLocation", {
		Name = "SpawnLocation",
		Size = Vector3.new(10, 1, 10),
		CFrame = CFrame.new(W.SpawnPosition + Vector3.new(0, 0.5, 0)),
		Anchored = true,
		Neutral = true,
		Duration = 0,
		Transparency = 1,
		CanCollide = false,
	}, folder)
end

-- Здание мастерской: стены и крыша над площадкой, вход смотрит на площадь
local function buildWorkshopBuilding(pad: Part)
	local building = make("Model", { Name = "Building" }, pad)
	local wood = Color3.fromRGB(120, 80, 55)
	local half = W.WorkshopSize.X / 2
	local wall = W.WorkshopWallHeight
	local base = W.WorkshopSize.Y / 2
	local function piece(name: string, size: Vector3, offset: Vector3, color: Color3)
		local part = block(name, size, pad.CFrame * CFrame.new(offset), color, building)
		part.Material = Enum.Material.WoodPlanks
	end
	piece(
		"BackWall",
		Vector3.new(half * 2, wall, 1),
		Vector3.new(0, base + wall / 2, half - 0.5),
		wood
	)
	piece(
		"LeftWall",
		Vector3.new(1, wall, half),
		Vector3.new(-half + 0.5, base + wall / 2, half / 2),
		wood
	)
	piece(
		"RightWall",
		Vector3.new(1, wall, half),
		Vector3.new(half - 0.5, base + wall / 2, half / 2),
		wood
	)
	piece(
		"Roof",
		Vector3.new(half * 2 + 2, 1, half + 2),
		Vector3.new(0, base + wall + 0.5, half / 2),
		Color3.fromRGB(190, 50, 50)
	)
	local snow = block(
		"RoofSnow",
		Vector3.new(half * 2 + 1, 0.8, half + 1),
		pad.CFrame * CFrame.new(0, base + wall + 1.4, half / 2),
		Color3.fromRGB(235, 242, 252),
		building
	)
	snow.Material = Enum.Material.Snow
	snow.CanCollide = false
	snow.CanTouch = false
end

-- Площадки мастерских по кругу вокруг площади, смотрят на центр
local function buildWorkshops()
	local container = make("Folder", { Name = "Workshops" }, folder)
	for index = 1, W.WorkshopCount do
		local angle = (index - 0.5) / W.WorkshopCount * math.pi * 2
		local position = Vector3.new(
			math.cos(angle) * W.WorkshopRadius,
			W.WorkshopSize.Y / 2,
			math.sin(angle) * W.WorkshopRadius
		)
		local pad = block(
			"Workshop" .. index,
			W.WorkshopSize,
			CFrame.lookAt(position, Vector3.new(0, position.Y, 0)),
			Color3.fromRGB(150, 100, 70),
			container
		)
		pad.Material = Enum.Material.WoodPlanks
		make("ObjectValue", { Name = "Owner" }, pad)
		make("Folder", { Name = "Elves" }, pad)
		local gui = make("BillboardGui", {
			Name = "OwnerGui",
			Size = UDim2.fromOffset(220, 44),
			StudsOffset = Vector3.new(0, 14, 0),
			MaxDistance = 250,
			AlwaysOnTop = false,
		}, pad)
		make("TextLabel", {
			Name = "Label",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.3,
			TextScaled = true,
			Font = Enum.Font.GothamBold,
		}, gui)
		buildWorkshopBuilding(pad)
		occupy(position, W.WorkshopSize.X * M.Footprint.WorkshopFactor)
		table.insert(workshops, pad)
	end
end

-- Деревня: главная ёлка, ярмарка и скамейки на площади, кольца домов вокруг, фонари вдоль троп
local function buildVillage()
	local container = make("Folder", { Name = "Village" }, folder)
	local center = Vector3.zero

	local treePosition = onGround(W.TreePosition.X, W.TreePosition.Z)
	MapProps.ChristmasTree(container, CFrame.new(treePosition), W.TreeHeight)
	occupy(treePosition, W.TreeHeight * M.Footprint.TreeFactor)

	for index = 1, M.StallCount do
		local angle = (index - 0.5) / M.StallCount * math.pi * 2
		local position = onGround(math.cos(angle) * M.StallRadius, math.sin(angle) * M.StallRadius)
		MapProps.Stall(container, facing(position, center), index)
		occupy(position, M.Footprint.Stall)
	end

	for index = 1, M.BenchCount do
		local angle = (index - 0.5) / M.BenchCount * math.pi * 2
		local position = onGround(math.cos(angle) * M.BenchRadius, math.sin(angle) * M.BenchRadius)
		MapProps.Bench(container, facing(position, center))
		occupy(position, M.Footprint.Bench)
	end

	for _, ring in M.HouseRings do
		for index = 1, ring.count do
			local angle = (index - 1 + ring.offset) / ring.count * math.pi * 2
			local width = rng:NextNumber(M.HouseWidthMin, M.HouseWidthMax)
			local depth = rng:NextNumber(M.HouseDepthMin, M.HouseDepthMax)
			local position =
				onGround(math.cos(angle) * ring.radius, math.sin(angle) * ring.radius, 0.5)
			MapProps.House(container, facing(position, center), {
				width = width,
				depth = depth,
				height = rng:NextNumber(M.HouseHeightMin, M.HouseHeightMax),
				colorIndex = rng:NextInteger(1, M.HouseColors),
			})
			occupy(position, math.max(width, depth) * M.Footprint.HouseFactor)
		end
	end

	-- Фонари: пара у начала каждой тропы и дальше вдоль неё по обе стороны
	local spread = math.rad(M.PlazaLampSpread)
	local directions = {
		{ direction = Vector3.new(0, 0, -1), length = M.NorthPathLength },
		{ direction = Vector3.new(0, 0, 1), length = M.PathLength },
		{ direction = Vector3.new(1, 0, 0), length = M.PathLength },
		{ direction = Vector3.new(-1, 0, 0), length = M.PathLength },
	}
	for _, entry in directions do
		local direction = entry.direction
		local side = Vector3.new(-direction.Z, 0, direction.X)
		local axisAngle = math.atan2(direction.Z, direction.X)
		for _, sign in { -1, 1 } do
			local angle = axisAngle + sign * spread
			local position = onGround(
				math.cos(angle) * M.PlazaLampRadius,
				math.sin(angle) * M.PlazaLampRadius,
				0.3
			)
			MapProps.Lamp(container, CFrame.new(position))
			occupy(position, M.Footprint.Lamp)
		end
		local distance = M.PlazaLampRadius + M.PathLampStep
		while distance < entry.length - M.PathLampOffset do
			if math.abs(distance - M.RingRadius) > M.PathWidth then
				for _, sign in { -1, 1 } do
					local point = direction * distance + side * (sign * M.PathLampOffset)
					local position = onGround(point.X, point.Z, 0.3)
					MapProps.Lamp(container, CFrame.new(position))
					occupy(position, M.Footprint.Lamp)
				end
			end
			distance += M.PathLampStep
		end
	end

	-- Снеговики между домами
	local placed, attempts = 0, 0
	while placed < M.Snowmen and attempts < M.Snowmen * 20 do
		attempts += 1
		local angle = rng:NextNumber() * math.pi * 2
		local radius = rng:NextNumber(M.SnowmanRadiusMin, M.SnowmanRadiusMax)
		local x, z = math.cos(angle) * radius, math.sin(angle) * radius
		if not Relief.IsPath(x, z) and not isBlocked(x, z, M.Footprint.SnowmanSpacing) then
			local position = onGround(x, z, 0.4)
			MapProps.Snowman(container, facing(position, center))
			occupy(position, M.Footprint.Snowman)
			placed += 1
		end
	end
end

-- Снежный парк: ворота-леденцы на тропе, фонари и скамейки вокруг озера
local function buildPark(district: Config.District)
	local container = make("Folder", { Name = district.id }, folder)
	local center = district.center
	local halfX, halfZ = district.size.X / 2, district.size.Y / 2
	local inset = M.LakeLampInset

	local gatePosition = onGround(center.X, center.Z + halfZ + inset * 2)
	MapProps.Gate(container, CFrame.new(gatePosition), M.GateWidth, "⛸️")
	occupy(gatePosition + Vector3.new(M.GateWidth / 2, 0, 0), M.Footprint.Lamp)
	occupy(gatePosition - Vector3.new(M.GateWidth / 2, 0, 0), M.Footprint.Lamp)

	for _, x in { -1, 0, 1 } do
		for _, z in { -1, 0, 1 } do
			-- Середина южного берега занята воротами, середина озера льдом
			if not (x == 0 and z == 0) and not (x == 0 and z == 1) then
				local position =
					onGround(center.X + x * (halfX + inset), center.Z + z * (halfZ + inset), 0.3)
				MapProps.Lamp(container, CFrame.new(position))
				occupy(position, M.Footprint.Lamp)
			end
		end
	end
	for _, x in { -0.5, 0.5 } do
		for _, z in { -1, 1 } do
			local position = onGround(center.X + x * halfX, center.Z + z * (halfZ + inset), 0.2)
			MapProps.Bench(container, facing(position, center))
			occupy(position, M.Footprint.Bench)
		end
	end
end

-- Лес: ели и валуны по зерну. Не растут на площади, тропах, льду и вплотную к постройкам.
local function buildForest()
	local container = make("Folder", { Name = "Forest" }, folder)
	local function isFree(x: number, z: number): boolean
		if math.sqrt(x * x + z * z) < M.RingRadius + M.PathWidth then
			return false
		end
		if Relief.IsPath(x, z) or isBlocked(x, z, M.PineSpacing) then
			return false
		end
		for _, district in Config.Districts do
			if
				district.ice
				and math.abs(x - district.center.X) < district.size.X / 2 + M.LakeShore
				and math.abs(z - district.center.Z) < district.size.Y / 2 + M.LakeShore
			then
				return false
			end
		end
		return Relief.Height(x, z) < M.PineMaxHeight
	end

	local placed, attempts = 0, 0
	while placed < M.Pines and attempts < M.PineAttempts do
		attempts += 1
		local x = rng:NextNumber(M.MinX - M.ForestOuter, M.MaxX + M.ForestOuter)
		local z = rng:NextNumber(M.MinZ - M.ForestOuter, M.MaxZ + M.ForestOuter)
		local inVillage = math.sqrt(x * x + z * z) < M.VillageRadius
		if isFree(x, z) and (not inVillage or rng:NextNumber() < M.PineVillageChance) then
			local scale = rng:NextNumber(M.PineScaleMin, M.PineScaleMax)
			local position = onGround(x, z, 1)
			MapProps.Pine(
				container,
				CFrame.new(position) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0),
				scale,
				rng:NextNumber() < 0.5
			)
			occupy(position, M.Footprint.PineFactor * scale)
			placed += 1
		end
	end

	placed, attempts = 0, 0
	while placed < M.Rocks and attempts < M.Rocks * 20 do
		attempts += 1
		local x = rng:NextNumber(M.MinX, M.MaxX)
		local z = rng:NextNumber(M.MinZ, M.MaxZ)
		if isFree(x, z) then
			local size = rng:NextNumber(M.RockSizeMin, M.RockSizeMax)
			local position = onGround(x, z)
			MapProps.Rock(container, CFrame.new(position), size)
			occupy(position, size / 2)
			placed += 1
		end
	end
end

-- Зимние сумерки: низкое солнце, голубые тени, лёгкая дымка. Меняется только запущенная игра.
local function applyLighting()
	local settings = M.Lighting
	Lighting.ClockTime = settings.ClockTime
	Lighting.GeographicLatitude = settings.GeographicLatitude
	Lighting.Brightness = settings.Brightness
	Lighting.Ambient = settings.Ambient
	Lighting.OutdoorAmbient = settings.OutdoorAmbient
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		local created = Instance.new("Atmosphere")
		created.Parent = Lighting
		atmosphere = created
	end
	if atmosphere then
		atmosphere.Density = settings.FogDensity
		atmosphere.Color = settings.FogColor
	end
end

-- Табло у саней: шансы содержимого подарков, строится из Config (совпадает с сервером)
local function buildChanceBoard(sleigh: Model, origin: CFrame)
	local board = block(
		"ChanceBoard",
		Vector3.new(12, 7, 0.5),
		origin * CFrame.new(-13, 4.5, 0) * CFrame.Angles(0, math.rad(25), 0),
		Color3.fromRGB(40, 50, 80),
		sleigh
	)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = make("SurfaceGui", { Name = "Chances", Face = face, PixelsPerStud = 40 }, board)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Vertical }, gui)
		for _, id in { "Small", "Medium", "Large" } do
			local size = Config.Gifts.Sizes[id]
			local parts = {}
			for _, content in size.contents do
				table.insert(parts, string.format("%s %d%%", content.rarity, content.chance))
			end
			make("TextLabel", {
				Size = UDim2.fromScale(1, 1 / 3),
				BackgroundTransparency = 1,
				Text = string.format("🎁×%d  %s", size.carriers, table.concat(parts, " · ")),
				TextColor3 = size.color,
				TextStrokeTransparency = 0.4,
				TextScaled = true,
				Font = Enum.Font.GothamBold,
			}, gui)
		end
	end
end

-- Сани Санты на площади: простая модель из Part, зона сдачи и кнопка «Сдать»
local function buildSleigh()
	local sleigh = make("Model", { Name = "Sleigh" }, folder)
	local origin = CFrame.new(W.SleighPosition)
	local red = Color3.fromRGB(200, 40, 45)
	local gold = Color3.fromRGB(240, 190, 60)
	local dark = Color3.fromRGB(60, 40, 30)

	local body = block("Body", Vector3.new(7, 2.5, 12), origin * CFrame.new(0, 2.6, 0), red, sleigh)
	block("Back", Vector3.new(7, 4, 1.5), origin * CFrame.new(0, 5, 5.25), red, sleigh)
	block("Front", Vector3.new(7, 2, 1.5), origin * CFrame.new(0, 4.2, -5.25), red, sleigh)
	block("Trim", Vector3.new(7.4, 0.4, 12.4), origin * CFrame.new(0, 3.95, 0), gold, sleigh)
	block("RunnerLeft", Vector3.new(0.6, 0.6, 14), origin * CFrame.new(-3, 0.4, 0), dark, sleigh)
	block("RunnerRight", Vector3.new(0.6, 0.6, 14), origin * CFrame.new(3, 0.4, 0), dark, sleigh)
	for _, x in { -3, 3 } do
		for _, z in { -4, 4 } do
			block("Strut", Vector3.new(0.5, 1, 0.5), origin * CFrame.new(x, 1, z), dark, sleigh)
		end
	end
	local sack = block(
		"Sack",
		Vector3.new(5, 5, 5),
		origin * CFrame.new(0, 5.5, 1.5),
		Color3.fromRGB(150, 110, 70),
		sleigh
	)
	sack.Shape = Enum.PartType.Ball
	sleigh.PrimaryPart = body

	local zone = make("Part", {
		Name = "DeliverZone",
		Size = Vector3.new(W.DeliverZoneSize, 10, W.DeliverZoneSize),
		CFrame = origin * CFrame.new(0, 5, 0),
		Transparency = 1,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
	}, sleigh)
	deliverZone = zone

	deliverPrompt = make("ProximityPrompt", {
		Name = "DeliverPrompt",
		ActionText = "Сдать",
		ObjectText = "🎁",
		HoldDuration = 0,
		MaxActivationDistance = Config.Gifts.DeliverDistance,
		RequiresLineOfSight = false,
	}, body)

	buildChanceBoard(sleigh, origin)
	sleigh.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- сани видны всем издалека
end

-- Районы с помехой «лёд»: скользкое покрытие поверх земли
local function buildDistricts()
	local container = make("Folder", { Name = "Districts" }, folder)
	for _, district in Config.Districts do
		if district.ice then
			buildPark(district)
			local ice = block(
				district.id .. "Ice",
				Vector3.new(district.size.X, Config.Ice.Thickness, district.size.Y),
				CFrame.new(district.center + Vector3.new(0, Config.Ice.Thickness / 2, 0)),
				Color3.fromRGB(120, 190, 240),
				container
			)
			ice.Material = Enum.Material.Ice
			ice.CustomPhysicalProperties =
				PhysicalProperties.new(0.9, Config.Ice.Friction, 0, Config.Ice.FrictionWeight, 1)
		end
	end
end

-- Высота земли в точке (подарки ложатся на рельеф)
function World.GroundHeight(x: number, z: number): number
	return Relief.Height(x, z)
end

-- Внутри ли точка игровой зоны, не ближе margin к невидимой стене
function World.InBounds(position: Vector3, margin: number): boolean
	return Relief.EdgeDistance(position.X, position.Z) > margin
end

-- Занята ли точка постройкой, деревом или иным препятствием (с запасом margin)
function World.IsBlocked(position: Vector3, margin: number): boolean
	return isBlocked(position.X, position.Z, margin)
end

-- Зона сдачи и кнопка «Сдать» (для системы подарков)
function World.GetSleighParts(): (Part?, ProximityPrompt?)
	return deliverZone, deliverPrompt
end

function World.GetFolder(): Folder
	return folder
end

function World.GetWorkshops(): { Part }
	return workshops
end

function World.init()
	for _, name in LEGACY do
		local legacy = Workspace:FindFirstChild(name)
		if legacy then
			legacy:Destroy()
		end
	end
	folder = make("Folder", { Name = "World" }, Workspace)
	buildGround()
	buildWalls()
	buildSpawn()
	buildSleigh()
	occupy(W.SleighPosition, M.Footprint.Sleigh)
	buildWorkshops()
	buildVillage()
	buildDistricts()
	buildForest()
	applyLighting()
end

return World
