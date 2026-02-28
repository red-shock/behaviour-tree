# Behaviour Tree

An extensible, configurable behaviour tree module useful for creating complex NPC behaviours from designing NPC actions and conditions.

## Getting Started

Import BehaviourTree like so,

```lua
local BT = require(Packages.BehaviourTree)
```

<details>
    <summary>For developer builds</summary><br>

> Run `test.project.json` when using Rojo in order to load the files into roblox studio.
>
> ```zsh
> rojo serve ./test.project.json
> ```

</details>

---

## Core Concepts

A behaviour tree is made up of **nodes** arranged in a hierarchy. The tree is evaluated ("ticked") each frame (or at whatever interval you choose). On each tick the tree walks its nodes from top to bottom, left to right, and every node returns one of three statuses:

| Status    | Meaning                                                       |
| --------- | ------------------------------------------------------------- |
| `SUCCESS` | The node finished its work successfully.                      |
| `FAILURE` | The node could not complete its work.                         |
| `RUNNING` | The node is still in progress and needs more ticks to finish. |

A fourth internal status, `IDLE`, indicates a node that has not yet been evaluated.

### Creating & Running a Tree

```lua
local BT = require(Packages.BehaviourTree)

-- Create a tree (defaults to a Fallback root if none is provided)
local tree = BT.new()

-- Optionally set debug output (0 = none, 1 = basic, 2 = transitions, 3 = verbose)
tree.debugLevel = 1

-- Add children to the tree
tree:addChild(mySequenceNode)

-- Tick the tree every frame
RunService.Heartbeat:Connect(function()
    tree:run()
end)
```

You can also pass a root control node directly:

```lua
local root = BT.SequenceNode.new("Root")
local tree = BT.new(root)
```

---

## Execution Nodes (Leaf Nodes)

Execution nodes are the leaves of the tree - they do the actual work. There are two kinds: **Action** nodes and **Condition** nodes.

### Action Nodes

An action node runs a function that performs a side-effect (move an NPC, play an animation, etc.).

```lua
local walkAction = BT.ActionNode.new("Walk", function()
    print("NPC is walking")
    task.wait(3) -- simulate work over several frames
    print("NPC finished walking")
end)
```

**How status is determined:**

| Outcome                                                                         | Status    |
| ------------------------------------------------------------------------------- | --------- |
| The function returns normally (no error)                                        | `SUCCESS` |
| The function throws an error (`error()` / unhandled exception)                  | `FAILURE` |
| The function yields (e.g. `task.wait()`) and the coroutine has not finished yet | `RUNNING` |

Because action functions are wrapped in a coroutine, any call that **yields** (such as `task.wait()`, `:MoveTo()`, or any async pattern) will cause the node to return `RUNNING` on that tick. On the next tick the coroutine is resumed; once it finishes the node reports `SUCCESS` or `FAILURE`.

#### Terminator Actions

Pass `true` as the third argument to create a **terminator** action. When a terminator action succeeds, it automatically pauses the entire tree - useful for "one-shot" goals like dying:

```lua
local dieAction = BT.ActionNode.new("Die", function()
    humanoid.Parent:Destroy()
end, true) -- isTerminator = true
```

#### Pausing & Cancelling

When a terminator action succeeds the tree is paused automatically. You can hook into this (or any manual `tree:pause()` call) with `tree.Paused.Event`:

```lua
tree.Paused.Event:Connect(function()
    tree:cancelActiveExecutionActions() -- cancels any in-flight coroutines
end)
```

Calling `tree:cancelActiveExecutionActions()` cleans up any coroutines that are still `RUNNING` when the tree stops. Only if you do **not** want running nodes to complete, call this method.

### Condition Nodes

A condition node evaluates a boolean predicate. It **cannot** be a terminator.

```lua
local isDead = BT.ConditionNode.new("isDead?", function()
    return humanoid.Health <= 0
end)
```

**How status is determined:**

| Return value                            | Status    |
| --------------------------------------- | --------- |
| `true`                                  | `SUCCESS` |
| `false` / `nil`                         | `FAILURE` |
| Function throws an error                | `FAILURE` |
| Function yields and hasn't finished yet | `RUNNING` |

Condition nodes are typically instant (no yielding), so they resolve to `SUCCESS` or `FAILURE` within one or two ticks.

---

## Control Nodes

Control nodes have one or more children and determine the **order and logic** with which those children are evaluated.

### Sequence Node

Runs its children **left-to-right**. Succeeds only if **all** children succeed. Fails as soon as **any** child fails.

```lua
local seq = BT.SequenceNode.new("AttackSequence")
seq:addChild({ isEnemyNearby, moveToEnemy, attackEnemy })
```

| Child returns | Sequence behaviour                                                           |
| ------------- | ---------------------------------------------------------------------------- |
| `SUCCESS`     | Move to the next child.                                                      |
| `FAILURE`     | Stop immediately - the sequence returns `FAILURE`.                           |
| `RUNNING`     | Stop - the sequence returns `RUNNING` and resumes from this child next tick. |

Think of a sequence as an **AND**: every child must succeed for the whole sequence to succeed.

### Fallback Node

Runs its children **left-to-right**. Succeeds as soon as **any** child succeeds. Fails only if **all** children fail.

```lua
local fallback = BT.FallbackNode.new("FindActivity")
fallback:addChild({ attackSequence, patrolSequence, idleAction })
```

| Child returns | Fallback behaviour                                                           |
| ------------- | ---------------------------------------------------------------------------- |
| `SUCCESS`     | Stop immediately - the fallback returns `SUCCESS`.                           |
| `FAILURE`     | Move to the next child.                                                      |
| `RUNNING`     | Stop - the fallback returns `RUNNING` and resumes from this child next tick. |

Think of a fallback as an **OR**: it tries each option until one works.

### Parallel Node

Runs **all** children on every tick (children that are already `RUNNING` are resumed rather than restarted). The result is governed by two thresholds:

- `minSuccess` - how many children must succeed for the parallel node to succeed (default: all children).
- `maxFailure` - how many children may fail before the parallel node fails (default: 1).

```lua
local parallel = BT.ParallelNode.new("LookAndWalk")
parallel.minSuccess = 2  -- succeed when at least 2 children succeed
parallel.maxFailure = 1  -- fail if any single child fails
parallel:addChild({ lookAroundAction, walkAction, playMusicAction })
```

While neither threshold is met the node stays `RUNNING`.

---

## Decorator Nodes

A decorator wraps a **single** child and modifies its result or controls how many times it runs. You can create a fully custom decorator, or use one of the built-in presets.

### Custom Decorator

```lua
local decorator = BT.DecoratorNode.new(
    "MyDecorator",
    function(runChild) -- wrapperFn: controls *how* the child is executed
        runChild()
    end,
    function(result) -- onCompleteFn: transforms the final boolean result
        return result
    end
)
decorator:addChild(someActionNode)
```

### Built-in Decorators

#### Inverter

Flips the child's result: `SUCCESS` becomes `FAILURE` and vice-versa.

```lua
local inverter = BT.DecoratorNode.Inverter.new("NotDead")
inverter:addChild(isDeadCondition)
```

#### Succeeder

Always returns `SUCCESS` regardless of the child's result.

```lua
local succeeder = BT.DecoratorNode.Succeeder.new()
succeeder:addChild(optionalAction)
```

#### Failer

Always returns `FAILURE` regardless of the child's result.

```lua
local failer = BT.DecoratorNode.Failer.new()
failer:addChild(someAction)
```

#### Repeater

Runs the child a fixed number of times, then returns `SUCCESS`.

```lua
local repeater = BT.DecoratorNode.Repeater.new(3, "RepeatThrice")
repeater:addChild(patrolAction)
```

---

## Putting It All Together

Below is a complete example showing a simple NPC that checks if it's dead, otherwise walks, and falls back to idling:

```lua
local RunService = game:GetService("RunService")
local BT = require(Packages.BehaviourTree)

local rig = workspace:WaitForChild("Rig")
local humanoid = rig:WaitForChild("Humanoid")

-- Create the tree (defaults to a Fallback root)
local tree = BT.new()
tree.debugLevel = 1

-- Branch 1: Death
local deathSeq = BT.SequenceNode.new("DeathSequence")
local isDead = BT.ConditionNode.new("isDead?", function()
    return humanoid.Health <= 0
end)
local die = BT.ActionNode.new("Die", function()
    rig:Destroy()
end, true) -- terminator - pauses the tree on success
deathSeq:addChild({ isDead, die })

-- Branch 2: Walk
local walkSeq = BT.SequenceNode.new("WalkSequence")
local canWalk = BT.ConditionNode.new("canWalk?", function()
    return humanoid.WalkSpeed > 0
end)
local walk = BT.ActionNode.new("Walk", function()
    humanoid:MoveTo(Vector3.new(50, 0, 0))
    humanoid.MoveToFinished:Wait() -- yields → RUNNING until finished
end)
walkSeq:addChild({ canWalk, walk })

-- Branch 3: Idle (fallback)
local idle = BT.ActionNode.new("Idle", function()
    -- do nothing
end)

-- Assemble
tree:addChild({ deathSeq, walkSeq, idle })

-- Pause handling
tree.Paused.Event:Connect(function()
    tree:cancelActiveExecutionActions()
end)

-- Run
RunService.Heartbeat:Connect(function()
    tree:run()
end)
```

**Printing the tree structure:**

Call `print(tree)` to visualise the node hierarchy:

```
<tree-uuid> : FALLBACK
  ├─ DeathSequence : SEQUENCE
  │  ├─ isDead? : CONDITION
  │  └─ Die : ACTION
  ├─ WalkSequence : SEQUENCE
  │  ├─ canWalk? : CONDITION
  │  └─ Walk : ACTION
  └─ Idle : ACTION
```

The output shows each node's name and type, with indentation reflecting the parent-child relationships. This is especially helpful when debugging larger trees.

---

## Debug Levels

Set `tree.debugLevel` to control how much diagnostic output is printed:

| Level | Constant      | Output                                                            |
| ----- | ------------- | ----------------------------------------------------------------- |
| 0     | `NONE`        | Silent.                                                           |
| 1     | `BASIC`       | Prints `TICK BEGIN` at the start of each tick.                    |
| 2     | `TRANSITIONS` | Also prints when nodes enter and exit (e.g. `[IDLE -> RUNNING]`). |
| 3     | `VERBOSE`     | Also prints coroutine lifecycle details and cancellation events.  |

```lua
tree.debugLevel = BT.Enums.DebugLevel.VERBOSE -- 3
```
