--!strict
-- Powerups: правила и расстановка боксов со знаком «?» по трассе, логика выбора способности
-- в стиле Beach Buggy Racing / Mario Kart (с балансировкой по текущей позиции в гонке).
local SledConfig = require(script.Parent.SledConfig)
local Track = require(script.Parent.Track)

local P = SledConfig.Powerups

export type Kind =
	"Rocket"
	| "Fireworks"
	| "Boost"
	| "Shield"
	| "Snowball"
	| "FreezeWave"
	| "IceMine"
	| "Magnet"

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

-- Выбор предмета в зависимости от позиции гонщика (8 случайных способностей в стиле BB Racing):
function Powerups.RollItem(rank: number, totalRacers: number?): Kind
	local total = totalRacers or 4
	local roll = math.random()
	local isTrailing = rank >= math.max(2, total - 1)
	local isLeading = rank == 1

	if isTrailing then
		-- Отстающий: чаще получает ракету, буст, магнит или снежную лавину
		if roll < 0.30 then
			return "Rocket"
		elseif roll < 0.48 then
			return "Boost"
		elseif roll < 0.62 then
			return "Magnet"
		elseif roll < 0.76 then
			return "Snowball"
		elseif roll < 0.86 then
			return "Fireworks"
		elseif roll < 0.94 then
			return "FreezeWave"
		else
			return "Shield"
		end
	elseif isLeading then
		-- Лидер: чаще получает щит, ледяную мину, ледяную волну или снежную атаку
		if roll < 0.24 then
			return "Shield"
		elseif roll < 0.44 then
			return "IceMine"
		elseif roll < 0.62 then
			return "Snowball"
		elseif roll < 0.76 then
			return "FreezeWave"
		elseif roll < 0.88 then
			return "Fireworks"
		elseif roll < 0.94 then
			return "Rocket"
		else
			return "Boost"
		end
	else
		-- Середина пелотона: равномерный микс всех 8 способностей
		if roll < 0.17 then
			return "Rocket"
		elseif roll < 0.31 then
			return "Snowball"
		elseif roll < 0.44 then
			return "Fireworks"
		elseif roll < 0.57 then
			return "Shield"
		elseif roll < 0.70 then
			return "Boost"
		elseif roll < 0.81 then
			return "FreezeWave"
		elseif roll < 0.91 then
			return "IceMine"
		else
			return "Magnet"
		end
	end
end

return Powerups
