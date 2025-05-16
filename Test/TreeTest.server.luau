local ServerScriptService = game:GetService("ServerScriptService")
local Rig = game.Workspace:WaitForChild("Rig")
local Humanoid = Rig:WaitForChild("Humanoid")

local BT = require(ServerScriptService.BehaviourTree)

local tree = BT.new()
local isDeadSequence = BT.ControlNode.new("IsDeadSequence", BT.Enums.NodeType.SEQUENCE)
local isDeadCondition = BT.ExecutionNode.new("isDead?", BT.Enums.NodeType.CONDITION, function()
    return Humanoid.Health <= 0
end)
local dieAction = BT.ExecutionNode.new("Die", BT.Enums.NodeType.ACTION, function()
    Humanoid.Health = 0
    print(`#{Rig.Name} Died`)
end)
local idleAction = BT.ExecutionNode.new("Idle", BT.Enums.NodeType.ACTION, function()
    print(`#{Rig.Name} is idling`)
end)

isDeadSequence:addChild({isDeadCondition, dieAction})
tree:addChild({isDeadSequence, idleAction})
print(tree)