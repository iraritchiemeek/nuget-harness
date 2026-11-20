# Fail unless recordings/ is exactly what the recording workflow wrote: every file listed in
# recordings/manifest.json has the listed SHA-256, no file is missing or extra, the snapshot to
# restore (-Snapshot) has the digest the recordings were made from, and the last commit that
# touched recordings/ was made by the recording workflow's bot account (skipped with -BeforeCommit,
# which the recording workflow uses to check its own output before committing it).
param([string]$Snapshot, [switch]$BeforeCommit)
. "$PSScriptRoot\common.ps1"
$rec = Join-Path $RepoRoot 'recordings'
$manifest = Get-Content (Join-Path $rec 'manifest.json') -Raw | ConvertFrom-Json
$problems = @()
$listed = @($manifest.files.PSObject.Properties.Name)
foreach ($rel in $listed) {
    $path = Join-Path $rec $rel
    if (-not (Test-Path $path)) { $problems += "missing: $rel"; continue }
    $hash = (Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $manifest.files.$rel) { $problems += "changed: $rel" }
}
foreach ($f in Get-ChildItem $rec -Recurse -File | Where-Object { $_.Name -ne 'manifest.json' }) {
    $rel = $f.FullName.Substring($rec.Length + 1).Replace('\', '/')
    if ($listed -notcontains $rel) { $problems += "not in the manifest: $rel" }
}
if ($Snapshot) {
    $digest = Get-FolderDigest $Snapshot
    if ($digest -ne $manifest.snapshotSha256) { $problems += "snapshot digest $digest, recordings were made from $($manifest.snapshotSha256)" }
}
if (-not $BeforeCommit) {
    $author = (& git -C $RepoRoot log -1 --format='%an' -- recordings/manifest.json recordings/responses | Out-String).Trim()
    if ($author -ne 'github-actions[bot]') { $problems += "last commit to the recordings was by '$author', not the recording workflow" }
}

if ($problems.Count) { $problems | Write-Host; throw "recordings do not match the manifest ($($problems.Count) problems)" }
Write-Summary "- recordings verified: $($listed.Count) files match recordings/manifest.json, recorded by $($manifest.run)"
