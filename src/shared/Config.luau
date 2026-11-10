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
	FlybyHeight = 70, -- высота полёта (студов)
	FlybyArcHeight = 25, -- подъём дуги в середине пути
	FlybyFrom = Vector3.new(-280, 70, 110), -- путь пролёта: над площадью к Снежному парку
	FlybyTo = Vector3.new(280, 70, -340),
	ExtraFlybyCooldown = 60, -- сек между дополнительными пролётами (для новичков)
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
		size = Vector2.new(120, 120),
		requiredSpeedLevel = 1,
		ice = false,
		mapGiftWeight = 70,
	},
	{
		id = "SnowPark",
		name = "Снежный парк",
		center = Vector3.new(0, 0, -230),
		size = Vector2.new(160, 140),
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
	GroundSize = 800,
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
}

-- Дневник коллекции
Config.Diary = {
	TierPercent = 10, -- награда за каждые 10%
	TierRewardCoins = 250, -- [ПРЕДПОЛОЖЕНИЕ] монет за ступень, умножается на номер ступени
}

-- Первая минута (CLAUDE.md, раздел 6)
Config.FirstMinute = {
	GiftDistance = 36, -- 10 метров от спавна (1 студ = 0,28 м)
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
