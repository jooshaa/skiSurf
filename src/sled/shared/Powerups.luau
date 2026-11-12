--!strict
-- Powerups: правила и расстановка боксов со знаком «?» по трассе, логика выбора способности
-- в стиле Beach Buggy Racing / Mario Kart (с балансировкой по текущей позиции в гонке).
local SledConfig = require(script.Parent.SledConfig)
local Track = require(script.Parent.Track)

local P = SledConfig.Powerups

export type Kind = "Rocket" | "Fireworks" | "Boost" | "Shield"

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

-- Выбор предмета в зависимости от позиции гонщика (резиновая лента / Mario Kart balance):
-- лидер получает защиту и салют, отстающие — ракету и ускорение
function Powerups.RollItem(rank: number, totalRacers: number?): Kind
	local total = totalRacers or 4
	local roll = math.random()
	local isTrailing = rank >= math.max(2, total - 1)
	local isLeading = rank == 1

	if isTrailing then
		-- Отстающий: нужен рывок вперед или сбить лидера
		if roll < 0.45 then
			return "Rocket"
		elseif roll < 0.80 then
			return "Boost"
		elseif roll < 0.95 then
			return "Fireworks"
		else
			return "Shield"
		end
	elseif isLeading then
		-- Лидер: защищается от ракет или разбрасывает фейерверки позади
		if roll < 0.40 then
			return "Shield"
		elseif roll < 0.75 then
			return "Fireworks"
		elseif roll < 0.90 then
			return "Rocket"
		else
			return "Boost"
		end
	else
		-- Середина пелотона: сбалансированный дроп
		if roll < 0.35 then
			return "Rocket"
		elseif roll < 0.65 then
			return "Fireworks"
		elseif roll < 0.85 then
			return "Boost"
		else
			return "Shield"
		end
	end
end

return Powerups
