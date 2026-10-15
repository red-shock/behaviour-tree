local Suite = if script then require(script.Parent.Parent.Suite) else require("../Suite")
local Tree = if script then require(script.Parent.Parent.Fixtures.Tree) else require("../Fixtures/Tree")

local function adoptionSupport(BT, role)
	if role == "candidate" and not (BT.adopt and BT.ControlNode.adoptChild) then
		return "BT.adopt/adoptChild are not available"
	end
	return nil
end

local function fixture(BT, role, probe, depth, width, adoption)
	local trees = {}
	local copiedNodes, cloneCalls = 0, 0
	local adopt = adoption and role == "candidate"
	local function instrument(node)
		if probe then
			local clone = node.clone
			node.clone = function(self)
				cloneCalls += 1
				copiedNodes += Tree.nodeCount(self)
				return clone(self)
			end
		end
		return node
	end
	local function build(level)
		if level == 0 then
			return instrument(BT.ActionNode.new("Leaf", Tree.noOp, false))
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
		verify = function(iterations, test)
			test("constructs one tree per operation", function()
				assert(#trees == iterations, `Expected {iterations} trees, got {#trees}`)
			end)
			test("preserves cloning or adoption ownership", function()
				for index, entry in ipairs(trees) do
					assert(
						rawequal(entry.tree.root, entry.suppliedRoot) == adopt,
						`Tree {index}: incorrect root identity`
					)
				end
			end)
			test("retains every node", function()
				for index, entry in ipairs(trees) do
					local actual = Tree.nodeCount(entry.tree.root)
					assert(actual == expectedNodes, `Tree {index}: expected {expectedNodes} nodes, got {actual}`)
				end
			end)
			test("binds every descendant to its tree", function()
				for index, entry in ipairs(trees) do
					Tree.visit(entry.tree.root, function(node)
						assert(
							rawequal(node.tree, entry.tree),
							`Tree {index}, node {node.name}: incorrect tree binding`
						)
					end)
				end
			end)
			test("binds every child to its parent", function()
				for index, entry in ipairs(trees) do
					Tree.visit(entry.tree.root, function(node)
						for _, child in ipairs(node.children or {}) do
							assert(
								rawequal(child.parent, node),
								`Tree {index}, child {child.name}: incorrect parent binding`
							)
						end
					end)
				end
			end)
			test("executes each constructed tree successfully", function()
				for index, entry in ipairs(trees) do
					entry.tree:run()
					assert(entry.tree.root.status == BT.Enums.Status.SUCCESS, `Tree {index}: execution did not succeed`)
				end
			end)
			return `{iterations}:{expectedNodes}`
		end,
		metrics = function()
			return { copiedNodes = copiedNodes, cloneCalls = cloneCalls, nodesPerTree = expectedNodes }
		end,
		cleanup = function()
			local errors = {}
			for index, entry in ipairs(trees) do
				local ok, message = pcall(Tree.destroy, entry.tree)
				if not ok then
					table.insert(errors, `Tree {index}: {message}`)
				end
			end
			table.clear(trees)
			assert(#errors == 0, table.concat(errors, "; "))
		end,
	}
end

return Suite.describe("Construction", function(test)
	for _, shape in ipairs({
		{ name = "wide", depth = 1, width = 32 },
		{ name = "deep", depth = 12, width = 1 },
		{ name = "balanced", depth = 3, width = 3 },
	}) do
		for _, adopt in ipairs({ false, true }) do
			test(
				`{shape.name} tree using {if adopt then "adoption against cloning" else "cloning on both revisions"}`,
				{
					id = `construction-{if adopt then "adopt" else "clone"}-{shape.name}`,
					unit = "tree assembly",
					unsupported = if adopt then adoptionSupport else nil,
					maxIterations = 8,
					create = function(BT, role, probe)
						return fixture(BT, role, probe, shape.depth, shape.width, adopt)
					end,
				}
			)
		end
	end
end)
