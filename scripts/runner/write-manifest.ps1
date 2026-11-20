# Copy a verified recording into recordings/responses and write recordings/manifest.json: where
# the recording came from (run, app commit, snapshot) and the SHA-256 of every file it rests on.
# verify-recordings.ps1 checks those hashes on every run. Only the recording workflow runs this.
param([Parameter(Mandatory)] [string]$From, [Parameter(Mandatory)] [string]$Snapshot)
. "$PSScriptRoot\common.ps1"
$rec = Join-Path $RepoRoot 'recordings'
$responses = Join-Path $rec 'responses'
if (Test-Path $responses) { Remove-Item $responses -Recurse -Force }
New-Item -ItemType Directory -Path $responses | Out-Null
Copy-Item (Join-Path $From '*') $responses

$files = [ordered]@{}
foreach ($f in @(Get-ChildItem $rec -Recurse -File | Where-Object { $_.Name -ne 'manifest.json' } | Sort-Object FullName)) {
    $rel = $f.FullName.Substring($rec.Length + 1).Replace('\', '/')
    $files[$rel] = (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
$manifest = [ordered]@{
    run             = "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID"
    appCommit       = $env:GALLERY_SHA
    snapshotRun     = "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/$env:SNAPSHOT_RUN_ID"
    snapshotSha256  = Get-FolderDigest $Snapshot
    requests        = @(Get-Content (Join-Path $responses '_index.tsv')).Count
    files           = $files
}
Write-Utf8File (Join-Path $rec 'manifest.json') @($manifest | ConvertTo-Json -Depth 4)
Write-Summary "- recordings: $($manifest.requests) records written, manifest lists $($files.Count) files; snapshot sha256 $($manifest.snapshotSha256)"
