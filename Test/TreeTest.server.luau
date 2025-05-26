local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Rig = game.Workspace:WaitForChild("Rig")
local Humanoid = Rig:WaitForChild("Humanoid")

local BT = require(ServerScriptService.BehaviourTree)

local tree = BT.new()
tree.debugLevel = 1

local isDeadSequence = BT.SequenceNode.new("IsDeadSequence")
local isDeadCondition = BT.ConditionNode.new("isDead?", function()
    return Humanoid.Health <= 0
end)
local dieAction = BT.ActionNode.new("Die", function()
    Humanoid.parent:Destroy()
    print(`#{Rig.Name} Died`)
end, true)

local isWalkSequence = BT.SequenceNode.new("IsWalkSequence")
local isWalkCondition = BT.ConditionNode.new("isWalking?", function()
    return true
end)
local walkAction = BT.ActionNode.new("Walk", function()
    print(`#{Rig.Name} is walking`)
    task.wait(5)
    print(`#{Rig.Name} has walked`)
end)

local idleAction = BT.ActionNode.new("Idle", function()
    print(`#{Rig.Name} is idling`)
end)

isDeadSequence:addChild({isDeadCondition, dieAction})
isWalkSequence:addChild({isWalkCondition, walkAction})
tree:addChild({isDeadSequence, isWalkSequence, idleAction})
print(tree)

local connection
tree.Paused.Event:Connect(function()
    print("Tree paused")
    tree:cancelActiveExecutionActions()
    if connection then
        connection:Disconnect()
    end
end)

connection = RunService.Heartbeat:Connect(function(dt)
    tree:run()
end)


