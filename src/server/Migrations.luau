--!strict
-- Migrations: чистые функции формата сохранения (без DataStore), чтобы их можно было проверить отдельно.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Elves = require(ReplicatedStorage.Elves)

local S = Config.Settings

local Migrations = {}

-- Новый профиль (всегда новая таблица). now = время первого входа
function Migrations.DefaultProfile(now: number?): any
	return {
		version = S.DataVersion,
		coins = S.StartCoins,
		elves = {},
		slots = Config.Elves.StartSlots,
		pity = 0,
		diary = "",
		diaryTiers = 0,
		firstJoin = now or os.time(),
		tutorialDone = false,
	}
end

-- Миграции: version N -> N+1
local STEPS: { [number]: (any) -> any } = {
	-- v1 {Coins=число} -> v2 {coins, dragons}
	[1] = function(data)
		return { version = 2, coins = data.Coins or S.StartCoins, dragons = {}, lock = data.lock }
	end,
	-- v2 {coins, dragons={element, rarity}} -> v3: драконы становятся эльфами той же редкости
	[2] = function(data)
		local elves = {}
		local seen: { [string]: boolean } = {}
		local keys = {}
		if type(data.dragons) == "table" then
			for _, dragon in ipairs(data.dragons) do
				if type(dragon) == "table" then
					table.insert(elves, { rarity = dragon.rarity, mutation = "None" })
					local key = Elves.DiaryKey(tostring(dragon.rarity), "None")
					if Elves.GetRarity(dragon.rarity) and not seen[key] then
						seen[key] = true
						table.insert(keys, key)
					end
				end
			end
		end
		return {
			version = 3,
			coins = data.coins,
			elves = elves,
			slots = Config.Elves.StartSlots,
			pity = 0,
			diary = table.concat(keys, ","),
			diaryTiers = 0,
			firstJoin = 0, -- старый игрок: не новичок
			tutorialDone = true,
			lock = data.lock,
		}
	end,
}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function sanitizeInt(value: any, default: number, min: number, max: number): number
	if not isFinite(value) then
		return default
	end
	return math.clamp(math.floor(value), min, max)
end

-- Приводим сохранённые данные к текущей версии. nil -> новый профиль.
-- Возвращает nil, если данные непонятны: тогда их НЕ трогаем.
function Migrations.Migrate(raw: any, now: number?): any
	if raw == nil then
		return Migrations.DefaultProfile(now)
	end
	local data = raw
	if type(data) == "number" then
		data = { version = 1, Coins = data } -- v0: просто число
	end
	if type(data) ~= "table" then
		return nil
	end
	if type(data.version) ~= "number" then
		-- Без версии: по форме отличаем v2 {coins, dragons} от v1 {Coins}
		data.version = if data.coins ~= nil or data.dragons ~= nil then 2 else 1
	end
	if data.version > S.DataVersion then
		return nil -- формат новее этого сервера: не трогаем и не перезаписываем
	end
	while data.version < S.DataVersion do
		local step = STEPS[data.version]
		if not step then
			return nil -- нет миграции: не затираем данные дефолтом
		end
		data = step(data)
	end
	-- Санитизация: NaN, бесконечность, дробные, отрицательные, неверные типы
	data.coins = sanitizeInt(data.coins, S.StartCoins, 0, 2 ^ 53)
	if type(data.elves) ~= "table" then
		data.elves = {}
	end
	data.slots = sanitizeInt(
		data.slots,
		Config.Elves.StartSlots,
		Config.Elves.StartSlots,
		Config.Elves.MaxSlots
	)
	data.pity = sanitizeInt(data.pity, 0, 0, Config.Elves.MutationPity)
	if type(data.diary) ~= "string" then
		data.diary = ""
	end
	data.diaryTiers = sanitizeInt(data.diaryTiers, 0, 0, math.floor(100 / Config.Diary.TierPercent))
	data.firstJoin = sanitizeInt(data.firstJoin, 0, 0, 2 ^ 53)
	data.tutorialDone = data.tutorialDone == true
	return data
end

return Migrations
