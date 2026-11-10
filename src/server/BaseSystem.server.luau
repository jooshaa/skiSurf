-- BaseSystem: выдача баз игрокам и модели драконов на базе (анимации на клиенте)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local DragonConfig = require(ReplicatedStorage:WaitForChild("DragonConfig"))
local DragonVisuals = require(ReplicatedStorage:WaitForChild("DragonVisuals"))
local S = DragonConfig.Settings

local basesFolder = Workspace:WaitForChild("Bases")
local bases = basesFolder:GetChildren()
table.sort(bases, function(a, b)
	return a.Name < b.Name
end)

local playerBase = {} -- player -> Part базы
local playerModels = {} -- player -> { [StringValue] = Model }
local playerConns = {} -- player -> соединения

local function setOwnerLabel(base, text)
	local gui = base:FindFirstChild("OwnerGui")
	local label = gui and gui:FindFirstChild("Label")
	if label then
		label.Text = text
	end
end

-- Занять свободную базу
local function claimBase(player)
	for _, base in ipairs(bases) do
		local owner = base:FindFirstChild("Owner")
		if owner and owner.Value == nil then
			owner.Value = player
			setOwnerLabel(base, player.Name)
			playerBase[player] = base
			return base
		end
	end
	warn("[BaseSystem] Нет свободной базы для " .. player.Name)
	return nil
end

-- Освободить базу
local function releaseBase(player)
	local base = playerBase[player]
	if base then
		base.Owner.Value = nil
		setOwnerLabel(base, "Свободно")
		playerBase[player] = nil
	end
end

-- Позиция слота сетки над базой (index с нуля)
local function slotCFrame(base, index)
	local col = index % S.GridCols
	local row = math.floor(index / S.GridCols)
	local x = (col - (S.GridCols - 1) / 2) * S.GridStep
	local z = (row - (S.GridCols - 1) / 2) * S.GridStep
	return base.CFrame * CFrame.new(x, base.Size.Y / 2 + 1.5, z)
end

-- Раскладываем модели по сетке в порядке папки Dragons
local function layout(player)
	local base = playerBase[player]
	local models = playerModels[player]
	local folder = player:FindFirstChild("Dragons")
	if not base or not models or not folder then
		return
	end
	local i = 0
	for _, dragon in ipairs(folder:GetChildren()) do
		local model = models[dragon]
		if model then
			local cf = slotCFrame(base, i)
			if model:GetAttribute("SlotCFrame") ~= cf then -- переставляем только изменившиеся
				model:SetAttribute("SlotCFrame", cf) -- клиент качает дракона вокруг этой точки
				model:PivotTo(cf)
			end
			i += 1
		end
	end
end

local function countModels(models)
	local n = 0
	for _ in pairs(models) do
		n += 1
	end
	return n
end

-- Создать модель для дракона (с учётом лимита видимых)
local function addDragonModel(player, dragon, skipLayout)
	local base = playerBase[player]
	local models = playerModels[player]
	if not base or not models or models[dragon] then
		return
	end
	if countModels(models) >= S.MaxVisibleDragons then
		return
	end
	local rarity = dragon:GetAttribute("Rarity")
	local model = DragonVisuals.CreateDragon(dragon:GetAttribute("Element"), rarity)
	if not model then
		return
	end
	model.Name = dragon.Name
	DragonVisuals.AddNameTag(model, rarity)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- части приходят на клиент вместе
	CollectionService:AddTag(model, "Dragon")
	models[dragon] = model
	local container = base:FindFirstChild("Dragons")
	if not container then
		container = Instance.new("Folder")
		container.Name = "Dragons"
		container.Parent = base
	end
	model.Parent = container
	if not skipLayout then
		layout(player)
	end
end

-- Удалить модель и подтянуть следующего невидимого дракона
local function removeDragonModel(player, dragon)
	local models = playerModels[player]
	if not models then
		return
	end
	if models[dragon] then
		models[dragon]:Destroy()
		models[dragon] = nil
	end
	local folder = player:FindFirstChild("Dragons")
	if folder then
		for _, d in ipairs(folder:GetChildren()) do
			if not models[d] then
				addDragonModel(player, d, true)
				break
			end
		end
	end
	layout(player)
end

local function onPlayerAdded(player)
	playerModels[player] = {}
	claimBase(player)

	local folder = player:WaitForChild("Dragons", S.LoadTimeout)
	if not folder or not playerModels[player] then
		return
	end
	playerConns[player] = {
		folder.ChildAdded:Connect(function(d)
			addDragonModel(player, d)
		end),
		folder.ChildRemoved:Connect(function(d)
			removeDragonModel(player, d)
		end),
	}
	-- Начальная раскладка одним проходом, а не после каждого дракона
	for _, d in ipairs(folder:GetChildren()) do
		addDragonModel(player, d, true)
	end
	layout(player)
end

local function onPlayerRemoving(player)
	for _, c in ipairs(playerConns[player] or {}) do
		c:Disconnect()
	end
	for _, model in pairs(playerModels[player] or {}) do
		model:Destroy()
	end
	playerConns[player] = nil
	playerModels[player] = nil
	releaseBase(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end
