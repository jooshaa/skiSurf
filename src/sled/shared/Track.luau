--!strict
-- Track: линия трассы из кусков (длина, поворот, уклон, ширина). Считается одинаково на сервере
-- и на клиенте. Санки живут в координатах трассы: путь вдоль линии и смещение от оси.
local SledConfig = require(script.Parent.SledConfig)

local T = SledConfig.Track

export type Data = {
	step: number,
	count: number,
	length: number,
	startS: number,
	finishS: number,
	checkpoints: { number },
	caves: { { from: number, to: number } }, -- участки внутри пещер
	pos: { Vector3 },
	yaw: { number },
	pitch: { number },
	width: { number },
	kappa: { number },
}

local Track = {}

local cached: Data? = nil

-- Скользящее среднее: стыки кусков становятся плавными
local function smooth(values: { number }, half: number): { number }
	local count = #values
	local result = table.create(count, 0)
	for i = 1, count do
		local sum = 0
		for k = i - half, i + half do
			sum += values[math.clamp(k, 1, count)]
		end
		result[i] = sum / (half * 2 + 1)
	end
	return result
end

local function tangentOf(yaw: number, pitch: number): Vector3
	local flat = math.cos(pitch)
	return Vector3.new(math.sin(yaw) * flat, -math.sin(pitch), -math.cos(yaw) * flat)
end

function Track.Get(): Data
	if cached then
		return cached
	end
	local step = T.Step
	local kappa: { number } = {}
	local pitch: { number } = {}
	local width: { number } = {}
	local checkpoints: { number } = {}
	local caves: { { from: number, to: number } } = {}

	local distance = 0
	for _, piece in T.Pieces do
		if piece.checkpoint then
			table.insert(checkpoints, distance)
		end
		local samples = math.max(1, math.round(piece.length / step))
		local curve = math.rad(piece.turn) / (samples * step)
		for _ = 1, samples do
			table.insert(kappa, curve)
			table.insert(pitch, math.rad(piece.slope))
			table.insert(width, piece.width)
		end
		if piece.cave then
			-- Соседние куски пещеры сливаются в одну
			local last = caves[#caves]
			if last and last.to == distance then
				last.to = distance + samples * step
			else
				table.insert(caves, { from = distance, to = distance + samples * step })
			end
		end
		distance += samples * step
	end

	local half = math.max(1, math.round(T.SmoothLength / step / 2))
	kappa = smooth(kappa, half)
	pitch = smooth(pitch, half)
	width = smooth(width, half)

	local count = #kappa
	local pos: { Vector3 } = table.create(count)
	local yaw: { number } = table.create(count)
	pos[1] = T.Origin
	yaw[1] = 0
	for i = 1, count - 1 do
		yaw[i + 1] = yaw[i] + kappa[i] * step
		pos[i + 1] = pos[i] + tangentOf(yaw[i], pitch[i]) * step
	end

	local length = (count - 1) * step
	local data: Data = {
		step = step,
		count = count,
		length = length,
		startS = T.StartS,
		finishS = length - T.FinishBeforeEnd,
		checkpoints = checkpoints,
		caves = caves,
		pos = pos,
		yaw = yaw,
		pitch = pitch,
		width = width,
		kappa = kappa,
	}
	cached = data
	return data
end

-- Точка трассы на расстоянии s: центр, касательная, вектор вправо (с наклоном полотна),
-- ширина и кривизна (+ это поворот вправо)
function Track.At(data: Data, s: number): (Vector3, Vector3, Vector3, number, number)
	local f = math.clamp(s / data.step, 0, data.count - 1.001)
	local i = math.floor(f) + 1
	local t = f - (i - 1)
	local yaw = data.yaw[i] + (data.yaw[i + 1] - data.yaw[i]) * t
	local pitch = data.pitch[i] + (data.pitch[i + 1] - data.pitch[i]) * t
	local kappa = data.kappa[i] + (data.kappa[i + 1] - data.kappa[i]) * t
	local bank = math.clamp(kappa * T.BankGain, -T.MaxBank, T.MaxBank)
	local flatRight = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
	-- В правом повороте правый край ниже: полотно наклонено внутрь поворота
	local right = flatRight * math.cos(bank) - Vector3.yAxis * math.sin(bank)
	return data.pos[i]:Lerp(data.pos[i + 1], t),
		tangentOf(yaw, pitch),
		right,
		data.width[i] + (data.width[i + 1] - data.width[i]) * t,
		kappa
end

local SC = SledConfig.Scenery
local M = SledConfig.Mesh

local function meshNoise(s: number, lane: number): number
	return math.clamp(math.noise(s * M.NoiseScale, lane * M.NoiseLane, SC.Seed) * 2, -1, 1)
end

-- Точный профиль снежного сугроба обочины (1-в-1 с генератором 3D-сетки TrackMesh):
-- возвращает:
--   fullWidth: 100% реальной ширины сугроба в точке s с учётом шума кромки и радиуса виража
--   nearSpan: расстояние до перегиба сугроба (45% от fullWidth)
--   drop: на сколько студов снег опустился ниже кромки полотна в точке over
--   slopeAngle: угол поперечного наклона склона (рад)
function Track.ShoulderProfile(data: Data, s: number, d: number): (number, number, number, number)
	local _, _, _, width, kappa = Track.At(data, s)
	local over = math.max(0, math.abs(d) - width / 2)
	local side = if d >= 0 then 1 else -1

	local reach = SC.ShoulderWidth
	if kappa * side > SC.InnerKappa then
		reach = math.min(reach, 1 / math.abs(kappa) - width / 2 - M.InnerGap)
	end
	reach = math.max(reach, SC.ShoulderMin)

	-- Неровность внешней кромки сугроба — точно по формуле TrackMesh.buildRing
	local fullWidth = reach * (1 - M.ShoulderNoise * (0.5 + 0.5 * meshNoise(s, side)))
	local nearSpan = fullWidth * M.MidShare
	local baseNearDrop = nearSpan * math.tan(M.NearSlope)
	local bump = math.min(M.ShoulderBump, baseNearDrop) * meshNoise(s, side * M.NoiseLane)
	local midDrop = baseNearDrop - bump
	local effectiveNearSlope = math.atan2(midDrop, math.max(nearSpan, 1))
	local outerSlope = SC.ShoulderSlope
	local cliffSlope = SC.SkirtSlope

	local drop: number
	local slopeAngle: number
	if over <= nearSpan then
		local t = if nearSpan > 0 then over / nearSpan else 0
		drop = midDrop * t
		slopeAngle = effectiveNearSlope * math.clamp(over / 3.5, 0, 1)
	elseif over <= fullWidth then
		local past = over - nearSpan
		drop = midDrop + past * math.tan(outerSlope)
		local blend = math.clamp(past / 7, 0, 1)
		slopeAngle = effectiveNearSlope + (outerSlope - effectiveNearSlope) * blend
	else
		local outerSpan = fullWidth - nearSpan
		local pastCliff = over - fullWidth
		drop = midDrop + outerSpan * math.tan(outerSlope) + pastCliff * math.tan(cliffSlope)
		local blend = math.clamp(pastCliff / 5, 0, 1)
		slopeAngle = outerSlope + (cliffSlope - outerSlope) * blend
	end

	return fullWidth, nearSpan, drop, slopeAngle
end

-- Система координат поверхности в точке (s, d): X вправо, Y вверх от снега, -Z по ходу трассы.
-- За пределами полотна (|d| > width/2) поверхность на 100% повторяет 3D-сетку сугроба обочины (TrackMesh).
function Track.Frame(data: Data, s: number, d: number): CFrame
	local pos, tangent, right, width = Track.At(data, s)
	local up = (-tangent):Cross(right).Unit
	local over = math.abs(d) - width / 2
	if over > 0 and Track.CaveDepth(data, s) <= 0 then
		local side = math.sign(d)
		local edgePos = pos + right * (side * width / 2)
		local flatRight = Vector3.new(right.X, 0, right.Z).Unit
		local _, _, drop, slopeAngle = Track.ShoulderProfile(data, s, d)

		local worldPos = edgePos + flatRight * (side * over) - Vector3.yAxis * drop
		local flatForward = Vector3.new(tangent.X, 0, tangent.Z).Unit
		local edgeFrame = CFrame.fromMatrix(worldPos, flatRight, Vector3.yAxis, -flatForward)
		local pitch = math.asin(math.clamp(tangent.Y, -0.95, 0.95))
		return edgeFrame * CFrame.Angles(pitch, 0, -side * slopeAngle)
	end
	return CFrame.fromMatrix(pos + right * d, up:Cross(-tangent), up, -tangent)
end

-- Самый крутой поворот на отрезке впереди
function Track.MaxKappa(data: Data, from: number, distance: number): number
	local first = math.clamp(math.floor(from / data.step) + 1, 1, data.count)
	local last = math.clamp(math.floor((from + distance) / data.step) + 1, 1, data.count)
	local worst = 0
	for i = first, last do
		worst = math.max(worst, math.abs(data.kappa[i]))
	end
	return worst
end

-- Насколько точка s внутри пещеры: расстояние до ближайшего выхода (минус = снаружи)
function Track.CaveDepth(data: Data, s: number): number
	local best = -math.huge
	for _, cave in data.caves do
		best = math.max(best, math.min(s - cave.from, cave.to - s))
	end
	return best
end

-- Последний чекпоинт не дальше s (или старт)
function Track.CheckpointBefore(data: Data, s: number): number
	local best = data.startS
	for _, checkpoint in data.checkpoints do
		if checkpoint <= s and checkpoint > best then
			best = checkpoint
		end
	end
	return best
end

return Track
