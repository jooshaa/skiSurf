--!strict
-- AnnounceClient: показывает объявления и уведомления, плавно скрывает
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config") :: ModuleScript) :: any
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes") :: ModuleScript) :: any

local S = Config.Settings
local Announce: RemoteEvent = Remotes.Get("Announce")
local Notify: RemoteEvent = Remotes.Get("Notify")

local gui = script.Parent :: Instance
local announceLabel = gui:WaitForChild("Label") :: TextLabel
local noticeLabel = gui:WaitForChild("Notice") :: TextLabel

type ShowState = { token: number, tween: Tween? }

-- Состояние показа для каждой метки
local state: { [TextLabel]: ShowState } = {}

local function show(label: TextLabel, text: string, color: Color3?)
	local st = state[label] or { token = 0 }
	state[label] = st
	st.token += 1
	local myToken = st.token
	if st.tween then
		st.tween:Cancel()
	end

	label.Text = text
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.4

	task.delay(S.AnnounceDuration, function()
		if st.token ~= myToken then
			return -- уже показано что-то новое
		end
		local tween = TweenService:Create(label, TweenInfo.new(S.AnnounceFadeTime), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		st.tween = tween
		tween:Play()
	end)
end

Announce.OnClientEvent:Connect(function(playerName: any, elfName: any, color: any)
	show(
		announceLabel,
		tostring(playerName) .. " 🎁 " .. tostring(elfName) .. "!",
		if typeof(color) == "Color3" then color else nil
	)
end)

Notify.OnClientEvent:Connect(function(text: any, color: any)
	show(noticeLabel, tostring(text), if typeof(color) == "Color3" then color else nil)
end)
