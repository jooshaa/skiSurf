--!strict
-- Gifts: подарки на карте, подъём, переноска и сдача в сани. Вся логика на сервере.
-- Маленький: касание поднимает, Weld к HumanoidRootPart. Средний и большой: «нести» нажимают
-- 2 или 3 игрока, сервер двигает подарок по центру несущих (CLAUDE.md, разделы 4.3 и 9).
-- Подарок никому не принадлежит, пока не сдан; уронённый лежит и ждёт, поднять может любой.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local RateLimit = require(script.Parent.Parent.RateLimit)
local World = require(script.Parent.World)

local S = Config.Settings
local G = Config.Gifts

type GiftSize = Config.GiftSize

export type Gift = {
	id: number,
	size: GiftSize,
	model: Model,
	root: Part,
	source: string, -- "Map" (лежит между пролётами) или "Flyby"
	state: string, -- "Falling" / "Idle" / "Waiting" / "Carried"
	carriers: { Player },
	weld: WeldConstraint?,
	availableAt: number, -- os.clock(), раньше поднять нельзя
	lastPosition: Vector3,
	lastCheck: number,
}

local Gifts = {}

local container: Folder
local gifts: { [Model]: Gift } = {}
local carrying: { [Player]: Gift } = {}
local deliveredListeners: { (Player, GiftSize, number) -> () } = {}
local nextId = 0
local mapTarget = 0
local rng = Random.new()
local debugNeeded: number? = nil -- только тесты в Studio: сколько несущих нужно общему подарку

local function neededCarriers(gift: Gift): number
	if gift.size.carriers > 1 and debugNeeded then
		return debugNeeded
	end
	return gift.size.carriers
end

local function getRootPart(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function baseSpeed(player: Player): number
	return player:GetAttribute("BaseSpeed") or S.WalkSpeed
end

local function setSpeed(player: Player, speed: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = speed
	end
end

-- Высота земли под точкой (без персонажей и подарков); nil, если земли под точкой нет
local function groundY(position: Vector3): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { container }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	-- Луч чуть выше точки: подарок ложится на пол под игроком, а не на крышу над ним
	local origin = Vector3.new(position.X, position.Y + G.GroundProbeUp, position.Z)
	local result = Workspace:Raycast(origin, Vector3.new(0, -G.GroundProbeDown, 0), params)
	return if result then result.Position.Y else nil
end

-- Где подарок ляжет в точке position; nil, если там нет земли (край карты)
local function restingCFrame(gift: Gift, position: Vector3): CFrame?
	local y = groundY(position)
	if not y then
		return nil
	end
	return CFrame.new(position.X, y + gift.size.partSize / 2, position.Z)
end

local function publish(gift: Gift)
	gift.model:SetAttribute("State", gift.state)
	gift.model:SetAttribute("Carriers", #gift.carriers)
	if gift.state ~= "Waiting" then
		gift.model:SetAttribute("HelpUntil", nil)
	end
	for _, player in gift.carriers do
		player:SetAttribute("CarryWaiting", gift.state == "Waiting")
	end
end

-- Защита от «улетающих» подарков: не сдвинулся ли подарок дальше, чем можно пройти пешком
local function isHonest(gift: Gift, now: number): boolean
	local elapsed = math.max(0, now - gift.lastCheck)
	local moved = ((gift.root.Position - gift.lastPosition) * Vector3.new(1, 0, 1)).Magnitude
	local slowest = math.huge
	for _, player in gift.carriers do
		slowest = math.min(slowest, player:GetAttribute("BaseSpeed") or S.WalkSpeed)
	end
	if slowest == math.huge then
		slowest = S.WalkSpeed
	end
	return moved <= slowest * gift.size.speedFactor * elapsed * G.SpeedTolerance + G.SpeedSlack
end

local function buildModel(size: GiftSize, cframe: CFrame): (Model, Part)
	local model = Instance.new("Model")
	model.Name = size.id .. "Gift"

	local root = Instance.new("Part")
	root.Name = "Box"
	root.Size = Vector3.new(size.partSize, size.partSize, size.partSize)
	root.Color = size.color
	root.Material = Enum.Material.SmoothPlastic
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.Massless = true
	root.CFrame = cframe -- до лент: WeldConstraint запоминает взаимное положение
	root.Parent = model

	local function decor(name: string, partSize: Vector3, offset: Vector3, shape: Enum.PartType?)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = partSize
		part.Color = Color3.new(1, 1, 1)
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = false
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
		if shape then
			part.Shape = shape
		end
		part.CFrame = root.CFrame * CFrame.new(offset)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		part.Parent = model
	end
	local side = size.partSize
	decor("RibbonX", Vector3.new(side * 1.04, side * 1.04, side * 0.2), Vector3.zero)
	decor("RibbonZ", Vector3.new(side * 0.2, side * 1.04, side * 1.04), Vector3.zero)
	decor(
		"Bow",
		Vector3.new(side * 0.4, side * 0.4, side * 0.4),
		Vector3.new(0, side * 0.6, 0),
		Enum.PartType.Ball
	)

	model.PrimaryPart = root
	model:SetAttribute("Size", size.id)
	model:SetAttribute("Needed", size.carriers)
	model:SetAttribute("Beam", size.beam)
	-- Общие подарки видны всем на сервере (значок «нужна помощь», столб света)
	model.ModelStreamingMode = if size.carriers > 1
		then Enum.ModelStreamingMode.Persistent
		else Enum.ModelStreamingMode.Atomic
	return model, root
end

-- Игрок перестаёт быть несущим (без изменения положения подарка)
local function detach(gift: Gift, player: Player)
	local index = table.find(gift.carriers, player)
	if index then
		table.remove(gift.carriers, index)
	end
	if carrying[player] == gift then
		carrying[player] = nil
	end
	if player.Parent == Players then
		player:SetAttribute("Carrying", nil)
		player:SetAttribute("CarryWaiting", nil)
		setSpeed(player, baseSpeed(player))
	end
end

local pickupSmall: (Player, Gift) -> ()
local fillMapLater: () -> ()

-- Кто уже стоит в подарке, когда его снова можно поднять (Touched повторно не сработает)
local function pickupByOverlap(gift: Gift)
	if gifts[gift.model] ~= gift or gift.state ~= "Idle" or gift.size.carriers ~= 1 then
		return
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { container }
	for _, part in Workspace:GetPartsInPart(gift.root, params) do
		local character = part.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if player then
			pickupSmall(player, gift)
			if gift.state ~= "Idle" then
				return
			end
		end
	end
end

-- Подарок падает на землю и ждёт: поднять может любой
-- voluntary: игрок сам отпустил, обратно в руки подарок не возвращаем
local function drop(gift: Gift, voluntary: boolean?)
	if gift.weld then
		gift.weld:Destroy()
		gift.weld = nil
	end
	for _, player in table.clone(gift.carriers) do
		detach(gift, player)
	end
	-- Куда положить: туда, где подарок сейчас, если он пришёл туда честно и там есть земля.
	-- Иначе в последнюю честную точку: телепорт не продвигает подарок, край карты его не съедает.
	local honest = gift.state ~= "Carried" or isHonest(gift, os.clock())
	local resting = if honest then restingCFrame(gift, gift.root.Position) else nil
	resting = resting or restingCFrame(gift, gift.lastPosition) or CFrame.new(gift.lastPosition)
	gift.root.AssemblyLinearVelocity = Vector3.zero
	gift.root.AssemblyAngularVelocity = Vector3.zero
	gift.root.Anchored = true
	gift.root.CFrame = resting :: CFrame
	gift.lastPosition = gift.root.Position
	gift.root.CanTouch = true
	gift.state = "Idle"
	gift.availableAt = os.clock() + G.PickupCooldown
	publish(gift)
	if not voluntary then
		task.delay(G.PickupCooldown + 0.05, pickupByOverlap, gift)
	end
end

local function removeGift(gift: Gift)
	if gift.weld then
		gift.weld:Destroy()
		gift.weld = nil
	end
	for _, player in table.clone(gift.carriers) do
		detach(gift, player)
	end
	gifts[gift.model] = nil
	gift.model:Destroy()
end

local function canTake(player: Player, gift: Gift, maxDistance: number): BasePart?
	if carrying[player] or os.clock() < gift.availableAt then
		return nil
	end
	if player:GetAttribute("ProfileReady") ~= true then
		return nil
	end
	local rootPart = getRootPart(player)
	if not rootPart then
		return nil
	end
	-- Сервер не верит клиенту: проверяем дистанцию до подарка
	if
		(rootPart.Position - gift.root.Position).Magnitude
		> maxDistance + gift.size.partSize / 2
	then
		return nil
	end
	return rootPart
end

local function startCarry(gift: Gift)
	gift.state = "Carried"
	gift.lastPosition = gift.root.Position
	gift.lastCheck = os.clock()
	gift.root.CanTouch = false
	-- Все несущие идут со скоростью самого медленного (CLAUDE.md, раздел 4.3)
	local slowest = math.huge
	for _, player in gift.carriers do
		slowest = math.min(slowest, baseSpeed(player))
	end
	for _, player in gift.carriers do
		setSpeed(player, slowest * gift.size.speedFactor)
	end
	publish(gift)
end

-- Маленький подарок: касание поднимает, Weld к HumanoidRootPart
function pickupSmall(player: Player, gift: Gift)
	if gift.state ~= "Idle" or gift.size.carriers ~= 1 then
		return
	end
	local rootPart = canTake(player, gift, G.PickupDistance)
	if not rootPart then
		return
	end
	table.insert(gift.carriers, player)
	carrying[player] = gift
	player:SetAttribute("Carrying", gift.size.id)

	gift.root.Anchored = false
	gift.root.CFrame = rootPart.CFrame * CFrame.new(0, 0.2, -(1 + gift.size.partSize / 2))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = gift.root
	weld.Parent = gift.root
	gift.weld = weld
	startCarry(gift)
end

-- Средний и большой: игрок нажал «нести»; подарок поднимается, когда набралось нужное число
local function joinCarry(player: Player, gift: Gift)
	if gift.size.carriers <= 1 or (gift.state ~= "Idle" and gift.state ~= "Waiting") then
		return
	end
	if #gift.carriers >= neededCarriers(gift) or not canTake(player, gift, G.JoinDistance) then
		return
	end
	table.insert(gift.carriers, player)
	carrying[player] = gift
	player:SetAttribute("Carrying", gift.size.id)
	if #gift.carriers >= neededCarriers(gift) then
		startCarry(gift)
	else
		gift.state = "Waiting"
		publish(gift)
	end
end

-- Игрок отпустил: поднятый подарок падает, ожидающий остаётся ждать остальных
local function release(player: Player, voluntary: boolean?)
	local gift = carrying[player]
	if not gift then
		return
	end
	if gift.state == "Carried" then
		drop(gift, voluntary)
	else
		detach(gift, player)
		gift.state = if #gift.carriers > 0 then "Waiting" else "Idle"
		publish(gift)
	end
end

local function createGift(
	size: GiftSize,
	source: string,
	position: Vector3,
	fallTime: number?
): Gift
	nextId += 1
	local resting = CFrame.new(position.X, (groundY(position) or 0) + size.partSize / 2, position.Z)
	local model, root = buildModel(size, resting)
	local gift: Gift = {
		id = nextId,
		size = size,
		model = model,
		root = root,
		source = source,
		state = "Idle",
		carriers = {},
		weld = nil,
		availableAt = 0,
		lastPosition = resting.Position,
		lastCheck = os.clock(),
	}
	gifts[model] = gift

	-- Коробку уничтожило извне (упала за карту): чистим записи и возвращаем подарок на карту
	root.Destroying:Connect(function()
		if gifts[model] ~= gift then
			return
		end
		for _, player in table.clone(gift.carriers) do
			detach(gift, player)
		end
		gifts[model] = nil
		if gift.source == "Map" then
			task.delay(G.RespawnTime, fillMapLater)
		end
	end)

	if fallTime and fallTime > 0 then
		-- Падение рисует клиент; сервер просто не даёт поднять подарок, пока он «летит»
		gift.state = "Falling"
		gift.availableAt = os.clock() + fallTime
		model:SetAttribute("FallStart", Workspace:GetServerTimeNow())
		model:SetAttribute("FallTime", fallTime)
		task.delay(fallTime, function()
			if gifts[model] == gift and gift.state == "Falling" then
				gift.state = "Idle"
				publish(gift)
				pickupByOverlap(gift) -- упал прямо под ноги стоящему игроку
			end
		end)
	end

	if size.carriers == 1 then
		root.Touched:Connect(function(hit)
			if gift.state ~= "Idle" then
				return
			end
			local character = hit.Parent
			local player = character and Players:GetPlayerFromCharacter(character)
			if player then
				pickupSmall(player, gift)
			end
		end)
	else
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "CarryPrompt"
		prompt.ActionText = "🤝"
		prompt.ObjectText = ""
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = G.JoinDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = root
		prompt.Triggered:Connect(function(player)
			if RateLimit.Allow(player, "carry") then
				joinCarry(player, gift)
			end
		end)
	end

	publish(gift)
	CollectionService:AddTag(model, "Gift")
	model.Parent = container
	return gift
end

-- Случайная свободная точка. district = nil: район выбирается по весам mapGiftWeight
local function randomPosition(only: Config.District?): Vector3
	local total = 0
	for _, district in Config.Districts do
		total += district.mapGiftWeight
	end
	for _ = 1, G.SpawnAttempts do
		local district = only or Config.Districts[1]
		if not only then
			local roll = rng:NextNumber() * total
			for _, candidate in Config.Districts do
				roll -= candidate.mapGiftWeight
				if roll < 0 then
					district = candidate
					break
				end
			end
		end
		local position = district.center
			+ Vector3.new(
				(rng:NextNumber() - 0.5) * district.size.X,
				0,
				(rng:NextNumber() - 0.5) * district.size.Y
			)
		local free = (position - Config.World.SleighPosition).Magnitude > G.DeliverDistance
			and (position - Config.World.SpawnPosition).Magnitude > G.SpawnClearance
		if free then
			for _, gift in gifts do
				if (gift.root.Position - position).Magnitude < G.MapSpacing then
					free = false
					break
				end
			end
		end
		if free then
			return position
		end
	end
	local fallback = only or Config.Districts[1]
	return fallback.center + Vector3.new(fallback.size.X / 4, 0, fallback.size.Y / 4)
end

local function countMapGifts(): number
	local count = 0
	for _, gift in gifts do
		if gift.source == "Map" then
			count += 1
		end
	end
	return count
end

local function fillMap()
	while countMapGifts() < mapTarget do
		createGift(G.Sizes.Small, "Map", randomPosition(nil))
	end
end
fillMapLater = fillMap

-- Сдача в сани: засчитывается всем несущим поровну
local function tryDeliver(player: Player)
	local gift = carrying[player]
	if not gift or gift.state ~= "Carried" then
		return
	end
	local rootPart = getRootPart(player)
	local sleigh = Config.World.SleighPosition
	if not rootPart then
		return
	end
	-- Проверка дистанции до саней: и игрок, и сам подарок должны быть рядом
	local flat = Vector3.new(1, 0, 1)
	if ((rootPart.Position - sleigh) * flat).Magnitude > G.DeliverDistance then
		return
	end
	if ((gift.root.Position - sleigh) * flat).Magnitude > G.DeliverDistance then
		return
	end
	-- Телепорт к саням не засчитывается: подарок возвращается в последнюю честную точку
	if not isHonest(gift, os.clock()) then
		drop(gift)
		return
	end

	local carriers = table.clone(gift.carriers)
	local size, source = gift.size, gift.source
	removeGift(gift)
	local share = 1 / #carriers
	for _, carrier in carriers do
		for _, listener in deliveredListeners do
			task.spawn(listener, carrier, size, share)
		end
	end
	if source == "Map" then
		task.delay(G.RespawnTime, function()
			fillMap()
		end)
	end
end

-- Проверки несущих: рядом ли они, не «улетел» ли подарок; движение общих подарков
local function stepCarried(gift: Gift, now: number)
	local sum = Vector3.zero
	for _, player in gift.carriers do
		local rootPart = getRootPart(player)
		if not rootPart then
			drop(gift)
			return
		end
		-- Все несущие должны быть рядом с подарком
		if
			(rootPart.Position - gift.root.Position).Magnitude
			> G.LeashDistance + gift.size.partSize
		then
			drop(gift)
			return
		end
		sum += rootPart.Position
	end

	if gift.size.carriers > 1 then
		-- Серверный CFrame: подарок летит над центром несущих
		local centroid = sum / #gift.carriers
		local target = Vector3.new(centroid.X, centroid.Y + G.CarryHeight, centroid.Z)
		gift.root.CFrame = CFrame.new(gift.root.Position:Lerp(target, G.CarryLerp))
	end

	-- Раз в интервал сверяем пройденный путь; нарушение = подарок падает в честной точке
	if now - gift.lastCheck >= G.SpeedCheckInterval then
		if not isHonest(gift, now) then
			drop(gift)
			return
		end
		gift.lastPosition = gift.root.Position
		gift.lastCheck = now
	end
end

-- Подписка: (игрок, размер, доля) за каждого несущего сданного подарка
function Gifts.OnDelivered(callback: (Player, GiftSize, number) -> ())
	table.insert(deliveredListeners, callback)
end

function Gifts.IsCarrying(player: Player): boolean
	return carrying[player] ~= nil
end

-- Отпустить подарок игрока (помехи, смерть, выход)
function Gifts.Release(player: Player)
	release(player)
end

-- Подарок пролёта: падает в точку position
function Gifts.SpawnDrop(sizeId: string, position: Vector3): Gift?
	local size = G.Sizes[sizeId]
	if not size then
		return nil
	end
	return createGift(size, "Flyby", position, G.DropFallTime)
end

-- Маленький подарок в заданной точке (первая минута, защита новичка)
function Gifts.SpawnSmallAt(position: Vector3): Gift
	return createGift(G.Sizes.Small, "Extra", position)
end

-- Сколько лежащих маленьких подарков в радиусе от точки
function Gifts.CountSmallNear(position: Vector3, radius: number): number
	local count = 0
	for _, gift in gifts do
		if gift.size.carriers == 1 and gift.state == "Idle" then
			if (gift.root.Position - position).Magnitude <= radius then
				count += 1
			end
		end
	end
	return count
end

-- Убрать несданные подарки прошлого пролёта (улетают вместе с Сантой).
-- Те, что прямо сейчас несут, остаются: их ещё можно сдать.
function Gifts.ClearFlyby()
	for _, gift in gifts do
		if gift.source == "Flyby" and gift.state ~= "Carried" then
			removeGift(gift)
		end
	end
end

-- Случайная свободная точка в районе (nil = любой район по весам)
function Gifts.RandomPosition(district: Config.District?): Vector3
	return randomPosition(district)
end

-- Только для тестов в Studio: общий подарок можно поднять меньшим числом игроков
function Gifts.DebugSetNeeded(count: number?)
	if RunService:IsStudio() then
		debugNeeded = count
	end
end

function Gifts.init()
	container = Instance.new("Folder")
	container.Name = "Gifts"
	container.Parent = World.GetFolder()
end

function Gifts.start()
	mapTarget = rng:NextInteger(G.MapMin, G.MapMax)
	fillMap()

	-- Сдача: касание саней или кнопка «Сдать»
	local zone, prompt = World.GetSleighParts()
	if zone then
		zone.Touched:Connect(function(hit)
			local character = hit.Parent
			local player = character and Players:GetPlayerFromCharacter(character)
			if player and carrying[player] then
				tryDeliver(player)
			end
		end)
	end
	if prompt then
		prompt.Triggered:Connect(function(player)
			if RateLimit.Allow(player, "deliver") then
				tryDeliver(player)
			end
		end)
	end

	-- Клиент просит отпустить подарок
	Remotes.Get("DropGift").OnServerEvent:Connect(function(player)
		if RateLimit.Allow(player, "drop") then
			release(player, true)
		end
	end)

	-- Клиент зовёт на помощь: значок над подарком мигает всем
	Remotes.Get("CallHelp").OnServerEvent:Connect(function(player)
		if not RateLimit.Allow(player, "help") then
			return
		end
		local gift = carrying[player]
		if gift and gift.state == "Waiting" then
			gift.model:SetAttribute("HelpUntil", Workspace:GetServerTimeNow() + G.HelpIconTime)
		end
	end)

	local function onCharacter(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function()
				release(player)
			end)
		end
	end
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		player.CharacterRemoving:Connect(function()
			release(player)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		release(player)
		carrying[player] = nil
	end)

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for _, gift in gifts do
			if gift.state == "Carried" then
				stepCarried(gift, now)
			elseif gift.state == "Waiting" then
				-- Ожидающий отошёл от подарка: больше не считается несущим
				for _, player in table.clone(gift.carriers) do
					local rootPart = getRootPart(player)
					if
						not rootPart
						or (rootPart.Position - gift.root.Position).Magnitude
							> G.LeashDistance + gift.size.partSize
					then
						release(player)
					end
				end
			end
		end
	end)
end

return Gifts
