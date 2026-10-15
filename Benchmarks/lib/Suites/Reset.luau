local Suite = if script then require(script.Parent.Parent.Suite) else require("../Suite")

local function fixture(BT, _, probe, width)
	local root = BT.SequenceNode.new("Reset")
	local keys = table.create(width)
	for index = 1, width do
		keys[index] = {}
	end
	local resets, replacements = 0, 0
	local reset = root._cancel or root._reset
	return {
		step = function()
			for _, key in ipairs(keys) do
				root._statusTable[key] = BT.Enums.Status.SUCCESS
			end
			root._successCount = width
			root._failureCount = width
			if probe then
				local before = root._statusTable
				reset(root)
				resets += 1
				if not rawequal(before, root._statusTable) then
					replacements += 1
				end
			else
				reset(root)
			end
		end,
		verify = function(iterations, test)
			test("clears cached child results", function()
				assert(next(root._statusTable) == nil, "Reset retained cached results")
			end)
			test("clears the success counter", function()
				assert(root._successCount == 0, `Expected 0, got {root._successCount}`)
			end)
			test("clears the failure counter", function()
				assert(root._failureCount == 0, `Expected 0, got {root._failureCount}`)
			end)
			test("returns to IDLE", function()
				assert(root.status == BT.Enums.Status.IDLE, `Expected IDLE, got {root.status}`)
			end)
			if probe then
				test("resets once per operation", function()
					assert(resets == iterations, `Expected {iterations} resets, got {resets}`)
				end)
			end
			return `empty:{width}`
		end,
		metrics = function()
			return { resets = resets, statusTableReplacements = replacements }
		end,
		cleanup = function() end,
	}
end

return Suite.describe("Reset", function(test)
	for _, width in ipairs({ 0, 16, 128 }) do
		test(`populate and reset {width} cached results`, {
			id = `reset-width{width}`,
			unit = "populate and reset",
			create = function(BT, role, probe)
				return fixture(BT, role, probe, width)
			end,
		})
	end
end)
