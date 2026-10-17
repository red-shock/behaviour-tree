return function(test)
	for _, level in ipairs({ 0, 1, 2, 3 }) do
		test(`ControlNode: cancellation at debug level {level} preserves cleanup`, function(BT, own)
			local tree = own(BT.new(BT.ParallelNode.new("Root")))
			tree:addChild(BT.ActionNode.new("Wait", function()
				coroutine.yield()
			end))
			local child = tree.root.children[1]
			local messages, formats, cancellations = {}, 0, 0
			tree.debugLevel = level
			tree.debugPrint = function(_, message)
				table.insert(messages, message)
			end
			local cancel = child._cancelThread
			child._cancelThread = function(self)
				cancellations += 1
				cancel(self)
			end
			child:run()
			table.clear(messages)
			child.name = setmetatable({}, {
				__tostring = function()
					formats += 1
					return "Wait"
				end,
			})
			tree.root._statusTable[child] = BT.Enums.Status.RUNNING
			tree.root:_reset()
			assert(cancellations == 1 and child._coroutine == nil, "Running child was not cancelled exactly once")
			assert(tree.root.status == BT.Enums.Status.IDLE, "Control reset changed")
			assert(next(tree.root._statusTable) == nil, "Reset retained cached status")
			if level < BT.Enums.DebugLevel.VERBOSE then
				assert(#messages == 0 and formats == 0, "Disabled cancellation diagnostic was formatted or logged")
			else
				assert(#messages == 1 and formats == 1, "Enabled cancellation diagnostic was lost")
				assert(messages[1] == "Wait is running, cancelling thread", "Changed cancellation message")
			end
		end)
	end
end
