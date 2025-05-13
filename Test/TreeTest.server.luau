local ServerScriptService = game:GetService("ServerScriptService")
local BT = require(ServerScriptService.BehaviourTree)

local tree = BT.new()
local idleNode = BT.Node.new("Idle")
local moveNode = BT.Node.new("Move")
local attackNode = BT.Node.new("Attack")

tree:addChild({idleNode, moveNode, attackNode})
print(tree)