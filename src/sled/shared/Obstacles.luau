--!strict
-- Obstacles: препятствия на полотне (сугробы, йети, лужи лавы) в координатах трассы.
-- Расстановка считается из чисел конфига одинаково на сервере, на клиенте и в тестах.
local SledConfig = require(script.Parent.SledConfig)
local Track = require(script.Parent.Track)

local O = SledConfig.Obstacles

export type Kind = "Drift" | "Yeti" | "Lava"

export type Obstacle = {
	kind: Kind,
	s: number, -- путь вдоль трассы
	d: number, -- своя точка: смещение от оси
	radius: number,
	keep: number, -- доля скорости после наезда
	sway: number, -- на сколько отходит от своей точки (йети ходит)
	rate: number,
	phase: number,
}

local Obstacles = {}

local cached: { Obstacle }? = nil

-- Число от 0 до 1, одно и то же для одних и тех же index и salt
local function rand(index: number, salt: number): number
	local x = math.sin(index * 12.9898 + salt * 78.233 + O.Seed) * 43758.5453
	return x - math.floor(x)
end

-- Свободная половина ширины для препятствия радиуса radius
local function room(track: Track.Data, s: number, radius: number): number
	local _, _, _, width = Track.At(track, s)
	return width / 2 - SledConfig.Physics.EdgeInset - O.EdgeGap - radius
end

-- Можно ли ставить препятствие в точке s: не у старта и финиша, не в крутом повороте,
-- не на трамплине и не там, где санки ещё летят
local function allowed(track: Track.Data, s: number): boolean
	if s < track.startS + O.StartClear or s > track.finishS - O.FinishClear then
		return false
	end
	local _, _, _, _, kappa = Track.At(track, s)
	if math.abs(kappa) > O.SharpKappa then
		return false
	end
	local first = math.clamp(math.floor((s - O.JumpGuard) / track.step) + 1, 1, track.count)
	local last = math.clamp(math.floor((s + O.JumpGuard) / track.step) + 1, 1, track.count)
	for i = first, last do
		if track.pitch[i] < 0 or track.pitch[i] > O.SteepPitch then
			return false
		end
	end
	return true
end

function Obstacles.Get(track: Track.Data): { Obstacle }
	if cached then
		return cached
	end
	local list: { Obstacle } = {}

	local function add(kind: Kind, s: number, d: number, sway: number, index: number)
		local spec = O[kind]
		table.insert(list, {
			kind = kind,
			s = s,
			d = d,
			radius = spec.radius,
			keep = spec.keep,
			sway = sway,
			rate = if sway > 0 then O.Yeti.rate else 0,
			phase = rand(index, 5) * math.pi * 2,
		})
	end

	-- Лужи лавы в пещерах
	for caveIndex, cave in track.caves do
		local index = 0
		for s = cave.from + O.Lava.enter, cave.to - O.Lava.enter, O.Lava.every do
			index += 1
			local free = room(track, s, O.Lava.radius)
			if free > 0 then
				local d = (rand(index, caveIndex) * 2 - 1) * free * O.Lava.spread
				add("Lava", s, d, 0, index + caveIndex * 100)
			end
		end
	end

	-- Йети ходят поперёк трассы под открытым небом
	local yetiAt: { number } = {}
	local index = 0
	for s = O.Yeti.first, track.finishS, O.Yeti.every do
		index += 1
		local free = room(track, s, O.Yeti.radius)
		if allowed(track, s) and Track.CaveDepth(track, s) < -O.CaveGuard and free > 0 then
			add("Yeti", s, 0, math.min(O.Yeti.sway, free), index)
			table.insert(yetiAt, s)
		end
	end

	-- Сугробы: там, где нет ни пещеры, ни йети
	index = 0
	for s = track.startS + O.StartClear, track.finishS, O.Drift.every do
		index += 1
		local free = room(track, s, O.Drift.radius)
		local clear = allowed(track, s) and Track.CaveDepth(track, s) < -O.CaveGuard and free > 0
		for _, taken in yetiAt do
			if math.abs(taken - s) < O.Drift.every / 2 then
				clear = false
			end
		end
		if clear then
			add("Drift", s, (rand(index, 9) * 2 - 1) * free * O.Drift.spread, 0, index)
		end
	end

	table.sort(list, function(a, b)
		return a.s < b.s
	end)
	cached = list
	return list
end

-- Где препятствие поперёк трассы в момент time
function Obstacles.D(obstacle: Obstacle, time: number): number
	return obstacle.d + obstacle.sway * math.sin(obstacle.phase + obstacle.rate * time)
end

return Obstacles
