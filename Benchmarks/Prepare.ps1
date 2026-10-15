[CmdletBinding()]
param(
    [string]$Baseline = 'HEAD',
    [string]$Candidate = 'WORKTREE',
    [ValidateSet('All', 'Diagnostics', 'Reset', 'Construction', 'Actions', 'Cancellation')]
    [string]$Workload = 'All',
    [ValidateRange(3, 101)][int]$Samples = 21,
    [ValidateRange(1, 20)][int]$WarmupBatches = 3,
    [ValidateRange(1, 4096)][int]$MaxIterations = 1024,
    [ValidateRange(1, 50)][double]$TargetMilliseconds = 5,
    [string]$EnvironmentLabel = 'local Studio',
    [switch]$PrintJson,
    [switch]$Build
)

$ErrorActionPreference = 'Stop'
$workspace = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runName = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$runDirectory = Join-Path $workspace ".benchmarks\$runName"
$utf8 = [System.Text.UTF8Encoding]::new($false)
New-Item -ItemType Directory -Path $runDirectory | Out-Null

function Invoke-Git {
    param([string[]]$GitArguments)
    $output = & git -C $workspace @GitArguments
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArguments[0]) failed" }
    return $output
}

function Get-SourceHash {
    param([string]$Directory)
    $entries = Get-ChildItem -LiteralPath $Directory -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($Directory.Length).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        "$relative`:$hash"
    }
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($utf8.GetBytes(($entries -join "`n"))))).Replace('-', '').ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

function Export-Variant {
    param([string]$Reference, [string]$Name)
    $destination = Join-Path $runDirectory $Name
    New-Item -ItemType Directory -Path $destination | Out-Null
    if ($Reference -eq 'WORKTREE') {
        $commit = Invoke-Git @('rev-parse', '--verify', 'HEAD')
        Copy-Item -LiteralPath (Join-Path $workspace 'BehaviourTree') -Destination $destination -Recurse
        $dirty = @(Invoke-Git @('status', '--porcelain', '--', 'BehaviourTree')).Count -gt 0
    } else {
        $commit = Invoke-Git @('rev-parse', '--verify', '--end-of-options', "$Reference`^{commit}")
        $archive = Join-Path $runDirectory "$Name.zip"
        Invoke-Git @('archive', '--format=zip', "--output=$archive", $commit, '--', 'BehaviourTree') | Out-Null
        Expand-Archive -LiteralPath $archive -DestinationPath $destination
        $dirty = $false
    }
    $package = Join-Path $destination 'BehaviourTree'
    if (-not (Test-Path -LiteralPath (Join-Path $package 'init.luau'))) { throw "$Reference has no BehaviourTree package" }
    return [ordered]@{
        label = $Reference
        commit = $commit
        worktree = ($Reference -eq 'WORKTREE')
        dirty = $dirty
        sourceHash = Get-SourceHash $package
    }
}

$baselineInfo = Export-Variant $Baseline 'Baseline'
$candidateInfo = Export-Variant $Candidate 'Candidate'
$harnessDirectory = Join-Path $runDirectory 'Harness'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'lib') -Destination $harnessDirectory -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Run.server.luau') -Destination (Join-Path $runDirectory 'Run.server.luau')
$manifest = [ordered]@{
    schemaVersion = 1
    preparedAt = [DateTime]::UtcNow.ToString('o')
    environmentLabel = $EnvironmentLabel
    baseline = $baselineInfo
    candidate = $candidateInfo
    harnessHash = Get-SourceHash $harnessDirectory
    runnerHash = (Get-FileHash -LiteralPath (Join-Path $runDirectory 'Run.server.luau') -Algorithm SHA256).Hash.ToLowerInvariant()
    config = [ordered]@{
        workload = $Workload
        samples = $Samples
        warmupBatches = $WarmupBatches
        maxIterations = $MaxIterations
        targetSeconds = $TargetMilliseconds / 1000
    }
    printJson = [bool]$PrintJson
}
$manifestJson = $manifest | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText((Join-Path $runDirectory 'manifest.json'), $manifestJson, $utf8)
# A Lua long string preserves JSON backslashes without treating user labels as code.
$equals = '===='
while ($manifestJson.Contains("]$equals]")) { $equals += '=' }
[System.IO.File]::WriteAllText((Join-Path $runDirectory 'Manifest.luau'), "return [$equals[`n$manifestJson`n]$equals]`n", $utf8)

$project = @{
    name = 'BehaviourTreeBenchmark'
    tree = @{
        '$className' = 'DataModel'
        ServerScriptService = @{
            '$className' = 'ServerScriptService'
            Benchmark = @{
                '$className' = 'Folder'
                Baseline = @{ '$path' = './Baseline/BehaviourTree' }
                Candidate = @{ '$path' = './Candidate/BehaviourTree' }
                Harness = @{ '$path' = './Harness' }
                Manifest = @{ '$path' = './Manifest.luau' }
            }
            RunBenchmarks = @{ '$path' = './Run.server.luau' }
        }
    }
}
$projectPath = Join-Path $runDirectory 'benchmark.project.json'
[System.IO.File]::WriteAllText($projectPath, ($project | ConvertTo-Json -Depth 10), $utf8)
if ($Build) {
    $placePath = Join-Path $runDirectory 'benchmark.rbxlx'
    & rojo build $projectPath -o $placePath
    if ($LASTEXITCODE -ne 0) { throw 'Rojo benchmark build failed' }
    Write-Output "Open in Studio and press Play: $placePath"
}
Write-Output "Manifest: $(Join-Path $runDirectory 'manifest.json')"
Write-Output "Rojo project: $projectPath"
if ($baselineInfo.sourceHash -eq $candidateInfo.sourceHash) {
    Write-Output 'Source snapshots match: this is an A/A noise check for legacy workloads.'
}
