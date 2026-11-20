# Fail unless a recordings folder (-Dir, by default recordings/ in the checkout) is exactly what the
# recording workflow made:
#   1. Every file listed in manifest.json has the listed SHA-256, and no file is missing or extra.
#   2. seed/state-b.txt is the push list state B was made with.
#   3. Every ignored header has a reason, and every parity exclusion meets the condition of its
#      amendment in both states (Read-ParityExclusionFile in common.ps1).
#   4. Provenance. The state B snapshot comes from the run named in the manifest. That run's commit
#      job kept the recording as the asset of the GitHub Release recordings-<run id>, because workflow
#      artifacts expire; the asset is, file for file, the folder being checked, manifest.json included.
#      The run itself must be a run of .github/workflows/record.yml on main that concluded success.
#      Run metadata outlives artifacts, but if GitHub answers 404 for the run, the check rests on the
#      release asset and the manifest's hashes alone, and the summary says so. Any other failure to
#      read the run fails the check.
#      A release asset is weaker evidence than a run artifact: anyone who can push can also replace
#      an asset, while only the run can write its artifact. The manifest hashes and the run check
#      bind the folder to the asset, not the asset to the run.
# -ThisRun is for the recording workflow, checking its own output before committing it: the
# manifest must name the current run, and the run and its release are not checked yet.
# Needs gh, with GH_TOKEN set, except with -ThisRun.
param([string]$Dir = (Join-Path $PSScriptRoot '../../recordings'), [switch]$ThisRun)
. "$PSScriptRoot\common.ps1"
$rec = (Resolve-Path $Dir).Path
$manifest = Get-Content (Join-Path $rec 'manifest.json') -Raw | ConvertFrom-Json
$problems = @()

# The SHA-256 of every file under a folder, keyed by its path relative to the folder.
function Get-FileHashTable([string]$Root) {
    $h = @{}
    foreach ($f in Get-ChildItem $Root -Recurse -File) {
        $h[$f.FullName.Substring($Root.Length + 1).Replace('\', '/')] = (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $h
}

# 1. The manifest's file list.
$actual = Get-FileHashTable $rec
$listed = @($manifest.files.PSObject.Properties.Name)
foreach ($rel in $listed) {
    if (-not $actual.ContainsKey($rel)) { $problems += "missing: $rel" }
    elseif ($actual[$rel] -ne $manifest.files.$rel) { $problems += "changed: $rel" }
}
foreach ($rel in $actual.Keys | Where-Object { $_ -ne 'manifest.json' -and $listed -notcontains $_ }) { $problems += "not in the manifest: $rel" }

# 2. The state B push list.
$list = (Get-FileHash (Join-Path $RepoRoot 'seed/state-b.txt') -Algorithm SHA256).Hash.ToLowerInvariant()
if ($list -ne $manifest.stateBList) { $problems += 'seed/state-b.txt changed since the recording' }

# 3. The ignored headers and the parity exclusions.
foreach ($line in Get-Content (Join-Path $rec 'ignored-headers.txt') | Where-Object { $_.Trim() -and -not $_.StartsWith('#') }) {
    if ($line -cnotmatch '^[a-z0-9-]+\s+\S') { $problems += "ignored header needs a lower-case name and a reason: $line" }
}
foreach ($state in 'state-a', 'state-b') {
    try { $null = Read-ParityExclusionFile -File (Join-Path $rec 'parity-exclusions.txt') -Recorded (Join-Path $rec $state) }
    catch { $problems += "parity exclusions, ${state}: $_" }
}

# 4. Provenance.
if ($manifest.run -notmatch '/actions/runs/(\d+)$') { throw "manifest run is not a run URL: $($manifest.run)" }
$runId = $Matches[1]
if ($manifest.stateBSnapshotRun -ne $manifest.run) { $problems += "the state B snapshot comes from $($manifest.stateBSnapshotRun), not the recording run $($manifest.run)" }
if ($ThisRun) {
    if ($runId -ne $env:GITHUB_RUN_ID) { $problems += "the manifest names run $runId, not this run ($env:GITHUB_RUN_ID)" }
} else {
    $tag = Get-RecordingReleaseTag $manifest.run
    $download = Join-Path ([IO.Path]::GetTempPath()) "recording-$runId-$PID"
    $release = Join-Path $download 'tree'
    New-Item -ItemType Directory -Force -Path $release | Out-Null
    & gh release download $tag --repo $env:GITHUB_REPOSITORY --pattern "$tag.tar.gz" --dir $download --clobber
    if ($LASTEXITCODE -ne 0) { throw "could not download $tag.tar.gz from release $tag" }
    & tar -xzf (Join-Path $download "$tag.tar.gz") -C $release
    if ($LASTEXITCODE -ne 0) { throw "could not extract $tag.tar.gz" }
    $expected = Get-FileHashTable (Resolve-Path $release).Path
    foreach ($rel in $expected.Keys) {
        if (-not $actual.ContainsKey($rel)) { $problems += "in release $tag, not here: $rel" }
        elseif ($actual[$rel] -ne $expected[$rel]) { $problems += "differs from release ${tag}: $rel" }
    }
    foreach ($rel in $actual.Keys | Where-Object { -not $expected.ContainsKey($_) }) { $problems += "not in release ${tag}: $rel" }
    Remove-Item $download -Recurse -Force

    $errors = Join-Path ([IO.Path]::GetTempPath()) "run-$runId-$PID.err"
    $runJson = & gh api "repos/$env:GITHUB_REPOSITORY/actions/runs/$runId" 2> $errors
    $runError = Get-Content $errors -Raw
    Remove-Item $errors
    if ($LASTEXITCODE -eq 0) {
        $run = $runJson | ConvertFrom-Json
        if ($run.path -ne '.github/workflows/record.yml' -or $run.head_branch -ne 'main' -or $run.conclusion -ne 'success') {
            $problems += "run $runId is $($run.path) on $($run.head_branch), concluded '$($run.conclusion)'; the recordings must come from a successful record.yml run on main"
        }
        $runChecked = 'its run is a successful record.yml run on main'
    } elseif ($runError -match 'HTTP 404') {
        $runChecked = "GitHub no longer has run $runId, so this rests on the release asset and the manifest hashes"
    } else {
        throw "could not read run ${runId}: $runError"
    }

    # A signal, not a control: anyone who can push can also set this author name.
    $author = (& git -C $RepoRoot log -1 --format='%an' -- recordings/manifest.json recordings/state-a recordings/state-b | Out-String).Trim()
    if ($author -ne 'github-actions[bot]') { $problems += "last commit to the recordings was by '$author', not the recording workflow" }
}

if ($problems.Count) { $problems | Write-Host; throw "recordings do not match what the recording run made ($($problems.Count) problems)" }
$from = if ($ThisRun) { 'this run' } else { "release $tag ($runChecked)" }
Write-Summary "- recordings verified: $($listed.Count) files match recordings/manifest.json and $from"
