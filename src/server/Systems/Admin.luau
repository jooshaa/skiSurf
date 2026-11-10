--!strict
-- Admin: команды для тестов. Выполняются только для UserId из Config.Admin.UserIds.
-- В Studio команды доступны ещё и через ServerStorage.AdminBindable (серверные тесты без клиента).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Config)
local Elves = require(ReplicatedStorage.Elves)
local ElfService = require(script.Parent.ElfService)
local Gifts = require(script.Parent.Gifts)
local PlayerData = require(script.Parent.PlayerData)
local Round = require(script.Parent.Round)

local A = Config.Admin

local Admin = {}

function Admin.IsAdmin(player: Player): boolean
	return table.find(A.UserIds, player.UserId) ~= nil
end

-- Выполнить команду от имени игрока. Возвращает успех и текст или таблицу результата
function Admin.Execute(player: Player, action: any, a: any, b: any): (boolean, any)
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
