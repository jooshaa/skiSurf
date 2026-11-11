--!strict
-- RoundFx: спектакль пролёта на клиенте. Санта летит по дуге, сани улетают при отлёте,
-- затем показываются итоги: сколько подарков открыто, монеты, эльфы.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config") :: ModuleScript) :: any
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes") :: ModuleScript) :: any

local R = Config.Round

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

-- Летящий Санта: свои простые формы (CLAUDE.md, красная линия 5)
local function buildSanta(): Model
	local model = Instance.new("Model")
	model.Name = "FlyingSanta"
	local function part(
		name: string,
		size: Vector3,
		offset: Vector3,
		color: Color3,
		shape: Enum.PartType?
	): Part
		local piece = make("Part", {
			Name = name,
			Size = size,
			CFrame = CFrame.new(offset),
			Color = color,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Material = Enum.Material.SmoothPlastic,
		}, model)
		if shape then
			piece.Shape = shape
		end
		return piece
	end
	local red = Color3.fromRGB(200, 40, 45)
	local body = part("Sleigh", Vector3.new(10, 4, 18), Vector3.new(0, 0, 0), red)
	-- Сани: 3D-модель, загруженная сервером; если её нет, простые детали
	local meshes = ReplicatedStorage:FindFirstChild(Config.Map.AssetFolder)
	local template = meshes and meshes:FindFirstChild("Sleigh")
	if template and template:IsA("MeshPart") then
		local sleigh = template:Clone()
		sleigh.Size *= Config.Map.FlyingSleighScale
		sleigh.CFrame = CFrame.new(0, sleigh.Size.Y / 2 - 3, 0)
			* CFrame.Angles(0, math.rad(Config.Map.Assets.Sleigh.yaw), 0)
		sleigh.Anchored = true
		sleigh.CanCollide = false
		sleigh.CanQuery = false
		sleigh.CanTouch = false
		sleigh.Parent = model
		body.Transparency = 1
	else
		part(
			"Runners",
			Vector3.new(12, 1, 22),
			Vector3.new(0, -2.5, 0),
			Color3.fromRGB(240, 190, 60)
		)
		part(
			"Sack",
			Vector3.new(8, 8, 8),
			Vector3.new(0, 5, 4),
			Color3.fromRGB(150, 110, 70),
			Enum.PartType.Ball
		)
	end
	part("Santa", Vector3.new(4, 5, 4), Vector3.new(0, 4.5, -4), red)
	part(
		"Head",
		Vector3.new(3.4, 3.4, 3.4),
		Vector3.new(0, 8.5, -4),
		Color3.fromRGB(255, 214, 170),
		Enum.PartType.Ball
	)
	part("Hat", Vector3.new(3, 2, 3), Vector3.new(0, 10.6, -4), red)
	for index = 1, 2 do
		part(
			"Deer" .. index,
			Vector3.new(3, 4, 7),
			Vector3.new(0, 0, -16 - index * 10),
			Color3.fromRGB(140, 95, 60)
		)
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 160)
	light.Range = 60
	light.Brightness = 3
	light.Parent = body
	model.PrimaryPart = body
	return model
end

-- Санта летит по дуге от from к to, время берём серверное
Remotes.Get("SantaFlyby").OnClientEvent
	:Connect(function(from: any, to: any, startTime: any, duration: any)
		if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
			return
		end
		if type(startTime) ~= "number" or type(duration) ~= "number" or duration <= 0 then
			return
		end
		local santa = buildSanta()
		santa.Parent = Workspace
		local connection: RBXScriptConnection
		connection = RunService.RenderStepped:Connect(function()
			local alpha = (Workspace:GetServerTimeNow() - startTime) / duration
			if alpha >= 1 or not santa.Parent then
				connection:Disconnect()
				santa:Destroy()
				return
			end
			alpha = math.max(alpha, 0)
			local position = from:Lerp(to, alpha)
				+ Vector3.new(0, math.sin(alpha * math.pi) * R.FlybyArcHeight, 0)
			santa:PivotTo(CFrame.lookAt(position, position + (to - from)))
		end)
	end)

-- Отлёт саней с площади: 3 секунды вверх и вперёд, затем сани возвращаются на место
local departing = false
local function playDeparture()
	local world = Workspace:FindFirstChild("World")
	local sleigh = world and world:FindFirstChild("Sleigh")
	if departing or not sleigh or not sleigh:IsA("Model") then
		return
	end
	departing = true
	local home = sleigh:GetPivot()
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.clamp((os.clock() - started) / R.DepartAnimTime, 0, 1)
		local eased = alpha * alpha
		sleigh:PivotTo(home * CFrame.new(0, eased * R.DepartRise, -eased * R.DepartRun))
		if alpha >= 1 then
			connection:Disconnect()
			task.delay(R.DepartReturnDelay, function()
				sleigh:PivotTo(home)
				departing = false
			end)
		end
	end)
end

-- Итоги: значки и числа, без текста
local resultGui =
	make("ScreenGui", { Name = "RoundResult", ResetOnSpawn = false, DisplayOrder = 8 }, playerGui)
local resultPanel = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.42),
	Size = UDim2.fromScale(0.6, 0.34),
	BackgroundColor3 = Color3.fromRGB(20, 30, 50),
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	Visible = false,
}, resultGui)
make("UICorner", { CornerRadius = UDim.new(0.12, 0) }, resultPanel)
make(
	"UISizeConstraint",
	{ MaxSize = Vector2.new(520, 300), MinSize = Vector2.new(260, 170) },
	resultPanel
)
local resultTitle = make("TextLabel", {
	Position = UDim2.fromScale(0.05, 0.05),
	Size = UDim2.fromScale(0.9, 0.3),
	BackgroundTransparency = 1,
	TextColor3 = Color3.new(1, 1, 1),
	TextScaled = true,
	Font = Enum.Font.GothamBold,
}, resultPanel)
local resultCoins = make("TextLabel", {
	Position = UDim2.fromScale(0.05, 0.36),
	Size = UDim2.fromScale(0.9, 0.22),
	BackgroundTransparency = 1,
	TextColor3 = Color3.fromRGB(255, 220, 90),
	TextScaled = true,
	Font = Enum.Font.GothamBold,
}, resultPanel)
local resultElves = make("Frame", {
	Position = UDim2.fromScale(0.05, 0.62),
	Size = UDim2.fromScale(0.9, 0.32),
	BackgroundTransparency = 1,
}, resultPanel)
make("UIGridLayout", {
	CellSize = UDim2.fromScale(0.3, 0.45),
	CellPadding = UDim2.fromScale(0.03, 0.08),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, resultElves)

local resultToken = 0
local function showResult(result: any)
	if type(result) ~= "table" then
		return
	end
	resultToken += 1
	local token = resultToken
	local star = if result.quotaMet == true then " ⭐" else ""
	resultTitle.Text = string.format(
		"🎁 ×%d   %d/%d%s",
		tonumber(result.gifts) or 0,
		tonumber(result.delivered) or 0,
		tonumber(result.target) or 0,
		star
	)
	resultCoins.Text = string.format("💰 +%d", tonumber(result.coins) or 0)
	for _, child in resultElves:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	if type(result.elves) == "table" then
		for index, elf in ipairs(result.elves) do
			if index > 6 or type(elf) ~= "table" then
				break
			end
			make("TextLabel", {
				BackgroundTransparency = 1,
				Text = tostring(elf.name),
				TextColor3 = if typeof(elf.color) == "Color3"
					then elf.color
					else Color3.new(1, 1, 1),
				TextStrokeTransparency = 0.4,
				TextScaled = true,
				Font = Enum.Font.GothamBold,
			}, resultElves)
		end
	end
	resultPanel.Visible = true
	resultPanel.Size = UDim2.fromScale(0.3, 0.17)
	TweenService:Create(
		resultPanel,
		TweenInfo.new(0.35, Enum.EasingStyle.Back),
		{ Size = UDim2.fromScale(0.6, 0.34) }
	):Play()
	task.delay(R.ResultShowTime, function()
		if resultToken == token then
			resultPanel.Visible = false
		end
	end)
end

Remotes.Get("RoundResult").OnClientEvent:Connect(showResult)

-- Отдельный remote: RoundState слушает только Hud, иначе первое состояние достаётся не тому скрипту
Remotes.Get("SleighDepart").OnClientEvent:Connect(playDeparture)
