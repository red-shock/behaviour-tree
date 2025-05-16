local Node = require(script.Parent.Node)
local Enums = require(script.Parent.Enums)

local ControlNode = {}
ControlNode.__index = ControlNode
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
    return self
end

function ControlNode:addChild(child: Node.Node)
    if self.nodeType == Enums.NodeType.DECORATOR and #self.children == 1 then
        error("Decorator node can only have one child, remove the existing child first")
    end

    if child == self then
        error("Cannot add self as child")
    end

    child.parent = self
    table.insert(self.children, child)
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

Node.addChild = argIsInstanceOf(Node.addChild)
Node.removeChild = argIsInstanceOf(Node.removeChild)

return ControlNode