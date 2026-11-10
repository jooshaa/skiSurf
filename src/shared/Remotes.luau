--!strict
-- Remotes: единый список RemoteEvent. Сервер создаёт, клиент ждёт.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "RemoteEvents"

-- Сервер -> клиент, если не указано иное
local NAMES = {
	"Announce", -- (playerName, elfName, color) редкий эльф, всем
	"Notify", -- (text, color) короткое уведомление одному игроку
	"RoundState", -- ({phase, delivered, target, endsAt}) норма и таймер для HUD
	"DropGift", -- клиент -> сервер: отпустить подарок
	"CallHelp", -- клиент -> сервер: позвать на помощь к общему подарку
}

local Remotes = {}

local folder: Instance
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	local target = existing or Instance.new("Folder")
	target.Name = FOLDER_NAME
	for _, name in NAMES do
		if not target:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = target
		end
	end
	target.Parent = ReplicatedStorage
	folder = target
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

function Remotes.Get(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
