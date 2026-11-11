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
	yaw: number, -- текущая скорость поворота носа, рад/с
	fell: boolean, -- вылетел за край
	bank: boolean, -- трётся о снежный борт у края
	bankFree: number, -- сколько секунд санки не касались борта
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
	state.yaw = 0
	state.fell = false
	state.bank = false
	state.bankFree = math.huge
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
		yaw = 0,
		fell = false,
		bank = false,
		bankFree = math.huge,
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
	if state.fell or dt ~= dt or dt <= 0 then
		return
	end
	if steer ~= steer then
		steer = 0 -- NaN от ввода не должен попасть в расчёт
	end
	steer = math.clamp(steer, -1, 1)
	local pos, tangent, right, _, kappa = Track.At(track, state.s)
	local heightBefore = pos.Y + right.Y * state.d
	local grounded = not state.airborne

	-- Руль поворачивает нос; движение догоняет нос со скоростью сцепления
	-- Санки набирают поворот не мгновенно: так в руле чувствуется вес
	local wantedYaw = steer * p.TurnRate * (if grounded then 1 else p.AirTurn)
	state.yaw += (wantedYaw - state.yaw) * (1 - math.exp(-p.SteerResponse * dt))
	state.heading += state.yaw * dt
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

	-- Край трассы: рыхлый снежный борт. Он не выбрасывает, а тормозит и возвращает на полотно.
	local posAfter, _, rightAfter, widthAfter = Track.At(track, state.s)
	local limit = widthAfter / 2 - p.EdgeInset
	state.bank = false
	if math.abs(state.d) > limit then
		local side = math.sign(state.d)
		state.d = side * limit
		state.bank = true
		local angle = math.max(0, math.sin(state.slide) * side)
		if grounded then
			-- Удар стоит скорости один раз: чем прямее въехал, тем больше. Дальше, пока санки
			-- трутся о борт, скорость просто тает.
			local keep = math.exp(-p.BankDrag * dt)
			if state.bankFree > p.BankRegrip then
				keep *= (1 - p.BankShock) * math.max(0, 1 - p.BankHit * angle)
			end
			state.v *= keep
			state.bankFree = 0
		end
		-- Борт отталкивает обратно на полотно; нос смотрит в него, только пока туда рулят
		if state.slide * side > -p.BankPush then
			state.slide = -side * p.BankPush
		end
		local into = math.max(0, steer * side)
		local cap = p.BankHeading * into - p.BankPush * (1 - into)
		if state.heading * side > cap then
			state.heading = side * cap
		end
	else
		state.bankFree += dt
	end

	-- Трасса поворачивает под санками: без руля они уезжают наружу. Assist проходит часть сам.
	local turned = kappa * ds * (if grounded then 1 - p.Assist else 1)
	state.heading -= turned
	state.slide -= turned

	-- Высота: если снег уходит вниз быстрее свободного падения, санки летят
	local ground = posAfter.Y + rightAfter.Y * state.d
	local free = state.y + state.w * dt - 0.5 * p.AirGravity * dt * dt
	if free > ground then
		state.y = free
		state.w -= p.AirGravity * dt
		state.air = free - ground
		state.airborne = state.air > p.AirThreshold
	else
		state.y = ground
		state.w = (ground - heightBefore) / dt
		state.air = 0
		state.airborne = false
	end
end

return SledSim
