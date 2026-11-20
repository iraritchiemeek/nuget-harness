# Build the gallery the way its README says: .\build.ps1 (jobs and artifacts skipped).
. "$PSScriptRoot\common.ps1"
Push-Location $GalleryDir
try {
    # Run in a child process so this script's strict mode does not leak into the gallery's script.
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -SkipJobs -SkipArtifacts
    if ($LASTEXITCODE -ne 0) { throw "gallery build.ps1 exited $LASTEXITCODE" }
} finally { Pop-Location }
if (-not (Test-Path (Join-Path $SiteDir 'bin\NuGetGallery.dll'))) { throw 'NuGetGallery.dll not found after build' }
Write-Summary "- build: ok (NuGetGallery.dll present)"
