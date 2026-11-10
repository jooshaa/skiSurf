-- EggSystem: открытие яиц (только на сервере), token bucket, общий цикл дохода с кэшем
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DragonConfig = require(ReplicatedStorage:WaitForChild("DragonConfig"))
local S = DragonConfig.Settings
local Announce = ReplicatedStorage:WaitForChild("Announce")
local Notify = ReplicatedStorage:WaitForChild("Notify")

local EGG_NAME = "BasicEgg"
local eggPart = Workspace:WaitForChild(EGG_NAME, 30)
if not eggPart then
	warn(
		"[EggSystem] В Workspace нет "
			.. EGG_NAME
			.. ", система яиц отключена"
	)
	return
end
local eggConfig = DragonConfig.Eggs[EGG_NAME]

-- ProximityPrompt на яйце
local prompt = eggPart:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
prompt.ActionText = "Открыть яйцо"
prompt.ObjectText = eggConfig.price .. " монет"
prompt.HoldDuration = eggConfig.holdDuration
prompt.MaxActivationDistance = eggConfig.promptDistance
prompt.RequiresLineOfSight = false
prompt.Parent = eggPart

-- Лимит запросов: token bucket на игрока
local buckets = {}
local function allowRequest(player)
	local now = os.clock()
	local b = buckets[player]
	if not b then
		b = { tokens = S.RateLimitBurst, last = now }
		buckets[player] = b
	end
	b.tokens = math.min(S.RateLimitBurst, b.tokens + (now - b.last) * S.RateLimitPerSecond)
	b.last = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

-- Кэш дохода: пересчитываем только при изменении папки Dragons
local income = {} -- player -> монет/сек
local incomeConns = {} -- player -> соединения

local function recomputeIncome(player, folder)
	local total = 0
	for _, d in ipairs(folder:GetChildren()) do
		total += d:GetAttribute("Income") or 0
	end
	income[player] = total
end

local function onPlayerAdded(player)
	local folder = player:WaitForChild("Dragons", S.LoadTimeout)
	if not folder or player.Parent ~= Players then
		return
	end
	incomeConns[player] = {
		folder.ChildAdded:Connect(function()
			recomputeIncome(player, folder)
		end),
		folder.ChildRemoved:Connect(function()
			recomputeIncome(player, folder)
		end),
	}
	recomputeIncome(player, folder)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(player)
	for _, c in ipairs(incomeConns[player] or {}) do
		c:Disconnect()
	end
	incomeConns[player] = nil
	income[player] = nil
	buckets[player] = nil
end)

-- Проверка дистанции персонажа до яйца (сервер не верит клиенту)
local function isNearEgg(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - eggPart.Position).Magnitude <= S.MaxEggDistance
end

-- Открытие яйца
local function openEgg(player)
	if not allowRequest(player) then
		return
	end
	if not isNearEgg(player) then
		warn("[EggSystem] " .. player.Name .. " слишком далеко от яйца")
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	local dragons = player:FindFirstChild("Dragons")
	if not coins or not dragons then
		Notify:FireClient(
			player,
			"Данные ещё загружаются...",
			Color3.fromRGB(255, 200, 80)
		)
		return
	end

	-- Лимит драконов: защищает размер сохранения и число инстансов
	if #dragons:GetChildren() >= S.MaxDragons then
		Notify:FireClient(
			player,
			"Достигнут лимит драконов (" .. S.MaxDragons .. ")",
			Color3.fromRGB(255, 120, 80)
		)
		return
	end

	-- Цена только из серверного конфига
	if coins.Value < eggConfig.price then
		Notify:FireClient(
			player,
			"Недостаточно монет, нужно " .. eggConfig.price,
			Color3.fromRGB(255, 120, 80)
		)
		return
	end
	coins.Value -= eggConfig.price

	-- Роллим и создаём дракона
	local rarity = DragonConfig.RollRarity()
	local element = DragonConfig.RollElement()
	local dragon = DragonConfig.MakeDragonValue(element.name, rarity.name)
	dragon.Parent = dragons

	print(
		string.format(
			"%s открыл яйцо: %s (+%d монет/сек)",
			player.Name,
			dragon.Name,
			rarity.income
		)
	)

	-- Объявление всем о редком драконе
	if rarity.announce then
		Announce:FireAllClients(player.Name, dragon.Name, rarity.color)
	end
end

prompt.Triggered:Connect(openEgg)

-- Единый цикл дохода: O(игроков) за тик, суммы берём из кэша
task.spawn(function()
	while true do
		task.wait(S.IncomeInterval)
		for player, amount in pairs(income) do
			if amount > 0 then
				local leaderstats = player:FindFirstChild("leaderstats")
				local coins = leaderstats and leaderstats:FindFirstChild("Coins")
				if coins then
					coins.Value += amount
				end
			end
		end
	end
end)
