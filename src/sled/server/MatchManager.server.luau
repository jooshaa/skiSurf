--!strict
-- MatchManager: серверное лобби и матчмейкинг на 4 участников (реальные игроки + боты на пустые слоты),
-- репликация 3D-позиций санок и суперсил между игроками в реальном времени.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SledConfig = require(ReplicatedStorage.SledConfig)

local M = SledConfig.Match
local RV = SledConfig.Rivals

local net = Instance.new("Folder")
net.Name = "SledNet"
net.Parent = ReplicatedStorage

local matchStateEv = Instance.new("RemoteEvent")
matchStateEv.Name = "MatchState"
matchStateEv.Parent = net

local clientReadyEv = Instance.new("RemoteEvent")
clientReadyEv.Name = "ClientReady"
clientReadyEv.Parent = net

local sledPoseEv = Instance.new("UnreliableRemoteEvent")
sledPoseEv.Name = "SledPose"
sledPoseEv.Parent = net

local powerupUsedEv = Instance.new("RemoteEvent")
powerupUsedEv.Name = "PowerupUsed"
powerupUsedEv.Parent = net

export type SlotInfo = {
	userId: number,
	name: string,
	isBot: boolean,
	ready: boolean,
	waiting: boolean,
	slot: number,
}

local phase: "lobby" | "racing" = "lobby"
local lobbyTimer = M.LobbyWait
local readyPlayers: { [number]: boolean } = {}

local function areAllPlayersReady(players: { Player }): boolean
	if #players == 0 then
		return false
	end
	for i = 1, math.min(#players, M.MaxRacers) do
		if not readyPlayers[players[i].UserId] then
			return false
		end
	end
	return true
end

local function buildSlots(includeBots: boolean): { SlotInfo }
	local slots: { SlotInfo } = {}
	local players = Players:GetPlayers()
	for i = 1, math.min(#players, M.MaxRacers) do
		local p = players[i]
		table.insert(slots, {
			userId = p.UserId,
			name = p.DisplayName,
			isBot = false,
			ready = readyPlayers[p.UserId] == true,
			waiting = false,
			slot = #slots + 1,
		})
	end
	local botIdx = 0
	while #slots < M.MaxRacers do
		if includeBots then
			botIdx += 1
			local botName = RV.Names[botIdx] or ("Bot" .. botIdx)
			table.insert(slots, {
				userId = -botIdx,
				name = botName,
				isBot = true,
				ready = true,
				waiting = false,
				slot = #slots + 1,
			})
		else
			table.insert(slots, {
				userId = 0,
				name = "Ожидание игрока...",
				isBot = false,
				ready = false,
				waiting = true,
				slot = #slots + 1,
			})
		end
	end
	return slots
end

local function broadcastState(includeBots: boolean)
	local players = Players:GetPlayers()
	matchStateEv:FireAllClients({
		phase = phase,
		timer = math.max(0, lobbyTimer),
		realCount = math.min(#players, M.MaxRacers),
		allReady = areAllPlayersReady(players),
		slots = buildSlots(includeBots),
	})
end

clientReadyEv.OnServerEvent:Connect(function(player: Player)
	readyPlayers[player.UserId] = true
	if phase == "lobby" then
		broadcastState(false)
	end
end)

sledPoseEv.OnServerEvent:Connect(
	function(
		player: Player,
		cf: CFrame,
		s: number,
		d: number,
		v: number,
		shield: boolean,
		boost: boolean,
		stunned: boolean
	)
		if typeof(cf) ~= "CFrame" or typeof(s) ~= "number" or typeof(d) ~= "number" then
			return
		end
		for _, other in Players:GetPlayers() do
			if other ~= player then
				sledPoseEv:FireClient(other, player.UserId, cf, s, d, v, shield, boost, stunned)
			end
		end
	end
)

powerupUsedEv.OnServerEvent:Connect(
	function(
		player: Player,
		kind: string,
		s: number,
		d: number,
		v: number,
		targetId: string?,
		cf: CFrame?
	)
		if typeof(kind) ~= "string" then
			return
		end
		for _, other in Players:GetPlayers() do
			if other ~= player then
				powerupUsedEv:FireClient(other, player.UserId, kind, s, d, v, targetId, cf)
			end
		end
	end
)

Players.PlayerAdded:Connect(function(player: Player)
	readyPlayers[player.UserId] = false
	task.defer(function()
		local players = Players:GetPlayers()
		matchStateEv:FireClient(player, {
			phase = phase,
			timer = math.max(0, lobbyTimer),
			realCount = math.min(#players, M.MaxRacers),
			allReady = areAllPlayersReady(players),
			slots = buildSlots(phase == "racing"),
		})
	end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	readyPlayers[player.UserId] = nil
	task.defer(function()
		if #Players:GetPlayers() == 0 then
			phase = "lobby"
			lobbyTimer = M.LobbyWait
		elseif phase == "lobby" then
			broadcastState(false)
		end
	end)
end)

task.spawn(function()
	while true do
		task.wait(0.25)
		local players = Players:GetPlayers()
		if #players == 0 then
			phase = "lobby"
			lobbyTimer = M.LobbyWait
			continue
		end

		if phase == "lobby" then
			local mountain = Workspace:FindFirstChild("Mountain")
			local trackReady = mountain ~= nil and mountain:GetAttribute("TrackReady") == true
			if trackReady then
				lobbyTimer -= 0.25
			end
			local allReady = areAllPlayersReady(players)
			local fullLobby = #players >= M.MaxRacers and allReady
			local timerDone = lobbyTimer <= 0 and (allReady or lobbyTimer <= -4)
			if trackReady and (fullLobby or timerDone) then
				phase = "racing"
				broadcastState(true)
			else
				broadcastState(false)
			end
		end
	end
end)
