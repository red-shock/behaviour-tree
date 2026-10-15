local Suite = if script then require(script.Parent.Parent.Suite) else require("../Suite")
local fixture = if script
	then require(script.Parent.Parent.Fixtures.Construction)
	else require("../Fixtures/Construction")
local Support = if script then require(script.Parent.Parent.Fixtures.Support) else require("../Fixtures/Support")

return Suite.describe(
	"Construction",
	function(test)
		for _, shape in ipairs({
			{ name = "wide", depth = 1, width = 32 },
			{ name = "deep", depth = 12, width = 1 },
			{ name = "balanced", depth = 3, width = 3 },
		}) do
			for _, adopt in ipairs({ false, true }) do
				test(
					`{shape.name} tree using {if adopt then "adoption against cloning" else "cloning on both revisions"}`,
					{
						id = `construction-{if adopt then "adopt" else "clone"}-{shape.name}`,
						unit = "tree assembly",
						unsupported = if adopt then Support.nodeAdoption else nil,
						maxIterations = 8,
						create = function(BT, role, probe)
							return fixture(BT, role, probe, shape.depth, shape.width, adopt)
						end,
					}
				)
			end
		end
	end,
	"Assembling fresh nested trees can copy the same descendants at multiple attachment levels before the tree ever runs."
)
