--!strict
-- TrackMesh: полотно, цветные края, снежные склоны и скалы одной гладкой поверхностью вместо
-- блоков. Сервер строит сетку по линии трассы и превращает её в обычные детали, которые видят
-- все игроки. Если движок не дал построить сетку, Build возвращает nil и гора собирается из блоков.
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SledConfig = require(ReplicatedStorage.SledConfig)
local Track = require(ReplicatedStorage.Track)
local Scenery = require(ServerScriptService.Scenery)

local V = SledConfig.Visual
local S = SledConfig.Scenery
local M = SledConfig.Mesh

local TrackMesh = {}

-- Точки и грани копятся в мировых координатах; сетка создаётся в конце, когда известен центр куска
type Builder = {
	points: { Vector3 },
	faces: { number }, -- по четыре числа на грань: три точки и номер цвета
	palette: { Color3 },
	colors: { [string]: number },
	low: Vector3,
	high: Vector3,
}

-- Поперечное сечение горы в одной точке трассы. Точки каждой полосы идут слева направо.
type Ring = {
	s: number,
	surface: { Vector3 },
	edges: { { Vector3 } }, -- [1] левый край, [2] правый
	shoulders: { { Vector3 }? },
	skirts: { { Vector3 }? },
	reach: { number },
}

local function newBuilder(): Builder
	return {
		points = {},
		faces = {},
		palette = {},
		colors = {},
		low = Vector3.one * math.huge,
		high = Vector3.one * -math.huge,
	}
end

local function colorIndex(builder: Builder, color: Color3): number
	local key = color:ToHex()
	local index = builder.colors[key]
	if not index then
		table.insert(builder.palette, color)
		index = #builder.palette
		builder.colors[key] = index
	end
	return index
end

local function point(builder: Builder, position: Vector3): number
	table.insert(builder.points, position)
	builder.low = builder.low:Min(position)
	builder.high = builder.high:Max(position)
	return #builder.points
end

-- Полоса между двумя сечениями. Точки обоих сечений идут слева направо, лицевая сторона сверху.
local function strip(
	builder: Builder,
	back: { Vector3 },
	front: { Vector3 },
	colorOf: (column: number) -> Color3
)
	local backIds = table.create(#back)
	local frontIds = table.create(#front)
	for i, position in back do
		backIds[i] = point(builder, position)
	end
	for i, position in front do
		frontIds[i] = point(builder, position)
	end
	local faces = builder.faces
	for column = 1, #back - 1 do
		local color = colorIndex(builder, colorOf(column))
		local a, b = backIds[column], backIds[column + 1]
		local c, d = frontIds[column + 1], frontIds[column]
		table.move({ a, b, c, color, a, c, d, color }, 1, 8, #faces + 1, faces)
	end
end

-- Превратить накопленное в деталь, которую получат клиенты. false = движок не дал построить сетку.
local function finish(
	builder: Builder,
	parent: Instance,
	name: string,
	material: Enum.Material
): boolean
	if #builder.faces == 0 then
		return true
	end
	-- Точки сетки считаем от центра куска: деталь встаёт в этот центр
	local centre = (builder.low + builder.high) / 2
	local mesh: EditableMesh? = nil
	local ok, part = pcall(function(): MeshPart?
		local created = AssetService:CreateEditableMesh()
		if not created then
			return nil
		end
		mesh = created
		local ids = table.create(#builder.points)
		for i, position in builder.points do
			ids[i] = created:AddVertex(position - centre)
		end
		local colors = table.create(#builder.palette)
		for i, color in builder.palette do
			colors[i] = created:AddColor(color, 1)
		end
		local faces = builder.faces
		for i = 1, #faces, 4 do
			local face = created:AddTriangle(ids[faces[i]], ids[faces[i + 1]], ids[faces[i + 2]])
			local color = colors[faces[i + 3]]
			created:SetFaceColors(face, { color, color, color })
		end
		-- Превращаем сетку в обычное содержимое: его получают клиенты
		local result, content = (AssetService :: any):CreateDataModelContentAsync(
			Content.fromObject(created)
		)
		if result ~= Enum.CreateContentResult.Success or not content then
			error("CreateDataModelContentAsync: " .. tostring(result))
		end
		return (AssetService :: any):CreateMeshPartAsync(content, {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Precise,
		})
	end)
	if mesh then
		(mesh :: EditableMesh):Destroy()
	end
	if not ok or typeof(part) ~= "Instance" or not part:IsA("MeshPart") then
		warn(
			"TrackMesh: сетка не создалась",
			name,
			if ok then "" else tostring(part)
		)
		return false
	end
	part.Name = name
	part.Material = material
	part.Color = Color3.new(1, 1, 1)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.CFrame = CFrame.new(centre)
	part.Parent = parent
	return true
end

local function noise(s: number, lane: number): number
	return math.clamp(math.noise(s * M.NoiseScale, lane * M.NoiseLane, S.Seed) * 2, -1, 1)
end

-- Сколько места есть под склон с каждой стороны, сглаженно вдоль трассы
local function measure(track: Track.Data, count: number): ({ { number } }, { { boolean } })
	local raw: { { number } } = table.create(count)
	local room: { { boolean } } = table.create(count)
	local skirtRun = S.SkirtLength * math.cos(S.SkirtSlope)
	for r = 1, count do
		local s = (r - 1) * M.RingStep
		local pos, tangent, right, width, kappa = Track.At(track, s)
		local flatRight = Vector3.new(right.X, 0, right.Z).Unit
		local flatForward = Vector3.new(tangent.X, 0, tangent.Z).Unit
		raw[r] = table.create(2, 0)
		room[r] = table.create(2, false)
		for index, side in { -1, 1 } do
			local edge = pos + right * (side * width / 2)
			local free = Scenery.Clearance(track, s, edge, flatRight * side, flatForward)
			local reach = math.clamp(free - S.NeighbourMargin, 0, S.ShoulderWidth)
			local inner = kappa * side > S.InnerKappa
			if inner then
				reach = math.min(reach, 1 / math.abs(kappa) - width / 2 - M.InnerGap)
			end
			raw[r][index] = math.max(reach, 0)
			room[r][index] = not inner and free > reach + skirtRun + S.NeighbourMargin
		end
	end

	-- Сначала берём самое узкое место рядом, потом усредняем: склон не дёргается и никуда не залезает
	local reach: { { number } } = table.create(count)
	local skirt: { { boolean } } = table.create(count)
	local spread = M.ReachSmooth
	for r = 1, count do
		reach[r] = table.create(2, 0)
		skirt[r] = table.create(2, false)
		for index = 1, 2 do
			local sum = 0
			local all = true
			for k = r - spread, r + spread do
				local narrow = math.huge
				for j = k - spread, k + spread do
					narrow = math.min(narrow, raw[math.clamp(j, 1, count)][index])
				end
				sum += narrow
				all = all and room[math.clamp(k, 1, count)][index]
			end
			local value = sum / (spread * 2 + 1)
			reach[r][index] = if value >= S.ShoulderMin then value else 0
			skirt[r][index] = all and reach[r][index] > 0
		end
	end
	return reach, skirt
end

local function buildRing(
	track: Track.Data,
	s: number,
	reach: { number },
	skirt: { boolean },
	floorY: number
): Ring
	local pos, tangent, right, width = Track.At(track, s)
	local up = right:Cross(tangent).Unit
	local flatRight = Vector3.new(right.X, 0, right.Z).Unit

	local surface = table.create(M.Columns + 1)
	for column = 0, M.Columns do
		surface[column + 1] = pos + right * (width * (column / M.Columns - 0.5))
	end

	local ring: Ring = {
		s = s,
		surface = surface,
		edges = {},
		shoulders = {},
		skirts = {},
		reach = { 0, 0 },
	}
	for index, side in { -1, 1 } do
		local base = pos + right * (side * width / 2)
		local top = base + up * V.EdgeHeight
		local inner = pos + right * (side * (width / 2 - V.EdgeWidth)) + up * M.EdgeInnerLift
		ring.edges[index] = if side < 0 then { base, top, inner } else { inner, top, base }

		local wide = reach[index]
		if wide > 0 then
			local outward = flatRight * side
			-- Неровность только сужает склон: шире разрешённого он не станет
			wide *= 1 - M.ShoulderNoise * (0.5 + 0.5 * noise(s, side))
			local near = wide * M.MidShare
			local start = base
			-- Бугор не выше, чем склон успел опуститься: он не закрывает цветной край
			local drop = near * math.tan(M.NearSlope)
			local bump = math.min(M.ShoulderBump, drop) * noise(s, side * M.NoiseLane)
			local mid = start + outward * near - Vector3.yAxis * (drop - bump)
			local outer = mid
				+ outward * (wide - near)
				- Vector3.yAxis * ((wide - near) * math.tan(S.ShoulderSlope))
			ring.shoulders[index] = if side < 0
				then { outer, mid, start }
				else { start, mid, outer }
			ring.reach[index] = wide

			if skirt[index] then
				local length = math.min(S.SkirtLength, (outer.Y - floorY) / math.sin(S.SkirtSlope))
				local run = length * math.cos(S.SkirtSlope)
				local fall = length * math.sin(S.SkirtSlope)
				local half = outer
					+ outward * (run * M.SkirtMidShare + M.SkirtJitter * noise(s, side * 3))
					- Vector3.yAxis * (fall * M.SkirtMidShare)
				local bottom = outer
					+ outward * (run + M.SkirtJitter * noise(s, side * 4))
					- Vector3.yAxis * fall
				ring.skirts[index] = if side < 0
					then { bottom, half, outer }
					else { outer, half, bottom }
			end
		end
	end
	return ring
end

local function shade(a: Color3, b: Color3, s: number, lane: number): Color3
	-- Несколько ступеней оттенка: грани читаются, а цветов в сетке немного
	local t = math.round((noise(s * M.ShadeStretch, lane) * 0.5 + 0.5) * M.ShadeSteps)
		/ M.ShadeSteps
	return a:Lerp(b, t)
end

-- Построить гору сеткой. Возвращает склоны для посадки леса или nil, если сетку построить нельзя.
function TrackMesh.Build(
	parent: Instance,
	track: Track.Data,
	colorAt: (number) -> Color3
): { Scenery.Shoulder }?
	local floorY = Scenery.FloorY(track)
	local count = math.floor(track.length / M.RingStep) + 1
	local reach, skirt = measure(track, count)

	local holder = Instance.new("Model")
	holder.Name = "Surface"
	local shoulders: { Scenery.Shoulder } = {}
	local weight = M.RingStep / (V.SegmentSamples * track.step)

	local first = 1
	local chunk = 0
	local previous: Ring? = nil
	while first < count do
		chunk += 1
		local last = math.min(first + M.ChunkRings, count)
		local snow = newBuilder()
		local paint = newBuilder()
		local rock = newBuilder()

		for r = first, last do
			local ring = buildRing(track, (r - 1) * M.RingStep, reach[r], skirt[r], floorY)
			if r > first and previous then
				local back = previous
				local middle = (back.s + ring.s) / 2
				local stripe = math.floor(back.s / M.StripeLength) % 2 == 0
				strip(snow, back.surface, ring.surface, function()
					return if stripe then V.SnowA else V.SnowB
				end)
				local edge = colorAt(middle)
				for index = 1, 2 do
					strip(paint, back.edges[index], ring.edges[index], function()
						return edge
					end)
					local backShoulder, frontShoulder = back.shoulders[index], ring.shoulders[index]
					if backShoulder and frontShoulder then
						strip(snow, backShoulder, frontShoulder, function(column)
							return shade(S.SnowBankA, S.SnowBankB, middle, index * 10 + column)
						end)
					end
					local backSkirt, frontSkirt = back.skirts[index], ring.skirts[index]
					if backSkirt and frontSkirt then
						strip(rock, backSkirt, frontSkirt, function(column)
							return shade(S.RockA, S.RockB, middle, index * 20 + column)
						end)
					end
				end
			end
			if r < last or last == count then
				for index, side in { -1, 1 } do
					local points = ring.shoulders[index]
					if points then
						table.insert(shoulders, {
							edge = if side < 0 then points[3] else points[1],
							mid = points[2],
							outer = if side < 0 then points[1] else points[3],
							width = ring.reach[index],
							weight = weight,
						})
					end
				end
			end
			previous = ring
		end

		local ok = finish(snow, holder, "Snow" .. chunk, Enum.Material.Snow)
		ok = finish(paint, holder, "Edge" .. chunk, Enum.Material.SmoothPlastic) and ok
		ok = finish(rock, holder, "Rock" .. chunk, Enum.Material.Slate) and ok
		if not ok then
			warn("TrackMesh: гора будет из блоков")
			holder:Destroy()
			return nil
		end
		first = last
	end

	holder.Parent = parent
	return shoulders
end

return TrackMesh
