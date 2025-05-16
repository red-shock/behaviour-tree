local Node = require(script.Parent.Node)
local Enums = require(script.Parent.Enums)

export type ConditionFunction = () -> boolean
export type ActionFunction = () -> nil

local ExecutionNode = {}
ExecutionNode.__index = ExecutionNode
ExecutionNode.validTypes = {
    Enums.NodeType.ACTION,
    Enums.NodeType.CONDITION,
}
setmetatable(ExecutionNode, Node)

function ExecutionNode.new(name: string | nil, nodeType: Enums.NodeType, fn: ConditionFunction | ActionFunction)
    if not table.find(ExecutionNode.validTypes, nodeType) then
        error("Invalid node type")
    end
    
    local self = Node.new(name)
    setmetatable(self, ExecutionNode)

    self.nodeType = nodeType
    self.fn = fn
    self.status = Enums.Status.IDLE
    return self
end

return ExecutionNode