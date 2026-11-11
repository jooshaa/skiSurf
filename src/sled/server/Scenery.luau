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

local Scenery = {}

export type Shoulder = { frame: CFrame, width: number, side: number }

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

local function loadMesh(mesh: string, texture: string): MeshPart?
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

-- Сколько свободного места сбоку от трассы до другого её витка (в шпильках витки близко).
-- Соседом считается точка трассы, которая лежит сбоку, а не впереди или позади по ходу.
local function clearance(
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
local function buildShoulders(parent: Instance, track: Track.Data, floorY: number): { Shoulder }
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
			local free = clearance(
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
				table.insert(shoulders, { frame = slope, width = run, side = side })

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

local function buildFloor(parent: Instance, track: Track.Data, floorY: number): (Vector3, number)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for i = 1, track.count do
		local pos = track.pos[i]
		minX, maxX = math.min(minX, pos.X), math.max(maxX, pos.X)
		minZ, maxZ = math.min(minZ, pos.Z), math.max(maxZ, pos.Z)
	end
	local centre = Vector3.new((minX + maxX) / 2, floorY, (minZ + maxZ) / 2)
	local radius = math.max(maxX - minX, maxZ - minZ) / 2
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
	return centre, radius
end

-- Дальние вершины кольцом вокруг долины: тёмная скала и снежная шапка
local function buildPeaks(parent: Instance, random: Random, centre: Vector3, radius: number)
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

local function buildTrees(parent: Instance, random: Random, shoulders: { Shoulder })
	local pineAsset = SledConfig.Assets.Pine
	local rockAsset = SledConfig.Assets.Rock
	local pine = loadMesh(pineAsset.mesh, pineAsset.texture)
	local rock = loadMesh(rockAsset.mesh, rockAsset.texture)

	for _, shoulder in shoulders do
		if shoulder.width >= S.TreeMinShoulder then
			-- Точка на склоне: от края трассы наружу
			local function spot(): CFrame
				local out = random:NextNumber(S.TreeEdgeGap, shoulder.width - S.TreeOuterGap)
				local point = (shoulder.frame * CFrame.new(shoulder.side * out, 0, 0)).Position
				return CFrame.new(point) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
			end

			if random:NextNumber() < S.TreeChance then
				local scale = random:NextNumber(S.TreeScaleMin, S.TreeScaleMax)
				local at = spot()
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
			end

			if random:NextNumber() < S.RockChance then
				local scale = random:NextNumber(S.RockScaleMin, S.RockScaleMax)
				local at = spot()
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
			end
		end
	end
end

-- Флажки вдоль краёв того же цвета, что и край: мимо них читается скорость
local function buildFlags(parent: Instance, track: Track.Data, colorAt: (number) -> Color3)
	for s = S.FlagEvery, track.length - S.FlagEvery, S.FlagEvery do
		local _, _, _, width = Track.At(track, s)
		local frame = Track.Frame(track, s, 0)
		local color = colorAt(s)
		for _, side in { -1, 1 } do
			local foot = frame * CFrame.new(side * (width / 2 + S.FlagOffset), 0, 0)
			-- Столбик стоит вертикально, как бы ни была наклонена трасса, и уходит в снег
			local look = frame.LookVector
			local upright = CFrame.lookAlong(
				foot.Position - Vector3.yAxis * S.FlagSink,
				Vector3.new(look.X, 0, look.Z)
			)
			block(
				parent,
				Vector3.new(S.FlagPole, S.FlagHeight + S.FlagSink, S.FlagPole),
				upright * CFrame.new(0, (S.FlagHeight + S.FlagSink) / 2, 0),
				S.FlagPoleColor,
				Enum.Material.SmoothPlastic
			)
			block(
				parent,
				Vector3.new(S.FlagPole / 2, S.FlagSize.Y, S.FlagSize.X),
				upright
					* CFrame.new(0, S.FlagSink + S.FlagHeight - S.FlagSize.Y / 2, S.FlagSize.X / 2),
				color,
				Enum.Material.SmoothPlastic
			)
		end
	end
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

-- Высота дна долины: до неё тянется скала под самой трассой
function Scenery.FloorY(track: Track.Data): number
	local lowest = math.huge
	for i = 1, track.count do
		lowest = math.min(lowest, track.pos[i].Y)
	end
	return lowest - S.FloorDepth
end

-- Всё, что строится сразу, без ожидания сети. Возвращает склоны для Scenery.Plant.
function Scenery.Build(
	parent: Instance,
	track: Track.Data,
	colorAt: (number) -> Color3
): { Shoulder }
	local floorY = Scenery.FloorY(track)
	local shoulders = buildShoulders(parent, track, floorY)
	local centre, radius = buildFloor(parent, track, floorY)
	buildPeaks(parent, Random.new(S.Seed), centre, radius)
	buildFlags(parent, track, colorAt)
	applyLighting()
	return shoulders
end

-- Лес и валуны. Ждёт загрузки моделей из сети, поэтому вызывается после того, как гора и
-- точка появления уже в мире.
function Scenery.Plant(parent: Instance, shoulders: { Shoulder })
	local forest = Instance.new("Model")
	forest.Name = "Forest"
	buildTrees(forest, Random.new(S.Seed + 1), shoulders)
	forest.Parent = parent
end

return Scenery
