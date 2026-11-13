--!strict
-- PowerupEffects: 3D-модели и анимации подарков «?», ракет с самонаведением и прицелом,
-- веерного салюта по дуге, двойных нитро-турбин и орбитального кристального щита (в стиле Beach Buggy Racing).
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Powerups = require(ReplicatedStorage.Powerups)
local SledConfig = require(ReplicatedStorage.SledConfig)
local Track = require(ReplicatedStorage.Track)

local P = SledConfig.Powerups

export type RocketProjectile = {
	id: number,
	ownerId: string,
	s: number,
	d: number,
	speed: number,
	targetSledId: string?,
	distanceTraveled: number,
	age: number,
	rollAngle: number,
	bankAngle: number,
	model: Model,
	flameCone: BasePart,
}

export type FireworkProjectile = {
	id: number,
	ownerId: string,
	pos: Vector3,
	vel3D: Vector3,
	speed: number,
	distanceTraveled: number,
	age: number,
	rollAngle: number,
	colorIndex: number,
	model: Model,
}

export type SnowballProjectile = {
	id: number,
	ownerId: string,
	s: number,
	d: number,
	crossVelocity: number,
	downhillSpeed: number,
	age: number,
	maxDuration: number,
	rollAngle: number,
	radius: number,
	model: Model,
}

export type ShieldVisual = {
	model: Model,
	dome: BasePart,
	crystals: { BasePart },
	ringA: BasePart,
	ringB: BasePart,
}

export type BoostVisual = {
	model: Model,
	flameL: BasePart,
	flameR: BasePart,
	trails: { Trail },
	emitters: { ParticleEmitter },
}

local PowerupEffects = {}

local boxFolder: Folder
local fxFolder: Folder
local boxVisuals: {
	[number]: {
		model: Model,
		root: Part,
		halo: Part,
		groundDisc: Part,
		billboard: BillboardGui,
		particles: ParticleEmitter,
		origPos: Vector3,
		scaleFactor: number,
	},
} =
	{}

local activeRockets: { RocketProjectile } = {}
local activeFireworks: { FireworkProjectile } = {}
local activeSnowballs: { SnowballProjectile } = {}
local nextProjId = 1

local lockOnModel: Model? = nil
local heldModel: Model? = nil
local heldKind: string? = nil

local GIFT_COLORS = {
	{ box = Color3.fromRGB(235, 45, 65), ribbon = Color3.fromRGB(255, 215, 45) }, -- Красный с золотом
	{ box = Color3.fromRGB(35, 165, 255), ribbon = Color3.fromRGB(255, 230, 60) }, -- Лазурный с золотом
	{ box = Color3.fromRGB(165, 55, 250), ribbon = Color3.fromRGB(80, 245, 255) }, -- Пурпурный с неоном
	{ box = Color3.fromRGB(30, 205, 110), ribbon = Color3.fromRGB(255, 220, 55) }, -- Изумрудный с золотом
}

local FIREWORK_PALETTE = {
	Color3.fromRGB(255, 55, 150),
	Color3.fromRGB(50, 220, 255),
	Color3.fromRGB(255, 210, 40),
	Color3.fromRGB(120, 255, 75),
	Color3.fromRGB(185, 75, 255),
}

local function basePart(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
end

local partPool: { Part } = {}

local function makePart(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	basePart(p)
	p.Parent = parent
	return p
end

-- Пул объектов (Object Pooling) для взрывов, осколков и ударных колец, чтобы не вызывать
-- Instance.new / Destroy в разгар гонки и исключить микро-фризы сборщика мусора (GC)
local function acquirePoolPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material?,
	shape: Enum.PartType?,
	lifetime: number
): Part
	local p = table.remove(partPool)
	if not p then
		p = Instance.new("Part")
		basePart(p)
	end
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Transparency = 0
	p.Parent = parent

	task.delay(lifetime, function()
		if p.Parent ~= nil then
			p:ClearAllChildren()
			p.Transparency = 1
			p.CFrame = CFrame.new(0, -500, 0)
			table.insert(partPool, p)
		end
	end)

	return p
end

local function makeWedge(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material?
): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = mat or Enum.Material.SmoothPlastic
	basePart(w)
	w.Parent = parent
	return w
end

local function attachRibbonTrail(
	parent: BasePart,
	offset0: Vector3,
	offset1: Vector3,
	colorSeq: ColorSequence,
	lifetime: number
): Trail
	local a0 = Instance.new("Attachment")
	a0.Position = offset0
	a0.Parent = parent

	local a1 = Instance.new("Attachment")
	a1.Position = offset1
	a1.Parent = parent

	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Color = colorSeq
	t.LightEmission = 1
	t.Lifetime = lifetime
	t.FaceCamera = true
	t.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.6, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	t.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	t.Parent = parent
	return t
end

-- ============================================================================
-- 1. 3D-МОДЕЛЬ ПОДАРКА СО ЗНАКОМ «?» (18 деталей: коробка, ленты, бант, медальоны «?», ореол)
-- ============================================================================
function PowerupEffects.BuildGiftBoxModel(
	boxId: number,
	center: Vector3,
	scale: number
): (Model, Part, Part, Part)
	local palette = GIFT_COLORS[(boxId - 1) % #GIFT_COLORS + 1]
	local boxColor = palette.box
	local ribColor = palette.ribbon
	local goldMetal = Color3.fromRGB(255, 200, 45)

	local m = Instance.new("Model")
	m.Name = "GiftBox_" .. boxId

	local s = 4.0 * scale
	local root = makePart(
		m,
		"Root",
		Vector3.new(s, s, s),
		CFrame.new(center),
		boxColor,
		Enum.Material.SmoothPlastic
	)
	m.PrimaryPart = root

	-- Внутреннее светящееся ядро
	local core = makePart(
		m,
		"NeonCore",
		Vector3.new(s * 0.88, s * 0.88, s * 0.88),
		CFrame.new(center),
		ribColor,
		Enum.Material.Neon
	)
	core.Transparency = 0.25

	-- Крышка подарка сверху и золотая окантовка снизу
	makePart(
		m,
		"LidTop",
		Vector3.new(s * 1.06, s * 0.18, s * 1.06),
		CFrame.new(center) * CFrame.new(0, s * 0.44, 0),
		boxColor,
		Enum.Material.SmoothPlastic
	)
	makePart(
		m,
		"BaseTrim",
		Vector3.new(s * 1.05, s * 0.12, s * 1.05),
		CFrame.new(center) * CFrame.new(0, -s * 0.45, 0),
		goldMetal,
		Enum.Material.Metal
	)

	-- Перекрестные неоновые подарочные ленты по всем 6 граням
	makePart(
		m,
		"RibbonX",
		Vector3.new(s * 1.08, s * 1.08, s * 0.24),
		CFrame.new(center),
		ribColor,
		Enum.Material.Neon
	)
	makePart(
		m,
		"RibbonZ",
		Vector3.new(s * 0.24, s * 1.08, s * 1.08),
		CFrame.new(center),
		ribColor,
		Enum.Material.Neon
	)
	makePart(
		m,
		"RibbonBelt",
		Vector3.new(s * 1.08, s * 0.22, s * 1.08),
		CFrame.new(center),
		ribColor,
		Enum.Material.Neon
	)

	-- Пышный 3D-бант на крышке подарка (4 петли + центральный узел)
	local bowY = s * 0.58
	makePart(
		m,
		"BowKnot",
		Vector3.new(s * 0.30, s * 0.28, s * 0.30),
		CFrame.new(center) * CFrame.new(0, bowY, 0),
		ribColor,
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	for loopIdx = 1, 4 do
		local ang = (loopIdx - 1) * (math.pi / 2) + math.pi / 4
		makeWedge(
			m,
			"BowLoop_" .. loopIdx,
			Vector3.new(s * 0.22, s * 0.36, s * 0.48),
			CFrame.new(center)
				* CFrame.new(0, bowY + s * 0.06, 0)
				* CFrame.Angles(0, ang, 0)
				* CFrame.new(0, 0, -s * 0.24)
				* CFrame.Angles(0.35, 0, 0),
			ribColor,
			Enum.Material.Neon
		)
	end

	-- Знаки «?» на всех 4 боковых гранях куба
	local faces = {
		Enum.NormalId.Front,
		Enum.NormalId.Back,
		Enum.NormalId.Left,
		Enum.NormalId.Right,
	}
	for _, face in faces do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.LightInfluence = 0
		sg.Brightness = 2.5
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 32
		sg.Parent = root

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Text = "?"
		lbl.Font = Enum.Font.FredokaOne
		lbl.TextScaled = true
		lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		lbl.TextStrokeColor3 = Color3.fromRGB(40, 15, 0)
		lbl.TextStrokeTransparency = 0
		lbl.Parent = sg
	end

	-- Внешняя неоновая сфера-ореол вокруг подарка
	local halo = makePart(
		m,
		"Halo",
		Vector3.new(s * 1.45, s * 1.45, s * 1.45),
		CFrame.new(center),
		ribColor,
		Enum.Material.ForceField,
		Enum.PartType.Ball
	)
	halo.Transparency = 0.5

	-- Световой круг-маяк на снегу под подарком (помогает легко прицелиться санями)
	local groundDisc = makePart(
		boxFolder or Workspace,
		"GroundBeacon_" .. boxId,
		Vector3.new(0.25, s * 2.1, s * 2.1),
		CFrame.new(center.X, center.Y - P.BoxFloat + 0.18, center.Z)
			* CFrame.Angles(0, 0, math.pi / 2),
		ribColor,
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	groundDisc.Transparency = 0.55

	return m, root, halo, groundDisc
end

-- ============================================================================
-- 2. 3D-МОДЕЛЬ РАКЕТЫ (22 детали: корпус, ступенчатый обтекатель, 8 крыльев, сопло, 3D-пламя)
-- ============================================================================
function PowerupEffects.BuildRocketModel(model: Model, frame: CFrame, scale: number): BasePart
	local root = makePart(model, "Root", Vector3.one, frame, Color3.new(1, 1, 1))
	root.Transparency = 1
	model.PrimaryPart = root

	local silver = Color3.fromRGB(238, 242, 250)
	local darkSteel = Color3.fromRGB(45, 50, 62)
	local crimson = Color3.fromRGB(235, 35, 45)
	local hazardGold = Color3.fromRGB(255, 205, 35)
	local neonOrange = Color3.fromRGB(255, 130, 20)
	local neonCyan = Color3.fromRGB(50, 225, 255)

	-- Основной цилиндрический фюзеляж (вдоль оси Z)
	makePart(
		model,
		"Fuselage",
		Vector3.new(3.6, 1.35, 1.35) * scale,
		frame * CFrame.Angles(0, math.pi / 2, 0),
		silver,
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)

	-- Бронекольца и сигнальная полоса
	makePart(
		model,
		"BandFront",
		Vector3.new(0.45, 1.44, 1.44) * scale,
		frame * CFrame.new(0, 0, -1.1 * scale) * CFrame.Angles(0, math.pi / 2, 0),
		crimson,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Cylinder
	)
	makePart(
		model,
		"BandHazard",
		Vector3.new(0.32, 1.46, 1.46) * scale,
		frame * CFrame.new(0, 0, -0.35 * scale) * CFrame.Angles(0, math.pi / 2, 0),
		hazardGold,
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	makePart(
		model,
		"BandRear",
		Vector3.new(0.55, 1.44, 1.44) * scale,
		frame * CFrame.new(0, 0, 1.15 * scale) * CFrame.Angles(0, math.pi / 2, 0),
		darkSteel,
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)

	-- Многоступенчатый острый носовой обтекатель (боеголовка)
	makePart(
		model,
		"NoseBase",
		Vector3.new(1.32, 1.32, 1.4) * scale,
		frame * CFrame.new(0, 0, -1.9 * scale),
		crimson,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	makePart(
		model,
		"NoseMid",
		Vector3.new(0.95, 0.95, 1.4) * scale,
		frame * CFrame.new(0, 0, -2.45 * scale),
		crimson,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	local warheadTip = makePart(
		model,
		"WarheadTip",
		Vector3.new(0.55, 0.55, 0.9) * scale,
		frame * CFrame.new(0, 0, -2.95 * scale),
		neonOrange,
		Enum.Material.Neon,
		Enum.PartType.Ball
	)

	-- 4 больших стреловидных хвостовых стабилизатора + 4 передних руля-канарда
	for finIdx = 1, 4 do
		local angle = (finIdx - 1) * (math.pi / 2)
		makeWedge(
			model,
			"TailFin_" .. finIdx,
			Vector3.new(0.22, 1.15, 1.55) * scale,
			frame
				* CFrame.new(0, 0, 1.05 * scale)
				* CFrame.Angles(0, 0, angle)
				* CFrame.new(0, 0.95 * scale, 0),
			crimson,
			Enum.Material.SmoothPlastic
		)
		-- Неоновые кромки на концах крыльев
		makePart(
			model,
			"FinTip_" .. finIdx,
			Vector3.new(0.16, 0.16, 1.35) * scale,
			frame
				* CFrame.new(0, 0, 1.15 * scale)
				* CFrame.Angles(0, 0, angle)
				* CFrame.new(0, 1.48 * scale, 0),
			neonCyan,
			Enum.Material.Neon
		)
		-- Передние рули наведения
		makeWedge(
			model,
			"Canard_" .. finIdx,
			Vector3.new(0.16, 0.52, 0.75) * scale,
			frame
				* CFrame.new(0, 0, -1.25 * scale)
				* CFrame.Angles(0, 0, angle + math.pi / 4)
				* CFrame.new(0, 0.72 * scale, 0),
			darkSteel,
			Enum.Material.Metal
		)
	end

	-- Сопло реактивного двигателя
	makePart(
		model,
		"Nozzle",
		Vector3.new(0.75, 1.12, 1.12) * scale,
		frame * CFrame.new(0, 0, 1.95 * scale) * CFrame.Angles(0, math.pi / 2, 0),
		darkSteel,
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)

	-- 3D-конус реактивного пламени позади сопла
	local flameCone = makePart(
		model,
		"FlameCone",
		Vector3.new(0.95, 0.95, 2.8) * scale,
		frame * CFrame.new(0, 0, 3.1 * scale),
		neonOrange,
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	makePart(
		model,
		"FlameCore",
		Vector3.new(0.55, 0.55, 1.8) * scale,
		frame * CFrame.new(0, 0, 2.6 * scale),
		Color3.fromRGB(255, 250, 150),
		Enum.Material.Neon,
		Enum.PartType.Ball
	)

	-- Двойной ленточный след (огненное ядро + дымная спираль)
	attachRibbonTrail(
		flameCone,
		Vector3.new(0, 0.45 * scale, 0),
		Vector3.new(0, -0.45 * scale, 0),
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 245, 130)),
			ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 100, 20)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 95, 110)),
		}),
		0.45
	)
	attachRibbonTrail(
		warheadTip,
		Vector3.new(0.9 * scale, 0, 2.5 * scale),
		Vector3.new(-0.9 * scale, 0, 2.5 * scale),
		ColorSequence.new(neonCyan),
		0.28
	)

	-- Густой шлейф пламени и искр
	local flame = Instance.new("ParticleEmitter")
	flame.LightEmission = 1
	flame.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 150)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 110, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 70, 80)),
	})
	flame.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2 * scale),
		NumberSequenceKeypoint.new(1, 0.15 * scale),
	})
	flame.Lifetime = NumberRange.new(0.3, 0.55)
	flame.Speed = NumberRange.new(16, 26)
	flame.SpreadAngle = Vector2.new(16, 16)
	flame.Rate = 75
	flame.Parent = flameCone

	return flameCone
end

-- ============================================================================
-- 3. 3D-МОДЕЛЬ ПЕТАРДЫ САЛЮТА (16 деталей: полосатый тубус, звёздный купол, стабилизаторы, фитиль)
-- ============================================================================
function PowerupEffects.BuildFireworkModel(
	model: Model,
	frame: CFrame,
	colorIndex: number,
	scale: number
): BasePart
	local root = makePart(model, "Root", Vector3.one, frame, Color3.new(1, 1, 1))
	root.Transparency = 1
	model.PrimaryPart = root

	local mainCol = FIREWORK_PALETTE[(colorIndex - 1) % #FIREWORK_PALETTE + 1]
	local altCol = FIREWORK_PALETTE[colorIndex % #FIREWORK_PALETTE + 1]
	local gold = Color3.fromRGB(255, 215, 50)
	local white = Color3.fromRGB(250, 250, 255)

	-- 4 чередующихся полосатых сегмента корпуса петарды
	for seg = 1, 4 do
		local zOff = (-1.05 + (seg - 1) * 0.65) * scale
		local segCol = if seg % 2 == 1 then mainCol else white
		makePart(
			model,
			"Segment_" .. seg,
			Vector3.new(0.62, 1.05, 1.05) * scale,
			frame * CFrame.new(0, 0, zOff) * CFrame.Angles(0, math.pi / 2, 0),
			segCol,
			Enum.Material.SmoothPlastic,
			Enum.PartType.Cylinder
		)
	end

	-- Золотой ободок и конический звёздный колпак спереди
	makePart(
		model,
		"GoldCollar",
		Vector3.new(0.24, 1.22, 1.22) * scale,
		frame * CFrame.new(0, 0, -1.42 * scale) * CFrame.Angles(0, math.pi / 2, 0),
		gold,
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	for sideIdx = 1, 4 do
		local ang = (sideIdx - 1) * (math.pi / 2)
		makeWedge(
			model,
			"CapCone_" .. sideIdx,
			Vector3.new(0.55, 0.58, 1.25) * scale,
			frame
				* CFrame.new(0, 0, -2.05 * scale)
				* CFrame.Angles(0, 0, ang)
				* CFrame.new(0, 0.28 * scale, 0),
			altCol,
			Enum.Material.Neon
		)
		-- 4 стабилизатора салюта
		makeWedge(
			model,
			"Fin_" .. sideIdx,
			Vector3.new(0.16, 0.72, 0.95) * scale,
			frame
				* CFrame.new(0, 0, 1.0 * scale)
				* CFrame.Angles(0, 0, ang)
				* CFrame.new(0, 0.68 * scale, 0),
			gold,
			Enum.Material.Neon
		)
	end

	-- Направляющая рейка и искрящийся фитиль сзади
	local fuse = makePart(
		model,
		"FuseGlow",
		Vector3.new(0.75, 0.75, 0.75) * scale,
		frame * CFrame.new(0, 0, 1.55 * scale),
		gold,
		Enum.Material.Neon,
		Enum.PartType.Ball
	)

	attachRibbonTrail(
		fuse,
		Vector3.new(0, 0.35 * scale, 0),
		Vector3.new(0, -0.35 * scale, 0),
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, gold),
			ColorSequenceKeypoint.new(0.5, mainCol),
			ColorSequenceKeypoint.new(1, altCol),
		}),
		0.42
	)

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.LightEmission = 1
	sparkle.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, gold),
		ColorSequenceKeypoint.new(0.5, mainCol),
		ColorSequenceKeypoint.new(1, altCol),
	})
	sparkle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.95 * scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkle.Lifetime = NumberRange.new(0.35, 0.6)
	sparkle.Speed = NumberRange.new(10, 18)
	sparkle.SpreadAngle = Vector2.new(35, 35)
	sparkle.Rate = 55
	sparkle.Parent = fuse

	return fuse
end

-- ============================================================================
-- 4. 3D-МОДЕЛЬ ДВОЙНЫХ НИТРО-ТУРБИН (Boost) И ОРБИТАЛЬНОГО КРИСТАЛЬНОГО ЩИТА (Shield)
-- ============================================================================
function PowerupEffects.CreateBoostTurbines(parent: Instance): BoostVisual
	local m = Instance.new("Model")
	m.Name = "NitroTurbines"

	local root = makePart(m, "Root", Vector3.one, CFrame.new(), Color3.new(1, 1, 1))
	root.Transparency = 1
	m.PrimaryPart = root

	local chrome = Color3.fromRGB(220, 230, 245)
	local darkMetal = Color3.fromRGB(40, 45, 58)
	local nitroBlue = Color3.fromRGB(30, 195, 255)
	local nitroPink = Color3.fromRGB(255, 65, 220)

	local flames: { BasePart } = {}
	local trails: { Trail } = {}
	local emitters: { ParticleEmitter } = {}

	-- Поперечная силовая рама крепления турбин к санкам
	makePart(
		m,
		"CrossMount",
		Vector3.new(4.2, 0.28, 0.38),
		CFrame.new(0, 1.15, 1.35),
		darkMetal,
		Enum.Material.Metal
	)

	for _, side in { -1, 1 } do
		local x = side * 2.15
		local y = 1.25
		local z = 1.25

		-- Хромированный баллон N2O / корпус турбины
		makePart(
			m,
			"Tank",
			Vector3.new(2.8, 1.05, 1.05),
			CFrame.new(x, y, z) * CFrame.Angles(0, math.pi / 2, 0),
			chrome,
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
		-- Неоновые кольца плазмы вокруг турбины
		makePart(
			m,
			"PlasmaBand1",
			Vector3.new(0.35, 1.14, 1.14),
			CFrame.new(x, y, z - 0.45) * CFrame.Angles(0, math.pi / 2, 0),
			nitroBlue,
			Enum.Material.Neon,
			Enum.PartType.Cylinder
		)
		makePart(
			m,
			"PlasmaBand2",
			Vector3.new(0.35, 1.14, 1.14),
			CFrame.new(x, y, z + 0.45) * CFrame.Angles(0, math.pi / 2, 0),
			nitroPink,
			Enum.Material.Neon,
			Enum.PartType.Cylinder
		)
		-- Воздухозаборник спереди и сопло сзади
		makePart(
			m,
			"Intake",
			Vector3.new(0.45, 1.18, 1.18),
			CFrame.new(x, y, z - 1.35) * CFrame.Angles(0, math.pi / 2, 0),
			darkMetal,
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
		makePart(
			m,
			"Nozzle",
			Vector3.new(0.65, 1.22, 1.22),
			CFrame.new(x, y, z + 1.45) * CFrame.Angles(0, math.pi / 2, 0),
			darkMetal,
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)

		-- 3D-конус форсажного пламени
		local flame = makePart(
			m,
			"Afterburner",
			Vector3.new(0.95, 0.95, 4.6),
			CFrame.new(x, y, z + 3.6),
			nitroBlue,
			Enum.Material.Neon,
			Enum.PartType.Ball
		)
		table.insert(flames, flame)

		local tr = attachRibbonTrail(
			flame,
			Vector3.new(0, 0.4, 0),
			Vector3.new(0, -0.4, 0),
			ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(160, 250, 255)),
				ColorSequenceKeypoint.new(0.5, nitroBlue),
				ColorSequenceKeypoint.new(1, nitroPink),
			}),
			0.35
		)
		table.insert(trails, tr)

		local em = Instance.new("ParticleEmitter")
		em.LightEmission = 1
		em.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 255, 255)),
			ColorSequenceKeypoint.new(0.5, nitroBlue),
			ColorSequenceKeypoint.new(1, nitroPink),
		})
		em.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.1),
			NumberSequenceKeypoint.new(1, 0.1),
		})
		em.Lifetime = NumberRange.new(0.2, 0.4)
		em.Speed = NumberRange.new(25, 40)
		em.SpreadAngle = Vector2.new(12, 12)
		em.Rate = 85
		em.Parent = flame
		table.insert(emitters, em)
	end

	m.Parent = parent
	return {
		model = m,
		flameL = flames[1],
		flameR = flames[2],
		trails = trails,
		emitters = emitters,
	}
end

function PowerupEffects.UpdateBoostVisual(vis: BoostVisual, cf: CFrame, clock: number)
	vis.model:PivotTo(cf)
	local pulse = 1 + math.sin(clock * 38) * 0.22
	vis.flameL.Size = Vector3.new(0.95 * pulse, 0.95 * pulse, 4.6 * pulse)
	vis.flameR.Size = Vector3.new(0.95 * pulse, 0.95 * pulse, 4.6 * pulse)
end

-- Орбитальный кристальный щит (6 вращающихся 3D-кристаллов льда + 2 энергетических кольца + купол)
function PowerupEffects.CreateShield(parent: Instance): ShieldVisual
	local m = Instance.new("Model")
	m.Name = "AegisCrystalShield"

	local root = makePart(m, "Root", Vector3.one, CFrame.new(), Color3.new(1, 1, 1))
	root.Transparency = 1
	m.PrimaryPart = root

	local iceNeon = Color3.fromRGB(70, 235, 255)
	local iceDeep = Color3.fromRGB(40, 150, 255)

	local dome = makePart(
		m,
		"ForceDome",
		Vector3.new(8.8, 8.8, 8.8),
		CFrame.new(),
		iceNeon,
		Enum.Material.ForceField,
		Enum.PartType.Ball
	)
	dome.Transparency = 0.35

	local ringA = makePart(
		m,
		"RingA",
		Vector3.new(0.22, 9.2, 9.2),
		CFrame.new(),
		iceNeon,
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	ringA.Transparency = 0.45

	local ringB = makePart(
		m,
		"RingB",
		Vector3.new(0.22, 8.4, 8.4),
		CFrame.new(),
		iceDeep,
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	ringB.Transparency = 0.45

	local crystals: { BasePart } = {}
	for i = 1, 6 do
		local gem = makePart(
			m,
			"IceCrystal_" .. i,
			Vector3.new(0.95, 2.1, 0.95),
			CFrame.new(),
			iceNeon,
			Enum.Material.Neon
		)
		gem.Transparency = 0.1
		attachRibbonTrail(
			gem,
			Vector3.new(0, 0.8, 0),
			Vector3.new(0, -0.8, 0),
			ColorSequence.new(iceNeon),
			0.25
		)
		table.insert(crystals, gem)
	end

	m.Parent = parent
	return {
		model = m,
		dome = dome,
		crystals = crystals,
		ringA = ringA,
		ringB = ringB,
	}
end

function PowerupEffects.UpdateShieldVisual(
	vis: ShieldVisual,
	centerCf: CFrame,
	clock: number,
	remainingTime: number?
)
	local base = centerCf * CFrame.new(0, 1.8, 0)
	local blinkHide = false
	if remainingTime and remainingTime < 1.6 then
		blinkHide = math.floor(clock * 14) % 2 == 0
	end
	vis.dome.Transparency = if blinkHide then 0.82 else 0.35
	vis.ringA.Transparency = if blinkHide then 0.85 else 0.45
	vis.ringB.Transparency = if blinkHide then 0.85 else 0.45

	vis.dome.CFrame = base * CFrame.Angles(0, clock * 1.5, 0)
	vis.ringA.CFrame = base * CFrame.Angles(clock * 2.4, clock * 1.8, 0.6)
	vis.ringB.CFrame = base * CFrame.Angles(-clock * 2.1, -clock * 1.4, -0.6)

	local count = #vis.crystals
	for i, gem in vis.crystals do
		local ang = clock * 3.6 + (i - 1) * (math.pi * 2 / count)
		local bob = math.sin(clock * 5 + i) * 0.55
		local radius = 4.6
		local pos = Vector3.new(math.cos(ang) * radius, bob, math.sin(ang) * radius)
		gem.Transparency = if blinkHide then 0.7 else 0.1
		gem.CFrame = base * CFrame.new(pos) * CFrame.Angles(0.35, -ang, clock * 4)
	end
end

-- 3D-модель гигантского снежного шара (ядро снега, комья наледи, кристаллы льда, снежный шлейф)
function PowerupEffects.BuildSnowballModel(model: Model, frame: CFrame, radius: number): BasePart
	local diameter = radius * 2
	local snowCol = Color3.fromRGB(242, 248, 255)
	local packedSnow = Color3.fromRGB(210, 228, 250)
	local iceCyan = Color3.fromRGB(95, 225, 255)

	local core = makePart(
		model,
		"SnowCore",
		Vector3.new(diameter, diameter, diameter),
		frame,
		snowCol,
		Enum.Material.Snow,
		Enum.PartType.Ball
	)
	model.PrimaryPart = core

	-- Выступающие снежные бугры для рельефного объёма при качении
	local lumpOffsets = {
		Vector3.new(0.55, 0.25, 0.15),
		Vector3.new(-0.52, -0.22, 0.25),
		Vector3.new(0.18, -0.55, -0.25),
		Vector3.new(-0.20, 0.52, -0.30),
		Vector3.new(0.25, 0.15, 0.55),
		Vector3.new(-0.25, -0.15, -0.55),
	}
	for idx, off in lumpOffsets do
		local lumpSize = diameter * 0.58
		makePart(
			model,
			"SnowLump_" .. idx,
			Vector3.new(lumpSize, lumpSize, lumpSize),
			frame * CFrame.new(off * radius),
			if idx % 2 == 0 then snowCol else packedSnow,
			Enum.Material.Snow,
			Enum.PartType.Ball
		)
	end

	-- Вмёрзшие ледяные кристаллы на поверхности кома
	for i = 1, 6 do
		local ang = (i - 1) * (math.pi / 3)
		local tilt = if i % 2 == 0 then 0.45 else -0.45
		makePart(
			model,
			"IceChunk_" .. i,
			Vector3.new(radius * 0.36, radius * 0.65, radius * 0.36),
			frame
				* CFrame.Angles(tilt, ang, 0)
				* CFrame.new(0, 0, -radius * 0.88)
				* CFrame.Angles(0.5, 0, 0.4),
			iceCyan,
			Enum.Material.Neon
		)
	end

	attachRibbonTrail(
		core,
		Vector3.new(0, radius * 0.55, 0),
		Vector3.new(0, -radius * 0.55, 0),
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, snowCol),
			ColorSequenceKeypoint.new(1, iceCyan),
		}),
		0.45
	)

	local snowMist = Instance.new("ParticleEmitter")
	snowMist.LightEmission = 0.4
	snowMist.Color = ColorSequence.new(snowCol, iceCyan)
	snowMist.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, radius * 0.55),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	snowMist.Lifetime = NumberRange.new(0.35, 0.65)
	snowMist.Speed = NumberRange.new(10, 20)
	snowMist.SpreadAngle = Vector2.new(180, 180)
	snowMist.Rate = 45
	snowMist.Parent = core

	return core
end

-- ============================================================================
-- 5. 3D-ПРЕДМЕТ В РУКАХ НА САНКАХ ДО ВЫСТРЕЛА + 3D-ПРИЦЕЛ НАВЕДЕНИЯ (Target Lock-On)
-- ============================================================================
function PowerupEffects.UpdateHeldItem(
	kind: string?,
	isRoulette: boolean,
	sledCf: CFrame,
	clock: number
)
	local effectiveKind = if isRoulette then nil else kind
	if effectiveKind ~= heldKind then
		if heldModel then
			heldModel:Destroy()
			heldModel = nil
		end
		heldKind = effectiveKind

		if effectiveKind and fxFolder then
			local m = Instance.new("Model")
			m.Name = "HeldItem_" .. effectiveKind
			if effectiveKind == "Rocket" then
				local cone = PowerupEffects.BuildRocketModel(m, sledCf, 0.78)
				cone.Transparency = 1
				local core = m:FindFirstChild("FlameCore") :: BasePart?
				if core then
					core.Transparency = 1
				end
			elseif effectiveKind == "Fireworks" then
				PowerupEffects.BuildFireworkModel(m, sledCf, 1, 0.9)
			elseif effectiveKind == "Snowball" then
				PowerupEffects.BuildSnowballModel(m, sledCf, 1.35)
			elseif effectiveKind == "Boost" then
				local b = PowerupEffects.CreateBoostTurbines(m)
				b.flameL.Transparency = 1
				b.flameR.Transparency = 1
				m.PrimaryPart = b.model.PrimaryPart
			elseif effectiveKind == "Shield" then
				local core = makePart(
					m,
					"HeldShieldCore",
					Vector3.new(1.4, 2.2, 1.4),
					sledCf,
					Color3.fromRGB(70, 235, 255),
					Enum.Material.Neon
				)
				m.PrimaryPart = core
			end
			-- Пока предмет в запасе на санках (до выстрела), отключаем реактивные ленты и дым
			for _, d in m:GetDescendants() do
				if d:IsA("Trail") or d:IsA("ParticleEmitter") then
					d.Enabled = false
				end
			end
			m.Parent = fxFolder
			heldModel = m
		end
	end

	if heldModel and heldKind then
		local hover = math.sin(clock * 5.0) * 0.25
		if heldKind == "Rocket" then
			heldModel:PivotTo(
				sledCf * CFrame.new(0, 8.2 + hover, 0) * CFrame.Angles(0.08, 0, clock * 1.8)
			)
		elseif heldKind == "Fireworks" then
			heldModel:PivotTo(
				sledCf * CFrame.new(0, 8.2 + hover, 0) * CFrame.Angles(0, 0, clock * 2.5)
			)
		elseif heldKind == "Snowball" then
			heldModel:PivotTo(
				sledCf * CFrame.new(0, 8.4 + hover, 0) * CFrame.Angles(clock * 2.2, clock * 2.8, 0)
			)
		elseif heldKind == "Boost" then
			local sub = heldModel:FindFirstChild("NitroTurbines") :: Model?
			if sub then
				sub:PivotTo(sledCf)
			end
		elseif heldKind == "Shield" then
			heldModel:PivotTo(
				sledCf * CFrame.new(0, 8.2 + hover, 0) * CFrame.Angles(0.4, clock * 3.2, 0.4)
			)
		end
	end
end

-- 3D-прицел наведения (Target Lock-On Reticle) над соперником, в которого нацелена ракета
function PowerupEffects.UpdateTargetLock(targetCf: CFrame?, clock: number)
	if not targetCf then
		if lockOnModel then
			lockOnModel.Parent = nil
		end
		return
	end

	if not lockOnModel then
		local m = Instance.new("Model")
		m.Name = "TargetLockReticle"
		local root = makePart(m, "Root", Vector3.one, CFrame.new(), Color3.new(1, 0, 0))
		root.Transparency = 1
		m.PrimaryPart = root

		local redNeon = Color3.fromRGB(255, 45, 45)
		local ring = makePart(
			m,
			"LockRing",
			Vector3.new(0.25, 6.8, 6.8),
			CFrame.new() * CFrame.Angles(0, 0, math.pi / 2),
			redNeon,
			Enum.Material.Neon,
			Enum.PartType.Cylinder
		)
		ring.Transparency = 0.25

		for i = 1, 4 do
			local ang = (i - 1) * (math.pi / 2)
			makeWedge(
				m,
				"Pointer_" .. i,
				Vector3.new(0.35, 0.9, 1.4),
				CFrame.Angles(0, ang, 0) * CFrame.new(0, 0, -3.6),
				redNeon,
				Enum.Material.Neon
			)
		end

		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromScale(4.2, 4.2)
		bb.StudsOffset = Vector3.new(0, 4.2, 0)
		bb.AlwaysOnTop = true
		bb.Adornee = root
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Text = "🎯"
		lbl.TextScaled = true
		lbl.Parent = bb
		bb.Parent = m

		lockOnModel = m
	end

	if lockOnModel then
		lockOnModel.Parent = fxFolder
		local pulse = 1 + math.sin(clock * 14) * 0.15
		lockOnModel:PivotTo(
			CFrame.new(targetCf.Position + Vector3.new(0, 1.2 + pulse * 0.3, 0))
				* CFrame.Angles(0, clock * 3.5, 0)
		)
	end
end

-- ============================================================================
-- 6. ИНИЦИАЛИЗАЦИЯ И АНИМАЦИЯ ПОДАРКОВ НА ТРАССЕ (С МАГНИТНЫМ ПРИТЯЖЕНИЕМ)
-- ============================================================================
function PowerupEffects.Init(track: Track.Data)
	if boxFolder then
		boxFolder:Destroy()
	end
	if fxFolder then
		fxFolder:Destroy()
	end

	boxFolder = Instance.new("Folder")
	boxFolder.Name = "PowerupBoxes"
	boxFolder.Parent = Workspace

	fxFolder = Instance.new("Folder")
	fxFolder.Name = "PowerupFx"
	fxFolder.Parent = Workspace

	table.clear(boxVisuals)
	table.clear(activeRockets)
	table.clear(activeFireworks)
	table.clear(activeSnowballs)
	table.clear(partPool)
	heldModel = nil
	heldKind = nil
	lockOnModel = nil

	-- Предварительный прогрев пула объектов (40 деталей) на старте, чтобы во время гонки не выделять память
	for _ = 1, 40 do
		local p = Instance.new("Part")
		basePart(p)
		p.Transparency = 1
		p.CFrame = CFrame.new(0, -500, 0)
		p.Parent = fxFolder
		table.insert(partPool, p)
	end

	local boxes = Powerups.GetBoxes(track)
	for _, box in boxes do
		local ground, _, right = Track.At(track, box.s)
		local groundY = ground.Y + right.Y * box.d
		local center = Vector3.new(
			ground.X + right.X * box.d,
			groundY + P.BoxFloat,
			ground.Z + right.Z * box.d
		)

		local model, root, halo, groundDisc = PowerupEffects.BuildGiftBoxModel(box.id, center, 1.0)
		model.Parent = boxFolder

		-- Высокий маячок «?» над подарком, чтобы видеть его за перегибами горы
		local bb = Instance.new("BillboardGui")
		bb.Name = "QuestionMark"
		bb.Size = UDim2.fromScale(3.6, 3.6)
		bb.StudsOffset = Vector3.new(0, 3.8, 0)
		bb.AlwaysOnTop = false
		bb.MaxDistance = 320
		bb.Adornee = root

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "?"
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 245, 110)
		label.TextStrokeColor3 = Color3.fromRGB(140, 45, 0)
		label.TextStrokeTransparency = 0
		label.Parent = bb
		bb.Parent = root

		local sparks = Instance.new("ParticleEmitter")
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 235, 90))
		sparks.Rate = 12
		sparks.Lifetime = NumberRange.new(0.6, 1.1)
		sparks.Speed = NumberRange.new(2, 5)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Parent = root

		boxVisuals[box.id] = {
			model = model,
			root = root,
			halo = halo,
			groundDisc = groundDisc,
			billboard = bb,
			particles = sparks,
			origPos = center,
			scaleFactor = 1.0,
		}
	end
end

local function setBoxVisible(vis: any, visible: boolean)
	for _, d in vis.model:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Name == "Halo" then
				d.Transparency = if visible then 0.5 else 1
			elseif d.Name == "NeonCore" then
				d.Transparency = if visible then 0.25 else 1
			else
				d.Transparency = if visible then 0 else 1
			end
		elseif d:IsA("SurfaceGui") then
			d.Enabled = visible
		end
	end
	vis.groundDisc.Transparency = if visible then 0.55 else 1
	vis.billboard.Enabled = visible
	vis.particles.Enabled = visible
end

-- Анимация вращения подарков, их перезарядки и магнитного притяжения к санкам игрока (с LOD-оптимизацией по дистанции)
function PowerupEffects.UpdateBoxes(
	boxes: { Powerups.Box },
	dt: number,
	clock: number,
	playerWorldPos: Vector3?,
	playerS: number?
)
	local magnetRad = P.BoxMagnetRadius or 16.5

	for _, box in boxes do
		local vis = boxVisuals[box.id]
		if not vis then
			continue
		end

		if box.cooldown > 0 then
			box.cooldown -= dt
			if box.cooldown <= 0 then
				box.active = true
				vis.root.Position = vis.origPos
				setBoxVisible(vis, true)
			end
		end

		if box.active then
			-- Distance Culling (LOD): не крутим матрицы CFrame и не испускаем частицы у далёких коробок
			if playerS and (box.s < playerS - 80 or box.s > playerS + 380) then
				if vis.particles.Enabled then
					vis.particles.Enabled = false
				end
				continue
			end
			if not vis.particles.Enabled then
				vis.particles.Enabled = true
			end

			local bob = math.sin(clock * P.BobRate + box.id * 1.3) * P.BobHeight
			local targetPos = vis.origPos + Vector3.new(0, bob, 0)

			-- Магнитное притяжение подарка к санкам игрока, когда он проезжает рядом
			if playerWorldPos then
				local dist = (playerWorldPos - vis.origPos).Magnitude
				if dist < magnetRad then
					local pull = math.clamp(1 - dist / magnetRad, 0, 1)
					targetPos = targetPos:Lerp(playerWorldPos + Vector3.new(0, 2.0, 0), pull * 0.75)
				end
			end

			local rotY = clock * P.SpinRate + box.id * 0.8
			local rotX = math.sin(clock * 1.8 + box.id) * 0.18
			local rotZ = math.cos(clock * 1.5 + box.id) * 0.14

			vis.model:PivotTo(CFrame.new(targetPos) * CFrame.Angles(rotX, rotY, rotZ))
		end
	end
end

-- Эффект подбора подарка (взрыв золотых звёзд, лент и расширяющаяся волна через Object Pool)
function PowerupEffects.PopBox(boxId: number)
	local vis = boxVisuals[boxId]
	if not vis then
		return
	end

	local popPos = vis.root.Position
	setBoxVisible(vis, false)

	local ring = acquirePoolPart(
		fxFolder,
		"PickupRing",
		Vector3.new(0.3, 3.5, 3.5),
		CFrame.new(popPos) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(255, 225, 60),
		Enum.Material.Neon,
		Enum.PartType.Cylinder,
		0.36
	)
	TweenService
		:Create(ring, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.1, 13, 13),
			Transparency = 1,
		})
		:Play()

	local burstPart = acquirePoolPart(
		fxFolder,
		"PopBurst",
		Vector3.one,
		CFrame.new(popPos),
		Color3.new(1, 1, 1),
		Enum.Material.SmoothPlastic,
		Enum.PartType.Block,
		1.0
	)
	burstPart.Transparency = 1

	local popEmitter = Instance.new("ParticleEmitter")
	popEmitter.LightEmission = 1
	popEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 120)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 90, 180)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 230, 255)),
	})
	popEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	popEmitter.Lifetime = NumberRange.new(0.45, 0.85)
	popEmitter.Speed = NumberRange.new(12, 24)
	popEmitter.SpreadAngle = Vector2.new(180, 180)
	popEmitter.Rate = 0
	popEmitter.Parent = burstPart

	popEmitter:Emit(35)
end

-- ============================================================================
-- 7. ЗАПУСК, ПОЛЁТ И ВЗРЫВ РАКЕТ, ПРЯМОГО САЛЮТА И ЛАВИНЫ СНЕЖНЫХ ШАРОВ
-- ============================================================================
function PowerupEffects.SpawnRocket(
	track: Track.Data,
	startS: number,
	startD: number,
	targetSledId: string?,
	launchSpeed: number?,
	ownerId: string?
): RocketProjectile
	local model = Instance.new("Model")
	model.Name = "Rocket_" .. nextProjId
	model.Parent = fxFolder

	local frame = Track.Frame(track, startS, startD) * CFrame.new(0, 2.8, 0)
	local flameCone = PowerupEffects.BuildRocketModel(model, frame, 1.05)

	local baseSpeed = P.Rocket.Speed
	local actualSpeed = if launchSpeed then math.max(baseSpeed, launchSpeed + 105) else baseSpeed

	local proj: RocketProjectile = {
		id = nextProjId,
		ownerId = ownerId or "player",
		s = startS,
		d = startD,
		speed = actualSpeed,
		targetSledId = targetSledId,
		distanceTraveled = 0,
		age = 0,
		rollAngle = 0,
		bankAngle = 0,
		model = model,
		flameCone = flameCone,
	}

	nextProjId += 1
	table.insert(activeRockets, proj)
	return proj
end

-- Салют стреляет строго по прямой в 3D (куда смотрит нос санок), не загибаясь по дороге
function PowerupEffects.SpawnFireworks(
	track: Track.Data,
	startS: number,
	startD: number,
	launchSpeed: number?,
	ownerId: string?,
	launchFrame: CFrame?
)
	local baseSpeed = P.Fireworks.Speed
	local actualSpeed = if launchSpeed then math.max(baseSpeed, launchSpeed + 135) else baseSpeed
	local baseFrame = launchFrame or Track.Frame(track, startS, startD)
	local origin = baseFrame.Position + baseFrame.LookVector * 6.0 + baseFrame.UpVector * 2.4

	for i = 1, P.Fireworks.VolleyCount do
		local model = Instance.new("Model")
		model.Name = "Firework_" .. nextProjId
		model.Parent = fxFolder

		local spreadAngle = P.Fireworks.SpreadAngles[i] or 0
		local dir = (CFrame.fromAxisAngle(baseFrame.UpVector, -spreadAngle) * baseFrame.LookVector).Unit
		local frame = CFrame.lookAt(origin, origin + dir)
		PowerupEffects.BuildFireworkModel(model, frame, i, 1.1)

		local proj: FireworkProjectile = {
			id = nextProjId,
			ownerId = ownerId or "player",
			pos = origin,
			vel3D = dir * actualSpeed,
			speed = actualSpeed,
			distanceTraveled = 0,
			age = 0,
			rollAngle = i * 1.2,
			colorIndex = i,
			model = model,
		}

		nextProjId += 1
		table.insert(activeFireworks, proj)
	end
end

-- Вызов снегопада / шариковой атаки снегов: впереди по курсу с горы и обочин слева направо
-- и справа налево перекатываются гигантские 3D снежные шары!
function PowerupEffects.SpawnSnowballs(
	track: Track.Data,
	casterS: number,
	casterSpeed: number?,
	ownerId: string?
)
	local count = P.Snowball.Count
	local radius = P.Snowball.Radius
	local leadExtra = if casterSpeed then casterSpeed * 0.25 else 0

	for i = 1, count do
		local spawnS = math.min(
			track.finishS - 20,
			casterS + P.Snowball.StartAhead + leadExtra + (i - 1) * P.Snowball.Spacing
		)
		local _, _, _, width = Track.At(track, spawnS)
		local halfWidth = width * 0.46

		-- Чередуем направление: слева направо (+1) и справа налево (-1) с горы через дорогу
		local dir = if i % 2 == 1 then 1 else -1
		local startD = -dir * (halfWidth - (i % 3) * 4)

		local model = Instance.new("Model")
		model.Name = "GiantSnowball_" .. nextProjId
		model.Parent = fxFolder

		local frame = Track.Frame(track, spawnS, startD) * CFrame.new(0, radius, 0)
		PowerupEffects.BuildSnowballModel(model, frame, radius)

		-- Снежное облако в точке появления шара у обочины/горы
		local cloud = acquirePoolPart(
			fxFolder,
			"BlizzardCloud_" .. nextProjId,
			Vector3.new(12, 5, 12),
			frame * CFrame.new(0, 10, 0),
			Color3.fromRGB(215, 238, 255),
			Enum.Material.Snow,
			Enum.PartType.Ball,
			1.25
		)
		cloud.Transparency = 0.25
		TweenService
			:Create(cloud, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(22, 7, 22),
				Transparency = 1,
			})
			:Play()

		local proj: SnowballProjectile = {
			id = nextProjId,
			ownerId = ownerId or "player",
			s = spawnS,
			d = startD,
			crossVelocity = dir * (P.Snowball.CrossSpeed + (i % 2) * 4),
			downhillSpeed = P.Snowball.DownhillSpeed,
			age = 0,
			maxDuration = P.Snowball.Duration,
			rollAngle = i * 0.9,
			radius = radius,
			model = model,
		}

		nextProjId += 1
		table.insert(activeSnowballs, proj)
	end
end

-- Мощный ледяной взрыв при столкновении с гигантским снежным шаром (через Object Pool)
function PowerupEffects.SnowExplosion(position: Vector3)
	local flash = acquirePoolPart(
		fxFolder,
		"SnowFlash",
		Vector3.new(6, 6, 6),
		CFrame.new(position),
		Color3.fromRGB(160, 235, 255),
		Enum.Material.Neon,
		Enum.PartType.Ball,
		0.42
	)
	flash.Transparency = 0.15
	TweenService
		:Create(flash, TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(24, 24, 24),
			Transparency = 1,
		})
		:Play()

	for i = 1, 10 do
		local phi = (i - 1) * (math.pi * 2 / 10)
		local dir = Vector3.new(math.cos(phi), 0.45 + (i % 3) * 0.2, math.sin(phi)).Unit
		local chunk = acquirePoolPart(
			fxFolder,
			"SnowChunk_" .. i,
			Vector3.new(2.2, 2.2, 2.2),
			CFrame.new(position),
			if i % 2 == 0 then Color3.fromRGB(245, 250, 255) else Color3.fromRGB(100, 225, 255),
			if i % 2 == 0 then Enum.Material.Snow else Enum.Material.Neon,
			Enum.PartType.Ball,
			0.55
		)
		TweenService
			:Create(chunk, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = CFrame.new(position + dir * 16) * CFrame.Angles(i, i * 2, 0),
				Size = Vector3.new(0.2, 0.2, 0.2),
				Transparency = 1,
			})
			:Play()
	end
end

-- Мощный многослойный 3D-взрыв (ударная волна-тор + огненный шар + разлетающиеся 3D-звёзды/осколки через Object Pool)
function PowerupEffects.Explosion(position: Vector3, isFirework: boolean)
	local boomPart = makePart(
		fxFolder,
		"BoomCenter",
		Vector3.new(2, 2, 2),
		CFrame.new(position),
		Color3.new(1, 1, 1)
	)
	boomPart.Transparency = 1

	local mainCol = if isFirework
		then FIREWORK_PALETTE[math.random(1, #FIREWORK_PALETTE)]
		else Color3.fromRGB(255, 165, 35)

	-- 1. Расширяющаяся световая сфера
	local flash = acquirePoolPart(
		fxFolder,
		"ExplosionFlash",
		Vector3.new(4, 4, 4),
		CFrame.new(position),
		mainCol,
		Enum.Material.Neon,
		Enum.PartType.Ball,
		0.38
	)
	flash.Transparency = 0.15
	TweenService
		:Create(flash, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = if isFirework then Vector3.new(24, 24, 24) else Vector3.new(20, 20, 20),
			Transparency = 1,
		})
		:Play()

	-- 2. Горизонтальное ударное кольцо по трассе (Shockwave Ring)
	local shockRing = acquirePoolPart(
		fxFolder,
		"ShockRing",
		Vector3.new(0.45, 4, 4),
		CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2),
		if isFirework then Color3.fromRGB(255, 235, 80) else Color3.fromRGB(255, 110, 25),
		Enum.Material.Neon,
		Enum.PartType.Cylinder,
		0.45
	)
	TweenService
		:Create(shockRing, TweenInfo.new(0.42, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.15, 32, 32),
			Transparency = 1,
		})
		:Play()

	-- 3. Разлетающиеся 3D-звёзды салюта или огненные 3D-осколки ракеты
	local shardCount = if isFirework then 12 else 8
	for i = 1, shardCount do
		local phi = (i - 1) * (math.pi * 2 / shardCount)
		local elev = ((i % 3) - 1) * 0.45
		local dir = Vector3.new(
			math.cos(phi) * math.cos(elev),
			math.sin(elev) + 0.35,
			math.sin(phi) * math.cos(elev)
		).Unit
		local shardCol = if isFirework
			then FIREWORK_PALETTE[(i - 1) % #FIREWORK_PALETTE + 1]
			else Color3.fromRGB(255, 190, 50)

		local shard = acquirePoolPart(
			fxFolder,
			"BurstShard_" .. i,
			if isFirework then Vector3.new(1.5, 1.5, 1.5) else Vector3.new(1.2, 1.2, 1.2),
			CFrame.new(position),
			shardCol,
			Enum.Material.Neon,
			if isFirework then Enum.PartType.Ball else Enum.PartType.Block,
			0.52
		)
		attachRibbonTrail(
			shard,
			Vector3.new(0, 0.5, 0),
			Vector3.new(0, -0.5, 0),
			ColorSequence.new(shardCol),
			0.28
		)

		local dist = if isFirework then 18 else 14
		TweenService
			:Create(shard, TweenInfo.new(0.48, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = CFrame.new(position + dir * dist) * CFrame.Angles(i * 2, i * 3, 0),
				Size = Vector3.new(0.1, 0.1, 0.1),
				Transparency = 1,
			})
			:Play()
	end

	-- 4. Густое облако искр
	local blast = Instance.new("ParticleEmitter")
	blast.LightEmission = 1
	if isFirework then
		blast.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 160)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(80, 255, 120)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(60, 210, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 230, 60)),
		})
	else
		blast.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 180)),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 100, 20)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 50, 50)),
		})
	end
	blast.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	blast.Lifetime = NumberRange.new(0.65, 1.25)
	blast.Speed = NumberRange.new(20, 38)
	blast.SpreadAngle = Vector2.new(180, 180)
	blast.Rate = 0
	blast.Parent = boomPart

	blast:Emit(if isFirework then 75 else 55)
	Debris:AddItem(boomPart, 1.5)
end

-- Обновление полёта ракет, прямого салюта и перекатывающихся через дорогу снежных шаров
function PowerupEffects.UpdateProjectiles(
	track: Track.Data,
	dt: number,
	racers: { { id: string, s: number, d: number, onHit: () -> () } }
)
	-- 1. Ракеты с самонаведением
	for i = #activeRockets, 1, -1 do
		local r = activeRockets[i]
		local ds = r.speed * dt
		r.s += ds
		r.distanceTraveled += ds
		r.age += dt
		r.rollAngle += dt * 14 -- быстрое вращение ракеты вокруг продольной оси

		-- Наведение на цель
		local targetRacer: any = nil
		if r.targetSledId then
			for _, racer in racers do
				if racer.id == r.targetSledId then
					targetRacer = racer
					break
				end
			end
		end

		local steerRate = 0
		if targetRacer and targetRacer.s > r.s then
			local deltaD = targetRacer.d - r.d
			local stepD = deltaD * math.clamp(dt * 6.5, 0, 1)
			r.d += stepD
			steerRate = math.clamp(deltaD * 0.08, -0.6, 0.6)
		else
			-- Лёгкое змеевидное покачивание, если летит по прямой
			local wave = math.cos(r.age * 16) * 8 * dt
			r.d += wave
			steerRate = math.sin(r.age * 16) * 0.2
		end
		r.bankAngle += (steerRate - r.bankAngle) * math.clamp(dt * 10, 0, 1)

		-- Прыжковая дуга на старте + парение над снегом
		local arcProgress = math.clamp(r.distanceTraveled / 140, 0, 1)
		local loft = math.sin(arcProgress * math.pi) * 4.2
		local pitch = math.cos(arcProgress * math.pi) * 0.16

		local surface = Track.Frame(track, r.s, r.d)
			* CFrame.new(0, 2.8 + loft, 0)
			* CFrame.Angles(pitch, -r.bankAngle, r.rollAngle)
		r.model:PivotTo(surface)

		-- Пульсация 3D-конуса реактивного пламени
		local pulse = 1 + math.sin(r.age * 45) * 0.25
		r.flameCone.Size = Vector3.new(1.0 * pulse, 1.0 * pulse, 2.9 * pulse)

		-- Проверка попадания в гонщиков (никогда не бьёт самого стрелка!)
		local hit = false
		for _, racer in racers do
			if
				racer.id ~= r.ownerId
				and math.abs(racer.s - r.s) < P.Rocket.HitRadius
				and math.abs(racer.d - r.d) < P.Rocket.HitRadius
			then
				hit = true
				PowerupEffects.Explosion(surface.Position, false)
				racer.onHit()
				break
			end
		end

		if not hit and (r.distanceTraveled >= P.Rocket.MaxRange or r.s >= track.finishS) then
			hit = true
			PowerupEffects.Explosion(surface.Position, false)
		end

		if hit then
			r.model:Destroy()
			table.remove(activeRockets, i)
		end
	end

	-- 2. Салют: летит строго по прямой в 3D (не следует за дорогой)
	local fwRayParams = RaycastParams.new()
	fwRayParams.FilterType = Enum.RaycastFilterType.Exclude
	local fwExclude: { Instance } = {}
	if fxFolder then
		table.insert(fwExclude, fxFolder)
	end
	local sledVis = Workspace:FindFirstChild("Sled")
	if sledVis then
		table.insert(fwExclude, sledVis)
	end
	fwRayParams.FilterDescendantsInstances = fwExclude
	fwRayParams.IgnoreWater = true

	for i = #activeFireworks, 1, -1 do
		local f = activeFireworks[i]
		local prevPos = f.pos
		local stepVec = f.vel3D * dt
		f.pos += stepVec
		f.distanceTraveled += stepVec.Magnitude
		f.age += dt
		f.rollAngle += dt * 18

		local cf = CFrame.lookAt(f.pos, f.pos + f.vel3D) * CFrame.Angles(0, 0, f.rollAngle)
		f.model:PivotTo(cf)

		local hit = false
		for _, racer in racers do
			if racer.id ~= f.ownerId then
				local racerPos = Track.Frame(track, racer.s, racer.d).Position + Vector3.yAxis * 2.2
				if (racerPos - f.pos).Magnitude < P.Fireworks.ExplosionRadius then
					hit = true
					PowerupEffects.Explosion(f.pos, true)
					racer.onHit()
					break
				end
			end
		end

		if not hit and f.age > 0.06 then
			local worldHit = Workspace:Raycast(prevPos, stepVec, fwRayParams)
			if worldHit then
				hit = true
				PowerupEffects.Explosion(worldHit.Position, true)
			end
		end

		if not hit and f.distanceTraveled >= P.Fireworks.Range then
			hit = true
			PowerupEffects.Explosion(f.pos, true)
		end

		if hit then
			f.model:Destroy()
			table.remove(activeFireworks, i)
		end
	end

	-- 3. Лавина снежных шаров (Snowball): катятся поперёк дороги слева направо и справа налево!
	for i = #activeSnowballs, 1, -1 do
		local sb = activeSnowballs[i]
		sb.age += dt
		sb.s += sb.downhillSpeed * dt
		sb.d += sb.crossVelocity * dt

		local _, _, _, width = Track.At(track, sb.s)
		local halfWidth = width * 0.48
		if math.abs(sb.d) > halfWidth then
			sb.d = math.sign(sb.d) * halfWidth
			sb.crossVelocity = -sb.crossVelocity -- доходя до края дороги, шар катится обратно поперёк полотна
		end

		local linearMove = math.sqrt(sb.crossVelocity ^ 2 + sb.downhillSpeed ^ 2) * dt
		sb.rollAngle += linearMove / sb.radius

		local bounce = math.abs(math.sin(sb.age * 9 + sb.id)) * 0.65
		local rollDir = math.sign(sb.crossVelocity)
		local surface = Track.Frame(track, sb.s, sb.d)
			* CFrame.new(0, sb.radius + bounce, 0)
			* CFrame.Angles(-sb.rollAngle * 0.45, 0, -rollDir * sb.rollAngle)
		sb.model:PivotTo(surface)

		local hit = false
		local hitRad = sb.radius + 3.2
		for _, racer in racers do
			if
				racer.id ~= sb.ownerId
				and math.abs(racer.s - sb.s) < hitRad
				and math.abs(racer.d - sb.d) < hitRad
			then
				hit = true
				PowerupEffects.SnowExplosion(surface.Position)
				racer.onHit()
				break
			end
		end

		if not hit and (sb.age >= sb.maxDuration or sb.s >= track.finishS) then
			hit = true
			PowerupEffects.SnowExplosion(surface.Position)
		end

		if hit then
			sb.model:Destroy()
			table.remove(activeSnowballs, i)
		end
	end
end

return PowerupEffects
