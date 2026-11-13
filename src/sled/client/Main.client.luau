--!strict
-- Main: прототип ощущения спуска. Один игрок, одни санки, одна гора. Санки считаются на клиенте
-- (SledSim), модель и камера ставятся по расчёту каждый кадр. Сервера, монет и соперников нет.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Obstacles = require(ReplicatedStorage.Obstacles)
local SledConfig = require(ReplicatedStorage.SledConfig)
local SledBot = require(ReplicatedStorage.SledBot)
local SledSim = require(ReplicatedStorage.SledSim)
local Track = require(ReplicatedStorage.Track)
local Powerups = require(ReplicatedStorage.Powerups)
-- Скрипты игрока копируются по одному: соседние модули могут появиться чуть позже
local Hud = require(script.Parent:WaitForChild("Hud"))
local Input = require(script.Parent:WaitForChild("Input"))
local SledView = require(script.Parent:WaitForChild("SledView"))
local PowerupEffects = require(script.Parent:WaitForChild("PowerupEffects"))

local R = SledConfig.Run
local C = SledConfig.Camera
local S = SledConfig.Sled
local F = SledConfig.Fx
local Z = SledConfig.Blizzard
local P = SledConfig.Powerups
local RV = SledConfig.Rivals
local O = SledConfig.Obstacles

local player = Players.LocalPlayer
local track = Track.Get()
local obstacleList = Obstacles.Get(track)
local roadYetisFolder: Instance? = nil
local params: SledConfig.Physics = table.clone(SledConfig.Physics)
params.OpenEdges = true -- без бортиков: вылет за пределы дороги возрождает на чекпоинте (как в BB Racing)
local state = SledSim.New(track, track.startS)
local boxes = Powerups.GetBoxes(track)

type Mode = "loading" | "countdown" | "run" | "fall" | "finish"
local mode: Mode = "loading"
local modeTime = 0 -- секунд в текущем режиме
local runTime = 0
local bestTime: number? = nil
local blink = 0
local lean = 0 -- наклон в поворот от -1 до 1, сглаженный руль
local autopilot = false -- клавиша B: едет бот, можно смотреть линию и камеру

-- Предметы игрока
local playerItem: Powerups.Kind? = nil
local isRoulette = false
local rouletteTime = 0
local shieldActive = false
local shieldTime = 0
local shieldVis: PowerupEffects.ShieldVisual? = nil
local boostVis: PowerupEffects.BoostVisual? = nil
local boostTime = 0
local spinOutTime = 0
local bumpCooldown = 0
local playerRank = 1

-- Загружаем точные координаты деревьев и валунов с сугробов обочины от сервера
local function syncTrackProps(inst: Instance?)
	if inst and inst:IsA("StringValue") and inst.Name == "TrackProps" then
		Obstacles.SetProps(Obstacles.ParseProps(inst.Value))
		inst.Changed:Connect(function()
			Obstacles.SetProps(Obstacles.ParseProps(inst.Value))
		end)
	end
end
syncTrackProps(ReplicatedStorage:FindFirstChild("TrackProps"))
ReplicatedStorage.ChildAdded:Connect(syncTrackProps)

-- Соперники (боты на санках)
type Rival = {
	id: string,
	name: string,
	state: SledSim.State,
	model: Model,
	color: Color3,
	startOffset: number,
	item: Powerups.Kind?,
	itemCooldown: number,
	shieldActive: boolean,
	shieldTime: number,
	shieldVis: PowerupEffects.ShieldVisual?,
	boostVis: PowerupEffects.BoostVisual?,
	boostTime: number,
	spinOutTime: number,
}
local rivals: { Rival } = {}

local fallFrame = CFrame.new()
local fallVelocity = Vector3.zero

local camDirection = Vector3.new(0, 0, -1)
local camFov = C.FovBase
local camKick = 0 -- кивок камеры после приземления, затухает
local camYaw = 0 -- игрок повернул камеру вокруг санок, рад
local camHeight = 0 -- высота камеры над базовой точкой в студах (+ выше, - ниже)
local camZoom = 1
local camIdle = 0 -- сколько секунд игрок не трогал камеру
local clock = 0

local airTime = 0 -- сколько длится текущий полёт
local weather = 0 -- сила метели вокруг игрока, 0..1
local onBank = false -- санки уже трутся о борт: удар показываем один раз
local lastPosition: Vector3? = nil
local velocity = Vector3.zero -- скорость санок в мире, для снегопада
local riderPitch = 0

----------------------------------------------------------------------------------------------------
-- Персонаж сидит на санках: корень закреплён и едет вместе с ними, поза сидя.
----------------------------------------------------------------------------------------------------

local riderRoot: BasePart? = nil
local riderHumanoid: Humanoid? = nil
local riderJoints: { [Instance]: CFrame } = {} -- суставы и их поворот в позе райдера

-- Суставы аватара бывают двух видов (Motor6D и AnimationConstraint), у обоих есть Transform
local function collectJoints(character: Model): { [Instance]: CFrame }
	local joints: { [Instance]: CFrame } = {}
	local found = 0
	for _, item in character:GetDescendants() do
		local angle = (S.Pose :: { [string]: number })[item.Name]
		if angle and (item:IsA("Motor6D") or item:IsA("AnimationConstraint")) then
			joints[item] = CFrame.Angles(math.rad(angle), 0, 0)
			found += 1
		end
	end
	return if found >= S.PoseMinJoints then joints else {}
end

-- Движок сбрасывает Transform каждый кадр, поэтому позу ставим перед каждым шагом симуляции
RunService.PreSimulation:Connect(function()
	for joint, transform in riderJoints do
		(joint :: any).Transform = transform
	end
end)

local poseConnections: { RBXScriptConnection } = {}

-- Поставить свою позу. Вызывается повторно, когда персонаж догружается: части тела, скрипт
-- Animate и Animator могут появиться позже самого персонажа.
local function applyPose(character: Model, humanoid: Humanoid)
	local joints = collectJoints(character)
	if not next(joints) then
		return
	end
	-- Своя поза: стандартные анимации выключаем, иначе они её перебивают
	local animate = character:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		animate.Enabled = false
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, playing in animator:GetPlayingAnimationTracks() do
			playing:Stop(0)
		end
	end
	riderJoints = joints
end

local function onCharacter(character: Model)
	riderRoot = nil
	riderHumanoid = nil
	riderJoints = {}
	for _, connection in poseConnections do
		connection:Disconnect()
	end
	table.clear(poseConnections)
	local humanoid = character:WaitForChild("Humanoid", R.CharacterTimeout) :: Humanoid?
	local rootPart = character:WaitForChild("HumanoidRootPart", R.CharacterTimeout) :: BasePart?
	if not humanoid or not rootPart or player.Character ~= character then
		return -- персонаж уже сменился, пока ждали
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	rootPart.Anchored = true
	humanoid.Sit = true
	riderRoot = rootPart
	riderHumanoid = humanoid

	applyPose(character, humanoid)
	local pending = false
	table.insert(
		poseConnections,
		character.DescendantAdded:Connect(function()
			if pending then
				return
			end
			pending = true
			task.defer(function()
				pending = false
				if player.Character == character then
					applyPose(character, humanoid)
				end
			end)
		end)
	)
	SledView.AttachHelmet(character)
end

local function disableDefaultControls()
	GuiService.TouchControlsEnabled = false
	local module =
		player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", R.CharacterTimeout)
	if module then
		local controls = (require :: any)(module):GetControls()
		controls:Disable()
	end
end

----------------------------------------------------------------------------------------------------
-- Заезд
----------------------------------------------------------------------------------------------------

local function setMode(newMode: Mode)
	mode = newMode
	modeTime = 0
end

-- Поставить санки на трассу; камера сразу встаёт за ними, а не доворачивает с прошлого места
local function place(s: number, speed: number)
	SledSim.Place(track, state, s, speed)
	local _, tangent = Track.At(track, s)
	camDirection = Vector3.new(tangent.X, 0, tangent.Z).Unit
	airTime = 0
	lastPosition = nil
	velocity = Vector3.zero
	camKick = 0
	SledView.Cut()
end

-- Создание детализированной 3D-модели санок и гонщика для соперника-бота
local function createRivalModel(name: string, color: Color3, runnerColor: Color3): Model
	local m = Instance.new("Model")
	m.Name = "Rival_" .. name

	local rootPart = Instance.new("Part")
	rootPart.Name = "Root"
	rootPart.Size = Vector3.one
	rootPart.Transparency = 1
	rootPart.Anchored = true
	rootPart.CanCollide = false
	rootPart.CanTouch = false
	rootPart.CanQuery = false
	rootPart.CastShadow = false
	rootPart.CFrame = CFrame.new()
	rootPart.Parent = m
	m.PrimaryPart = rootPart

	local function addPart(
		partName: string,
		size: Vector3,
		offset: CFrame,
		partColor: Color3,
		mat: Enum.Material?,
		meshType: Enum.MeshType?
	): Part
		local p = Instance.new("Part")
		p.Name = partName
		p.Size = size
		p.CFrame = offset
		p.Color = partColor
		p.Material = mat or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		if meshType then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = meshType
			mesh.Parent = p
		end
		p.Parent = m
		return p
	end

	local function addWedge(
		partName: string,
		size: Vector3,
		offset: CFrame,
		partColor: Color3,
		mat: Enum.Material?
	): WedgePart
		local w = Instance.new("WedgePart")
		w.Name = partName
		w.Size = size
		w.CFrame = offset
		w.Color = partColor
		w.Material = mat or Enum.Material.SmoothPlastic
		w.Anchored = true
		w.CanCollide = false
		w.CanTouch = false
		w.CanQuery = false
		w.CastShadow = false
		w.Parent = m
		return w
	end

	local woodColor = Color3.fromRGB(222, 184, 135)
	local darkColor = Color3.fromRGB(32, 36, 46)
	local skinColor = Color3.fromRGB(255, 218, 185)
	local visorColor = Color3.fromRGB(0, 210, 255)
	local stripeColor = Color3.fromRGB(245, 248, 255)
	local tailGlow = Color3.fromRGB(255, 70, 50)

	local scale = 0.68
	local yShift = 3.35

	local function xf(
		px: number,
		py: number,
		pz: number,
		rx: number?,
		ry: number?,
		rz: number?
	): CFrame
		local pos = Vector3.new(px * scale, py * scale + yShift, pz * scale)
		if rx or ry or rz then
			return CFrame.new(pos)
				* CFrame.fromOrientation(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
		end
		return CFrame.new(pos)
	end

	-- 1. Аэродинамичный корпус санок: обтекаемый нос, деревянная дека, боковые борта, спойлер и стоп-огни
	addWedge(
		"NoseFairing",
		Vector3.new(3.40, 1.15, 2.30) * scale,
		xf(0, -3.55, -4.60),
		color,
		Enum.Material.SmoothPlastic
	)
	addPart(
		"NoseBumper",
		Vector3.new(3.55, 0.50, 0.65) * scale,
		xf(0, -3.95, -5.55),
		darkColor,
		Enum.Material.Metal,
		Enum.MeshType.Sphere
	)
	for i = -2, 2 do
		local slatColor = if math.abs(i) == 2 then color else woodColor
		addPart(
			"Slat",
			Vector3.new(0.68, 0.20, 7.60) * scale,
			xf(i * 0.78, -3.90, 0.20),
			slatColor,
			Enum.Material.Wood
		)
	end
	for _, side in { -1, 1 } do
		addPart(
			"SideRail",
			Vector3.new(0.32, 0.55, 7.40) * scale,
			xf(side * 1.85, -3.65, 0.15),
			color,
			Enum.Material.SmoothPlastic
		)
		addPart(
			"TailLight",
			Vector3.new(0.45, 0.24, 0.24) * scale,
			xf(side * 1.15, -3.35, 3.85),
			tailGlow,
			Enum.Material.Neon,
			Enum.MeshType.Sphere
		)
	end
	addPart(
		"SeatCushion",
		Vector3.new(2.40, 0.40, 2.80) * scale,
		xf(0, -3.68, 1.30),
		darkColor,
		Enum.Material.Fabric,
		Enum.MeshType.Sphere
	)
	addPart(
		"RearSpoiler",
		Vector3.new(3.60, 0.22, 0.85) * scale,
		xf(0, -2.55, 3.70, -14, 0, 0),
		color,
		Enum.Material.SmoothPlastic
	)
	for _, side in { -1, 1 } do
		addPart(
			"SpoilerStrut",
			Vector3.new(0.20, 0.90, 0.35) * scale,
			xf(side * 1.25, -3.05, 3.60),
			darkColor,
			Enum.Material.Metal
		)
	end

	-- 2. Металлические полозья с загнутыми носами и амортизаторами
	for _, side in { -1, 1 } do
		local rx = side * 1.55
		addPart(
			"MainRunner",
			Vector3.new(0.32, 0.32, 8.60) * scale,
			xf(rx, -4.80, 0.25),
			runnerColor,
			Enum.Material.Metal
		)
		addPart(
			"FrontCurl",
			Vector3.new(0.32, 0.32, 1.45) * scale,
			xf(rx, -4.42, -4.55, 32, 0, 0),
			runnerColor,
			Enum.Material.Metal
		)
		for _, zStrut in { -2.8, 0.0, 2.8 } do
			addPart(
				"Strut",
				Vector3.new(0.28, 0.72, 0.28) * scale,
				xf(rx, -4.35, zStrut),
				darkColor,
				Enum.Material.Metal,
				Enum.MeshType.Cylinder
			)
		end
	end

	-- 3. Скульптурный гонщик: округлый шлем с аэро-гребнем и визором, наклонённый торс, плечи и шарф на ветру
	addPart(
		"Torso",
		Vector3.new(2.35, 2.25, 1.55) * scale,
		xf(0, -2.05, 0.45, -16, 0, 0),
		color,
		Enum.Material.SmoothPlastic,
		Enum.MeshType.Sphere
	)
	addPart(
		"SuitStripe",
		Vector3.new(0.55, 1.85, 1.62) * scale,
		xf(0, -2.05, 0.45, -16, 0, 0),
		stripeColor,
		Enum.Material.SmoothPlastic,
		Enum.MeshType.Sphere
	)
	addPart(
		"Head",
		Vector3.new(2.15, 2.15, 2.15) * scale,
		xf(0, 0.15, 0.10),
		skinColor,
		Enum.Material.SmoothPlastic,
		Enum.MeshType.Sphere
	)
	addPart(
		"Helmet",
		Vector3.new(2.65, 2.55, 2.75) * scale,
		xf(0, 0.35, 0.15, -8, 0, 0),
		color,
		Enum.Material.SmoothPlastic,
		Enum.MeshType.Sphere
	)
	addPart(
		"HelmetFin",
		Vector3.new(0.32, 0.70, 1.65) * scale,
		xf(0, 1.25, 0.65, -20, 0, 0),
		stripeColor,
		Enum.Material.SmoothPlastic
	)
	addPart(
		"GoggleRim",
		Vector3.new(2.15, 0.88, 0.85) * scale,
		xf(0, 0.30, -0.92),
		darkColor,
		Enum.Material.SmoothPlastic,
		Enum.MeshType.Sphere
	)
	addPart(
		"GoggleGlass",
		Vector3.new(1.88, 0.60, 0.90) * scale,
		xf(0, 0.30, -0.98),
		visorColor,
		Enum.Material.Neon,
		Enum.MeshType.Sphere
	)
	-- Развевающийся шарф гонщика
	addPart(
		"ScarfNeck",
		Vector3.new(1.85, 0.55, 1.65) * scale,
		xf(0, -0.90, 0.30),
		stripeColor,
		Enum.Material.Fabric,
		Enum.MeshType.Sphere
	)
	addPart(
		"ScarfTail",
		Vector3.new(0.75, 0.22, 2.25) * scale,
		xf(0.35, -0.85, 1.75, 10, -12, 0),
		stripeColor,
		Enum.Material.Fabric
	)

	for _, side in { -1, 1 } do
		addPart(
			"Shoulder",
			Vector3.new(0.95, 0.95, 0.95) * scale,
			xf(side * 1.25, -1.35, 0.25),
			color,
			Enum.Material.SmoothPlastic,
			Enum.MeshType.Sphere
		)
		addPart(
			"Sleeve",
			Vector3.new(0.75, 0.75, 2.25) * scale,
			xf(side * 1.42, -2.05, -0.65, -28, -side * 10, 0),
			color,
			Enum.Material.SmoothPlastic,
			Enum.MeshType.Sphere
		)
		addPart(
			"Hand",
			Vector3.new(0.72, 0.72, 0.72) * scale,
			xf(side * 1.45, -2.70, -1.55),
			darkColor,
			Enum.Material.SmoothPlastic,
			Enum.MeshType.Sphere
		)
		addPart(
			"Thigh",
			Vector3.new(0.92, 0.92, 2.35) * scale,
			xf(side * 0.75, -2.75, -0.35, -8, 0, 0),
			color,
			Enum.Material.SmoothPlastic,
			Enum.MeshType.Sphere
		)
		addPart(
			"Boot",
			Vector3.new(0.95, 0.65, 1.45) * scale,
			xf(side * 0.80, -3.35, -1.65),
			darkColor,
			Enum.Material.SmoothPlastic,
			Enum.MeshType.Sphere
		)
	end

	-- Имя соперника сверху
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(4.5, 1.25)
	bb.StudsOffset = Vector3.new(0, 4.8, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 180
	bb.Adornee = rootPart

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.fromScale(1, 1)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = name
	nameLbl.Font = Enum.Font.FredokaOne
	nameLbl.TextScaled = true
	nameLbl.TextColor3 = color
	nameLbl.TextStrokeTransparency = 0.15
	nameLbl.Parent = bb
	bb.Parent = m

	m.Parent = Workspace
	return m
end

local function setRivalPose(rival: Rival)
	local surface = Track.Frame(track, rival.state.s, rival.state.d)
		+ Vector3.new(0, rival.state.air, 0)
	local spinYaw = if rival.spinOutTime > 0 then rival.spinOutTime * 14 else 0
	local wheeliePitch = if rival.boostTime > 0 then 0.12 else 0
	local cf = surface
		* CFrame.new(0, S.RideHeight, 0)
		* CFrame.Angles(
			wheeliePitch,
			-(rival.state.heading + (rival.state.heading - rival.state.slide) * S.DriftVisual)
				+ spinYaw,
			0
		)

	rival.model:PivotTo(cf)

	if rival.shieldVis then
		PowerupEffects.UpdateShieldVisual(rival.shieldVis, cf, clock, rival.shieldTime)
	end
	if rival.boostVis then
		PowerupEffects.UpdateBoostVisual(rival.boostVis, cf, clock)
	end
end

-- Поиск ближайшего соперника впереди в радиусе наведения ракеты
local function findNearestRivalAhead(): Rival?
	local nearestAhead: Rival? = nil
	local minGap = math.huge
	for _, r in rivals do
		local gap = r.state.s - state.s
		if gap > 5 and gap < minGap and gap < P.Rocket.MaxRange then
			minGap = gap
			nearestAhead = r
		end
	end
	return nearestAhead
end

-- Использование предмета игроком (ракета, прямой салют, снегопад шаров, буст, щит на время)
local function usePlayerItem()
	if not playerItem or isRoulette then
		return
	end

	local item = playerItem
	playerItem = nil
	Hud.SetPowerup(nil, false, usePlayerItem)

	if item == "Rocket" then
		local nearestAhead = findNearestRivalAhead()
		local targetId = if nearestAhead then nearestAhead.id else nil
		PowerupEffects.SpawnRocket(track, state.s + 10, state.d, targetId, state.v, "player")
		camKick = math.max(camKick, C.BankKick * 1.4)
	elseif item == "Fireworks" then
		PowerupEffects.SpawnFireworks(track, state.s + 10, state.d, state.v, "player")
		camKick = math.max(camKick, C.BankKick * 1.2)
	elseif item == "Snowball" then
		PowerupEffects.SpawnSnowballs(track, state.s, state.v, "player")
		camKick = math.max(camKick, C.BankKick * 1.1)
	elseif item == "Boost" then
		boostTime = P.Boost.Duration
		state.v += P.Boost.ExtraSpeed
		if not boostVis then
			boostVis = PowerupEffects.CreateBoostTurbines(Workspace)
		end
		SledView.Land(1.0)
	elseif item == "Shield" then
		shieldTime = P.Shield.Duration
		shieldActive = true
		state.shielded = true
		if not shieldVis then
			shieldVis = PowerupEffects.CreateShield(Workspace)
		end
	end
end

local function initRivals()
	for _, r in rivals do
		r.model:Destroy()
		if r.shieldVis then
			r.shieldVis.model:Destroy()
		end
		if r.boostVis then
			r.boostVis.model:Destroy()
		end
	end
	table.clear(rivals)

	for i = 1, RV.Count do
		local name = RV.Names[i] or ("Racer " .. i)
		local color = RV.SledColors[i] or Color3.fromRGB(200, 200, 200)
		local runnerColor = RV.RunnerColors[i] or Color3.fromRGB(40, 40, 40)
		local offset = RV.StartOffsets[i] or (i * 4)
		local model = createRivalModel(name, color, runnerColor)
		local rState = SledSim.New(track, track.startS)
		rState.d = offset

		local rival: Rival = {
			id = "rival_" .. i,
			name = name,
			state = rState,
			model = model,
			color = color,
			startOffset = offset,
			item = nil,
			itemCooldown = 0,
			shieldActive = false,
			shieldTime = 0,
			shieldVis = nil,
			boostVis = nil,
			boostTime = 0,
			spinOutTime = 0,
		}
		table.insert(rivals, rival)
		setRivalPose(rival)
	end
end

local function updateRoadYetis()
	if not roadYetisFolder or roadYetisFolder.Parent == nil then
		local mountain = Workspace:FindFirstChild("Mountain")
		local obsModel = if mountain then mountain:FindFirstChild("Obstacles") else nil
		roadYetisFolder = if obsModel then obsModel:FindFirstChild("RoadYetis") else nil
	end
	if not roadYetisFolder then
		return
	end

	local yetiYaw = math.rad(SledConfig.Assets.Yeti.yaw)
	for index, obstacle in obstacleList do
		if obstacle.kind == "Yeti" then
			-- LOD: обновляем только тех йети, которые в пределах видимости игрока, или при старте
			if math.abs(obstacle.s - state.s) < 650 or state.time == 0 then
				local figure = roadYetisFolder:FindFirstChild(tostring(index))
				if figure and figure:IsA("BasePart") then
					local d = Obstacles.D(obstacle, state.time)
					local frame = Track.Frame(track, obstacle.s, d)
					local waddle = math.sin(state.time * O.Yeti.waddleRate + obstacle.phase)
						* O.Yeti.waddle
					local knockSpin = 0
					if state.lastHit == index and state.hitFree < O.Yeti.knockTime then
						knockSpin = (O.Yeti.knockTime - state.hitFree) * O.Yeti.knockSpin
					end
					figure.CFrame = frame
						* CFrame.new(0, figure.Size.Y / 2, 0)
						* CFrame.Angles(0, math.pi + yetiYaw + knockSpin, waddle)
				end
			end
		end
	end
end

local function restart()
	SledSim.Reset(track, state, track.startS)
	place(track.startS, 0)
	camYaw = 0 -- высоту и зум игрок выбрал сам: их не сбрасываем
	runTime = 0
	blink = 0
	updateRoadYetis()

	playerItem = nil
	isRoulette = false
	rouletteTime = 0
	shieldActive = false
	shieldTime = 0
	state.shielded = false
	if shieldVis then
		shieldVis.model:Destroy()
		shieldVis = nil
	end
	if boostVis then
		boostVis.model:Destroy()
		boostVis = nil
	end
	boostTime = 0
	spinOutTime = 0
	playerRank = 1
	PowerupEffects.UpdateHeldItem(nil, false, CFrame.new(), 0)
	PowerupEffects.UpdateTargetLock(nil, 0)

	Powerups.ResetBoxes(boxes)
	for _, r in rivals do
		SledSim.Reset(track, r.state, track.startS)
		r.state.d = r.startOffset
		r.state.shielded = false
		r.item = nil
		r.itemCooldown = 0
		r.shieldActive = false
		r.shieldTime = 0
		if r.shieldVis then
			r.shieldVis.model:Destroy()
			r.shieldVis = nil
		end
		if r.boostVis then
			r.boostVis.model:Destroy()
			r.boostVis = nil
		end
		r.boostTime = 0
		r.spinOutTime = 0
		setRivalPose(r)
	end

	Hud.SetPowerup(nil, false, usePlayerItem)
	Hud.SetRank(1, #rivals + 1)
	Hud.Result(nil, nil)
	setMode("countdown")
end

local function applyPreset(index: number)
	local preset = SledConfig.Presets[index]
	local fresh: { [string]: any } = table.clone(SledConfig.Physics) :: any
	for key, value in preset.values :: { [string]: number } do
		fresh[key] = value
	end
	fresh.OpenEdges = true
	for key, value in fresh do
		(params :: any)[key] = value
	end
end

-- Положение санок в мире по состоянию расчёта
local function sledFrame(): CFrame
	local surface = Track.Frame(track, state.s, state.d) + Vector3.new(0, state.air, 0)
	local spinYaw = if spinOutTime > 0 then spinOutTime * 14 else 0
	local wheeliePitch = if boostTime > 0 then 0.12 else 0
	return surface
		* CFrame.new(0, S.RideHeight, 0)
		* CFrame.Angles(
			wheeliePitch,
			-(state.heading + (state.heading - state.slide) * S.DriftVisual) + spinYaw,
			0
		)
		* CFrame.Angles(0, 0, -lean * S.Lean)
end

local function startFall()
	fallFrame = sledFrame()
	local surface = Track.Frame(track, state.s, state.d)
	local direction =
		surface:VectorToWorldSpace(Vector3.new(math.sin(state.slide), 0, -math.cos(state.slide)))
	-- Реалистичная инерция срыва с края сугроба без рывков и мультяшных взрывов
	fallVelocity = direction * state.v + Vector3.new(0, math.min(state.w * R.FallLift, -6), 0)
	SledView.Land(0.85)
	setMode("fall")
end

local function simulate(dt: number, steer: number, brake: boolean)
	local steps = math.max(1, math.ceil(dt / R.SubStep))
	local step = dt / steps
	for _ = 1, steps do
		SledSim.Step(track, state, params, steer, brake, step)
	end
end

local function updateRun(dt: number, steer: number, brake: boolean)
	-- Стан от ракеты/салюта/снежного шара: крутит санки
	if spinOutTime > 0 then
		spinOutTime -= dt
		steer = 0
		brake = false
		state.yaw = P.Rocket.SpinSpeed
	end

	-- Таймер защитного щита на время (защищает и от снарядов, и от сугробов/йети/лавы)
	if shieldTime > 0 then
		shieldTime -= dt
		if shieldTime <= 0 then
			shieldTime = 0
			shieldActive = false
			state.shielded = false
		else
			shieldActive = true
			state.shielded = true
		end
	else
		shieldActive = false
		state.shielded = false
	end

	-- Нитро-ускорение с 3D-турбинами
	if boostTime > 0 then
		boostTime -= dt
		state.v = math.max(state.v, 138)
		if boostTime <= 0 and boostVis then
			boostVis.model:Destroy()
			boostVis = nil
		end
	end

	local hitsBefore = state.hits
	simulate(dt, steer, brake)
	runTime += dt

	-- Реакция камеры и снежных брызг зависит от типа препятствия и силы удара
	if state.hits > hitsBefore then
		local kind = state.lastHitKind
		local impact = state.lastHitImpact
		if kind == "Tree" or kind == "Rock" then
			camKick = math.max(camKick, C.HitKick * (1.2 + 1.1 * impact))
			SledView.Land(math.clamp(0.6 + 0.45 * impact, 0.6, 1.0))
		elseif kind == "Yeti" then
			camKick = math.max(camKick, C.HitKick * (1.4 + 0.5 * impact))
			SledView.Land(0.9)
		elseif kind == "Drift" then
			camKick = math.max(camKick, C.HitKick * 0.65)
			SledView.Land(1.0)
		else
			camKick = math.max(camKick, C.HitKick * 1.25)
			SledView.Land(F.HitPuff)
		end
	end

	-- Синхронизируем 3D-модели шагающих по трассе йети с физическим расчётом SledSim (Obstacles.D)
	updateRoadYetis()

	-- Подбор боксов игроком
	for _, box in boxes do
		if
			box.active
			and math.abs(state.s - box.s) < P.BoxRadius
			and math.abs(state.d - box.d) < P.BoxRadius
		then
			box.active = false
			box.cooldown = P.BoxRespawn
			PowerupEffects.PopBox(box.id)
			if not playerItem and not isRoulette then
				isRoulette = true
				rouletteTime = P.RouletteDuration
				Hud.SetPowerup("?", true, usePlayerItem)
			end
		end
	end

	-- Прокрутка рулетки предмета
	if isRoulette then
		rouletteTime -= dt
		if rouletteTime <= 0 then
			isRoulette = false
			playerItem = Powerups.RollItem(playerRank, #rivals + 1)
			Hud.SetPowerup(playerItem, false, usePlayerItem)
		end
	end

	-- Обновление орбитального щита и турбин игрока
	local currentPlayerFrame = sledFrame()
	if shieldVis then
		if shieldActive then
			PowerupEffects.UpdateShieldVisual(shieldVis, currentPlayerFrame, clock, shieldTime)
		else
			shieldVis.model:Destroy()
			shieldVis = nil
		end
	end
	if boostVis then
		PowerupEffects.UpdateBoostVisual(boostVis, currentPlayerFrame, clock)
	end

	-- Отображение 3D-предмета на санках до выстрела + прицел наведения
	PowerupEffects.UpdateHeldItem(playerItem, isRoulette, currentPlayerFrame, clock)
	if playerItem == "Rocket" and not isRoulette then
		local lockedRival = findNearestRivalAhead()
		if lockedRival then
			local rCf = Track.Frame(track, lockedRival.state.s, lockedRival.state.d)
			PowerupEffects.UpdateTargetLock(rCf, clock)
		else
			PowerupEffects.UpdateTargetLock(nil, clock)
		end
	else
		PowerupEffects.UpdateTargetLock(nil, clock)
	end

	-- Симуляция соперников
	for _, r in rivals do
		local rSteer, rBrake = 0, false
		if r.spinOutTime > 0 then
			r.spinOutTime -= dt
			r.state.yaw = P.Rocket.SpinSpeed
		else
			rSteer, rBrake = SledBot.Control(track, r.state, SledConfig.Physics)
		end

		if r.shieldTime > 0 then
			r.shieldTime -= dt
			if r.shieldTime <= 0 then
				r.shieldTime = 0
				r.shieldActive = false
				r.state.shielded = false
				if r.shieldVis then
					r.shieldVis.model:Destroy()
					r.shieldVis = nil
				end
			else
				r.shieldActive = true
				r.state.shielded = true
			end
		end

		if r.boostTime > 0 then
			r.boostTime -= dt
			r.state.v = math.max(r.state.v, 132)
			if r.boostTime <= 0 and r.boostVis then
				r.boostVis.model:Destroy()
				r.boostVis = nil
			end
		end

		SledSim.Step(track, r.state, SledConfig.Physics, rSteer, rBrake, dt)
		if r.state.fell then
			SledSim.Place(
				track,
				r.state,
				Track.CheckpointBefore(track, r.state.s),
				SledConfig.Run.RespawnSpeed
			)
		end

		-- Соперники подбирают боксы
		for _, box in boxes do
			if
				box.active
				and math.abs(r.state.s - box.s) < P.BoxRadius
				and math.abs(r.state.d - box.d) < P.BoxRadius
			then
				box.active = false
				box.cooldown = P.BoxRespawn
				PowerupEffects.PopBox(box.id)
				if not r.item then
					r.item = Powerups.RollItem(2, #rivals + 1)
					r.itemCooldown = math.random(15, 30) / 10
				end
			end
		end

		-- Использование предметов соперниками
		if r.itemCooldown > 0 then
			r.itemCooldown -= dt
		elseif r.item then
			local rItem = r.item
			r.item = nil
			if rItem == "Rocket" then
				local targetId: string? = if state.s > r.state.s then "player" else nil
				if not targetId then
					for _, other in rivals do
						if other.id ~= r.id and other.state.s > r.state.s then
							targetId = other.id
							break
						end
					end
				end
				PowerupEffects.SpawnRocket(
					track,
					r.state.s + 10,
					r.state.d,
					targetId,
					r.state.v,
					r.id
				)
			elseif rItem == "Fireworks" then
				PowerupEffects.SpawnFireworks(track, r.state.s + 10, r.state.d, r.state.v, r.id)
			elseif rItem == "Snowball" then
				PowerupEffects.SpawnSnowballs(track, r.state.s, r.state.v, r.id)
			elseif rItem == "Boost" then
				r.boostTime = P.Boost.Duration
				r.state.v += P.Boost.ExtraSpeed
				if not r.boostVis then
					r.boostVis = PowerupEffects.CreateBoostTurbines(Workspace)
				end
			elseif rItem == "Shield" then
				r.shieldTime = P.Shield.Duration
				r.shieldActive = true
				r.state.shielded = true
				if not r.shieldVis then
					r.shieldVis = PowerupEffects.CreateShield(Workspace)
				end
			end
		end

		setRivalPose(r)
	end

	-- Физика столкновений санок между собой: толкание корпусами при обгоне и удары в бампер
	if bumpCooldown > 0 then
		bumpCooldown = math.max(0, bumpCooldown - dt)
	end
	local playerBumped = false
	for i, r in rivals do
		if SledSim.CollideSleds(track, state, r.state, dt) then
			playerBumped = true
		end
		for j = i + 1, #rivals do
			SledSim.CollideSleds(track, r.state, rivals[j].state, dt)
		end
		setRivalPose(r)
	end
	if playerBumped and bumpCooldown <= 0 then
		bumpCooldown = 0.25
		camKick = math.max(camKick, C.BankKick * 1.35)
		SledView.Land(0.65)
	end

	-- Обновление снарядов и попаданий (подбрасывание санок в воздух при взрыве!)
	local racerTargets = {
		{
			id = "player",
			s = state.s,
			d = state.d,
			onHit = function()
				if shieldActive then
					-- Щит на время: отражает удар без потери щита и даёт импульс скорости!
					state.v += 18
					PowerupEffects.SnowExplosion(Track.Frame(track, state.s, state.d).Position)
				else
					spinOutTime = P.Rocket.StunDuration
					state.v *= P.Rocket.SpeedFactor
					state.yaw = P.Rocket.SpinSpeed
					state.air = math.max(state.air, 4.5)
					state.w = 22
					state.airborne = true
					camKick = C.HitKick * 2.0
					SledView.Land(1.0)
				end
			end,
		},
	}
	for _, r in rivals do
		table.insert(racerTargets, {
			id = r.id,
			s = r.state.s,
			d = r.state.d,
			onHit = function()
				if r.shieldActive then
					r.state.v += 15
					PowerupEffects.SnowExplosion(Track.Frame(track, r.state.s, r.state.d).Position)
				else
					r.spinOutTime = P.Rocket.StunDuration
					r.state.v *= P.Rocket.SpeedFactor
					r.state.yaw = P.Rocket.SpinSpeed
					r.state.air = math.max(r.state.air, 6.0)
					r.state.w = 26
					r.state.airborne = true
				end
			end,
		})
	end
	PowerupEffects.UpdateProjectiles(track, dt, racerTargets)

	-- Анимация подарков и магнитное притяжение к игроку (с LOD-отсечением далёких подарков)
	PowerupEffects.UpdateBoxes(boxes, dt, clock, currentPlayerFrame.Position, state.s)

	-- Расчёт позиции в гонке
	local aheadCount = 0
	for _, r in rivals do
		if r.state.s > state.s then
			aheadCount += 1
		end
	end
	playerRank = aheadCount + 1
	Hud.SetRank(playerRank, #rivals + 1)

	if state.airborne then
		airTime += dt
	elseif airTime > 0 then
		if airTime >= F.LandMinAir then
			local strength = math.clamp(airTime / F.LandFullAir, 0, 1)
			SledView.Land(strength)
			camKick = C.LandKick * strength
		end
		airTime = 0
	end
	-- Удар о снежный борт: камера кивает, из-под санок летит снег
	if state.bank and not onBank then
		camKick = math.max(camKick, C.BankKick)
		SledView.Land(F.BankPuff)
	end
	onBank = state.bank
	if state.fell then
		startFall()
	elseif state.s >= track.finishS then
		bestTime = if bestTime then math.min(bestTime, runTime) else runTime
		Hud.Result(runTime, bestTime)
		setMode("finish")
	end
end

local function updateFall(dt: number)
	local sideSign = if state.d >= 0 then 1 else -1
	local _, _, right = Track.At(track, state.s)
	local flatOutward = Vector3.new(right.X, 0, right.Z).Unit * sideSign
	-- Баллистическое падение с естественным уводом вдоль 62° скального склона, чтобы санки не проваливались внутрь скалы
	fallVelocity += flatOutward * (14 * dt) - Vector3.new(0, params.AirGravity * 1.15 * dt, 0)
	local nextPos = fallFrame.Position + fallVelocity * dt
	-- В реальности санки при падении не крутят сальто, а плавно наклоняют нос вниз по траектории падения с лёгким креном в сторону обрыва
	fallFrame = (fallFrame - fallFrame.Position + nextPos)
		* CFrame.Angles(-R.FallSpin * dt, 0, -sideSign * R.FallRoll * dt)
	runTime += dt
	if modeTime >= R.FallTime then
		place(Track.CheckpointBefore(track, state.s), R.RespawnSpeed)
		blink = R.RespawnBlink
		setMode("run")
	end
end

local function updateFinish(dt: number)
	-- После черты санки сами выравниваются и тормозят на выкате
	local steer =
		math.clamp(-state.heading * R.FinishSteerHeading - state.d * R.FinishSteerCenter, -1, 1)
	simulate(dt, steer, true)
	local lastS = track.length - R.EndMargin
	if state.fell or state.s > lastS then
		SledSim.Place(track, state, math.min(state.s, lastS), 0)
	end
	if modeTime >= R.FinishPause then
		restart()
	end
end

----------------------------------------------------------------------------------------------------
-- Камера в стиле Beach Buggy Racing: плотно следует за направлением движения и руления санок
----------------------------------------------------------------------------------------------------

local function updateCamera(dt: number, frame: CFrame)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local position = frame.Position
	-- Забираем сдвиг каждый кадр: накопленное за время падения не должно дёрнуть камеру после возврата
	local dragX, dragY, wheel = Input.TakeCamera()

	if mode == "fall" then
		-- Реалистичная камера при срыве с обрыва: плавно скользит за кромку склона и провожает падающие вниз санки
		camFov += (C.FallFov - camFov) * (1 - math.exp(-C.FovRate * dt))
		camera.FieldOfView = camFov
		local cliffVantage = position + Vector3.new(0, 14, 0) - camDirection * 20
		local eyePos = camera.CFrame.Position:Lerp(cliffVantage, 1 - math.exp(-3.5 * dt))
		camera.CFrame = CFrame.lookAt(eyePos, position)
		return
	end

	-- Вращение камеры как в Beach Buggy Racing: камера следует за реальным курсом и заносом санок,
	-- а не уводит взгляд вбок заранее на дальнюю точку дуги
	local surfaceFrame = Track.Frame(track, state.s, state.d)
	local sledYaw = -(state.slide * 0.65 + state.heading * 0.35)
	local sledForward = (surfaceFrame * CFrame.Angles(0, sledYaw, 0)).LookVector
	local wanted = Vector3.new(sledForward.X, 0, sledForward.Z)
	if wanted.Magnitude > 0.01 then
		local blended = camDirection:Lerp(wanted.Unit, 1 - math.exp(-C.TurnRate * dt))
		if blended.Magnitude > 0.01 then
			camDirection = blended.Unit
		end
	end

	-- Игрок может повернуть камеру вокруг санок, поднять/опустить её по высоте (в росте) и приблизить/отдалить
	camYaw = (camYaw + dragX * C.OrbitSpeed + math.pi) % (math.pi * 2) - math.pi
	camHeight = math.clamp(camHeight - dragY * 0.045, -2.6, 15.0)
	camZoom = math.clamp(camZoom * (1 + C.ZoomStep) ^ -wheel, C.ZoomMin, C.ZoomMax)
	-- Отпустил камеру: через паузу она сама возвращается за спину
	if Input.CameraHeld() or dragX ~= 0 or dragY ~= 0 then
		camIdle = 0
	else
		camIdle += dt
		if camIdle > C.OrbitReturnDelay then
			camYaw *= math.exp(-C.OrbitReturnRate * dt)
		end
	end
	local turned = math.abs(camYaw)
	local direction = CFrame.Angles(0, -camYaw, 0):VectorToWorldSpace(camDirection)

	local distance = (C.Distance + state.v * C.DistancePerSpeed) * camZoom
	local side = Vector3.new(-direction.Z, 0, direction.X)
	local eye = position - direction * distance - side * (lean * C.SideSway)
	local eyeY = position.Y + (C.Height + camHeight) * camZoom
	-- Пока камера почти сзади и не поднята высоко, она не проваливается под снег позади
	local clearance = 1 - math.clamp(turned / C.OrbitClearance, 0, 1)
	if clearance > 0 then
		local behind = Track.At(track, state.s - distance)
		local minEye = behind.Y + (if camHeight < 0 then 1.8 else C.MinClearance)
		local lifted = math.max(eyeY, minEye)
		eyeY += (lifted - eyeY) * clearance
	end
	eye = Vector3.new(eye.X, eyeY, eye.Z)

	local slopePitchY = surfaceFrame.LookVector.Y * C.FocusAhead * 0.55
	local focus = position + camDirection * C.FocusAhead
	focus = Vector3.new(
		focus.X,
		position.Y + C.FocusHeight + slopePitchY + state.air * C.AirFocus,
		focus.Z
	)
	-- Чем дальше камера от положения «сзади» или выше поднята, тем больше она смотрит на сами санки
	local heightBlend = math.clamp(camHeight / 14, 0, 0.55)
	focus = focus:Lerp(
		position + Vector3.new(0, C.FocusHeight, 0),
		math.max(math.clamp(turned / C.OrbitFocusBlend, 0, 1), heightBlend)
	)

	local boostFovBonus = if boostTime > 0 then 15 else 0
	local wantedFov = C.FovBase
		+ C.FovExtra * math.clamp(state.v / C.FovSpeedRef, 0, 1)
		+ boostFovBonus
	camFov += (wantedFov - camFov) * (1 - math.exp(-C.FovRate * dt))
	camera.FieldOfView = camFov
	camKick *= math.exp(-C.LandKickDecay * dt)
	local shake = C.ShakeAmount * math.clamp(state.v / C.ShakeSpeedRef, 0, 1) ^ C.ShakeCurve
	if state.airborne then
		shake = 0 -- в полёте тишина: так приземление ощущается сильнее
	end
	camera.CFrame = CFrame.lookAt(eye, focus)
		* CFrame.Angles(
			math.noise(clock * C.ShakeFreq, 0) * shake - camKick,
			math.noise(0, clock * C.ShakeFreq) * shake,
			-lean * C.Roll
		)
end

----------------------------------------------------------------------------------------------------
-- Кадр
----------------------------------------------------------------------------------------------------

local function onFrame(frameTime: number)
	local dt = math.min(frameTime, R.MaxFrameTime)
	modeTime += dt
	clock += dt
	blink = math.max(0, blink - dt)
	Input.Update(dt)
	local steer = Input.Steer()
	local brake = Input.Brake()
	if autopilot and mode == "run" then
		steer, brake = SledBot.Control(track, state, params)
	end

	if mode == "loading" then
		local mountain = Workspace:FindFirstChild("Mountain")
		local ready = mountain ~= nil and mountain:GetAttribute("TrackReady") == true
		if ready or modeTime > 5.0 then
			Hud.SetLoading(false)
			updateRoadYetis()
			setMode("countdown")
		end
	elseif mode == "countdown" then
		local lit = math.floor(modeTime / R.CountdownStep)
		Hud.Countdown(math.min(lit, R.CountdownLights))
		if lit > R.CountdownLights then
			Hud.Countdown(nil)
			setMode("run")
		end
	elseif mode == "run" then
		updateRun(dt, steer, brake)
	elseif mode == "fall" then
		updateFall(dt)
	else
		updateFinish(dt)
	end

	lean += (steer - lean) * (1 - math.exp(-S.LeanRate * dt))
	local frame = if mode == "fall" then fallFrame else sledFrame()
	SledView.SetPose(frame)
	if lastPosition and dt > 0 then
		velocity = (frame.Position - lastPosition) / dt
	end
	lastPosition = frame.Position

	-- Райдер: в поворот наклоняется сильнее санок, на скорости пригибается, на тормозе откидывается
	local wantedPitch = if brake and mode == "run"
		then S.RiderBrakeLean
		else -S.RiderTuck * math.clamp(state.v / S.TuckSpeedRef, 0, 1)
	riderPitch += (wantedPitch - riderPitch) * (1 - math.exp(-S.RiderRate * dt))
	if riderRoot then
		riderRoot.CFrame = frame
			* CFrame.new(S.RiderOffset)
			* CFrame.Angles(riderPitch, 0, -lean * S.RiderLean)
	end
	if riderHumanoid and not riderHumanoid.Sit then
		riderHumanoid.Sit = true -- встал (например, после возрождения): сажаем обратно
	end

	updateCamera(dt, frame)
	local sliding = (mode == "run" or mode == "finish") and not state.airborne
	local hidden = blink > 0 and math.floor(blink * R.BlinkRate) % 2 == 0
	SledView.Update(
		state.v,
		state.heading - state.slide,
		steer,
		brake or state.bank,
		sliding,
		velocity,
		hidden
	)
	-- Метель на своих участках трассы нарастает и стихает плавно
	local share = state.s / track.finishS
	local wanted = 0
	for _, zone in Z.Zones do
		local inside = math.min(share - zone.from, zone.to - share) / Z.Fade
		wanted = math.max(wanted, math.clamp(inside, 0, 1))
	end
	weather += (wanted - weather) * (1 - math.exp(-Z.Smooth * dt))
	SledView.SetWeather(weather)
	Hud.Update(state.v, steer, brake, share, runTime)
end

SledView.Create()
Hud.Create()
Hud.SetLoading(true)
PowerupEffects.Init(track)
initRivals()
Hud.Tuning(params :: any, applyPreset, restart)
Hud.Result(nil, nil)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		restart()
	elseif input.KeyCode == Enum.KeyCode.B then
		autopilot = not autopilot
	elseif input.KeyCode == Enum.KeyCode.C then
		camYaw, camHeight, camZoom = 0, 0, 1 -- камера обратно за спину и на стандартную высоту
	elseif
		input.KeyCode == Enum.KeyCode.E
		or input.KeyCode == Enum.KeyCode.Space
		or input.KeyCode == Enum.KeyCode.F
	then
		usePlayerItem()
	end
end)

player.CharacterAdded:Connect(function(character)
	task.spawn(disableDefaultControls)
	onCharacter(character)
end)
task.spawn(disableDefaultControls)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

RunService:BindToRenderStep("Sled", Enum.RenderPriority.Camera.Value + 1, onFrame)
