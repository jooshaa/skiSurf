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
local shieldPart: Part? = nil
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
	shieldPart: Part?,
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

-- Создание 3D-модели санок для соперника-бота
local function createRivalModel(name: string, color: Color3, runnerColor: Color3): Model
	local m = Instance.new("Model")
	m.Name = "Rival_" .. name
	m.Parent = Workspace

	local rootPart = Instance.new("Part")
	rootPart.Name = "Root"
	rootPart.Size = S.Board
	rootPart.Color = color
	rootPart.Material = Enum.Material.SmoothPlastic
	rootPart.Anchored = true
	rootPart.CanCollide = false
	rootPart.CanTouch = false
	rootPart.CanQuery = false
	rootPart.CastShadow = false
	rootPart.Parent = m

	for _ = 1, 2 do
		local runner = Instance.new("Part")
		runner.Name = "Runner"
		runner.Size = S.Runner
		runner.Color = runnerColor
		runner.Material = Enum.Material.SmoothPlastic
		runner.Anchored = true
		runner.CanCollide = false
		runner.CanTouch = false
		runner.CanQuery = false
		runner.CastShadow = false
		runner.Parent = m
	end

	-- Dummy Rider: тело и голова
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(1.8, 1.8, 1.2)
	torso.Color = color
	torso.Material = Enum.Material.SmoothPlastic
	torso.Anchored = true
	torso.CanCollide = false
	torso.CanTouch = false
	torso.CanQuery = false
	torso.CastShadow = false
	torso.Parent = m

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.3, 1.3, 1.3)
	head.Color = Color3.fromRGB(240, 200, 160)
	head.Material = Enum.Material.SmoothPlastic
	head.Anchored = true
	head.CanCollide = false
	head.CanTouch = false
	head.CanQuery = false
	head.CastShadow = false
	head.Parent = m

	-- Имя соперника сверху
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(4, 1.2)
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 160
	bb.Adornee = rootPart

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.fromScale(1, 1)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = name
	nameLbl.Font = Enum.Font.FredokaOne
	nameLbl.TextScaled = true
	nameLbl.TextColor3 = color
	nameLbl.TextStrokeTransparency = 0.2
	nameLbl.Parent = bb
	bb.Parent = m

	return m
end

local function setRivalPose(rival: Rival)
	local surface = Track.Frame(track, rival.state.s, rival.state.d)
		+ Vector3.new(0, rival.state.air, 0)
	local cf = surface
		* CFrame.new(0, S.RideHeight, 0)
		* CFrame.Angles(
			0,
			-(rival.state.heading + (rival.state.heading - rival.state.slide) * S.DriftVisual),
			0
		)

	local rootPart = rival.model:FindFirstChild("Root") :: Part?
	if rootPart then
		rootPart.CFrame = cf * CFrame.new(0, S.Runner.Y + S.Board.Y / 2, 0)
	end
	local torso = rival.model:FindFirstChild("Torso") :: Part?
	if torso then
		torso.CFrame = cf * CFrame.new(0, 1.8, 0.2)
	end
	local head = rival.model:FindFirstChild("Head") :: Part?
	if head then
		head.CFrame = cf * CFrame.new(0, 3.0, 0.2)
	end

	local runners: { Part } = {}
	for _, child in rival.model:GetChildren() do
		if child.Name == "Runner" and child:IsA("Part") then
			table.insert(runners, child)
		end
	end
	for i, side in { -1, 1 } do
		local rPart = runners[i]
		if rPart then
			local x = side * (S.Board.X / 2 - S.Runner.X / 2)
			rPart.CFrame = cf * CFrame.new(x, S.Runner.Y / 2, 0)
		end
	end

	if rival.shieldPart then
		rival.shieldPart.CFrame = cf
	end
end

-- Использование предмета игроком (ракета, салют, буст, щит)
local function usePlayerItem()
	if not playerItem or isRoulette then
		return
	end

	local item = playerItem
	playerItem = nil
	Hud.SetPowerup(nil, false, usePlayerItem)

	if item == "Rocket" then
		local nearestAhead: Rival? = nil
		local minGap = math.huge
		for _, r in rivals do
			local gap = r.state.s - state.s
			if gap > 5 and gap < minGap and gap < P.Rocket.MaxRange then
				minGap = gap
				nearestAhead = r
			end
		end
		local targetId = if nearestAhead then nearestAhead.id else nil
		PowerupEffects.SpawnRocket(track, state.s + 10, state.d, targetId)
	elseif item == "Fireworks" then
		PowerupEffects.SpawnFireworks(track, state.s + 12, state.d)
	elseif item == "Boost" then
		boostTime = P.Boost.Duration
		state.v += P.Boost.ExtraSpeed
		SledView.Land(1.0)
	elseif item == "Shield" then
		shieldActive = true
		if not shieldPart then
			shieldPart = PowerupEffects.CreateShield(Workspace)
		end
	end
end

local function initRivals()
	for _, r in rivals do
		r.model:Destroy()
		if r.shieldPart then
			r.shieldPart:Destroy()
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
			shieldPart = nil,
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
	if shieldPart then
		shieldPart:Destroy()
		shieldPart = nil
	end
	boostTime = 0
	spinOutTime = 0
	playerRank = 1

	Powerups.ResetBoxes(boxes)
	for _, r in rivals do
		SledSim.Place(track, r.state, track.startS, 0)
		r.state.d = r.startOffset
		r.item = nil
		r.itemCooldown = 0
		r.shieldActive = false
		if r.shieldPart then
			r.shieldPart:Destroy()
			r.shieldPart = nil
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
	local fresh: { [string]: number } = table.clone(SledConfig.Physics) :: any
	for key, value in preset.values :: { [string]: number } do
		fresh[key] = value
	end
	for key, value in fresh do
		(params :: any)[key] = value
	end
end

-- Положение санок в мире по состоянию расчёта
local function sledFrame(): CFrame
	local surface = Track.Frame(track, state.s, state.d) + Vector3.new(0, state.air, 0)
	return surface
		* CFrame.new(0, S.RideHeight, 0)
		* CFrame.Angles(0, -(state.heading + (state.heading - state.slide) * S.DriftVisual), 0)
		* CFrame.Angles(0, 0, -lean * S.Lean)
end

local function startFall()
	fallFrame = sledFrame()
	local surface = Track.Frame(track, state.s, state.d)
	local direction =
		surface:VectorToWorldSpace(Vector3.new(math.sin(state.slide), 0, -math.cos(state.slide)))
	fallVelocity = direction * state.v + Vector3.new(0, state.w * R.FallLift, 0)
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
	-- Стан от ракеты/салюта: крутит санки
	if spinOutTime > 0 then
		spinOutTime -= dt
		steer = 0
		brake = false
		state.yaw = P.Rocket.SpinSpeed
	end

	-- Нитро-ускорение
	if boostTime > 0 then
		boostTime -= dt
		state.v = math.max(state.v, 115)
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

	-- Обновление щита игрока
	if shieldPart then
		if shieldActive then
			local surf = Track.Frame(track, state.s, state.d)
			shieldPart.CFrame = surf * CFrame.new(0, S.RideHeight, 0)
		else
			shieldPart:Destroy()
			shieldPart = nil
		end
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

		if r.boostTime > 0 then
			r.boostTime -= dt
			r.state.v = math.max(r.state.v, 115)
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
				PowerupEffects.SpawnRocket(track, r.state.s + 10, r.state.d, targetId)
			elseif rItem == "Fireworks" then
				PowerupEffects.SpawnFireworks(track, r.state.s + 12, r.state.d)
			elseif rItem == "Boost" then
				r.boostTime = P.Boost.Duration
				r.state.v += P.Boost.ExtraSpeed
			elseif rItem == "Shield" then
				r.shieldActive = true
				if not r.shieldPart then
					r.shieldPart = PowerupEffects.CreateShield(r.model)
				end
			end
		end

		setRivalPose(r)
	end

	-- Обновление снарядов и попаданий
	local racerTargets = {
		{
			id = "player",
			s = state.s,
			d = state.d,
			onHit = function()
				if shieldActive then
					shieldActive = false
					if shieldPart then
						shieldPart:Destroy()
						shieldPart = nil
					end
					PowerupEffects.Explosion(Track.Frame(track, state.s, state.d).Position, true)
				else
					spinOutTime = P.Rocket.StunDuration
					state.v *= P.Rocket.SpeedFactor
					state.yaw = P.Rocket.SpinSpeed
					camKick = C.HitKick * 1.5
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
					r.shieldActive = false
					if r.shieldPart then
						r.shieldPart:Destroy()
						r.shieldPart = nil
					end
					PowerupEffects.Explosion(
						Track.Frame(track, r.state.s, r.state.d).Position,
						true
					)
				else
					r.spinOutTime = P.Rocket.StunDuration
					r.state.v *= P.Rocket.SpeedFactor
					r.state.yaw = P.Rocket.SpinSpeed
				end
			end,
		})
	end
	PowerupEffects.UpdateProjectiles(track, dt, racerTargets)

	-- Анимация боксов
	PowerupEffects.UpdateBoxes(boxes, dt, clock)

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
	fallVelocity -= Vector3.new(0, params.AirGravity * dt, 0)
	fallFrame = (fallFrame + fallVelocity * dt)
		* CFrame.Angles(R.FallSpin * dt, 0, R.FallSpin * R.FallRoll * dt)
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
-- Камера: сзади и сверху, смотрит туда, куда трасса повернёт
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
		-- Камера остаётся на месте и провожает санки взглядом
		camFov += (C.FallFov - camFov) * (1 - math.exp(-C.FovRate * dt))
		camera.FieldOfView = camFov
		camera.CFrame = CFrame.lookAt(camera.CFrame.Position, position)
		return
	end

	local aheadS = state.s + C.LookAhead + state.v * C.LookAheadTime
	local ahead, _, aheadRight = Track.At(track, aheadS)
	local toAhead = ahead + aheadRight * state.d * C.LateralFollow - position
	local wanted = Vector3.new(toAhead.X, 0, toAhead.Z)
	if wanted.Magnitude > 1 then
		local blended = camDirection:Lerp(wanted.Unit, 1 - math.exp(-C.TurnRate * dt))
		if blended.Magnitude > 0.01 then
			camDirection = blended.Unit
		end
	end

	-- Игрок может повернуть камеру вокруг санок, поднять её и отдалить
	camYaw = (camYaw + dragX * C.OrbitSpeed + math.pi) % (math.pi * 2) - math.pi
	camPitch = math.clamp(camPitch + dragY * C.OrbitSpeed, C.OrbitPitchMin, C.OrbitPitchMax)
	camZoom = math.clamp(camZoom * (1 + C.ZoomStep) ^ -wheel, C.ZoomMin, C.ZoomMax)
	-- Отпустил камеру: через паузу она сама возвращается за спину (на телефоне нет клавиши сброса)
	if Input.CameraHeld() or dragX ~= 0 or dragY ~= 0 then
		camIdle = 0
	else
		camIdle += dt
		if camIdle > C.OrbitReturnDelay then
			camYaw *= math.exp(-C.OrbitReturnRate * dt)
		end
	end
	local turned = math.abs(camYaw) -- высота камеры не считается «поворотом»: взгляд остаётся вперёд по трассе
	local direction = CFrame.Angles(0, -camYaw, 0):VectorToWorldSpace(camDirection)

	local distance = (C.Distance + state.v * C.DistancePerSpeed) * camZoom
	-- В повороте камеру выносит наружу: видно, как санки уходят под тебя
	local side = Vector3.new(-direction.Z, 0, direction.X)
	local eye = position - direction * (distance * math.cos(camPitch)) - side * (lean * C.SideSway)
	local eyeY = position.Y + C.Height * camZoom + distance * math.sin(camPitch)
	-- Пока камера почти сзади, она не опускается ниже снега позади; при повороте запас плавно уходит
	local clearance = 1 - math.clamp(turned / C.OrbitClearance, 0, 1)
	if clearance > 0 then
		local behind = Track.At(track, state.s - distance)
		local lifted = math.max(eyeY, behind.Y + C.MinClearance)
		eyeY += (lifted - eyeY) * clearance
	end
	eye = Vector3.new(eye.X, eyeY, eye.Z)
	local focusGround = Track.At(track, state.s + C.FocusAhead)
	local focus = position + camDirection * C.FocusAhead
	focus = Vector3.new(focus.X, focusGround.Y + C.FocusHeight + state.air * C.AirFocus, focus.Z)
	-- Чем дальше камера от положения «сзади», тем больше она смотрит на сами санки
	focus = focus:Lerp(
		position + Vector3.new(0, C.FocusHeight, 0),
		math.clamp(turned / C.OrbitFocusBlend, 0, 1)
	)

	local wantedFov = C.FovBase + C.FovExtra * math.clamp(state.v / C.FovSpeedRef, 0, 1)
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
