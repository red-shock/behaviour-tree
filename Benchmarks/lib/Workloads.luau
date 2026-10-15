local Workloads = {}

local function noOp() end

local function destroyTree(tree)
	local ok, message = pcall(tree.cancelActiveExecutionActions, tree)
	tree.Paused:Destroy()
	assert(ok, message)
end

local function visit(node, callback)
	callback(node)
	for _, child in ipairs(node.children or {}) do
		visit(child, callback)
	end
end

local function nodeCount(node)
	local count = 0
	visit(node, function()
		count += 1
	end)
	return count
end

local function supported()
	return nil
end

local function actionSupport(BT, role)
	if role == "candidate" and not (BT.SynchronousActionNode and BT.SynchronousActionNode.new) then
		return "SynchronousActionNode.new is not available"
	end
	return nil
end

local function adoptionSupport(BT, role)
	if role == "candidate" and not (BT.adopt and BT.ControlNode.adoptChild) then
		return "BT.adopt/adoptChild are not available"
	end
	return nil
end

local function cancellationSupport(BT)
	if type(BT.ControlNode._cancel) ~= "function" then
		return "Requires recursive cancellation on BOTH revisions"
	end
	local root = BT.ParallelNode.new("AccountingGate")
	root:addChild(BT.ActionNode.new("First", noOp, false))
	root:addChild(BT.ActionNode.new("Second", noOp, false))
	local tree = BT.new(root)
	local ok, status = pcall(function()
		tree:run()
		return tree.root.status
	end)
	destroyTree(tree)
	if not ok or status ~= BT.Enums.Status.SUCCESS then
		return "Requires correct immediate parallel accounting on BOTH revisions"
	end
	return nil
end

local function tickFixture(BT, role, probe, options)
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
		tree.debugPrint = noOp
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
		verify = function(iterations)
			local expected = if options.running then BT.Enums.Status.RUNNING else BT.Enums.Status.SUCCESS
			assert(tree.root.status == expected, "Unexpected tree status")
			if probe then
				assert(calls == (iterations + starts) * options.width, "Incorrect action invocation count")
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
			destroyTree(tree)
		end,
	}
end

local function resetFixture(BT, _, probe, width)
	local root = BT.SequenceNode.new("Reset")
	local keys = table.create(width)
	for index = 1, width do
		keys[index] = {}
	end
	local resets, replacements = 0, 0
	local reset = root._cancel or root._reset
	return {
		step = function()
			for _, key in ipairs(keys) do
				root._statusTable[key] = BT.Enums.Status.SUCCESS
			end
			root._successCount = width
			root._failureCount = width
			if probe then
				local before = root._statusTable
				reset(root)
				resets += 1
				if not rawequal(before, root._statusTable) then
					replacements += 1
				end
			else
				reset(root)
			end
		end,
		verify = function(iterations)
			assert(next(root._statusTable) == nil, "Reset retained cached results")
			assert(root._successCount == 0 and root._failureCount == 0, "Reset retained counters")
			assert(root.status == BT.Enums.Status.IDLE, "Reset retained status")
			if probe then
				assert(resets == iterations, "Incorrect reset count")
			end
			return `empty:{width}`
		end,
		metrics = function()
			return { resets = resets, statusTableReplacements = replacements }
		end,
		cleanup = noOp,
	}
end

local function constructionFixture(BT, role, probe, depth, width, adoption)
	local trees = {}
	local copiedNodes, cloneCalls = 0, 0
	local adopt = adoption and role == "candidate"
	local function instrument(node)
		if probe then
			local clone = node.clone
			node.clone = function(self)
				cloneCalls += 1
				copiedNodes += nodeCount(self)
				return clone(self)
			end
		end
		return node
	end
	local function build(level)
		if level == 0 then
			return instrument(BT.ActionNode.new("Leaf", noOp, false))
		end
		local root = instrument(BT.SequenceNode.new("Branch"))
		for _ = 1, width do
			local child = build(level - 1)
			if adopt then
				root:adoptChild(child)
			else
				root:addChild(child)
			end
		end
		return root
	end
	local expectedNodes = 0
	for level = 0, depth do
		expectedNodes += width ^ level
	end
	return {
		step = function()
			local root = build(depth)
			local tree = if adopt then BT.adopt(root) else BT.new(root)
			table.insert(trees, { tree = tree, suppliedRoot = root })
		end,
		verify = function(iterations)
			assert(#trees == iterations, "Incorrect construction count")
			for _, entry in ipairs(trees) do
				local tree = entry.tree
				assert(rawequal(tree.root, entry.suppliedRoot) == adopt, "Construction ownership contract changed")
				assert(nodeCount(tree.root) == expectedNodes, "Construction lost nodes")
				visit(tree.root, function(node)
					assert(rawequal(node.tree, tree), "Incorrect tree binding")
					for _, child in ipairs(node.children or {}) do
						assert(rawequal(child.parent, node), "Incorrect parent binding")
					end
				end)
				tree:run()
				assert(tree.root.status == BT.Enums.Status.SUCCESS, "Constructed tree cannot execute")
			end
			return `{iterations}:{expectedNodes}`
		end,
		metrics = function()
			return { copiedNodes = copiedNodes, cloneCalls = cloneCalls, nodesPerTree = expectedNodes }
		end,
		cleanup = function()
			local firstError
			for _, entry in ipairs(trees) do
				local ok, message = pcall(destroyTree, entry.tree)
				if not ok then
					firstError = firstError or tostring(message)
				end
			end
			table.clear(trees)
			assert(not firstError, firstError)
		end,
	}
end

local function cancellationFixture(BT, _, probe, mode)
	local trace, cancellations = {}, 0
	local enabled = false
	local root = if mode == "fallback" or mode == "switch"
		then BT.FallbackNode.new("Root")
		else BT.SequenceNode.new("Root")
	local function action(name, running)
		return BT.ActionNode.new(name, function()
			if probe then
				table.insert(trace, name)
			end
			if running then
				coroutine.yield()
			end
		end, false)
	end
	if mode ~= "dense" then
		root:addChild(BT.ConditionNode.new("Guard", function()
			if probe then
				table.insert(trace, "guard")
			end
			return if mode == "switch" then enabled else mode == "fallback"
		end))
	end
	for branchIndex = 1, (if mode == "switch" then 1 else 8) do
		local branch = BT.SequenceNode.new(`Branch{branchIndex}`)
		for leafIndex = 1, (if mode == "switch" then 1 else 8) do
			branch:addChild(action(`{branchIndex}/{leafIndex}`, mode == "switch"))
		end
		root:addChild(branch)
	end
	local tree = BT.new(root)
	if probe then
		visit(tree.root, function(node)
			local cancel = node._cancel
			node._cancel = function(self)
				cancellations += 1
				return cancel(self)
			end
		end)
	end
	return {
		step = function()
			if mode == "switch" then
				enabled = false
				tree:run()
				enabled = true
			end
			tree:run()
		end,
		verify = function(iterations)
			local expected = if mode == "sequence" then BT.Enums.Status.FAILURE else BT.Enums.Status.SUCCESS
			assert(tree.root.status == expected, "Unexpected cancellation workload result")
			visit(tree.root, function(node)
				assert(node._coroutine == nil, "Preempted execution still owns a coroutine")
			end)
			if probe then
				local perIteration = if mode == "dense" then 64 elseif mode == "switch" then 3 else 1
				assert(#trace == perIteration * iterations, "Incorrect cancellation workload invocation count")
			end
			return if probe then table.concat(trace, ",") else expected
		end,
		metrics = function()
			return { cancellationCalls = cancellations, callbackCalls = #trace }
		end,
		cleanup = function()
			destroyTree(tree)
		end,
	}
end

function Workloads.create()
	local cases = {}
	local function add(id, workload, unit, create, unsupported, limit)
		table.insert(cases, {
			id = id,
			workload = workload,
			unit = unit,
			create = create,
			unsupported = unsupported or supported,
			maxIterations = limit,
		})
	end
	for _, level in ipairs({ 0, 2, 3 }) do
		for _, width in ipairs({ 8, 64 }) do
			add(`diagnostics-level{level}-width{width}`, "Diagnostics", "tree tick", function(BT, role, probe)
				return tickFixture(BT, role, probe, { width = width, level = level, conditions = true })
			end)
		end
	end
	for _, width in ipairs({ 0, 16, 128 }) do
		add(`reset-width{width}`, "Reset", "populate and reset", function(BT, role, probe)
			return resetFixture(BT, role, probe, width)
		end)
	end
	for _, shape in ipairs({
		{ name = "wide", depth = 1, width = 32 },
		{ name = "deep", depth = 12, width = 1 },
		{ name = "balanced", depth = 3, width = 3 },
	}) do
		for _, adopt in ipairs({ false, true }) do
			add(
				`construction-{if adopt then "adopt" else "clone"}-{shape.name}`,
				"Construction",
				"tree assembly",
				function(BT, role, probe)
					return constructionFixture(BT, role, probe, shape.depth, shape.width, adopt)
				end,
				if adopt then adoptionSupport else supported,
				8
			)
		end
	end
	add("actions-ordinary-width32", "Actions", "tree tick", function(BT, role, probe)
		return tickFixture(BT, role, probe, { width = 32 })
	end)
	for _, width in ipairs({ 1, 32, 128 }) do
		add(`actions-synchronous-width{width}`, "Actions", "tree tick", function(BT, role, probe)
			return tickFixture(BT, role, probe, { width = width, synchronous = true })
		end, actionSupport)
	end
	add("actions-mixed-running", "Actions", "tree tick with a suspended leaf", function(BT, role, probe)
		return tickFixture(BT, role, probe, { width = 16, synchronous = true, running = true })
	end, actionSupport)
	for _, mode in ipairs({ "sequence", "fallback", "dense", "switch" }) do
		add(
			`cancellation-{mode}`,
			"Cancellation",
			if mode == "switch" then "priority switch (two ticks)" else "tree tick",
			function(BT, role, probe)
				return cancellationFixture(BT, role, probe, mode)
			end,
			cancellationSupport
		)
	end
	return cases
end

return Workloads
