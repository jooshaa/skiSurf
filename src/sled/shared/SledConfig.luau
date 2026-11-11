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
	EdgeWidth = 1.4,
	EdgeHeight = 0.5,
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
	Rock = {
		mesh = "rbxassetid://140505658057323",
		texture = "rbxassetid://78869310967314",
		width = 11, -- ширина валуна в студах при масштабе 1
	},
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
	FogDensity = 0.15,
	FogOffset = 0.15,
	FogColor = Color3.fromRGB(205, 225, 250),
	FogDecay = Color3.fromRGB(150, 185, 235),
	FogGlare = 0.2,
	FogHaze = 1.2,
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

-- Гладкая поверхность горы (TrackMesh)
SledConfig.Mesh = {
	RingStep = 3, -- расстояние между поперечными сечениями, студов
	ChunkRings = 70, -- сечений в одном куске сетки
	Columns = 4, -- полос поперёк полотна
	StripeLength = 18, -- длина полосы оттенка на полотне: по полосам читается скорость
	EdgeInnerLift = 0.06, -- внутренняя кромка цветного края чуть выше снега
	InnerGap = 1, -- внутри шпильки склоны сходятся к центру поворота, не доходя до него на столько
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
