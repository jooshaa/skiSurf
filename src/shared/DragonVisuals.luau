-- DragonVisuals: модель дракона из простых Part, эффекты и табличка с именем
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DragonConfig = require(ReplicatedStorage:WaitForChild("DragonConfig"))

local DragonVisuals = {}

local function makePart(class, name, size, cframe, color, parent)
	local p = Instance.new(class)
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function resolve(element, rarity)
	if type(element) == "string" then
		element = DragonConfig.GetElement(element)
	end
	if type(rarity) == "string" then
		rarity = DragonConfig.GetRarity(rarity)
	end
	return element, rarity
end

-- Геометрия дракона (~4 студа), без эффектов. Дракон смотрит в -Z
function DragonVisuals.CreateDragon(element, rarity)
	element, rarity = resolve(element, rarity)
	if not element or not rarity then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = element.name .. " " .. rarity.name .. " Dragon"
	model:SetAttribute("Element", element.name)
	model:SetAttribute("Rarity", rarity.name)

	local color = element.color
	local dark = Color3.new(color.R * 0.6, color.G * 0.6, color.B * 0.6)

	-- Тело
	local body =
		makePart("Part", "Body", Vector3.new(1.6, 1.4, 2.6), CFrame.new(0, 0, 0), color, model)
	-- Голова
	makePart("Part", "Head", Vector3.new(1.2, 1.0, 1.2), CFrame.new(0, 0.6, -1.8), color, model)
	-- Глаза цвета редкости
	for _, x in ipairs({ -0.35, 0.35 }) do
		local eye = makePart(
			"Part",
			"Eye",
			Vector3.new(0.25, 0.25, 0.1),
			CFrame.new(x, 0.75, -2.4),
			rarity.color,
			model
		)
		eye.Material = Enum.Material.Neon
	end
	-- Крылья (клинья), приподняты вверх
	makePart(
		"WedgePart",
		"LeftWing",
		Vector3.new(0.2, 2.4, 1.8),
		CFrame.new(-1.9, 1.0, 0.2) * CFrame.Angles(0, 0, math.rad(70)),
		dark,
		model
	)
	makePart(
		"WedgePart",
		"RightWing",
		Vector3.new(0.2, 2.4, 1.8),
		CFrame.new(1.9, 1.0, 0.2) * CFrame.Angles(0, 0, math.rad(-70)),
		dark,
		model
	)
	-- Хвост (тонкий конец назад)
	makePart(
		"WedgePart",
		"Tail",
		Vector3.new(0.6, 0.6, 1.8),
		CFrame.new(0, -0.2, 2.1) * CFrame.Angles(0, math.rad(180), 0),
		color,
		model
	)

	model.PrimaryPart = body
	return model
end

-- Эффекты (вызываются на клиенте): свет редкости, искры для топ-редкостей
function DragonVisuals.ApplyEffects(model, rarity)
	local _, r = resolve(nil, rarity)
	local body = model:FindFirstChild("Body")
	if not r or not body or body:FindFirstChild("RarityLight") then
		return
	end

	local light = Instance.new("PointLight")
	light.Name = "RarityLight"
	light.Color = r.color
	light.Brightness = 1.5
	light.Range = 8
	light.Parent = body

	if r.announce then -- Legendary и Mythic
		local pe = Instance.new("ParticleEmitter")
		pe.Name = "Sparks"
		pe.Color = ColorSequence.new(r.color)
		pe.Size = NumberSequence.new(0.35, 0)
		pe.Lifetime = NumberRange.new(0.6, 1.2)
		pe.Rate = 20
		pe.Speed = NumberRange.new(2, 4)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.LightEmission = 1
		pe.Parent = body

		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = r.color
		sparkles.Parent = body
	end
end

-- Табличка над драконом: имя цветом редкости
function DragonVisuals.AddNameTag(model, rarity)
	local _, r = resolve(nil, rarity)
	local body = model:FindFirstChild("Body")
	if not r or not body then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Size = UDim2.new(0, 160, 0, 36)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 80
	gui.AlwaysOnTop = false
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = model.Name
	label.TextColor3 = r.color
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = gui
	gui.Parent = body
end

return DragonVisuals
