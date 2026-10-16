local Tree = if script then require(script.Parent.Tree) else require("./Tree")

return function(BT, role, probe, options)
	local calls, formats, loggerCalls = 0, 0, 0
	local threads, trace = {}, {}
	local result = if probe
		then setmetatable({}, {
			__tostring = function()
				formats += 1
				return "Result"
			end,
		})
		else false
	local callback = if probe
		then function()
			calls += 1
			threads[coroutine.running()] = true
			return result
		end
		else function()
			return result
		end
	local root = BT.SequenceNode.new("Tick")
	local factory = if options.synchronous and role == "candidate" then BT.SynchronousActionNode else BT.ActionNode
	for index = 1, options.width do
		if options.conditions and index % 2 == 0 then
			root:addChild(BT.ConditionNode.new(
				`Condition{index}`,
				if probe
					then function()
						calls += 1
						threads[coroutine.running()] = true
						return true
					end
					else function()
						return true
					end
			))
		else
			root:addChild(factory.new(`Action{index}`, callback, false))
		end
	end
	if options.running then
		root:addChild(BT.ActionNode.new("ManuallySuspended", function()
			-- The fixture owns this raw yield. It is never resumed, only cancelled in teardown.
			coroutine.yield()
		end, false))
	end
	local tree = BT.new(root)
	tree.debugLevel = options.level or BT.Enums.DebugLevel.NONE
	if probe then
		for _, child in ipairs(tree.root.children) do
			local fn = child.fn
			child.fn = function()
				table.insert(trace, child.name)
				return fn()
			end
		end
		tree.debugPrint = function()
			loggerCalls += 1
		end
	elseif tree.debugLevel > BT.Enums.DebugLevel.NONE then
		-- Measure call-site formatting with an identical quiet sink, not Output rendering.
		tree.debugPrint = Tree.noOp
	end
	local starts = 0
	if options.running then
		tree:run()
		starts = 1
	end
	return {
		step = function()
			tree:run()
		end,
		verify = function(iterations, test)
			local expected = if options.running then BT.Enums.Status.RUNNING else BT.Enums.Status.SUCCESS
			test("returns the expected root status", function()
				assert(tree.root.status == expected, `Expected {expected}, got {tree.root.status}`)
			end)
			if probe then
				test("invokes every immediate leaf once per tick", function()
					local expectedCalls = (iterations + starts) * options.width
					assert(calls == expectedCalls, `Expected {expectedCalls} calls, got {calls}`)
				end)
			end
			return `{expected}:{if probe then table.concat(trace, ",") else tostring(options.width)}`
		end,
		metrics = function()
			local threadCount = 0
			for _ in pairs(threads) do
				threadCount += 1
			end
			return {
				leafCalls = calls,
				resultFormats = formats,
				loggerCalls = loggerCalls,
				callbackThreadIdentities = threadCount,
			}
		end,
		cleanup = function()
			Tree.destroy(tree)
		end,
	}
end
