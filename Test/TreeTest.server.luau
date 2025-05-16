local ServerScriptService = game:GetService("ServerScriptService")
local BT = require(ServerScriptService.BehaviourTree)

local tree = BT.new()
local idleNode = BT.ExecutionNode.new("Idle", BT.Enums.NodeType.ACTION)
local moveNode = BT.ExecutionNode.new("Move", BT.Enums.NodeType.ACTION)
local attackNode = BT.ExecutionNode.new("Attack", BT.Enums.NodeType.ACTION)

tree:addChild({idleNode, moveNode, attackNode})
print(tree)