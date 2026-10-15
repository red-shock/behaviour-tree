local Suite = if script then require(script.Parent.Parent.Suite) else require("../Suite")
local Tree = if script then require(script.Parent.Parent.Fixtures.Tree) else require("../Fixtures/Tree")
local Support = if script then require(script.Parent.Parent.Fixtures.Support) else require("../Fixtures/Support")

-- An invented worker lifecycle: inputs and sizes are synthetic benchmark choices.
-- Work is resumed by this fixture before another branch is selected, so the
-- ordinary replay does not depend on a new cancellation policy.
local frames = {
	{ unavailable = true, assigned = false, ready = false, running = false },
	{ unavailable = false, assigned = false, ready = false, running = false },
	{ unavailable = false, assigned = true, ready = false, running = true },
	{ unavailable = false, assigned = true, ready = false, running = true },
	{ unavailable = false, assigned = true, ready = false, running = false, resume = true },
	{ unavailable = false, assigned = true, ready = true, running = false },
}

local function fixture(BT, role, probe, population, options)
	local agents, trace, threads = {}, {}, {}
	local conditionCalls, immediateCalls = 0, 0
	local statusError
	local immediate = if options.synchronous and role == "candidate" then BT.SynchronousActionNode else BT.ActionNode
	for index = 1, population do
		local state = { input = frames[1], planValid = false, started = 0, finished = 0 }
		local function record(label)
			if probe then
				table.insert(trace, `{index}:{label}`)
				threads[coroutine.running()] = true
			end
		end
		local function action(name, counter, update)
			return immediate.new(name, function()
				if probe then
					immediateCalls += 1
				end
				record(name)
				state[counter] = (state[counter] or 0) + 1
				if update then
					update()
				end
			end, false)
		end
		local function condition(name, predicate)
			return BT.ConditionNode.new(name, function()
				local result = predicate()
				if probe then
					conditionCalls += 1
					record(`{name}={result}`)
				end
				return result
			end)
		end
		local root = BT.SequenceNode.new("Worker")
		local maintenance = if options.parallel then BT.ParallelNode.new("Maintenance") else root
		maintenance:addChild(action("Refresh", "refreshes"))
		maintenance:addChild(action("Observe", "observations"))
		if options.parallel then
			root:addChild(maintenance)
		end

		local priority = BT.FallbackNode.new("Dispatch")
		local deferred = BT.SequenceNode.new("Deferred")
		deferred:addChild(condition("Unavailable", function()
			return state.input.unavailable
		end))
		deferred:addChild(action("Defer", "deferrals"))
		priority:addChild(deferred)

		local complete = BT.SequenceNode.new("Complete")
		complete:addChild(condition("Ready", function()
			return state.input.ready
		end))
		complete:addChild(action("Commit", "commits"))
		priority:addChild(complete)

		local work = BT.SequenceNode.new("Work")
		work:addChild(condition("Assigned", function()
			return state.input.assigned
		end))
		local planning = BT.FallbackNode.new("Planning")
		planning:addChild(condition("PlanValid", function()
			return state.planValid
		end))
		planning:addChild(action("Prepare", "preparations", function()
			state.planValid = true
		end))
		work:addChild(planning)
		work:addChild(BT.ActionNode.new("Process", function()
			state.started += 1
			record("Process:start")
			state.pending = coroutine.running()
			coroutine.yield()
			state.finished += 1
			record("Process:finish")
		end, false))
		priority:addChild(work)
		priority:addChild(action("Idle", "idles"))
		root:addChild(priority)
		table.insert(agents, { tree = BT.new(root), state = state })
	end
	return {
		step = function()
			for _, agent in ipairs(agents) do
				agent.state.planValid = false
			end
			for _, input in ipairs(frames) do
				for index, agent in ipairs(agents) do
					local state = agent.state
					state.input = input
					if input.resume then
						assert(state.pending, `Worker {index}: no owned work to resume`)
						local ok, message = coroutine.resume(state.pending)
						assert(ok, message)
						state.pending = nil
					end
					agent.tree:run()
					local expected = if input.running then BT.Enums.Status.RUNNING else BT.Enums.Status.SUCCESS
					if agent.tree.root.status ~= expected then
						statusError = statusError or `Worker {index}: expected {expected}, got {agent.tree.root.status}`
					end
				end
			end
		end,
		verify = function(iterations, test)
			test("follows the scripted SUCCESS and RUNNING transitions", function()
				assert(not statusError, statusError)
			end)
			test("runs maintenance once per worker tick", function()
				for index, agent in ipairs(agents) do
					local expected = iterations * #frames
					assert(agent.state.refreshes == expected, `Worker {index}: incorrect refresh count`)
					assert(agent.state.observations == expected, `Worker {index}: incorrect observation count`)
				end
			end)
			test("selects only the expected priority branches", function()
				for index, agent in ipairs(agents) do
					for _, counter in ipairs({ "deferrals", "commits", "preparations", "idles" }) do
						assert(agent.state[counter] == iterations, `Worker {index}: incorrect {counter} count`)
					end
				end
			end)
			test("starts and completes owned work once per cycle", function()
				for index, agent in ipairs(agents) do
					assert(agent.state.started == iterations, `Worker {index}: work restarted while suspended`)
					assert(agent.state.finished == iterations, `Worker {index}: work did not complete`)
				end
			end)
			test("finishes each cycle without retained execution handles", function()
				for index, agent in ipairs(agents) do
					assert(agent.state.pending == nil, `Worker {index}: retained driver-owned work`)
					Tree.visit(agent.tree.root, function(node)
						assert(node._coroutine == nil, `Worker {index}, node {node.name}: retained execution handle`)
					end)
				end
			end)
			if probe then
				test("performs the same guarded checks and immediate updates", function()
					local cycles = iterations * population
					assert(conditionCalls == cycles * 18, `Expected {cycles * 18} conditions, got {conditionCalls}`)
					assert(immediateCalls == cycles * 16, `Expected {cycles * 16} updates, got {immediateCalls}`)
				end)
			end
			return if probe then table.concat(trace, ",") else `{iterations}:{population}:complete`
		end,
		metrics = function()
			local threadCount = 0
			for _ in pairs(threads) do
				threadCount += 1
			end
			return {
				workers = population,
				ticksPerCycle = #frames * population,
				conditionCalls = conditionCalls,
				immediateActionCalls = immediateCalls,
				callbackThreadIdentities = threadCount,
			}
		end,
		cleanup = function()
			local errors = {}
			for index, agent in ipairs(agents) do
				local ok, message = pcall(Tree.destroy, agent.tree)
				if not ok then
					table.insert(errors, `Worker {index}: {message}`)
				end
			end
			assert(#errors == 0, table.concat(errors, "; "))
		end,
	}
end

return Suite.describe(
	"DecisionCycle",
	function(test)
		for _, population in ipairs({ 1, 16 }) do
			test(
				`guarded decision replay for {population} independent {if population == 1 then "worker" else "workers"}`,
				{
					id = `decision-cycle-ordinary-workers{population}`,
					unit = `decision cycle ({#frames * population} ticks)`,
					create = function(BT, role, probe)
						return fixture(BT, role, probe, population, {})
					end,
				}
			)
		end
		test("16 workers with synchronous immediate updates", {
			id = "decision-cycle-synchronous-workers16",
			unit = "decision cycle (96 ticks)",
			unsupported = Support.synchronousActions,
			create = function(BT, role, probe)
				return fixture(BT, role, probe, 16, { synchronous = true })
			end,
		})
		test("16 workers with parallel maintenance", {
			id = "decision-cycle-parallel-workers16",
			unit = "decision cycle (96 ticks)",
			unsupported = Support.parallelAccounting,
			create = function(BT, role, probe)
				return fixture(BT, role, probe, 16, { parallel = true })
			end,
		})
	end,
	"Repeated maintenance, guarded priority choices, cached preparation, and work spanning ticks make fixed per-node costs accumulate across independent trees."
)
