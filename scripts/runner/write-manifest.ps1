# Copy verified recordings of both data states into recordings/state-a and recordings/state-b and
# write recordings/manifest.json: where the recordings came from (run, app commit, the two
# snapshots, the state B push list) and the SHA-256 of every file they rest on.
# verify-recordings.ps1 checks those hashes on every run. Only the recording workflow runs this.
param([Parameter(Mandatory)] [string]$StateA, [Parameter(Mandatory)] [string]$StateB,
      [Parameter(Mandatory)] [string]$Snapshot, [Parameter(Mandatory)] [string]$StateBSnapshot)
. "$PSScriptRoot\common.ps1"
$rec = Join-Path $RepoRoot 'recordings'
foreach ($state in @(@{ Name = 'state-a'; From = $StateA }, @{ Name = 'state-b'; From = $StateB })) {
    $to = Join-Path $rec $state.Name
    if (Test-Path $to) { Remove-Item $to -Recurse -Force }
    New-Item -ItemType Directory -Path $to | Out-Null
    Copy-Item (Join-Path $state.From '*') $to
}

$files = [ordered]@{}
foreach ($f in @(Get-ChildItem $rec -Recurse -File | Where-Object { $_.Name -ne 'manifest.json' } | Sort-Object FullName)) {
    $rel = $f.FullName.Substring($rec.Length + 1).Replace('\', '/')
    $files[$rel] = (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
$run = "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID"
$manifest = [ordered]@{
    run                  = $run
    appCommit            = $env:GALLERY_SHA
    snapshotRun          = "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/$env:SNAPSHOT_RUN_ID"
    snapshotSha256       = Get-FolderDigest $Snapshot
    stateBList           = (Get-FileHash (Join-Path $RepoRoot 'seed/state-b.txt') -Algorithm SHA256).Hash.ToLowerInvariant()
    stateBSnapshotRun    = $run
    stateBSnapshotSha256 = Get-FolderDigest $StateBSnapshot
    requests             = @(Get-Content (Join-Path $rec 'state-a/_index.tsv')).Count
    files                = $files
}
Write-Utf8File (Join-Path $rec 'manifest.json') @($manifest | ConvertTo-Json -Depth 4)
Write-Summary "- recordings: $($manifest.requests) requests in each of two states, manifest lists $($files.Count) files"
