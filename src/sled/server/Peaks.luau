--!strict
-- Peaks: дальние горы вокруг долины. Несколько форм вершин строятся сеткой (гранёная скала,
-- снежная шапка) и расставляются кольцом с разным размером и поворотом.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SledConfig = require(ReplicatedStorage.SledConfig)
local Track = require(ReplicatedStorage.Track)
local MeshBuilder = require(ServerScriptService.MeshBuilder)
local Scenery = require(ServerScriptService.Scenery)

local P = SledConfig.Peaks

local Peaks = {}

local function tone(a: Color3, b: Color3, random: Random): Color3
	return a:Lerp(b, random:NextInteger(0, P.ToneSteps) / P.ToneSteps)
end

-- Одна форма вершины: кольца точек от макушки к подножию, неровные по высоте и ширине
local function buildShape(variant: number): MeshPart?
	local random = Random.new(P.Seed + variant)
	local rings: { { Vector3 } } = {}
	for k = 1, P.Rings do
		local share = k / P.Rings
		local ring = table.create(P.Segments)
		for j = 1, P.Segments do
			local angle = (j + random:NextNumber(-P.Jitter, P.Jitter)) / P.Segments * math.pi * 2
			-- Отроги: в одних направлениях гора тянется дальше, чем в других
			local ridge = 1
				+ P.Ridge
					* math.noise(
						math.cos(angle) * P.RidgeCount,
						math.sin(angle) * P.RidgeCount,
						variant
					)
			local reach = P.Radius * share * math.clamp(ridge, P.RidgeMin, 1)
			local height = if k == P.Rings
				then 0
				else P.Height * (1 - share) ^ P.Profile * (1 + random:NextNumber(
					-P.Rough,
					P.Rough
				))
			ring[j] = Vector3.new(math.cos(angle) * reach, height, -math.sin(angle) * reach)
		end
		rings[k] = ring
	end

	local builder = MeshBuilder.New()
	local snowLine = P.Height * P.SnowLine
	local function face(a: Vector3, b: Vector3, c: Vector3)
		local level = (a.Y + b.Y + c.Y) / 3
			+ random:NextNumber(-P.SnowRough, P.SnowRough) * P.Height
		local color = if level > snowLine
			then tone(P.SnowA, P.SnowB, random)
			else tone(P.RockA, P.RockB, random)
		MeshBuilder.Triangle(builder, a, b, c, color)
	end

	local top = Vector3.new(0, P.Height, 0)
	for j = 1, P.Segments do
		local nextJ = j % P.Segments + 1
		face(top, rings[1][j], rings[1][nextJ])
		for k = 1, P.Rings - 1 do
			local inner, outer = rings[k], rings[k + 1]
			face(inner[j], outer[j], outer[nextJ])
			face(inner[j], outer[nextJ], inner[nextJ])
		end
	end
	return MeshBuilder.Create(builder, "Peak", Enum.Material.SmoothPlastic)
end

-- Расставить горы вокруг трассы. false = сетку построить не удалось.
function Peaks.Build(parent: Instance, track: Track.Data): boolean
	local shapes: { MeshPart } = {}
	for variant = 1, P.Variants do
		local shape = buildShape(variant)
		if not shape then
			return false
		end
		table.insert(shapes, shape)
	end

	local centre, radius = Scenery.Bounds(track)
	local random = Random.new(P.Seed)
	local holder = Instance.new("Model")
	holder.Name = "Peaks"
	for i = 1, P.Count do
		local peak = shapes[(i - 1) % #shapes + 1]:Clone()
		local scale = random:NextNumber(P.ScaleMin, P.ScaleMax)
		local tall = random:NextNumber(P.TallMin, P.TallMax)
		peak.Size =
			Vector3.new(peak.Size.X * scale, peak.Size.Y * scale * tall, peak.Size.Z * scale)
		local angle = (i + random:NextNumber(-P.Spread, P.Spread)) / P.Count * math.pi * 2
		-- Подножие горы не доходит до трассы: отступаем на её полуширину и запас
		local distance = radius + peak.Size.X / 2 + random:NextNumber(P.DistanceMin, P.DistanceMax)
		peak.CFrame = CFrame.new(
			centre.X + math.cos(angle) * distance,
			centre.Y - P.Sink + peak.Size.Y / 2,
			centre.Z + math.sin(angle) * distance
		) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
		peak.Parent = holder
	end

	-- Ближние горы вдоль трассы: на слабой графике дальние не рисуются, а эти всегда рядом
	local side = 1
	for along = P.NearEvery, track.length - P.NearEvery, P.NearEvery do
		local pos, tangent, right = Track.At(track, along)
		local outward = Vector3.new(right.X, 0, right.Z).Unit * side
		local forward = Vector3.new(tangent.X, 0, tangent.Z).Unit
		local hill = shapes[random:NextInteger(1, #shapes)]:Clone()
		local scale = random:NextNumber(P.NearScaleMin, P.NearScaleMax)
		hill.Size *= scale
		local lateral = random:NextNumber(P.NearLateralMin, P.NearLateralMax) + hill.Size.X / 2
		-- Гора не должна встать на соседний виток трассы
		if Scenery.Clearance(track, along, pos, outward, forward) > lateral + hill.Size.X / 2 then
			local top = pos.Y + random:NextNumber(P.NearRiseMin, P.NearRiseMax)
			local foot = pos + outward * lateral
			hill.CFrame = CFrame.new(foot.X, top - hill.Size.Y / 2, foot.Z)
				* CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
			hill.Parent = holder
		end
		side = -side
	end

	holder.Parent = parent
	return true
end

return Peaks
