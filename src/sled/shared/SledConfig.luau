--!strict
-- SledConfig: ВСЕ числа прототипа спуска (CONCEPT.md, шаг 1). Только данные, без логики.
-- Единицы: студы, секунды, радианы (углы кусков трассы в градусах, так их проще читать).

export type Piece = {
	length: number, -- длина куска, студов
	turn: number, -- на сколько градусов трасса повернёт за кусок (+ вправо, - влево)
	slope: number, -- уклон вниз, градусов (минус = подъём, трамплин)
	width: number, -- ширина полотна
	checkpoint: boolean?, -- чекпоинт в начале куска
}

export type Physics = {
	SlopeGravity: number, -- разгон на уклоне: умножается на синус уклона
	Friction: number, -- постоянное трение снега
	Drag: number, -- сопротивление воздуха, растёт с квадратом скорости
	Brake: number, -- замедление при зажатом тормозе
	MinSpeed: number, -- санки не останавливаются сами
	MinSpeedAccel: number, -- как быстро санки набирают минимальную скорость (без рывка)
	InsideLimit: number, -- предел ускорения пути по внутренней стороне поворота
	BrakeMinSpeed: number, -- до какой скорости можно затормозить
	TurnRate: number, -- поворот носа при полном отклонении руля, рад/с
	SteerResponse: number, -- как быстро санки откликаются на руль (меньше = тяжелее, с инерцией)
	Grip: number, -- как быстро движение догоняет нос (больше = цепче, меньше = занос)
	AlignRate: number, -- как быстро нос возвращается по ходу, когда руль отпущен
	MaxSlip: number, -- предел угла заноса
	MaxSlide: number, -- предел угла движения относительно трассы
	SlipDrag: number, -- потеря скорости в заносе
	SteerDrag: number, -- потеря скорости от самого руления
	Assist: number, -- 0..1: какую долю поворота трассы санки проходят сами
	AirGravity: number, -- падение в полёте
	AirTurn: number, -- доля руления в воздухе
	AirThreshold: number, -- выше этой высоты над снегом санки считаются в полёте
}

local SledConfig = {}

-- Базовый характер санок. Пресеты ниже меняют только часть полей.
SledConfig.Physics = {
	SlopeGravity = 70,
	Friction = 2,
	Drag = 0.0008,
	Brake = 55,
	MinSpeed = 12,
	MinSpeedAccel = 40,
	InsideLimit = 0.4,
	BrakeMinSpeed = 6,
	TurnRate = 1.6,
	SteerResponse = 9,
	Grip = 6,
	AlignRate = 3,
	MaxSlip = 0.6,
	MaxSlide = 1.2,
	SlipDrag = 0.4,
	SteerDrag = 0.03,
	Assist = 0.25,
	AirGravity = 110,
	AirTurn = 0.35,
	AirThreshold = 0.4,
} :: Physics

-- Три характера для сравнения (кнопки 1, 2, 3 в панели настройки)
SledConfig.Presets = {
	{ id = "Grippy", values = { Grip = 9, TurnRate = 1.7, SlipDrag = 0.7, Assist = 0.3 } },
	{
		id = "Drift",
		values = { Grip = 2.6, TurnRate = 2, SlipDrag = 0.3, MaxSlip = 0.85, Assist = 0.2 },
	},
	{
		id = "Heavy",
		values = {
			Grip = 4.5,
			TurnRate = 1.25,
			SlopeGravity = 80,
			Brake = 45,
			Assist = 0.3,
		},
	},
} :: { { id: string, values: { [string]: number } } }

-- Какие числа можно крутить ползунками на лету: имя поля, минимум, максимум
SledConfig.Tunable = {
	{ key = "SlopeGravity", min = 30, max = 140 },
	{ key = "Drag", min = 0.0003, max = 0.003 },
	{ key = "Brake", min = 15, max = 120 },
	{ key = "TurnRate", min = 0.6, max = 3.5 },
	{ key = "Grip", min = 1, max = 14 },
	{ key = "SteerResponse", min = 5, max = 30 }, -- ниже 5 бот вылетает в шикане
	{ key = "SlipDrag", min = 0, max = 1.5 },
	{ key = "Assist", min = 0, max = 0.8 },
	{ key = "AirGravity", min = 60, max = 220 },
}

SledConfig.Track = {
	Step = 4, -- шаг расчёта линии трассы
	SmoothLength = 56, -- на какой длине сглаживаются стыки кусков
	Origin = Vector3.new(0, 1400, 0), -- вершина горы
	BankGain = 10, -- наклон полотна в повороте: кривизна * BankGain
	MaxBank = 0.3,
	StartS = 24, -- где стоят санки на старте
	FinishBeforeEnd = 220, -- финишная черта за столько студов до конца полотна
	Pieces = {
		{ length = 60, turn = 0, slope = 4, width = 60 },
		{ length = 300, turn = 0, slope = 16, width = 56 },
		{ length = 260, turn = 50, slope = 14, width = 52 },
		{ length = 260, turn = -60, slope = 14, width = 52 },
		{ length = 200, turn = 0, slope = 18, width = 48, checkpoint = true },
		{ length = 200, turn = 70, slope = 13, width = 44 },
		{ length = 200, turn = -70, slope = 13, width = 44 },
		{ length = 260, turn = 0, slope = 20, width = 48 },
		{ length = 120, turn = 0, slope = 14, width = 52, checkpoint = true },
		{ length = 100, turn = 170, slope = 6, width = 50 }, -- первая шпилька: без тормоза не пройти
		{ length = 180, turn = 0, slope = 16, width = 46, checkpoint = true },
		{ length = 100, turn = -170, slope = 6, width = 50 }, -- вторая шпилька
		{ length = 220, turn = 0, slope = 22, width = 48, checkpoint = true },
		{ length = 60, turn = 0, slope = -14, width = 56 }, -- губа трамплина
		{ length = 160, turn = 0, slope = 32, width = 64 }, -- приземление
		{ length = 400, turn = 120, slope = 14, width = 50, checkpoint = true },
		{ length = 120, turn = -60, slope = 12, width = 42 },
		{ length = 120, turn = 60, slope = 12, width = 42 },
		{ length = 300, turn = 0, slope = 18, width = 56, checkpoint = true },
		{ length = 220, turn = 0, slope = 0, width = 70 }, -- выкат после финиша
	} :: { Piece },
}

SledConfig.Run = {
	CountdownStep = 0.7, -- секунд на одну лампочку отсчёта
	CountdownLights = 3,
	FallTime = 1.1, -- сколько санки кувыркаются после вылета
	FallSpin = 5, -- скорость кувырка, рад/с
	FallRoll = 0.6, -- доля кувырка вбок
	FallLift = 0.5, -- доля вертикальной скорости, с которой санки уходят в вылет
	FinishSteerHeading = 3, -- после финиша санки сами выравниваются...
	FinishSteerCenter = 0.02, -- ...и возвращаются к середине
	EndMargin = 12, -- ближе этого к концу полотна санки не едут
	BlinkRate = 10, -- миганий в секунду после респауна
	RespawnSpeed = 45,
	RespawnBlink = 1.2, -- мигание после респауна
	FinishPause = 4, -- пауза с результатом перед новым стартом
	CharacterTimeout = 10, -- сколько ждём появления частей персонажа
	MaxFrameTime = 0.1, -- длиннее кадр не считаем (подвисание); ниже 10 кадров игра замедляется
	SubStep = 1 / 90, -- шаг расчёта не длиннее этого
}

SledConfig.Input = {
	SteerRange = 0.11, -- сдвиг пальца на эту долю ширины экрана = полный руль
	SteerCurve = 1.4, -- степень кривой: больше = точнее около центра
	DeadZone = 0.04,
	KeyRampUp = 5, -- как быстро руль с клавиатуры доходит до упора, 1/с
	KeyRampDown = 9,
	CameraZone = 0.38, -- верхняя доля экрана: палец здесь крутит камеру, а не рулит
}

SledConfig.Camera = {
	Distance = 20,
	DistancePerSpeed = 0.05,
	Height = 9,
	MinClearance = 5, -- не ниже этого над снегом позади
	LookAhead = 30,
	LookAheadTime = 0.45, -- плюс скорость * это время
	LateralFollow = 0.5, -- доля бокового смещения санок в точке взгляда
	FocusAhead = 26,
	FocusHeight = 3,
	AirFocus = 0.5, -- доля высоты полёта, на которую поднимается взгляд
	TurnRate = 5, -- как быстро камера доворачивает
	FovBase = 68,
	FovExtra = 24,
	FovSpeedRef = 150,
	FovRate = 3,
	Roll = 0.06, -- наклон камеры в повороте
	SideSway = 2.2, -- на сколько студов камеру выносит наружу поворота
	ShakeAmount = 0.007, -- дрожь камеры на полной скорости, рад
	ShakeFreq = 13,
	ShakeSpeedRef = 150,
	ShakeCurve = 2, -- степень: дрожь появляется только ближе к полной скорости
	LandKick = 0.07, -- кивок камеры при приземлении, рад
	LandKickDecay = 7,
	FallFov = 60,
	OrbitSpeed = 0.006, -- поворот камеры на пиксель сдвига пальца или мыши, рад
	OrbitPitchMin = -0.15, -- насколько камеру можно опустить, рад
	OrbitPitchMax = 1.2, -- и поднять
	OrbitFocusBlend = 0.5, -- при таком отклонении камера смотрит уже на санки, а не вперёд по трассе, рад
	OrbitClearance = 0.15, -- пока камера почти сзади, она не опускается ниже снега позади, рад
	OrbitReturnDelay = 2.5, -- через столько секунд без касания камера сама возвращается за спину
	OrbitReturnRate = 3, -- как быстро возвращается, 1/с
	ZoomStep = 0.1, -- шаг колёсика мыши
	ZoomMin = 0.6,
	ZoomMax = 2.5,
}

SledConfig.Visual = {
	TrackThickness = 2,
	SegmentSamples = 2, -- один блок полотна на столько шагов линии
	CliffHeight = 70,
	CliffInset = 0.96,
	CliffDrop = 3,
	EdgeWidth = 1.4,
	EdgeHeight = 0.5,
	StripeEvery = 2, -- смена оттенка снега через столько блоков: по полосам читается скорость
	BrakeKappa = 1 / 75, -- поворот круче этого считается тормозным
	BrakeLookahead = 150, -- за сколько студов до него край становится оранжевым
	PineEvery = 72,
	PineOffset = 9,
	PineClearTurn = 200, -- ближе этого к крутому повороту ели не ставим: уступ залез бы на соседний виток
	PineLedge = 14,
	PineHeight = 26,
	PineWidth = 12,
	GateHeight = 16,
	StartGateOffset = 10, -- стартовые ворота на столько студов впереди санок
	GatePole = 1.6,
	FinishTiles = 8,
	SpawnPadSize = 12,
	SnowA = Color3.fromRGB(246, 249, 255),
	SnowB = Color3.fromRGB(226, 235, 250),
	Cliff = Color3.fromRGB(96, 104, 122),
	EdgeSafe = Color3.fromRGB(70, 140, 255),
	EdgeWarn = Color3.fromRGB(255, 150, 40),
	EdgeTurn = Color3.fromRGB(235, 60, 60),
	Pine = Color3.fromRGB(38, 110, 72),
	Trunk = Color3.fromRGB(98, 70, 50),
	Checkpoint = Color3.fromRGB(70, 210, 120),
	ClockTime = 13.5,
	Brightness = 2.6,
	FogDensity = 0.28,
	FogColor = Color3.fromRGB(205, 225, 250),
}

SledConfig.Sled = {
	RideHeight = 0.9, -- низ полозьев над линией полотна
	Lean = 0.32, -- наклон санок в повороте
	LeanRate = 8,
	DriftVisual = 0.5, -- на сколько санки видимо доворачивают нос в заносе (доля угла заноса)
	Board = Vector3.new(3.2, 0.4, 6),
	Runner = Vector3.new(0.4, 0.5, 6.6),
	NoseLength = 1.6,
	NoseLift = 0.55,
	NoseAngle = math.rad(50),
	Color = Color3.fromRGB(220, 50, 50),
	RunnerColor = Color3.fromRGB(240, 200, 70),
	RiderOffset = Vector3.new(0, 3.2, 1.2), -- где корень персонажа относительно низа санок
	-- Поза райдера: ноги вытянуты вперёд по платформе, руки тянутся к верёвке. Градусы наклона
	-- сустава вперёд. Стандартная поза «сидя» свешивает голени вниз, сквозь санки.
	Pose = {
		LeftHip = 88,
		RightHip = 88,
		LeftKnee = -4,
		RightKnee = -4,
		LeftShoulder = 32,
		RightShoulder = 32,
		LeftElbow = 42,
		RightElbow = 42,
	},
	PoseMinJoints = 4, -- если суставов найдено меньше (другой тип аватара), остаётся обычная поза сидя
	RiderLean = 0.3, -- райдер наклоняется в поворот сильнее санок, рад
	RiderTuck = 0.28, -- наклон вперёд на полной скорости, рад
	RiderBrakeLean = 0.2, -- откидывается назад на тормозе, рад
	RiderRate = 6,
	TuckSpeedRef = 150,
}

-- Готовые 3D-модели (сгенерированы в Studio). Пустая строка = модели нет, санки из блоков.
SledConfig.Assets = {
	Sled = {
		mesh = "rbxassetid://117835823962192",
		texture = "rbxassetid://132425872814667",
		length = 6, -- длина санок в студах
		yaw = 0, -- поворот модели, чтобы нос смотрел вперёд, градусов
		lift = 0, -- подъём над линией полозьев
	},
	Helmet = {
		mesh = "rbxassetid://108995259556996",
		texture = "rbxassetid://106517137680329",
		width = 2, -- ширина шлема в студах: чуть больше головы
		yaw = 0, -- поворот модели, чтобы очки смотрели вперёд, градусов
		offset = Vector3.new(0, 0.2, 0), -- сдвиг от центра головы
		hideHair = true, -- причёска и шапка торчат сквозь шлем: прячем их, пока шлем надет
	},
}

-- Снег из-под санок
SledConfig.Fx = {
	SnowColor = Color3.fromRGB(205, 220, 244), -- чуть голубее снега, иначе белое на белом не видно
	PuffStart = 0.35, -- начальный размер облачка в долях конечного
	PuffTransparency = 0, -- прозрачность облачка в начале (0 = плотное)
	Inherit = 0.6, -- доля скорости санок, которую получает снежная пыль (иначе она сразу остаётся позади)
	PuffGravity = 18,
	PuffGlow = 0,
	Spread = 22,
	EmitHeight = 0.3,
	RearTilt = 0.9, -- пыль из-под полозьев летит назад под этим углом, рад
	SpraySize = 4,
	SprayLife = 0.7,
	SpraySpeed = 10,
	SprayPerSpeed = 1, -- частиц в секунду на единицу скорости
	SprayBrake = 120, -- добавка на тормозе
	SprayMax = 220,
	CarveTilt = 1.05, -- шлейф в повороте летит вбок под этим углом, рад
	CarveBack = 0.5, -- где по длине санок рождается шлейф (доля от середины до хвоста)
	CarveSize = 8,
	CarveLife = 1,
	CarveSpeed = 22,
	CarvePerSpeed = 6, -- частиц в секунду на единицу скорости и радиан заноса
	CarveSteer = 0.15, -- сколько руль добавляет к заносу для шлейфа
	CarveMax = 260,
	LandSize = 6,
	LandLife = 0.9,
	LandSpeed = 16,
	LandSpread = 80,
	LandCount = 40,
	LandMinAir = 0.2, -- полёт короче этого приземлением не считается, секунд
	LandFullAir = 0.9, -- полёт этой длины даёт полное облако и полный кивок камеры
	TrailWidth = 0.35,
	TrailHeight = 0.06,
	TrailLife = 1.4,
	TrailColor = Color3.fromRGB(160, 180, 212),
	TrailTransparency = 0.3,
	BlinkTransparency = 0.6,
}

-- Снегопад вокруг игрока
SledConfig.Snowfall = {
	Area = 100, -- сторона объёма вокруг игрока
	Height = 28,
	Rate = 1200, -- снежинок в секунду
	Lifetime = 1.6,
	Speed = 9,
	Spread = 20,
	Size = 0.5,
	Transparency = 0.2, -- прозрачность снежинки (0 = плотная)
	TouchRateShare = 0.5, -- на телефоне снежинок меньше: доля от Rate
	Glow = 0.3,
	Wind = Vector3.new(2, 0, 1),
	LeadTime = 0.3, -- объём снегопада сдвинут вперёд на столько секунд пути; камера остаётся внутри
}

SledConfig.Hud = {
	SpeedMax = 170, -- полная полоска скорости
	BrakeButton = 0.26, -- диаметр кнопки тормоза в долях высоты экрана
	SteerBar = 0.3, -- ширина полоски руля в долях ширины экрана
}

SledConfig.Bot = {
	LookTime = 1.3, -- бот смотрит вперёд на столько секунд пути
	BrakeMargin = 0.8, -- тормозит, если поворот требует больше этой доли TurnRate
	CenterGain = 0.03,
	MaxAngle = 0.5, -- под каким углом к трассе бот возвращается к середине
	MaxFalls = 50,
	HeadingGain = 4,
	MaxTime = 300,
	Step = 1 / 120, -- как у игрока при 60 кадрах: два шага расчёта на кадр
}

return SledConfig
