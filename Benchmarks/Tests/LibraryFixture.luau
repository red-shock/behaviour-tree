-- Loads the unchanged library for fixture smoke tests, NOT Roblox timing or scheduler tests.
-- Only GUIDs, BindableEvent lifetime, and raw coroutine cancellation are simulated.
local fs = require("@std/fs")
local luau = require("@lute/luau")

return function(options)
	options = options or {}
	local root = { moduleName = "init" }
	local cache, events = {}, {}
	local guid = 0
	for _, name in ipairs({ "Enums", "Node", "ControlNode", "ExecutionNode", "DecoratorNode", "Tree" }) do
		root[name] = { moduleName = name, Parent = root }
	end
	local services = {
		HttpService = {
			GenerateGUID = function()
				guid += 1
				return `test-{guid}`
			end,
		},
		RunService = {
			IsStudio = function()
				return options.isStudio or false
			end,
		},
	}
	local globals = {
		assert = assert,
		error = error,
		type = type,
		pairs = pairs,
		ipairs = ipairs,
		next = next,
		getmetatable = getmetatable,
		setmetatable = setmetatable,
		rawequal = rawequal,
		pcall = pcall,
		tostring = tostring,
		table = table,
		string = string,
		math = math,
		coroutine = coroutine,
		print = options.print or print,
		warn = print,
	}
	local function loadModule(reference)
		if cache[reference] then
			return cache[reference]
		end
		local source = fs.readFileToString(`BehaviourTree/{reference.moduleName}.luau`)
		local environment = setmetatable({
			script = reference,
			require = loadModule,
			game = {
				GetService = function(_, name)
					assert(services[name], `Unexpected service {name}`)
					return services[name]
				end,
			},
			Instance = {
				new = function(class)
					assert(class == "BindableEvent", `Unexpected instance {class}`)
					local event = { Fire = function() end }
					event.Destroy = function()
						events[event] = nil
					end
					events[event] = true
					return event
				end,
			},
			task = { cancel = coroutine.close },
		}, { __index = globals })
		cache[reference] = luau.load(luau.compile(source), reference.moduleName, environment)()
		return cache[reference]
	end
	return loadModule(root), function()
		assert(next(events) == nil, "Fixture leaked a BindableEvent")
	end
end
