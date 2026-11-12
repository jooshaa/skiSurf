--!strict
-- SledConfig: ВСЕ числа прототипа спуска (CONCEPT.md, шаг 1). Только данные, без логики.
-- Единицы: студы, секунды, радианы (углы кусков трассы в градусах, так их проще читать).

export type Piece = {
	length: number, -- длина куска, студов
	turn: number, -- на сколько градусов трасса повернёт за кусок (+ вправо, - влево)
	slope: number, -- уклон вниз, градусов (минус = подъём, трамплин)
	width: number, -- ширина полотна
	checkpoint: boolean?, -- чекпоинт в начале куска
	cave: boolean?, -- кусок идёт внутри лавовой пещеры
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
	EdgeInset: number, -- санки останавливаются у борта за столько студов до края полотна
	BankHit: number, -- доля скорости, которую съедает удар в борт под прямым углом
	BankDrag: number, -- как быстро тает скорость, пока санки трутся о борт, 1/с
	BankShock: number, -- доля скорости, которую съедает само касание борта
	BankHeading: number, -- круче этого угла нос в борт не смотрит, даже если туда рулят, рад
	BankPush: number, -- под каким углом борт отталкивает санки обратно, рад
	BankRegrip: number, -- повторное касание раньше этого времени не считается новым ударом, с
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
	TurnRate = 1.85,
	SteerResponse = 18,
	Grip = 7,
	AlignRate = 3,
	MaxSlip = 0.6,
	MaxSlide = 1.2,
	SlipDrag = 0.4,
	SteerDrag = 0.03,
	Assist = 0.25,
	AirGravity = 110,
	AirTurn = 0.35,
	AirThreshold = 0.4,
	EdgeInset = 2,
	BankHit = 0.9,
	BankDrag = 3,
	BankShock = 0.4,
	BankHeading = 0.5,
	BankPush = 0.12,
	BankRegrip = 0.8,
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
	Origin = Vector3.new(0, 2600, 0), -- вершина горы
	BankGain = 10, -- наклон полотна в повороте: кривизна * BankGain
	MaxBank = 0.3,
	StartS = 24, -- где стоят санки на старте
	FinishBeforeEnd = 240, -- финишная черта за столько студов до конца полотна
	MinGap = 30, -- между краями разных витков трассы остаётся не меньше этого (проверяет тест)
	GapSkip = 400, -- точки ближе этого по пути считаются одним витком
	Pieces = {
		{ length = 80, turn = 0, slope = 4, width = 84 },
		{ length = 320, turn = 0, slope = 16, width = 78 },
		{ length = 300, turn = 50, slope = 14, width = 72 },
		{ length = 300, turn = -60, slope = 14, width = 72 },
		{ length = 240, turn = 0, slope = 18, width = 68, checkpoint = true },
		{ length = 240, turn = 70, slope = 13, width = 64 },
		{ length = 240, turn = -70, slope = 13, width = 64 },
		{ length = 280, turn = 0, slope = 20, width = 68 },
		-- Первая лавовая пещера: полого, чтобы успевать объезжать лаву
		{ length = 220, turn = 0, slope = 12, width = 62, checkpoint = true, cave = true },
		{ length = 260, turn = 40, slope = 10, width = 58, cave = true },
		{ length = 260, turn = -40, slope = 10, width = 58, cave = true },
		{ length = 140, turn = 0, slope = 18, width = 66, checkpoint = true },
		{ length = 105, turn = 168, slope = 8, width = 46 }, -- первая шпилька: без тормоза в борт
		{ length = 240, turn = 0, slope = 20, width = 58, checkpoint = true },
		{ length = 105, turn = -168, slope = 8, width = 46 }, -- вторая шпилька
		{ length = 240, turn = 0, slope = 22, width = 68, checkpoint = true },
		{ length = 60, turn = 0, slope = -14, width = 76 }, -- губа трамплина
		{ length = 180, turn = 0, slope = 32, width = 88 }, -- приземление
		{ length = 440, turn = 120, slope = 14, width = 70, checkpoint = true },
		{ length = 150, turn = -60, slope = 12, width = 60 },
		{ length = 150, turn = 60, slope = 12, width = 60 },
		-- Вторая половина горы
		{ length = 320, turn = 0, slope = 19, width = 76, checkpoint = true }, -- разгон
		{ length = 360, turn = -110, slope = 12, width = 70 }, -- длинная левая дуга
		{ length = 200, turn = 0, slope = 17, width = 66 },
		{ length = 130, turn = 45, slope = 12, width = 60, checkpoint = true }, -- слалом
		{ length = 130, turn = -45, slope = 12, width = 60 },
		{ length = 130, turn = 45, slope = 12, width = 60 },
		{ length = 130, turn = -45, slope = 12, width = 60 },
		{ length = 260, turn = 0, slope = 21, width = 70, checkpoint = true },
		{ length = 50, turn = 0, slope = -12, width = 76 }, -- второй трамплин
		{ length = 150, turn = 0, slope = 30, width = 88 },
		{ length = 300, turn = 90, slope = 16, width = 70, checkpoint = true },
		{ length = 105, turn = -168, slope = 8, width = 46 }, -- третья шпилька
		{ length = 240, turn = 0, slope = 20, width = 58, checkpoint = true },
		{ length = 105, turn = 168, slope = 8, width = 46 }, -- четвёртая шпилька
		{ length = 300, turn = 0, slope = 20, width = 70, checkpoint = true },
		{ length = 400, turn = -90, slope = 14, width = 72 },
		-- Вторая лавовая пещера: полого, чтобы успевать объезжать лаву
		{ length = 220, turn = 0, slope = 12, width = 62, checkpoint = true, cave = true },
		{ length = 260, turn = -40, slope = 10, width = 58, cave = true },
		{ length = 260, turn = 40, slope = 10, width = 58, cave = true },
		{ length = 360, turn = 0, slope = 18, width = 80, checkpoint = true }, -- финишная прямая
		{ length = 240, turn = 0, slope = 0, width = 90 }, -- выкат после финиша
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
	KeyRampUp = 8, -- как быстро руль с клавиатуры доходит до упора, 1/с
	KeyRampDown = 9,
	CameraKeySpeed = 220, -- клавиши Q и E двигают камеру как сдвиг мыши на столько пикселей в секунду
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
	BankKick = 0.05, -- кивок камеры при ударе о снежный борт, рад
	HitKick = 0.09, -- кивок камеры при наезде на препятствие, рад
	FallFov = 60,
	OrbitSpeed = 0.006, -- поворот камеры на пиксель сдвига пальца или мыши, рад
	OrbitPitchDefault = 0.28, -- высота камеры на старте: трасса видна сверху, рад
	OrbitPitchMin = -0.1, -- насколько камеру можно опустить, рад
	OrbitPitchMax = 1.25, -- и поднять
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
	CliffMaxHeight = 2000, -- скала под трассой тянется до дна долины, но не выше этого
	CliffInset = 0.96,
	CliffDrop = 3,
	EdgeWidth = 2.2,
	EdgeHeight = 1.1,
	StripeEvery = 2, -- смена оттенка снега через столько блоков: по полосам читается скорость
	BrakeKappa = 1 / 75, -- поворот круче этого считается тормозным
	BrakeLookahead = 150, -- за сколько студов до него край становится оранжевым
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
	Pine = {
		mesh = "rbxassetid://80433606563396",
		texture = "rbxassetid://99120275467953",
		height = 26, -- высота ели в студах при масштабе 1
	},
	Yeti = {
		mesh = "rbxassetid://136535407749915",
		texture = "rbxassetid://96111302308302",
		height = 17, -- рост йети в студах
		yaw = 0, -- поворот модели, чтобы лицо смотрело на трассу, градусов
	},
	Rock = {
		mesh = "rbxassetid://140505658057323",
		texture = "rbxassetid://78869310967314",
		width = 11, -- ширина валуна в студах при масштабе 1
	},
	MysteryBox = {
		mesh = "rbxassetid://70369734584582",
		texture = "rbxassetid://78510357381206",
		size = 3.6, -- размер 3D-куба со знаком вопроса
	},
	Rocket = {
		mesh = "rbxassetid://73370285848875",
		texture = "rbxassetid://128867327938659",
		length = 4.2, -- длина 3D-ракеты в полёте
	},
	Firework = {
		mesh = "rbxassetid://99070122163489",
		texture = "rbxassetid://87574745297829",
		length = 3.2, -- длина 3D-петарды салюта
	},
}

-- Указатели поворота: щиты со стрелками на внешней стороне дуги
SledConfig.Signs = {
	Kappa = 1 / 360, -- поворот круче этого получает указатели
	Every = 44, -- шаг между щитами вдоль трассы
	MinShoulder = 12, -- на склоне уже этого щит не ставим
	Offset = 5, -- от края трассы наружу
	Post = 0.5,
	PostHeight = 3.5, -- от снега до низа щита
	Sink = 4, -- столб уходит в снег
	Board = Vector3.new(8, 4, 0.4),
	Arrows = 2, -- стрелок на щите
	ArrowGap = 3.2,
	ArrowRun = 1.5, -- ширина стрелки
	ArrowRise = 1.4, -- полувысота стрелки
	ArrowThick = 0.7,
	ArrowDepth = 0.3,
	PostColor = Color3.fromRGB(60, 64, 76),
	BoardColor = Color3.fromRGB(255, 205, 40),
	BoardSharp = Color3.fromRGB(235, 60, 60), -- тормозной поворот
	ArrowColor = Color3.fromRGB(24, 26, 34),
}

-- Йети у трассы
SledConfig.Yeti = {
	At = { 0.1, 0.27, 0.45, 0.6, 0.78, 0.93 }, -- где стоят: доля пути от старта до финиша
	MinShoulder = 20,
	Search = 160, -- ищем подходящий склон не дальше этого от точки
	Offset = 11, -- от края трассы
	Clear = 16, -- ближе этого к йети не растут ели и не лежат валуны
	Scale = 1,
	Sink = 0.8,
}

-- Метель: участки трассы, где снег валит стеной и дальше хуже видно
SledConfig.Blizzard = {
	-- Доли пути до финиша. Пещеры занимают 0,22–0,31 и 0,88–0,96: там снега нет.
	Zones = {
		{ from = 0.09, to = 0.17 },
		{ from = 0.33, to = 0.43 },
		{ from = 0.52, to = 0.6 },
		{ from = 0.68, to = 0.78 },
	},
	Fade = 0.025, -- метель нарастает и стихает на такой доле пути
	Rate = 3, -- во сколько раз больше снежинок
	Wind = Vector3.new(34, -6, 10), -- ветер в метель (добавляется к обычному)
	FogDensity = 0.62,
	FogOffset = 0,
	FogHaze = 2.6,
	Smooth = 2.5, -- как быстро меняется погода, 1/с
	-- Порывы: крупные хлопья, которые несёт ветром поперёк экрана
	GustRate = 700, -- хлопьев в секунду в разгар метели
	GustSize = 1.5,
	GustLifetime = 1.1,
	GustSpeed = 14,
	GustPush = 2.2, -- во сколько раз ветер сильнее толкает крупные хлопья
	GustTransparency = 0.35,
	GustVary = 0.7, -- самые быстрые и короткие хлопья: доля от обычных
	GustFade = 0.2, -- доля жизни хлопья на появление и на исчезновение
	TouchRate = 2, -- на телефоне в метель снежинок больше только во столько раз
	Epsilon = 0.005, -- меньшее изменение силы метели не применяется
}

-- Окружение трассы: на езду не влияет
SledConfig.Scenery = {
	Seed = 7, -- одно и то же число = один и тот же лес
	-- Снежный склон от края трассы
	ShoulderWidth = 46, -- на сколько студов склон уходит в сторону
	ShoulderMin = 6, -- уже этого склон не строим (витки шпильки слишком близко)
	ShoulderSlope = math.rad(30), -- наклон склона вниз (у сетки: после перегиба)
	ShoulderThickness = 6,
	ShoulderDrop = 0.15, -- склон чуть ниже полотна, чтобы поверхности не мерцали
	Overlap = 0.6, -- запас длины блоков, чтобы не было щелей
	NeighbourGuard = 12, -- точки трассы ближе этого по пути не проверяем: это тот же блок
	InnerOverlap = 2, -- внутри шпильки склоны сходятся в центре с таким запасом: дыры не остаётся
	LayerStagger = 0.12, -- соседние блоки склона и скалы сдвинуты по глубине, чтобы не мерцали
	NeighbourMargin = 5, -- зазор до соседнего витка
	SnowBankA = Color3.fromRGB(236, 242, 252),
	SnowBankB = Color3.fromRGB(228, 236, 250),
	-- Скала под склоном
	SkirtSlope = math.rad(62),
	SkirtLength = 160,
	SkirtThickness = 10,
	InnerKappa = 1 / 400, -- поворот круче этого: с внутренней стороны скалу не ставим
	RockA = Color3.fromRGB(104, 112, 130),
	RockB = Color3.fromRGB(86, 94, 114),
	-- Дно долины
	FloorDepth = 220, -- ниже самой низкой точки трассы
	FloorTile = 2048,
	FloorThickness = 8,
	FloorMargin = 5000, -- дно выходит за трассу на столько студов
	FloorColor = Color3.fromRGB(222, 232, 248),
	-- Дальние вершины
	PeakCount = 16,
	PeakDistanceMin = 1500,
	PeakDistanceMax = 3200,
	PeakWidthMin = 1500,
	PeakWidthMax = 2600,
	PeakHeightMin = 1300,
	PeakHeightMax = 2000, -- деталь не бывает выше 2048
	PeakCap = 0.42, -- доля высоты под снежной шапкой
	PeakCapWiden = 1.04,
	PeakCapLift = 6,
	PeakRock = Color3.fromRGB(92, 102, 126),
	PeakSnow = Color3.fromRGB(240, 245, 255),
	-- Лес и валуны на склонах
	TreeMinShoulder = 16, -- на склоне уже этого ничего не растёт
	CaveGuard = 14, -- и ближе этого к пещере тоже
	TreeShadows = true,
	RockShadows = false,
	TreeChance = 0.24, -- шанс ели на 8 студов склона
	TreeEdgeGap = 7, -- не ближе этого к краю трассы
	TreeOuterGap = 4,
	TreeScaleMin = 0.6,
	TreeScaleMax = 1.35,
	TreeSink = 1.5, -- ствол утоплен в снег
	RockChance = 0.07, -- на 8 студов склона
	RockScaleMin = 0.5,
	RockScaleMax = 1.4,
	RockSink = 1.5,
	RockBlockHeight = 0.6, -- запасной валун из блока: высота и глубина в долях ширины
	RockBlockDepth = 0.8,
	-- Флажки
	FlagEvery = 48,
	FlagOffset = 1.5, -- от края трассы наружу
	FlagHeight = 6,
	FlagSink = 4, -- столбик уходит в снег на столько
	FlagPole = 0.35,
	FlagSize = Vector2.new(2.4, 1.5),
	FlagPoleColor = Color3.fromRGB(60, 64, 76),
	-- Свет и небо
	ClockTime = 10.2, -- утро: длинные синие тени поперёк трассы
	Latitude = 38,
	Brightness = 2.1,
	Ambient = Color3.fromRGB(70, 82, 110),
	OutdoorAmbient = Color3.fromRGB(128, 148, 190),
	SunTint = Color3.fromRGB(255, 244, 226),
	ShadowSoftness = 0.25,
	EnvironmentDiffuse = 1,
	EnvironmentSpecular = 0.4,
	Exposure = -0.35, -- снег не должен выгорать в белое: на нём видны полосы и тени
	FogDensity = 0.1, -- дальние горы видны сквозь дымку, но их появление на слабой графике скрыто
	FogOffset = 0.25,
	FogColor = Color3.fromRGB(205, 225, 250),
	FogDecay = Color3.fromRGB(150, 185, 235),
	FogGlare = 0.2,
	FogHaze = 0.9,
	Saturation = 0.12,
	Contrast = 0.06,
	Tint = Color3.fromRGB(255, 252, 246),
	BloomIntensity = 0.25,
	BloomSize = 24,
	BloomThreshold = 2.2,
	SunRays = 0.06,
	SunRaysSpread = 0.6,
	CloudCover = 0.58,
	CloudDensity = 0.45,
	CloudColor = Color3.fromRGB(255, 255, 255),
}

-- Дальние горы вокруг долины (Peaks)
SledConfig.Peaks = {
	Seed = 11,
	Variants = 4, -- разных форм вершин
	Count = 20, -- гор вокруг долины
	Rings = 8, -- колец точек от макушки к подножию
	Segments = 18, -- точек в кольце
	Radius = 1000, -- полуширина подножия (деталь не бывает больше 2048)
	Height = 1900,
	Profile = 1.25, -- больше = острее пик и шире подножие
	Jitter = 0.3, -- сдвиг точек по кругу, доля шага
	Rough = 0.1, -- неровность высоты граней, доля
	Ridge = 0.9, -- насколько отроги длиннее впадин
	RidgeCount = 1.6, -- сколько отрогов по кругу
	RidgeMin = 0.45,
	SnowLine = 0.34, -- выше этой доли высоты лежит снег
	SnowRough = 0.05, -- неровность границы снега, доля высоты
	ToneSteps = 3, -- оттенков между двумя цветами
	RockA = Color3.fromRGB(84, 96, 128),
	RockB = Color3.fromRGB(112, 124, 152),
	SnowA = Color3.fromRGB(244, 248, 255),
	SnowB = Color3.fromRGB(214, 228, 250),
	ScaleMin = 0.5,
	ScaleMax = 1,
	TallMin = 0.7, -- дополнительное сжатие по высоте
	TallMax = 1,
	Spread = 0.35, -- разброс по кругу, доля шага
	DistanceMin = 250, -- от дальней точки трассы до подножия
	DistanceMax = 1500,
	Sink = 40, -- подножие утоплено ниже дна долины
	-- Ближние горы вдоль трассы (видны и на слабой графике)
	NearEvery = 300, -- одна гора на столько студов трассы, стороны чередуются
	NearLateralMin = 110, -- от оси трассы до ближнего края подножия
	NearLateralMax = 260,
	NearScaleMin = 0.28,
	NearScaleMax = 0.5,
	NearRiseMin = 70, -- макушка выше трассы на столько
	NearRiseMax = 280,
}

-- Гладкая поверхность горы (TrackMesh)
SledConfig.Mesh = {
	RingStep = 3, -- расстояние между поперечными сечениями, студов
	ChunkRings = 70, -- сечений в одном куске сетки
	Columns = 4, -- полос поперёк полотна
	StripeLength = 18, -- длина полосы оттенка на полотне: по полосам читается скорость
	EdgeInnerLift = 0.06, -- внутренняя кромка цветного края чуть выше снега
	InnerGap = 1, -- внутри шпильки склоны сходятся к центру поворота, не доходя до него на столько
	MeasureYield = 150, -- через столько сечений расчёт склонов уступает кадр серверу
	ReachSmooth = 3, -- сглаживание ширины склона, сечений в каждую сторону
	MidShare = 0.45, -- где у склона перегиб, доля ширины
	NearSlope = math.rad(9), -- наклон склона до перегиба (после: Scenery.ShoulderSlope)
	ShoulderNoise = 0.16, -- неровность внешней кромки склона, доля ширины
	ShoulderBump = 1.6, -- бугры на перегибе, студов
	SkirtMidShare = 0.35, -- где у скалы перегиб, доля длины
	SkirtJitter = 10, -- изломы скалы, студов
	NoiseScale = 0.021, -- частота неровностей вдоль трассы
	NoiseLane = 7.3, -- сдвиг шума между полосами
	ShadeStretch = 2.5, -- оттенки меняются чаще, чем форма
	ShadeSteps = 4, -- ступеней оттенка между двумя цветами
}

-- Снег из-под санок
SledConfig.Fx = {
	SnowColor = Color3.fromRGB(226, 236, 252), -- чуть голубее снега, иначе белое на белом не видно
	PuffStart = 0.35, -- начальный размер облачка в долях конечного
	PuffTransparency = 0.6, -- прозрачность облачка в начале (0 = плотное)
	Inherit = 0.6, -- доля скорости санок, которую получает снежная пыль (иначе она сразу остаётся позади)
	PuffGravity = 18,
	PuffGlow = 0.15,
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
	BankPuff = 0.6, -- доля облака приземления при ударе о борт
	HitPuff = 1, -- то же при наезде на препятствие
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

-- Препятствия на полотне. Наезд стоит скорости и отбрасывает в сторону; потерять заезд нельзя.
SledConfig.Obstacles = {
	Seed = 3, -- одно и то же число = одна и та же расстановка
	HitRegrip = 0.5, -- повторный удар раньше этого времени не считается, с
	Push = 0.22, -- на какой угол санки отбрасывает в сторону, рад
	StartClear = 420, -- от старта до первого препятствия
	FinishClear = 200, -- перед финишем чисто
	EdgeGap = 4, -- препятствие не ближе этого к снежному борту
	SteepPitch = math.rad(25), -- круче этого (приземление) и на подъёме (трамплин) препятствий нет
	JumpGuard = 100, -- и на столько студов вокруг
	SharpKappa = 1 / 90, -- в поворотах круче этого препятствий нет
	CaveGuard = 40, -- сугробы и йети не ближе этого к входу в пещеру
	-- Сугроб: тормозит несильно
	Drift = {
		radius = 6.5,
		keep = 0.7, -- доля скорости, которая остаётся после наезда
		every = 210, -- шаг вдоль трассы
		spread = 0.8, -- как далеко от оси, доля свободной ширины
		height = 0.5, -- высота в долях радиуса
		color = Color3.fromRGB(196, 212, 240),
	},
	-- Йети ходит поперёк трассы
	Yeti = {
		radius = 5.5,
		keep = 0.45,
		every = 560,
		first = 700, -- где стоит первый
		sway = 18, -- на сколько студов отходит от своей точки
		rate = 0.9, -- как быстро ходит, рад/с
		height = 13,
		waddle = 0.12, -- раскачивание при ходьбе, рад
		waddleRate = 6,
		knockTime = 0.9, -- сколько йети кружится после удара, с
		knockSpin = 14, -- рад/с
	},
	-- Лужа лавы в пещере
	Lava = {
		radius = 7,
		keep = 0.5,
		every = 95,
		enter = 80, -- от входа в пещеру до первой лужи
		spread = 0.7,
		thickness = 0.35,
		rim = 1.2, -- каменный ободок шире лужи на столько
		color = Color3.fromRGB(255, 120, 20),
		rimColor = Color3.fromRGB(46, 40, 44),
	},
}

-- Лавовая пещера над кусками трассы с пометкой cave
SledConfig.Cave = {
	RingStep = 12, -- шаг сводов вдоль трассы
	Segments = 7, -- плит в одном своде
	Side = 7, -- от края полотна до стены: здесь течёт лава
	Height = 28, -- высота свода над осью
	Thickness = 6,
	Sink = 4, -- свод начинается ниже полотна, чтобы под стеной не было щели
	Overlap = 0.8,
	Rock = Color3.fromRGB(58, 52, 60),
	RockB = Color3.fromRGB(70, 62, 68),
	SnowCap = 3, -- сколько верхних плит снаружи покрыто снегом
	SnowThickness = 2.5,
	SnowColor = Color3.fromRGB(236, 242, 252),
	PortalGrow = 4, -- входная арка больше свода на столько
	PortalDepth = 6,
	PortalColor = Color3.fromRGB(150, 200, 235),
	LavaDrop = 0.1, -- лава у стен чуть ниже полотна
	LavaThickness = 1,
	LavaColor = Color3.fromRGB(255, 110, 20),
	LightEvery = 72,
	LightRange = 60,
	LightBrightness = 2.2,
	LightColor = Color3.fromRGB(255, 140, 60),
	LightHeight = 3,
	-- Что видит игрок внутри (клиент)
	Fade = 50, -- свет меняется на таком пути от входа, студов
	Smooth = 4, -- и не быстрее этого, 1/с
	Brightness = 0.25,
	Exposure = -0.1,
	Ambient = Color3.fromRGB(70, 38, 30),
	OutdoorAmbient = Color3.fromRGB(60, 36, 34),
	FogColor = Color3.fromRGB(120, 60, 40),
	FogDensity = 0.3,
	CameraHeight = 17, -- камера не выше этого над полотном, иначе она окажется над сводом
	Epsilon = 0.005,
}

SledConfig.Hud = {
	SpeedMax = 170, -- полная полоска скорости
	BrakeButton = 0.26, -- диаметр кнопки тормоза в долях высоты экрана
	SteerBar = 0.3, -- ширина полоски руля в долях ширины экрана
}

SledConfig.Bot = {
	LookTime = 1.3, -- бот смотрит вперёд на столько секунд пути
	BrakeMargin = 0.9, -- тормозит, если поворот требует больше этой доли TurnRate
	CenterGain = 0.03,
	MaxAngle = 0.5, -- под каким углом к трассе бот возвращается к середине
	MaxFalls = 50,
	HeadingGain = 4,
	MaxTime = 300,
	Step = 1 / 120, -- как у игрока при 60 кадрах: два шага расчёта на кадр
	AvoidTime = 1.6, -- бот замечает препятствие за столько секунд пути
	AvoidMin = 40, -- и не ближе этого, студов
	AvoidMargin = 4, -- объезжает с таким запасом
	AvoidGain = 0.06, -- как резко уходит в сторону, рад на студ
	AvoidBrake = 9, -- тормозит, если до линии объезда дальше этого, студов
}

SledConfig.Powerups = {
	BoxLines = { 0.06, 0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.84, 0.92 }, -- 10 линий подарков по всей трассе
	BoxesPerLine = 4, -- по 4 больших подарка в ряд, чтобы легко брать на любой скорости
	BoxSpread = 0.72, -- на какую долю свободной ширины расставляются боксы
	BoxSize = Vector3.new(5.2, 5.2, 5.2),
	BoxFloat = 3.6, -- высота над полотном
	BoxRadius = 9.5, -- увеличенный радиус взятия санями
	BoxMagnetRadius = 16.5, -- радиус магнитного притяжения подарка к санкам
	BoxRespawn = 2.5, -- секунд до повторного появления
	SpinRate = 2.2, -- скорость вращения бокса, рад/с
	BobRate = 3.2,
	BobHeight = 0.55,
	RouletteDuration = 0.65, -- сколько длится прокрутка предмета на экране

	Rocket = {
		Speed = 225,
		MaxRange = 620,
		HitRadius = 9.5,
		StunDuration = 1.4,
		SpeedFactor = 0.28,
		SpinSpeed = 16,
	},
	Fireworks = {
		VolleyCount = 5,
		SpreadAngles = { -0.24, -0.12, 0, 0.12, 0.24 },
		Speed = 165,
		Range = 280,
		ExplosionRadius = 16,
		StunDuration = 1.15,
		SpeedFactor = 0.35,
		SpinSpeed = 12,
	},
	Boost = {
		ExtraSpeed = 55,
		Duration = 2.8,
	},
	Shield = {
		Duration = 7.0,
	},
}

SledConfig.Rivals = {
	Count = 3,
	Names = { "Frosty", "Blaze", "Shadow" },
	SledColors = {
		Color3.fromRGB(45, 180, 255),
		Color3.fromRGB(255, 95, 40),
		Color3.fromRGB(175, 65, 245),
	},
	RunnerColors = {
		Color3.fromRGB(20, 45, 75),
		Color3.fromRGB(65, 25, 15),
		Color3.fromRGB(40, 18, 55),
	},
	StartOffsets = { -5.0, 3.5, 7.5 }, -- смещение от оси на старте
}

return SledConfig
