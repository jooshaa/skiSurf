--!strict
-- Diary: дневник коллекции. Сетка редкость x мутация, процент завершения, отметки наград
-- за каждые 10%. Данные читаются из атрибутов игрока (их пишет сервер). Без текста: значки и цвета.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config") :: ModuleScript) :: any
local Elves = require(ReplicatedStorage:WaitForChild("Elves") :: ModuleScript) :: any

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MUTATION_ICON: { [string]: string } = {
	None = "🧝",
	Frosty = "❄️",
	Candy = "🍬",
	Aurora = "🌈",
	Golden = "⭐",
}

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className) :: any
	for key, value in props do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local gui = make("ScreenGui", {
	Name = "Diary",
	ResetOnSpawn = false,
	DisplayOrder = 6,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

-- Кнопка дневника: слева, под счётчиком монет
local openButton = make("TextButton", {
	Name = "Open",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, 34),
	Size = UDim2.fromOffset(110, 56),
	BackgroundColor3 = Color3.fromRGB(20, 30, 50),
	BackgroundTransparency = 0.25,
	BorderSizePixel = 0,
	Text = "📖 0%",
	TextColor3 = Color3.new(1, 1, 1),
	TextScaled = true,
	Font = Enum.Font.GothamBold,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0.3, 0) }, openButton)
make("UIPadding", {
	PaddingTop = UDim.new(0.15, 0),
	PaddingBottom = UDim.new(0.15, 0),
	PaddingLeft = UDim.new(0.08, 0),
	PaddingRight = UDim.new(0.08, 0),
}, openButton)

local panel = make("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.7, 0.8),
	BackgroundColor3 = Color3.fromRGB(20, 30, 50),
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0.06, 0) }, panel)
make(
	"UISizeConstraint",
	{ MaxSize = Vector2.new(560, 620), MinSize = Vector2.new(280, 320) },
	panel
)
make("UIAspectRatioConstraint", { AspectRatio = 0.9 }, panel)

local closeButton = make("TextButton", {
	Name = "Close",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -8, 0, 8),
	Size = UDim2.fromScale(0.13, 0.11),
	BackgroundColor3 = Color3.fromRGB(200, 70, 70),
	BorderSizePixel = 0,
	Text = "✖",
	TextColor3 = Color3.new(1, 1, 1),
	TextScaled = true,
	Font = Enum.Font.GothamBold,
}, panel)
make("UICorner", { CornerRadius = UDim.new(0.3, 0) }, closeButton)

local title = make("TextLabel", {
	Position = UDim2.fromScale(0.05, 0.02),
	Size = UDim2.fromScale(0.75, 0.1),
	BackgroundTransparency = 1,
	Text = "📖 0%",
	TextColor3 = Color3.new(1, 1, 1),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextScaled = true,
	Font = Enum.Font.GothamBold,
}, panel)

-- Полоска завершения с отметками наград за каждую ступень
local progress = make("Frame", {
	Position = UDim2.fromScale(0.05, 0.14),
	Size = UDim2.fromScale(0.9, 0.05),
	BackgroundColor3 = Color3.fromRGB(50, 60, 85),
	BorderSizePixel = 0,
}, panel)
make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, progress)
local progressFill = make("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = Color3.fromRGB(70, 200, 110),
	BorderSizePixel = 0,
}, progress)
make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, progressFill)

local tiers = math.floor(100 / Config.Diary.TierPercent)
local tierMarks: { TextLabel } = {}
for index = 1, tiers do
	tierMarks[index] = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.05 + 0.9 * index / tiers, 0.195),
		Size = UDim2.fromScale(0.08, 0.05),
		BackgroundTransparency = 1,
		Text = "🎁",
		TextTransparency = 0.6,
		TextScaled = true,
		Font = Enum.Font.GothamBold,
	}, panel)
end

-- Сетка: строки = редкости, столбцы = мутации
local grid = make("Frame", {
	Position = UDim2.fromScale(0.05, 0.27),
	Size = UDim2.fromScale(0.9, 0.7),
	BackgroundTransparency = 1,
}, panel)
local columns = #Config.Mutations
local rows = #Config.Rarities
local cells: { [string]: TextLabel } = {}
for row, rarity in ipairs(Config.Rarities) do
	for column, mutation in ipairs(Config.Mutations) do
		local cell = make("TextLabel", {
			Position = UDim2.fromScale((column - 1) / columns + 0.01, (row - 1) / rows + 0.01),
			Size = UDim2.fromScale(1 / columns - 0.02, 1 / rows - 0.02),
			BackgroundColor3 = Color3.fromRGB(45, 55, 80),
			BorderSizePixel = 0,
			Text = "?",
			TextColor3 = Color3.fromRGB(120, 130, 150),
			TextScaled = true,
			Font = Enum.Font.GothamBold,
		}, grid)
		make("UICorner", { CornerRadius = UDim.new(0.2, 0) }, cell)
		make("UIPadding", {
			PaddingTop = UDim.new(0.2, 0),
			PaddingBottom = UDim.new(0.2, 0),
		}, cell)
		make("UIStroke", { Color = rarity.color, Thickness = 2, Transparency = 0.5 }, cell)
		cells[Elves.DiaryKey(rarity.name, mutation.name)] = cell
	end
end

local function refresh()
	local set, count = Elves.ParseDiary(player:GetAttribute("Diary"))
	local percent = math.floor(count / Elves.DiaryTotal() * 100 + 0.5)
	local text = string.format("📖 %d%%", percent)
	openButton.Text = text
	title.Text = text
	progressFill.Size = UDim2.fromScale(math.clamp(percent / 100, 0, 1), 1)
	local claimed = player:GetAttribute("DiaryTiers") or 0
	for index, mark in tierMarks do
		mark.TextTransparency = if index <= claimed then 0 else 0.6
	end
	for _, rarity in Config.Rarities do
		for _, mutation in Config.Mutations do
			local cell = cells[Elves.DiaryKey(rarity.name, mutation.name)]
			if set[Elves.DiaryKey(rarity.name, mutation.name)] then
				cell.Text = MUTATION_ICON[mutation.name] or "🧝"
				cell.BackgroundColor3 = rarity.color
				cell.BackgroundTransparency = 0.2
			else
				cell.Text = "?"
				cell.BackgroundColor3 = Color3.fromRGB(45, 55, 80)
				cell.BackgroundTransparency = 0
			end
		end
	end
end

openButton.Activated:Connect(function()
	panel.Visible = not panel.Visible
end)
closeButton.Activated:Connect(function()
	panel.Visible = false
end)
player:GetAttributeChangedSignal("Diary"):Connect(refresh)
player:GetAttributeChangedSignal("DiaryTiers"):Connect(refresh)
refresh()
