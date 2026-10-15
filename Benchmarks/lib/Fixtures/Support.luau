local Tree = if script then require(script.Parent.Tree) else require("./Tree")

local Support = {}

function Support.synchronousActions(BT, role)
	if role == "candidate" and not (BT.SynchronousActionNode and BT.SynchronousActionNode.new) then
		return "SynchronousActionNode.new is not available"
	end
	return nil
end

function Support.nodeAdoption(BT, role)
	if role == "candidate" and not (BT.adopt and BT.ControlNode.adoptChild) then
		return "BT.adopt/adoptChild are not available"
	end
	return nil
end

function Support.parallelAccounting(BT)
	local root = BT.ParallelNode.new("AccountingGate")
	root:addChild(BT.ActionNode.new("First", Tree.noOp, false))
	root:addChild(BT.ActionNode.new("Second", Tree.noOp, false))
	local tree = BT.new(root)
	local ok, status = pcall(function()
		tree:run()
		return tree.root.status
	end)
	Tree.destroy(tree)
	if not ok or status ~= BT.Enums.Status.SUCCESS then
		return "Requires correct immediate parallel accounting on BOTH revisions"
	end
	return nil
end

function Support.cancellation(BT)
	if type(BT.ControlNode._cancel) ~= "function" then
		return "Requires recursive cancellation on BOTH revisions"
	end
	return Support.parallelAccounting(BT)
end

return Support
