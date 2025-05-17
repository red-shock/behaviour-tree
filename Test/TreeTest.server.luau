local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Rig = game.Workspace:WaitForChild("Rig")
local Humanoid = Rig:WaitForChild("Humanoid")

local BT = require(ServerScriptService.BehaviourTree)

local tree = BT.new()
local isDeadSequence = BT.ControlNode.new("IsDeadSequence", BT.Enums.NodeType.SEQUENCE)
local isDeadCondition = BT.ExecutionNode.new("isDead?", BT.Enums.NodeType.CONDITION, function()
    return Humanoid.Health <= 0
end)
local dieAction = BT.ExecutionNode.new("Die", BT.Enums.NodeType.ACTION, function()
    Humanoid.parent:Destroy()
    print(`#{Rig.Name} Died`)
end, true)
local idleAction = BT.ExecutionNode.new("Idle", BT.Enums.NodeType.ACTION, function()
    print(`#{Rig.Name} is idling`)
end)

isDeadSequence:addChild({isDeadCondition, dieAction})
tree:addChild({isDeadSequence, idleAction})
print(tree)

local connection
tree.Paused.Event:Connect(function()
    print("Tree paused")
    if connection then
        connection:Disconnect()
    end
end)

connection = RunService.Heartbeat:Connect(function()
    tree:run()
end)
