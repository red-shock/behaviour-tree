local Suite = if script then require(script.Parent.Parent.Suite) else require("../Suite")
local DecisionCycle = if script
	then require(script.Parent.Parent.Fixtures.DecisionCycle)
	else require("../Fixtures/DecisionCycle")
local Support = if script then require(script.Parent.Parent.Fixtures.Support) else require("../Fixtures/Support")

return Suite.describe(
	"DecisionCycle",
	function(test)
		for _, population in ipairs({ 1, 16 }) do
			test(
				`guarded decision replay for {population} independent {if population == 1 then "worker" else "workers"}`,
				{
					id = `decision-cycle-ordinary-workers{population}`,
					unit = `decision cycle ({DecisionCycle.ticksPerWorker * population} ticks)`,
					create = function(BT, role, probe)
						return DecisionCycle.create(BT, role, probe, population, {})
					end,
				}
			)
		end
		test("16 workers with synchronous immediate updates", {
			id = "decision-cycle-synchronous-workers16",
			unit = `decision cycle ({DecisionCycle.ticksPerWorker * 16} ticks)`,
			unsupported = Support.synchronousActions,
			create = function(BT, role, probe)
				return DecisionCycle.create(BT, role, probe, 16, { synchronous = true })
			end,
		})
		test("16 workers with parallel maintenance", {
			id = "decision-cycle-parallel-workers16",
			unit = `decision cycle ({DecisionCycle.ticksPerWorker * 16} ticks)`,
			unsupported = Support.parallelAccounting,
			create = function(BT, role, probe)
				return DecisionCycle.create(BT, role, probe, 16, { parallel = true })
			end,
		})
	end,
	"Repeated maintenance, guarded priority choices, cached preparation, and work spanning ticks make fixed per-node costs accumulate across independent trees."
)
