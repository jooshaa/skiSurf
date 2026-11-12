--!strict
-- PowerupEffects: визуализация 3D-боксов со знаком «?», полёта 3D-ракет, залпов салюта, взрывов и щитов.
local AssetService = game:GetService("AssetService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Powerups = require(ReplicatedStorage.Powerups)
local SledConfig = require(ReplicatedStorage.SledConfig)
local Track = require(ReplicatedStorage.Track)

local P = SledConfig.Powerups
local A = SledConfig.Assets

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
		root: BasePart,
		inner: BasePart,
		billboard: BillboardGui,
		particles: ParticleEmitter,
		baseY: number,
	},
} =
	{}

local activeRockets: { RocketProjectile } = {}
local activeFireworks: { FireworkProjectile } = {}
local nextProjId = 1

local boxMeshTemplate: MeshPart? = nil
local rocketMeshTemplate: MeshPart? = nil
local fireworkMeshTemplate: MeshPart? = nil
local templatesLoaded = false

local function basePart(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
end

local function loadMeshTemplate(
	name: string,
	meshId: string,
	textureId: string,
	scaleTo: number
): MeshPart?
	if meshId == "" then
		return nil
	end
	local ok, result = pcall(function()
		return (AssetService :: any):CreateMeshPartAsync(Content.fromUri(meshId))
	end)
	if not ok or typeof(result) ~= "Instance" or not result:IsA("MeshPart") then
		return nil
	end
	local mesh = result :: MeshPart
	mesh.Name = name
	mesh.TextureID = textureId
	local maxDim = math.max(mesh.Size.X, mesh.Size.Y, mesh.Size.Z)
	if maxDim > 0 then
		mesh.Size *= (scaleTo / maxDim)
	end
	basePart(mesh)
	return mesh
end

local function preloadTemplates()
	if templatesLoaded then
		return
	end
	templatesLoaded = true

	task.spawn(function()
		local mb = A.MysteryBox
		if mb then
			local loaded = loadMeshTemplate("MysteryBoxMesh", mb.mesh, mb.texture, mb.size)
			if loaded then
				boxMeshTemplate = loaded
				-- Заменяем внутренний куб каждого бокса на настоящую 3D-модель со знаком «?»
				for _, vis in boxVisuals do
					if vis.inner and vis.inner.Parent then
						local clone = loaded:Clone()
						clone.CFrame = vis.inner.CFrame
						clone.Transparency = if vis.root.Transparency >= 1 then 1 else 0
						clone.Parent = vis.root
						vis.inner:Destroy()
						vis.inner = clone
					end
				end
			end
		end
	end)

	task.spawn(function()
		local rk = A.Rocket
		if rk then
			rocketMeshTemplate = loadMeshTemplate("RocketMesh", rk.mesh, rk.texture, rk.length)
		end
	end)

	task.spawn(function()
		local fw = A.Firework
		if fw then
			fireworkMeshTemplate = loadMeshTemplate("FireworkMesh", fw.mesh, fw.texture, fw.length)
		end
	end)
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
	preloadTemplates()

	local boxes = Powerups.GetBoxes(track)
	for _, box in boxes do
		local ground, _, right = Track.At(track, box.s)
		local groundY = ground.Y + right.Y * box.d
		local center = Vector3.new(
			ground.X + right.X * box.d,
			groundY + P.BoxFloat,
			ground.Z + right.Z * box.d
		)

		-- Внешняя неоновая аура вокруг 3D-бокса
		local outer = Instance.new("Part")
		outer.Name = "Box_" .. box.id
		outer.Shape = Enum.PartType.Ball
		outer.Size = P.BoxSize * 1.15
		outer.Position = center
		outer.Color = Color3.fromRGB(255, 210, 50)
		outer.Material = Enum.Material.ForceField
		outer.Transparency = 0.45
		basePart(outer)
		outer.Parent = boxFolder

		-- 3D-модель золотого куба со знаком «?» (или детализированный куб до загрузки меша)
		local inner: BasePart
		if boxMeshTemplate then
			local clone = boxMeshTemplate:Clone()
			clone.Position = center
			clone.Parent = outer
			inner = clone
		else
			local fallback = Instance.new("Part")
			fallback.Name = "Core"
			fallback.Size = P.BoxSize * 0.85
			fallback.Position = center
			fallback.Color = Color3.fromRGB(255, 185, 25)
			fallback.Material = Enum.Material.Neon
			fallback.Transparency = 0.05
			basePart(fallback)
			fallback.Parent = outer
			inner = fallback
		end

		-- Яркий знак «?» над боксом, чтобы его было видно издалека на высокой скорости
		local bb = Instance.new("BillboardGui")
		bb.Name = "QuestionMark"
		bb.Size = UDim2.fromScale(2.8, 2.8)
		bb.StudsOffset = Vector3.new(0, 2.6, 0)
		bb.AlwaysOnTop = false
		bb.MaxDistance = 260
		bb.Adornee = outer

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "?"
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 245, 130)
		label.TextStrokeColor3 = Color3.fromRGB(160, 60, 0)
		label.TextStrokeTransparency = 0
		label.Parent = bb
		bb.Parent = outer

		-- Золотые искры вокруг бокса
		local sparks = Instance.new("ParticleEmitter")
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 230, 80))
		sparks.Rate = 8
		sparks.Lifetime = NumberRange.new(0.6, 1.0)
		sparks.Speed = NumberRange.new(1.5, 3.5)
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

-- Анимация вращения 3D-боксов и их перезарядка
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
				vis.root.Transparency = 0.45
				vis.inner.Transparency = 0
				vis.billboard.Enabled = true
				vis.particles.Enabled = true

				-- Эффект упругого появления
				local targetSize = if boxMeshTemplate
					then boxMeshTemplate.Size
					else P.BoxSize * 0.85
				vis.inner.Size = targetSize * 0.1
				TweenService:Create(
					vis.inner,
					TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{
						Size = targetSize,
					}
				):Play()
			end
		end

		if box.active then
			local bob = math.sin(clock * P.BobRate + box.id * 1.5) * P.BobHeight
			local pos = Vector3.new(vis.root.Position.X, vis.baseY + bob, vis.root.Position.Z)
			local rotY = clock * P.SpinRate + box.id * 0.8
			local rotX = math.sin(clock * 1.5 + box.id) * 0.22

			vis.root.CFrame = CFrame.new(pos) * CFrame.Angles(0, rotY, 0)
			vis.inner.CFrame = CFrame.new(pos) * CFrame.Angles(rotX, rotY * 1.2, 0)
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

-- Собирает 3D-ракету (меш из Studio AI или детализированную составную модель с крыльями и соплом)
local function buildRocketVisual(model: Model, frame: CFrame): Part
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one
	root.Transparency = 1
	root.CFrame = frame
	basePart(root)
	root.Parent = model
	model.PrimaryPart = root

	if rocketMeshTemplate then
		local mesh = rocketMeshTemplate:Clone()
		-- AI-модель ракеты ориентирована носом вверх (+Y), наклоняем её вперёд (-Z)
		mesh.CFrame = frame * CFrame.Angles(-math.pi / 2, 0, 0)
		mesh.Parent = model
	else
		-- Детализированная составная ракета: серебристо-белый корпус, красный обтекатель и 4 стабилизатора
		local fuselage = Instance.new("Part")
		fuselage.Name = "Fuselage"
		fuselage.Shape = Enum.PartType.Cylinder
		fuselage.Size = Vector3.new(2.6, 1.1, 1.1)
		fuselage.Color = Color3.fromRGB(240, 244, 250)
		fuselage.Material = Enum.Material.Metal
		fuselage.CFrame = frame * CFrame.Angles(0, math.pi / 2, 0)
		basePart(fuselage)
		fuselage.Parent = model

		local stripe = Instance.new("Part")
		stripe.Name = "Stripe"
		stripe.Shape = Enum.PartType.Cylinder
		stripe.Size = Vector3.new(0.6, 1.15, 1.15)
		stripe.Color = Color3.fromRGB(230, 40, 40)
		stripe.Material = Enum.Material.SmoothPlastic
		stripe.CFrame = frame * CFrame.new(0, 0, -0.3) * CFrame.Angles(0, math.pi / 2, 0)
		basePart(stripe)
		stripe.Parent = model

		local nose = Instance.new("Part")
		nose.Name = "Nose"
		nose.Shape = Enum.PartType.Ball
		nose.Size = Vector3.new(1.1, 1.1, 1.8)
		nose.Color = Color3.fromRGB(235, 35, 35)
		nose.Material = Enum.Material.SmoothPlastic
		nose.CFrame = frame * CFrame.new(0, 0, -1.4)
		basePart(nose)
		nose.Parent = model

		for finIdx = 1, 4 do
			local angle = (finIdx - 1) * (math.pi / 2)
			local fin = Instance.new("WedgePart")
			fin.Name = "Fin_" .. finIdx
			fin.Size = Vector3.new(0.18, 0.85, 1.1)
			fin.Color = Color3.fromRGB(220, 30, 30)
			fin.Material = Enum.Material.SmoothPlastic
			fin.CFrame = frame
				* CFrame.new(0, 0, 0.9)
				* CFrame.Angles(0, 0, angle)
				* CFrame.new(0, 0.7, 0)
			basePart(fin)
			fin.Parent = model
		end
	end

	local exhaust = Instance.new("Part")
	exhaust.Name = "Exhaust"
	exhaust.Shape = Enum.PartType.Ball
	exhaust.Size = Vector3.new(0.75, 0.75, 0.75)
	exhaust.Color = Color3.fromRGB(255, 160, 30)
	exhaust.Material = Enum.Material.Neon
	exhaust.CFrame = frame * CFrame.new(0, 0, 1.9) * CFrame.Angles(0, math.pi, 0)
	basePart(exhaust)
	exhaust.Parent = model

	-- Реактивная струя пламени и дыма
	local flame = Instance.new("ParticleEmitter")
	flame.LightEmission = 1
	flame.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 140)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 110, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 70, 75)),
	})
	flame.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.0),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	flame.Lifetime = NumberRange.new(0.35, 0.55)
	flame.Speed = NumberRange.new(14, 22)
	flame.SpreadAngle = Vector2.new(14, 14)
	flame.Rate = 60
	flame.Parent = exhaust

	return exhaust
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

	local frame = Track.Frame(track, startS, startD) * CFrame.new(0, 2.4, 0)
	local exhaust = buildRocketVisual(model, frame)

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

-- Создание залпа салюта (3 3D-фейерверка)
function PowerupEffects.SpawnFireworks(track: Track.Data, startS: number, startD: number)
	for i = 1, P.Fireworks.VolleyCount do
		local model = Instance.new("Model")
		model.Name = "Firework_" .. nextProjId
		model.Parent = fxFolder

		local frame = Track.Frame(track, startS, startD) * CFrame.new(0, 2.5, 0)

		local root = Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.one
		root.Transparency = 1
		root.CFrame = frame
		basePart(root)
		root.Parent = model
		model.PrimaryPart = root

		if fireworkMeshTemplate then
			local mesh = fireworkMeshTemplate:Clone()
			mesh.CFrame = frame * CFrame.Angles(-math.pi / 2, 0, 0)
			mesh.Parent = model
		else
			local body = Instance.new("Part")
			body.Shape = Enum.PartType.Cylinder
			body.Size = Vector3.new(2.2, 0.9, 0.9)
			body.Color = Color3.fromRGB(255, 65, 160)
			body.Material = Enum.Material.SmoothPlastic
			body.CFrame = frame * CFrame.Angles(0, math.pi / 2, 0)
			basePart(body)
			body.Parent = model

			local cap = Instance.new("Part")
			cap.Shape = Enum.PartType.Ball
			cap.Size = Vector3.new(1.1, 1.1, 1.3)
			cap.Color = Color3.fromRGB(165, 60, 250)
			cap.Material = Enum.Material.Neon
			cap.CFrame = frame * CFrame.new(0, 0, -1.1)
			basePart(cap)
			cap.Parent = model
		end

		local fuseGlow = Instance.new("Part")
		fuseGlow.Name = "FuseGlow"
		fuseGlow.Shape = Enum.PartType.Ball
		fuseGlow.Size = Vector3.new(0.65, 0.65, 0.65)
		fuseGlow.Color = Color3.fromRGB(255, 220, 70)
		fuseGlow.Material = Enum.Material.Neon
		fuseGlow.CFrame = frame * CFrame.new(0, 0, 1.4)
		basePart(fuseGlow)
		fuseGlow.Parent = model

		-- Искрящийся шлейф фейерверка
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.LightEmission = 1
		sparkle.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 80)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 60, 200)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 220, 255)),
		})
		sparkle.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.85),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkle.Lifetime = NumberRange.new(0.4, 0.6)
		sparkle.Speed = NumberRange.new(8, 14)
		sparkle.Rate = 45
		sparkle.Parent = fuseGlow

		local spreadAngle = P.Fireworks.SpreadAngles[i] or 0
		local lateralVel = math.tan(spreadAngle) * P.Fireworks.Speed

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

		local surface = Track.Frame(track, r.s, r.d) * CFrame.new(0, 2.4, 0)
		r.model:PivotTo(surface)

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
		f.model:PivotTo(surface)

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
