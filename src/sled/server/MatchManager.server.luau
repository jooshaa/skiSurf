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

local requestStartEv = Instance.new("RemoteEvent")
requestStartEv.Name = "RequestStart"
requestStartEv.Parent = net

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
	slot: number,
}

local phase: "lobby" | "racing" = "lobby"
local lobbyTimer = M.LobbyWait
local startRequested = false

local function buildSlots(): { SlotInfo }
	local slots: { SlotInfo } = {}
	local players = Players:GetPlayers()
	for i = 1, math.min(#players, M.MaxRacers) do
		local p = players[i]
		table.insert(slots, {
			userId = p.UserId,
			name = p.DisplayName,
			isBot = false,
			slot = #slots + 1,
		})
	end
	local botIdx = 0
	while #slots < M.MaxRacers do
		botIdx += 1
		local botName = RV.Names[botIdx] or ("Bot" .. botIdx)
		table.insert(slots, {
			userId = -botIdx,
			name = botName,
			isBot = true,
			slot = #slots + 1,
		})
	end
	return slots
end

local function broadcastState()
	matchStateEv:FireAllClients({
		phase = phase,
		timer = lobbyTimer,
		slots = buildSlots(),
	})
end

requestStartEv.OnServerEvent:Connect(function()
	if phase == "lobby" then
		startRequested = true
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
	task.defer(function()
		matchStateEv:FireClient(player, {
			phase = phase,
			timer = lobbyTimer,
			slots = buildSlots(),
		})
	end)
end)

Players.PlayerRemoving:Connect(function()
	task.defer(function()
		if #Players:GetPlayers() == 0 then
			phase = "lobby"
			lobbyTimer = M.LobbyWait
			startRequested = false
		elseif phase == "lobby" then
			broadcastState()
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
			startRequested = false
			continue
		end

		if phase == "lobby" then
			local mountain = Workspace:FindFirstChild("Mountain")
			local trackReady = mountain ~= nil and mountain:GetAttribute("TrackReady") == true
			if trackReady then
				lobbyTimer = math.max(0, lobbyTimer - 0.25)
			end
			broadcastState()
			if trackReady and (lobbyTimer <= 0 or startRequested) then
				phase = "racing"
				startRequested = false
				broadcastState()
			end
		end
	end
end)
