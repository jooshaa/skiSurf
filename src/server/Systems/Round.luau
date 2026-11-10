--!strict
-- Round: один общий цикл пролётов Санты на сервер (CLAUDE.md, разделы 3 и 9).
-- Объявление -> пролёт с падением подарков -> сбор до нормы или таймера -> отлёт саней ->
-- каждому открываются сданные подарки -> новый цикл. Норма и сдача считаются на сервере.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Config)
local Elves = require(ReplicatedStorage.Elves)
local Remotes = require(ReplicatedStorage.Remotes)
local ElfService = require(script.Parent.ElfService)
local Gifts = require(script.Parent.Gifts)
local PlayerData = require(script.Parent.PlayerData)

local R = Config.Round

type GiftSize = Config.GiftSize
type Delivery = { size: GiftSize, share: number }

export type Result = {
	gifts: number,
	coins: number,
	elves: { { name: string, color: Color3 } },
	quotaMet: boolean,
	delivered: number,
	target: number,
}

local Round = {}

local rng = Random.new()
local phase = "Active"
local endsAt = 0 -- серверное время конца фазы
local deliveredShares = 0 -- сумма долей; один подарок = 1
local pending: { [Player]: { Delivery } } = {}
local forceDeparture = false
local lastFlyby = 0
local cycleTarget = R.QuotaBase -- норма фиксируется в начале цикла и не прыгает при входе и выходе
local cycleQuotaMet = false -- итог текущего отлёта (для тех, кто выходит во время анимации)
local cycleId = 0

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- Норма растёт с числом игроков; считается один раз в начале цикла
local function computeTarget(): number
	return R.QuotaBase + R.QuotaPerExtraPlayer * math.max(0, #Players:GetPlayers() - 1)
end

local function quotaTarget(): number
	return cycleTarget
end

local function deliveredCount(): number
	return math.floor(deliveredShares + 1e-6)
end

local function snapshot(): { [string]: any }
	return {
		phase = phase,
		delivered = deliveredCount(),
		target = quotaTarget(),
		endsAt = endsAt,
	}
end

local function broadcast()
	Remotes.Get("RoundState"):FireAllClients(snapshot())
end

-- Открыть сданные подарки игрока: ролл по таблице размера (раздел 4.1), эльф в мастерскую, монеты
local function openDeliveries(player: Player, quotaMet: boolean): Result
	local list = pending[player]
	pending[player] = nil
	local result: Result = {
		gifts = if list then #list else 0,
		coins = 0,
		elves = {},
		quotaMet = quotaMet,
		delivered = deliveredCount(),
		target = quotaTarget(),
	}
	if not list then
		return result
	end
	if player.Parent == Players then
		player:SetAttribute("PendingGifts", 0)
	end
	local coins = 0
	for _, delivery in list do
		local size = delivery.size
		local amount = rng:NextInteger(size.coinsMin, size.coinsMax) * delivery.share
		if quotaMet then
			amount *= 1 + R.QuotaBonus
		end
		local rarity = Elves.RollContents(size.contents)
		local elf = ElfService.GrantRolled(player, rarity.name)
		if elf then
			table.insert(result.elves, { name = elf.Name, color = rarity.color })
		else
			-- Эльфа некуда положить: ничего не теряем, отдаём его доход монетами
			amount += rarity.income * Config.Elves.OverflowCoinSeconds
		end
		coins += amount
	end
	result.coins = math.floor(coins + 0.5)
	if result.coins > 0 then
		PlayerData.AddCoins(player, result.coins)
	end
	return result
end

local function farthestDistrict(): Config.District
	local best = Config.Districts[1]
	local bestDistance = -1
	for _, district in Config.Districts do
		local distance = (district.center - Config.World.SleighPosition).Magnitude
		if distance > bestDistance then
			best = district
			bestDistance = distance
		end
	end
	return best
end

local function farDistricts(): { Config.District }
	local list = {}
	for _, district in Config.Districts do
		if district.requiredSpeedLevel > 1 then
			table.insert(list, district)
		end
	end
	if #list == 0 then
		table.insert(list, farthestDistrict())
	end
	return list
end

-- Пролёт: клиенты рисуют Санту, сервер роняет подарки по ходу полёта
local function flyby()
	lastFlyby = os.clock()
	Remotes.Get("SantaFlyby"):FireAllClients(R.FlybyFrom, R.FlybyTo, now(), R.FlybyDuration)

	local drops: { { size: string, district: Config.District? } } = {}
	for _ = 1, R.DropSmall do
		table.insert(drops, { size = "Small", district = nil }) -- маленькие падают везде
	end
	local far = farDistricts()
	for index = 1, R.DropMedium do
		table.insert(drops, { size = "Medium", district = far[(index - 1) % #far + 1] })
	end
	for _ = 1, R.DropLarge do
		table.insert(drops, { size = "Large", district = farthestDistrict() })
	end
	local startedIn = cycleId
	for index, drop in drops do
		local delaySeconds = R.FlybyDuration * R.DropSpread * index / #drops
		task.delay(delaySeconds, function()
			if cycleId == startedIn then -- цикл уже сменился: не роняем подарки в новый
				Gifts.SpawnDrop(drop.size, Gifts.RandomPosition(drop.district))
			end
		end)
	end
end

local function waitForPlayers()
	while #Players:GetPlayers() == 0 do
		Players.PlayerAdded:Wait()
	end
end

local function runCycle(first: boolean)
	waitForPlayers()
	cycleId += 1
	cycleQuotaMet = false
	cycleTarget = computeTarget()
	if first then
		-- Новый сервер: первая минута без спектакля, только подарки на карте
		phase = "Active"
		endsAt = now() + R.FirstCycleDelay
	else
		phase = "Announce"
		endsAt = now() + R.AnnounceLead
		broadcast()
		task.wait(R.AnnounceLead)
		flyby()
		phase = "Active"
		endsAt = now() + R.Interval
	end
	forceDeparture = false -- команда отлёта действует только на идущий сбор
	broadcast()

	-- Отлёт: норма собрана или таймер вышел
	while true do
		task.wait(R.PollInterval)
		if forceDeparture or now() >= endsAt or deliveredCount() >= quotaTarget() then
			break
		end
	end
	forceDeparture = false
	local quotaMet = deliveredCount() >= quotaTarget()
	cycleQuotaMet = quotaMet

	phase = "Departing"
	endsAt = now() + R.DepartAnimTime
	broadcast()
	Remotes.Get("SleighDepart"):FireAllClients()
	task.wait(R.DepartAnimTime)

	-- Итог фиксируем один раз: звезда и числа в окне всегда согласованы
	local delivered, target = deliveredCount(), quotaTarget()
	for _, player in Players:GetPlayers() do
		-- Ошибка у одного игрока не должна оставить остальных без подарков
		local ok, err = pcall(function()
			local result = openDeliveries(player, quotaMet)
			result.delivered = delivered
			result.target = target
			Remotes.Get("RoundResult"):FireClient(player, result)
		end)
		if not ok then
			warn(
				"[Round] Открытие подарков " .. player.Name .. ": " .. tostring(err)
			)
		end
	end
	Gifts.ClearFlyby()
	deliveredShares = 0
	table.clear(pending)
end

function Round.GetDelivered(): number
	return deliveredCount()
end

function Round.GetTarget(): number
	return quotaTarget()
end

function Round.GetPhase(): string
	return phase
end

-- Сколько секунд до конца текущей фазы
function Round.GetTimeLeft(): number
	return math.max(0, endsAt - now())
end

-- Админ: отправить сани сейчас, следующий цикл начнётся с пролёта
function Round.ForceDeparture()
	forceDeparture = true
end

-- Дополнительный пролёт без смены цикла (первый пролёт для новичка)
function Round.ExtraFlyby(): boolean
	if phase ~= "Active" or os.clock() - lastFlyby < R.ExtraFlybyCooldown then
		return false
	end
	flyby()
	return true
end

-- Открыть сданные подарки игрока прямо сейчас, без бонуса нормы (первая минута, выход из игры)
function Round.OpenNow(player: Player): Result
	return openDeliveries(player, false)
end

function Round.start()
	Gifts.OnDelivered(function(player, size, share)
		local list = pending[player]
		if not list then
			list = {}
			pending[player] = list
		end
		table.insert(list, { size = size, share = share })
		deliveredShares += share
		player:SetAttribute("Contribution", (player:GetAttribute("Contribution") or 0) + share)
		player:SetAttribute("PendingGifts", #list)
		broadcast()
	end)

	-- Игрок уходит до отлёта: его сданные подарки открываются сразу, до сохранения
	PlayerData.OnBeforeSave(function(player)
		if pending[player] then
			-- Вышел во время анимации отлёта при выполненной норме: бонус сохраняется
			openDeliveries(player, phase == "Departing" and cycleQuotaMet)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		Remotes.Get("RoundState"):FireClient(player, snapshot())
	end)
	Players.PlayerRemoving:Connect(function(player)
		-- Не трогаем pending сразу: подарки открывает OnBeforeSave, порядок обработчиков не гарантирован
		task.defer(function()
			pending[player] = nil
			broadcast()
		end)
	end)

	task.spawn(function()
		local first = true
		while true do
			local ok, err = pcall(runCycle, first)
			if not ok then
				warn("[Round] Ошибка цикла: " .. tostring(err))
				task.wait(R.ErrorRetryDelay)
			end
			first = false
		end
	end)
end

return Round
