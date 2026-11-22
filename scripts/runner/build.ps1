# Build the gallery the way its README says: .\build.ps1 (jobs and artifacts skipped).
. "$PSScriptRoot\common.ps1"
Push-Location $GalleryDir
try {
    # Run in a child process so this script's strict mode does not leak into the gallery's script.
    if ($env:WarningsNotAsErrors) {
        # Only upstream-fix.yml sets this (see its env). The build must then report exactly the known
        # audit finding, or it fails here, before anything is cached.
        $log = Join-Path $env:RUNNER_TEMP 'gallery-build.log'
        & cmd.exe /c "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -SkipJobs -SkipArtifacts 2>&1" | Tee-Object -FilePath $log | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "gallery build.ps1 exited $LASTEXITCODE" }
        & "$PSScriptRoot\..\upstream\audit.ps1" -Log $log
    } else {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -SkipJobs -SkipArtifacts
        if ($LASTEXITCODE -ne 0) { throw "gallery build.ps1 exited $LASTEXITCODE" }
    }
} finally { Pop-Location }
if (-not (Test-Path (Join-Path $SiteDir 'bin\NuGetGallery.dll'))) { throw 'NuGetGallery.dll not found after build' }
Write-Summary "- build: ok (NuGetGallery.dll present)"
