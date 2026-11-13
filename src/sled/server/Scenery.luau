--!strict
-- Scenery: всё, что вокруг трассы и не влияет на езду: снежные склоны по бокам, скалы под ними,
-- дно долины, дальние вершины, лес, валуны, флажки, облака и свет. Линию трассы не меняет.
local AssetService = game:GetService("AssetService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SledConfig = require(ReplicatedStorage.SledConfig)
local Track = require(ReplicatedStorage.Track)

local V = SledConfig.Visual
local S = SledConfig.Scenery
local M = SledConfig.Mesh
local G = SledConfig.Signs
local Y = SledConfig.Yeti

local Scenery = {}

-- Склон у края трассы: ломаная от края через перегиб к внешней кромке.
-- weight: доля от обычного шанса посадки (сечения сетки идут чаще блоков)
export type Shoulder = {
	edge: Vector3,
	mid: Vector3,
	outer: Vector3,
	width: number,
	weight: number,
	s: number, -- путь вдоль трассы
	side: number, -- -1 слева от трассы, 1 справа
}

local function block(
	parent: Instance,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	shadow: boolean?
): Part
	local part = Instance.new("Part")
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = shadow == true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Пирамида из четырёх угловых клиньев: ель без модели и дальние вершины
local function pyramid(
	parent: Instance,
	base: CFrame,
	width: number,
	height: number,
	color: Color3,
	material: Enum.Material,
	shadow: boolean
)
	for quarter = 0, 3 do
		local piece = Instance.new("CornerWedgePart")
		piece.Size = Vector3.new(width / 2, height, width / 2)
		-- Вершина углового клина в углу (+X, -Z): четыре четверти сходятся вершинами в центре
		piece.CFrame = base
			* CFrame.new(0, height / 2, 0)
			* CFrame.Angles(0, quarter * math.pi / 2, 0)
			* CFrame.new(-width / 4, 0, width / 4)
		piece.Color = color
		piece.Material = material
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanTouch = false
		piece.CanQuery = false
		piece.CastShadow = shadow
		piece.Parent = parent
	end
end

function Scenery.LoadMesh(mesh: string, texture: string): MeshPart?
	if mesh == "" then
		return nil
	end
	local ok, result = pcall(function()
		-- Декорации без столкновений: простая коробка вместо точной формы, детализация по расстоянию
		return (AssetService :: any):CreateMeshPartAsync(Content.fromUri(mesh), {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Automatic,
		})
	end)
	if not ok or typeof(result) ~= "Instance" or not result:IsA("MeshPart") then
		warn(
			"Scenery: модель не загрузилась, ставлю простую фигуру",
			mesh
		)
		return nil
	end
	result.TextureID = texture
	result.Anchored = true
	result.CanCollide = false
	result.CanTouch = false
	result.CanQuery = false
	return result
end

-- Высота дна долины: до неё тянется скала под самой трассой
function Scenery.FloorY(track: Track.Data): number
	local lowest = math.huge
	for i = 1, track.count do
		lowest = math.min(lowest, track.pos[i].Y)
	end
	return lowest - S.FloorDepth
end

-- Сколько свободного места сбоку от трассы до другого её витка (в шпильках витки близко).
-- Соседом считается точка трассы, которая лежит сбоку, а не впереди или позади по ходу.
function Scenery.Clearance(
	track: Track.Data,
	s: number,
	edge: Vector3,
	outward: Vector3,
	along: Vector3
): number
	local best = math.huge
	for i = 1, track.count do
		local other = (i - 1) * track.step
		if math.abs(other - s) > S.NeighbourGuard then
			local pos = track.pos[i]
			local dx, dz = pos.X - edge.X, pos.Z - edge.Z
			local lateral = dx * outward.X + dz * outward.Z
			if lateral > 0 and lateral > math.abs(dx * along.X + dz * along.Z) then
				best = math.min(best, math.sqrt(dx * dx + dz * dz) - track.width[i] / 2)
			end
		end
	end
	return best
end

-- Снежный склон от края трассы вниз и скала под ним
-- Запасной вариант из блоков (основной строит TrackMesh)
function Scenery.ShoulderParts(parent: Instance, track: Track.Data): { Shoulder }
	local floorY = Scenery.FloorY(track)
	local shoulders: { Shoulder } = {}
	local span = V.SegmentSamples * track.step
	local index = 0
	for s = 0, track.length - span, span do
		index += 1
		local a = Track.At(track, s)
		local b = Track.At(track, s + span)
		local mid, _, right, width, kappa = Track.At(track, s + span / 2)
		local forward = (b - a).Unit
		local up = (-forward):Cross(right).Unit
		local frame = CFrame.fromMatrix((a + b) / 2, up:Cross(-forward), up, -forward)
		local flatRight = Vector3.new(right.X, 0, right.Z).Unit
		local flatForward = Vector3.new(forward.X, 0, forward.Z).Unit
		local stagger = (index % 2) * S.LayerStagger -- соседние блоки на разной глубине: не мерцают

		for _, side in { -1, 1 } do
			local outward = flatRight * side
			local free = Scenery.Clearance(
				track,
				s + span / 2,
				mid + right * (side * width / 2),
				outward,
				flatForward
			)
			local reach = math.clamp(free - S.NeighbourMargin, 0, S.ShoulderWidth)
			-- Внутри поворота склон не длиннее радиуса: иначе блоки проходят друг сквозь друга
			local inner = kappa * side > S.InnerKappa
			if inner then
				reach = math.min(reach, 1 / math.abs(kappa) - width / 2 + S.InnerOverlap)
			end
			if reach >= S.ShoulderMin then
				-- Снаружи поворота блоки расходятся веером: удлиняем только там
				local fan = math.max(0, -kappa * side)
				local length = (b - a).Magnitude * (1 + fan * (width / 2 + reach)) + S.Overlap
				local slope = frame
					* CFrame.new(side * width / 2, 0, 0)
					* CFrame.Angles(0, 0, -side * S.ShoulderSlope)
				local run = reach / math.cos(S.ShoulderSlope)
				block(
					parent,
					Vector3.new(run, S.ShoulderThickness, length),
					slope
						* CFrame.new(
							side * run / 2,
							-S.ShoulderThickness / 2 - S.ShoulderDrop - stagger,
							0
						),
					if index % 2 == 0 then S.SnowBankA else S.SnowBankB,
					Enum.Material.Snow
				)
				local edge = slope.Position
				local outer = (slope * CFrame.new(side * run, 0, 0)).Position
				table.insert(shoulders, {
					edge = edge,
					mid = edge:Lerp(outer, M.MidShare),
					outer = outer,
					width = run,
					weight = 1,
					s = s + span / 2,
					side = side,
				})

				-- Скала под склоном: только там, где до соседнего витка есть место
				-- (и не внутри поворота: там скалы соседних блоков торчали бы друг из друга)
				if
					not inner
					and free
						> reach + S.SkirtLength * math.cos(S.SkirtSlope) + S.NeighbourMargin
				then
					local skirt = slope
						* CFrame.new(side * run, -S.ShoulderDrop, 0)
						* CFrame.Angles(0, 0, -side * (S.SkirtSlope - S.ShoulderSlope))
					local top = skirt.Position.Y
					local drop = math.min(S.SkirtLength, (top - floorY) / math.sin(S.SkirtSlope))
					local reachOut = width / 2 + reach + drop * math.cos(S.SkirtSlope)
					block(
						parent,
						Vector3.new(
							drop,
							S.SkirtThickness,
							(b - a).Magnitude * (1 + fan * reachOut) + S.Overlap
						),
						skirt * CFrame.new(side * drop / 2, -S.SkirtThickness / 2 - stagger, 0),
						if (index + side) % 3 == 0 then S.RockB else S.RockA,
						Enum.Material.Slate
					)
				end
			end
		end
	end
	return shoulders
end

-- Середина долины и расстояние от неё до самой дальней точки трассы
function Scenery.Bounds(track: Track.Data): (Vector3, number)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for i = 1, track.count do
		local pos = track.pos[i]
		minX, maxX = math.min(minX, pos.X), math.max(maxX, pos.X)
		minZ, maxZ = math.min(minZ, pos.Z), math.max(maxZ, pos.Z)
	end
	local centre = Vector3.new((minX + maxX) / 2, Scenery.FloorY(track), (minZ + maxZ) / 2)
	local radius = 0
	for i = 1, track.count do
		local pos = track.pos[i]
		radius = math.max(radius, math.sqrt((pos.X - centre.X) ^ 2 + (pos.Z - centre.Z) ^ 2))
	end
	return centre, radius
end

local function buildFloor(parent: Instance, track: Track.Data)
	local centre, radius = Scenery.Bounds(track)
	local floorY = centre.Y
	local half = math.ceil((radius + S.FloorMargin) / S.FloorTile)
	for ix = -half, half - 1 do
		for iz = -half, half - 1 do
			block(
				parent,
				Vector3.new(S.FloorTile, S.FloorThickness, S.FloorTile),
				CFrame.new(
					centre.X + (ix + 0.5) * S.FloorTile,
					floorY - S.FloorThickness / 2,
					centre.Z + (iz + 0.5) * S.FloorTile
				),
				S.FloorColor,
				Enum.Material.Snow
			)
		end
	end
end

-- Дальние вершины из клиньев: запасной вариант (основной строит Peaks)
function Scenery.PeakParts(parent: Instance, track: Track.Data)
	local centre, radius = Scenery.Bounds(track)
	local random = Random.new(S.Seed)
	for i = 1, S.PeakCount do
		local angle = (i + random:NextNumber(-0.3, 0.3)) / S.PeakCount * math.pi * 2
		local distance = radius + random:NextNumber(S.PeakDistanceMin, S.PeakDistanceMax)
		local width = random:NextNumber(S.PeakWidthMin, S.PeakWidthMax)
		local height = random:NextNumber(S.PeakHeightMin, S.PeakHeightMax)
		local base = CFrame.new(
			centre.X + math.cos(angle) * distance,
			centre.Y,
			centre.Z + math.sin(angle) * distance
		) * CFrame.Angles(0, random:NextNumber(0, math.pi / 2), 0)
		pyramid(parent, base, width, height, S.PeakRock, Enum.Material.Slate, false)
		local cap = S.PeakCap
		pyramid(
			parent,
			base * CFrame.new(0, height * (1 - cap) + S.PeakCapLift, 0),
			width * cap * S.PeakCapWiden,
			height * cap,
			S.PeakSnow,
			Enum.Material.Snow,
			false
		)
	end
end

local function buildTrees(
	parent: Instance,
	track: Track.Data,
	random: Random,
	shoulders: { Shoulder },
	avoid: { Vector3 }
): { string }
	-- Рядом с йети ничего не растёт: его не должно закрывать
	local function free(at: CFrame): boolean
		for _, point in avoid do
			if (point - at.Position).Magnitude < Y.Clear then
				return false
			end
		end
		return true
	end

	local propEntries: { string } = {}
	local pineAsset = SledConfig.Assets.Pine
	local rockAsset = SledConfig.Assets.Rock
	local pine = Scenery.LoadMesh(pineAsset.mesh, pineAsset.texture)
	local rock = Scenery.LoadMesh(rockAsset.mesh, rockAsset.texture)

	for _, shoulder in shoulders do
		if shoulder.width >= S.TreeMinShoulder then
			local _, _, _, trackW = Track.At(track, shoulder.s)

			-- Точка на склоне: от края трассы наружу
			local function spot(): (CFrame, number)
				local out = random:NextNumber(S.TreeEdgeGap, shoulder.width - S.TreeOuterGap)
				local share = out / shoulder.width
				local point = if share < M.MidShare
					then shoulder.edge:Lerp(shoulder.mid, share / M.MidShare)
					else shoulder.mid:Lerp(
						shoulder.outer,
						(share - M.MidShare) / (1 - M.MidShare)
					)
				return CFrame.new(point) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0),
					out
			end

			if random:NextNumber() < S.TreeChance * shoulder.weight then
				local scale = random:NextNumber(S.TreeScaleMin, S.TreeScaleMax)
				local at, out = spot()
				if not free(at) then
					continue
				end
				if pine then
					local tree = pine:Clone()
					tree.Size *= pineAsset.height * scale / tree.Size.Y
					tree.CFrame = at * CFrame.new(0, tree.Size.Y / 2 - S.TreeSink, 0)
					tree.CastShadow = S.TreeShadows
					tree.Parent = parent
				else
					local height = V.PineHeight * scale
					local width = V.PineWidth * scale
					block(
						parent,
						Vector3.new(width / 5, height / 4, width / 5),
						at * CFrame.new(0, height / 8 - S.TreeSink, 0),
						V.Trunk,
						Enum.Material.Wood
					)
					pyramid(
						parent,
						at * CFrame.new(0, height / 4 - S.TreeSink, 0),
						width,
						height,
						V.Pine,
						Enum.Material.SmoothPlastic,
						true
					)
				end
				local d = shoulder.side * (trackW / 2 + out)
				local radius = SledConfig.Obstacles.Tree.radius * scale
				table.insert(propEntries, string.format("%.1f,%.1f,%.1f,T", shoulder.s, d, radius))
			end

			if random:NextNumber() < S.RockChance * shoulder.weight then
				local scale = random:NextNumber(S.RockScaleMin, S.RockScaleMax)
				local at, out = spot()
				if not free(at) then
					continue
				end
				if rock then
					local boulder = rock:Clone()
					boulder.Size *= rockAsset.width * scale / math.max(
						boulder.Size.X,
						boulder.Size.Z
					)
					boulder.CFrame = at * CFrame.new(0, boulder.Size.Y / 2 - S.RockSink * scale, 0)
					boulder.CastShadow = S.RockShadows
					boulder.Parent = parent
				else
					local size = rockAsset.width * scale
					block(
						parent,
						Vector3.new(size, size * S.RockBlockHeight, size * S.RockBlockDepth),
						at * CFrame.new(0, size * S.RockBlockHeight / 2 - S.RockSink * scale, 0),
						S.RockA,
						Enum.Material.Slate,
						true
					)
				end
				local d = shoulder.side * (trackW / 2 + out)
				local radius = SledConfig.Obstacles.Rock.radius * scale
				table.insert(propEntries, string.format("%.1f,%.1f,%.1f,R", shoulder.s, d, radius))
			end
		end
	end

	return propEntries
end

local function applyLighting()
	Lighting.ClockTime = S.ClockTime
	Lighting.GeographicLatitude = S.Latitude
	Lighting.Brightness = S.Brightness
	Lighting.Ambient = S.Ambient
	Lighting.OutdoorAmbient = S.OutdoorAmbient
	Lighting.ColorShift_Top = S.SunTint
	Lighting.ShadowSoftness = S.ShadowSoftness
	Lighting.EnvironmentDiffuseScale = S.EnvironmentDiffuse
	Lighting.EnvironmentSpecularScale = S.EnvironmentSpecular
	Lighting.ExposureCompensation = S.Exposure

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = S.FogDensity
	atmosphere.Offset = S.FogOffset
	atmosphere.Color = S.FogColor
	atmosphere.Decay = S.FogDecay
	atmosphere.Glare = S.FogGlare
	atmosphere.Haze = S.FogHaze
	atmosphere.Parent = Lighting

	local colour = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
		or Instance.new("ColorCorrectionEffect")
	colour.Saturation = S.Saturation
	colour.Contrast = S.Contrast
	colour.TintColor = S.Tint
	colour.Parent = Lighting

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = S.BloomIntensity
	bloom.Size = S.BloomSize
	bloom.Threshold = S.BloomThreshold
	bloom.Parent = Lighting

	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect") or Instance.new("SunRaysEffect")
	rays.Intensity = S.SunRays
	rays.Spread = S.SunRaysSpread
	rays.Parent = Lighting

	local terrain = Workspace.Terrain
	local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = S.CloudCover
	clouds.Density = S.CloudDensity
	clouds.Color = S.CloudColor
	clouds.Parent = terrain
end

-- Ближайший к точке s склон с нужной стороны, на котором хватает места
local function shoulderNear(
	shoulders: { Shoulder },
	s: number,
	side: number,
	minWidth: number,
	reach: number
): Shoulder?
	local best: Shoulder? = nil
	local bestGap = reach
	for _, shoulder in shoulders do
		local gap = math.abs(shoulder.s - s)
		if shoulder.side == side and shoulder.width >= minWidth and gap <= bestGap then
			best = shoulder
			bestGap = gap
		end
	end
	return best
end

-- Точка на склоне на расстоянии out от края трассы
local function onShoulder(shoulder: Shoulder, out: number): Vector3
	local share = math.clamp(out / shoulder.width, 0, 1)
	if share < M.MidShare then
		return shoulder.edge:Lerp(shoulder.mid, share / M.MidShare)
	end
	return shoulder.mid:Lerp(shoulder.outer, (share - M.MidShare) / (1 - M.MidShare))
end

-- Указатели поворота: щиты со стрелками на внешней стороне дуги, лицом к едущему. Без текста.
local function buildSigns(parent: Instance, track: Track.Data, shoulders: { Shoulder })
	for s = G.Every, track.finishS, G.Every do
		local _, _, _, _, kappa = Track.At(track, s)
		if math.abs(kappa) >= G.Kappa then
			local turn = math.sign(kappa) -- 1: поворот вправо, щит стоит слева
			local shoulder = shoulderNear(shoulders, s, -turn, G.MinShoulder, G.Every / 2)
			if shoulder then
				-- Щит стоит лицом к едущему в той точке, где он на самом деле стоит
				local _, tangent = Track.At(track, shoulder.s)
				local forward = Vector3.new(tangent.X, 0, tangent.Z).Unit
				local right = forward:Cross(Vector3.yAxis)
				local foot = onShoulder(shoulder, G.Offset)
				-- X щита смотрит вправо от едущего, Z на него самого
				local frame = CFrame.fromMatrix(foot, right, Vector3.yAxis)
				local tall = G.PostHeight + G.Sink
				block(
					parent,
					Vector3.new(G.Post, tall, G.Post),
					frame * CFrame.new(0, tall / 2 - G.Sink, 0),
					G.PostColor,
					Enum.Material.SmoothPlastic
				)
				local centre = frame * CFrame.new(0, G.PostHeight + G.Board.Y / 2, 0)
				local sharp = math.abs(kappa) >= V.BrakeKappa
				block(
					parent,
					G.Board,
					centre,
					if sharp then G.BoardSharp else G.BoardColor,
					Enum.Material.SmoothPlastic
				)
				-- Стрелка из двух планок: остриё смотрит в сторону поворота
				local angle = math.atan2(G.ArrowRise, G.ArrowRun)
				local length = math.sqrt(G.ArrowRise ^ 2 + G.ArrowRun ^ 2)
				for index = 1, G.Arrows do
					local x = (index - (G.Arrows + 1) / 2) * G.ArrowGap
					for _, half in { -1, 1 } do
						block(
							parent,
							Vector3.new(length, G.ArrowThick, G.ArrowDepth),
							centre
								* CFrame.new(x, half * G.ArrowRise / 2, G.Board.Z / 2)
								* CFrame.Angles(0, 0, -half * turn * angle),
							G.ArrowColor,
							Enum.Material.SmoothPlastic
						)
					end
				end
			end
		end
	end
end

-- Йети у трассы: стоят на склонах и смотрят на проезжающих
local function buildYetis(parent: Instance, track: Track.Data, shoulders: { Shoulder }): { Vector3 }
	local placed: { Vector3 } = {}
	local asset = SledConfig.Assets.Yeti
	local yeti = Scenery.LoadMesh(asset.mesh, asset.texture)
	if not yeti then
		return placed
	end
	for index, share in Y.At do
		local s = track.finishS * share
		local side = if index % 2 == 0 then 1 else -1
		local shoulder = shoulderNear(shoulders, s, side, Y.MinShoulder, Y.Search)
			or shoulderNear(shoulders, s, -side, Y.MinShoulder, Y.Search)
		if shoulder then
			local foot = onShoulder(shoulder, Y.Offset)
			local toTrack = shoulder.edge - foot
			local figure = yeti:Clone()
			figure.Name = "Yeti"
			figure.Size *= asset.height * Y.Scale / figure.Size.Y
			figure.CFrame = CFrame.lookAlong(
				foot + Vector3.yAxis * (figure.Size.Y / 2 - Y.Sink),
				Vector3.new(toTrack.X, 0, toTrack.Z)
			) * CFrame.Angles(0, math.rad(asset.yaw), 0)
			figure.CastShadow = true
			figure.Parent = parent
			table.insert(placed, foot)
		end
	end
	return placed
end

-- Всё вокруг, что строится сразу, без ожидания сети (без флажков/бортиков по обочинам — только знаки на опасных поворотах)
function Scenery.Build(parent: Instance, track: Track.Data, _colorAt: (number) -> Color3)
	buildFloor(parent, track)
	applyLighting()
end

-- Лес и валуны. Ждёт загрузки моделей из сети, поэтому вызывается после того, как гора и
-- точка появления уже в мире.
function Scenery.Plant(parent: Instance, track: Track.Data, all: { Shoulder })
	-- Склоны под сводами пещер пустые: ель проткнула бы стену
	local shoulders: { Shoulder } = {}
	for _, shoulder in all do
		if Track.CaveDepth(track, shoulder.s) < -S.CaveGuard then
			table.insert(shoulders, shoulder)
		end
	end
	local signs = Instance.new("Model")
	signs.Name = "Signs"
	buildSigns(signs, track, shoulders)
	signs.Parent = parent

	local forest = Instance.new("Model")
	forest.Name = "Forest"
	local yetis = buildYetis(forest, track, shoulders)
	local propEntries = buildTrees(forest, track, Random.new(S.Seed + 1), shoulders, yetis)
	forest.Parent = parent

	local existing = ReplicatedStorage:FindFirstChild("TrackProps")
	local propsVal = if existing and existing:IsA("StringValue")
		then existing
		else Instance.new("StringValue")
	propsVal.Name = "TrackProps"
	propsVal.Value = table.concat(propEntries, ";")
	propsVal.Parent = ReplicatedStorage
end

return Scenery
