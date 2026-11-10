--!strict
-- Hazards: помехи мира (CLAUDE.md, раздел 4.2). Мешает мир, а не игроки.
-- Лёд в Снежном парке: скользкое покрытие (строит World) и шанс уронить подарок на ходу.
-- Уронённый подарок лежит и ждёт: потерь нет.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local Gifts = require(script.Parent.Gifts)

local Hazards = {}

local rng = Random.new()

local function insideDistrict(district: Config.District, position: Vector3): boolean
	local offset = position - district.center
	return math.abs(offset.X) <= district.size.X / 2 and math.abs(offset.Z) <= district.size.Y / 2
end

local lastPosition: { [Player]: Vector3 } = {}

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Стоит ли игрок на льду
function Hazards.IsOnIce(player: Player): boolean
	local root = getRoot(player)
	if not root then
		return false
	end
	for _, district in Config.Districts do
		if district.ice and insideDistrict(district, root.Position) then
			return true
		end
	end
	return false
end

-- Сколько студов игрок прошёл с прошлой проверки (скорости клиента сервер не верит)
local function movedSinceLastCheck(player: Player): number
	local root = getRoot(player)
	if not root then
		lastPosition[player] = nil
		return 0
	end
	local previous = lastPosition[player]
	lastPosition[player] = root.Position
	if not previous then
		return 0
	end
	return ((root.Position - previous) * Vector3.new(1, 0, 1)).Magnitude
end

function Hazards.start()
	Players.PlayerRemoving:Connect(function(player)
		lastPosition[player] = nil
	end)

	task.spawn(function()
		while true do
			local elapsed = task.wait(Config.Ice.CheckInterval)
			local moving: { [Player]: boolean } = {}
			for _, player in Players:GetPlayers() do
				moving[player] = movedSinceLastCheck(player) / elapsed >= Config.Ice.MinMoveSpeed
			end
			-- Один бросок на подарок, а не на каждого несущего: втроём шанс уронить тот же
			for _, carriers in Gifts.GetCarriedGroups() do
				local slipping = false
				for _, player in carriers do
					-- Стоящий на месте не роняет
					if moving[player] and Hazards.IsOnIce(player) then
						slipping = true
						break
					end
				end
				if slipping and rng:NextNumber() < Config.Ice.DropChance then
					Gifts.Release(carriers[1])
					for _, player in carriers do
						Remotes.Get("Notify")
							:FireClient(player, "🧊", Color3.fromRGB(150, 220, 255))
					end
				end
			end
		end
	end)
end

return Hazards
