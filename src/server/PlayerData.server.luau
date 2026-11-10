-- PlayerData: leaderstats, папка Dragons, загрузка/сохранение с session lock и миграциями
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local DragonConfig = require(ReplicatedStorage:WaitForChild("DragonConfig"))
local S = DragonConfig.Settings
local Notify = ReplicatedStorage:WaitForChild("Notify")

-- Получаем DataStore через pcall (в неопубликованном месте недоступен)
local store = nil
local okStore, storeErr = pcall(function()
	store = DataStoreService:GetDataStore(S.StoreName)
end)
if not okStore then
	warn("[PlayerData] DataStore недоступен: " .. tostring(storeErr))
end

local sessionToken = {} -- player -> уникальный токен сессии (владелец блокировки)
local autosaving = {} -- player -> true, пока работает цикл автосохранения
local saving = {} -- player -> true, пока идёт запись (сериализация записей)
local finalSaved = {} -- player -> true после финального сохранения
local shuttingDown = false

local function getKey(player)
	return "Player_" .. player.UserId
end

-- Новый профиль (всегда новая таблица)
local function defaultProfile()
	return { version = S.DataVersion, coins = S.StartCoins, dragons = {} }
end

-- Миграции: version N -> N+1
local MIGRATIONS = {
	-- v1 {Coins=число} -> v2 {coins, dragons}
	[1] = function(data)
		return { version = 2, coins = data.Coins or S.StartCoins, dragons = {}, lock = data.lock }
	end,
}

-- Приводим сохранённые данные к текущей версии. nil -> новый профиль.
-- Возвращает nil, если данные непонятны: тогда их НЕ трогаем.
local function migrate(raw)
	if raw == nil then
		return defaultProfile()
	end
	local data = raw
	if type(data) == "number" then
		data = { version = 1, Coins = data } -- v0: просто число
	end
	if type(data) ~= "table" then
		return nil
	end
	if type(data.version) ~= "number" then
		data.version = 1
	end
	while data.version < S.DataVersion do
		local step = MIGRATIONS[data.version]
		if not step then
			return nil -- нет миграции: не затираем данные дефолтом
		end
		data = step(data)
	end
	-- Санитизация монет: NaN, бесконечность, дробные, отрицательные
	local c = data.coins
	if type(c) ~= "number" or c ~= c or c == math.huge or c == -math.huge then
		c = S.StartCoins
	end
	data.coins = math.clamp(math.floor(c), 0, 2 ^ 53)
	if type(data.dragons) ~= "table" then
		data.dragons = {}
	end
	return data
end

-- Свежая блокировка другой сессии?
local function isForeignLock(data, myToken)
	local lock = type(data) == "table" and data.lock
	if type(lock) ~= "table" or lock.token == myToken then
		return false
	end
	return os.time() - (tonumber(lock.time) or 0) < S.LockStaleSeconds
end

-- pcall с экспоненциальным backoff
local function withRetry(attempts, label, fn)
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
			delaySeconds = math.min(delaySeconds * 2, 16)
		end
	end
	return false
end

-- Одна попытка захвата блокировки и загрузки: "ok"/"locked"/"error", data
local function tryClaim(player, token)
	local result, locked, corrupt = nil, false, false
	local ok, err = pcall(function()
		store:UpdateAsync(getKey(player), function(old)
			if isForeignLock(old, token) then
				locked = true
				return nil -- другая сессия владеет данными, ничего не пишем
			end
			local data = migrate(old)
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
		return "error"
	end
	if locked then
		return "locked"
	end
	if corrupt then
		warn(
			"[PlayerData] Загрузка "
				.. player.Name
				.. ": данные повреждены или неизвестной версии"
		)
		return "error"
	end
	return "ok", result
end

-- Загрузка с повторами при ошибке и ожиданием чужой блокировки
local function loadData(player, token)
	if not store then
		return "error"
	end
	local errorTries, lockTries = 0, 0
	local delaySeconds = S.RetryBackoffBase
	while true do
		local status, data = tryClaim(player, token)
		if status == "ok" then
			return "ok", data
		elseif status == "locked" then
			lockTries += 1
			if lockTries >= S.LockRetries then
				return "locked"
			end
			task.wait(S.LockRetryDelay)
		else
			errorTries += 1
			if errorTries >= S.LoadRetries then
				return "error"
			end
			task.wait(delaySeconds)
			delaySeconds = math.min(delaySeconds * 2, 16)
		end
		if player.Parent ~= Players then
			return "left"
		end
	end
end

-- Снять свою блокировку без изменения данных (игрок ушёл во время загрузки)
local function releaseLockOnly(key, token)
	withRetry(S.SaveRetries, "Снятие блокировки", function()
		store:UpdateAsync(key, function(old)
			if type(old) ~= "table" or isForeignLock(old, token) then
				return nil
			end
			old.lock = nil
			return old
		end)
	end)
end

-- Собираем данные игрока для сохранения
local function serialize(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	local dragons = player:FindFirstChild("Dragons")
	if not coins or not dragons then
		return nil
	end
	return {
		version = S.DataVersion,
		coins = coins.Value,
		dragons = DragonConfig.SerializeDragons(dragons),
	}
end

-- Сохранение через UpdateAsync; releaseLock=true при выходе
local function saveData(player, releaseLock)
	if not store or player:GetAttribute("DataLoaded") ~= true then
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
		store:UpdateAsync(getKey(player), function(old)
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
			-- Снимаем блокировку при выходе, выключении сервера или если игрок уже ушёл
			local release = releaseLock or shuttingDown or player.Parent ~= Players
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

local function onPlayerAdded(player)
	player:SetAttribute("DataLoaded", false)
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
	if status == "error" then
		if S.KickOnLoadFailure then
			player:Kick(
				"Не удалось загрузить данные. Пожалуйста, перезайдите."
			)
			return
		end
		data = defaultProfile()
	end

	coins.Value = data.coins

	-- Восстанавливаем драконов и только потом показываем папку
	local folder = Instance.new("Folder")
	folder.Name = "Dragons"
	local restored = DragonConfig.RestoreDragons(folder, data.dragons)
	folder.Parent = player

	local loaded = status == "ok"
	player:SetAttribute("DataLoaded", loaded)
	if loaded then
		print(
			string.format(
				"[PlayerData] %s загружен: %d монет, %d драконов",
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
		task.delay(3, function()
			if player.Parent == Players then
				Notify:FireClient(
					player,
					"Не удалось загрузить сохранение. Прогресс этой сессии не сохранится!",
					Color3.fromRGB(255, 80, 80)
				)
			end
		end)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

-- Сохраняем и снимаем блокировку при выходе, затем чистим таблицы
Players.PlayerRemoving:Connect(function(player)
	autosaving[player] = nil
	saveData(player, true)
	sessionToken[player] = nil
	saving[player] = nil
	finalSaved[player] = nil
end)

-- Сохраняем всех при закрытии сервера, ждём не дольше таймаута
game:BindToClose(function()
	shuttingDown = true
	table.clear(autosaving)
	local pending = 0
	for _, p in ipairs(Players:GetPlayers()) do
		pending += 1
		task.spawn(function()
			saveData(p, true)
			pending -= 1
		end)
	end
	local timeout = RunService:IsStudio() and 5 or S.BindToCloseTimeout
	local deadline = os.clock() + timeout
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)
