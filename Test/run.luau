local loadLibrary = require("../Benchmarks/Tests/LibraryFixture")
local passed, failed = 0, 0

local function test(name, fn, options)
	local BT, clean = loadLibrary(options)
	local trees = {}
	local ok, message = pcall(fn, BT, function(tree)
		table.insert(trees, tree)
		return tree
	end)
	for _, tree in ipairs(trees) do
		local cancelled, cancelError = pcall(tree.cancelActiveExecutionActions, tree)
		tree.Paused:Destroy()
		if not cancelled then
			ok, message = false, `cleanup: {cancelError}; test: {message}`
		end
	end
	local cleaned, cleanupError = pcall(clean)
	if not cleaned then
		ok, message = false, `fixture cleanup: {cleanupError}; test: {message}`
	end
	if ok then
		passed += 1
		print(`PASS {name}`)
	else
		failed += 1
		print(`FAIL {name}: {message}`)
	end
end

require("./ExecutionNode.spec")(test)
require("./ControlNode.spec")(test)
require("./Tree.spec")(test)
print(`Diagnostic regression tests: {passed} passed, {failed} failed`)
assert(failed == 0, "Diagnostic regression tests failed")
