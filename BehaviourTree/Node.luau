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
	self.tree = nil
	self.name = name or "Node"
	self.status = Enums.Status.IDLE
	return self
end

function Node:remove()
	if not self.parent then
		error("Cannot remove root node")
	end

	self.parent = nil
	self.tree = nil
end

function Node:isLeaf()
	return not self.children
end

function Node:isRoot()
	return self.parent == nil
end

function Node:pause()
	self.status = Enums.Status.IDLE
end

function Node:clone()
	local function deepCopy(orig, copies)
		copies = copies or {}
		local orig_type = type(orig)
		local copy
		if orig_type == "table" then
			if copies[orig] then
				copy = copies[orig]
			else
				copy = {}
				copies[orig] = copy
				for orig_key, orig_value in next, orig, nil do
					copy[deepCopy(orig_key, copies)] = deepCopy(orig_value, copies)
				end
				setmetatable(copy, getmetatable(orig))
			end
		else -- number, string, boolean, etc
			copy = orig
		end
		return copy
	end
	return deepCopy(self)
end

function Node.findTree(node: Node)
	local current = node
	while current do
		if current.__class == "Tree" then
			return current
		end
		current = current.parent
	end
	return nil
end

function Node.isInstanceOf(node: any)
	local mt = getmetatable(node)
	while mt do
		if rawequal(mt, Node) then
			return true
		end
		mt = getmetatable(mt)
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
