local Node = require(script.Parent.Node)

local Tree = {}
Tree.__index = Tree

function Tree.new(root : Node.Node | nil)
    local self = setmetatable({}, Tree)
    self.root = root
    return self
end

function Tree:addChild(child: Node.Node | { Node.Node })
    if #child == 1 then
        self:_addSingleNode(child)
    elseif #child > 1 then
        self:_addNodeList(child)
    else
        error("Child is not a valid Node or Node list")
    end
end

function Tree:_addNodeList(nodeList: { Node.Node })
    if not self.root then
        error("Root is not set")
    end
    
    for _, node in ipairs(nodeList) do
       self:_addSingleNode(node) 
    end
end

function Tree:_addSingleNode(node: Node.Node)
    if not Node.isInstanceOf(node) then
        error(`Node is not an instance of Node: ${node}`)
    end

    if not self.root then
        self._setRoot(node)
    else
        self.root:addChild(node)
    end
end

function Tree:_setRoot(node)
    if self.root or not Node.isInstanceOf(self.root) then
        error(`Root cannot be set to ${node}`)
    end
    self.root = node
end

Tree.__tostring = function(self)
    if not self.root then
        return "Tree is empty"
    end
    
    local str = "\n"..self.root.name
    local function recursivePrint(node, prefix, isLast)
        prefix = prefix or ""
        local connector = isLast and "└─ " or "├─ "
        str = str.. "\n" .. prefix .. connector .. node.name
    
        local children = node.children or {}
        for i, child in ipairs(children) do
            local newPrefix = prefix .. (isLast and "   " or "│  ")
            recursivePrint(child, newPrefix, i == #children)
        end
    end
    for _, child in ipairs(self.root.children) do
        recursivePrint(child, "".."  ")
    end
    return str
end

return Tree