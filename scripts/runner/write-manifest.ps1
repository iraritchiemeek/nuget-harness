# Assemble a recording in -Out, laid out as recordings/ is in the repository: the request set,
# ignored headers and parity exclusions this run used (from recordings/ in the checkout), the
# verified records of both data states in state-a and state-b, and manifest.json. The manifest says
# where the recording came from (run, app commit, the two snapshots, the state B push list) and
# holds the SHA-256 of every other file. verify-recordings.ps1 checks all of it on every run.
# Only the recording workflow runs this; its commit job copies -Out into recordings/.
param([Parameter(Mandatory)] [string]$Out, [Parameter(Mandatory)] [string]$StateA, [Parameter(Mandatory)] [string]$StateB,
      [Parameter(Mandatory)] [string]$Snapshot, [Parameter(Mandatory)] [string]$StateBSnapshot)
. "$PSScriptRoot\common.ps1"
$inputs = Join-Path $RepoRoot 'recordings'
if (Test-Path $Out) { Remove-Item $Out -Recurse -Force }
New-Item -ItemType Directory -Path $Out | Out-Null
$Out = (Resolve-Path $Out).Path
foreach ($name in 'requests.txt', 'ignored-headers.txt', 'parity-exclusions.txt') { Copy-Item (Join-Path $inputs $name) $Out }
foreach ($state in @(@{ Name = 'state-a'; From = $StateA }, @{ Name = 'state-b'; From = $StateB })) {
    $to = Join-Path $Out $state.Name
    New-Item -ItemType Directory -Path $to | Out-Null
    Copy-Item (Join-Path $state.From '*') $to
}

$files = [ordered]@{}
foreach ($f in @(Get-ChildItem $Out -Recurse -File | Sort-Object FullName)) {
    $rel = $f.FullName.Substring($Out.Length + 1).Replace('\', '/')
    $files[$rel] = (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
$run = "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID"
$previous = Get-Content (Join-Path $inputs 'manifest.json') -Raw | ConvertFrom-Json
$manifest = [ordered]@{
    run                  = $run
    appCommit            = $env:GALLERY_SHA
    snapshotRun          = $previous.snapshotRun   # state A: the seed snapshot, fixed since spec 01
    snapshotSha256       = Get-FolderDigest $Snapshot
    stateBList           = (Get-FileHash (Join-Path $RepoRoot 'seed/state-b.txt') -Algorithm SHA256).Hash.ToLowerInvariant()
    stateBSnapshotRun    = $run
    stateBSnapshotSha256 = Get-FolderDigest $StateBSnapshot
    requests             = @(Get-Content (Join-Path $Out 'state-a/_index.tsv')).Count
    files                = $files
}
Write-Utf8File (Join-Path $Out 'manifest.json') @($manifest | ConvertTo-Json -Depth 4)
Write-Summary "- recording: $($manifest.requests) requests in each of two states, manifest lists $($files.Count) files"
