local Node = require(script.Parent.Node)
local Enums = require(script.Parent.Enums)

export type ExecutionNode = {
    name: string | nil,
    nodeType: Enums.NodeType,
    fn: ConditionFunction | ActionFunction,
    status: Enums.Status,
    isTerminator: boolean,
    _functionConnections: { [number]: thread },
    tree: any, -- Reference to the tree this node belongs to
}

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
        isTerminator = false
        warn("Condition node cannot be a terminator")
    end
    
    local self = Node.new(name)
    setmetatable(self, ExecutionNode)

    self.nodeType = nodeType
    self.fn = fn
    self.status = Enums.Status.IDLE
    self.isTerminator = isTerminator or false
    self._coroutine = nil
    self.__class = "ExecutionNode"
    return self
end

function ExecutionNode:run()
    if not self._coroutine then
        self._coroutine = {
            success = true,
            result = nil,
        }
        
        self._coroutine.fn = coroutine.create(function()
            local success, result = pcall(self.fn)
            self._coroutine.success = success
            self._coroutine.result = result
        end)

        coroutine.resume(self._coroutine.fn)
        self.status = Enums.Status.RUNNING
    else
        if coroutine.status(self._coroutine.fn) == "dead" then
            self.tree:debugPrint(`{self.name} coroutine is dead, resetting. Success: {self._coroutine.success}, Result: {self._coroutine.result}`, 2)
            if not self._coroutine.success then
                self.status = Enums.Status.FAILURE
            else
                if self.nodeType == Enums.NodeType.ACTION then
                    self.status = Enums.Status.SUCCESS
                    if self.isTerminator then
                        if not self.tree then
                            error("Tree is not set, cannot pause")
                        end
                        self.tree:pause()
                    end
                elseif self.nodeType == Enums.NodeType.CONDITION then
                    self.status = self._coroutine.result and Enums.Status.SUCCESS or Enums.Status.FAILURE
                end
            end
            self._coroutine = nil
        end
    end
    return self.status
end

function ExecutionNode:_cancelThread()
    if self._coroutine then
        if self._coroutine.fn then
            coroutine.close(self._coroutine.fn)
        end
        self._coroutine = nil
    end
end

function ExecutionNode.isInstanceOf(node: any)
    return Node.isInstanceOf(node) and ExecutionNode.__class == node.__class
end

function ExecutionNode:isLeaf()
    return true
end

return ExecutionNode