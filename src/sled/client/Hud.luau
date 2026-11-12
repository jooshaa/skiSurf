--!strict
-- Hud: экран прототипа без слов: время, полоска пути, полоска скорости, руль, кнопка тормоза,
-- лампочки отсчёта. Плюс панель настройки (шестерёнка): три характера санок и ползунки.
-- Панель с подписями: это инструмент разработчика, в игру она не пойдёт.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local SledConfig = require(ReplicatedStorage.SledConfig)

local H = SledConfig.Hud

local WHITE = Color3.new(1, 1, 1)
local DARK = Color3.fromRGB(20, 26, 40)
local ACCENT = Color3.fromRGB(70, 140, 255)
local RED = Color3.fromRGB(235, 60, 60)
local GREEN = Color3.fromRGB(70, 210, 120)

local Hud = {}

local gui: ScreenGui
local timeLabel: TextLabel
local resultLabel: TextLabel
local progressDot: Frame
local speedFill: Frame
local steerKnob: Frame
local brakeButton: Frame
local lights: { Frame } = {}
local lightRow: Frame
local shownTenths = -1 -- время на экране меняется 10 раз в секунду, а не каждый кадр

local rankLabel: TextLabel
local itemSlot: Frame
local itemIcon: TextLabel
local itemUseBtn: TextButton
local onItemUse: (() -> ())? = nil

local function round(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = instance
end

local function frame(
	parent: Instance,
	size: UDim2,
	position: UDim2,
	color: Color3,
	transparency: number
): Frame
	local item = Instance.new("Frame")
	item.Size = size
	item.Position = position
	item.BackgroundColor3 = color
	item.BackgroundTransparency = transparency
	item.BorderSizePixel = 0
	item.Parent = parent
	return item
end

local function label(parent: Instance, size: UDim2, position: UDim2): TextLabel
	local item = Instance.new("TextLabel")
	item.Size = size
	item.Position = position
	item.AnchorPoint = Vector2.new(0.5, 0)
	item.BackgroundTransparency = 1
	item.Font = Enum.Font.GothamBold
	item.TextScaled = true
	item.TextColor3 = WHITE
	item.TextStrokeTransparency = 0.4
	item.Text = ""
	item.Parent = parent
	return item
end

local function formatTime(seconds: number): string
	return string.format("%d:%04.1f", math.floor(seconds / 60), seconds % 60)
end

function Hud.Create()
	gui = Instance.new("ScreenGui")
	gui.Name = "SledHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	timeLabel = label(gui, UDim2.fromScale(0.22, 0.07), UDim2.fromScale(0.5, 0.045))
	resultLabel = label(gui, UDim2.fromScale(0.5, 0.2), UDim2.fromScale(0.5, 0.3))
	resultLabel.Visible = false

	local progress =
		frame(gui, UDim2.fromScale(0.5, 0.008), UDim2.fromScale(0.25, 0.025), WHITE, 0.6)
	round(progress, 1)
	progressDot = frame(progress, UDim2.fromScale(0.03, 3), UDim2.fromScale(0, -1), ACCENT, 0)
	progressDot.AnchorPoint = Vector2.new(0.5, 0)
	round(progressDot, 1)

	local speed = frame(gui, UDim2.fromScale(0.24, 0.022), UDim2.fromScale(0.38, 0.94), DARK, 0.5)
	round(speed, 1)
	speedFill = frame(speed, UDim2.fromScale(0, 1), UDim2.fromScale(0, 0), ACCENT, 0)
	round(speedFill, 1)

	local steer =
		frame(gui, UDim2.fromScale(H.SteerBar, 0.03), UDim2.fromScale(0.05, 0.86), DARK, 0.5)
	round(steer, 1)
	steerKnob = frame(steer, UDim2.fromScale(0.12, 2.2), UDim2.fromScale(0.5, -0.6), WHITE, 0)
	steerKnob.AnchorPoint = Vector2.new(0.5, 0)
	round(steerKnob, 1)

	-- Кнопка тормоза крупная: детские пальцы и панические нажатия. Сама она нажатия не ловит:
	-- тормозит касание в любом месте правой половины экрана, кнопка только показывает, куда жать.
	brakeButton = frame(
		gui,
		UDim2.fromScale(H.BrakeButton, H.BrakeButton),
		UDim2.fromScale(0.96, 0.92),
		RED,
		0.35
	)
	brakeButton.SizeConstraint = Enum.SizeConstraint.RelativeYY
	brakeButton.AnchorPoint = Vector2.new(1, 1)
	round(brakeButton, 0.5)
	local stop =
		frame(brakeButton, UDim2.fromScale(0.36, 0.36), UDim2.fromScale(0.32, 0.32), WHITE, 0)
	round(stop, 0.2)

	lightRow = frame(gui, UDim2.fromScale(0.3, 0.12), UDim2.fromScale(0.35, 0.3), DARK, 1)
	local total = SledConfig.Run.CountdownLights
	for index = 1, total do
		local light = frame(
			lightRow,
			UDim2.fromScale(0.8, 0.8),
			UDim2.fromScale((index - 0.5) / total, 0.1),
			DARK,
			0.3
		)
		light.SizeConstraint = Enum.SizeConstraint.RelativeYY
		light.AnchorPoint = Vector2.new(0.5, 0)
		round(light, 0.5)
		lights[index] = light
	end

	-- Позиция в гонке (1ST, 2ND, 3RD, 4TH) в левом верхнем углу
	rankLabel = label(gui, UDim2.fromScale(0.18, 0.08), UDim2.fromScale(0.025, 0.11))
	rankLabel.AnchorPoint = Vector2.new(0, 0)
	rankLabel.TextXAlignment = Enum.TextXAlignment.Left
	rankLabel.Font = Enum.Font.FredokaOne
	rankLabel.Text = "1ST"
	rankLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	rankLabel.TextStrokeColor3 = Color3.fromRGB(20, 24, 34)
	rankLabel.TextStrokeTransparency = 0.3

	-- Слот предмета (справа над кнопкой тормоза, как в Mario Kart / BB Racing)
	itemSlot = frame(
		gui,
		UDim2.fromScale(0.18, 0.18),
		UDim2.fromScale(0.96, 0.63),
		Color3.fromRGB(30, 36, 52),
		0.25
	)
	itemSlot.SizeConstraint = Enum.SizeConstraint.RelativeYY
	itemSlot.AnchorPoint = Vector2.new(1, 1)
	round(itemSlot, 0.5)

	-- Обводка слота
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(255, 205, 50)
	stroke.Transparency = 0.2
	stroke.Parent = itemSlot

	-- Иконка предмета внутри слота
	itemIcon = Instance.new("TextLabel")
	itemIcon.Size = UDim2.fromScale(0.85, 0.85)
	itemIcon.Position = UDim2.fromScale(0.5, 0.5)
	itemIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	itemIcon.BackgroundTransparency = 1
	itemIcon.Font = Enum.Font.FredokaOne
	itemIcon.TextScaled = true
	itemIcon.TextColor3 = WHITE
	itemIcon.Text = ""
	itemIcon.Parent = itemSlot

	-- Кнопка активации для тачскрина / клика
	itemUseBtn = Instance.new("TextButton")
	itemUseBtn.Size = UDim2.fromScale(1, 1)
	itemUseBtn.BackgroundTransparency = 1
	itemUseBtn.Text = ""
	itemUseBtn.Parent = itemSlot
	itemUseBtn.Activated:Connect(function()
		if onItemUse then
			onItemUse()
		end
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- Обновление слота предмета (рулетка, иконка, готовность)
function Hud.SetPowerup(kind: string?, isRoulette: boolean, onUse: (() -> ())?)
	onItemUse = onUse
	if not itemSlot or not itemIcon then
		return
	end

	if not kind then
		itemSlot.Visible = false
		itemIcon.Text = ""
		return
	end

	itemSlot.Visible = true
	if isRoulette then
		itemIcon.Text = "❓"
		itemIcon.TextColor3 = Color3.fromRGB(255, 230, 80)
	else
		if kind == "Rocket" then
			itemIcon.Text = "🚀"
		elseif kind == "Fireworks" then
			itemIcon.Text = "🎆"
		elseif kind == "Boost" then
			itemIcon.Text = "⚡"
		elseif kind == "Shield" then
			itemIcon.Text = "🛡️"
		else
			itemIcon.Text = "?"
		end
	end
end

-- Позиция в гонке
function Hud.SetRank(rank: number, _total: number)
	if not rankLabel then
		return
	end
	local suffixes = { [1] = "1ST", [2] = "2ND", [3] = "3RD", [4] = "4TH" }
	local colors = {
		[1] = Color3.fromRGB(255, 215, 0), -- Золото
		[2] = Color3.fromRGB(215, 225, 240), -- Серебро
		[3] = Color3.fromRGB(205, 130, 60), -- Бронза
		[4] = Color3.fromRGB(150, 160, 180),
	}
	rankLabel.Text = suffixes[rank] or string.format("%dTH", rank)
	rankLabel.TextColor3 = colors[rank] or Color3.fromRGB(180, 190, 210)
end

function Hud.Update(speed: number, steer: number, brake: boolean, progress: number, time: number)
	local tenths = math.floor(time * 10)
	if tenths ~= shownTenths then
		shownTenths = tenths
		timeLabel.Text = formatTime(time)
	end
	progressDot.Position = UDim2.fromScale(math.clamp(progress, 0, 1), -1)
	speedFill.Size = UDim2.fromScale(math.clamp(speed / H.SpeedMax, 0, 1), 1)
	steerKnob.Position = UDim2.fromScale(0.5 + steer * 0.44, -0.6)
	brakeButton.BackgroundTransparency = if brake then 0 else 0.35
end

-- lit = сколько лампочек горит; nil прячет отсчёт
function Hud.Countdown(lit: number?)
	lightRow.Visible = lit ~= nil
	if lit then
		for index, light in lights do
			light.BackgroundColor3 = if index <= lit then GREEN else DARK
			light.BackgroundTransparency = if index <= lit then 0 else 0.3
		end
	end
end

-- Время заезда и лучшее время; nil прячет результат
function Hud.Result(time: number?, best: number?)
	resultLabel.Visible = time ~= nil
	if time and best then
		resultLabel.Text = formatTime(time) .. "\n★ " .. formatTime(best)
	end
end

-- Панель настройки. params меняется на месте; onPreset(номер) и onRestart вызывает главный скрипт.
function Hud.Tuning(
	params: { [string]: number },
	onPreset: (index: number) -> (),
	onRestart: () -> ()
)
	local function button(parent: Instance, text: string, size: UDim2, position: UDim2): TextButton
		local item = Instance.new("TextButton")
		item.Size = size
		item.Position = position
		item.BackgroundColor3 = DARK
		item.BackgroundTransparency = 0.25
		item.BorderSizePixel = 0
		item.Font = Enum.Font.GothamBold
		item.TextSize = 16
		item.TextColor3 = WHITE
		item.Text = text
		item.AutoButtonColor = true
		item.Parent = parent
		round(item, 0.2)
		return item
	end

	local rowHeight = 30
	local rows = #SledConfig.Tunable
	local gear = button(gui, "⚙", UDim2.fromOffset(40, 40), UDim2.fromOffset(12, 48))
	local panel = frame(
		gui,
		UDim2.fromOffset(250, 52 + rows * rowHeight),
		UDim2.fromOffset(12, 94),
		DARK,
		0.35
	)
	panel.Visible = false
	panel.Active = true -- нажатия по панели не должны рулить санками
	gear.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)

	local refresh: { () -> () } = {}
	for index, preset in SledConfig.Presets do
		local item = button(
			panel,
			tostring(index),
			UDim2.fromOffset(52, 36),
			UDim2.fromOffset(8 + (index - 1) * 58, 8)
		)
		item.Name = preset.id
		item.Activated:Connect(function()
			onPreset(index)
			for _, update in refresh do
				update()
			end
		end)
	end
	button(panel, "↺", UDim2.fromOffset(52, 36), UDim2.fromOffset(190, 8)).Activated:Connect(
		onRestart
	)

	local dragging: ((number) -> ())? = nil
	local dragInput: InputObject? = nil -- ползунок слушает только тот палец, который его взял
	for index, tunable in SledConfig.Tunable do
		local bar = button(
			panel,
			"",
			UDim2.fromOffset(234, rowHeight - 6),
			UDim2.fromOffset(8, 50 + (index - 1) * rowHeight)
		)
		bar.AutoButtonColor = false
		bar.TextXAlignment = Enum.TextXAlignment.Left
		bar.TextSize = 13
		local fill = frame(bar, UDim2.fromScale(0, 1), UDim2.fromScale(0, 0), ACCENT, 0.45)
		round(fill, 0.2)

		local function update()
			local value = params[tunable.key]
			local share = (value - tunable.min) / (tunable.max - tunable.min)
			fill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
			bar.Text = string.format("  %s  %.4g", tunable.key, value)
		end
		local function setFromX(x: number)
			local share = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
			params[tunable.key] = tunable.min + (tunable.max - tunable.min) * share
			update()
		end
		bar.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging = setFromX
				dragInput = input
				setFromX(input.Position.X)
			end
		end)
		table.insert(refresh, update)
		update()
	end

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if
			dragging
			and (input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput)
		then
			dragging(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input == dragInput then
			dragging = nil
			dragInput = nil
		end
	end)
end

return Hud
