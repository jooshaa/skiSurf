--!strict
-- Elves: поиск редкостей и мутаций, роллы, создание и сериализация эльфов.
-- Роллы вызывает только сервер; модуль общий, чтобы клиент мог читать названия и цвета.
local Config = require(script.Parent.Config)

type Rarity = Config.Rarity
type Mutation = Config.Mutation

export type ElfRecord = { rarity: string, mutation: string }

local Elves = {}

local rng = Random.new()
local nextOrder = 0

-- Взвешенный выбор по полю chance
local function weighted<T>(list: { T }): T
	local total = 0
	for _, entry in list do
		total += (entry :: any).chance
	end
	local roll = rng:NextNumber() * total
	local acc = 0
	for _, entry in list do
		acc += (entry :: any).chance
		if roll < acc then
			return entry
		end
	end
	return list[1]
end

function Elves.GetRarity(name: any): Rarity?
	for _, rarity in Config.Rarities do
		if rarity.name == name then
			return rarity
		end
	end
	return nil
end

function Elves.GetMutation(name: any): Mutation?
	for _, mutation in Config.Mutations do
		if mutation.name == name then
			return mutation
		end
	end
	return nil
end

-- Общий ролл редкости по Config.Rarities
function Elves.RollRarity(): Rarity
	return weighted(Config.Rarities)
end

-- Ролл редкости по таблице содержимого подарка (CLAUDE.md, раздел 4.1)
function Elves.RollContents(contents: { Config.Content }): Rarity
	local picked = weighted(contents)
	return Elves.GetRarity(picked.rarity) or Config.Rarities[1]
end

-- Ролл мутации; forceMutated = сработала защита (pity), None исключается
function Elves.RollMutation(forceMutated: boolean?): Mutation
	if not forceMutated then
		return weighted(Config.Mutations)
	end
	local mutated = {}
	for _, mutation in Config.Mutations do
		if mutation.name ~= "None" then
			table.insert(mutated, mutation)
		end
	end
	return weighted(mutated)
end

function Elves.DiaryKey(rarityName: string, mutationName: string): string
	return rarityName .. ":" .. mutationName
end

function Elves.ElfName(rarityName: string, mutationName: string): string
	if mutationName == "None" then
		return rarityName .. " Elf"
	end
	return mutationName .. " " .. rarityName .. " Elf"
end

-- Доход эльфа = базовый доход редкости x множитель мутации
function Elves.Income(rarity: Rarity, mutation: Mutation): number
	return rarity.income * mutation.multiplier
end

-- Создаёт StringValue эльфа с атрибутами (без родителя); nil при неверных именах
function Elves.MakeElfValue(rarityName: any, mutationName: any): StringValue?
	local rarity = Elves.GetRarity(rarityName)
	local mutation = Elves.GetMutation(mutationName or "None")
	if not rarity or not mutation then
		return nil
	end
	nextOrder += 1
	local value = Instance.new("StringValue")
	value.Name = Elves.ElfName(rarity.name, mutation.name)
	value.Value = value.Name
	value:SetAttribute("Rarity", rarity.name)
	value:SetAttribute("Mutation", mutation.name)
	value:SetAttribute("Income", Elves.Income(rarity, mutation)) -- доход из конфига, а не из сохранения
	value:SetAttribute("Order", nextOrder) -- порядок получения, для стабильной сортировки
	value:SetAttribute("Active", false)
	return value
end

-- Папка Elves -> таблица для сохранения
function Elves.Serialize(folder: Instance): { ElfRecord }
	local children = folder:GetChildren()
	table.sort(children, function(a, b)
		return (a:GetAttribute("Order") or 0) < (b:GetAttribute("Order") or 0)
	end)
	local list = {}
	for _, elf in children do
		table.insert(list, {
			rarity = elf:GetAttribute("Rarity") :: string,
			mutation = elf:GetAttribute("Mutation") :: string,
		})
	end
	return list
end

-- Таблица из сохранения -> StringValue в папке. Возвращает число восстановленных и записи
-- с неизвестной редкостью или мутацией: их нельзя терять, они сохраняются обратно как есть.
function Elves.Restore(folder: Instance, list: any): (number, { any })
	local count = 0
	local unknown = {}
	if type(list) ~= "table" then
		return count, unknown
	end
	for _, entry in ipairs(list) do
		if type(entry) == "table" then
			local value = Elves.MakeElfValue(entry.rarity, entry.mutation)
			if value then
				value.Parent = folder
				count += 1
			else
				table.insert(unknown, entry)
			end
		end
	end
	return count, unknown
end

return Elves
