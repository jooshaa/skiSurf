-- DragonAnimator: покачивание и эффекты драконов только на клиенте.
-- Твиним CFrame каждой части напрямую: TweenService работает нативно, Lua в кадре не нужен.
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DragonConfig = require(ReplicatedStorage:WaitForChild("DragonConfig"))
local DragonVisuals = require(ReplicatedStorage:WaitForChild("DragonVisuals"))
local S = DragonConfig.Settings

local active = {} -- model -> { tweens, offsets, conns, period }

local function stopTweens(a)
	for _, t in ipairs(a.tweens) do
		t:Cancel()
	end
	table.clear(a.tweens)
end

local function stop(model)
	local a = active[model]
	if not a then
		return
	end
	active[model] = nil
	stopTweens(a)
	for _, c in ipairs(a.conns) do
		c:Disconnect()
	end
end

-- Ставим части в слот и запускаем бесконечный твин вверх-вниз
local function startTweens(model, a)
	stopTweens(a)
	local slot = model:GetAttribute("SlotCFrame")
	if typeof(slot) ~= "CFrame" then
		return
	end
	local top = slot * CFrame.new(0, S.BobAmplitude, 0)
	local info =
		TweenInfo.new(a.period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	for part, offset in pairs(a.offsets) do
		if part.Parent then
			part.CFrame = slot * offset
			local t = TweenService:Create(part, info, { CFrame = top * offset })
			t:Play()
			table.insert(a.tweens, t)
		end
	end
end

local function start(model)
	if active[model] then
		return
	end
	-- Ждём репликации тела (при стриминге части могут прийти чуть позже)
	local body = model:WaitForChild("Body", 5)
	if not body or not model.Parent or active[model] then
		return
	end

	DragonVisuals.ApplyEffects(model, model:GetAttribute("Rarity"))

	-- Смещения частей относительно пивота: сервер держит модель ровно в слоте
	local pivot = model:GetPivot()
	local offsets = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			offsets[part] = pivot:ToObjectSpace(part.CFrame)
		end
	end

	local a = {
		tweens = {},
		offsets = offsets,
		conns = {},
		period = S.BobPeriod * (0.85 + math.random() * 0.3), -- чуть разные периоды, чтобы не качались синхронно
	}
	active[model] = a
	table.insert(
		a.conns,
		model:GetAttributeChangedSignal("SlotCFrame"):Connect(function()
			startTweens(model, a) -- сервер переставил дракона: перезапускаем вокруг нового слота
		end)
	)

	-- Случайная фаза: одноразовая пауза перед стартом (не DelayTime, он повторяется каждый цикл)
	task.wait(math.random() * S.BobPeriod)
	if active[model] ~= a then
		return
	end
	startTweens(model, a)
end

CollectionService:GetInstanceAddedSignal("Dragon"):Connect(function(model)
	task.spawn(start, model)
end)
CollectionService:GetInstanceRemovedSignal("Dragon"):Connect(stop)
for _, model in ipairs(CollectionService:GetTagged("Dragon")) do
	task.spawn(start, model)
end
