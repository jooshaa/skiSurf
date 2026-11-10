--!strict
-- RateLimit: token bucket на игрока и канал (CLAUDE.md, раздел 9: 5 запросов в секунду).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)

local S = Config.Settings

type Bucket = { tokens: number, last: number }

local buckets: { [Player]: { [string]: Bucket } } = {}

local RateLimit = {}

-- true, если запрос разрешён; channel разделяет лимиты разных действий
function RateLimit.Allow(player: Player, channel: string): boolean
	local now = os.clock()
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local bucket = perPlayer[channel]
	if not bucket then
		bucket = { tokens = S.RateLimitBurst, last = now }
		perPlayer[channel] = bucket
	end
	bucket.tokens =
		math.min(S.RateLimitBurst, bucket.tokens + (now - bucket.last) * S.RateLimitPerSecond)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

return RateLimit
