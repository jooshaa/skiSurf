--!strict
-- GiftFx: эффекты подарков только на клиенте: падение с неба, столб света у больших,
-- значок «нужна помощь» над общими подарками (виден всем на сервере).
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config") :: ModuleScript) :: any

local G = Config.Gifts

local cleanups: { [Instance]: { RBXScriptConnection } } = {}

-- Падение: сервер уже положил подарок на землю, клиент рисует полёт сверху
local function playFall(model: Instance, root: BasePart, conns: { RBXScriptConnection })
	local fallStart = model:GetAttribute("FallStart")
	local fallTime = model:GetAttribute("FallTime")
	if type(fallStart) ~= "number" or type(fallTime) ~= "number" or fallTime <= 0 then
		return
	end
	if Workspace:GetServerTimeNow() >= fallStart + fallTime then
		return
	end
	local rest = root.CFrame
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		if not root.Parent then
			connection:Disconnect()
			return
		end
		if model:GetAttribute("State") ~= "Falling" then
			root.CFrame = rest -- сервер уже разрешил подъём: ставим точно на землю
			connection:Disconnect()
			return
		end
		local alpha = math.clamp((Workspace:GetServerTimeNow() - fallStart) / fallTime, 0, 1)
		root.CFrame = rest + Vector3.new(0, G.DropFallHeight * (1 - alpha * alpha), 0)
		if alpha >= 1 then
			root.CFrame = rest
			connection:Disconnect()
		end
	end)
	table.insert(conns, connection)
end

-- Столб света: Beam между двумя Attachment, сам следует за подарком
local function addLightBeam(root: BasePart, color: Color3)
	local bottom = Instance.new("Attachment")
	bottom.Name = "BeamBottom"
	bottom.Parent = root
	local top = Instance.new("Attachment")
	top.Name = "BeamTop"
	top.Position = Vector3.new(0, G.BeamHeight, 0)
	top.Parent = root
	local beam = Instance.new("Beam")
	beam.Name = "LightBeam"
	beam.Attachment0 = bottom
	beam.Attachment1 = top
	beam.Width0 = G.BeamWidth
	beam.Width1 = G.BeamWidth
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Parent = root
end

-- Значок над общим подарком: сколько несущих из скольких, мигает по призыву о помощи
local function addHelpIcon(model: Instance, root: BasePart, conns: { RBXScriptConnection })
	local gui = Instance.new("BillboardGui")
	gui.Name = "HelpIcon"
	gui.Size = UDim2.fromOffset(110, 46)
	gui.StudsOffset = Vector3.new(0, root.Size.Y / 2 + 3, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = G.HelpIconDistance
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 30, 50)
	label.BackgroundTransparency = 0.3
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.4, 0)
	corner.Parent = label
	gui.Parent = root

	local function update()
		local state = model:GetAttribute("State")
		local carriers = model:GetAttribute("Carriers") or 0
		local needed = model:GetAttribute("Needed") or 1
		gui.Enabled = state == "Idle" or state == "Waiting"
		local calling = (model:GetAttribute("HelpUntil") or 0) > Workspace:GetServerTimeNow()
		label.Text = string.format("%s %d/%d", if calling then "🙋" else "🤝", carriers, needed)
		label.BackgroundColor3 = if calling
			then Color3.fromRGB(240, 170, 40)
			else Color3.fromRGB(20, 30, 50)
		gui.Size = if calling then UDim2.fromOffset(150, 62) else UDim2.fromOffset(110, 46)
	end
	for _, name in { "State", "Carriers", "HelpUntil" } do
		table.insert(conns, model:GetAttributeChangedSignal(name):Connect(update))
	end
	-- Призыв гаснет по времени: перепроверяем, когда он должен закончиться
	table.insert(
		conns,
		model:GetAttributeChangedSignal("HelpUntil"):Connect(function()
			local left = (model:GetAttribute("HelpUntil") or 0) - Workspace:GetServerTimeNow()
			if left > 0 then
				task.delay(left + 0.1, function()
					if gui.Parent then
						update()
					end
				end)
			end
		end)
	)
	update()
end

local function attach(model: Instance)
	if cleanups[model] then
		return
	end
	local conns: { RBXScriptConnection } = {}
	cleanups[model] = conns
	local root = model:WaitForChild("Box", 5)
	if not root or not root:IsA("BasePart") or cleanups[model] ~= conns then
		return
	end
	playFall(model, root, conns)
	if model:GetAttribute("Beam") == true and not root:FindFirstChild("LightBeam") then
		addLightBeam(root, root.Color)
	end
	if (model:GetAttribute("Needed") or 1) > 1 and not root:FindFirstChild("HelpIcon") then
		addHelpIcon(model, root, conns)
	end
end

local function detach(model: Instance)
	local conns = cleanups[model]
	if conns then
		cleanups[model] = nil
		for _, connection in conns do
			connection:Disconnect()
		end
	end
end

CollectionService:GetInstanceAddedSignal("Gift"):Connect(function(model)
	task.spawn(attach, model)
end)
CollectionService:GetInstanceRemovedSignal("Gift"):Connect(detach)
for _, model in CollectionService:GetTagged("Gift") do
	task.spawn(attach, model)
end
