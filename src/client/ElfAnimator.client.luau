--!strict
-- ElfAnimator: покачивание и эффекты эльфов только на клиенте.
-- Твиним CFrame каждой части напрямую: TweenService работает нативно, Lua в кадре не нужен.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config") :: ModuleScript) :: any
local ElfVisuals = require(ReplicatedStorage:WaitForChild("ElfVisuals") :: ModuleScript) :: any

local S = Config.Settings

type Animation = {
	tweens: { Tween },
	offsets: { [BasePart]: CFrame },
	conns: { RBXScriptConnection },
	period: number,
}

local active: { [Instance]: Animation } = {}

local function stopTweens(animation: Animation)
	for _, tween in animation.tweens do
		tween:Cancel()
	end
	table.clear(animation.tweens)
end

local function stop(model: Instance)
	local animation = active[model]
	if not animation then
		return
	end
	active[model] = nil
	stopTweens(animation)
	for _, connection in animation.conns do
		connection:Disconnect()
	end
end

-- Ставим части в слот и запускаем бесконечный твин вверх-вниз
local function startTweens(model: Instance, animation: Animation)
	stopTweens(animation)
	local slot = model:GetAttribute("SlotCFrame")
	if typeof(slot) ~= "CFrame" then
		return
	end
	local top = slot * CFrame.new(0, S.BobAmplitude, 0)
	local info =
		TweenInfo.new(animation.period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	for part, offset in animation.offsets do
		if part.Parent then
			part.CFrame = slot * offset
			local tween = TweenService:Create(part, info, { CFrame = top * offset })
			tween:Play()
			table.insert(animation.tweens, tween)
		end
	end
end

local function start(model: Instance)
	if active[model] or not model:IsA("Model") then
		return
	end
	-- Ждём репликации тела (при стриминге части могут прийти чуть позже)
	local body = model:WaitForChild("Body", 5)
	if not body or not model.Parent or active[model] then
		return
	end

	ElfVisuals.ApplyEffects(model, model:GetAttribute("Rarity"), model:GetAttribute("Mutation"))

	-- Смещения частей относительно пивота: сервер держит модель ровно в слоте
	local pivot = model:GetPivot()
	local offsets: { [BasePart]: CFrame } = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			offsets[part] = pivot:ToObjectSpace(part.CFrame)
		end
	end

	local animation: Animation = {
		tweens = {},
		offsets = offsets,
		conns = {},
		period = S.BobPeriod * (0.85 + math.random() * 0.3), -- чуть разные периоды, чтобы не качались синхронно
	}
	active[model] = animation
	table.insert(
		animation.conns,
		model:GetAttributeChangedSignal("SlotCFrame"):Connect(function()
			startTweens(model, animation) -- сервер переставил эльфа: перезапускаем вокруг нового слота
		end)
	)

	-- Случайная фаза: одноразовая пауза перед стартом (не DelayTime, он повторяется каждый цикл)
	task.wait(math.random() * S.BobPeriod)
	if active[model] ~= animation then
		return
	end
	startTweens(model, animation)
end

CollectionService:GetInstanceAddedSignal("Elf"):Connect(function(model)
	task.spawn(start, model)
end)
CollectionService:GetInstanceRemovedSignal("Elf"):Connect(stop)
for _, model in CollectionService:GetTagged("Elf") do
	task.spawn(start, model)
end
