--!strict
-- Round: норма сервера и сданные подарки игроков. Цикл пролётов Санты добавляется на шаге 3.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local Gifts = require(script.Parent.Gifts)

local R = Config.Round

type GiftSize = Config.GiftSize
type Delivery = { size: GiftSize, share: number }

local Round = {}

local phase = "Active"
local endsAt = 0
local deliveredShares = 0 -- сумма долей; один подарок = 1
local pending: { [Player]: { Delivery } } = {}

local function quotaTarget(): number
	return R.QuotaBase + R.QuotaPerExtraPlayer * math.max(0, #Players:GetPlayers() - 1)
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

function Round.GetDelivered(): number
	return deliveredCount()
end

function Round.GetTarget(): number
	return quotaTarget()
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

	Players.PlayerAdded:Connect(function(player)
		Remotes.Get("RoundState"):FireClient(player, snapshot())
		broadcast() -- норма растёт с числом игроков
	end)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		task.defer(broadcast)
	end)
	broadcast()
end

return Round
