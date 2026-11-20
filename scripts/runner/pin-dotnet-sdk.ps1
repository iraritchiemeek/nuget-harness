# The gallery's global.json asks for SDK 8.0.318 with rollForward=latestMajor, so on a runner
# that also has newer SDKs it picks the newest one. On windows-2022 that is an SDK that needs
# MSBuild 18.x, while the image's VS 2022 ships MSBuild 17.14, and restore fails with
# "Version 11.0.100 of the .NET SDK requires at least version 18.7.0 of MSBuild".
# Instead of editing the gallery's global.json, move every SDK newer than major 8 out of the
# dotnet folder for this run. This changes the runner, not the app.
. "$PSScriptRoot\common.ps1"
$sdkRoot = 'C:\Program Files\dotnet\sdk'
$parked = 'C:\dotnet-sdk-parked'
New-Item -ItemType Directory -Force -Path $parked | Out-Null
Write-Host 'SDKs before:'; & dotnet --list-sdks
Get-ChildItem $sdkRoot -Directory | Where-Object { $_.Name -match '^(\d+)\.' -and [int]$Matches[1] -gt 8 } | ForEach-Object {
    Write-Host "parking SDK $($_.Name)"
    Move-Item $_.FullName (Join-Path $parked $_.Name)
}
Write-Host 'SDKs after:'; & dotnet --list-sdks
Push-Location $GalleryDir
try { $v = (& dotnet --version).Trim() } finally { Pop-Location }
if ($v -notmatch '^8\.') { throw "gallery folder resolves SDK $v, expected 8.x" }
Write-Summary "- dotnet SDK: newer-than-8 SDKs parked; gallery folder resolves SDK $v"
