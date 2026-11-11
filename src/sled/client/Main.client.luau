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
-- Скрипты игрока копируются по одному: соседние модули могут появиться чуть позже
local Hud = require(script.Parent:WaitForChild("Hud"))
local Input = require(script.Parent:WaitForChild("Input"))
local SledView = require(script.Parent:WaitForChild("SledView"))

local R = SledConfig.Run
local C = SledConfig.Camera
local S = SledConfig.Sled
local F = SledConfig.Fx

local player = Players.LocalPlayer
local track = Track.Get()
local params: SledConfig.Physics = table.clone(SledConfig.Physics)
local state = SledSim.New(track, track.startS)

type Mode = "countdown" | "run" | "fall" | "finish"
local mode: Mode = "countdown"
local modeTime = 0 -- секунд в текущем режиме
local runTime = 0
local bestTime: number? = nil
local blink = 0
local lean = 0
local autopilot = false -- клавиша B: едет бот, можно смотреть линию и камеру

local fallFrame = CFrame.new()
local fallVelocity = Vector3.zero

local camDirection = Vector3.new(0, 0, -1)
local camFov = C.FovBase
local camKick = 0 -- кивок камеры после приземления, затухает
local clock = 0

local airTime = 0 -- сколько длится текущий полёт
local lastPosition: Vector3? = nil
local velocity = Vector3.zero -- скорость санок в мире, для снегопада
local riderPitch = 0

----------------------------------------------------------------------------------------------------
-- Персонаж сидит на санках: корень закреплён и едет вместе с ними, поза сидя.
----------------------------------------------------------------------------------------------------

local riderRoot: BasePart? = nil
local riderHumanoid: Humanoid? = nil

local function onCharacter(character: Model)
	riderRoot = nil
	riderHumanoid = nil
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
	SledView.Cut()
end

local function restart()
	place(track.startS, 0)
	runTime = 0
	blink = 0
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
		* CFrame.Angles(0, 0, -lean)
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
	simulate(dt, steer, brake)
	runTime += dt
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

	local distance = C.Distance + state.v * C.DistancePerSpeed
	local behind = Track.At(track, state.s - distance)
	-- В повороте камеру выносит наружу: видно, как санки уходят под тебя
	local side = Vector3.new(-camDirection.Z, 0, camDirection.X)
	local eye = position - camDirection * distance - side * (lean / S.Lean * C.SideSway)
	eye = Vector3.new(eye.X, math.max(position.Y + C.Height, behind.Y + C.MinClearance), eye.Z)
	local focusGround = Track.At(track, state.s + C.FocusAhead)
	local focus = position + camDirection * C.FocusAhead
	focus = Vector3.new(focus.X, focusGround.Y + C.FocusHeight + state.air * C.AirFocus, focus.Z)

	local wantedFov = C.FovBase + C.FovExtra * math.clamp(state.v / C.FovSpeedRef, 0, 1)
	camFov += (wantedFov - camFov) * (1 - math.exp(-C.FovRate * dt))
	camera.FieldOfView = camFov
	camKick *= math.exp(-C.LandKickDecay * dt)
	local shake = C.ShakeAmount * math.clamp(state.v / C.ShakeSpeedRef, 0, 1) ^ 2
	if state.airborne then
		shake = 0 -- в полёте тишина: так приземление ощущается сильнее
	end
	camera.CFrame = CFrame.lookAt(eye, focus)
		* CFrame.Angles(
			math.noise(clock * C.ShakeFreq, 0) * shake - camKick,
			math.noise(0, clock * C.ShakeFreq) * shake,
			-lean / S.Lean * C.Roll
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

	lean += (steer * S.Lean - lean) * (1 - math.exp(-S.LeanRate * dt))
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
			* CFrame.Angles(riderPitch, 0, -lean / S.Lean * S.RiderLean)
	end
	if riderHumanoid and not riderHumanoid.Sit then
		riderHumanoid.Sit = true -- встал (например, после возрождения): сажаем обратно
	end

	updateCamera(dt, frame)
	local sliding = (mode == "run" or mode == "finish") and not state.airborne
	local hidden = blink > 0 and math.floor(blink * R.BlinkRate) % 2 == 0
	SledView.Update(state.v, state.heading - state.slide, steer, brake, sliding, velocity, hidden)
	Hud.Update(state.v, steer, brake, state.s / track.finishS, runTime)
end

SledView.Create()
Hud.Create()
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
