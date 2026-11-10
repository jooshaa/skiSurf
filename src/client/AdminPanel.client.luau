--!strict
-- AdminPanel: панель тестов. Показывается только тому, кого сервер пометил атрибутом IsAdmin.
-- Клиент лишь отправляет команды; права каждый раз проверяет сервер (Admin.luau).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config") :: ModuleScript) :: any
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
	Name = "AdminPanel",
	ResetOnSpawn = false,
	DisplayOrder = 20,
	Enabled = false,
}, playerGui)

local toggle = make("TextButton", {
	Name = "Toggle",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(56, 56),
	BackgroundColor3 = Color3.fromRGB(60, 60, 70),
	BorderSizePixel = 0,
	Text = "🛠",
	TextScaled = true,
	Font = Enum.Font.GothamBold,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, toggle)

local panel = make("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -76, 0.5, 0),
	Size = UDim2.fromOffset(300, 430),
	BackgroundColor3 = Color3.fromRGB(25, 25, 32),
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, panel)
make("UIPadding", {
	PaddingTop = UDim.new(0, 10),
	PaddingBottom = UDim.new(0, 10),
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
}, panel)
make("UIListLayout", {
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, panel)

local order = 0
local function row(height: number): Frame
	order += 1
	local frame = make("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, panel)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, frame)
	return frame
end

local function button(
	parent: Instance,
	text: string,
	widthScale: number,
	color: Color3?
): TextButton
	local created = make("TextButton", {
		Size = UDim2.new(widthScale, -6, 1, 0),
		BackgroundColor3 = color or Color3.fromRGB(60, 90, 160),
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 16,
		Font = Enum.Font.GothamBold,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, created)
	return created
end

local function send(action: string, a: any?, b: any?)
	Remotes.Get("AdminAction"):FireServer(action, a, b)
end

-- Монеты
local coinsRow = row(38)
for _, amount in { 1000, 100000 } do
	button(coinsRow, "💰 +" .. amount, 0.5).Activated:Connect(function()
		send("coins", amount)
	end)
end

-- Эльф любой редкости и мутации
local rarityIndex, mutationIndex = 1, 1
local elfRow = row(38)
local rarityButton = button(elfRow, "", 0.36, Color3.fromRGB(70, 70, 85))
local mutationButton = button(elfRow, "", 0.36, Color3.fromRGB(70, 70, 85))
local grantButton = button(elfRow, "🧝 +", 0.28, Color3.fromRGB(60, 150, 90))
local function refreshElf()
	rarityButton.Text = Config.Rarities[rarityIndex].name
	rarityButton.TextColor3 = Config.Rarities[rarityIndex].color
	mutationButton.Text = Config.Mutations[mutationIndex].name
	mutationButton.TextColor3 = Config.Mutations[mutationIndex].color
end
rarityButton.Activated:Connect(function()
	rarityIndex = rarityIndex % #Config.Rarities + 1
	refreshElf()
end)
mutationButton.Activated:Connect(function()
	mutationIndex = mutationIndex % #Config.Mutations + 1
	refreshElf()
end)
grantButton.Activated:Connect(function()
	send("elf", Config.Rarities[rarityIndex].name, Config.Mutations[mutationIndex].name)
end)
refreshElf()

-- Пролёт сейчас и сброс данных (сброс требует второго нажатия)
local actionRow = row(38)
button(actionRow, "🎅 пролёт", 0.5, Color3.fromRGB(180, 60, 60)).Activated:Connect(
	function()
		send("flyby")
	end
)
local resetButton = button(actionRow, "♻ сброс", 0.5, Color3.fromRGB(110, 110, 120))
local resetArmed = false
resetButton.Activated:Connect(function()
	if not resetArmed then
		resetArmed = true
		resetButton.Text = "♻ точно?"
		task.delay(3, function()
			resetArmed = false
			resetButton.Text = "♻ сброс"
		end)
		return
	end
	resetArmed = false
	resetButton.Text = "♻ сброс"
	send("reset")
end)

-- Проверка шансов: N открытий подарка, без выдачи эльфов
local openRow = row(38)
for _, sizeId in { "Small", "Medium", "Large" } do
	button(
		openRow,
		"🎲 " .. string.sub(sizeId, 1, 1) .. "×200",
		1 / 3,
		Color3.fromRGB(120, 80, 160)
	).Activated:Connect(function()
		send("open", sizeId, 200)
	end)
end

order += 1
local output = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 230),
	BackgroundColor3 = Color3.fromRGB(15, 15, 20),
	BorderSizePixel = 0,
	Text = "",
	TextColor3 = Color3.fromRGB(210, 220, 230),
	TextSize = 13,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Font = Enum.Font.Code,
	LayoutOrder = order,
}, panel)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, output)
make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingTop = UDim.new(0, 6) }, output)

Remotes.Get("AdminResult").OnClientEvent:Connect(function(ok: any, text: any)
	output.Text = (if ok == true then "✔ " else "✖ ") .. tostring(text)
end)

toggle.Activated:Connect(function()
	panel.Visible = not panel.Visible
end)

local function refreshAccess()
	gui.Enabled = player:GetAttribute("IsAdmin") == true
end
player:GetAttributeChangedSignal("IsAdmin"):Connect(refreshAccess)
refreshAccess()
