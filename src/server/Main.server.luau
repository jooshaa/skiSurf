--!strict
-- Deliver a Gift: точка входа сервера. Два прохода: init() всех систем, затем start().
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Remotes создаются до систем, чтобы клиенты не ждали
require(ReplicatedStorage.Remotes)

local Systems = script.Parent:WaitForChild("Systems")

-- Порядок важен: мир и данные раньше игровых систем
local ORDER = {
	"World",
	"PlayerData",
	"ElfService",
	"Workshop",
	"Income",
	"Gifts",
	"Round",
}

local loaded: { { name: string, system: any } } = {}
for _, name in ORDER do
	local module = Systems:WaitForChild(name) :: ModuleScript
	table.insert(loaded, { name = name, system = (require :: any)(module) })
end

for _, entry in loaded do
	if typeof(entry.system.init) == "function" then
		entry.system.init()
	end
end

for _, entry in loaded do
	if typeof(entry.system.start) == "function" then
		task.spawn(entry.system.start)
	end
end

print("[deliver-a-gift] server started")
