--!strict
-- SledSim: движение санок в координатах трассы. Чистый расчёт без Instance: один и тот же код
-- двигает санки игрока на клиенте, бота-проверяющего и (позже) проверку на сервере.
local Obstacles = require(script.Parent.Obstacles)
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
	time: number, -- секунд с начала заезда: по этим часам ходят йети
	lastHit: number, -- номер препятствия, на которое наехали последним (0 = ещё ни на одно)
	hits: number, -- сколько наездов за заезд
	hitFree: number, -- сколько секунд санки не касались препятствий
	shielded: boolean?, -- активен ли защитный щит (защищает от торможения о сугробы, йети и лаву)
}

local O = SledConfig.Obstacles

local SledSim = {}

local function groundHeight(track: Track.Data, s: number, d: number): number
	local pos, _, right, width = Track.At(track, s)
	local over = math.abs(d) - width / 2
	local drop = if over > 0 then over * 0.24 + math.max(0, over - 5) ^ 2 * 0.065 else 0
	return pos.Y + right.Y * d - drop
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
	state.hitFree = math.huge
end

-- Начать заезд заново: часы и счётчик наездов с нуля
function SledSim.Reset(track: Track.Data, state: State, s: number)
	SledSim.Place(track, state, s, 0)
	state.time = 0
	state.hits = 0
	state.lastHit = 0
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
		time = 0,
		lastHit = 0,
		hits = 0,
		hitFree = math.huge,
		shielded = false,
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
	local _, tangent, _, _, kappa = Track.At(track, state.s)
	local heightBefore = groundHeight(track, state.s, state.d)
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

	-- Край трассы: в режиме OpenEdges за краем дороги идёт живой наклонный снежный склон обочины!
	-- Если чуть заступил за край (до 10.5 студов), санки кренятся на рыхлом снегу и их тянет вниз по склону,
	-- но можно вырулить обратно. Если скатился дальше по склону (> 10.5 студов) — срывается в пропасть.
	local _, _, _, widthAfter = Track.At(track, state.s)
	local limit = widthAfter / 2 - p.EdgeInset
	state.bank = false
	if p.OpenEdges then
		local over = math.abs(state.d) - widthAfter / 2
		if over > 0 then
			local side = math.sign(state.d)
			state.bank = true -- пускаем снежную пыль из-под полозьев на обочине
			-- Рыхлый снег слегка притормаживает, а уклон обочины физически стягивает санки вниз по склону
			state.v *= math.exp(-0.35 * dt)
			state.d += side * (2.5 + over * 1.1) * dt
			local slopePull = math.clamp(0.22 + over * 0.09, 0.22, 1.5)
			state.slide = math.clamp(state.slide + side * slopePull * dt, -p.MaxSlide, p.MaxSlide)
			state.heading =
				math.clamp(state.heading + side * slopePull * 0.65 * dt, -p.MaxSlide, p.MaxSlide)
			if over > 10.5 then
				state.fell = true
				return
			end
			state.bankFree = 0
		else
			state.bankFree += dt
		end
	elseif math.abs(state.d) > limit then
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

	-- Препятствия: наезд стоит скорости один раз и отбрасывает в сторону. В полёте и под щитом их проходят насквозь.
	state.time += dt
	local touching = false
	if grounded then
		for index, obstacle in Obstacles.Get(track) do
			local gap = state.s - obstacle.s
			if gap < -obstacle.radius then
				break -- список идёт по порядку: дальше только те, что ещё впереди
			end
			if gap < obstacle.radius then
				local side = state.d - Obstacles.D(obstacle, state.time)
				if gap * gap + side * side < obstacle.radius * obstacle.radius then
					touching = true
					if state.hitFree > O.HitRegrip and not state.shielded then
						local away = if side >= 0 then 1 else -1
						state.v *= obstacle.keep
						state.slide = away * O.Push
						state.heading = away * O.Push
						state.lastHit = index
						state.hits += 1
					end
				end
			end
		end
	end
	if touching then
		state.hitFree = 0
	else
		state.hitFree += dt
	end

	-- Трасса поворачивает под санками: без руля они уезжают наружу. Assist проходит часть сам.
	local turned = kappa * ds * (if grounded then 1 - p.Assist else 1)
	state.heading -= turned
	state.slide -= turned

	-- Высота: если снег уходит вниз быстрее свободного падения, санки летят
	local ground = groundHeight(track, state.s, state.d)
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
