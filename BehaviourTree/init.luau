local Tree = require(script.Tree)
local BehaviourTree = {}

BehaviourTree.new = function()
    local root = BehaviourTree.Node.new("Sequence")
    return Tree.new(root)
end

BehaviourTree.Node = require(script.Node)

return BehaviourTree