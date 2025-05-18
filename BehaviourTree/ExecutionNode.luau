local Node = require(script.Parent.Node)
local Enums = require(script.Parent.Enums)

export type ConditionFunction = () -> boolean
export type ActionFunction = () -> nil

local ExecutionNode = {}
ExecutionNode.__index = ExecutionNode
ExecutionNode.__class = "ExecutionNode"
ExecutionNode.validTypes = {
    Enums.NodeType.ACTION,
    Enums.NodeType.CONDITION,
}
setmetatable(ExecutionNode, Node)

function ExecutionNode.new(name: string | nil, nodeType: Enums.NodeType, fn: ConditionFunction | ActionFunction, isTerminator: boolean)
    if not table.find(ExecutionNode.validTypes, nodeType) then
        error("Invalid node type")
    end
    
    if nodeType == Enums.NodeType.CONDITION and isTerminator then
        warn("Condition node cannot be a terminator")
    end
    
    local self = Node.new(name)
    setmetatable(self, ExecutionNode)

    self.nodeType = nodeType
    self.fn = fn
    self.status = Enums.Status.IDLE
    self.isTerminator = isTerminator or false
    self._functionConnections = {}
    self.__class = "ExecutionNode"
    return self
end

function ExecutionNode:run()
    if self.status == Enums.Status.RUNNING then
        return self.status
    end

    if self.nodeType == Enums.NodeType.ACTION then
        self:_runAction()
        elseif self.nodeType == Enums.NodeType.CONDITION then
        self.status = Enums.Status.RUNNING
        local result = self.fn()
        self.status = result and Enums.Status.SUCCESS or Enums.Status.FAILURE
    end
    return self.status
end

function ExecutionNode:_runAction()
    local connectionId = tick()
    local thread = task.spawn(function()
        self.status = Enums.Status.RUNNING
        self.fn()
        self.status = Enums.Status.SUCCESS
        if self.isTerminator then
            if self.tree == nil then
                error("Tree is not set, cannot terminate")
            end
            self.tree:pause()
        end
        self._functionConnections[connectionId] = nil
    end)
    self._functionConnections[connectionId] = thread
end

function ExecutionNode:_cancelThreads()
    for connectionId, _ in pairs(self._functionConnections) do
        task.cancel(self._functionConnections[connectionId])
        self._functionConnections[connectionId] = nil
    end
end

function ExecutionNode.isInstanceOf(node: any)
    return Node.isInstanceOf(node) and ExecutionNode.__class == node.__class
end

function ExecutionNode:isLeaf()
    return true
end

return ExecutionNode