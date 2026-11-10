--!strict
-- Income: один общий цикл дохода на сервер (CLAUDE.md, раздел 9). Суммы берём из кэша,
-- кэш пересчитывается только когда меняется набор работающих эльфов.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local ElfService = require(script.Parent.ElfService)
local PlayerData = require(script.Parent.PlayerData)

local S = Config.Settings

local Income = {}

local income: { [Player]: number } = {} -- монет/сек
local remainder: { [Player]: number } = {} -- дробный остаток (мутации дают нецелый доход)

local function recompute(player: Player)
	local folder = player:FindFirstChild("Elves")
	if not folder or player.Parent ~= Players then
		return
	end
	local total = 0
	for _, elf in folder:GetChildren() do
		if elf:GetAttribute("Active") == true then
			total += elf:GetAttribute("Income") or 0
		end
	end
	income[player] = total
	player:SetAttribute("IncomePerSecond", total)
end

function Income.Get(player: Player): number
	return income[player] or 0
end

function Income.start()
	ElfService.OnActiveChanged(recompute)
	for _, player in Players:GetPlayers() do
		recompute(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		income[player] = nil
		remainder[player] = nil
	end)

	-- Единый цикл дохода: O(игроков) за тик
	task.spawn(function()
		while true do
			local elapsed = task.wait(S.IncomeInterval)
			for player, amount in income do
				if amount > 0 then
					local total = (remainder[player] or 0) + amount * elapsed
					local whole = math.floor(total)
					remainder[player] = total - whole
					if whole > 0 then
						PlayerData.AddCoins(player, whole)
					end
				end
			end
		end
	end)
end

return Income
