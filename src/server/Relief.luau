--!strict
-- Relief: рельеф карты. Высота считается формулой (шум + плоские зоны + горы по краю), по ней
-- сервер один раз при старте заполняет Terrain. Плоскими остаются площадь с мастерскими и озеро,
-- вокруг холмы, по границе карты горы. Тропинки рисуются материалом и идут по рельефу.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Config)

local M = Config.Map

local RESOLUTION = 4 -- размер ячейки Terrain, задан движком

local Relief = {}

local function smooth(t: number): number
	local clamped = math.clamp(t, 0, 1)
	return clamped * clamped * (3 - 2 * clamped)
end

-- Расстояние от точки до прямоугольника района (0 внутри)
local function rectDistance(x: number, z: number, district: Config.District): number
	local dx = math.max(math.abs(x - district.center.X) - district.size.X / 2, 0)
	local dz = math.max(math.abs(z - district.center.Z) - district.size.Y / 2, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- Расстояние до границы игровой зоны: больше нуля внутри, меньше нуля снаружи
function Relief.EdgeDistance(x: number, z: number): number
	return math.min(x - M.MinX, M.MaxX - x, z - M.MinZ, M.MaxZ - z)
end

-- Высота земли в точке (студов над нулём, не ниже нуля)
function Relief.Height(x: number, z: number): number
	local radius = math.sqrt(x * x + z * z)
	local flat = smooth((radius - M.FlatRadius) / M.FlatBlend)
	for _, district in Config.Districts do
		if district.ice then
			local shore = rectDistance(x, z, district) - M.LakeShore
			flat = math.min(flat, smooth(shore / M.LakeBlend))
		end
	end

	local height = 0
	if flat > 0 then
		local hill = math.clamp(math.noise(x / M.HillScale, z / M.HillScale, M.Seed) + 0.5, 0, 1)
		local detail =
			math.clamp(math.noise(x / M.DetailScale, z / M.DetailScale, M.Seed + 7) + 0.5, 0, 1)
		height = flat * (hill * M.HillHeight + detail * M.DetailHeight)
	end

	local mountain = smooth((M.MountainStart - Relief.EdgeDistance(x, z)) / M.MountainWidth)
	if mountain > 0 then
		local ridge = math.clamp(
			math.noise(x / M.MountainScale, z / M.MountainScale, M.Seed + 19) + 0.5,
			0,
			1
		)
		height += mountain ^ M.MountainPower * M.MountainHeight * (M.MountainRidgeMin + ridge * (M.MountainRidgeMax - M.MountainRidgeMin))
	end
	return height
end

-- Лежит ли точка на тропинке (лучи от площади по четырём сторонам, кольцо вокруг мастерских)
function Relief.IsPath(x: number, z: number): boolean
	local half = M.PathWidth / 2
	local radius = math.sqrt(x * x + z * z)
	if radius < Config.World.PlazaRadius then
		return false
	end
	if math.abs(radius - M.RingRadius) < half then
		return true
	end
	if math.abs(x) < half then
		-- Северная тропа длиннее: она доходит до ворот парка
		if z < 0 and z > -M.NorthPathLength then
			return true
		end
		if z > 0 and z < M.PathLength then
			return true
		end
	end
	return math.abs(z) < half and math.abs(x) < M.PathLength
end

local function materialAt(x: number, z: number, height: number): Enum.Material
	if math.sqrt(x * x + z * z) < Config.World.PlazaRadius then
		return Enum.Material.Cobblestone
	end
	if Relief.IsPath(x, z) then
		return Enum.Material.Pavement
	end
	if height > M.RockMinHeight then
		local slope = math.abs(Relief.Height(x + RESOLUTION, z) - height)
			+ math.abs(Relief.Height(x, z + RESOLUTION) - height)
		if slope > M.RockSlope then
			return Enum.Material.Rock
		end
		if height > M.GlacierHeight then
			return Enum.Material.Glacier
		end
	end
	return Enum.Material.Snow
end

-- Заполнить Terrain по формуле высоты. Пишем кусками, высота куска по его самой высокой точке.
function Relief.Build()
	local terrain = Workspace.Terrain
	local step = M.ChunkCells * RESOLUTION
	local minX = math.floor((M.MinX - M.Outer) / RESOLUTION) * RESOLUTION
	local maxX = math.ceil((M.MaxX + M.Outer) / RESOLUTION) * RESOLUTION
	local minZ = math.floor((M.MinZ - M.Outer) / RESOLUTION) * RESOLUTION
	local maxZ = math.ceil((M.MaxZ + M.Outer) / RESOLUTION) * RESOLUTION
	-- Гладкий Terrain рисует поверхность на пол-ячейки выше заполненного объёма (проверено замером),
	-- поэтому заполняем до высоты минус пол-ячейки и держим два слоя под нулём
	local baseY = -2 * RESOLUTION
	local surfaceShift = RESOLUTION / 2

	for chunkX = minX, maxX - 1, step do
		for chunkZ = minZ, maxZ - 1, step do
			local countX = math.min(M.ChunkCells, (maxX - chunkX) / RESOLUTION)
			local countZ = math.min(M.ChunkCells, (maxZ - chunkZ) / RESOLUTION)

			local heights: { { number } } = table.create(countX)
			local highest = 0
			for i = 1, countX do
				local row: { number } = table.create(countZ)
				local x = chunkX + (i - 0.5) * RESOLUTION
				for k = 1, countZ do
					local height = Relief.Height(x, chunkZ + (k - 0.5) * RESOLUTION)
					row[k] = height
					highest = math.max(highest, height)
				end
				heights[i] = row
			end

			local countY = math.ceil(highest / RESOLUTION) + 3 -- два слоя под нулём и слой воздуха сверху
			local materials: { { { Enum.Material } } } = table.create(countX)
			local occupancies: { { { number } } } = table.create(countX)
			for i = 1, countX do
				local materialColumn: { { Enum.Material } } = table.create(countY)
				local occupancyColumn: { { number } } = table.create(countY)
				for j = 1, countY do
					materialColumn[j] = table.create(countZ, Enum.Material.Air)
					occupancyColumn[j] = table.create(countZ, 0)
				end
				local x = chunkX + (i - 0.5) * RESOLUTION
				for k = 1, countZ do
					local height = heights[i][k]
					local material = materialAt(x, chunkZ + (k - 0.5) * RESOLUTION, height)
					for j = 1, countY do
						local bottom = baseY + (j - 1) * RESOLUTION
						local fill = math.clamp((height - surfaceShift - bottom) / RESOLUTION, 0, 1)
						if fill <= 0 then
							break
						end
						materialColumn[j][k] = material
						occupancyColumn[j][k] = fill
					end
				end
				materials[i] = materialColumn
				occupancies[i] = occupancyColumn
			end

			local region = Region3.new(
				Vector3.new(chunkX, baseY, chunkZ),
				Vector3.new(
					chunkX + countX * RESOLUTION,
					baseY + countY * RESOLUTION,
					chunkZ + countZ * RESOLUTION
				)
			)
			terrain:WriteVoxels(region, RESOLUTION, materials :: any, occupancies :: any)
		end
	end
end

return Relief
