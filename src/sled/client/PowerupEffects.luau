--!strict
-- PowerupEffects: визуализация боксов со знаком «?», полёта ракет, залпов салюта, взрывов и щитов.
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
	s: number,
	d: number,
	speed: number,
	targetSledId: string?, -- ID цели (бота или игрока)
	distanceTraveled: number,
	model: Model,
	flamePart: Part,
}

export type FireworkProjectile = {
	id: number,
	s: number,
	d: number,
	lateralVelocity: number,
	speed: number,
	distanceTraveled: number,
	model: Model,
}

local PowerupEffects = {}

local boxFolder: Folder
local fxFolder: Folder
local boxVisuals: {
	[number]: {
		root: Part,
		inner: Part,
		billboard: BillboardGui,
		particles: ParticleEmitter,
		baseY: number,
	},
} =
	{}

local activeRockets: { RocketProjectile } = {}
local activeFireworks: { FireworkProjectile } = {}
local nextProjId = 1

local function basePart(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
end

-- Создание папок для визуалов и эффектов
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

	local boxes = Powerups.GetBoxes(track)
	for _, box in boxes do
		local ground, _, right = Track.At(track, box.s)
		local groundY = ground.Y + right.Y * box.d
		local center = Vector3.new(
			ground.X + right.X * box.d,
			groundY + P.BoxFloat,
			ground.Z + right.Z * box.d
		)

		local outer = Instance.new("Part")
		outer.Name = "Box_" .. box.id
		outer.Size = P.BoxSize
		outer.Position = center
		outer.Color = Color3.fromRGB(255, 195, 35)
		outer.Material = Enum.Material.Neon
		outer.Transparency = 0.25
		basePart(outer)
		outer.Parent = boxFolder

		-- Внутренний кристалл
		local inner = Instance.new("Part")
		inner.Name = "Core"
		inner.Size = P.BoxSize * 0.65
		inner.Position = center
		inner.Color = Color3.fromRGB(255, 120, 20)
		inner.Material = Enum.Material.Neon
		inner.Transparency = 0.1
		basePart(inner)
		inner.Parent = outer

		-- Знак «?» на боксе
		local bb = Instance.new("BillboardGui")
		bb.Name = "QuestionMark"
		bb.Size = UDim2.fromScale(3.2, 3.2)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 250
		bb.Adornee = outer

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "?"
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextStrokeColor3 = Color3.fromRGB(180, 70, 0)
		label.TextStrokeTransparency = 0
		label.Parent = bb
		bb.Parent = outer

		-- Золотые искры вокруг бокса
		local sparks = Instance.new("ParticleEmitter")
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 230, 80))
		sparks.Rate = 6
		sparks.Lifetime = NumberRange.new(0.6, 1.0)
		sparks.Speed = NumberRange.new(1, 3)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Parent = outer

		boxVisuals[box.id] = {
			root = outer,
			inner = inner,
			billboard = bb,
			particles = sparks,
			baseY = center.Y,
		}
	end
end

-- Анимация вращения боксов и их перезарядка
function PowerupEffects.UpdateBoxes(boxes: { Powerups.Box }, dt: number, clock: number)
	for _, box in boxes do
		local vis = boxVisuals[box.id]
		if not vis then
			continue
		end

		if box.cooldown > 0 then
			box.cooldown -= dt
			if box.cooldown <= 0 then
				box.active = true
				vis.root.Transparency = 0.25
				vis.inner.Transparency = 0.1
				vis.billboard.Enabled = true
				vis.particles.Enabled = true

				-- Эффект хлопка при появлении
				local origSize = P.BoxSize
				vis.root.Size = origSize * 0.1
				TweenService:Create(
					vis.root,
					TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{
						Size = origSize,
					}
				):Play()
			end
		end

		if box.active then
			local bob = math.sin(clock * P.BobRate + box.id * 1.5) * P.BobHeight
			local pos = Vector3.new(vis.root.Position.X, vis.baseY + bob, vis.root.Position.Z)
			local rotY = clock * P.SpinRate + box.id * 0.8
			local rotX = math.sin(clock * 1.5 + box.id) * 0.25

			vis.root.CFrame = CFrame.new(pos) * CFrame.Angles(rotX, rotY, 0)
			vis.inner.CFrame = CFrame.new(pos) * CFrame.Angles(-rotX, -rotY * 1.3, math.pi / 4)
		end
	end
end

-- Эффект подбора бокса
function PowerupEffects.PopBox(boxId: number)
	local vis = boxVisuals[boxId]
	if not vis then
		return
	end

	vis.root.Transparency = 1
	vis.inner.Transparency = 1
	vis.billboard.Enabled = false
	vis.particles.Enabled = false

	-- Взрыв звезд и искр при подборе
	local burstPart = Instance.new("Part")
	burstPart.Size = Vector3.new(1, 1, 1)
	burstPart.Position = vis.root.Position
	burstPart.Transparency = 1
	basePart(burstPart)
	burstPart.Parent = fxFolder

	local popEmitter = Instance.new("ParticleEmitter")
	popEmitter.LightEmission = 1
	popEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 100)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 120, 20)),
	})
	popEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	popEmitter.Lifetime = NumberRange.new(0.5, 0.8)
	popEmitter.Speed = NumberRange.new(8, 18)
	popEmitter.SpreadAngle = Vector2.new(180, 180)
	popEmitter.Rate = 0
	popEmitter.Parent = burstPart

	popEmitter:Emit(25)
	Debris:AddItem(burstPart, 1.2)
end

-- Создание ракеты (Rocket)
function PowerupEffects.SpawnRocket(
	track: Track.Data,
	startS: number,
	startD: number,
	targetSledId: string?
): RocketProjectile
	local model = Instance.new("Model")
	model.Name = "Rocket_" .. nextProjId
	model.Parent = fxFolder

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(1.4, 1.4, 3.2)
	body.Color = Color3.fromRGB(240, 45, 45)
	body.Material = Enum.Material.SmoothPlastic
	basePart(body)
	body.Parent = model

	local nose = Instance.new("Part")
	nose.Name = "Nose"
	nose.Size = Vector3.new(1.2, 1.2, 1.4)
	nose.Color = Color3.fromRGB(255, 255, 255)
	nose.Material = Enum.Material.SmoothPlastic
	basePart(nose)
	nose.Parent = model

	local exhaust = Instance.new("Part")
	exhaust.Name = "Exhaust"
	exhaust.Size = Vector3.new(0.6, 0.6, 0.6)
	exhaust.Transparency = 1
	basePart(exhaust)
	exhaust.Parent = model

	-- Шлейф пламени и дыма из ракеты
	local flame = Instance.new("ParticleEmitter")
	flame.LightEmission = 1
	flame.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 120)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 120, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 80, 80)),
	})
	flame.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	flame.Lifetime = NumberRange.new(0.35, 0.55)
	flame.Speed = NumberRange.new(12, 18)
	flame.SpreadAngle = Vector2.new(15, 15)
	flame.Rate = 50
	flame.Parent = exhaust

	local frame = Track.Frame(track, startS, startD) * CFrame.new(0, 2.2, 0)
	body.CFrame = frame
	nose.CFrame = frame * CFrame.new(0, 0, -2.1)
	exhaust.CFrame = frame * CFrame.new(0, 0, 1.7) * CFrame.Angles(0, math.pi, 0)

	local proj: RocketProjectile = {
		id = nextProjId,
		s = startS,
		d = startD,
		speed = P.Rocket.Speed,
		targetSledId = targetSledId,
		distanceTraveled = 0,
		model = model,
		flamePart = exhaust,
	}

	nextProjId += 1
	table.insert(activeRockets, proj)
	return proj
end

-- Создание залпа салюта (3 фейерверка)
function PowerupEffects.SpawnFireworks(track: Track.Data, startS: number, startD: number)
	for i = 1, P.Fireworks.VolleyCount do
		local model = Instance.new("Model")
		model.Name = "Firework_" .. nextProjId
		model.Parent = fxFolder

		local shell = Instance.new("Part")
		shell.Size = Vector3.new(1.2, 1.2, 1.8)
		shell.Color = Color3.fromRGB(255, 70, 180)
		shell.Material = Enum.Material.Neon
		basePart(shell)
		shell.Parent = model

		-- Искрящийся шлейф фейерверка
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.LightEmission = 1
		sparkle.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 80)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 60, 200)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 220, 255)),
		})
		sparkle.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkle.Lifetime = NumberRange.new(0.4, 0.6)
		sparkle.Speed = NumberRange.new(8, 14)
		sparkle.Rate = 40
		sparkle.Parent = shell

		local spreadAngle = P.Fireworks.SpreadAngles[i] or 0
		local lateralVel = math.tan(spreadAngle) * P.Fireworks.Speed

		local frame = Track.Frame(track, startS, startD) * CFrame.new(0, 2.5, 0)
		shell.CFrame = frame

		local proj: FireworkProjectile = {
			id = nextProjId,
			s = startS,
			d = startD,
			lateralVelocity = lateralVel,
			speed = P.Fireworks.Speed,
			distanceTraveled = 0,
			model = model,
		}

		nextProjId += 1
		table.insert(activeFireworks, proj)
	end
end

-- Красивый взрыв в точке (универсальный для ракет и салюта)
function PowerupEffects.Explosion(position: Vector3, isFirework: boolean)
	local boomPart = Instance.new("Part")
	boomPart.Size = Vector3.new(2, 2, 2)
	boomPart.Position = position
	boomPart.Transparency = 1
	basePart(boomPart)
	boomPart.Parent = fxFolder

	-- Световая сфера взрыва
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(3, 3, 3)
	flash.Position = position
	flash.Color = if isFirework then Color3.fromRGB(255, 100, 255) else Color3.fromRGB(255, 200, 50)
	flash.Material = Enum.Material.Neon
	flash.Transparency = 0.2
	basePart(flash)
	flash.Parent = fxFolder

	TweenService
		:Create(flash, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(16, 16, 16),
			Transparency = 1,
		})
		:Play()
	Debris:AddItem(flash, 0.3)

	-- Огненные и разноцветные осколки
	local blast = Instance.new("ParticleEmitter")
	blast.LightEmission = 1
	if isFirework then
		blast.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(80, 255, 120)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(60, 180, 255)),
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
		NumberSequenceKeypoint.new(0, 2.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	blast.Lifetime = NumberRange.new(0.6, 1.2)
	blast.Speed = NumberRange.new(16, 32)
	blast.SpreadAngle = Vector2.new(180, 180)
	blast.Rate = 0
	blast.Parent = boomPart

	blast:Emit(if isFirework then 60 else 45)
	Debris:AddItem(boomPart, 1.5)
end

-- Обновление полёта ракет и фейерверков
function PowerupEffects.UpdateProjectiles(
	track: Track.Data,
	dt: number,
	racers: { { id: string, s: number, d: number, onHit: () -> () } }
)
	-- Ракеты
	for i = #activeRockets, 1, -1 do
		local r = activeRockets[i]
		local ds = r.speed * dt
		r.s += ds
		r.distanceTraveled += ds

		-- Наведение на цель (если цель есть и впереди)
		local targetRacer: any = nil
		if r.targetSledId then
			for _, racer in racers do
				if racer.id == r.targetSledId then
					targetRacer = racer
					break
				end
			end
		end

		if targetRacer and targetRacer.s > r.s then
			-- Плавно подруливаем поперек трассы в сторону цели
			r.d += (targetRacer.d - r.d) * math.clamp(dt * 5.0, 0, 1)
		end

		local surface = Track.Frame(track, r.s, r.d) * CFrame.new(0, 2.2, 0)
		local body = r.model:FindFirstChild("Body") :: Part?
		local nose = r.model:FindFirstChild("Nose") :: Part?
		local exhaust = r.model:FindFirstChild("Exhaust") :: Part?
		if body and nose and exhaust then
			body.CFrame = surface
			nose.CFrame = surface * CFrame.new(0, 0, -2.1)
			exhaust.CFrame = surface * CFrame.new(0, 0, 1.7) * CFrame.Angles(0, math.pi, 0)
		end

		-- Проверка попадания в гонщиков
		local hit = false
		for _, racer in racers do
			if
				math.abs(racer.s - r.s) < P.Rocket.HitRadius
				and math.abs(racer.d - r.d) < P.Rocket.HitRadius
			then
				hit = true
				PowerupEffects.Explosion(surface.Position, false)
				racer.onHit()
				break
			end
		end

		-- Взрыв по превышению дальности или финишу
		if not hit and (r.distanceTraveled >= P.Rocket.MaxRange or r.s >= track.finishS) then
			hit = true
			PowerupEffects.Explosion(surface.Position, false)
		end

		if hit then
			r.model:Destroy()
			table.remove(activeRockets, i)
		end
	end

	-- Фейерверки (Салют)
	for i = #activeFireworks, 1, -1 do
		local f = activeFireworks[i]
		local ds = f.speed * dt
		f.s += ds
		f.d += f.lateralVelocity * dt
		f.distanceTraveled += ds

		local surface = Track.Frame(track, f.s, f.d) * CFrame.new(0, 2.5, 0)
		local shell = f.model:FindFirstChildOfClass("Part")
		if shell then
			shell.CFrame = surface
		end

		local hit = false
		for _, racer in racers do
			if
				math.abs(racer.s - f.s) < P.Fireworks.ExplosionRadius
				and math.abs(racer.d - f.d) < P.Fireworks.ExplosionRadius
			then
				hit = true
				PowerupEffects.Explosion(surface.Position, true)
				racer.onHit()
				break
			end
		end

		if not hit and (f.distanceTraveled >= P.Fireworks.Range or f.s >= track.finishS) then
			hit = true
			PowerupEffects.Explosion(surface.Position, true)
		end

		if hit then
			f.model:Destroy()
			table.remove(activeFireworks, i)
		end
	end
end

-- Создание купола ледяного щита вокруг санок
function PowerupEffects.CreateShield(sledModel: Model): Part
	local shield = Instance.new("Part")
	shield.Name = "IceShield"
	shield.Shape = Enum.PartType.Ball
	shield.Size = Vector3.new(8.5, 8.5, 8.5)
	shield.Color = Color3.fromRGB(120, 220, 255)
	shield.Material = Enum.Material.ForceField
	shield.Transparency = 0.4
	basePart(shield)
	shield.Parent = sledModel
	return shield
end

return PowerupEffects
