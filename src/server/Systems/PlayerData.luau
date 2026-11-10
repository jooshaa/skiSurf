--!strict
-- PlayerData: leaderstats, папка Elves, загрузка/сохранение с session lock и миграциями.
-- Состояние игрока живёт в инстансах (leaderstats, Elves, атрибуты), сюда же его читает клиент.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Config)
local Elves = require(ReplicatedStorage.Elves)
local Remotes = require(ReplicatedStorage.Remotes)
local Migrations = require(script.Parent.Parent.Migrations)

local S = Config.Settings

local PlayerData = {}

local store: DataStore? = nil
local sessionToken: { [Player]: string } = {} -- уникальный токен сессии (владелец блокировки)
local autosaving: { [Player]: boolean } = {} -- пока работает цикл автосохранения
local saving: { [Player]: boolean } = {} -- пока идёт запись (сериализация записей)
local finalSaved: { [Player]: boolean } = {} -- после финального сохранения
local unknownElves: { [Player]: { any } } = {} -- записи неизвестных эльфов, сохраняем как есть
local shuttingDown = false
local beforeSave: { (Player) -> () } = {} -- вызываются перед финальным сохранением
local onReset: { (Player) -> () } = {} -- вызываются после сброса профиля

local function runBeforeSave(player: Player)
	for _, callback in beforeSave do
		local ok, err = pcall(callback, player)
		if not ok then
			warn("[PlayerData] Ошибка перед сохранением: " .. tostring(err))
		end
	end
end

local function getKey(player: Player): string
	return "Player_" .. player.UserId
end

local function getCoins(player: Player): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	if coins and coins:IsA("IntValue") then
		return coins
	end
	return nil
end

-- Свежая блокировка другой сессии?
local function isForeignLock(data: any, myToken: string): boolean
	local lock = type(data) == "table" and data.lock
	if type(lock) ~= "table" or lock.token == myToken then
		return false
	end
	return os.time() - (tonumber(lock.time) or 0) < S.LockStaleSeconds
end

-- pcall с экспоненциальным backoff
local function withRetry(attempts: number, label: string, fn: () -> ()): boolean
	local delaySeconds = S.RetryBackoffBase
	for attempt = 1, attempts do
		local ok, err = pcall(fn)
		if ok then
			return true
		end
		warn(
			string.format(
				"[PlayerData] %s, попытка %d/%d: %s",
				label,
				attempt,
				attempts,
				tostring(err)
			)
		)
		if attempt < attempts then
			task.wait(delaySeconds)
			delaySeconds = math.min(delaySeconds * 2, S.RetryBackoffMax)
		end
	end
	return false
end

-- Одна попытка захвата блокировки и загрузки: "ok"/"locked"/"error", data
local function tryClaim(dataStore: DataStore, player: Player, token: string): (string, any)
	local result, locked, corrupt = nil, false, false
	local ok, err = pcall(function()
		dataStore:UpdateAsync(getKey(player), function(old)
			if isForeignLock(old, token) then
				locked = true
				return nil -- другая сессия владеет данными, ничего не пишем
			end
			local data = Migrations.Migrate(old)
			if not data then
				corrupt = true
				return nil -- непонятные данные, не трогаем
			end
			data.lock = { token = token, time = os.time() }
			result = data
			return data
		end)
	end)
	if not ok then
		warn("[PlayerData] Загрузка " .. player.Name .. ": " .. tostring(err))
		return "error", nil
	end
	if locked then
		return "locked", nil
	end
	if corrupt then
		warn(
			"[PlayerData] Загрузка "
				.. player.Name
				.. ": данные повреждены или неизвестной версии"
		)
		return "error", nil
	end
	return "ok", result
end

-- Загрузка с повторами при ошибке и ожиданием чужой блокировки
local function loadData(player: Player, token: string): (string, any)
	local dataStore = store
	if not dataStore then
		return "error", nil
	end
	local errorTries, lockTries = 0, 0
	local delaySeconds = S.RetryBackoffBase
	while true do
		local status, data = tryClaim(dataStore, player, token)
		if status == "ok" then
			return "ok", data
		elseif status == "locked" then
			lockTries += 1
			if lockTries >= S.LockRetries then
				return "locked", nil
			end
			task.wait(S.LockRetryDelay)
		else
			errorTries += 1
			if errorTries >= S.LoadRetries then
				return "error", nil
			end
			task.wait(delaySeconds)
			delaySeconds = math.min(delaySeconds * 2, S.RetryBackoffMax)
		end
		if player.Parent ~= Players then
			return "left", nil
		end
	end
end

-- Снять свою блокировку без изменения данных (игрок ушёл во время загрузки)
local function releaseLockOnly(key: string, token: string)
	local dataStore = store
	if not dataStore then
		return
	end
	withRetry(S.SaveRetries, "Снятие блокировки", function()
		dataStore:UpdateAsync(key, function(old)
			if type(old) ~= "table" or isForeignLock(old, token) then
				return nil
			end
			old.lock = nil
			return old
		end)
	end)
end

-- Собираем данные игрока для сохранения
local function serialize(player: Player): any
	local coins = getCoins(player)
	local folder = player:FindFirstChild("Elves")
	if not coins or not folder then
		return nil
	end
	local elves: { any } = Elves.Serialize(folder)
	for _, entry in unknownElves[player] or {} do
		table.insert(elves, entry)
	end
	return {
		version = S.DataVersion,
		coins = coins.Value,
		elves = elves,
		slots = player:GetAttribute("Slots") or Config.Elves.StartSlots,
		pity = player:GetAttribute("Pity") or 0,
		diary = player:GetAttribute("Diary") or "",
		diaryTiers = player:GetAttribute("DiaryTiers") or 0,
		firstJoin = player:GetAttribute("FirstJoin") or 0,
		tutorialDone = player:GetAttribute("TutorialDone") == true,
		flybySeen = player:GetAttribute("FlybySeen") == true,
	}
end

-- Переносим профиль в инстансы игрока; возвращает число восстановленных эльфов
local function applyProfile(player: Player, data: any): number
	local coins = getCoins(player)
	if coins then
		coins.Value = data.coins
	end
	player:SetAttribute("Slots", data.slots)
	player:SetAttribute("Pity", data.pity)
	player:SetAttribute("Diary", data.diary)
	player:SetAttribute("DiaryTiers", data.diaryTiers)
	player:SetAttribute("FirstJoin", data.firstJoin)
	player:SetAttribute("TutorialDone", data.tutorialDone)
	player:SetAttribute("FlybySeen", data.flybySeen == true)

	-- Восстанавливаем эльфов и только потом показываем папку
	local existing = player:FindFirstChild("Elves")
	if existing then
		existing:ClearAllChildren()
		local count, unknown = Elves.Restore(existing, data.elves)
		unknownElves[player] = unknown
		return count
	end
	local folder = Instance.new("Folder")
	folder.Name = "Elves"
	local restored, unknown = Elves.Restore(folder, data.elves)
	unknownElves[player] = unknown
	folder.Parent = player
	return restored
end

-- Сохранение через UpdateAsync; releaseLock=true при выходе
local function saveData(player: Player, releaseLock: boolean)
	local dataStore = store
	if not dataStore or player:GetAttribute("DataLoaded") ~= true then
		return
	end
	local token = sessionToken[player]
	if not token or finalSaved[player] then
		return
	end
	-- Снимок данных берём сразу, пока объекты игрока точно живы
	local data = serialize(player)
	if not data then
		return
	end
	-- Записи одного игрока строго по очереди: автосейв не обгонит сохранение при выходе
	while saving[player] do
		task.wait(0.1)
	end
	if finalSaved[player] then
		return
	end
	saving[player] = true

	local refused = false
	local ok = withRetry(S.SaveRetries, "Сохранение " .. player.Name, function()
		dataStore:UpdateAsync(getKey(player), function(old)
			-- Чужая свежая блокировка или более новый формат: не перезаписываем
			if isForeignLock(old, token) then
				refused = true
				return nil
			end
			if
				type(old) == "table"
				and type(old.version) == "number"
				and old.version > data.version
			then
				refused = true
				return nil
			end
			-- Снимаем блокировку только при финальном сохранении: выход или выключение сервера
			-- (не по player.Parent: иначе автосейв в полёте снимет блокировку раньше финального сохранения)
			local release = releaseLock or shuttingDown
			data.lock = if release then nil else { token = token, time = os.time() }
			return data
		end)
	end)
	saving[player] = nil

	if refused then
		warn(
			"[PlayerData] Сохранение "
				.. player.Name
				.. " отклонено: данными владеет другая сессия или они новее"
		)
		player:SetAttribute("DataLoaded", false) -- больше не пишем в этой сессии
		if player.Parent == Players then
			player:Kick(
				"Ваша сессия открыта на другом сервере. Пожалуйста, перезайдите."
			)
		end
		return
	end
	if ok and (releaseLock or shuttingDown) then
		finalSaved[player] = true
	end
end

local function onPlayerAdded(player: Player)
	player:SetAttribute("DataLoaded", false)
	player:SetAttribute("ProfileReady", false)
	local token = HttpService:GenerateGUID(false)
	sessionToken[player] = token

	-- leaderstats сразу, чтобы таблица лидеров появилась мгновенно
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = S.StartCoins
	coins.Parent = leaderstats
	leaderstats.Parent = player

	local status, data = loadData(player, token)
	if player.Parent ~= Players then
		if status == "ok" then
			releaseLockOnly(getKey(player), token) -- захватили, но игрок уже ушёл
		end
		return
	end

	if status == "locked" then
		player:Kick(
			"Ваши данные ещё сохраняются на другом сервере. Зайдите через 1-2 минуты."
		)
		return
	end
	if status ~= "ok" then
		if S.KickOnLoadFailure then
			player:Kick(
				"Не удалось загрузить данные. Пожалуйста, перезайдите."
			)
			return
		end
		data = Migrations.DefaultProfile()
		if not RunService:IsStudio() then
			-- Сбой загрузки: это может быть давний игрок, не показываем ему обучение и бонусы новичка
			data.firstJoin = 0
			data.tutorialDone = true
			data.flybySeen = true
		end
	end
	if status == "ok" and data.firstJoin == 0 and not data.tutorialDone then
		data.firstJoin = os.time()
	end

	local restored = applyProfile(player, data)

	local loaded = status == "ok"
	player:SetAttribute("DataLoaded", loaded)
	player:SetAttribute("ProfileReady", true)
	if loaded then
		print(
			string.format(
				"[PlayerData] %s загружен: %d монет, %d эльфов",
				player.Name,
				data.coins,
				restored
			)
		)
		-- Автосохранение, разнесённое по игрокам, заодно обновляет блокировку
		autosaving[player] = true
		task.spawn(function()
			task.wait(S.AutosaveInterval * ((player.UserId % 100) / 100))
			while autosaving[player] and not shuttingDown do
				saveData(player, false)
				task.wait(S.AutosaveInterval)
			end
		end)
	else
		warn(
			"[PlayerData] "
				.. player.Name
				.. ": данные не загружены, сохранение отключено"
		)
		task.delay(S.LoadFailNoticeDelay, function()
			if player.Parent == Players then
				Remotes.Get("Notify"):FireClient(
					player,
					"Не удалось загрузить сохранение. Прогресс этой сессии не сохранится!",
					Color3.fromRGB(255, 80, 80)
				)
			end
		end)
	end
end

-- Профиль применён к инстансам игрока (даже если DataStore недоступен)
function PlayerData.IsReady(player: Player): boolean
	return player:GetAttribute("ProfileReady") == true
end

function PlayerData.GetCoins(player: Player): number
	local coins = getCoins(player)
	return if coins then coins.Value else 0
end

-- Начислить монеты (только сервер). Возвращает false, если профиль ещё не готов
function PlayerData.AddCoins(player: Player, amount: number): boolean
	local coins = getCoins(player)
	if not coins or not PlayerData.IsReady(player) then
		return false
	end
	if amount ~= amount or amount == math.huge or amount == -math.huge then
		return false
	end
	coins.Value = math.clamp(coins.Value + math.floor(amount), 0, 2 ^ 53)
	return true
end

-- Сброс профиля к новому (админ-панель). Сохранится обычным автосохранением
function PlayerData.Reset(player: Player)
	if not PlayerData.IsReady(player) then
		return
	end
	applyProfile(player, Migrations.DefaultProfile())
	for _, callback in onReset do
		task.spawn(callback, player)
	end
end

-- Подписка: профиль игрока сброшен, другие системы чистят своё состояние
function PlayerData.OnReset(callback: (Player) -> ())
	table.insert(onReset, callback)
end

-- Подписка: игрок уходит, сейчас будет финальное сохранение (успеть начислить незавершённое)
function PlayerData.OnBeforeSave(callback: (Player) -> ())
	table.insert(beforeSave, callback)
end

function PlayerData.init()
	-- Получаем DataStore через pcall (в неопубликованном месте недоступен)
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(S.StoreName)
	end)
	if not ok then
		warn("[PlayerData] DataStore недоступен: " .. tostring(err))
	end
end

function PlayerData.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Сохраняем и снимаем блокировку при выходе, затем чистим таблицы
	Players.PlayerRemoving:Connect(function(player)
		autosaving[player] = nil
		runBeforeSave(player)
		saveData(player, true)
		sessionToken[player] = nil
		unknownElves[player] = nil
		saving[player] = nil
		finalSaved[player] = nil
	end)

	-- Сохраняем всех при закрытии сервера, ждём не дольше таймаута
	game:BindToClose(function()
		shuttingDown = true
		table.clear(autosaving)
		local pending = 0
		for _, player in Players:GetPlayers() do
			pending += 1
			task.spawn(function()
				runBeforeSave(player)
				saveData(player, true)
				pending -= 1
			end)
		end
		local timeout = if RunService:IsStudio()
			then S.BindToCloseStudioTimeout
			else S.BindToCloseTimeout
		local deadline = os.clock() + timeout
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return PlayerData
