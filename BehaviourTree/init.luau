local Tree = require(script.Tree)
local ExecutionNode = require(script.ExecutionNode)
local ControlNode = require(script.ControlNode)

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

BehaviourTree.ActionNode.new = function(name: string | nil, fn: ExecutionNode.ActionFunction, isTerminator: boolean)
    return BehaviourTree.ExecutionNode.new(name, BehaviourTree.Enums.NodeType.ACTION, fn, isTerminator)
end
BehaviourTree.ConditionNode.new = function(name: string | nil, fn: ExecutionNode.ConditionFunction, isTerminator: boolean)
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

return BehaviourTree