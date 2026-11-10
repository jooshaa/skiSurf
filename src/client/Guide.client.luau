--!strict
-- Guide: стрелки первой минуты. Текста нет: прыгающая стрелка над целью и луч от игрока к ней.
-- Цель и шаг задаёт сервер атрибутами TutorialStage и TutorialTarget.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config") :: ModuleScript) :: any

local F = Config.FirstMinute

local player = Players.LocalPlayer

-- Невидимая опора в точке цели: на ней стрелка и конец луча
local anchor = Instance.new("Part")
anchor.Name = "GuideTarget"
anchor.Size = Vector3.new(1, 1, 1)
anchor.Transparency = 1
anchor.Anchored = true
anchor.CanCollide = false
anchor.CanQuery = false
anchor.CanTouch = false

local targetAttachment = Instance.new("Attachment")
targetAttachment.Parent = anchor

local arrow = Instance.new("BillboardGui")
arrow.Name = "Arrow"
arrow.Size = UDim2.fromOffset(90, 90)
arrow.AlwaysOnTop = true
arrow.MaxDistance = 1000
arrow.Parent = anchor
local arrowLabel = Instance.new("TextLabel")
arrowLabel.Size = UDim2.fromScale(1, 1)
arrowLabel.BackgroundTransparency = 1
arrowLabel.Text = "⬇️"
arrowLabel.TextScaled = true
arrowLabel.Font = Enum.Font.GothamBold
arrowLabel.Parent = arrow

local beam = Instance.new("Beam")
beam.Name = "GuideBeam"
beam.Width0 = 1.2
beam.Width1 = 1.2
beam.FaceCamera = true
beam.LightEmission = 1
beam.Color = ColorSequence.new(Color3.fromRGB(255, 220, 60))
beam.Transparency = NumberSequence.new(0.3)
beam.Attachment1 = targetAttachment
beam.Parent = anchor

local function attachToCharacter(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root and root:IsA("BasePart") then
		local attachment = Instance.new("Attachment")
		attachment.Name = "GuideOrigin"
		attachment.Parent = root
		beam.Attachment0 = attachment
	end
end

local function refresh()
	local stage = player:GetAttribute("TutorialStage")
	local target = player:GetAttribute("TutorialTarget")
	if type(stage) == "number" and stage > 0 and typeof(target) == "Vector3" then
		anchor.Position = target + Vector3.new(0, 1, 0)
		anchor.Parent = Workspace
	else
		anchor.Parent = nil
	end
end

player.CharacterAdded:Connect(attachToCharacter)
if player.Character then
	task.spawn(attachToCharacter, player.Character)
end
player:GetAttributeChangedSignal("TutorialStage"):Connect(refresh)
player:GetAttributeChangedSignal("TutorialTarget"):Connect(refresh)
refresh()

-- Стрелка подпрыгивает над целью
RunService.Heartbeat:Connect(function()
	if anchor.Parent then
		local bounce = math.sin(os.clock() * F.ArrowBounceSpeed) * F.ArrowBounce
		arrow.StudsOffset = Vector3.new(0, F.ArrowHeight + bounce, 0)
	end
end)
