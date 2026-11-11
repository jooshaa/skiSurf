--!strict
-- MeshBuilder: собирает сетку из точек и цветных граней и превращает её в обычную деталь,
-- которую сервер передаёт всем игрокам. Общий инструмент для трассы и дальних гор.
local AssetService = game:GetService("AssetService")

local MeshBuilder = {}

-- Точки и грани копятся в мировых координатах; сетка создаётся в конце, когда известен центр куска
export type Builder = {
	points: { Vector3 },
	faces: { number }, -- по четыре числа на грань: три точки и номер цвета
	palette: { Color3 },
	colors: { [string]: number },
	low: Vector3,
	high: Vector3,
}

function MeshBuilder.New(): Builder
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
function MeshBuilder.Strip(
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

-- Отдельный треугольник со своими точками: грань получается плоской, без сглаживания с соседями.
-- Точки против часовой стрелки, если смотреть на лицевую сторону.
function MeshBuilder.Triangle(builder: Builder, a: Vector3, b: Vector3, c: Vector3, color: Color3)
	local faces = builder.faces
	table.move(
		{ point(builder, a), point(builder, b), point(builder, c), colorIndex(builder, color) },
		1,
		4,
		#faces + 1,
		faces
	)
end

-- Превратить накопленное в деталь, которую получат клиенты. nil = движок не дал построить сетку.
-- Деталь возвращается без родителя, стоящей в центре своей сетки.
function MeshBuilder.Create(builder: Builder, name: string, material: Enum.Material): MeshPart?
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
			"MeshBuilder: сетка не создалась",
			name,
			if ok then "" else tostring(part)
		)
		return nil
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
	return part
end

-- То же, но сразу в мир. Пустая сетка не ошибка. false = движок не дал построить сетку.
function MeshBuilder.Finish(
	builder: Builder,
	parent: Instance,
	name: string,
	material: Enum.Material
): boolean
	if #builder.faces == 0 then
		return true
	end
	local part = MeshBuilder.Create(builder, name, material)
	if not part then
		return false
	end
	part.Parent = parent
	return true
end

return MeshBuilder
