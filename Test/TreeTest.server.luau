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
--tree:addChild({isDeadSequence, isWalkSequence, idleAction})
--print(tree)

local parallelNode = BT.ParallelNode.new("ParallelNode")
local failer = BT.DecoratorNode.Repeater.new(3)
local printAction1 = BT.ActionNode.new("PrintAction1", function()
    print("Action 1 executed")
end)
failer:addChild(printAction1)

local printAction2 = BT.ActionNode.new("PrintAction2", function()
    print("Action 2 executed")
end)
local printAction3 = BT.ActionNode.new("PrintAction3", function()
    print("Action 3 executed")
end)

print("adding children to parallel node")
parallelNode:addChild({failer, printAction2, printAction3})

print("adding parallel node to tree")
local pTree = BT.new(parallelNode)
pTree.debugLevel = 1

print(pTree)

local connection
tree.Paused.Event:Connect(function()
    print("Tree paused")
    tree:cancelActiveExecutionActions()
    if connection then
        connection:Disconnect()
    end
end)

connection = RunService.Heartbeat:Connect(function(dt)
    pTree:run()
end)


