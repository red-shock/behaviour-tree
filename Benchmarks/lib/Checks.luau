local Checks = {}

-- Run independent, named expectations outside the timed operation loop.
function Checks.new()
	local results, names = {}, {}
	return {
		results = results,
		test = function(name, fn)
			assert(type(name) == "string" and name ~= "" and not names[name], "Check names must be nonempty and unique")
			names[name] = true
			local ok, message = pcall(fn)
			table.insert(results, {
				name = name,
				status = if ok then "passed" else "failed",
				message = if ok then nil else tostring(message),
			})
		end,
	}
end

return Checks
