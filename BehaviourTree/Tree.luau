local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Node = require(script.Parent.Node)
local Enums = require(script.Parent.Enums)

export type Tree = {
	root: Node.Node | nil,
	currentNode: Node.Node | nil,
	paused: boolean,
}

local Tree = {}
Tree.__index = Tree
Tree.__class = "Tree"

function Tree.new(root: Node.Node)
	local self = setmetatable({}, Tree)
	self.currentNode = root
	self.uuid = HttpService:GenerateGUID(false)
	self.paused = false
	self.Paused = Instance.new("BindableEvent") :: BindableEvent
	self.debugLevel = Enums.DebugLevel.NONE
	self:_addSingleNode(root)
	return self
end

function Tree:addChild(child: Node.Node | { Node.Node })
	if #child == 0 then
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

	for _, child in ipairs(nodeList) do
		self:_addSingleNode(child)
	end
end

function Tree:_addSingleNode(node: Node.Node)
	if not self.root then
		self:_setRoot(node)
		self:_setTree(self.root)
	else
		self.root:addChild(node)
	end
end

function Tree:_setTree(node: Node.Node)
	local function setTree(child: Node.Node)
		if child.children then
			for _, n in ipairs(child.children) do
				setTree(n)
			end
		end
		child.tree = self
	end
	setTree(node)
end

function Tree:_setRoot(node)
	if self.root or not Node.isInstanceOf(node) then
		error(`Root cannot be set to {node}`)
	end
	self.root = node:clone()
	self.root.name = self.uuid
end

function Tree:run()
	if self.paused then
		return
	end

	if not self.root then
		error("Tree has no root node")
	end

	if self.root.status ~= Enums.Status.RUNNING and not self.paused then
		self:debugPrint("TICK BEGIN", Enums.DebugLevel.BASIC)
	end
	self.root:run()
end

function Tree:pause()
	self.paused = true
	local function pauseNode(node: Node.Node)
		for _, child in ipairs(node.children) do
			if not child:isLeaf() then
				pauseNode(child)
			else
				child:pause()
			end
		end
	end
	pauseNode(self.root)
	self.Paused:Fire()
end

function Tree:cancelActiveExecutionActions()
	if not self.root then
		error("Tree has no root node")
	end

	local function cancelActions(node: Node.Node)
		if type(node._cancelThread) == "function" then
			node:_cancelThread()
		else
			for _, child in ipairs(node.children) do
				cancelActions(child)
			end
		end
	end

	cancelActions(self.root)
end

function Tree:debugPrint(str: string, debugLevel: number?)
	debugLevel = debugLevel or 1
	if self.debugLevel < debugLevel then
		return
	end
	if RunService:IsStudio() then
		print(`[BehaviourTree:{self.uuid}]: {str}`)
	end
end

Tree.__tostring = function(self)
	if not self.root then
		return "Tree is empty"
	end

	local str = "\n" .. self.root.name .. " : " .. self.root.nodeType
	local function recursivePrint(node, prefix, isLast)
		prefix = prefix or ""
		local connector = isLast and "└─ " or "├─ "
		str = str .. "\n" .. prefix .. connector .. node.name .. " : " .. node.nodeType

		local children = node.children or {}
		for i, child in ipairs(children) do
			local newPrefix = prefix .. (isLast and "   " or "│  ")
			recursivePrint(child, newPrefix, i == #children)
		end
	end
	for _, child in ipairs(self.root.children) do
		recursivePrint(child, "" .. "  ")
	end
	return str
end

return Tree
