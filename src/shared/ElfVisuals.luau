--!strict
-- ElfVisuals: модель эльфа из простых Part, эффекты и табличка с именем.
-- Свой стиль (CLAUDE.md, красная линия 5): крупная голова, колпак цвета редкости.
local Config = require(script.Parent.Config)
local Elves = require(script.Parent.Elves)

type Rarity = Config.Rarity

local ElfVisuals = {}

local TUNIC = Color3.fromRGB(40, 140, 70)
local SKIN = Color3.fromRGB(255, 214, 170)
local BOOTS = Color3.fromRGB(70, 45, 30)

-- Частицы мутаций (визуал, рисует клиент). Цвет берётся из Config.Mutations
local MUTATION_FX: { [string]: { rate: number, speed: number, drift: number, size: number, glow: number } } =
	{
		Frosty = { rate = 8, speed = 1.5, drift = -2, size = 0.3, glow = 0.3 }, -- снежинки падают
		Candy = { rate = 10, speed = 2.5, drift = 1, size = 0.35, glow = 0.2 }, -- конфетти
		Aurora = { rate = 14, speed = 1, drift = 3, size = 0.6, glow = 1 }, -- сияние поднимается
		Golden = { rate = 20, speed = 3, drift = 0, size = 0.4, glow = 1 }, -- золотые искры
	}

local function makePart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function resolveRarity(rarity: any): Rarity?
	if type(rarity) == "string" then
		return Elves.GetRarity(rarity)
	end
	return rarity
end

-- Геометрия эльфа (~3,5 студа), без эффектов. Смотрит в -Z, пивот в центре тела, ступни на -1,5
function ElfVisuals.CreateElf(rarityName: any, mutationName: any): Model?
	local rarity = Elves.GetRarity(rarityName)
	local mutation = Elves.GetMutation(mutationName or "None")
	if not rarity or not mutation then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = Elves.ElfName(rarity.name, mutation.name)
	model:SetAttribute("Rarity", rarity.name)
	model:SetAttribute("Mutation", mutation.name)

	local tunic = if mutation.name == "None" then TUNIC else mutation.color

	local body = makePart("Body", Vector3.new(1.4, 1.4, 0.9), CFrame.new(0, 0, 0), tunic, model)
	makePart("Head", Vector3.new(1.5, 1.4, 1.4), CFrame.new(0, 1.4, 0), SKIN, model)
	for _, x in { -0.35, 0.35 } do
		local eye = makePart(
			"Eye",
			Vector3.new(0.25, 0.3, 0.1),
			CFrame.new(x, 1.5, -0.72),
			rarity.color,
			model
		)
		eye.Material = Enum.Material.Neon
		makePart("Leg", Vector3.new(0.5, 0.8, 0.6), CFrame.new(x, -1.1, 0), BOOTS, model)
	end
	-- Колпак цвета редкости: поля, верх и помпон
	makePart(
		"HatBrim",
		Vector3.new(1.7, 0.3, 1.6),
		CFrame.new(0, 2.25, 0),
		Color3.new(1, 1, 1),
		model
	)
	makePart("HatTop", Vector3.new(1.1, 0.9, 1.1), CFrame.new(0, 2.85, 0), rarity.color, model)
	local pom = makePart(
		"HatPom",
		Vector3.new(0.5, 0.5, 0.5),
		CFrame.new(0, 3.5, 0),
		Color3.new(1, 1, 1),
		model
	)
	pom.Shape = Enum.PartType.Ball

	model.PrimaryPart = body
	return model
end

-- Эффекты (вызываются на клиенте): свет редкости, искры для топ-редкостей
function ElfVisuals.ApplyEffects(model: Model, rarityName: any, mutationName: any)
	local rarity = resolveRarity(rarityName)
	local body = model:FindFirstChild("Body")
	if not rarity or not body or body:FindFirstChild("RarityLight") then
		return
	end

	local light = Instance.new("PointLight")
	light.Name = "RarityLight"
	light.Color = rarity.color
	light.Brightness = 1.5
	light.Range = 8
	light.Parent = body

	if rarity.announce then -- Legendary и Mythic
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Sparks"
		emitter.Color = ColorSequence.new(rarity.color)
		emitter.Size = NumberSequence.new(0.35, 0)
		emitter.Lifetime = NumberRange.new(0.6, 1.2)
		emitter.Rate = 12
		emitter.Speed = NumberRange.new(2, 4)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.LightEmission = 1
		emitter.Parent = body
	end

	-- Мутация: свои частицы поверх редкости
	local mutation = Elves.GetMutation(mutationName)
	local fx = mutation and MUTATION_FX[mutation.name]
	if mutation and fx then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "MutationFx"
		emitter.Color = ColorSequence.new(mutation.color)
		emitter.Size = NumberSequence.new(fx.size, 0)
		emitter.Lifetime = NumberRange.new(1, 1.8)
		emitter.Rate = fx.rate
		emitter.Speed = NumberRange.new(fx.speed * 0.5, fx.speed)
		emitter.Acceleration = Vector3.new(0, fx.drift, 0)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.LightEmission = fx.glow
		emitter.Parent = body
		light.Color = mutation.color
	end
end

-- Табличка над эльфом: имя цветом редкости
function ElfVisuals.AddNameTag(model: Model, rarityName: any)
	local rarity = resolveRarity(rarityName)
	local body = model:FindFirstChild("Body")
	if not rarity or not body then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Size = UDim2.fromOffset(110, 20)
	gui.StudsOffset = Vector3.new(0, 4.4, 0)
	gui.MaxDistance = 40
	gui.AlwaysOnTop = false
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = model.Name
	label.TextColor3 = rarity.color
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = gui
	gui.Parent = body
end

return ElfVisuals
