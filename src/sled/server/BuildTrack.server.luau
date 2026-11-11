--!strict
-- BuildTrack: строит гору прототипа по линии трассы: полотно, обрыв под ним, цветные края
-- (синий = можно ехать, оранжевый = скоро тормозить, красный = поворот), чекпоинты, финиш, ели.
-- Всё без столкновений: санки едут по расчёту, а не по физике.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SledConfig = require(ReplicatedStorage.SledConfig)
local Track = require(ReplicatedStorage.Track)

local V = SledConfig.Visual

local track = Track.Get()

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

local function buildSurface(parent: Instance)
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

		-- Обрыв под полотном: вертикальная скала, чтобы трасса читалась как гребень горы
		local flatForward = Vector3.new(forward.X, 0, forward.Z).Unit
		local flatRight = Vector3.new(-flatForward.Z, 0, flatForward.X)
		local top = mid.Y - V.TrackThickness - V.CliffDrop
		block(
			parent,
			Vector3.new(width * V.CliffInset, V.CliffHeight, length),
			CFrame.fromMatrix(
				Vector3.new(mid.X, top - V.CliffHeight / 2, mid.Z),
				flatRight,
				Vector3.yAxis,
				-flatForward
			),
			V.Cliff,
			Enum.Material.Slate
		)
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

-- Ель на уступе у края трассы: мимо них видно, как быстро едешь
local function buildPine(parent: Instance, s: number, side: number)
	local pos, tangent, _, width = Track.At(track, s)
	local flatForward = Vector3.new(tangent.X, 0, tangent.Z).Unit
	local flatRight = Vector3.new(-flatForward.Z, 0, flatForward.X)
	local base = pos + flatRight * side * (width / 2 + V.PineOffset + V.PineLedge / 2)
	local frame = CFrame.fromMatrix(base, flatRight, Vector3.yAxis, -flatForward)

	block(
		parent,
		Vector3.new(V.PineLedge, V.CliffHeight, V.PineLedge),
		frame * CFrame.new(0, -V.CliffHeight / 2, 0),
		V.Cliff,
		Enum.Material.Slate
	)
	block(
		parent,
		Vector3.new(V.PineWidth / 5, V.PineHeight / 4, V.PineWidth / 5),
		frame * CFrame.new(0, V.PineHeight / 8, 0),
		V.Trunk,
		Enum.Material.Wood
	)
	for quarter = 0, 3 do
		local piece = Instance.new("CornerWedgePart")
		piece.Size = Vector3.new(V.PineWidth / 2, V.PineHeight, V.PineWidth / 2)
		-- Вершина углового клина в углу (+X, -Z): четыре четверти сходятся вершинами в центре
		piece.CFrame = frame
			* CFrame.new(0, V.PineHeight / 4 + V.PineHeight / 2, 0)
			* CFrame.Angles(0, quarter * math.pi / 2, 0)
			* CFrame.new(-V.PineWidth / 4, 0, V.PineWidth / 4)
		piece.Color = V.Pine
		piece.Material = Enum.Material.SmoothPlastic
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanTouch = false
		piece.CanQuery = false
		piece.CastShadow = false
		piece.Parent = parent
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

local function applyLighting()
	Lighting.ClockTime = V.ClockTime
	Lighting.Brightness = V.Brightness
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = V.FogDensity
	atmosphere.Color = V.FogColor
	atmosphere.Decay = V.FogColor
	atmosphere.Parent = Lighting
end

local model = Instance.new("Model")
model.Name = "Mountain"
buildSurface(model)
buildGate(model, track.startS + 10, V.Checkpoint, 1)
for _, checkpoint in track.checkpoints do
	buildGate(model, checkpoint, V.Checkpoint, 1)
end
buildGate(model, track.finishS, Color3.new(1, 1, 1), V.FinishTiles)
local side = 1
for s = V.PineEvery, track.length - V.PineEvery, V.PineEvery do
	if Track.MaxKappa(track, s - V.PineClearTurn, V.PineClearTurn * 2) <= V.BrakeKappa then
		buildPine(model, s, side)
		side = -side
	end
end
buildSpawn(model)
model.Parent = Workspace
applyLighting()
