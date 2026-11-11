--!strict
-- SledView: всё, что видно на санках и вокруг них. Модель санок (готовая 3D-модель, а пока она
-- грузится или если не загрузилась, простая из блоков), снег из-под полозьев, шлейф в повороте,
-- следы на снегу, облако при приземлении и снегопад вокруг игрока. Только картинка.
local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local SledConfig = require(ReplicatedStorage.SledConfig)

local S = SledConfig.Sled
local F = SledConfig.Fx
local W = SledConfig.Snowfall

local PUFF = "rbxasset://textures/particles/smoke_main.dds" -- встроенная текстура движка

local SledView = {}

local sled: Model
local root: Part
local bodyParts: { BasePart } = {} -- видимые части: мигают после респауна
local rearSprays: { ParticleEmitter } = {}
local carveLeft: ParticleEmitter
local carveRight: ParticleEmitter
local landing: ParticleEmitter
local trails: { Trail } = {}
local snowCloud: Part
local shownHidden = false

local function basePart(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
end

local function block(size: Vector3, offset: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Size = size
	part.CFrame = root.CFrame * offset
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	basePart(part)
	part.Parent = sled
	table.insert(bodyParts, part)
	return part
end

-- Запасные санки из блоков
local function buildBlocks()
	local runnerY = S.Runner.Y / 2
	block(S.Board, CFrame.new(0, S.Runner.Y + S.Board.Y / 2, 0), S.Color)
	for _, side in { -1, 1 } do
		local x = side * (S.Board.X / 2 - S.Runner.X / 2)
		block(S.Runner, CFrame.new(x, runnerY, 0), S.RunnerColor)
		block(
			Vector3.new(S.Runner.X, S.Runner.Y, S.NoseLength),
			CFrame.new(x, runnerY + S.NoseLift, -S.Runner.Z / 2 - S.NoseLength / 3)
				* CFrame.Angles(S.NoseAngle, 0, 0),
			S.RunnerColor
		)
	end
end

-- Готовая 3D-модель по номеру из конфига; nil, если номера нет или модель не загрузилась
local function loadAsset(name: string, meshId: string, textureId: string): MeshPart?
	if meshId == "" then
		return nil
	end
	local ok, result = pcall(function()
		return (AssetService :: any):CreateMeshPartAsync(Content.fromUri(meshId))
	end)
	if not ok or typeof(result) ~= "Instance" or not result:IsA("MeshPart") then
		warn(
			string.format(
				"[SledView] модель %s не загрузилась: %s",
				name,
				tostring(result)
			)
		)
		return nil
	end
	local mesh = result :: MeshPart
	mesh.Name = name
	mesh.TextureID = textureId
	return mesh
end

-- Модель санок: при удаче блоки убираются
local function loadSled()
	local asset = SledConfig.Assets.Sled
	local mesh = loadAsset("Body", asset.mesh, asset.texture)
	if not mesh then
		return
	end
	mesh.Size *= asset.length / math.max(mesh.Size.X, mesh.Size.Z)
	basePart(mesh)
	mesh.CFrame = root.CFrame
		* CFrame.new(0, mesh.Size.Y / 2 + asset.lift, 0)
		* CFrame.Angles(0, math.rad(asset.yaw), 0)
	for _, part in bodyParts do
		part:Destroy()
	end
	table.clear(bodyParts)
	mesh.Transparency = if shownHidden then F.BlinkTransparency else 0
	mesh.Parent = sled
	table.insert(bodyParts, mesh)
end

local helmetTemplate: MeshPart? = nil
local helmetLoading = false
local HELMET_NAME = "SledHelmet"

-- Персонаж ещё тот же и жив? После каждого ожидания он мог смениться.
local function isCurrent(character: Model): boolean
	return character.Parent ~= nil and Players.LocalPlayer.Character == character
end

-- Шлем с очками на голову персонажа. Чужого игрока не касается: это только свой райдер.
function SledView.AttachHelmet(character: Model)
	while helmetLoading do
		task.wait() -- модель уже грузит другой вызов (персонаж возродился): ждём её
	end
	if not helmetTemplate then
		helmetLoading = true
		local asset = SledConfig.Assets.Helmet
		local loaded = loadAsset(HELMET_NAME, asset.mesh, asset.texture)
		if loaded then
			loaded.Size *= asset.width / math.max(loaded.Size.X, loaded.Size.Z)
		end
		helmetTemplate = loaded -- nil при неудаче: следующий персонаж попробует снова
		helmetLoading = false
	end
	local head = character:WaitForChild("Head", SledConfig.Run.CharacterTimeout)
	if not helmetTemplate or not head or not head:IsA("BasePart") or not isCurrent(character) then
		return
	end
	if character:FindFirstChild(HELMET_NAME) then
		return
	end
	local asset = SledConfig.Assets.Helmet
	local helmet = helmetTemplate:Clone()
	helmet.Anchored = false
	helmet.Massless = true
	helmet.CanCollide = false
	helmet.CanTouch = false
	helmet.CanQuery = false
	helmet.CFrame = head.CFrame
		* CFrame.new(asset.offset)
		* CFrame.Angles(0, math.rad(asset.yaw), 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = helmet
	weld.Parent = helmet
	helmet.Parent = character

	if asset.hideHair then
		local function hide(item: Instance)
			if not item:IsA("Accessory") then
				return
			end
			local kind = item.AccessoryType
			if kind == Enum.AccessoryType.Hair or kind == Enum.AccessoryType.Hat then
				-- Аксессуар может появиться раньше своей детали: ждём её
				local handle = item:WaitForChild("Handle", SledConfig.Run.CharacterTimeout)
				if handle and handle:IsA("BasePart") then
					handle.Transparency = 1 -- только у себя на экране, аватар не меняется
				end
			end
		end
		for _, item in character:GetChildren() do
			task.spawn(hide, item)
		end
		character.ChildAdded:Connect(function(item)
			task.spawn(hide, item) -- аксессуары могут догрузиться позже
		end)
	end
end

local function emitter(
	parent: Instance,
	size: number,
	lifetime: number,
	speed: number
): ParticleEmitter
	local item = Instance.new("ParticleEmitter")
	item.Texture = PUFF
	item.Color = ColorSequence.new(F.SnowColor)
	item.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * F.PuffStart),
		NumberSequenceKeypoint.new(1, size),
	})
	item.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, F.PuffTransparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	item.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	item.Speed = NumberRange.new(speed * 0.6, speed)
	item.SpreadAngle = Vector2.new(F.Spread, F.Spread)
	item.Rotation = NumberRange.new(0, 360)
	item.RotSpeed = NumberRange.new(-90, 90)
	item.Acceleration = Vector3.new(0, -F.PuffGravity, 0)
	item.LightEmission = F.PuffGlow
	item.VelocityInheritance = F.Inherit
	item.Rate = 0
	item.Parent = parent
	return item
end

local function attachment(position: Vector3, tilt: number): Attachment
	local item = Instance.new("Attachment")
	-- Частицы летят вдоль оси Y крепления: tilt наклоняет её вбок от санок
	item.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, tilt)
	item.Parent = root
	return item
end

local function buildEffects()
	local halfWidth = S.Board.X / 2
	local rear = S.Runner.Z / 2
	for _, side in { -1, 1 } do
		-- Снежная пыль из-под задних концов полозьев, чуть назад
		local back = attachment(Vector3.new(side * halfWidth, F.EmitHeight, rear), 0)
		back.CFrame *= CFrame.Angles(F.RearTilt, 0, 0)
		table.insert(rearSprays, emitter(back, F.SpraySize, F.SprayLife, F.SpraySpeed))

		-- След полоза: плоская лента на снегу
		local inner =
			attachment(Vector3.new(side * (halfWidth - F.TrailWidth), F.TrailHeight, rear), 0)
		local outer = attachment(Vector3.new(side * halfWidth, F.TrailHeight, rear), 0)
		local trail = Instance.new("Trail")
		trail.Attachment0 = inner
		trail.Attachment1 = outer
		trail.FaceCamera = false
		trail.Lifetime = F.TrailLife
		trail.Color = ColorSequence.new(F.TrailColor)
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, F.TrailTransparency),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.LightInfluence = 1
		trail.Enabled = false
		trail.Parent = root
		table.insert(trails, trail)
	end

	-- Шлейф в повороте: снег летит наружу с той стороны, которой санки упираются в снег
	local left = attachment(Vector3.new(-halfWidth, F.EmitHeight, rear * F.CarveBack), F.CarveTilt)
	local right = attachment(Vector3.new(halfWidth, F.EmitHeight, rear * F.CarveBack), -F.CarveTilt)
	carveLeft = emitter(left, F.CarveSize, F.CarveLife, F.CarveSpeed)
	carveRight = emitter(right, F.CarveSize, F.CarveLife, F.CarveSpeed)

	local centre = attachment(Vector3.new(0, F.EmitHeight, 0), 0)
	landing = emitter(centre, F.LandSize, F.LandLife, F.LandSpeed)
	landing.SpreadAngle = Vector2.new(F.LandSpread, F.LandSpread)
end

-- Снегопад: снежинки рождаются сразу во всём объёме вокруг точки, куда игрок сейчас приедет.
-- На скорости они проносятся мимо камеры, и это главный признак скорости.
local function buildSnowfall()
	snowCloud = Instance.new("Part")
	snowCloud.Name = "SnowCloud"
	snowCloud.Size = Vector3.new(W.Area, W.Height, W.Area)
	snowCloud.Transparency = 1
	basePart(snowCloud)

	local snow = Instance.new("ParticleEmitter")
	snow.Name = "Snow"
	snow.Rate = if UserInputService.TouchEnabled then W.Rate * W.TouchRateShare else W.Rate
	snow.Lifetime = NumberRange.new(W.Lifetime * 0.7, W.Lifetime)
	snow.Speed = NumberRange.new(W.Speed * 0.6, W.Speed)
	snow.EmissionDirection = Enum.NormalId.Bottom
	snow.SpreadAngle = Vector2.new(W.Spread, W.Spread)
	snow.Size = NumberSequence.new(W.Size)
	snow.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, W.Transparency),
		NumberSequenceKeypoint.new(0.8, W.Transparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	snow.Color = ColorSequence.new(Color3.new(1, 1, 1))
	snow.LightEmission = W.Glow
	snow.Rotation = NumberRange.new(0, 360)
	snow.Acceleration = W.Wind
	snow.Parent = snowCloud
	snowCloud.Parent = Workspace
end

function SledView.Create()
	sled = Instance.new("Model")
	sled.Name = "Sled"
	root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one
	root.Transparency = 1
	basePart(root)
	root.Parent = sled
	sled.PrimaryPart = root
	buildBlocks()
	buildEffects()
	buildSnowfall()
	sled.Parent = Workspace
	task.spawn(loadSled)
end

function SledView.SetPose(frame: CFrame)
	sled:PivotTo(frame)
end

-- Санки перенесли (старт, респаун): следы не должны тянуться через всю гору
function SledView.Cut()
	for _, trail in trails do
		trail:Clear()
	end
end

-- Облако снега при приземлении; strength от 0 до 1
function SledView.Land(strength: number)
	landing:Emit(math.round(F.LandCount * math.clamp(strength, 0, 1)))
end

-- Раз в кадр. sliding: санки едут по снегу (не в полёте и не в кувырке); slip: угол заноса (+ нос
-- правее движения); velocity: скорость санок в мире; hidden: фаза мигания после респауна
function SledView.Update(
	speed: number,
	slip: number,
	steer: number,
	brake: boolean,
	sliding: boolean,
	velocity: Vector3,
	hidden: boolean
)
	local spray = 0
	local left = 0
	local right = 0
	if sliding then
		spray = speed * F.SprayPerSpeed + (if brake then F.SprayBrake else 0)
		local carve = speed * F.CarvePerSpeed
		-- Нос правее движения: санки упираются левым бортом, снег летит влево. Руль добавляет чуть-чуть.
		left = math.max(0, slip + steer * F.CarveSteer) * carve
		right = math.max(0, -slip - steer * F.CarveSteer) * carve
	end
	for _, item in rearSprays do
		item.Rate = math.min(spray, F.SprayMax)
	end
	carveLeft.Rate = math.min(left, F.CarveMax)
	carveRight.Rate = math.min(right, F.CarveMax)
	for _, trail in trails do
		trail.Enabled = sliding
	end

	if hidden ~= shownHidden then
		shownHidden = hidden
		for _, part in bodyParts do
			part.Transparency = if hidden then F.BlinkTransparency else 0
		end
	end

	-- Скорость на закреплённой детали ничего не двигает, но её наследуют частицы
	root.AssemblyLinearVelocity = velocity

	local camera = Workspace.CurrentCamera
	if camera then
		snowCloud.Position = camera.CFrame.Position + velocity * W.LeadTime
	end
end

return SledView
