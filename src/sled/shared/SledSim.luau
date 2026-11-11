--!strict
-- SledSim: движение санок в координатах трассы. Чистый расчёт без Instance: один и тот же код
-- двигает санки игрока на клиенте, бота-проверяющего и (позже) проверку на сервере.
local SledConfig = require(script.Parent.SledConfig)
local Track = require(script.Parent.Track)

export type State = {
	s: number, -- путь вдоль трассы
	d: number, -- смещение от оси (+ вправо)
	v: number, -- скорость
	heading: number, -- куда смотрит нос относительно трассы (+ вправо)
	slide: number, -- куда санки реально едут относительно трассы
	y: number, -- высота точки под санками
	w: number, -- вертикальная скорость
	air: number, -- высота над снегом
	airborne: boolean,
	fell: boolean, -- вылетел за край
}

local SledSim = {}

local function groundHeight(track: Track.Data, s: number, d: number): number
	local pos, _, right = Track.At(track, s)
	return pos.Y + right.Y * d
end

-- Поставить санки на трассу в точке s
function SledSim.Place(track: Track.Data, state: State, s: number, speed: number)
	state.s = s
	state.d = 0
	state.v = speed
	state.heading = 0
	state.slide = 0
	state.y = groundHeight(track, s, 0)
	state.w = 0
	state.air = 0
	state.airborne = false
	state.fell = false
end

function SledSim.New(track: Track.Data, s: number): State
	local state: State = {
		s = 0,
		d = 0,
		v = 0,
		heading = 0,
		slide = 0,
		y = 0,
		w = 0,
		air = 0,
		airborne = false,
		fell = false,
	}
	SledSim.Place(track, state, s, 0)
	return state
end

-- Один шаг: steer от -1 (влево) до 1 (вправо), brake зажат или нет
function SledSim.Step(
	track: Track.Data,
	state: State,
	p: SledConfig.Physics,
	steer: number,
	brake: boolean,
	dt: number
)
	if state.fell or dt <= 0 then
		return
	end
	if steer ~= steer then
		steer = 0 -- NaN от ввода не должен попасть в расчёт
	end
	local pos, tangent, right, _, kappa = Track.At(track, state.s)
	local heightBefore = pos.Y + right.Y * state.d
	local grounded = not state.airborne

	-- Руль поворачивает нос; движение догоняет нос со скоростью сцепления
	state.heading += steer * p.TurnRate * (if grounded then 1 else p.AirTurn) * dt
	if grounded then
		state.slide += (state.heading - state.slide) * (1 - math.exp(-p.Grip * dt))
		local release = 1 - math.abs(steer)
		state.heading += (state.slide - state.heading) * (1 - math.exp(-p.AlignRate * dt)) * release
	end
	local slip = math.clamp(state.heading - state.slide, -p.MaxSlip, p.MaxSlip)
	state.slide = math.clamp(state.slide, -p.MaxSlide, p.MaxSlide)
	state.heading = state.slide + slip

	-- Скорость: разгоняет только уклон, гасят трение, воздух, занос и тормоз
	if grounded then
		local accel = p.SlopeGravity * -tangent.Y * math.cos(state.slide)
			- p.Friction
			- p.Drag * state.v * state.v
			- p.SlipDrag * state.v * math.abs(math.sin(slip))
			- p.SteerDrag * state.v * math.abs(steer)
		if brake then
			accel -= p.Brake
		end
		-- Ниже минимума санки не останавливаются, но и не прыгают до него рывком
		local floor = if brake then p.BrakeMinSpeed else p.MinSpeed
		local speed = state.v + accel * dt
		if speed < floor then
			speed = math.max(speed, math.min(floor, state.v + p.MinSpeedAccel * dt))
		end
		state.v = speed
	end

	-- Перемещение. На внутренней стороне поворота тот же путь проходит больше трассы.
	local ds = state.v * math.cos(state.slide) * dt / math.max(p.InsideLimit, 1 - kappa * state.d)
	state.s += ds
	state.d += state.v * math.sin(state.slide) * dt

	-- Трасса поворачивает под санками: без руля они уезжают наружу. Assist проходит часть сам.
	local turned = kappa * ds * (if grounded then 1 - p.Assist else 1)
	state.heading -= turned
	state.slide -= turned

	-- Высота: если снег уходит вниз быстрее свободного падения, санки летят
	local posAfter, _, rightAfter, widthAfter = Track.At(track, state.s)
	local ground = posAfter.Y + rightAfter.Y * state.d
	local free = state.y + state.w * dt - 0.5 * p.AirGravity * dt * dt
	local outside = math.abs(state.d) > widthAfter / 2
	if free > ground then
		state.y = free
		state.w -= p.AirGravity * dt
		state.air = free - ground
		state.airborne = state.air > p.AirThreshold
	elseif outside then
		state.fell = true -- под санками нет полотна: вылет
	else
		state.y = ground
		state.w = (ground - heightBefore) / dt
		state.air = 0
		state.airborne = false
	end
end

return SledSim
