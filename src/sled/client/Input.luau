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
local cameraTouch: InputObject? = nil
local cameraLast = Vector3.zero
local mouseCamera = false
local cameraX = 0 -- накопленный сдвиг для камеры, пикселей
local cameraY = 0
local cameraZoom = 0 -- накопленные щелчки колёсика

local function screenWidth(): number
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize.X else 1000
end

local function isLeftHalf(x: number): boolean
	return x < screenWidth() / 2
end

-- Верхняя часть экрана отдана камере: большие пальцы рулят и тормозят внизу
local function isCameraZone(y: number): boolean
	local camera = Workspace.CurrentCamera
	return camera ~= nil and y < camera.ViewportSize.Y * I.CameraZone
end

local function beginSteer(x: number)
	steerOrigin = x
	steerRaw = 0
end

local function moveSteer(x: number)
	local range = math.max(1, I.SteerRange * screenWidth())
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
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		mouseCamera = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	elseif input.UserInputType == Enum.UserInputType.Touch then
		if isCameraZone(input.Position.Y) then
			if not cameraTouch then
				cameraTouch = input
				cameraLast = input.Position
			end
		elseif isLeftHalf(input.Position.X) then
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

UserInputService.InputChanged:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.Touch then
		if input == steerTouch then
			moveSteer(input.Position.X)
		elseif input == cameraTouch then
			cameraX += input.Position.X - cameraLast.X
			cameraY += input.Position.Y - cameraLast.Y
			cameraLast = input.Position
		end
	elseif input.UserInputType == Enum.UserInputType.MouseMovement then
		if mouseCamera then
			cameraX += input.Delta.X
			cameraY += input.Delta.Y
		elseif mouseSteer then
			moveSteer(input.Position.X)
		end
	elseif input.UserInputType == Enum.UserInputType.MouseWheel then
		cameraZoom += input.Position.Z
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.Touch then
		if input == steerTouch then
			steerTouch = nil
			steerRaw = 0
		end
		if input == cameraTouch then
			cameraTouch = nil
		end
		brakeTouches[input] = nil
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		mouseCamera = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
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

local function isOver(input: InputObject): boolean
	return input.UserInputState == Enum.UserInputState.End
		or input.UserInputState == Enum.UserInputState.Cancel
end

local function releaseAll()
	steerTouch = nil
	steerRaw = 0
	table.clear(brakeTouches)
	mouseSteer = false
	mouseBrake = false
	cameraTouch = nil
	if mouseCamera then
		mouseCamera = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end

-- Свернули игру или открыли меню: событие конца касания может не прийти, отпускаем всё сами
UserInputService.WindowFocusReleased:Connect(releaseAll)

local function typing(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil
end

-- Вызывать раз в кадр: клавиатурный руль доходит до упора плавно
function Input.Update(dt: number)
	-- Касание, которое система отменила без события, не должно оставить руль или тормоз зажатым
	if steerTouch and isOver(steerTouch) then
		steerTouch = nil
		steerRaw = 0
	end
	if cameraTouch and isOver(cameraTouch) then
		cameraTouch = nil
	end
	for touch in brakeTouches do
		if isOver(touch) then
			brakeTouches[touch] = nil
		end
	end

	local target = 0
	if not typing() then
		if keyDown(Enum.KeyCode.A, Enum.KeyCode.Left) then
			target -= 1
		end
		if keyDown(Enum.KeyCode.D, Enum.KeyCode.Right) then
			target += 1
		end
	end
	-- Стрелка Вверх (или E) поднимает камеру, Стрелка Вниз (или Q) опускает (в том же направлении, что и тянуть вверх-вниз)
	if not typing() then
		if
			UserInputService:IsKeyDown(Enum.KeyCode.Up)
			or UserInputService:IsKeyDown(Enum.KeyCode.E)
		then
			cameraY -= I.CameraKeySpeed * dt
		end
		if
			UserInputService:IsKeyDown(Enum.KeyCode.Down)
			or UserInputService:IsKeyDown(Enum.KeyCode.Q)
		then
			cameraY += I.CameraKeySpeed * dt
		end
	end
	local rate = if target == 0 then I.KeyRampDown else I.KeyRampUp
	local change = rate * dt
	keySteer += math.clamp(target - keySteer, -change, change)
end

-- Сдвиг для камеры с прошлого вызова: пиксели вправо, пиксели вниз, щелчки колёсика (+ ближе)
function Input.TakeCamera(): (number, number, number)
	local x, y, zoom = cameraX, cameraY, cameraZoom
	cameraX, cameraY, cameraZoom = 0, 0, 0
	return x, y, zoom
end

-- Игрок сейчас держит камеру пальцем или правой кнопкой мыши
function Input.CameraHeld(): boolean
	return mouseCamera or cameraTouch ~= nil
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
		or (
			not typing()
			and (
				keyDown(Enum.KeyCode.Space, Enum.KeyCode.S)
				or UserInputService:IsKeyDown(Enum.KeyCode.Down)
			)
		)
end

return Input
