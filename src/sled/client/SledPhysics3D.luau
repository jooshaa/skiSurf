--!strict
-- SledPhysics3D: реальная 3D-физика санок (Raycast-подвеска на 4 точки + 3D-коллизии с горой,
-- деревьями, валунами, йети и соперниками в стиле Beach Buggy Racing).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SledConfig = require(ReplicatedStorage.SledConfig)
local Track = require(ReplicatedStorage.Track)

local O = SledConfig.Obstacles

export type ImpactCallback = (kind: string, severity: number) -> ()

export type Controller = {
	chassis: Part,
	align: AlignOrientation,
	rayParams: RaycastParams,
	grounded: boolean,
	airborne: boolean,
	airTime: number,
	airHeight: number,
	speed: number,
	forwardSpeed: number,
	lateralSpeed: number,
	s: number,
	d: number,
	shielded: boolean,
	boosted: boolean,
	stunned: boolean,
	falling: boolean,
	groundNormal: Vector3,
	headingDir: Vector3,
	steerFiltered: number,
	lastHitCooldown: number,
	prevSpeed: number,
	onImpact: ImpactCallback?,
}

local SledPhysics3D = {}

local CORNER_OFFSETS = {
	Vector3.new(-1.35, 0, -2.2),
	Vector3.new(1.35, 0, -2.2),
	Vector3.new(-1.35, 0, 2.2),
	Vector3.new(1.35, 0, 2.2),
}

local REST_LENGTH = 2.4
local RAY_LENGTH = 3.3
local SPRING_K = 240
local SPRING_DAMP = 14
local RACE_GRAVITY = 115

-- Проекция мировой 3D-позиции санок на ближайшую точку трассы (s, d)
function SledPhysics3D.Project(track: Track.Data, pos: Vector3, hintS: number?): (number, number)
	local startIdx = 1
	local endIdx = track.count
	if hintS then
		local center = math.clamp(math.floor(hintS / track.step) + 1, 1, track.count)
		startIdx = math.max(1, center - 85)
		endIdx = math.min(track.count, center + 85)
	end

	local bestIdx = startIdx
	local bestDistSq = math.huge
	for i = startIdx, endIdx do
		local p = track.pos[i]
		local dx = pos.X - p.X
		local dy = pos.Y - p.Y
		local dz = pos.Z - p.Z
		local dSq = dx * dx + dy * dy + dz * dz
		if dSq < bestDistSq then
			bestDistSq = dSq
			bestIdx = i
		end
	end

	-- Если санки сильно сместились (например, после телепорта или падения), ищем по всей трассе
	if bestDistSq > 140 * 140 and hintS ~= nil then
		for i = 1, track.count do
			local p = track.pos[i]
			local dx = pos.X - p.X
			local dy = pos.Y - p.Y
			local dz = pos.Z - p.Z
			local dSq = dx * dx + dy * dy + dz * dz
			if dSq < bestDistSq then
				bestDistSq = dSq
				bestIdx = i
			end
		end
	end

	local s = (bestIdx - 1) * track.step
	local centerPos, forward, right = Track.At(track, s)
	local rel = pos - centerPos
	local along = rel:Dot(forward)
	s = math.clamp(s + along, 0, track.length)
	centerPos, _, right = Track.At(track, s)
	local d = (pos - centerPos):Dot(right)
	return s, d
end

function SledPhysics3D.Create(
	track: Track.Data,
	startS: number,
	exclude: { Instance },
	onImpact: ImpactCallback?
): Controller
	local chassis = Instance.new("Part")
	chassis.Name = "SledChassis3D"
	chassis.Size = Vector3.new(3.2, 1.1, 5.8)
	chassis.Transparency = 1
	chassis.CanCollide = true
	chassis.CanTouch = true
	chassis.CanQuery = false
	chassis.Anchored = false
	chassis.Massless = false
	chassis.CustomPhysicalProperties = PhysicalProperties.new(1.0, 0.015, 0.12, 100, 100)
	chassis.Parent = Workspace

	local att = Instance.new("Attachment")
	att.Parent = chassis

	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.RigidityEnabled = false
	align.MaxTorque = 600000
	align.Responsiveness = 45
	align.Parent = chassis

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = { chassis }
	for _, inst in exclude do
		table.insert(filterList, inst)
	end
	rayParams.FilterDescendantsInstances = filterList
	rayParams.IgnoreWater = true

	local ctrl: Controller = {
		chassis = chassis,
		align = align,
		rayParams = rayParams,
		grounded = true,
		airborne = false,
		airTime = 0,
		airHeight = 0,
		speed = 0,
		forwardSpeed = 0,
		lateralSpeed = 0,
		s = startS,
		d = 0,
		shielded = false,
		boosted = false,
		stunned = false,
		falling = false,
		groundNormal = Vector3.yAxis,
		headingDir = Vector3.new(0, 0, -1),
		steerFiltered = 0,
		lastHitCooldown = 0,
		prevSpeed = 0,
		onImpact = onImpact,
	}

	chassis.Touched:Connect(function(hit: BasePart)
		if ctrl.falling or ctrl.lastHitCooldown > 0 then
			return
		end
		local obs = hit:GetAttribute("SledObstacle")
		if typeof(obs) ~= "string" then
			return
		end

		if obs == "Drift" then
			ctrl.lastHitCooldown = O.HitRegrip
			if not ctrl.shielded then
				chassis.AssemblyLinearVelocity *= O.Drift.keep
				if ctrl.onImpact then
					ctrl.onImpact("Drift", 0.55)
				end
			end
		elseif obs == "Lava" then
			ctrl.lastHitCooldown = O.HitRegrip
			if not ctrl.shielded then
				chassis.AssemblyLinearVelocity *= O.Lava.keep
				chassis.AssemblyAngularVelocity += Vector3.new(0, (math.random() - 0.5) * 6, 0)
				if ctrl.onImpact then
					ctrl.onImpact("Lava", 0.75)
				end
			end
		elseif obs == "Tree" or obs == "Rock" or obs == "Yeti" then
			ctrl.lastHitCooldown = 0.35
			if ctrl.shielded then
				-- Щит пробивает препятствие с лёгким толчком и без потери хода
				chassis.AssemblyLinearVelocity += chassis.CFrame.LookVector * 12
				if ctrl.onImpact then
					ctrl.onImpact(obs, 0.3)
				end
			elseif ctrl.onImpact then
				local sev = math.clamp(ctrl.speed / 100, 0.35, 1.0)
				ctrl.onImpact(obs, sev)
			end
		end
	end)

	SledPhysics3D.Place(ctrl, track, startS, 0, 0)
	return ctrl
end

function SledPhysics3D.AddExclude(ctrl: Controller, inst: Instance)
	local list = ctrl.rayParams.FilterDescendantsInstances
	table.insert(list, inst)
	ctrl.rayParams.FilterDescendantsInstances = list
end

function SledPhysics3D.Place(
	ctrl: Controller,
	track: Track.Data,
	s: number,
	d: number,
	speed: number
)
	local frame = Track.Frame(track, s, d)
	ctrl.chassis.CFrame = frame * CFrame.new(0, 1.5, 0)
	ctrl.chassis.AssemblyLinearVelocity = frame.LookVector * speed
	ctrl.chassis.AssemblyAngularVelocity = Vector3.zero
	ctrl.align.CFrame = frame
	ctrl.align.Enabled = true
	ctrl.s = s
	ctrl.d = d
	ctrl.headingDir = frame.LookVector
	ctrl.steerFiltered = 0
	ctrl.speed = speed
	ctrl.prevSpeed = speed
	ctrl.airTime = 0
	ctrl.airHeight = 0
	ctrl.grounded = true
	ctrl.airborne = false
	ctrl.falling = false
end

function SledPhysics3D.SetFrozen(ctrl: Controller, frozen: boolean)
	ctrl.chassis.Anchored = frozen
	if frozen then
		ctrl.chassis.AssemblyLinearVelocity = Vector3.zero
		ctrl.chassis.AssemblyAngularVelocity = Vector3.zero
	end
end

function SledPhysics3D.Step(
	ctrl: Controller,
	track: Track.Data,
	dt: number,
	steer: number,
	brake: boolean
)
	if dt <= 0 or ctrl.chassis.Anchored then
		return
	end

	ctrl.lastHitCooldown = math.max(0, ctrl.lastHitCooldown - dt)
	local cf = ctrl.chassis.CFrame
	local mass = ctrl.chassis.AssemblyMass
	local vel = ctrl.chassis.AssemblyLinearVelocity

	-- 1. 4-точечная Raycast-подвеска под углами санок
	local rayDir = ((-cf.UpVector * 0.72) + (-Vector3.yAxis * 0.28)).Unit * RAY_LENGTH
	local hitCount = 0
	local normalSum = Vector3.zero
	local minDist = RAY_LENGTH

	if not ctrl.falling then
		for _, localOff in CORNER_OFFSETS do
			local origin = cf:PointToWorldSpace(localOff)
			local result = Workspace:Raycast(origin, rayDir, ctrl.rayParams)
			if result then
				hitCount += 1
				normalSum += result.Normal
				minDist = math.min(minDist, result.Distance)
				local compression = math.max(0, REST_LENGTH - result.Distance)
				local cornerVel = ctrl.chassis:GetVelocityAtPosition(origin)
				local spring = compression * SPRING_K - cornerVel:Dot(result.Normal) * SPRING_DAMP
				if spring > 0 then
					local impulse = result.Normal * (math.min(spring, 950) * (mass / 4) * dt)
					ctrl.chassis:ApplyImpulseAtPosition(impulse, origin)
				end
			end
		end
	end

	ctrl.grounded = hitCount > 0
	if ctrl.grounded then
		ctrl.groundNormal = normalSum.Unit
		ctrl.airTime = 0
		ctrl.airHeight = 0
		ctrl.airborne = false
	else
		ctrl.airTime += dt
		ctrl.airHeight = math.max(0, minDist - REST_LENGTH)
		ctrl.airborne = ctrl.airTime > 0.14
	end

	-- 2. Определение реального 3D-столкновения по резкому падению скорости (удар о дерево/камень/стену/соперника)
	local curSpeed = vel.Magnitude
	if ctrl.prevSpeed - curSpeed > 18 and ctrl.lastHitCooldown <= 0 then
		ctrl.lastHitCooldown = 0.25
		if ctrl.onImpact then
			local sev = math.clamp((ctrl.prevSpeed - curSpeed) / 55, 0.35, 1.0)
			ctrl.onImpact("Solid", sev)
		end
	end
	ctrl.prevSpeed = curSpeed

	-- 3. Управление, тяга, карвинг и выравнивание санок (отключаются при падении с обрыва!)
	if ctrl.falling then
		ctrl.align.Enabled = false
	else
		-- Смягчаем гравитацию Roblox (196.2 -> RACE_GRAVITY), чтобы санки не казались свинцовыми
		local lift = Workspace.Gravity - RACE_GRAVITY
		if lift > 0 then
			ctrl.chassis:ApplyImpulse(Vector3.yAxis * (lift * mass * dt))
		end

		ctrl.align.Enabled = true
		local up = if ctrl.grounded then ctrl.groundNormal else Vector3.yAxis
		local physLook = cf.LookVector
		-- Если корпус сильно развернуло столкновением, подтягиваем курс к фактическому носу
		if ctrl.headingDir:Dot(physLook) < 0.75 then
			ctrl.headingDir = physLook
		end

		local flatLook = ctrl.headingDir - up * ctrl.headingDir:Dot(up)
		if flatLook.Magnitude < 0.01 then
			flatLook = Vector3.new(physLook.X, 0, physLook.Z)
		end
		flatLook = flatLook.Unit

		local vForward = vel:Dot(flatLook)
		local vRight = 0

		if ctrl.grounded and not ctrl.stunned then
			-- Плавный отклик руля как в Beach Buggy Racing (без резкого дёрганья на первом кадре)
			local steerRateResp = if math.abs(steer) > 0.05 then 9.5 else 12.0
			ctrl.steerFiltered += (steer - ctrl.steerFiltered) * (1 - math.exp(-steerRateResp * dt))

			local lowSpeedScale = math.clamp(math.abs(vForward) / 26, 0.35, 1.0)
			local highSpeedScale = math.clamp(1.0 - (vForward - 85) / 150, 0.72, 1.0)
			local steerRate = if brake then 2.25 else 1.7
			local yawStep = -ctrl.steerFiltered * steerRate * lowSpeedScale * highSpeedScale * dt
			local targetLook = (CFrame.fromAxisAngle(up, yawStep) * flatLook).Unit
			ctrl.headingDir = targetLook
			local targetRight = targetLook:Cross(up).Unit
			local tilt = -ctrl.steerFiltered * 0.24
			local tiltedUp = (up * math.cos(tilt) + targetRight * math.sin(tilt)).Unit
			ctrl.align.Responsiveness = 26
			ctrl.align.CFrame =
				CFrame.fromMatrix(Vector3.zero, tiltedUp:Cross(-targetLook), tiltedUp, -targetLook)

			-- Проецируем текущий импульс на НОВЫЙ курс: появляется реальный боковой снос и инерция
			vForward = vel:Dot(targetLook)
			vRight = vel:Dot(targetRight)

			-- Естественный разгон с горы + мягкая тяга на старте + аэродинамическое сопротивление
			local maxSpeed = if ctrl.boosted then 170 else 130
			if brake then
				local brakeStep = 55 * dt
				if vForward > 6 then
					vForward = math.max(6, vForward - brakeStep)
				else
					vForward *= math.exp(-2.5 * dt)
				end
			else
				if ctrl.boosted then
					vForward = math.min(maxSpeed, vForward + 75 * dt)
				elseif vForward < 65 then
					-- Плавный старт и поддержание хода на пологих участках
					vForward += 18 * dt
				end
				-- Сопротивление воздуха, трение снега и лёгкое торможение в заносе
				local drag = (0.0014 * vForward * math.abs(vForward) + 2.2) * dt
				local slipDrag = math.abs(vRight) * 0.14 * dt
				if vForward > 0 then
					vForward = math.max(0, vForward - drag - slipDrag)
				end
				vForward = math.min(maxSpeed, vForward)
			end

			-- Боковое сцепление полозьев: мягкий карвинг на ходу и контролируемый занос на тормозе
			local grip = if brake then 2.1 else 5.8
			vRight *= math.exp(-grip * dt)

			local vUp = vel:Dot(up)
			ctrl.chassis.AssemblyLinearVelocity = targetLook * vForward
				+ targetRight * vRight
				+ up * vUp
		elseif not ctrl.grounded then
			-- В воздухе позволяем слегка подруливать и мягко держим нос по курсу
			local airYaw = -steer * 1.05 * dt
			local targetLook = (CFrame.fromAxisAngle(Vector3.yAxis, airYaw) * flatLook).Unit
			ctrl.headingDir = targetLook
			ctrl.align.Responsiveness = 12
			ctrl.align.CFrame = CFrame.lookAt(Vector3.zero, targetLook)
		end

		ctrl.forwardSpeed = vForward
		ctrl.lateralSpeed = vRight
	end

	ctrl.speed = ctrl.chassis.AssemblyLinearVelocity.Magnitude
	local projS, projD = SledPhysics3D.Project(track, cf.Position, ctrl.s)
	ctrl.s = projS
	ctrl.d = projD
end

-- Визуальный CFrame санок (слегка смещён вниз от центра коллайдера к уровню полозьев)
function SledPhysics3D.Pose(ctrl: Controller): CFrame
	return ctrl.chassis.CFrame * CFrame.new(0, -0.55, 0)
end

return SledPhysics3D
