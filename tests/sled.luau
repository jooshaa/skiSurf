--!nocheck
-- Тесты расчёта санок без Studio. Запуск: lune run tests/sled.luau (или scripts/check.sh).
-- Загружает общие модули прототипа как есть, подставляя им `script` и типы Roblox из Lune.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local ROOT = "src/sled/shared/"
local cache = {}

local function load(name: string)
	if cache[name] ~= nil then
		return cache[name]
	end
	local parent = setmetatable({}, {
		__index = function(_, key)
			return { module = key }
		end,
	})
	local env = {
		script = { Parent = parent },
		require = function(token)
			return load(token.module)
		end,
	}
	-- Типы данных Roblox (Vector3, CFrame, Color3 и т. д.) берём из Lune
	for _, key in
		{ "Vector3", "Vector2", "CFrame", "Color3", "UDim", "UDim2", "NumberRange", "Enum" }
	do
		env[key] = (roblox :: any)[key]
	end
	local chunk = luau.load(fs.readFile(ROOT .. name .. ".luau"), {
		debugName = name,
		environment = env :: any,
	})
	cache[name] = chunk()
	return cache[name]
end

local SledConfig = load("SledConfig")
local Track = load("Track")
local SledSim = load("SledSim")
local SledBot = load("SledBot")

local failed = 0
local function check(name: string, ok: boolean, detail: string?)
	print(
		string.format(
			"%s  %s%s",
			if ok then "ok  " else "FAIL",
			name,
			if detail then "  (" .. detail .. ")" else ""
		)
	)
	if not ok then
		failed += 1
	end
end

local function physics(presetId: string?)
	local p = table.clone(SledConfig.Physics)
	if presetId then
		for _, preset in SledConfig.Presets do
			if preset.id == presetId then
				for key, value in preset.values do
					p[key] = value
				end
			end
		end
	end
	return p
end

local track = Track.Get()

-- Трасса
check("трасса: финиш после старта", track.finishS > track.startS)
do
	local finite = true
	for s = 0, track.finishS, 10 do
		local pos, tangent, right, width = Track.At(track, s)
		if
			pos.X ~= pos.X
			or pos.Y ~= pos.Y
			or tangent.Magnitude ~= tangent.Magnitude
			or width <= 0
		then
			finite = false
		end
		if math.abs(tangent.Magnitude - 1) > 1e-3 or math.abs(right.Magnitude - 1) > 1e-3 then
			finite = false
		end
	end
	check(
		"трасса: точки конечные, векторы единичные, ширина > 0",
		finite
	)
end
check(
	"трасса: высота только убывает от старта к финишу в целом",
	Track.At(track, track.finishS).Y < Track.At(track, track.startS).Y
)

-- Бот на каждом характере: с тормозом доезжает без вылетов, без тормоза вылетает
for _, id in { false, "Grippy", "Drift", "Heavy" } do
	local name = if id then id else "Base"
	local p = physics(id or nil)
	local run = SledBot.Run(p, true, true)
	check(
		name .. ": бот с тормозом финиширует без вылетов",
		run.finished and run.falls == 0,
		string.format(
			"%.1f с, вылетов %d, макс. скорость %.0f",
			run.time,
			run.falls,
			run.maxSpeed
		)
	)
	check(
		name .. ": есть полёт на трамплине",
		run.airTime > 0.2,
		string.format("%.2f с в воздухе", run.airTime)
	)
	local noBrake = SledBot.Run(p, false, true)
	check(
		name .. ": без тормоза трасса не проходится чисто",
		noBrake.falls > 0,
		"первый вылет на s=" .. tostring(noBrake.fallAt[1])
	)
end

-- Расчёт
do
	local p = physics()
	local state = SledSim.New(track, track.startS)
	for _ = 1, 600 do
		SledSim.Step(track, state, p, 0, true, 1 / 120)
	end
	check(
		"тормоз: санки не едут назад и не стоят",
		state.v >= p.BrakeMinSpeed - 1e-6 and state.s > track.startS
	)

	state = SledSim.New(track, track.startS)
	SledSim.Step(track, state, p, 0 / 0, false, 1 / 120)
	check(
		"NaN в руле не ломает состояние",
		state.s == state.s and state.heading == state.heading
	)

	state = SledSim.New(track, track.startS)
	local before = state.s
	SledSim.Step(track, state, p, 1, false, 0)
	SledSim.Step(track, state, p, 1, false, -1)
	check(
		"нулевой и отрицательный шаг ничего не меняют",
		state.s == before
	)

	state = SledSim.New(track, track.startS)
	for _ = 1, 2400 do
		SledSim.Step(track, state, p, 1, false, 1 / 120)
		if state.fell then
			break
		end
	end
	check("руль до упора вправо приводит к вылету", state.fell)
	local s = state.s
	SledSim.Step(track, state, p, 0, false, 1 / 120)
	check("после вылета расчёт стоит", state.s == s)

	-- Разный шаг расчёта (телефон 30 кадров против ПК 120) не должен менять результат заметно
	local saved = SledConfig.Bot.Step
	SledConfig.Bot.Step = 1 / 60
	local slow = SledBot.Run(p, true, true)
	SledConfig.Bot.Step = 1 / 240
	local fast = SledBot.Run(p, true, true)
	SledConfig.Bot.Step = saved
	check(
		"время заезда почти не зависит от шага расчёта",
		slow.finished and fast.finished and math.abs(slow.time - fast.time) < 1,
		string.format("%.2f с при 60 Гц, %.2f с при 240 Гц", slow.time, fast.time)
	)
end

if failed > 0 then
	print(string.format("\nПровалено: %d", failed))
	process.exit(1)
end
print("\nВсе тесты прошли")
