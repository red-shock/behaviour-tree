local Node = require(script.Parent.Node)
local Enums = require(script.Parent.Enums)

local ControlNode = {}
ControlNode.__index = ControlNode
setmetatable(ControlNode, Node)

function ControlNode.new(name: string | nil, nodeType: Enums.NodeType)
    if not Enums.NodeType[nodeType] then
        error("Invalid node type")
    end
    
    local self = Node.new(name)
    setmetatable(self, ControlNode)

    self.nodeType = nodeType
    return self
end

function ControlNode:addChild(child: Node.Node)
    if self.nodeType == Enums.NodeType.DECORATOR and #self.children == 1 then
        error("Decorator node can only have one child, remove the existing child first")
    end

    Node.addChild(self, child)
end

return ControlNode