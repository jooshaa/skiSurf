-- DragonConfig: все числа игры, стихии, редкости, яйца и функции-помощники
local DragonConfig = {}

-- Все настройки игры в одном месте
DragonConfig.Settings = {
	StartCoins = 100, -- стартовые монеты
	IncomeInterval = 1, -- сек между начислениями дохода

	-- DataStore
	StoreName = "PlayerData_v1",
	DataVersion = 2, -- версия формата сохранения
	AutosaveInterval = 60, -- сек между автосохранениями (разнесено по игрокам)
	LoadRetries = 3, -- попыток загрузки при ошибке
	SaveRetries = 3, -- попыток сохранения при ошибке
	RetryBackoffBase = 1, -- сек, пауза удваивается: 1, 2, 4...
	LockRetries = 5, -- попыток дождаться чужой блокировки
	LockRetryDelay = 2, -- сек между ними
	LockStaleSeconds = 120, -- блокировка старше этого считается мёртвой (2 x автосейв)
	KickOnLoadFailure = false, -- true: кикать при неудачной загрузке (рекомендуется для продакшена)
	BindToCloseTimeout = 25, -- сек ожидания сохранений при выключении сервера
	LoadTimeout = 120, -- сек, сколько другие системы ждут папку Dragons

	-- Безопасность
	MaxEggDistance = 12, -- макс. дистанция до яйца (студов)
	RateLimitPerSecond = 5, -- запросов в секунду на игрока (token bucket)
	RateLimitBurst = 5, -- макс. запросов подряд

	-- Базы
	BaseCount = 6,
	BaseRadius = 80, -- радиус круга баз вокруг спавна
	BaseSize = Vector3.new(40, 1, 40),
	GridStep = 6, -- шаг сетки драконов
	GridCols = 6, -- колонок в сетке
	MaxVisibleDragons = 30, -- макс. моделей на базе
	MaxDragons = 200, -- макс. драконов у игрока (защита размера сохранения)

	-- Клиентские эффекты
	BobAmplitude = 0.5, -- амплитуда покачивания (студов)
	BobPeriod = 1.5, -- период покачивания (сек)
	AnnounceDuration = 4, -- сек показа объявления
	AnnounceFadeTime = 1, -- сек плавного исчезновения
}

-- Стихии драконов
DragonConfig.Elements = {
	{ name = "Fire", color = Color3.fromRGB(255, 85, 0) },
	{ name = "Ice", color = Color3.fromRGB(130, 220, 255) },
	{ name = "Storm", color = Color3.fromRGB(170, 120, 255) },
	{ name = "Nature", color = Color3.fromRGB(80, 200, 80) },
	{ name = "Shadow", color = Color3.fromRGB(60, 40, 90) },
}

-- Редкости: шанс (%), доход монет/сек, цвет, объявлять ли всем
DragonConfig.Rarities = {
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
}

-- Яйца
DragonConfig.Eggs = {
	BasicEgg = { price = 50, holdDuration = 0.5, promptDistance = 10 },
}

local rng = Random.new()

-- Ролл редкости по шансам (взвешенный выбор)
function DragonConfig.RollRarity()
	local total = 0
	for _, r in ipairs(DragonConfig.Rarities) do
		total += r.chance
	end
	local roll = rng:NextNumber() * total
	local acc = 0
	for _, r in ipairs(DragonConfig.Rarities) do
		acc += r.chance
		if roll < acc then
			return r
		end
	end
	return DragonConfig.Rarities[1]
end

-- Случайная стихия
function DragonConfig.RollElement()
	return DragonConfig.Elements[rng:NextInteger(1, #DragonConfig.Elements)]
end

-- Поиск по имени
function DragonConfig.GetElement(name)
	for _, e in ipairs(DragonConfig.Elements) do
		if e.name == name then
			return e
		end
	end
	return nil
end

function DragonConfig.GetRarity(name)
	for _, r in ipairs(DragonConfig.Rarities) do
		if r.name == name then
			return r
		end
	end
	return nil
end

-- Создаёт StringValue дракона с атрибутами (без родителя); nil при неверных именах
function DragonConfig.MakeDragonValue(elementName, rarityName)
	local element = DragonConfig.GetElement(elementName)
	local rarity = DragonConfig.GetRarity(rarityName)
	if not element or not rarity then
		return nil
	end
	local v = Instance.new("StringValue")
	v.Name = element.name .. " " .. rarity.name .. " Dragon"
	v.Value = v.Name
	v:SetAttribute("Element", element.name)
	v:SetAttribute("Rarity", rarity.name)
	v:SetAttribute("Income", rarity.income) -- доход берём из конфига, а не из сохранения
	return v
end

-- Папка Dragons -> таблица для сохранения
function DragonConfig.SerializeDragons(folder)
	local list = {}
	for _, d in ipairs(folder:GetChildren()) do
		table.insert(
			list,
			{ element = d:GetAttribute("Element"), rarity = d:GetAttribute("Rarity") }
		)
	end
	return list
end

-- Таблица из сохранения -> StringValue в папке; возвращает число восстановленных
function DragonConfig.RestoreDragons(folder, list)
	local n = 0
	for _, entry in ipairs(list or {}) do
		if type(entry) == "table" then
			local v = DragonConfig.MakeDragonValue(entry.element, entry.rarity)
			if v then
				v.Parent = folder
				n += 1
			end
		end
	end
	return n
end

return DragonConfig
