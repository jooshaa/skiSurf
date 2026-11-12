--!strict
-- Powerups: правила и расстановка боксов со знаком «?» по трассе, логика выбора способности
-- в стиле Beach Buggy Racing / Mario Kart (с балансировкой по текущей позиции в гонке).
local SledConfig = require(script.Parent.SledConfig)
local Track = require(script.Parent.Track)

local P = SledConfig.Powerups

export type Kind = "Rocket" | "Fireworks" | "Boost" | "Shield" | "Snowball"

export type Box = {
	id: number,
	s: number,
	d: number,
	active: boolean,
	cooldown: number,
}

local Powerups = {}

local cachedBoxes: { Box }? = nil

-- Создаёт и кэширует список боксов на полотне трассы
function Powerups.GetBoxes(track: Track.Data): { Box }
	if cachedBoxes then
		return cachedBoxes
	end

	local list: { Box } = {}
	local boxId = 0

	for _, lineRatio in P.BoxLines do
		local s = track.startS + (track.finishS - track.startS) * lineRatio
		local _, _, _, width = Track.At(track, s)
		local usableWidth = (width - SledConfig.Physics.EdgeInset * 2) * P.BoxSpread
		local count = P.BoxesPerLine

		for i = 1, count do
			boxId += 1
			local t = if count > 1 then (i - 1) / (count - 1) * 2 - 1 else 0
			local d = t * (usableWidth / 2)
			table.insert(list, {
				id = boxId,
				s = s,
				d = d,
				active = true,
				cooldown = 0,
			})
		end
	end

	cachedBoxes = list
	return list
end

-- Сброс состояния боксов при перезапуске гонки
function Powerups.ResetBoxes(boxes: { Box })
	for _, box in boxes do
		box.active = true
		box.cooldown = 0
	end
end

-- Выбор предмета в зависимости от позиции гонщика (резиновая лента / Beach Buggy Racing balance):
-- включает Ракети (Rocket), Салют вперёд (Fireworks), Лавину снежных шаров (Snowball), Нитро (Boost) и Щит на время (Shield)
function Powerups.RollItem(rank: number, totalRacers: number?): Kind
	local total = totalRacers or 4
	local roll = math.random()
	local isTrailing = rank >= math.max(2, total - 1)
	local isLeading = rank == 1

	if isTrailing then
		-- Отстающий: чаще получает ракету, буст или снежную лавину впереди
		if roll < 0.36 then
			return "Rocket"
		elseif roll < 0.58 then
			return "Boost"
		elseif roll < 0.76 then
			return "Snowball"
		elseif roll < 0.90 then
			return "Fireworks"
		else
			return "Shield"
		end
	elseif isLeading then
		-- Лидер: чаще получает щит на время, снежную атаку или прямой салют
		if roll < 0.32 then
			return "Shield"
		elseif roll < 0.58 then
			return "Snowball"
		elseif roll < 0.80 then
			return "Fireworks"
		elseif roll < 0.90 then
			return "Rocket"
		else
			return "Boost"
		end
	else
		-- Середина пелотона: равномерный баланс всех 5 способностей
		if roll < 0.24 then
			return "Rocket"
		elseif roll < 0.46 then
			return "Snowball"
		elseif roll < 0.66 then
			return "Fireworks"
		elseif roll < 0.84 then
			return "Shield"
		else
			return "Boost"
		end
	end
end

return Powerups
