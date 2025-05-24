local ControlNode = require(script.Parent.ControlNode)
local ExecutionNode = require(script.Parent.ExecutionNode)
local Enums = require(script.Parent.Enums)

local DecoratorNode = {}
DecoratorNode.__index = DecoratorNode
DecoratorNode.__class = "DecoratorNode"

setmetatable(DecoratorNode, ControlNode)

function DecoratorNode.new(name: string | nil, wrapperFn: (() -> boolean) -> nil, onCompleteFn: ((boolean) -> boolean))
    local self = ControlNode.new(name, Enums.NodeType.DECORATOR)
    setmetatable(self, DecoratorNode)

    self.wrapperFn = wrapperFn or function(runChild)
        runChild()
    end
    self.onCompleteFn = onCompleteFn or function(success)
        return success
    end

    self._coroutine = nil
    self.__class = "DecoratorNode"
    return self
end

function DecoratorNode:addCompleteCallback(child: ExecutionNode.ExecutionNode)
    if not child then
        warn("DecoratorNode does not contain a child node")
        return
    end

    child.onComplete = function(success)
        local newValue = self.onCompleteFn(success) and Enums.Status.SUCCESS or Enums.Status.FAILURE
        self.status = newValue
        return newValue
    end
end

function DecoratorNode:run()
    if not self._coroutine then
        local child = self.children[1]
        if not child then
            self.status = Enums.Status.SUCCESS
            return Enums.Status.SUCCESS
        end

        self._coroutine = {
            success = true,
            result = nil,
        }

        self._coroutine.fn = coroutine.create(function()
            local success, result = pcall(function()
                return self.wrapperFn(function()
                    return child.fn()
                end)
            end)

            self._coroutine.success = success
            self._coroutine.result = result
        end)

        coroutine.resume(self._coroutine.fn)
        self.status = Enums.Status.RUNNING
    else
        if coroutine.status(self._coroutine.fn) == "dead" then
            local value = self._coroutine.result == nil and self._coroutine.success or self._coroutine.result
            local result = self.onCompleteFn(value)

            self.status = result and Enums.Status.SUCCESS or Enums.Status.FAILURE
            if self.nodeType == Enums.NodeType.ACTION and self.status == Enums.Status.SUCCESS and self.isTerminator then
                if not self.tree then
                    error("Tree is not set, cannot pause")
                end
                self.tree:pause()
            end
            self._coroutine = nil
        end
    end
    return self.status
end

function DecoratorNode:_cancelThread()
    if self._coroutine then
        if self._coroutine.fn then
            coroutine.close(self._coroutine.fn)
        end
        self._coroutine = nil
    end
end

return DecoratorNode