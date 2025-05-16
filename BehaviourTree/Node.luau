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
    self.status = Enums.Status.IDLE
    return self
end

function Node:remove()
    if not self.parent then
        error("Cannot remove root node")
    end
    
    self.parent = nil
end

function Node.isInstanceOf(node: any)
    local mt = getmetatable(node)
	while mt do
		if mt == Node then
			return true
		end
		mt = getmetatable(mt)  -- move up the inheritance chain
	end
	return false
end

Node.__eq = function(a: Node, b: Node)
    if Node.isInstanceOf(a) and Node.isInstanceOf(b) then
        return a.name == b.name and a.parent == b.parent
    end
end

Node.__tostring = function(self)
    return self.name or "Node"
end

return Node