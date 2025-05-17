local Node = require(script.Parent.Node)
local Enums = require(script.Parent.Enums)

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
    
    local self = Node.new(name)
    setmetatable(self, ControlNode)

    self.nodeType = nodeType
    self.children = {}
    self.childrenStatus = Enums.Status.SUCCESS
    self.__class = "ControlNode"
    return self
end

function ControlNode:addChild(child: Node.Node | { Node.Node })
    if #child == 0 then
        self:_addSingleNode(child)
    elseif #child > 1 then
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

    child.parent = self
    table.insert(self.children, child)
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
    elseif self.nodeType == Enums.NodeType.DECORATOR then
        return self:_runDecorator()
    end
end

function ControlNode:_runSequence()
    for _, child in ipairs(self.children) do
        local status = child:run()

        if status == Enums.Status.RUNNING then
            self.childrenStatus = Enums.Status.RUNNING
            return self.childrenStatus
        end

        if status == Enums.Status.FAILURE then
            self.childrenStatus = Enums.Status.FAILURE
            return self.childrenStatus
        end
    end
    self.childrenStatus = Enums.Status.SUCCESS
    return self.childrenStatus
end

function ControlNode:_runFallback()
    for _, child in ipairs(self.children) do
        local status = child:run()

        if status == Enums.Status.RUNNING then
            self.childrenStatus = Enums.Status.RUNNING
            return self.childrenStatus
        end

        if status == Enums.Status.SUCCESS then
            self.childrenStatus = Enums.Status.SUCCESS
            return self.childrenStatus
        end
    end
    self.childrenStatus = Enums.Status.FAILURE
    return self.childrenStatus
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