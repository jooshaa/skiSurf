--!strict
-- SnowFx: снегопад. Невидимая плита летит над камерой и сыплет снежинки вокруг игрока.
-- Только картинка: на игру не влияет.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config") :: ModuleScript) :: any

local S = Config.Map.Snowfall

local cloud = Instance.new("Part")
cloud.Name = "SnowCloud"
cloud.Size = Vector3.new(S.Area, 1, S.Area)
cloud.Transparency = 1
cloud.Anchored = true
cloud.CanCollide = false
cloud.CanQuery = false
cloud.CanTouch = false

local emitter = Instance.new("ParticleEmitter")
emitter.Name = "Snow"
emitter.Rate = S.Rate
emitter.Lifetime = NumberRange.new(S.Lifetime * 0.8, S.Lifetime)
emitter.Speed = NumberRange.new(S.Speed * 0.7, S.Speed)
emitter.EmissionDirection = Enum.NormalId.Bottom
emitter.SpreadAngle = Vector2.new(12, 12)
emitter.Size = NumberSequence.new(S.Size)
emitter.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.1, 0.15),
	NumberSequenceKeypoint.new(0.85, 0.15),
	NumberSequenceKeypoint.new(1, 1),
})
emitter.Color = ColorSequence.new(Color3.new(1, 1, 1))
emitter.LightEmission = 0.4
emitter.Rotation = NumberRange.new(0, 360)
emitter.RotSpeed = NumberRange.new(-40, 40)
emitter.Acceleration = Vector3.new(1.5, 0, 0.8) -- лёгкий ветер
emitter.Parent = cloud

cloud.Parent = Workspace

RunService.RenderStepped:Connect(function()
	local camera = Workspace.CurrentCamera
	if camera then
		cloud.Position = camera.CFrame.Position + Vector3.new(0, S.Height, 0)
	end
end)
