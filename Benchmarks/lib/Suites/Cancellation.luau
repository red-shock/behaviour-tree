local Suite = if script then require(script.Parent.Parent.Suite) else require("../Suite")
local fixture = if script
	then require(script.Parent.Parent.Fixtures.Cancellation)
	else require("../Fixtures/Cancellation")
local Support = if script then require(script.Parent.Parent.Fixtures.Support) else require("../Fixtures/Support")

return Suite.describe(
	"Cancellation",
	function(test)
		local names = {
			sequence = "early-failing sequence with untouched branches",
			fallback = "early-success fallback with untouched branches",
			dense = "fully visited nested tree with 64 leaves",
			switch = "priority switch preempts a suspended action",
		}
		for _, mode in ipairs({ "sequence", "fallback", "dense", "switch" }) do
			test(names[mode], {
				id = `cancellation-{mode}`,
				unit = if mode == "switch" then "priority switch (two ticks)" else "tree tick",
				unsupported = Support.cancellation,
				create = function(BT, role, probe)
					return fixture(BT, role, probe, mode)
				end,
			})
		end
	end,
	"Priority guards often leave large branches untouched; cleanup should be measured against both sparse visits and fully visited trees, including branch preemption."
)
