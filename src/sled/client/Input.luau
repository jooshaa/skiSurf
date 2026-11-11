--!strict
-- Input: два действия игрока. Руль: палец на левой половине экрана, сдвиг влево-вправо.
-- Тормоз: палец на правой половине. На ПК: A/D или стрелки, пробел или S. Мышь работает как палец.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local SledConfig = require(ReplicatedStorage.SledConfig)

local I = SledConfig.Input

local Input = {}

local steerTouch: InputObject? = nil
local steerOrigin = 0
local steerRaw = 0 -- -1..1 от пальца
local brakeTouches: { [InputObject]: boolean } = {}
local mouseSteer = false
local mouseBrake = false
local keySteer = 0

local function screenWidth(): number
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize.X else 1000
end

local function isLeftHalf(x: number): boolean
	return x < screenWidth() / 2
end

local function beginSteer(x: number)
	steerOrigin = x
	steerRaw = 0
end

local function moveSteer(x: number)
	local range = I.SteerRange * screenWidth()
	-- Плавающий центр: если палец ушёл дальше упора, центр едет за ним, и обратный ход сразу рулит
	if x - steerOrigin > range then
		steerOrigin = x - range
	elseif steerOrigin - x > range then
		steerOrigin = x + range
	end
	steerRaw = (x - steerOrigin) / range
end

local function isPointer(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return -- нажатие по кнопке или ползунку панели
	end
	if input.UserInputType == Enum.UserInputType.Touch then
		if isLeftHalf(input.Position.X) then
			if not steerTouch then
				steerTouch = input
				beginSteer(input.Position.X)
			end
		else
			brakeTouches[input] = true
		end
	elseif isPointer(input) then
		if isLeftHalf(input.Position.X) then
			mouseSteer = true
			beginSteer(input.Position.X)
		else
			mouseBrake = true
		end
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		if input == steerTouch then
			moveSteer(input.Position.X)
		end
	elseif input.UserInputType == Enum.UserInputType.MouseMovement and mouseSteer then
		moveSteer(input.Position.X)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		if input == steerTouch then
			steerTouch = nil
			steerRaw = 0
		end
		brakeTouches[input] = nil
	elseif isPointer(input) then
		if mouseSteer then
			steerRaw = 0
		end
		mouseSteer = false
		mouseBrake = false
	end
end)

local function keyDown(a: Enum.KeyCode, b: Enum.KeyCode): boolean
	return UserInputService:IsKeyDown(a) or UserInputService:IsKeyDown(b)
end

-- Вызывать раз в кадр: клавиатурный руль доходит до упора плавно
function Input.Update(dt: number)
	local target = 0
	if keyDown(Enum.KeyCode.A, Enum.KeyCode.Left) then
		target -= 1
	end
	if keyDown(Enum.KeyCode.D, Enum.KeyCode.Right) then
		target += 1
	end
	local rate = if target == 0 then I.KeyRampDown else I.KeyRampUp
	local change = rate * dt
	keySteer += math.clamp(target - keySteer, -change, change)
end

-- Руль от -1 (влево) до 1 (вправо)
function Input.Steer(): number
	if steerTouch or mouseSteer then
		local size = math.abs(steerRaw)
		if size < I.DeadZone then
			return 0
		end
		local scaled = (size - I.DeadZone) / (1 - I.DeadZone)
		return math.sign(steerRaw) * math.clamp(scaled, 0, 1) ^ I.SteerCurve
	end
	return keySteer
end

function Input.Brake(): boolean
	return mouseBrake
		or next(brakeTouches) ~= nil
		or keyDown(Enum.KeyCode.Space, Enum.KeyCode.S)
		or UserInputService:IsKeyDown(Enum.KeyCode.Down)
end

return Input
