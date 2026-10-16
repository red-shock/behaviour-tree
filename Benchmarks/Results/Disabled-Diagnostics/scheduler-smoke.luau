-- Run in the generated P01 benchmark's Server context after the timing run finishes.
local BT = require(game:GetService("ServerScriptService").Benchmark.Candidate)
local cases = {}
for _, condition in ipairs({ false, true }) do
	for _, waiting in ipairs({ "task.wait", "signal" }) do
		local event = Instance.new("BindableEvent")
		local root = BT.SequenceNode.new("Root")
		local calls, finished = 0, false
		local factory = if condition then BT.ConditionNode else BT.ActionNode
		root:addChild(factory.new("Wait", function()
			calls += 1
			if waiting == "task.wait" then
				task.wait(0.02)
			else
				event.Event:Wait()
			end
			finished = true
			return true
		end))
		local tree = BT.new(root)
		local ok, message = pcall(function()
			tree:run()
			assert(tree.root.status == BT.Enums.Status.RUNNING, "Expected RUNNING before scheduler completion")
			if waiting == "signal" then
				event:Fire()
			end
			local deadline = os.clock() + 2
			while not finished and os.clock() < deadline do
				task.wait()
			end
			assert(finished and calls == 1, "Callback did not complete exactly once")
			tree:run()
			assert(tree.root.status == BT.Enums.Status.SUCCESS, "Expected SUCCESS after scheduler completion")
			assert(tree.root.children[1]._coroutine == nil, "Completed execution retained its handle")
		end)
		tree:cancelActiveExecutionActions()
		tree.Paused:Destroy()
		event:Destroy()
		table.insert(
			cases,
			{ condition = condition, waiting = waiting, passed = ok, error = if ok then nil else tostring(message) }
		)
	end
end
return game:GetService("HttpService"):JSONEncode(cases)
