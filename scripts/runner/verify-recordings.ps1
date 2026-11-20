# Fail unless recordings/ is exactly what the recording workflow wrote: every file listed in
# recordings/manifest.json has the listed SHA-256, no file is missing or extra, seed/state-b.txt is
# the push list state B was made with, the snapshots to restore (-Snapshot for state A,
# -StateBSnapshot for state B; each checked when given) have the digests the recordings were made
# from, and the last commit that touched the recordings was made by the recording workflow's bot
# account (skipped with -BeforeCommit, which the recording workflow uses to check its own output
# before committing it).
param([string]$Snapshot, [string]$StateBSnapshot, [switch]$BeforeCommit)
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
$list = (Get-FileHash (Join-Path $RepoRoot 'seed/state-b.txt') -Algorithm SHA256).Hash.ToLowerInvariant()
if ($list -ne $manifest.stateBList) { $problems += 'seed/state-b.txt changed since the recording' }
foreach ($s in @(@{ Dir = $Snapshot; Want = $manifest.snapshotSha256; Name = 'state A' },
                 @{ Dir = $StateBSnapshot; Want = $manifest.stateBSnapshotSha256; Name = 'state B' })) {
    if (-not $s.Dir) { continue }
    $digest = Get-FolderDigest $s.Dir
    if ($digest -ne $s.Want) { $problems += "$($s.Name) snapshot digest $digest, recordings were made from $($s.Want)" }
}
if (-not $BeforeCommit) {
    $author = (& git -C $RepoRoot log -1 --format='%an' -- recordings/manifest.json recordings/state-a recordings/state-b | Out-String).Trim()
    if ($author -ne 'github-actions[bot]') { $problems += "last commit to the recordings was by '$author', not the recording workflow" }
}

if ($problems.Count) { $problems | Write-Host; throw "recordings do not match the manifest ($($problems.Count) problems)" }
Write-Summary "- recordings verified: $($listed.Count) files match recordings/manifest.json, recorded by $($manifest.run)"
