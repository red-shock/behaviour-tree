local Node = require(script.Parent.Node)
local Enums = require(script.Parent.Enums)

export type ControlNode = {
    nodeType: Enums.NodeType,
    children: { Node.Node },
    childrenStatus: Enums.Status,
    addChild: (self: ControlNode, child: Node.Node | { Node.Node }) -> nil,
    removeChild: (self: ControlNode, child: Node.Node) -> nil,
    run: (self: ControlNode) -> Enums.Status,
}

local ControlNode = {}
ControlNode.__index = ControlNode
ControlNode.__class = "ControlNode"
ControlNode.validTypes = {
    Enums.NodeType.SEQUENCE,
    Enums.NodeType.FALLBACK,
    Enums.NodeType.PARALLEL,
    Enums.NodeType.DECORATOR,
}
setmetatable(ControlNode, Node)

function ControlNode.new(name: string | nil, nodeType: Enums.NodeType)
    if not table.find(ControlNode.validTypes, nodeType) then
        error("Invalid node type")
    end
    
    local self = setmetatable(Node.new(name), ControlNode)

    self.nodeType = nodeType
    self.children = {}
    self.minSuccess = nil
    self.maxFailure = nil
    self._runningThreads = {}
    self._statusTable = {}
    self._successCount = 0
    self._failureCount = 0
    self.__class = "ControlNode"
    return self
end

function ControlNode:addChild(child: Node.Node | { Node.Node })
    if #child == 0 then
        self:_addSingleNode(child)
    elseif #child > 1 then
        if self.nodeType == Enums.NodeType.DECORATOR then
            error("Decorator node can only have one child")
        end
        self:_addNodeList(child)
    else
        error("Child is not a valid Node or Node list")
    end
end

function ControlNode:_addSingleNode(child: Node.Node)
    if self.nodeType == Enums.NodeType.DECORATOR and #self.children == 1 then
        error("Decorator node can only have one child, remove the existing child first")
    end

    if child == self then
        error("Cannot add self as child")
    end

    local newChild = child:clone()
    newChild.parent = self
    table.insert(self.children, newChild)
    if self.tree then
        self.tree:_setTree(newChild)
    end
end

function ControlNode:_addNodeList(nodeList: { Node.Node })
    for _, node in ipairs(nodeList) do
       self:_addSingleNode(node)
    end
end

function ControlNode:removeChild(child: Node.Node)
    for i, v in pairs(self.children) do
        if v == child then
            child.parent = nil
            table.remove(self.children, i)
        end
    end
end

function ControlNode:remove()
    if not self.parent then
        error("Cannot remove root node")
    end

    for _, v in pairs(self.children) do
        v.parent = self.parent
        self.parent:addChild(v)
    end

    self.parent:removeChild(self)
    Node.remove(self)
end

function ControlNode:run()
    if self.nodeType == Enums.NodeType.SEQUENCE then
        return self:_runSequence()
    elseif self.nodeType == Enums.NodeType.FALLBACK then
        return self:_runFallback()
    elseif self.nodeType == Enums.NodeType.PARALLEL then
        return self:_runParallel()
    end
end

function ControlNode:_runSequence()
    for _, child in ipairs(self.children) do
        child:run()

        if child.status == Enums.Status.RUNNING then
            self.status = Enums.Status.RUNNING
            return self.status
        end

        if child.status == Enums.Status.FAILURE then
            self:_reset()
            self.status = Enums.Status.FAILURE
            return self.status
        end
    end
    self:_reset()
    self.status = Enums.Status.SUCCESS
    return self.status
end

function ControlNode:_runFallback()
    for _, child in ipairs(self.children) do
        child:run()

        if child.status == Enums.Status.RUNNING then
            self.status = Enums.Status.RUNNING
            return self.status
        end

        if child.status == Enums.Status.SUCCESS then
            self:_reset()
            self.status = Enums.Status.SUCCESS
            return self.status
        end
    end
    self:_reset()
    self.status = Enums.Status.FAILURE
    return self.status
end

function ControlNode:_reset()
    for node, status in pairs(self._statusTable) do
        if status == Enums.Status.RUNNING then
            if type(node._cancelThread) == "function" then
                self.tree:debugPrint(`{node.name} is running, cancelling thread`, Enums.DebugLevel.VERBOSE)
                node:_cancelThread()
            end
        end
    end
    self._statusTable = {}
    self._successCount = 0
    self._failureCount = 0
    self.status = Enums.Status.IDLE
end

function ControlNode:_validateParallel()
    local minSuccess = self.minSuccess or #self.children
    local maxFailure = self.maxFailure or 1
    if self._successCount >= minSuccess then
        self:_reset()
        self.status = Enums.Status.SUCCESS
        return self.status
    elseif self._failureCount >= maxFailure then
        self:_reset()
        self.status = Enums.Status.FAILURE
        return self.status
    end
end

function ControlNode:_runParallel()
    -- if we do not have a running node
    for _, child in ipairs(self.children) do
        self:_runChild(child)

        if child.status == Enums.Status.RUNNING then
            self.status = Enums.Status.RUNNING
            continue
        end

        if child.status == Enums.Status.SUCCESS and self._statusTable[child] == Enums.Status.RUNNING then
            self._statusTable[child] = Enums.Status.SUCCESS
            self._successCount += 1
            self:_validateParallel()
            if self.status == Enums.Status.SUCCESS then
                return self.status
            end
        elseif child.status == Enums.Status.FAILURE and self._statusTable[child] == Enums.Status.RUNNING then
            self._statusTable[child] = Enums.Status.FAILURE
            self._failureCount += 1
            self:_validateParallel()
            if self.status == Enums.Status.FAILURE then
                return self.status
            end
        end
    end
    return self.status
end

function ControlNode:_runChild(child: Node.Node)
    if not self._statusTable[child] then
        self._statusTable[child] = child:run()
    elseif child.status == Enums.Status.RUNNING then
        child:run()
    end
end

function ControlNode.isInstanceOf(node: any)
    return Node.isInstanceOf(node) and ControlNode.__class == node.__class
end

local function argIsInstanceOf(fn: any)
    return function(self, ...)
        local args = { ... }
        if #args > 0 and Node.isInstanceOf(args[1]) then
            return fn(self, ...)
        else
            error(`Argument 1 must be an instance of Node`)
        end
    end
end

Node.addChild = argIsInstanceOf(Node._addSingleNode)
Node.removeChild = argIsInstanceOf(Node.removeChild)

return ControlNode