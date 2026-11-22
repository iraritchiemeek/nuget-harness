# Stop the app, apply one upstream patch to the gallery checkout, rebuild with build.ps1 and start the
# app again. The checkout must be unpatched before, and afterwards its source diff must equal the patch
# byte for byte. Nothing here is saved to a cache: gallery-build has already run, on the unpatched tree.
param([Parameter(Mandatory)] [string]$Patch, [switch]$NoStart)
. "$PSScriptRoot/../runner/common.ps1"
$Patch = (Resolve-Path $Patch).Path
$checkDir = Join-Path $OutDir 'checks'
New-Item -ItemType Directory -Force -Path $checkDir | Out-Null

& git -C $GalleryDir diff --quiet HEAD
if ($LASTEXITCODE -ne 0) { throw 'the gallery checkout was not clean before the patch' }
& "$PSScriptRoot/../runner/stop-site.ps1"
& git -C $GalleryDir apply $Patch
if ($LASTEXITCODE -ne 0) { throw "git apply exited $LASTEXITCODE" }
& "$PSScriptRoot/../runner/build.ps1"

$diff = Join-Path $checkDir 'spec03-source.diff'
& git -C $GalleryDir diff --full-index "--output=$diff" HEAD
if ($LASTEXITCODE -ne 0) { throw "git diff exited $LASTEXITCODE" }
$same = (Get-FileHash $diff).Hash -eq (Get-FileHash $Patch).Hash
Write-Summary "- patched app: source diff of the checkout equals $(Split-Path $Patch -Leaf) byte for byte: $same"
if (-not $same) { throw 'the source diff of the patched checkout is not the patch' }
if (-not $NoStart) { & "$PSScriptRoot/../runner/start-site.ps1" }
