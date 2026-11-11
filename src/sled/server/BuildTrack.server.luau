--!strict
-- BuildTrack: строит гору прототипа по линии трассы: полотно, обрыв под ним, цветные края
-- (синий = можно ехать, оранжевый = скоро тормозить, красный = поворот), чекпоинты, финиш. Всё вокруг трассы строит Scenery.
-- Всё без столкновений: санки едут по расчёту, а не по физике.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local SledConfig = require(ReplicatedStorage.SledConfig)
local Track = require(ReplicatedStorage.Track)
local Scenery = require(ServerScriptService.Scenery)
local Peaks = require(ServerScriptService.Peaks)
local TrackMesh = require(ServerScriptService.TrackMesh)

local V = SledConfig.Visual

local track = Track.Get()
local floorY = Scenery.FloorY(track)

local function block(
	parent: Instance,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
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
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function edgeColor(s: number): Color3
	local _, _, _, _, kappa = Track.At(track, s)
	if math.abs(kappa) > V.BrakeKappa then
		return V.EdgeTurn
	end
	if Track.MaxKappa(track, s, V.BrakeLookahead) > V.BrakeKappa then
		return V.EdgeWarn
	end
	return V.EdgeSafe
end

-- Полотно с краями из блоков (запасной вариант) и скала под трассой: каждое по отдельности
local function buildSurface(parent: Instance, surface: boolean, cliffs: boolean)
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
		-- На повороте прямые блоки расходятся по внешнему краю: удлиняем, чтобы не было щелей
		local length = (b - a).Magnitude * (1 + math.abs(kappa) * width / 2) + 0.2

		if surface then
			local stripe = math.floor((index - 1) / V.StripeEvery) % 2 == 0
			block(
				parent,
				Vector3.new(width, V.TrackThickness, length),
				frame * CFrame.new(0, -V.TrackThickness / 2, 0),
				if stripe then V.SnowA else V.SnowB,
				Enum.Material.Snow
			)

			local color = edgeColor(s + span / 2)
			for _, side in { -1, 1 } do
				block(
					parent,
					Vector3.new(V.EdgeWidth, V.EdgeHeight, length),
					frame * CFrame.new(side * (width - V.EdgeWidth) / 2, V.EdgeHeight / 2, 0),
					color,
					Enum.Material.SmoothPlastic
				)
			end
		end

		if cliffs then
			-- Обрыв под полотном: вертикальная скала, чтобы трасса читалась как гребень горы
			local flatForward = Vector3.new(forward.X, 0, forward.Z).Unit
			local flatRight = Vector3.new(-flatForward.Z, 0, flatForward.X)
			-- На наклонённом повороте внутренний край ниже оси: скала не должна вылезать над ним
			local top = mid.Y - V.TrackThickness - V.CliffDrop - math.abs(right.Y) * width / 2
			local height = math.clamp(top - floorY, V.CliffHeight, V.CliffMaxHeight)
			block(
				parent,
				Vector3.new(width * V.CliffInset, height, length),
				CFrame.fromMatrix(
					Vector3.new(mid.X, top - height / 2, mid.Z),
					flatRight,
					Vector3.yAxis,
					-flatForward
				),
				V.Cliff,
				Enum.Material.Slate
			)
		end
	end
end

-- Ворота поперёк трассы: два столба и перекладина
local function buildGate(parent: Instance, s: number, color: Color3, tiles: number)
	local _, _, _, width = Track.At(track, s)
	local frame = Track.Frame(track, s, 0)
	for _, side in { -1, 1 } do
		block(
			parent,
			Vector3.new(V.GatePole, V.GateHeight, V.GatePole),
			frame * CFrame.new(side * width / 2, V.GateHeight / 2, 0),
			color,
			Enum.Material.SmoothPlastic
		)
	end
	local tileWidth = width / tiles
	for tile = 1, tiles do
		local dark = tiles > 1 and tile % 2 == 0
		block(
			parent,
			Vector3.new(tileWidth, V.GatePole * 1.5, V.GatePole),
			frame * CFrame.new(-width / 2 + (tile - 0.5) * tileWidth, V.GateHeight, 0),
			if dark then Color3.new(0.1, 0.1, 0.12) else color,
			Enum.Material.SmoothPlastic
		)
	end
end

local function buildSpawn(parent: Instance)
	local frame = Track.Frame(track, track.startS, 0)
	local spawn = Instance.new("SpawnLocation")
	spawn.Size = Vector3.new(V.SpawnPadSize, 1, V.SpawnPadSize)
	spawn.CFrame = CFrame.new(frame.Position + Vector3.yAxis * 0.5)
	spawn.Anchored = true
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = parent
end

local model = Instance.new("Model")
model.Name = "Mountain"
-- Санки едут только на клиенте, сервер видит игрока на старте: без этого при StreamingEnabled
-- дальняя часть трассы не подгрузилась бы
model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
buildSurface(model, false, true)
buildGate(model, track.startS + V.StartGateOffset, V.Checkpoint, 1)
for _, checkpoint in track.checkpoints do
	buildGate(model, checkpoint, V.Checkpoint, 1)
end
buildGate(model, track.finishS, Color3.new(1, 1, 1), V.FinishTiles)
Scenery.Build(model, track, edgeColor)
buildSpawn(model)
model.Parent = Workspace

-- Гладкая поверхность и лес ждут движок и сеть: строим их, когда гора и точка появления уже на
-- месте. Санки едут по расчёту, поэтому заезд можно начать и до этого.
task.spawn(function()
	local ok, shoulders = pcall(TrackMesh.Build, model, track, edgeColor)
	if not ok then
		warn(
			"BuildTrack: гладкая поверхность не построилась, собираю из блоков",
			shoulders
		)
	end
	-- Дальние горы: сеткой, а если не вышло, из клиньев
	local peaksOk, peaksBuilt = pcall(Peaks.Build, model, track)
	if not peaksOk or not peaksBuilt then
		Scenery.PeakParts(model, track)
	end
	if ok and shoulders then
		Scenery.Plant(model, track, shoulders)
	else
		buildSurface(model, true, false)
		Scenery.Plant(model, track, Scenery.ShoulderParts(model, track))
	end
end)
