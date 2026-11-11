--!strict
-- Tutorial: первая минута (CLAUDE.md, раздел 6) и защита новичка.
-- Три подсказки-стрелки без текста: подарок -> сани -> мастерская. Первый подарок открывается
-- сразу у саней, чтобы первый эльф появился до 30-й секунды. Стрелки рисует клиент по атрибутам.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local Gifts = require(script.Parent.Gifts)
local PlayerData = require(script.Parent.PlayerData)
local Round = require(script.Parent.Round)
local World = require(script.Parent.World)

local F = Config.FirstMinute

local Tutorial = {}

local rng = Random.new()
local tutorialGift: { [Player]: Gifts.Gift } = {}
local runId: { [Player]: number } = {} -- растёт при каждом перезапуске обучения

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Новичок: первые NewbieDuration секунд после самого первого входа
function Tutorial.IsNewbie(player: Player): boolean
	local firstJoin = player:GetAttribute("FirstJoin")
	if type(firstJoin) ~= "number" or firstJoin <= 0 then
		return false
	end
	return os.time() - firstJoin < F.NewbieDuration
end

local function setStage(player: Player, stage: number, target: Vector3?)
	player:SetAttribute("TutorialTarget", target)
	player:SetAttribute("TutorialStage", stage)
end

local function removeTutorialGift(player: Player)
	local gift = tutorialGift[player]
	tutorialGift[player] = nil
	if gift then
		Gifts.Remove(gift) -- подарок-подсказка не понадобился; чужим он недоступен, поэтому убираем
	end
end

local function finish(player: Player)
	removeTutorialGift(player)
	if player.Parent == Players then
		player:SetAttribute("TutorialDone", true)
		setStage(player, 0, nil)
	end
end

-- Шаг 1: маленький подарок в 10 метрах от спавна, стрелка на него
local function begin(player: Player)
	runId[player] = (runId[player] or 0) + 1
	removeTutorialGift(player)
	local position = Config.World.SpawnPosition + F.GiftDirection.Unit * F.GiftDistance
	local gift = Gifts.SpawnSmallAt(position, player)
	if gift then
		tutorialGift[player] = gift
		setStage(player, 1, gift.root.Position)
	else
		local nearest = Gifts.NearestSmall(position)
		setStage(player, if nearest then 1 else 0, nearest)
	end
end

-- Стрелка шага 1 всегда ведёт к подарку, который ещё лежит
local function retarget(player: Player)
	if player:GetAttribute("TutorialStage") ~= 1 then
		return
	end
	local gift = tutorialGift[player]
	if gift and gift.state == "Idle" then
		setStage(player, 1, gift.root.Position)
		return
	end
	local root = getRoot(player)
	local nearest = root and Gifts.NearestSmall(root.Position)
	if nearest then
		setStage(player, 1, nearest)
	end
end

-- Точка для дополнительного подарка: на земле и не внутри мастерской
local function isOpenGround(position: Vector3): boolean
	local clear = Config.Map.GiftClearance
	-- Рельеф продолжается за стеной, поэтому край карты проверяем отдельно
	if
		not Gifts.HasGround(position)
		or World.IsBlocked(position, clear)
		or not World.InBounds(position, Config.Map.WallThickness / 2 + clear)
	then
		return false
	end
	local clearance = Config.World.WorkshopSize.X * F.NewbieGiftWorkshopClearance
	for _, pad in World.GetWorkshops() do
		if ((pad.Position - position) * Vector3.new(1, 0, 1)).Magnitude < clearance then
			return false
		end
	end
	return true
end

local function onPlayer(player: Player)
	-- Ждём профиль: только он знает, проходил ли игрок первую минуту
	local deadline = os.clock() + Config.Settings.LoadTimeout
	while player:GetAttribute("ProfileReady") ~= true do
		if player.Parent ~= Players or os.clock() > deadline then
			return
		end
		task.wait(0.2)
	end

	if player.Parent ~= Players then
		return -- вышел, пока ждали профиль: не оставляем подарок-подсказку без хозяина
	end
	if player:GetAttribute("TutorialDone") ~= true then
		begin(player)
	else
		setStage(player, 0, nil)
	end

	player:GetAttributeChangedSignal("Carrying"):Connect(function()
		local stage = player:GetAttribute("TutorialStage")
		if stage == 1 and player:GetAttribute("Carrying") ~= nil then
			-- Шаг 2: подарок в руках, стрелка на сани. Взят именно подарок-подсказка, если он
			-- больше не зарезервирован; иначе игрок поднял другой, а подсказку уберёт finish()
			local gift = tutorialGift[player]
			if gift and gift.reservedFor == nil then
				tutorialGift[player] = nil
			end
			setStage(player, 2, Config.World.SleighPosition)
		elseif stage == 2 and player:GetAttribute("Carrying") == nil then
			-- Уронил до сдачи: стрелка снова ведёт к лежащему подарку
			if (player:GetAttribute("PendingGifts") or 0) == 0 then
				player:SetAttribute("TutorialStage", 1)
				retarget(player)
			end
		end
	end)

	-- Для новичка первый пролёт Санты через 90 секунд, один раз за всё время (флаг в профиле)
	if Tutorial.IsNewbie(player) and player:GetAttribute("FlybySeen") ~= true then
		task.delay(F.FirstFlybyDelay, function()
			if player.Parent ~= Players or player:GetAttribute("FlybySeen") == true then
				return
			end
			if Round.GetTimeLeft() > F.FirstFlybySkipIfSooner then
				Round.ExtraFlyby()
			end
		end)
	end
end

function Tutorial.start()
	-- Шаг 3: первая сдача открывается сразу, эльф идёт в мастерскую, стрелка на неё
	Gifts.OnDelivered(function(player)
		local stage = player:GetAttribute("TutorialStage")
		if stage ~= 1 and stage ~= 2 then
			return
		end
		local run = runId[player]
		task.defer(function()
			if player.Parent ~= Players or runId[player] ~= run then
				return
			end
			local result = Round.OpenNow(player)
			Remotes.Get("RoundResult"):FireClient(player, result)
			local workshop = player:GetAttribute("WorkshopPosition")
			setStage(player, 3, if typeof(workshop) == "Vector3" then workshop else nil)
			task.delay(F.WorkshopArrowTime, function()
				if runId[player] == run then -- обучение не перезапускали (сброс профиля)
					finish(player)
				end
			end)
		end)
	end)

	-- Профиль сбросили (админ-панель): первая минута начинается заново
	PlayerData.OnReset(function(player)
		begin(player)
	end)

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		removeTutorialGift(player)
		runId[player] = nil
	end)

	-- Защита новичка: рядом с ним всегда лежит несколько маленьких подарков
	task.spawn(function()
		while true do
			task.wait(F.NewbieGiftInterval)
			Gifts.RemoveStale("Extra", F.NewbieGiftLifetime) -- забытые подарки не занимают потолок
			for _, player in Players:GetPlayers() do
				retarget(player)
				local root = getRoot(player)
				if
					root
					and Tutorial.IsNewbie(player)
					and player:GetAttribute("TutorialDone") == true
				then
					local missing = F.NewbieGiftCount
						- Gifts.CountSmallNear(root.Position, F.NewbieGiftRadius)
					for _ = 1, missing do
						if Gifts.CountBySource("Extra") >= F.NewbieGiftCap then
							break
						end
						local angle = rng:NextNumber() * math.pi * 2
						local distance = rng:NextNumber(
							F.NewbieGiftRadius * F.NewbieGiftInnerRadius,
							F.NewbieGiftRadius
						)
						local x = root.Position.X + math.cos(angle) * distance
						local z = root.Position.Z + math.sin(angle) * distance
						-- На поверхности рельефа: рядом с новичком может быть склон
						local position = Vector3.new(x, World.GroundHeight(x, z), z)
						if isOpenGround(position) then
							Gifts.SpawnSmallAt(position, nil)
						end
					end
				end
			end
		end
	end)
end

return Tutorial
