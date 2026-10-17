local function attach(node, level)
	local messages = {}
	node.tree = {
		debugLevel = level,
		debugPrint = function(_, message, threshold)
			table.insert(messages, { message = message, threshold = threshold })
		end,
	}
	return messages
end

return function(test)
	test("ExecutionNode: NONE avoids formatting names, results, and errors", function(BT)
		local formats, calls = 0, 0
		local sentinel = setmetatable({}, {
			__tostring = function()
				formats += 1
				return "DiagnosticValue"
			end,
		})
		for _, condition in ipairs({ false, true }) do
			for _, outcome in ipairs({ "truthy", "false", "nil", "error" }) do
				local factory = if condition then BT.ConditionNode else BT.ActionNode
				local node = factory.new("Leaf", function()
					calls += 1
					if outcome == "error" then
						error(sentinel, 0)
					elseif outcome == "truthy" then
						return sentinel
					elseif outcome == "false" then
						return false
					end
					return nil
				end)
				node.name = sentinel
				local messages = attach(node, BT.Enums.DebugLevel.NONE)
				local success = outcome ~= "error" and (not condition or outcome == "truthy")
				local expected = if success then BT.Enums.Status.SUCCESS else BT.Enums.Status.FAILURE
				assert(node:run() == expected, `Changed {outcome} result for condition={condition}`)
				assert(node._coroutine == nil, "Completed leaf retained execution state")
				assert(#messages == 0, "Disabled diagnostic reached logger")
			end
		end
		assert(calls == 8, "A callback was skipped or repeated")
		assert(formats == 0, "Disabled diagnostics formatted a value")
	end)

	test("ExecutionNode: TRANSITIONS preserves action and condition messages", function(BT)
		local formats = 0
		local value = setmetatable({}, {
			__tostring = function()
				formats += 1
				return "Result"
			end,
		})
		local cases = {
			{
				factory = BT.ActionNode,
				fn = function()
					return value
				end,
				status = "SUCCESS",
				kind = "ACTION",
			},
			{
				factory = BT.ActionNode,
				fn = function()
					error(value, 0)
				end,
				status = "FAILURE",
				kind = "ACTION",
			},
			{
				factory = BT.ConditionNode,
				fn = function()
					return true
				end,
				status = "SUCCESS",
				kind = "CONDITION",
			},
			{
				factory = BT.ConditionNode,
				fn = function()
					return false
				end,
				status = "FAILURE",
				kind = "CONDITION",
			},
		}
		for _, case in ipairs(cases) do
			local node = case.factory.new("Leaf", case.fn)
			local messages = attach(node, BT.Enums.DebugLevel.TRANSITIONS)
			assert(node:run() == case.status, "Changed terminal status")
			assert(#messages == 1, "Incorrect transition message count")
			assert(
				messages[1].message == `Exiting Leaf ({case.kind}) [RUNNING -> {case.status}]`,
				"Changed transition wording"
			)
			assert(messages[1].threshold == BT.Enums.DebugLevel.TRANSITIONS, "Changed transition threshold")
		end
		assert(formats == 0, "TRANSITIONS formatted verbose results")
	end)

	test("ExecutionNode: VERBOSE preserves lifecycle order and result formatting", function(BT)
		local formats = 0
		local result = setmetatable({}, {
			__tostring = function()
				formats += 1
				return "Result"
			end,
		})
		local node = BT.ActionNode.new("Leaf", function()
			return result
		end)
		local messages = attach(node, BT.Enums.DebugLevel.VERBOSE)
		assert(node:run() == BT.Enums.Status.SUCCESS, "Changed action result")
		assert(#messages == 2 and formats == 1, "Incorrect verbose formatting count")
		assert(
			messages[1].message == "Leaf coroutine is dead, resetting. Success: true, Result: Result",
			"Changed lifecycle message"
		)
		assert(messages[1].threshold == BT.Enums.DebugLevel.VERBOSE, "Changed lifecycle threshold")
		assert(messages[2].message == "Exiting Leaf (ACTION) [RUNNING -> SUCCESS]", "Changed message ordering")
	end)

	test("ExecutionNode: debug levels can change between runs", function(BT)
		local calls = 0
		local node = BT.ActionNode.new("Leaf", function()
			calls += 1
		end)
		local messages = attach(node, BT.Enums.DebugLevel.NONE)
		for _, level in ipairs({ 0, 3, 0, 1, 2 }) do
			node.tree.debugLevel = level
			node:run()
		end
		assert(calls == 5, "Changing levels changed callback execution")
		assert(#messages == 3, "Diagnostic level was cached or ignored")
	end)

	for _, condition in ipairs({ false, true }) do
		test(`ExecutionNode: suspended condition={condition} preserves completion and diagnostics`, function(BT)
			local factory = if condition then BT.ConditionNode else BT.ActionNode
			local calls = 0
			local node = factory.new("Wait", function()
				calls += 1
				coroutine.yield()
				return true
			end)
			local messages = attach(node, BT.Enums.DebugLevel.NONE)
			assert(node:run() == BT.Enums.Status.RUNNING, "Suspended callback did not return RUNNING")
			assert(node:run() == BT.Enums.Status.RUNNING and calls == 1, "Tick resumed or restarted the callback")
			assert(#messages == 0, "Disabled entry diagnostic reached logger")
			node.tree.debugLevel = BT.Enums.DebugLevel.VERBOSE
			local resumed, message = coroutine.resume(node._coroutine.fn)
			assert(resumed, message)
			assert(node:run() == BT.Enums.Status.SUCCESS, "Completed callback did not succeed")
			assert(#messages == 2 and calls == 1, "Changed completion messages or callback count")
		end)
	end

	test("ExecutionNode: enabled entry message is unchanged", function(BT)
		local node = BT.ActionNode.new("Wait", function()
			coroutine.yield()
		end)
		local messages = attach(node, BT.Enums.DebugLevel.TRANSITIONS)
		node:run()
		node:_cancelThread()
		assert(#messages == 1, "Incorrect entry message count")
		assert(messages[1].message == "Entering Wait (ACTION) [IDLE -> RUNNING]", "Changed entry message")
	end)
end
