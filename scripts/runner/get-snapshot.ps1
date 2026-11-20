# Download a gallery database snapshot and check its digest against recordings/manifest.json before
# anything restores it. Fails on any difference.
# Snapshots are kept as assets of the GitHub Release snapshots-v1, because workflow artifacts expire.
# Each asset is the snapshot folder as a .tar.gz, named after the artifact and the run that made it,
# both read from the manifest:
#   -State a  seed-snapshot-<snapshotRun id>.tar.gz       (the spec 01 seed, made by old-app.yml)
#   -State b  state-b-snapshot-<stateBSnapshotRun id>.tar.gz  (made by record.yml)
# The manifest holds the folder digest the recordings were made from (Get-FolderDigest), so a
# replaced asset fails here. Needs gh, with GH_TOKEN set.
param([Parameter(Mandatory)] [ValidateSet('a', 'b')] [string]$State, [Parameter(Mandatory)] [string]$Dir,
      [string]$Manifest = (Join-Path $PSScriptRoot '../../recordings/manifest.json'))
. "$PSScriptRoot\common.ps1"
$m = Get-Content $Manifest -Raw | ConvertFrom-Json
$asset, $want = if ($State -eq 'a') { (Get-SnapshotAssetName 'seed-snapshot' $m.snapshotRun), $m.snapshotSha256 }
                else { (Get-SnapshotAssetName 'state-b-snapshot' $m.stateBSnapshotRun), $m.stateBSnapshotSha256 }

$download = Join-Path ([IO.Path]::GetTempPath()) "snapshot-$State-$PID"
New-Item -ItemType Directory -Force -Path $download, $Dir | Out-Null
& gh release download $SnapshotRelease --repo $env:GITHUB_REPOSITORY --pattern $asset --dir $download --clobber
if ($LASTEXITCODE -ne 0) { throw "could not download $asset from release $SnapshotRelease" }
& tar -xzf (Join-Path $download $asset) -C $Dir
if ($LASTEXITCODE -ne 0) { throw "could not extract $asset" }
Remove-Item $download -Recurse -Force

$digest = Get-FolderDigest $Dir
if ($digest -ne $want) { throw "$asset has digest $digest; recordings/manifest.json says the recordings were made from $want" }
Write-Summary "- snapshot: $asset from release $SnapshotRelease, digest matches the manifest ($digest)"
