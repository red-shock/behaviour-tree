local Tree = if script then require(script.Parent.Tree) else require("./Tree")

local function fixture(BT, _, probe, mode)
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
		Tree.visit(tree.root, function(node)
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
		verify = function(iterations, test)
			local expected = if mode == "sequence" then BT.Enums.Status.FAILURE else BT.Enums.Status.SUCCESS
			test("returns the expected root status", function()
				assert(tree.root.status == expected, `Expected {expected}, got {tree.root.status}`)
			end)
			test("releases every owned coroutine", function()
				Tree.visit(tree.root, function(node)
					assert(node._coroutine == nil, `Node {node.name} still owns a coroutine`)
				end)
			end)
			if probe then
				test("invokes only the expected callbacks", function()
					local perIteration = if mode == "dense" then 64 elseif mode == "switch" then 3 else 1
					local expectedCalls = perIteration * iterations
					assert(#trace == expectedCalls, `Expected {expectedCalls} callbacks, got {#trace}`)
				end)
			end
			return if probe then table.concat(trace, ",") else expected
		end,
		metrics = function()
			return { cancellationCalls = cancellations, callbackCalls = #trace }
		end,
		cleanup = function()
			Tree.destroy(tree)
		end,
	}
end

return fixture
