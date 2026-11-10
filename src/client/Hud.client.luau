--!strict
-- Hud: полоска нормы, таймер, монеты и кнопки переноски. Без текста: только значки и числа
-- (CLAUDE.md, красная линия 6), крупные кнопки под один палец.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes") :: ModuleScript) :: any

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className) :: any
	for key, value in props do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local gui = make("ScreenGui", {
	Name = "Hud",
	ResetOnSpawn = false,
	DisplayOrder = 5,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local function panel(name: string, position: UDim2, size: UDim2, anchor: Vector2): Frame
	local frame = make("Frame", {
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = size,
		BackgroundColor3 = Color3.fromRGB(20, 30, 50),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, frame)
	return frame
end

local function label(parent: Instance, text: string): TextLabel
	return make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.5,
		TextScaled = true,
		Font = Enum.Font.GothamBold,
		ZIndex = 3,
	}, parent)
end

-- Норма: полоска и счёт
local quota = panel("Quota", UDim2.new(0.5, 0, 0, 8), UDim2.new(0.4, 0, 0, 36), Vector2.new(0.5, 0))
make("UISizeConstraint", { MaxSize = Vector2.new(420, 36), MinSize = Vector2.new(180, 36) }, quota)
local quotaFill = make("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = Color3.fromRGB(70, 200, 110),
	BorderSizePixel = 0,
	ZIndex = 2,
}, quota)
make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, quotaFill)
local quotaLabel = label(quota, "🎁 0/0")

-- Таймер отлёта
local timer =
	panel("Timer", UDim2.new(0.5, 0, 0, 50), UDim2.fromOffset(110, 30), Vector2.new(0.5, 0))
local timerLabel = label(timer, "")
timer.Visible = false

-- Монеты и доход в секунду
local coinsPanel =
	panel("Coins", UDim2.new(0, 12, 0.5, -60), UDim2.fromOffset(150, 34), Vector2.new(0, 0.5))
local coinsLabel = label(coinsPanel, "💰 0")
local incomePanel =
	panel("Income", UDim2.new(0, 12, 0.5, -22), UDim2.fromOffset(110, 26), Vector2.new(0, 0.5))
local incomeLabel = label(incomePanel, "+0/s")

local function roundButton(name: string, text: string, position: UDim2, color: Color3): TextButton
	local button = make("TextButton", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = position,
		Size = UDim2.fromOffset(84, 84),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Text = text,
		TextScaled = true,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = true,
		Visible = false,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, button)
	make("UIPadding", {
		PaddingTop = UDim.new(0.18, 0),
		PaddingBottom = UDim.new(0.18, 0),
		PaddingLeft = UDim.new(0.18, 0),
		PaddingRight = UDim.new(0.18, 0),
	}, button)
	return button
end

-- Кнопки переноски: отпустить и позвать на помощь
local dropButton =
	roundButton("Drop", "⬇️🎁", UDim2.new(0.5, 0, 1, -110), Color3.fromRGB(200, 70, 70))
local helpButton =
	roundButton("Help", "🙋", UDim2.new(0.5, 100, 1, -110), Color3.fromRGB(240, 170, 40))

dropButton.Activated:Connect(function()
	Remotes.Get("DropGift"):FireServer()
end)
helpButton.Activated:Connect(function()
	Remotes.Get("CallHelp"):FireServer()
end)

local function formatNumber(value: number): string
	if value >= 1e9 then
		return string.format("%.1fB", value / 1e9)
	elseif value >= 1e6 then
		return string.format("%.1fM", value / 1e6)
	elseif value >= 1e4 then
		return string.format("%.1fK", value / 1e3)
	end
	return tostring(math.floor(value))
end

local function updateCarry()
	local carryingSize = player:GetAttribute("Carrying")
	dropButton.Visible = carryingSize ~= nil
	-- Звать на помощь можно, только пока подарок ждёт остальных несущих
	helpButton.Visible = carryingSize ~= nil and player:GetAttribute("CarryWaiting") == true
end
player:GetAttributeChangedSignal("Carrying"):Connect(updateCarry)
player:GetAttributeChangedSignal("CarryWaiting"):Connect(updateCarry)
updateCarry()

local function updateIncome()
	local income = player:GetAttribute("IncomePerSecond") or 0
	incomeLabel.Text = string.format(
		"+%s/s",
		if income % 1 == 0 then formatNumber(income) else string.format("%.1f", income)
	)
end
player:GetAttributeChangedSignal("IncomePerSecond"):Connect(updateIncome)
updateIncome()

task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats")
	local coins = leaderstats:WaitForChild("Coins") :: IntValue
	local function updateCoins()
		coinsLabel.Text = "💰 " .. formatNumber(coins.Value)
	end
	coins.Changed:Connect(updateCoins)
	updateCoins()
end)

-- Состояние пролёта приходит с сервера через RemoteEvent
local state = { phase = "Active", delivered = 0, target = 0, endsAt = 0 }

local function updateQuota()
	local target = math.max(1, state.target)
	quotaLabel.Text = string.format("🎁 %d/%d", state.delivered, state.target)
	quotaFill.Size = UDim2.fromScale(math.clamp(state.delivered / target, 0, 1), 1)
	quotaFill.BackgroundColor3 = if state.delivered >= target
		then Color3.fromRGB(255, 200, 60)
		else Color3.fromRGB(70, 200, 110)
end

Remotes.Get("RoundState").OnClientEvent:Connect(function(newState: any)
	if type(newState) ~= "table" then
		return
	end
	state.phase = tostring(newState.phase)
	state.delivered = tonumber(newState.delivered) or 0
	state.target = tonumber(newState.target) or 0
	state.endsAt = tonumber(newState.endsAt) or 0
	updateQuota()
end)
updateQuota()

-- Первая минута: полоска нормы и таймер появляются после первого эльфа (CLAUDE.md, раздел 6)
local function inTutorial(): boolean
	local stage = player:GetAttribute("TutorialStage")
	return stage == 1 or stage == 2
end
local function updateTutorial()
	quota.Visible = not inTutorial()
end
player:GetAttributeChangedSignal("TutorialStage"):Connect(updateTutorial)
updateTutorial()

-- Таймер считаем локально от серверного времени, раз в четверть секунды
local accumulated = 0
RunService.Heartbeat:Connect(function(deltaTime)
	accumulated += deltaTime
	if accumulated < 0.25 then
		return
	end
	accumulated = 0
	if state.endsAt <= 0 or inTutorial() then
		timer.Visible = false
		return
	end
	local left = math.max(0, state.endsAt - Workspace:GetServerTimeNow())
	timer.Visible = true
	local icon = if state.phase == "Announce" then "🎅" else "⏱"
	timerLabel.Text =
		string.format("%s %d:%02d", icon, math.floor(left / 60), math.floor(left % 60))
end)
