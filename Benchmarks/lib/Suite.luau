local Suite = {}

-- Registration only: fixture creation and timing happen later in Runner.
function Suite.describe(name, define, rationale)
	assert(type(name) == "string" and name ~= "", "A workload suite needs a name")
	local cases, ids = {}, {}
	define(function(testName, definition)
		assert(type(testName) == "string" and testName ~= "", "A benchmark test needs a name")
		assert(
			type(definition.id) == "string" and not ids[definition.id],
			"Benchmark ids must be unique within a suite"
		)
		assert(type(definition.create) == "function", "A benchmark test needs a fixture factory")
		assert(type(definition.unit) == "string", "A benchmark test needs an operation unit")
		ids[definition.id] = true
		local case = table.clone(definition)
		case.name = testName
		case.workload = name
		case.rationale = definition.rationale or rationale
		case.unsupported = case.unsupported or function()
			return nil
		end
		table.insert(cases, case)
	end)
	return cases
end

return Suite
