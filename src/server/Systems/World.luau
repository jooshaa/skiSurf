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
		table.insert(workshops, pad)
	end
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
	buildWorkshops()
end

return World
