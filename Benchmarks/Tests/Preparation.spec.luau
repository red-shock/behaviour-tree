local fs = require("@std/fs")
local path = require("@std/path")
local process = require("@std/process")
local json = require("@std/json")
local crypto = require("@lute/crypto")
local luau = require("@lute/luau")

local function join(...)
	return path.format(path.join(...))
end

local workspace = path.format(path.resolve(path.dirname(process.args[1]), "../.."))
local prefix = join(workspace, ".benchmarks", `preparer-tests-{os.time()}-{process.pid()}`)
local scratch, suffix = prefix, 0
while fs.exists(scratch) do
	suffix += 1
	scratch = `{prefix}-{suffix}`
end
local fixture = join(scratch, "fixture with spaces")
local hooks = join(scratch, "empty-hooks")
fs.createDirectory(hooks, { makeParents = true })

local function write(relative, contents)
	local filename = join(fixture, relative)
	fs.createDirectory(path.dirname(filename), { makeParents = true })
	fs.writeStringToFile(filename, contents)
end

local function git(...)
	local result = process.run({ "git", "-c", `core.hooksPath={hooks}`, "-C", fixture, ... })
	assert(result.ok, result.stderr)
	return result.stdout
end

local entry = join(fixture, "Benchmarks", "Prepare.luau")
write("Benchmarks/Prepare.luau", fs.readFileToString(join(workspace, "Benchmarks", "Prepare.luau")))
write("Benchmarks/lib/Example.luau", "return {}\n")
write("Benchmarks/lib/Nested/Other.luau", "return false\n")
write("Benchmarks/Run.server.luau", "print('fixture only')\n")
write(".gitignore", "/.benchmarks/\n")
local original = "-- mixed line endings and UTF-8: café\r\nreturn { value = 'original' }\n"
local committedBytes = "\0\1\26\r\n\n\255"
write("BehaviourTree/init.luau", original)
write("BehaviourTree/bytes.bin", committedBytes)
write("BehaviourTree/folder with spaces/éxample.luau", "return 'nested'\n")
git("init", "-q")
git("config", "core.autocrlf", "false")
git("add", "BehaviourTree", ".gitignore")
git(
	"-c",
	"user.name=Benchmark Fixture",
	"-c",
	"user.email=benchmark@example.invalid",
	"commit",
	"--no-gpg-sign",
	"-qm",
	"Fixture"
)
local commit = string.gsub(git("rev-parse", "HEAD"), "%s+$", "")

local function prepare(arguments)
	local command = { path.format(process.execPath()), entry }
	for _, value in ipairs(arguments) do
		table.insert(command, value)
	end
	-- Deliberately run outside the fixture repository; preparation follows its script location.
	return process.run(command, { cwd = scratch })
end

local function prepared(arguments)
	local result = prepare(arguments)
	assert(result.ok, result.stderr)
	local manifestPath = string.match(result.stdout, "Manifest: ([^\r\n]+)")
	assert(manifestPath, "Preparer did not report its manifest path")
	return json.deserialize(fs.readFileToString(manifestPath)), path.dirname(manifestPath)
end

local function sha256(contents)
	local digest = crypto.digest(crypto.hash.sha256, contents)
	local bytes = {}
	for offset = 0, buffer.len(digest) - 1 do
		bytes[offset + 1] = string.format("%02x", buffer.readu8(digest, offset))
	end
	return table.concat(bytes)
end

local passed, failed = 0, 0
local function test(name, fn)
	local ok, message = pcall(fn)
	if ok then
		passed += 1
		print(`  PASS {name}`)
	else
		failed += 1
		print(`  FAIL {name}: {message}`)
	end
end

print("describe Luau benchmark preparation")
test("help and invalid options do not create snapshots", function()
	local help = prepare({ "--help" })
	assert(help.ok and string.find(help.stdout, "--baseline", 1, true), "Missing CLI help")
	for _, arguments in ipairs({
		{ "--samples", "2" },
		{ "--samples", "3.5" },
		{ "--max-iterations", "0" },
		{ "--target-ms", "51" },
		{ "--workload", "Missing" },
		{ "--case" },
		{ "--build=false" },
		{ "--samples", "3", "--samples", "5" },
		{ "--unknown" },
	}) do
		local result = prepare(arguments)
		assert(not result.ok, `Invalid options were accepted: {table.concat(arguments, " ")}`)
	end
	assert(not fs.exists(join(fixture, ".benchmarks")), "Invalid options created snapshot directories")
end)

test("committed snapshots preserve exact bytes and build an isolated Rojo place", function()
	local unchangedManifest, unchangedDirectory = prepared({ "--baseline", "HEAD", "--candidate", "HEAD", "--build" })
	assert(
		unchangedManifest.baseline.commit == commit and unchangedManifest.candidate.commit == commit,
		"Wrong revisions"
	)
	assert(unchangedManifest.baseline.sourceHash == unchangedManifest.candidate.sourceHash, "A/A hashes differ")
	assert(
		unchangedManifest.baseline.dirty == false and unchangedManifest.candidate.worktree == false,
		"Incorrect source metadata"
	)
	local source = fs.readFileToString(join(unchangedDirectory, "Baseline", "BehaviourTree", "init.luau"))
	assert(source == original, "Git snapshot changed file bytes")
	assert(
		fs.metadata(join(unchangedDirectory, "Baseline", "BehaviourTree", "init.luau")).size == #original,
		"File size changed"
	)
	assert(
		fs.readFileToString(join(unchangedDirectory, "Baseline", "BehaviourTree", "bytes.bin")) == committedBytes,
		"Git export changed binary bytes"
	)
	assert(
		fs.readFileToString(
			join(unchangedDirectory, "Candidate", "BehaviourTree", "folder with spaces", "éxample.luau")
		) == "return 'nested'\n",
		"Nested or Unicode filename was lost"
	)
	assert(
		fs.exists(join(unchangedDirectory, "Harness", "Nested", "Other.luau")),
		"Harness subdirectories were not copied"
	)
	assert(fs.exists(join(unchangedDirectory, "benchmark.rbxlx")), "Rojo place was not built")
	assert(unchangedManifest.runnerHash == sha256("print('fixture only')\n"), "Runner hash is not SHA-256")
	assert(
		unchangedManifest.schemaVersion == 2 and unchangedManifest.hashFormat == "sha256-sorted-relative-paths-v1",
		"Missing hash format"
	)
end)

test("working-tree snapshots include edits and untracked files without changing the baseline", function()
	local unchangedManifest, unchangedDirectory = prepared({ "--baseline", "HEAD", "--candidate", "HEAD" })
	local changed = "return { value = 'edited' }\n"
	local binary = "\0\1\26\r\n\n\255"
	write("BehaviourTree/init.luau", changed)
	write("BehaviourTree/untracked.bin", binary)
	local manifest, directory = prepared({})
	assert(
		manifest.baseline.sourceHash == unchangedManifest.baseline.sourceHash,
		"Baseline changed after a working edit"
	)
	assert(manifest.candidate.worktree and manifest.candidate.dirty, "Working-copy changes were not recorded")
	assert(manifest.candidate.sourceHash ~= manifest.baseline.sourceHash, "Changed source has the same fingerprint")
	assert(
		fs.readFileToString(join(directory, "Baseline", "BehaviourTree", "init.luau")) == original,
		"Baseline contains an uncommitted edit"
	)
	assert(
		fs.readFileToString(join(directory, "Candidate", "BehaviourTree", "init.luau")) == changed,
		"Candidate edit is missing"
	)
	assert(
		fs.readFileToString(join(directory, "Candidate", "BehaviourTree", "untracked.bin")) == binary,
		"Binary or untracked bytes changed"
	)
	assert(
		fs.metadata(join(directory, "Candidate", "BehaviourTree", "untracked.bin")).size == #binary,
		"Binary copy changed size"
	)
	assert(
		fs.readFileToString(join(unchangedDirectory, "Candidate", "BehaviourTree", "init.luau")) == original,
		"An earlier snapshot was mutated"
	)
	assert(string.gsub(git("rev-parse", "HEAD"), "%s+$", "") == commit, "Preparation changed HEAD")
end)

test("labels and options round-trip through JSON and the generated Luau module", function()
	local label = 'Example "quoted" environment \\ path\n]====] ]=====]'
	local manifest, directory = prepared({
		"--candidate=HEAD",
		"--workload",
		"DecisionCycle",
		"--case",
		"decision-cycle-ordinary-workers16",
		"--samples",
		"7",
		"--warmup-batches",
		"2",
		"--max-iterations",
		"8",
		"--target-ms",
		"1.5",
		"--environment-label",
		label,
		"--print-json",
	})
	assert(manifest.environmentLabel == label, "Label was interpreted or incorrectly escaped")
	assert(manifest.printJson and manifest.config.workload == "DecisionCycle", "Flags or workload were lost")
	assert(manifest.config.case == "decision-cycle-ordinary-workers16", "Case filter was lost")
	assert(
		manifest.config.samples == 7 and manifest.config.warmupBatches == 2 and manifest.config.maxIterations == 8,
		"Integer options changed"
	)
	assert(manifest.config.targetSeconds == 0.0015, "Target units changed")
	local moduleSource = fs.readFileToString(join(directory, "Manifest.luau"))
	local moduleJson = luau.load(luau.compile(moduleSource), "Manifest", {})()
	assert(moduleJson == fs.readFileToString(join(directory, "manifest.json")), "Manifest module altered the JSON")
end)

test("symbolic links and submodules are rejected without following external content", function()
	local blob = string.gsub(git("rev-parse", "HEAD:BehaviourTree/init.luau"), "%s+$", "")
	git("update-index", "--add", "--cacheinfo", "120000", blob, "BehaviourTree/link.luau")
	git(
		"-c",
		"user.name=Benchmark Fixture",
		"-c",
		"user.email=benchmark@example.invalid",
		"commit",
		"--no-gpg-sign",
		"-qm",
		"Unsupported link fixture"
	)
	local linked = prepare({ "--baseline", "HEAD", "--candidate", "HEAD" })
	assert(
		not linked.ok and string.find(linked.stderr, "Unsupported Git entry", 1, true),
		"Symbolic-link blob was exported as a file"
	)
	git("update-index", "--add", "--cacheinfo", "160000", commit, "BehaviourTree/Vendor")
	local submodule = prepare({ "--baseline", commit, "--candidate", "WORKTREE" })
	assert(
		not submodule.ok and string.find(submodule.stderr, "Submodules are not supported", 1, true),
		"Working submodule was copied"
	)
	git("update-index", "--force-remove", "BehaviourTree/Vendor")
end)

test("bad revisions and missing packages fail instead of reporting a prepared comparison", function()
	local missing = prepare({ "--baseline", "missing-benchmark-reference" })
	assert(
		not missing.ok and not string.find(missing.stdout, "Manifest:", 1, true),
		"Missing revision was reported as prepared"
	)
	git("rm", "-qr", "--cached", "BehaviourTree")
	git(
		"-c",
		"user.name=Benchmark Fixture",
		"-c",
		"user.email=benchmark@example.invalid",
		"commit",
		"--no-gpg-sign",
		"-qm",
		"Empty package fixture"
	)
	local empty = prepare({ "--candidate", "HEAD" })
	assert(
		not empty.ok and string.find(empty.stderr, "has no BehaviourTree package", 1, true),
		"Missing package was accepted"
	)
end)

print(`Preparation tests: {passed} passed, {failed} failed`)
assert(failed == 0, "Benchmark preparation tests failed")
