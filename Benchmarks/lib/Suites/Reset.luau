local Suite = if script then require(script.Parent.Parent.Suite) else require("../Suite")
local fixture = if script then require(script.Parent.Parent.Fixtures.Reset) else require("../Fixtures/Reset")

return Suite.describe(
	"Reset",
	function(test)
		for _, width in ipairs({ 0, 16, 128 }) do
			test(`populate and reset {width} cached results`, {
				id = `reset-width{width}`,
				unit = "populate and reset",
				create = function(BT, role, probe)
					return fixture(BT, role, probe, width)
				end,
			})
		end
	end,
	"Short-lived control cycles repeatedly clear private result caches; replacement allocations can dominate nearly empty resets."
)
