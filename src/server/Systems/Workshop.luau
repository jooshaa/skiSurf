--!strict
-- Workshop: выдача мастерских игрокам и модели работающих эльфов в них (анимации на клиенте).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local ElfVisuals = require(ReplicatedStorage.ElfVisuals)
local ElfService = require(script.Parent.ElfService)
local World = require(script.Parent.World)

local W = Config.World

local Workshop = {}

local playerPad: { [Player]: Part } = {}
local playerModels: { [Player]: { [Instance]: Model } } = {}

local function setOwnerLabel(pad: Part, text: string)
	local gui = pad:FindFirstChild("OwnerGui")
	local label = gui and gui:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function getOwnerValue(pad: Part): ObjectValue?
	local owner = pad:FindFirstChild("Owner")
	if owner and owner:IsA("ObjectValue") then
		return owner
	end
	return nil
end

-- Занять свободную мастерскую
local function claimPad(player: Player): Part?
	for _, pad in World.GetWorkshops() do
		local owner = getOwnerValue(pad)
		if owner and owner.Value == nil then
			owner.Value = player
			setOwnerLabel(pad, player.DisplayName)
			playerPad[player] = pad
			player:SetAttribute("WorkshopPosition", pad.Position)
			return pad
		end
	end
	warn("[Workshop] Нет свободной мастерской для " .. player.Name)
	return nil
end

local function releasePad(player: Player)
	local pad = playerPad[player]
	if pad then
		local owner = getOwnerValue(pad)
		if owner then
			owner.Value = nil
		end
		setOwnerLabel(pad, "")
		playerPad[player] = nil
	end
end

-- Позиция слота сетки над площадкой (index с нуля), эльф стоит ступнями на полу
local function slotCFrame(pad: Part, index: number, total: number): CFrame
	local rows = math.max(1, math.ceil(total / W.GridCols))
	local col = index % W.GridCols
	local row = math.floor(index / W.GridCols)
	local x = (col - (W.GridCols - 1) / 2) * W.GridStep
	local z = (row - (rows - 1) / 2) * W.GridStep
	return pad.CFrame * CFrame.new(x, pad.Size.Y / 2 + 1.5, z)
end

-- Мастерская игрока (для других систем)
function Workshop.GetPad(player: Player): Part?
	return playerPad[player]
end

-- Привести модели в мастерской к набору работающих эльфов
function Workshop.Refresh(player: Player)
	local pad = playerPad[player]
	local models = playerModels[player]
	local folder = player:FindFirstChild("Elves")
	if not pad or not models or not folder then
		return
	end

	for elf, model in models do
		if elf.Parent ~= folder or elf:GetAttribute("Active") ~= true then
			model:Destroy()
			models[elf] = nil
		end
	end

	local active = {}
	for _, elf in folder:GetChildren() do
		if elf:GetAttribute("Active") == true then
			table.insert(active, elf)
		end
	end
	table.sort(active, function(a, b)
		return (a:GetAttribute("Order") or 0) < (b:GetAttribute("Order") or 0)
	end)

	local container = pad:FindFirstChild("Elves") or pad
	local slots = player:GetAttribute("Slots") or Config.Elves.StartSlots
	for index, elf in active do
		local model = models[elf]
		if not model then
			local rarity = elf:GetAttribute("Rarity")
			local created = ElfVisuals.CreateElf(rarity, elf:GetAttribute("Mutation"))
			if created then
				ElfVisuals.AddNameTag(created, rarity)
				created.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- части приходят на клиент вместе
				CollectionService:AddTag(created, "Elf")
				models[elf] = created
				created.Parent = container
				model = created
			end
		end
		if model then
			local cframe = slotCFrame(pad, index - 1, slots)
			if model:GetAttribute("SlotCFrame") ~= cframe then -- переставляем только изменившиеся
				model:SetAttribute("SlotCFrame", cframe) -- клиент качает эльфа вокруг этой точки
				model:PivotTo(cframe)
			end
		end
	end
end

local function onPlayerAdded(player: Player)
	if playerModels[player] then
		return
	end
	playerModels[player] = {}
	claimPad(player)
	Workshop.Refresh(player)
end

local function onPlayerRemoving(player: Player)
	for _, model in playerModels[player] or {} do
		model:Destroy()
	end
	playerModels[player] = nil
	releasePad(player)
end

function Workshop.start()
	ElfService.OnActiveChanged(Workshop.Refresh)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return Workshop
