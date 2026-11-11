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

local R = SledConfig.Run
local C = SledConfig.Camera
local S = SledConfig.Sled

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

----------------------------------------------------------------------------------------------------
-- Санки: простая модель из блоков, живёт только на клиенте
----------------------------------------------------------------------------------------------------

local sled = Instance.new("Model")
sled.Name = "Sled"
local sledParts: { BasePart } = {}

local function sledPart(size: Vector3, offset: CFrame, color: Color3, visible: boolean): Part
	local part = Instance.new("Part")
	part.Size = size
	part.CFrame = offset
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = if visible then 0 else 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Parent = sled
	if visible then
		table.insert(sledParts, part)
	end
	return part
end

local root = sledPart(Vector3.one, CFrame.new(), S.Color, false)
sled.PrimaryPart = root
local runnerY = S.Runner.Y / 2
local boardY = S.Runner.Y + S.Board.Y / 2
sledPart(S.Board, CFrame.new(0, boardY, 0), S.Color, true)
for _, side in { -1, 1 } do
	local x = side * (S.Board.X / 2 - S.Runner.X / 2)
	sledPart(S.Runner, CFrame.new(x, runnerY, 0), S.RunnerColor, true)
	-- Загнутый нос полоза
	sledPart(
		Vector3.new(S.Runner.X, S.Runner.Y, 1.6),
		CFrame.new(x, runnerY + 0.55, -S.Runner.Z / 2 - 0.5) * CFrame.Angles(math.rad(50), 0, 0),
		S.RunnerColor,
		true
	)
end

local sprays: { ParticleEmitter } = {}
for _, side in { -1, 1 } do
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(side * S.Board.X / 2, 0.2, S.Runner.Z / 2)
	attachment.Parent = root
	local spray = Instance.new("ParticleEmitter")
	spray.Color = ColorSequence.new(Color3.new(1, 1, 1))
	spray.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 2.2),
	})
	spray.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	spray.Lifetime = NumberRange.new(0.3, 0.6)
	spray.Speed = NumberRange.new(6, 12)
	spray.SpreadAngle = Vector2.new(25, 25)
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Acceleration = Vector3.new(0, -30, 0)
	spray.Rate = 0
	spray.Parent = attachment
	table.insert(sprays, spray)
end
sled.Parent = Workspace

----------------------------------------------------------------------------------------------------
-- Персонаж сидит на санках: корень закреплён и едет вместе с ними, поза сидя.
----------------------------------------------------------------------------------------------------

local riderRoot: BasePart? = nil
local riderHumanoid: Humanoid? = nil

local function onCharacter(character: Model)
	riderRoot = nil
	riderHumanoid = nil
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	rootPart.Anchored = true
	humanoid.Sit = true
	riderRoot = rootPart
	riderHumanoid = humanoid
end

local function disableDefaultControls()
	GuiService.TouchControlsEnabled = false
	local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
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

local function restart()
	SledSim.Place(track, state, track.startS, 0)
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
		* CFrame.Angles(0, -state.heading, 0)
		* CFrame.Angles(0, 0, -lean)
end

local function startFall()
	fallFrame = sledFrame()
	local surface = Track.Frame(track, state.s, state.d)
	local direction =
		surface:VectorToWorldSpace(Vector3.new(math.sin(state.slide), 0, -math.cos(state.slide)))
	fallVelocity = direction * state.v + Vector3.new(0, state.w * 0.5, 0)
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
		* CFrame.Angles(R.FallSpin * dt, 0, R.FallSpin * 0.6 * dt)
	runTime += dt
	if modeTime >= R.FallTime then
		SledSim.Place(track, state, Track.CheckpointBefore(track, state.s), R.RespawnSpeed)
		blink = R.RespawnBlink
		setMode("run")
	end
end

local function updateFinish(dt: number)
	-- После черты санки сами выравниваются и тормозят на выкате
	local steer = math.clamp(-state.heading * 3 - state.d * 0.02, -1, 1)
	simulate(dt, steer, true)
	if state.fell or state.s > track.length - 12 then
		SledSim.Place(track, state, math.min(state.s, track.length - 12), 0)
	end
	if modeTime >= R.FinishPause then
		restart()
	end
end

----------------------------------------------------------------------------------------------------
-- Камера: сзади и сверху, смотрит туда, куда трасса повернёт
----------------------------------------------------------------------------------------------------

local function updateCamera(dt: number, frame: CFrame, steer: number)
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
	local eye = position - camDirection * distance
	eye = Vector3.new(eye.X, math.max(position.Y + C.Height, behind.Y + C.MinClearance), eye.Z)
	local focusGround = Track.At(track, state.s + C.FocusAhead)
	local focus = position + camDirection * C.FocusAhead
	focus = Vector3.new(focus.X, focusGround.Y + C.FocusHeight + state.air * 0.5, focus.Z)

	local wantedFov = C.FovBase + C.FovExtra * math.clamp(state.v / C.FovSpeedRef, 0, 1)
	camFov += (wantedFov - camFov) * (1 - math.exp(-C.FovRate * dt))
	camera.FieldOfView = camFov
	camera.CFrame = CFrame.lookAt(eye, focus) * CFrame.Angles(0, 0, -steer * C.Roll)
end

----------------------------------------------------------------------------------------------------
-- Кадр
----------------------------------------------------------------------------------------------------

local function updateEffects(steer: number, brake: boolean)
	local slip = math.abs(state.heading - state.slide)
	local rate = 0
	if mode == "run" and not state.airborne then
		rate = state.v * S.SprayBase + slip * S.SprayTurn + (if brake then S.SprayBrake else 0)
		rate += math.abs(steer) * S.SprayTurn * 0.3
	end
	for _, spray in sprays do
		spray.Rate = math.min(rate, S.SprayMax)
	end

	-- После респауна санки мигают: видно, что это новая попытка
	local hidden = blink > 0 and math.floor(blink * 10) % 2 == 0
	for _, part in sledParts do
		part.Transparency = if hidden then 0.6 else 0
	end
end

local function onFrame(frameTime: number)
	local dt = math.min(frameTime, R.MaxFrameTime)
	modeTime += dt
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
	sled:PivotTo(frame)
	if riderRoot then
		riderRoot.CFrame = frame * CFrame.new(S.RiderOffset)
	end
	if riderHumanoid and not riderHumanoid.Sit then
		riderHumanoid.Sit = true -- встал (например, после возрождения): сажаем обратно
	end

	updateCamera(dt, frame, steer)
	updateEffects(steer, brake)
	Hud.Update(state.v, steer, brake, state.s / track.finishS, runTime)
end

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
