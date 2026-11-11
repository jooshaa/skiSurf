--!strict
-- Config: ВСЕ числа игры Deliver a Gift (CLAUDE.md, раздел 9). Только данные, без логики.
-- Пометка [ПРЕДПОЛОЖЕНИЕ]: значения нет ни в CLAUDE.md, ни в задании. Выбрано временно, проверьте.

export type Rarity = {
	name: string,
	chance: number,
	income: number,
	color: Color3,
	announce: boolean,
}

export type Mutation = {
	name: string,
	chance: number,
	multiplier: number,
	color: Color3,
	announce: boolean,
}

export type Content = { rarity: string, chance: number }

export type GiftSize = {
	id: string,
	carriers: number, -- сколько игроков несут
	speedFactor: number, -- доля обычной скорости с подарком
	partSize: number, -- сторона коробки, студов
	color: Color3,
	coinsMin: number,
	coinsMax: number,
	beam: boolean, -- столб света
	contents: { Content }, -- редкость эльфа внутри, шансы в %
}

export type District = {
	id: string,
	name: string,
	center: Vector3,
	size: Vector2, -- X и Z
	requiredSpeedLevel: number,
	ice: boolean,
	mapGiftWeight: number, -- доля маленьких подарков между пролётами
}

local Config = {}

Config.Settings = {
	StartCoins = 100, -- стартовые монеты
	IncomeInterval = 1, -- сек между начислениями дохода
	WalkSpeed = 16, -- обычная скорость персонажа (улучшений скорости пока нет)

	-- DataStore
	StoreName = "PlayerData_v1",
	DataVersion = 3, -- версия формата сохранения
	AutosaveInterval = 60, -- сек между автосохранениями (разнесено по игрокам)
	LoadRetries = 3, -- попыток загрузки при ошибке
	SaveRetries = 3, -- попыток сохранения при ошибке
	RetryBackoffBase = 1, -- сек, пауза удваивается: 1, 2, 4...
	RetryBackoffMax = 16, -- сек, потолок паузы
	LoadFailNoticeDelay = 3, -- сек до уведомления о неудачной загрузке
	BindToCloseStudioTimeout = 5, -- сек ожидания сохранений в Studio
	LockRetries = 5, -- попыток дождаться чужой блокировки
	LockRetryDelay = 2, -- сек между ними
	LockStaleSeconds = 120, -- блокировка старше этого считается мёртвой (2 x автосейв)
	KickOnLoadFailure = false, -- true: кикать при неудачной загрузке (рекомендуется для продакшена)
	BindToCloseTimeout = 25, -- сек ожидания сохранений при выключении сервера
	LoadTimeout = 120, -- сек, сколько другие системы ждут папку Elves

	-- Безопасность (CLAUDE.md, раздел 9: 5 запросов в секунду)
	RateLimitPerSecond = 5,
	RateLimitBurst = 5,

	-- Клиентские эффекты
	BobAmplitude = 0.15, -- амплитуда покачивания эльфа (студов)
	BobPeriod = 1.5, -- период покачивания (сек)
	AnnounceDuration = 4, -- сек показа объявления
	AnnounceFadeTime = 1, -- сек плавного исчезновения
}

-- Редкости эльфов: шанс (%), доход монет/сек, цвет, объявлять ли всем
Config.Rarities = {
	{
		name = "Common",
		chance = 60,
		income = 1,
		color = Color3.fromRGB(200, 200, 200),
		announce = false,
	},
	{
		name = "Rare",
		chance = 25,
		income = 3,
		color = Color3.fromRGB(60, 140, 255),
		announce = false,
	},
	{
		name = "Epic",
		chance = 10,
		income = 8,
		color = Color3.fromRGB(170, 60, 255),
		announce = false,
	},
	{
		name = "Legendary",
		chance = 4,
		income = 25,
		color = Color3.fromRGB(255, 180, 0),
		announce = true,
	},
	{
		name = "Mythic",
		chance = 1,
		income = 100,
		color = Color3.fromRGB(255, 60, 120),
		announce = true,
	},
} :: { Rarity }

-- Мутации (CLAUDE.md, раздел 5): шанс (%), множитель дохода
Config.Mutations = {
	{
		name = "None",
		chance = 80,
		multiplier = 1,
		color = Color3.fromRGB(255, 255, 255),
		announce = false,
	},
	{
		name = "Frosty",
		chance = 10,
		multiplier = 1.5,
		color = Color3.fromRGB(150, 220, 255),
		announce = false,
	},
	{
		name = "Candy",
		chance = 6,
		multiplier = 2.5,
		color = Color3.fromRGB(255, 120, 170),
		announce = false,
	},
	{
		name = "Aurora",
		chance = 3,
		multiplier = 4,
		color = Color3.fromRGB(90, 255, 190),
		announce = true,
	},
	{
		name = "Golden",
		chance = 1,
		multiplier = 8,
		color = Color3.fromRGB(255, 215, 0),
		announce = true,
	},
} :: { Mutation }

Config.Elves = {
	StartSlots = 10, -- работающих эльфов в мастерской на старте (CLAUDE.md, раздел 5)
	MaxSlots = 30, -- потолок расширения слотов (столько помещается на площадке)
	MaxStored = 200, -- всего эльфов в сохранении; лишние ждут в хранилище, ничего не теряется
	MutationPity = 40, -- после стольких эльфов без мутации следующий с мутацией
	OverflowCoinSeconds = 60, -- [ПРЕДПОЛОЖЕНИЕ] хранилище полно: эльф меняется на доход за столько секунд
}

-- Пролёт Санты
Config.Round = {
	Interval = 600, -- сек от пролёта до отлёта саней
	AnnounceLead = 10, -- сек, за сколько объявляем пролёт
	QuotaBase = 20, -- норма сервера при одном игроке
	QuotaPerExtraPlayer = 8, -- [ПРЕДПОЛОЖЕНИЕ] прибавка к норме за каждого игрока сверх первого
	QuotaBonus = 0.5, -- +50% монет при выполненной норме
	FlybyDuration = 8, -- сек полёта Санты над картой
	FlybyHeight = 140, -- высота полёта (студов)
	FlybyArcHeight = 25, -- подъём дуги в середине пути
	FlybyFrom = Vector3.new(-640, 140, 330), -- путь пролёта: из-за гор над деревней к Снежному парку
	FlybyTo = Vector3.new(640, 140, -640),
	ExtraFlybyCooldown = 300, -- сек между дополнительными пролётами (для новичков)
	DropSmall = 12, -- маленьких подарков за пролёт
	DropMedium = 2,
	DropLarge = 1,
	DepartAnimTime = 3, -- сек анимации отлёта на клиенте
	ResultShowTime = 6, -- сек показа итогов
	PollInterval = 0.5, -- сек между проверками «норма собрана или таймер вышел»
	ErrorRetryDelay = 5, -- сек паузы, если цикл упал с ошибкой
	DepartRise = 120, -- на сколько студов сани поднимаются при отлёте
	DepartRun = 200, -- и на сколько улетают вперёд
	DepartReturnDelay = 2, -- сек до возвращения саней на площадь
	DropSpread = 0.8, -- доля времени пролёта, за которую падают подарки
	FirstCycleDelay = 90, -- сек до первого пролёта на новом сервере (первая минута без спектакля)
}

-- Подарки
Config.Gifts = {
	PickupDistance = 8, -- макс. дистанция подъёма (студов)
	DeliverDistance = 16, -- макс. дистанция до саней при сдаче
	MapMin = 8, -- маленьких подарков на карте между пролётами
	MapMax = 12,
	RespawnTime = 30, -- сек до нового подарка на карте
	PickupCooldown = 1, -- сек после падения, пока подарок нельзя поднять касанием
	JoinDistance = 10, -- дистанция, с которой можно нажать «нести»
	LeashDistance = 14, -- несущий дальше этого от подарка отпускает его
	CarryHeight = 3.5, -- высота подарка над землёй при совместной переноске
	HelpIconTime = 20, -- сек показа значка «нужна помощь»
	DropFallHeight = 60, -- с какой высоты падают подарки пролёта
	DropFallTime = 2.5, -- сек падения
	SpeedTolerance = 1.5, -- во сколько раз быстрее разрешённого может двигаться подарок
	SpeedSlack = 6, -- студов запаса на рывки сети
	SpeedCheckInterval = 1, -- сек между проверками пути
	CarryLerp = 0.5, -- плавность движения общего подарка к центру несущих
	GroundProbeUp = 2, -- откуда над подарком ищем землю
	GroundProbeDown = 400,
	SpawnAttempts = 20, -- попыток найти свободную точку
	SpawnClearance = 12, -- подарки не появляются ближе к спавну
	MapSpacing = 8, -- и ближе друг к другу
	ClearGraceTime = 20, -- сек: только что уронённый подарок пролёта не исчезает при отлёте
	BeamHeight = 300, -- высота столба света над большим подарком
	BeamWidth = 5,
	HelpIconDistance = 2000, -- значок «нужна помощь» виден через всю карту

	-- CLAUDE.md, раздел 4.1. Монеты в подарке: [ПРЕДПОЛОЖЕНИЕ], в CLAUDE.md сумм нет.
	Sizes = {
		Small = {
			id = "Small",
			carriers = 1,
			speedFactor = 1,
			partSize = 2,
			color = Color3.fromRGB(220, 50, 60),
			coinsMin = 10,
			coinsMax = 20,
			beam = false,
			contents = {
				{ rarity = "Common", chance = 70 },
				{ rarity = "Rare", chance = 25 },
				{ rarity = "Epic", chance = 5 },
			},
		},
		Medium = {
			id = "Medium",
			carriers = 2,
			speedFactor = 0.8,
			partSize = 4,
			color = Color3.fromRGB(50, 110, 230),
			coinsMin = 60,
			coinsMax = 100,
			beam = false,
			contents = {
				{ rarity = "Rare", chance = 50 },
				{ rarity = "Epic", chance = 35 },
				{ rarity = "Legendary", chance = 15 },
			},
		},
		Large = {
			id = "Large",
			carriers = 3,
			speedFactor = 0.6,
			partSize = 6,
			color = Color3.fromRGB(255, 200, 40),
			coinsMin = 240,
			coinsMax = 360,
			beam = true,
			contents = {
				{ rarity = "Epic", chance = 50 },
				{ rarity = "Legendary", chance = 40 },
				{ rarity = "Mythic", chance = 10 },
			},
		},
	} :: { [string]: GiftSize },
}

-- Районы (CLAUDE.md, раздел 4.2). Доступ по скорости пока не проверяется: улучшений скорости ещё нет.
Config.Districts = {
	{
		id = "Plaza",
		name = "Площадь",
		center = Vector3.new(0, 0, 0),
		size = Vector2.new(280, 280), -- площадь, мастерские и ближние дома деревни
		requiredSpeedLevel = 1,
		ice = false,
		mapGiftWeight = 70,
	},
	{
		id = "SnowPark",
		name = "Снежный парк",
		center = Vector3.new(0, 0, -400),
		size = Vector2.new(260, 200), -- замёрзшее озеро
		requiredSpeedLevel = 2,
		ice = true,
		mapGiftWeight = 30,
	},
} :: { District }

-- Помеха «лёд» в Снежном парке
Config.Ice = {
	Thickness = 0.4, -- толщина ледяного покрытия
	Friction = 0.02, -- трение ледяного покрытия
	FrictionWeight = 100,
	CheckInterval = 1, -- сек между проверками «уронил»
	MinMoveSpeed = 4, -- студов/с: медленнее считаем, что игрок стоит, и не роняем
	SlideGrip = 1.6, -- насколько быстро скорость на льду догоняет управление (меньше = скользче)
	DropChance = 0.12, -- [ПРЕДПОЛОЖЕНИЕ] шанс уронить подарок за проверку, пока несёшь по льду
}

-- Карта (строится кодом на сервере)
Config.World = {
	GroundSize = 2048, -- запасная плита под рельефом, если в месте нет Baseplate
	SleighPosition = Vector3.new(0, 0, -26),
	SpawnPosition = Vector3.new(0, 0, 0),
	PlazaRadius = 70,
	WorkshopCount = 8, -- серверы на 8 игроков
	WorkshopRadius = 96, -- радиус круга мастерских вокруг площади
	WorkshopSize = Vector3.new(30, 1, 30),
	WorkshopWallHeight = 10,
	DeliverZoneSize = 20, -- сторона зоны касания вокруг саней
	GridStep = 5, -- шаг сетки эльфов
	GridCols = 5, -- колонок в сетке
	TreePosition = Vector3.new(0, 0, 38), -- главная ёлка на площади, за спиной у спавна
	TreeHeight = 50,
}

-- Карта: рельеф, деревня, лес. Всё строится кодом на сервере при старте.
Config.Map = {
	Seed = 2026, -- зерно: карта одинаковая на всех серверах

	-- Границы игровой зоны (студов). За ними горы и невидимая стена.
	MinX = -400,
	MaxX = 400,
	MinZ = -620,
	MaxZ = 340,
	Outer = 200, -- ширина пояса гор за границей
	WallHeight = 500,
	WallThickness = 8,

	-- Рельеф
	FlatRadius = 125, -- площадь и мастерские стоят на ровном
	FlatBlend = 150, -- на таком расстоянии ровное место переходит в холмы
	LakeShore = 14, -- ровный берег вокруг озера
	LakeBlend = 80,
	HillScale = 95, -- ширина холмов
	HillHeight = 18, -- высота холмов
	DetailScale = 32, -- мелкие сугробы
	DetailHeight = 4,
	MountainStart = 50, -- за сколько студов до границы начинается подъём
	MountainWidth = 230,
	MountainHeight = 150,
	MountainScale = 70,
	MountainPower = 1.4,
	MountainRidgeMin = 0.65, -- разброс высоты гребня
	MountainRidgeMax = 1.35,
	RockSlope = 7.5, -- перепад высоты на ячейку, с которого склон каменный
	RockMinHeight = 25,
	GlacierHeight = 120, -- выше этого вершины ледяные
	ChunkCells = 32, -- ячеек Terrain в одном куске записи
	SafetyPlateDrop = 6, -- на сколько страховочная плита утоплена под снег

	-- Тропинки
	PathWidth = 12,
	PathLength = 255, -- длина троп на запад, восток и юг
	NorthPathLength = 300, -- северная тропа до ворот Снежного парка
	RingRadius = 140, -- круговая тропа за мастерскими

	-- Деревня: кольца домов вокруг площади, лицом к центру
	HouseRings = {
		{ radius = 172, count = 12, offset = 0.5 },
		{ radius = 226, count = 16, offset = 0.5 },
	},
	HouseWidthMin = 22,
	HouseWidthMax = 30,
	HouseDepthMin = 18,
	HouseDepthMax = 22,
	HouseHeightMin = 11,
	HouseHeightMax = 14,
	StallRadius = 58, -- ярмарочные прилавки на площади
	StallCount = 4,
	BenchRadius = 64,
	BenchCount = 8,
	PlazaLampRadius = 74,
	PlazaLampSpread = 12, -- градусов: пара фонарей по бокам каждой тропы у площади
	PathLampStep = 44, -- шаг фонарей вдоль троп
	PathLampOffset = 10, -- на сколько фонарь отстоит от середины тропы
	LakeLampInset = 10, -- фонари и скамейки отстоят от кромки льда
	GateWidth = 24,
	Snowmen = 14,
	SnowmanRadiusMin = 130,
	SnowmanRadiusMax = 250,

	-- Лес
	Pines = 240,
	PineAttempts = 4000,
	PineScaleMin = 0.9,
	PineScaleMax = 1.9,
	PineSpacing = 9, -- ели не ближе этого друг к другу и к постройкам
	PineVillageChance = 0.3, -- в деревне ели реже, чем в лесу
	VillageRadius = 260,
	ForestOuter = 90, -- ели заходят на предгорья за границей
	PineMaxHeight = 80, -- выше на склонах ели не растут
	Rocks = 36,
	RockSizeMin = 4,
	RockSizeMax = 10,
	GiftClearance = 3, -- запас вокруг построек, где подарки не появляются
	-- Радиус круга, который постройка занимает на земле (для подарков и елей)
	Footprint = {
		WorkshopFactor = 0.75, -- доля ширины мастерской
		TreeFactor = 0.35, -- доля высоты главной ёлки
		HouseFactor = 0.62, -- доля большей стороны дома
		PineFactor = 1.5, -- умножается на масштаб ели
		Sleigh = 12,
		Stall = 7,
		Bench = 4,
		Lamp = 2,
		Snowman = 3,
		SnowmanSpacing = 6, -- снеговики не ближе этого к постройкам
	},
	HouseColors = 7, -- сколько цветов стен в палитре домиков

	-- 3D-модели, сгенерированные в Studio для этой игры (свои, не из магазина). Сервер загружает
	-- их при старте; если модель не загрузилась, постройка собирается из простых деталей.
	-- height: высота в мире (студов), yaw: поворот, чтобы «лицо» модели смотрело вперёд (градусов).
	Assets = {
		Sleigh = {
			mesh = "rbxassetid://91597671614359",
			texture = "rbxassetid://82702579366858",
			height = 10,
			yaw = 0,
			solid = true, -- столкновение по форме модели, а не по коробке
		},
		Snowman = {
			mesh = "rbxassetid://110954337937922",
			texture = "rbxassetid://78918260643784",
			height = 10,
			yaw = 0,
			solid = false,
		},
		Lamp = {
			mesh = "rbxassetid://84214837289403",
			texture = "rbxassetid://87267907286966",
			height = 12,
			yaw = 0,
			solid = false,
		},
		Stall = {
			mesh = "rbxassetid://89044135036401",
			texture = "rbxassetid://100908881583121",
			height = 10,
			yaw = 0,
			solid = true,
		},
	},
	AssetFolder = "MapMeshes", -- папка в ReplicatedStorage с загруженными моделями (для клиента)
	LampLightHeight = 0.82, -- доля высоты фонаря, на которой горит свет
	FlyingSleighScale = 1.5, -- во сколько раз сани в небе больше саней на площади

	-- Освещение: зимние сумерки, чтобы горели окна и гирлянды
	Lighting = {
		ClockTime = 16.6,
		GeographicLatitude = 58,
		Brightness = 2,
		Ambient = Color3.fromRGB(120, 132, 168),
		OutdoorAmbient = Color3.fromRGB(132, 146, 184),
		FogDensity = 0.12, -- плотность дымки (Atmosphere.Density)
		FogColor = Color3.fromRGB(196, 208, 232),
	},

	-- Снегопад (эффект на клиенте)
	Snowfall = {
		Rate = 140, -- снежинок в секунду
		Height = 40, -- на какой высоте над камерой рождаются
		Area = 110, -- сторона квадрата вокруг камеры
		Speed = 9,
		Lifetime = 7,
		Size = 0.35,
	},
}

-- Дневник коллекции
Config.Diary = {
	TierPercent = 10, -- награда за каждые 10%
	TierRewardCoins = 250, -- [ПРЕДПОЛОЖЕНИЕ] монет за ступень, умножается на номер ступени
}

-- Первая минута (CLAUDE.md, раздел 6)
Config.FirstMinute = {
	GiftDistance = 36, -- 10 метров от спавна (1 студ = 0,28 м)
	GiftDirection = Vector3.new(0.83, 0, -0.55), -- в какую сторону от спавна лежит первый подарок
	FirstFlybySkipIfSooner = 45, -- если общий пролёт ближе этого (сек), отдельный для новичка не нужен
	WorkshopArrowTime = 8, -- сек стрелки на мастерскую после первого эльфа
	NewbieGiftInnerRadius = 0.4, -- доля радиуса: ближе к новичку подарки не появляются
	NewbieGiftWorkshopClearance = 0.75, -- доля ширины мастерской: ближе к её центру не появляются
	NewbieGiftLifetime = 120, -- сек: несобранный дополнительный подарок исчезает
	NewbieGiftCap = 12, -- [ПРЕДПОЛОЖЕНИЕ] потолок дополнительных подарков на сервере
	ArrowBounce = 1.2, -- амплитуда прыжка стрелки (студов)
	ArrowBounceSpeed = 5,
	FirstFlybyDelay = 90, -- сек до первого пролёта для новичка
	NewbieDuration = 600, -- сек защиты новичка
	NewbieGiftCount = 3, -- [ПРЕДПОЛОЖЕНИЕ] столько маленьких подарков держим рядом с новичком
	NewbieGiftRadius = 40, -- в каком радиусе от новичка
	NewbieGiftInterval = 15, -- сек между проверками
	ArrowHeight = 6, -- высота стрелки над целью
}

-- Админ-панель: только эти UserId
Config.Admin = {
	UserIds = { 10515276399 },
	MaxCoinsGrant = 1000000,
	MaxBulkOpen = 1000,
}

return Config
