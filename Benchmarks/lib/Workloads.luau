local suites = {
	if script then require(script.Parent.Suites.Diagnostics) else require("./Suites/Diagnostics"),
	if script then require(script.Parent.Suites.Reset) else require("./Suites/Reset"),
	if script then require(script.Parent.Suites.Construction) else require("./Suites/Construction"),
	if script then require(script.Parent.Suites.Actions) else require("./Suites/Actions"),
	if script then require(script.Parent.Suites.Cancellation) else require("./Suites/Cancellation"),
	if script then require(script.Parent.Suites.DecisionCycle) else require("./Suites/DecisionCycle"),
}

local Workloads = {}

function Workloads.create()
	local cases, ids = {}, {}
	for _, suite in ipairs(suites) do
		for _, case in ipairs(suite) do
			assert(not ids[case.id], `Duplicate benchmark id: {case.id}`)
			ids[case.id] = true
			table.insert(cases, case)
		end
	end
	return cases
end

return Workloads
