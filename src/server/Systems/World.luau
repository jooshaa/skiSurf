--!strict
-- World: карта строится кодом на сервере, чтобы проект собирался из git без ручной сборки в Studio.
-- Существующие Baseplate и SpawnLocation переиспользуются. Устаревшие объекты (Bases, BasicEgg)
-- убираются только из запущенного сервера, в файле места они остаются.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Config)

local W = Config.World

local LEGACY = { "Bases", "BasicEgg" }

local World = {}

local folder: Folder
local workshops: { Part } = {}
local deliverZone: Part? = nil
local deliverPrompt: ProximityPrompt? = nil

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

local function buildGround()
	if Workspace:FindFirstChild("Baseplate") then
		return
	end
	local ground = block(
		"Ground",
		Vector3.new(W.GroundSize, 4, W.GroundSize),
		CFrame.new(0, -2, 0),
		Color3.fromRGB(235, 240, 250),
		folder
	)
	ground.Material = Enum.Material.Snow
end

local function buildSpawn()
	if Workspace:FindFirstChildWhichIsA("SpawnLocation", true) then
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
		table.insert(workshops, pad)
	end
end

local function buildPlaza()
	local plaza = make("Part", {
		Name = "Plaza",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, W.PlazaRadius * 2, W.PlazaRadius * 2),
		CFrame = CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(215, 220, 230),
		Material = Enum.Material.Cobblestone,
		Anchored = true,
		CanCollide = false,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	}, folder)
	return plaza
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
	buildSpawn()
	buildPlaza()
	buildSleigh()
	buildWorkshops()
end

return World
