-- AnnounceClient: показывает объявления и уведомления, плавно скрывает
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local DragonConfig = require(ReplicatedStorage:WaitForChild("DragonConfig"))
local S = DragonConfig.Settings
local Announce = ReplicatedStorage:WaitForChild("Announce")
local Notify = ReplicatedStorage:WaitForChild("Notify")

local gui = script.Parent
local announceLabel = gui:WaitForChild("Label")
local noticeLabel = gui:WaitForChild("Notice")

-- Состояние показа для каждой метки
local state = {}

local function show(label, text, color)
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
		st.tween = TweenService:Create(label, TweenInfo.new(S.AnnounceFadeTime), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		st.tween:Play()
	end)
end

Announce.OnClientEvent:Connect(function(playerName, dragonName, color)
	show(
		announceLabel,
		tostring(playerName) .. " получил " .. tostring(dragonName) .. "!",
		color
	)
end)

Notify.OnClientEvent:Connect(function(text, color)
	show(noticeLabel, tostring(text), color)
end)
