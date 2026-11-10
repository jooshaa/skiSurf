--!strict
-- Admin: команды для тестов. Выполняются только для UserId из Config.Admin.UserIds.
-- В Studio команды доступны ещё и через ServerStorage.AdminBindable (серверные тесты без клиента).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Config)
local Elves = require(ReplicatedStorage.Elves)
local Remotes = require(ReplicatedStorage.Remotes)
local RateLimit = require(script.Parent.Parent.RateLimit)
local ElfService = require(script.Parent.ElfService)
local Gifts = require(script.Parent.Gifts)
local PlayerData = require(script.Parent.PlayerData)
local Round = require(script.Parent.Round)

local A = Config.Admin

local Admin = {}

function Admin.IsAdmin(player: Player): boolean
	return table.find(A.UserIds, player.UserId) ~= nil
end

-- N открытий подарка размера sizeId тем же кодом, что и настоящее открытие (ролл редкости по
-- таблице размера, ролл мутации с защитой). Эльфы не выдаются. Возвращает текст и счётчики.
local function simulateOpenings(player: Player, size: Config.GiftSize, count: number): (string, any)
	local rarities: { [string]: number } = {}
	local mutations: { [string]: number } = {}
	-- Счётчик защиты считаем на копии: статистика не меняет профиль игрока
	local pity = player:GetAttribute("Pity") or 0
	for _ = 1, count do
		local rarity = Elves.RollContents(size.contents)
		local mutation = Elves.RollMutation(pity >= Config.Elves.MutationPity)
		pity = if mutation.name == "None" then pity + 1 else 0
		rarities[rarity.name] = (rarities[rarity.name] or 0) + 1
		mutations[mutation.name] = (mutations[mutation.name] or 0) + 1
	end
	local lines = { string.format("%s x%d (факт / Config)", size.id, count) }
	for _, content in size.contents do
		local got = (rarities[content.rarity] or 0) / count * 100
		table.insert(
			lines,
			string.format("%-10s %5.1f%% / %d%%", content.rarity, got, content.chance)
		)
	end
	for _, mutation in Config.Mutations do
		local got = (mutations[mutation.name] or 0) / count * 100
		table.insert(
			lines,
			string.format("%-10s %5.1f%% / %d%%", mutation.name, got, mutation.chance)
		)
	end
	return table.concat(lines, "\n"), { rarities = rarities, mutations = mutations, count = count }
end

-- Выполнить команду от имени игрока. Возвращает успех и текст или таблицу результата
function Admin.Execute(player: Player, action: any, a: any, b: any): (boolean, any, any?)
	if not Admin.IsAdmin(player) then
		return false, "forbidden"
	end
	if action == "coins" then
		local amount = tonumber(a)
		if not amount or amount ~= amount then
			return false, "amount"
		end
		amount = math.clamp(math.floor(amount), 0, A.MaxCoinsGrant)
		return PlayerData.AddCoins(player, amount), amount
	elseif action == "elf" then
		if not Elves.GetRarity(a) or not Elves.GetMutation(b) then
			return false, "unknown rarity or mutation"
		end
		local elf, reason = ElfService.Grant(player, a, b)
		return elf ~= nil, if elf then elf.Name else reason
	elseif action == "flyby" then
		Round.ForceDeparture()
		return true, "departure forced, flyby follows"
	elseif action == "reset" then
		PlayerData.Reset(player)
		return true, "profile reset"
	elseif action == "open" then
		local size = Config.Gifts.Sizes[tostring(a)]
		local count = tonumber(b)
		if not size or not count or count ~= count then
			return false, "size or count"
		end
		local text, data =
			simulateOpenings(player, size, math.clamp(math.floor(count), 1, A.MaxBulkOpen))
		return true, text, data
	elseif RunService:IsStudio() and action == "solo" then
		-- Тест совместной переноски одним клиентом: общий подарок поднимается в одиночку
		Gifts.DebugSetNeeded(if a == true then 1 else nil)
		return true, "solo carry " .. tostring(a == true)
	elseif RunService:IsStudio() and action == "gift" then
		-- Тест: подарок нужного размера в точке
		if typeof(b) ~= "Vector3" then
			return false, "position"
		end
		return Gifts.SpawnDrop(tostring(a), b) ~= nil, "gift"
	end
	return false, "unknown action"
end

function Admin.start()
	-- Клиенту сообщаем только, показывать ли панель; права проверяются на каждой команде
	local function mark(player: Player)
		if Admin.IsAdmin(player) then
			player:SetAttribute("IsAdmin", true)
		end
	end
	Players.PlayerAdded:Connect(mark)
	for _, player in Players:GetPlayers() do
		mark(player)
	end

	Remotes.Get("AdminAction").OnServerEvent:Connect(function(player, action, a, b)
		if not Admin.IsAdmin(player) or not RateLimit.Allow(player, "admin") then
			return
		end
		local ok, text = Admin.Execute(player, action, a, b)
		Remotes.Get("AdminResult"):FireClient(player, ok, tostring(text))
	end)

	if RunService:IsStudio() then
		local bindable = Instance.new("BindableFunction")
		bindable.Name = "AdminBindable"
		bindable.OnInvoke = function(player: any, action: any, a: any, b: any)
			if typeof(player) ~= "Instance" or not player:IsA("Player") then
				return false, "player"
			end
			return Admin.Execute(player, action, a, b)
		end
		bindable.Parent = ServerStorage
	end
end

return Admin
