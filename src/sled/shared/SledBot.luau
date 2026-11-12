--!strict
-- SledBot: бот-проверяющий. Проезжает трассу тем же расчётом, что и игрок, и сообщает время,
-- вылеты и скорость. Нужен, чтобы проверять честность трассы числами, а не на глаз.
local Obstacles = require(script.Parent.Obstacles)
local SledConfig = require(script.Parent.SledConfig)
local SledSim = require(script.Parent.SledSim)
local Track = require(script.Parent.Track)

local B = SledConfig.Bot

export type Result = {
	finished: boolean,
	time: number,
	falls: number,
	fallAt: { number }, -- где вылетал (путь вдоль трассы)
	maxSpeed: number,
	airTime: number,
	brakeTime: number,
	bankTime: number, -- сколько тёрся о снежный борт
	hits: number, -- сколько раз наехал на препятствие
}

-- Какой линии поперёк трассы держаться: середины, а перед препятствием объехать его
local function line(track: Track.Data, state: SledSim.State, p: SledConfig.Physics): number
	local reach = math.max(B.AvoidMin, state.v * B.AvoidTime)
	for _, obstacle in Obstacles.Get(track) do
		local gap = obstacle.s - state.s
		if gap > reach then
			break
		end
		if gap > -obstacle.radius then
			local at = Obstacles.D(obstacle, state.time + math.max(0, gap) / math.max(state.v, 1))
			local clear = obstacle.radius + B.AvoidMargin
			if math.abs(at) < clear or math.abs(state.d - at) < clear then
				local _, _, _, width = Track.At(track, obstacle.s)
				local limit = width / 2 - p.EdgeInset - B.AvoidMargin
				-- Объезжаем с той стороны, где уже едем, если там хватает места
				local side = if state.d >= at then 1 else -1
				if math.abs(at + side * clear) > limit then
					side = -side
				end
				return at + side * clear
			end
			return 0
		end
	end
	return 0
end

local SledBot = {}

-- Что бот делает в этот момент: руль от -1 до 1 и тормоз
function SledBot.Control(
	track: Track.Data,
	state: SledSim.State,
	p: SledConfig.Physics
): (number, boolean)
	local _, _, _, _, kappa = Track.At(track, state.s)
	-- Держим середину и заранее доворачиваем на кривизну трассы
	local target = line(track, state, p)
	local gain = if target == 0 then B.CenterGain else B.AvoidGain
	local wanted = math.clamp((target - state.d) * gain, -B.MaxAngle, B.MaxAngle)
	local feed = kappa * state.v * (1 - p.Assist) / p.TurnRate
	local steer = math.clamp((wanted - state.heading) * B.HeadingGain + feed, -1, 1)
	local ahead = Track.MaxKappa(track, state.s, state.v * B.LookTime)
	-- Не успевает объехать: притормаживает
	local late = target ~= 0 and math.abs(target - state.d) > B.AvoidBrake
	return steer, late or ahead * state.v * (1 - p.Assist) > p.TurnRate * B.BrakeMargin
end

-- useBrake = false: бот не тормозит вообще (так видно, где тормоз обязателен)
-- useSteer = false: бот не рулит (так видно, сколько держит одна помощь)
function SledBot.Run(p: SledConfig.Physics, useBrake: boolean, useSteer: boolean): Result
	local track = Track.Get()
	local state = SledSim.New(track, track.startS)
	local result: Result = {
		finished = false,
		time = 0,
		falls = 0,
		fallAt = {},
		maxSpeed = 0,
		airTime = 0,
		brakeTime = 0,
		bankTime = 0,
		hits = 0,
	}
	local dt = B.Step
	while result.time < B.MaxTime do
		local steer, brake = SledBot.Control(track, state, p)
		if not useSteer then
			steer = 0
		end
		if not useBrake then
			brake = false
		end

		SledSim.Step(track, state, p, steer, brake, dt)
		result.time += dt
		result.maxSpeed = math.max(result.maxSpeed, state.v)
		if state.airborne then
			result.airTime += dt
		end
		if brake then
			result.brakeTime += dt
		end
		if state.bank then
			result.bankTime += dt
		end
		if state.fell then
			result.falls += 1
			table.insert(result.fallAt, math.round(state.s))
			if result.falls > B.MaxFalls then
				break
			end
			result.time += SledConfig.Run.FallTime
			SledSim.Place(
				track,
				state,
				Track.CheckpointBefore(track, state.s),
				SledConfig.Run.RespawnSpeed
			)
		end
		result.hits = state.hits
		if state.s >= track.finishS then
			result.finished = true
			break
		end
	end
	return result
end

return SledBot
