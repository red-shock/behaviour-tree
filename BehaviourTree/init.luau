local Tree = require(script.Tree)
local ExecutionNode = require(script.ExecutionNode)
local ControlNode = require(script.ControlNode)
local DecoratorNode = require(script.DecoratorNode)

local BehaviourTree = {}

BehaviourTree.new = function(root: ControlNode.ControlNode | nil)
	local node = root or BehaviourTree.ControlNode.new("Root", BehaviourTree.Enums.NodeType.FALLBACK)
	return Tree.new(node)
end

BehaviourTree.ExecutionNode = ExecutionNode
BehaviourTree.ControlNode = ControlNode
BehaviourTree.Enums = require(script.Enums)

BehaviourTree.ActionNode = {}
BehaviourTree.ConditionNode = {}
BehaviourTree.SequenceNode = {}
BehaviourTree.FallbackNode = {}
BehaviourTree.ParallelNode = {}
BehaviourTree.DecoratorNode = {
	Inverter = {},
	Succeeder = {},
	Failer = {},
	Repeater = {},
}

BehaviourTree.ActionNode.new = function(name: string | nil, fn: ExecutionNode.ActionFunction, isTerminator: boolean)
	return BehaviourTree.ExecutionNode.new(name, BehaviourTree.Enums.NodeType.ACTION, fn, isTerminator)
end
BehaviourTree.ConditionNode.new = function(
	name: string | nil,
	fn: ExecutionNode.ConditionFunction,
	isTerminator: boolean
)
	return BehaviourTree.ExecutionNode.new(name, BehaviourTree.Enums.NodeType.CONDITION, fn, isTerminator)
end
BehaviourTree.SequenceNode.new = function(name: string | nil)
	return BehaviourTree.ControlNode.new(name, BehaviourTree.Enums.NodeType.SEQUENCE)
end
BehaviourTree.FallbackNode.new = function(name: string | nil)
	return BehaviourTree.ControlNode.new(name, BehaviourTree.Enums.NodeType.FALLBACK)
end
BehaviourTree.ParallelNode.new = function(name: string | nil)
	return BehaviourTree.ControlNode.new(name, BehaviourTree.Enums.NodeType.PARALLEL)
end
BehaviourTree.DecoratorNode.new = function(
	name: string | nil,
	wrapperFn: (() -> boolean) -> nil | nil,
	onCompleteFn: ((boolean) -> boolean) | nil
)
	return DecoratorNode.new(name, wrapperFn, onCompleteFn)
end
BehaviourTree.DecoratorNode.Inverter.new = function(name: string | nil)
	return BehaviourTree.DecoratorNode.new(name or "Inverter", nil, function(result)
		return not result
	end)
end
BehaviourTree.DecoratorNode.Succeeder.new = function(name: string | nil)
	return BehaviourTree.DecoratorNode.new(name or "Succeeder", nil, function(_)
		return true
	end)
end
BehaviourTree.DecoratorNode.Failer.new = function(name: string | nil)
	return BehaviourTree.DecoratorNode.new(name or "Failer", nil, function(_)
		return false
	end)
end
BehaviourTree.DecoratorNode.Repeater.new = function(count: number, name: string | nil)
	return BehaviourTree.DecoratorNode.new(name or "Repeater", function(runChild)
		for _ = 1, count do
			runChild()
		end
		return true
	end)
end

return BehaviourTree
