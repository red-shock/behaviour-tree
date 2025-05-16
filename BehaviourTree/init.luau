local Tree = require(script.Tree)
local BehaviourTree = {}

BehaviourTree.new = function()
    local root = BehaviourTree.ControlNode.new("Root", BehaviourTree.Enums.NodeType.SEQUENCE)
    return Tree.new(root)
end

BehaviourTree.ExecutionNode = require(script.ExecutionNode)
BehaviourTree.ControlNode = require(script.ControlNode)
BehaviourTree.Enums = require(script.Enums)

return BehaviourTree