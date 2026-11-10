--!strict
-- ElfService: выдача эльфов и выбор «работающих» (лучшие по доходу, не больше слотов мастерской).
-- Остальные эльфы ждут в хранилище: ничего не теряется (CLAUDE.md, красная линия 2).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Elves = require(ReplicatedStorage.Elves)
local Remotes = require(ReplicatedStorage.Remotes)

local S = Config.Settings

local ElfService = {}

local listeners: { (Player) -> () } = {}
local pending: { [Player]: boolean } = {}
local connections: { [Player]: { RBXScriptConnection } } = {}

-- Подписка: набор работающих эльфов игрока изменился
function ElfService.OnActiveChanged(callback: (Player) -> ())
	table.insert(listeners, callback)
end

-- Пересчитать работающих эльфов: лучшие по доходу, при равенстве раньше полученные
function ElfService.RefreshActive(player: Player)
	local folder = player:FindFirstChild("Elves")
	if not folder then
		return
	end
	local list = folder:GetChildren()
	table.sort(list, function(a, b)
		local incomeA = a:GetAttribute("Income") or 0
		local incomeB = b:GetAttribute("Income") or 0
		if incomeA ~= incomeB then
			return incomeA > incomeB
		end
		return (a:GetAttribute("Order") or 0) < (b:GetAttribute("Order") or 0)
	end)
	local slots = player:GetAttribute("Slots") or Config.Elves.StartSlots
	for index, elf in list do
		local active = index <= slots
		if elf:GetAttribute("Active") ~= active then
			elf:SetAttribute("Active", active)
		end
	end
	for _, callback in listeners do
		task.spawn(callback, player)
	end
end

-- Несколько изменений папки за кадр дают один пересчёт
local function scheduleRefresh(player: Player)
	if pending[player] then
		return
	end
	pending[player] = true
	task.defer(function()
		pending[player] = nil
		if player.Parent == Players then
			ElfService.RefreshActive(player)
		end
	end)
end

-- Можно ли выдать ещё одного эльфа (есть место в сохранении)
function ElfService.HasRoom(player: Player): boolean
	local folder = player:FindFirstChild("Elves")
	return folder ~= nil and #folder:GetChildren() < Config.Elves.MaxStored
end

-- Выдать эльфа. Редкость и мутация по именам; nil = ролл по Config.
-- Возвращает эльфа или nil и причину ("loading" / "full" / "invalid")
function ElfService.Grant(
	player: Player,
	rarityName: string?,
	mutationName: string?
): (StringValue?, string?)
	local folder = player:FindFirstChild("Elves")
	if not folder or player:GetAttribute("ProfileReady") ~= true then
		return nil, "loading"
	end
	if #folder:GetChildren() >= Config.Elves.MaxStored then
		return nil, "full"
	end
	local rarity = if rarityName then Elves.GetRarity(rarityName) else Elves.RollRarity()
	local mutation = Elves.GetMutation(mutationName or "None")
	if not rarity or not mutation then
		return nil, "invalid"
	end
	local elf = Elves.MakeElfValue(rarity.name, mutation.name)
	if not elf then
		return nil, "invalid"
	end
	elf.Parent = folder

	-- Редкие дропы объявляются всему серверу
	if rarity.announce or mutation.announce then
		local color = if mutation.announce then mutation.color else rarity.color
		Remotes.Get("Announce"):FireAllClients(player.Name, elf.Name, color)
	end
	return elf, nil
end

local function onPlayerAdded(player: Player)
	local folder = player:WaitForChild("Elves", S.LoadTimeout)
	if not folder or player.Parent ~= Players then
		return
	end
	connections[player] = {
		folder.ChildAdded:Connect(function()
			scheduleRefresh(player)
		end),
		folder.ChildRemoved:Connect(function()
			scheduleRefresh(player)
		end),
		player:GetAttributeChangedSignal("Slots"):Connect(function()
			scheduleRefresh(player)
		end),
	}
	ElfService.RefreshActive(player)
end

function ElfService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		for _, connection in connections[player] or {} do
			connection:Disconnect()
		end
		connections[player] = nil
		pending[player] = nil
	end)
end

return ElfService
