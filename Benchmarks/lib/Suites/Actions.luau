local Suite = if script then require(script.Parent.Parent.Suite) else require("../Suite")
local tickFixture = if script then require(script.Parent.Parent.Fixtures.Tick) else require("../Fixtures/Tick")
local Support = if script then require(script.Parent.Parent.Fixtures.Support) else require("../Fixtures/Support")

return Suite.describe(
	"Actions",
	function(test)
		test("32 ordinary immediate actions", {
			id = "actions-ordinary-width32",
			unit = "tree tick",
			create = function(BT, role, probe)
				return tickFixture(BT, role, probe, { width = 32 })
			end,
		})
		for _, width in ipairs({ 1, 32, 128 }) do
			test(`{width} synchronous actions against ordinary actions`, {
				id = `actions-synchronous-width{width}`,
				unit = "tree tick",
				unsupported = Support.synchronousActions,
				create = function(BT, role, probe)
					return tickFixture(BT, role, probe, { width = width, synchronous = true })
				end,
			})
		end
		test("16 immediate actions before a suspended leaf", {
			id = "actions-mixed-running",
			unit = "tree tick with a suspended leaf",
			unsupported = Support.synchronousActions,
			create = function(BT, role, probe)
				return tickFixture(BT, role, probe, { width = 16, synchronous = true, running = true })
			end,
		})
	end,
	"Immediate state updates pay execution state and coroutine setup costs on every visit, while genuinely suspended actions still need owned work."
)
