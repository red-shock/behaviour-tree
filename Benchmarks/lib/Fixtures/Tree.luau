local Tree = {}

function Tree.noOp() end

function Tree.destroy(tree)
	local ok, message = pcall(tree.cancelActiveExecutionActions, tree)
	tree.Paused:Destroy()
	assert(ok, message)
end

function Tree.visit(node, callback)
	callback(node)
	for _, child in ipairs(node.children or {}) do
		Tree.visit(child, callback)
	end
end

function Tree.nodeCount(node)
	local count = 0
	Tree.visit(node, function()
		count += 1
	end)
	return count
end

return Tree
