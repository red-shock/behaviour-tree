local fs = require("@std/fs")
local path = require("@std/path")
local process = require("@std/process")
local json = require("@std/json")
local crypto = require("@lute/crypto")

local workspace = path.format(path.resolve(path.dirname(process.args[1]), ".."))
local workloads = {
	All = true,
	Diagnostics = true,
	Reset = true,
	Construction = true,
	Actions = true,
	Cancellation = true,
	DecisionCycle = true,
}
local definitions = {
	["--baseline"] = { key = "baseline", default = "HEAD" },
	["--candidate"] = { key = "candidate", default = "WORKTREE" },
	["--workload"] = { key = "workload", default = "All" },
	["--case"] = { key = "case", default = "" },
}

local function help()
	print([[Usage: lute Benchmarks/Prepare.luau [options]
  --baseline REF           Baseline Git revision or WORKTREE (default HEAD)
  --candidate REF          Candidate Git revision or WORKTREE (default WORKTREE)
  --workload NAME          All, Diagnostics, Reset, Construction, Actions, Cancellation, DecisionCycle
  --case ID                Only this exact scenario ID
  --help, -h               Show this help

Always builds a Studio place. Open the printed path and press Play.
]])
end

local function options()
	local result, seen = {}, {}
	for _, definition in pairs(definitions) do
		result[definition.key] = definition.default
	end
	local index = 2 -- Lute includes the script path as the first argument.
	while index <= #process.args do
		local argument = process.args[index]
		if argument == "--help" or argument == "-h" then
			help()
			return nil
		end
		local name, value = string.match(argument, "^(%-%-[^=]+)=(.*)$")
		name = name or argument
		local definition = definitions[name]
		assert(definition, `Unknown option: {name}. Use --help for usage.`)
		assert(not seen[name], `Duplicate option: {name}`)
		seen[name] = true
		if value == nil then
			index += 1
			value = process.args[index]
			assert(value and not string.match(value, "^%-%-"), `{name} requires a value`)
		end
		assert(value ~= "", `{name} requires a nonempty value`)
		result[definition.key] = value
		index += 1
	end
	assert(workloads[result.workload], `Unknown workload: {result.workload}`)
	return result
end

local function command(arguments)
	-- No shell: labels, paths, and Git revisions are separate process arguments.
	local result = process.run(arguments, { cwd = workspace })
	assert(result.ok, `{arguments[1]} {arguments[2] or ""} failed (exit {result.exitcode}): {result.stderr}`)
	return result.stdout
end

local function git(...)
	return command({ "git", "-C", workspace, ... })
end

local function trim(value)
	return (string.gsub(value, "%s+$", ""))
end

local function join(...)
	return path.format(path.join(...))
end

local function write(filename, contents)
	fs.createDirectory(path.dirname(filename), { makeParents = true })
	fs.writeStringToFile(filename, contents)
end

local function copyDirectory(source, destination)
	fs.createDirectory(destination, { makeParents = true })
	for _, entry in ipairs(fs.listDirectory(source)) do
		assert(entry.name ~= ".git", "Nested Git repositories are not supported in snapshots")
		local from, to = join(source, entry.name), join(destination, entry.name)
		if entry.type == "dir" then
			copyDirectory(from, to)
		else
			assert(entry.type == "file", `Unsupported snapshot entry: {from} ({entry.type})`)
			fs.copy(from, to)
		end
	end
end

local function sha256(contents)
	local digest = crypto.digest(crypto.hash.sha256, contents)
	local bytes = {}
	for offset = 0, buffer.len(digest) - 1 do
		bytes[offset + 1] = string.format("%02x", buffer.readu8(digest, offset))
	end
	return table.concat(bytes)
end

local function sourceHash(directory)
	local files = {}
	local function visit(relative)
		for _, entry in ipairs(fs.listDirectory(join(directory, relative))) do
			local name = if relative == "" then entry.name else `{relative}/{entry.name}`
			if entry.type == "dir" then
				visit(name)
			else
				assert(entry.type == "file", `Unsupported hash entry: {name}`)
				table.insert(files, name)
			end
		end
	end
	visit("")
	table.sort(files)
	local entries = {}
	for _, name in ipairs(files) do
		table.insert(entries, `{name}:{sha256(fs.readFileToString(join(directory, name)))}`)
	end
	return sha256(table.concat(entries, "\n"))
end

local function exportVariant(reference, name, runDirectory)
	local worktree = reference == "WORKTREE"
	local commit =
		trim(git("rev-parse", "--verify", "--end-of-options", `{if worktree then "HEAD" else reference}^\{commit\}`))
	local destination = join(runDirectory, name)
	local dirty = false
	if worktree then
		for entry in string.gmatch(git("ls-files", "--stage", "-z", "--", "BehaviourTree"), "([^%z]+)%z") do
			assert(not string.match(entry, "^160000 "), "Submodules are not supported in working-tree snapshots")
		end
		copyDirectory(join(workspace, "BehaviourTree"), join(destination, "BehaviourTree"))
		dirty = git("status", "--porcelain", "--", "BehaviourTree") ~= ""
	else
		-- Export exact blobs without an archive extractor or checkout/filter conversions.
		local listing = git("ls-tree", "-r", "-z", "--full-tree", commit, "--", "BehaviourTree")
		for entry in string.gmatch(listing, "([^%z]+)%z") do
			local mode, kind, object, filename = string.match(entry, "^(%d+) (%w+) (%x+)\t(.+)$")
			assert(kind == "blob" and (mode == "100644" or mode == "100755"), `Unsupported Git entry: {entry}`)
			assert(
				string.sub(filename, 1, 14) == "BehaviourTree/" and not string.find(filename, "\\", 1, true),
				"Unexpected snapshot path"
			)
			for segment in string.gmatch(filename, "[^/]+") do
				assert(segment ~= ".." and segment ~= ".", "Unexpected snapshot path segment")
			end
			write(join(destination, filename), git("cat-file", "blob", object))
		end
	end
	local package = join(destination, "BehaviourTree")
	assert(fs.exists(join(package, "init.luau")), `{reference} has no BehaviourTree package`)
	return { label = reference, commit = commit, worktree = worktree, dirty = dirty, sourceHash = sourceHash(package) }
end

local function main()
	local config = options()
	if not config then
		return
	end
	local prefix = `{os.date("!%Y%m%d-%H%M%S")}-{process.pid()}`
	local suffix = 0
	local runDirectory
	repeat
		runDirectory = join(workspace, ".benchmarks", `{prefix}-{suffix}`)
		suffix += 1
	until not fs.exists(runDirectory)
	fs.createDirectory(runDirectory, { makeParents = true })
	local baseline = exportVariant(config.baseline, "Baseline", runDirectory)
	local candidate = exportVariant(config.candidate, "Candidate", runDirectory)
	local harness = join(runDirectory, "Harness")
	copyDirectory(join(workspace, "Benchmarks", "lib"), harness)
	local runner = join(runDirectory, "Run.server.luau")
	fs.copy(join(workspace, "Benchmarks", "Run.server.luau"), runner)
	local manifest = {
		schemaVersion = 2,
		hashFormat = "sha256-sorted-relative-paths-v1",
		preparedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		baseline = baseline,
		candidate = candidate,
		harnessHash = sourceHash(harness),
		runnerHash = sha256(fs.readFileToString(runner)),
		config = {
			workload = config.workload,
			case = config.case,
			samples = 21,
			warmupBatches = 3,
			maxIterations = 1024,
			targetSeconds = 0.005,
		},
	}
	local manifestJson = json.serialize(manifest, true)
	write(join(runDirectory, "manifest.json"), manifestJson)
	local equals = "===="
	while string.find(manifestJson, `]{equals}]`, 1, true) do
		equals ..= "="
	end
	write(join(runDirectory, "Manifest.luau"), `return [{equals}[\n{manifestJson}]{equals}]\n`)
	local projectPath = join(runDirectory, "benchmark.project.json")
	write(
		projectPath,
		json.serialize({
			name = "BehaviourTreeBenchmark",
			tree = {
				["$className"] = "DataModel",
				ServerScriptService = {
					["$className"] = "ServerScriptService",
					Benchmark = {
						["$className"] = "Folder",
						Baseline = { ["$path"] = "./Baseline/BehaviourTree" },
						Candidate = { ["$path"] = "./Candidate/BehaviourTree" },
						Harness = { ["$path"] = "./Harness" },
						Manifest = { ["$path"] = "./Manifest.luau" },
					},
					RunBenchmarks = { ["$path"] = "./Run.server.luau" },
				},
			},
		}, true)
	)
	local place = join(runDirectory, "benchmark.rbxlx")
	print(trim(command({ "rojo", "build", projectPath, "-o", place })))
	print(`Open in Studio and press Play: {place}`)
	print(`Manifest: {join(runDirectory, "manifest.json")}`)
	print(`Rojo project: {projectPath}`)
	if baseline.sourceHash == candidate.sourceHash then
		print("Source snapshots match: this is an A/A noise check for legacy workloads.")
	end
end

main()
