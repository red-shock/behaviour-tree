local Suite = if script then require(script.Parent.Parent.Suite) else require("../Suite")
local tickFixture = if script then require(script.Parent.Parent.Fixtures.Tick) else require("../Fixtures/Tick")

return Suite.describe("Diagnostics", function(test)
	local levels = { [0] = "NONE", [2] = "TRANSITIONS", [3] = "VERBOSE" }
	for _, level in ipairs({ 0, 2, 3 }) do
		for _, width in ipairs({ 8, 64 }) do
			test(`{levels[level]} logging with {width} alternating leaves`, {
				id = `diagnostics-level{level}-width{width}`,
				unit = "tree tick",
				create = function(BT, role, probe)
					return tickFixture(BT, role, probe, { width = width, level = level, conditions = true })
				end,
			})
		end
	end
end, "Frequent ticks through cheap leaves can spend time formatting diagnostics even when logging is disabled.")
