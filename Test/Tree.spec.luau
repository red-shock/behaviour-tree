return function(test)
	test("Tree: NONE avoids logger calls and BASIC keeps tick boundaries", function(BT, own)
		local tree = own(BT.new(BT.SequenceNode.new("Root")))
		tree:addChild(BT.ActionNode.new("Wait", function()
			coroutine.yield()
		end))
		local messages = {}
		tree.debugPrint = function(_, message)
			table.insert(messages, message)
		end
		tree:run()
		assert(#messages == 0, "NONE called the tree logger")
		tree:cancelActiveExecutionActions()
		tree.root.status = BT.Enums.Status.IDLE
		tree.debugLevel = BT.Enums.DebugLevel.BASIC
		tree:run()
		tree:run()
		assert(#messages == 1 and messages[1] == "TICK BEGIN", "Changed running tick boundary")
		local resumed, message = coroutine.resume(tree.root.children[1]._coroutine.fn)
		assert(resumed, message)
		tree:run()
		assert(#messages == 1, "Completion of a RUNNING root began a new tick")
		tree:run()
		assert(#messages == 2 and messages[2] == "TICK BEGIN", "Terminal root did not begin a new tick")
		tree:pause()
		tree:run()
		assert(#messages == 2, "Paused tree logged a tick")
	end)

	local printed = {}
	test("Tree: direct logger calls still filter levels and format the prefix", function(BT, own)
		local tree = own(BT.new())
		tree.debugLevel = BT.Enums.DebugLevel.BASIC
		tree:debugPrint("Hidden", BT.Enums.DebugLevel.TRANSITIONS)
		tree:debugPrint("Visible")
		assert(#printed == 1, "Direct logger level filtering changed")
		assert(printed[1] == `[BehaviourTree:{tree.uuid}]: Visible`, "Changed output prefix")
	end, {
		isStudio = true,
		print = function(message)
			table.insert(printed, message)
		end,
	})

	test("Tree: direct logging remains silent outside Studio", function(BT, own)
		local tree = own(BT.new())
		tree.debugLevel = BT.Enums.DebugLevel.VERBOSE
		tree:debugPrint("Hidden")
	end, {
		print = function()
			error("Printed outside Studio")
		end,
	})
end
