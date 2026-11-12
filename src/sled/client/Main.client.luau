--!strict
-- Main: прототип ощущения спуска. Один игрок, одни санки, одна гора. Санки считаются на клиенте
-- (SledSim), модель и камера ставятся по расчёту каждый кадр. Сервера, монет и соперников нет.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

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

local player = Players.LocalPlayer
local track = Track.Get()
local params: SledConfig.Physics = table.clone(SledConfig.Physics)
params.OpenEdges = true -- без бортиков: вылет за пределы дороги возрождает на чекпоинте (как в BB Racing)
local state = SledSim.New(track, track.startS)
local boxes = Powerups.GetBoxes(track)

type Mode = "countdown" | "run" | "fall" | "finish"
local mode: Mode = "countdown"
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
local playerRank = 1

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
local camPitch = C.OrbitPitchDefault
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
		mat: Enum.Material?
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
		p.Parent = m
		return p
	end

	local woodColor = Color3.fromRGB(222, 184, 135)
	local darkColor = Color3.fromRGB(38, 40, 48)
	local skinColor = Color3.fromRGB(255, 218, 185)
	local visorColor = Color3.fromRGB(0, 195, 255)
	local stripeColor = Color3.fromRGB(245, 245, 250)

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

	-- 1. Деревянный настил из 5 планок + 3 поперечины + спинка
	for i = -2, 2 do
		local slatColor = if math.abs(i) == 2 then color else woodColor
		addPart(
			"Slat",
			Vector3.new(0.72, 0.20, 8.00) * scale,
			xf(i * 0.82, -3.90, 0),
			slatColor,
			Enum.Material.Wood
		)
	end
	for _, zCross in { -3.0, 0.0, 3.0 } do
		addPart(
			"Crossbeam",
			Vector3.new(4.00, 0.20, 0.40) * scale,
			xf(0, -4.10, zCross),
			woodColor,
			Enum.Material.Wood
		)
	end
	addPart(
		"Backrest",
		Vector3.new(1.40, 1.00, 0.24) * scale,
		xf(0, -3.30, 3.50),
		color,
		Enum.Material.Wood
	)

	-- 2. Стальные полозья с загнутыми носами и стойками
	for _, side in { -1, 1 } do
		local rx = side * 1.50
		addPart(
			"MainRunner",
			Vector3.new(8.50, 0.30, 0.30) * scale,
			xf(rx, -4.80, 0.25, 0, 90, 0),
			runnerColor,
			Enum.Material.Metal
		)
		addPart(
			"FrontCurl",
			Vector3.new(0.76, 0.75, 0.30) * scale,
			xf(rx, -4.44, -4.70, 0, -90, -83),
			runnerColor,
			Enum.Material.Metal
		)
		addPart(
			"RearCurl",
			Vector3.new(0.53, 0.46, 0.30) * scale,
			xf(rx, -4.80, 4.53, 0, -90, 9),
			runnerColor,
			Enum.Material.Metal
		)
		for _, zStrut in { -3.0, 0.0, 3.0 } do
			addPart(
				"Strut",
				Vector3.new(0.60, 0.36, 0.36) * scale,
				xf(rx, -4.50, zStrut, 0, 90, 90),
				runnerColor,
				Enum.Material.Metal
			)
		end
	end

	-- 3. Фигурка гонщика: торс с полосами, голова, шлем, лыжные очки, руки и ноги в ботинках
	addPart("Torso", Vector3.new(2.40, 2.00, 1.60) * scale, xf(0, -2.00, 0.50), color)
	addPart("SuitStripeV", Vector3.new(0.40, 1.60, 0.06) * scale, xf(0, -2.00, -0.30), stripeColor)
	addPart("SuitStripeH", Vector3.new(2.00, 0.40, 0.06) * scale, xf(0, -2.00, -0.30), stripeColor)
	addPart("Head", Vector3.new(2.50, 2.50, 2.50) * scale, xf(0, 0.30, 0.50), skinColor)
	addPart("Helmet", Vector3.new(2.80, 2.80, 2.80) * scale, xf(0, 0.45, 0.50), color)
	addPart("GoggleRim", Vector3.new(2.25, 0.90, 0.42) * scale, xf(0, 0.50, -0.90), darkColor)
	addPart(
		"GoggleGlass",
		Vector3.new(1.95, 0.62, 0.44) * scale,
		xf(0, 0.50, -0.94),
		visorColor,
		Enum.Material.Neon
	)
	addPart("GoggleStrap", Vector3.new(2.90, 0.30, 2.88) * scale, xf(0, 0.50, 0.50), darkColor)

	for _, side in { -1, 1 } do
		addPart(
			"Sleeve",
			Vector3.new(2.55, 0.80, 0.80) * scale,
			xf(side * 1.50, -2.03, -0.13, 0, 90, -45),
			color
		)
		addPart(
			"Hand",
			Vector3.new(0.82, 0.82, 0.82) * scale,
			xf(side * 1.50, -2.94, -1.04),
			skinColor
		)
		addPart(
			"Thigh",
			Vector3.new(2.60, 1.00, 1.00) * scale,
			xf(side * 0.80, -2.50, -0.30, 0, 90, 0),
			color
		)
		addPart(
			"Calf",
			Vector3.new(1.60, 1.00, 1.00) * scale,
			xf(side * 0.80, -2.80, -1.10, 0, -90, -90),
			color
		)
		addPart(
			"Boot",
			Vector3.new(1.12, 0.62, 1.42) * scale,
			xf(side * 0.80, -3.30, -1.30),
			darkColor
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

local function restart()
	place(track.startS, 0)
	camYaw = 0 -- высоту и зум игрок выбрал сам: их не сбрасываем
	runTime = 0
	blink = 0

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
		SledSim.Place(track, r.state, track.startS, 0)
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
	local outwardSign = if state.d >= 0 then 1 else -1
	fallVelocity = direction * state.v
		+ surface.RightVector * (outwardSign * 18)
		+ Vector3.new(0, math.min(state.w * R.FallLift, -14) - 12, 0)
	PowerupEffects.SnowExplosion(fallFrame.Position)
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

	simulate(dt, steer, brake)
	runTime += dt

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
	fallVelocity -= Vector3.new(0, params.AirGravity * 1.45 * dt, 0)
	fallFrame = (fallFrame + fallVelocity * dt)
		* CFrame.Angles(R.FallSpin * dt, R.FallSpin * 0.4 * dt, R.FallSpin * R.FallRoll * dt)
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
		-- Камера вылетает за край обрыва вслед за санками и смотрит сверху вниз в пропасть (2.6 сек реального падения!)
		camFov += (C.FallFov - camFov) * (1 - math.exp(-C.FovRate * dt))
		camera.FieldOfView = camFov
		local cliffVantage = position + Vector3.new(0, 22, 0) - camDirection * 24
		local eyePos = camera.CFrame.Position:Lerp(cliffVantage, 1 - math.exp(-3.2 * dt))
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

	-- Игрок может повернуть камеру вокруг санок, поднять её и отдалить
	camYaw = (camYaw + dragX * C.OrbitSpeed + math.pi) % (math.pi * 2) - math.pi
	camPitch = math.clamp(camPitch + dragY * C.OrbitSpeed, C.OrbitPitchMin, C.OrbitPitchMax)
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
	local eye = position - direction * (distance * math.cos(camPitch)) - side * (lean * C.SideSway)
	local eyeY = position.Y + C.Height * camZoom + distance * math.sin(camPitch)
	-- Пока камера почти сзади, она не опускается ниже снега позади
	local clearance = 1 - math.clamp(turned / C.OrbitClearance, 0, 1)
	if clearance > 0 then
		local behind = Track.At(track, state.s - distance)
		local lifted = math.max(eyeY, behind.Y + C.MinClearance)
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
	-- Чем дальше камера от положения «сзади», тем больше она смотрит на сами санки
	focus = focus:Lerp(
		position + Vector3.new(0, C.FocusHeight, 0),
		math.clamp(turned / C.OrbitFocusBlend, 0, 1)
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

	if mode == "countdown" then
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
		camYaw, camPitch, camZoom = 0, C.OrbitPitchDefault, 1 -- камера обратно за спину
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
