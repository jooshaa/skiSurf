--!strict
-- IceFx: скольжение на льду. Движением персонажа владеет клиент, поэтому инерцию даёт он:
-- на льду направление движения не сразу слушается управления (разгон и остановка с заносом).
-- Шанс уронить подарок считает сервер (Hazards).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config") :: ModuleScript) :: any

local player = Players.LocalPlayer

local slide = Vector3.zero -- сглаженное направление движения, длина 0..1
local wasOnIce = false

local function onIce(position: Vector3): boolean
	for _, district in Config.Districts do
		if district.ice then
			local offset = position - district.center
			if
				math.abs(offset.X) <= district.size.X / 2
				and math.abs(offset.Z) <= district.size.Y / 2
			then
				return true
			end
		end
	end
	return false
end

-- Ввод игрока в мировых координатах. Модуль управления каждый кадр (приоритет Input) задаёт
-- направление через Player:Move; читаем его из Humanoid до того, как подменим сглаженным.
local function inputDirection(humanoid: Humanoid): Vector3
	local direction = humanoid.MoveDirection
	return Vector3.new(direction.X, 0, direction.Z)
end

-- После ControlModule (приоритет Input): подменяем направление этого кадра сглаженным
RunService:BindToRenderStep(
	"IceSlide",
	Enum.RenderPriority.Input.Value + 1,
	function(deltaTime: number)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
			wasOnIce = false
			return
		end
		-- Лёд под ногами, а не просто район: в прыжке и на лестнице управление обычное
		local sliding = humanoid.FloorMaterial == Enum.Material.Ice and onIce(root.Position)
		if not sliding then
			if wasOnIce then
				wasOnIce = false
				if humanoid.FloorMaterial ~= Enum.Material.Air then
					player:Move(Vector3.zero, false) -- сошли со льда: не оставляем своё направление
				end
			end
			return
		end
		local wanted = inputDirection(humanoid)
		if not wasOnIce then
			slide = wanted -- въехали на лёд: начинаем с текущего направления
			wasOnIce = true
		end
		slide = slide:Lerp(wanted, math.clamp(deltaTime * Config.Ice.SlideGrip, 0, 1))
		if slide.Magnitude < 0.02 then
			slide = Vector3.zero
		end
		player:Move(slide, false)
	end
)
