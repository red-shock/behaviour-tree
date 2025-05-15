local Enums = require(script.Parent.Enums)
export type Node = {
    __index: Node,
    parent: Node | nil,
    name: string | nil,
    children: { Node },
}

local Node = {}

Node.__index = Node

function Node.new(name: string | nil)
    local self = setmetatable({}, Node)
    self.parent = nil
    self.name = name or "Node"
    self.children = {}
    self.status = Enums.Status.IDLE
    return self
end

function Node:addChild(child: Node)
    if child == self then
        error("Cannot add self as child")
    end

    child.parent = self
    table.insert(self.children, child)
end

function Node:removeChild(child: Node)
    for i, v in pairs(self.children) do
        if v == child then
            child.parent = nil
            table.remove(self.children, i)
        end
    end
end

function Node:remove()
    if not self.parent then
        error("Cannot remove root node")
    end

    for _, v in pairs(self.children) do
        v.parent = self.parent
        self.parent:addChild(v)
    end

    self.parent:removeChild(self)
    self.parent = nil
end

function Node.isInstanceOf(node: any)
    return getmetatable(node) == Node
end

Node.__eq = function(a: Node, b: Node)
    if Node.isInstanceOf(a) and Node.isInstanceOf(b) then
        return a.name == b.name and a.parent == b.parent
    end
end

Node.__tostring = function(self)
    return self.name
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

return Node