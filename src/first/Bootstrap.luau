--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local SERVER_RDY_ATTR = "ServerReady"

local IS_SERVER = RunService:IsServer()
local IS_STUDIO = RunService:IsStudio()

export type Module = {
	name: string?,
	init: (...any?) -> (),
	start: () -> (),
	dependencies: { string }?,
}

local function loadModules(
	Container: Instance,
	deep: boolean,
	pred: (string) -> boolean
): { [string]: Module }
	local loadedModules = {}
	for _, v: Instance in pairs(deep and Container:GetDescendants() or Container:GetChildren()) do
		if not v:IsA("ModuleScript") or not pred(v.Name) then continue end

		local t = tick()
		local success, res = pcall(function()
			local module = require(v) :: Module
			if not module.name then module.name = v.Name end
			loadedModules[v.Name] = module
		end)

		if _G.DEBUG then
			local et = tick() - t
			if success then
				print(`Loaded {v.Name} in {et}s`)
			else
				warn(`Failed to load {v.Name} in {et}s\n{res}`)
			end
		end
	end
	return loadedModules
end

local function setup(Container: Instance, deep: boolean)
	local RuntimeFolder = IS_SERVER and Instance.new("Folder", ReplicatedStorage)
		or ReplicatedStorage:WaitForChild("Runtime")
	local RemotesFolder = IS_SERVER and Instance.new("Folder", ReplicatedStorage)
		or ReplicatedStorage:WaitForChild("Remotes")
	if IS_SERVER then -- Set up runtime folder
		RuntimeFolder.Name = "Runtime"
		RemotesFolder.Name = "Remotes"
	end

	-- Require all modules
	local modules = loadModules(
		Container,
		true,
		function(name) return name:match(`{IS_SERVER and "Service" or "Controller"}$`) ~= nil end
	) :: { [string]: Module }

	-- init() modules
	local initModules = {}
	for name, module in pairs(modules) do
		if _G.DEBUG then print(`Initializing {name}...`) end
		module.init(RuntimeFolder, RemotesFolder)
		initModules[name] = module
		if _G.DEBUG then print(`Initialized {name}`) end
	end

	-- start() modules
	for name, module in pairs(initModules) do
		if _G.DEBUG then print(`Starting {name}...`) end
		task.spawn(function() module.start() end)
	end

	if IS_SERVER then ReplicatedStorage:SetAttribute(SERVER_RDY_ATTR, true) end
end

if not IS_SERVER and not game:IsLoaded() then
	local t = tick()
	game.Loaded:Wait()
	if _G.DEBUG then
		print(`Client game.Loaded yielded for {math.round((tick() - t) * 1000) / 1000}s`)
	end
end

if IS_SERVER then
	setup(ServerStorage.Services, true)
else
	if not ReplicatedStorage:GetAttribute(SERVER_RDY_ATTR) then
		ReplicatedStorage:GetAttributeChangedSignal(SERVER_RDY_ATTR):Wait()
	end
	setup(ReplicatedStorage.Modules.Controllers, true)
end

return {}
