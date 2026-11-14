--!strict
-- Hazards: то, что видно от препятствий и пещер. Своды и лава пещер, сугробы, лужи лавы и йети
-- на полотне. Только картинка: наезд считает SledSim по тем же числам (Obstacles).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Obstacles = require(ReplicatedStorage.Obstacles)
local SledConfig = require(ReplicatedStorage.SledConfig)
local Track = require(ReplicatedStorage.Track)
local Scenery = require(ServerScriptService.Scenery)

local K = SledConfig.Cave
local O = SledConfig.Obstacles

local Hazards = {}

local function block(
	parent: Instance,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	shadow: boolean,
	solid: boolean?
): Part
	local part = Instance.new("Part")
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = solid == true
	part.CanTouch = false
	part.CanQuery = solid == true
	part.CastShadow = shadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Свод из плит по половине эллипса. out: на сколько плиты вынесены наружу от линии свода
local function arch(
	parent: Instance,
	frame: CFrame,
	halfWidth: number,
	height: number,
	thickness: number,
	depth: number,
	out: number,
	first: number,
	last: number,
	color: Color3,
	material: Enum.Material,
	shadow: boolean,
	solid: boolean?
)
	local rise = height + K.Sink
	for index = first, last do
		local a0 = math.pi * (index - 1) / K.Segments
		local a1 = math.pi * index / K.Segments
		local p0 = Vector2.new(math.cos(a0) * halfWidth, math.sin(a0) * rise)
		local p1 = Vector2.new(math.cos(a1) * halfWidth, math.sin(a1) * rise)
		local mid = (p0 + p1) / 2
		local delta = p1 - p0
		-- Плита лежит вдоль хорды; её -Y смотрит наружу свода
		block(
			parent,
			Vector3.new(delta.Magnitude + K.Overlap + out, thickness, depth),
			frame
				* CFrame.new(mid.X, mid.Y - K.Sink, 0)
				* CFrame.Angles(0, 0, math.atan2(delta.Y, delta.X))
				* CFrame.new(0, -out - thickness / 2, 0),
			color,
			material,
			shadow,
			solid
		)
	end
end

local function buildCave(parent: Instance, track: Track.Data, from: number, to: number)
	local rings = math.max(1, math.round((to - from) / K.RingStep))
	local span = (to - from) / rings
	local capFirst = math.floor((K.Segments - K.SnowCap) / 2) + 1
	local lit = 0
	for ring = 1, rings do
		local s = from + (ring - 0.5) * span
		local _, _, _, width, kappa = Track.At(track, s)
		local frame = Track.Frame(track, s, 0)
		local half = width / 2 + K.Side
		-- На повороте плиты расходятся по внешней стороне: удлиняем, чтобы не было щелей
		local depth = span * (1 + math.abs(kappa) * (half + K.Thickness)) + K.Overlap
		arch(
			parent,
			frame,
			half,
			K.Height,
			K.Thickness,
			depth,
			0,
			1,
			K.Segments,
			if ring % 2 == 0 then K.Rock else K.RockB,
			Enum.Material.Slate,
			true,
			true
		)
		arch(
			parent,
			frame,
			half,
			K.Height,
			K.SnowThickness,
			depth,
			K.Thickness,
			capFirst,
			capFirst + K.SnowCap - 1,
			K.SnowColor,
			Enum.Material.Snow,
			false,
			true
		)
		-- Сталактиты под высоким потолком туннеля (не мешают санкам)
		if ring % 3 == 0 then
			local stalSide = if ring % 2 == 0 then -1 else 1
			local sx = stalSide * (half * 0.42)
			local stalH = 3.2 + (ring % 3) * 0.9
			local stal = block(
				parent,
				Vector3.new(1.5, stalH, 1.5),
				frame
					* CFrame.new(sx, K.Height - stalH * 0.5 - 1.0, 0)
					* CFrame.Angles(0, 0, math.pi),
				Color3.fromRGB(165, 210, 240),
				Enum.Material.Ice,
				false,
				true
			)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Wedge
			mesh.Parent = stal
		end
		-- Лава течёт вдоль обеих стен
		for _, side in { -1, 1 } do
			local lava = block(
				parent,
				Vector3.new(K.Side, K.LavaThickness, depth),
				frame
					* CFrame.new(
						side * (width / 2 + K.Side / 2),
						-K.LavaDrop - K.LavaThickness / 2,
						0
					),
				K.LavaColor,
				Enum.Material.Neon,
				false,
				false
			)
			local due = math.floor((s - from) / K.LightEvery)
			if due > lit and side == (if due % 2 == 0 then 1 else -1) then
				lit = due
				local light = Instance.new("PointLight")
				light.Color = K.LightColor
				light.Range = K.LightRange
				light.Brightness = K.LightBrightness
				light.Shadows = false
				light.Parent = lava
				-- Светящийся кристальный факел на стене туннеля
				block(
					parent,
					Vector3.new(1.1, 2.6, 1.1),
					frame
						* CFrame.new(side * (half - 1.2), 6.5, 0)
						* CFrame.Angles(0, 0, -side * 0.35),
					K.LightColor,
					Enum.Material.Neon,
					false,
					true
				)
			end
		end
	end
	-- Ледяные арки на входе и выходе (твёрдые для санок и снарядов)
	for _, s in { from, to } do
		local _, _, _, width = Track.At(track, s)
		arch(
			parent,
			Track.Frame(track, s, 0),
			width / 2 + K.Side + K.PortalGrow,
			K.Height + K.PortalGrow,
			K.Thickness + K.PortalGrow,
			K.PortalDepth,
			-K.PortalGrow,
			1,
			K.Segments,
			K.PortalColor,
			Enum.Material.Ice,
			true,
			true
		)
	end
end

-- Где стоит йети на полотне в момент time. Клиент двигает их по этой же формуле.
function Hazards.YetiFrame(track: Track.Data, obstacle: Obstacles.Obstacle, time: number): CFrame
	return Track.Frame(track, obstacle.s, Obstacles.D(obstacle, time))
end

local function buildObstacles(parent: Instance, track: Track.Data)
	local yetis = Instance.new("Folder")
	yetis.Name = "RoadYetis"
	local asset = SledConfig.Assets.Yeti
	local yeti = Scenery.LoadMesh(asset.mesh, asset.texture)
	for index, obstacle in Obstacles.Get(track) do
		local frame = Track.Frame(track, obstacle.s, obstacle.d)
		if obstacle.kind == "Drift" then
			local spec = O.Drift
			local mound = block(
				parent,
				Vector3.new(
					obstacle.radius * 2,
					obstacle.radius * 2 * spec.height,
					obstacle.radius * 2
				),
				frame,
				spec.color,
				Enum.Material.Snow,
				false
			)
			local shape = Instance.new("SpecialMesh")
			shape.MeshType = Enum.MeshType.Sphere
			shape.Parent = mound
			mound.CanTouch = true
			mound:SetAttribute("SledObstacle", "Drift")
		elseif obstacle.kind == "Lava" then
			local spec = O.Lava
			local flat = frame * CFrame.Angles(0, 0, math.pi / 2) -- ось цилиндра вверх от снега
			local pool = block(
				parent,
				Vector3.new(spec.thickness * 1.15, obstacle.radius * 1.82, obstacle.radius * 1.82),
				flat * CFrame.new(spec.thickness * 0.55, 0, 0),
				spec.color,
				Enum.Material.Neon,
				false
			)
			pool.Shape = Enum.PartType.Cylinder
			pool.CanTouch = true
			pool:SetAttribute("SledObstacle", "Lava")

			-- Внешняя корка застывшей магмы
			local crust = block(
				parent,
				Vector3.new(
					spec.thickness * 0.75,
					(obstacle.radius + spec.rim * 0.65) * 2,
					(obstacle.radius + spec.rim * 0.65) * 2
				),
				flat * CFrame.new(spec.thickness * 0.3, 0, 0),
				Color3.fromRGB(145, 42, 14),
				Enum.Material.CrackedLava,
				false
			)
			crust.Shape = Enum.PartType.Cylinder

			-- Кольцо из 10 объёмных базальтовых камней по краю кратера
			local rockCount = 10
			for r = 1, rockCount do
				local ang = (r / rockCount) * math.pi * 2 + (index % 5) * 0.25
				local dist = obstacle.radius + spec.rim * 0.45
				local rx = math.cos(ang) * dist
				local rz = math.sin(ang) * dist
				local rw = 1.6 + ((r + index) % 3) * 0.45
				local rh = 0.85 + ((r * 2 + index) % 3) * 0.35
				local rock = block(
					parent,
					Vector3.new(rw, rh, rw * 0.85),
					frame
						* CFrame.new(rx, rh * 0.35, rz)
						* CFrame.Angles(((r % 3) - 1) * 0.22, ang, (((r + 1) % 3) - 1) * 0.25),
					if r % 2 == 0 then spec.rimColor else Color3.fromRGB(34, 28, 34),
					Enum.Material.Slate,
					true
				)
				rock.Shape = Enum.PartType.Block
			end

			-- Пузырящиеся лавовые купола внутри кратера
			for b = 1, 3 do
				local bAng = b * 2.1 + index
				local bDist = obstacle.radius * (0.28 + (b % 2) * 0.24)
				local bSize = 1.05 + (b % 2) * 0.45
				local bubble = block(
					parent,
					Vector3.new(bSize, bSize * 0.55, bSize),
					frame
						* CFrame.new(
							math.cos(bAng) * bDist,
							spec.thickness * 0.7,
							math.sin(bAng) * bDist
						),
					Color3.fromRGB(255, 185, 45),
					Enum.Material.Neon,
					false
				)
				bubble.Shape = Enum.PartType.Ball
			end

			-- Свечение и искры жара
			local glow = Instance.new("PointLight")
			glow.Color = Color3.fromRGB(255, 120, 35)
			glow.Range = 22
			glow.Brightness = 1.5
			glow.Shadows = false
			glow.Parent = pool

			local embers = Instance.new("ParticleEmitter")
			embers.Color =
				ColorSequence.new(Color3.fromRGB(255, 210, 80), Color3.fromRGB(255, 65, 15))
			embers.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(1, 0),
			})
			embers.LightEmission = 1
			embers.Lifetime = NumberRange.new(0.6, 1.1)
			embers.Rate = 14
			embers.Speed = NumberRange.new(4, 9)
			embers.SpreadAngle = Vector2.new(25, 25)
			embers.EmissionDirection = Enum.NormalId.Right -- для цилиндра, повернутого на 90°, Right = вверх
			embers.Parent = pool
		else
			local spec = O.Yeti
			local figure: BasePart
			if yeti then
				figure = yeti:Clone()
				figure.Size *= spec.height / figure.Size.Y
			else
				-- Модель не загрузилась: белый столб того же размера
				figure = block(
					yetis,
					Vector3.new(obstacle.radius, spec.height, obstacle.radius),
					frame,
					Color3.new(1, 1, 1),
					Enum.Material.Snow,
					true
				)
			end
			figure.Name = tostring(index)
			figure.CastShadow = true
			figure.CanCollide = false
			figure.CanTouch = true
			figure.CanQuery = true
			figure:SetAttribute("SledObstacle", "Yeti")
			-- Лицом вверх по трассе, к едущему
			figure.CFrame = Hazards.YetiFrame(track, obstacle, 0)
				* CFrame.new(0, figure.Size.Y / 2, 0)
				* CFrame.Angles(0, math.pi + math.rad(asset.yaw), 0)
			figure.Parent = yetis
		end
	end
	yetis.Parent = parent
end

-- Пещеры: из блоков, сети не ждут
function Hazards.BuildCaves(parent: Instance, track: Track.Data)
	for index, cave in track.caves do
		local model = Instance.new("Model")
		model.Name = "Cave" .. index
		buildCave(model, track, cave.from, cave.to)
		model.Parent = parent
	end
end

-- Препятствия: йети ждёт загрузки модели из сети
function Hazards.BuildObstacles(parent: Instance, track: Track.Data)
	local model = Instance.new("Model")
	model.Name = "Obstacles"
	buildObstacles(model, track)
	model.Parent = parent
end

return Hazards
