# The gallery's global.json asks for SDK 8.0.318 with rollForward=latestMajor, so on a runner
# that also has newer SDKs it picks the newest one. On windows-2022 that is an SDK that needs
# MSBuild 18.x, while the image's VS 2022 ships MSBuild 17.14, and restore fails with
# "Version 11.0.100 of the .NET SDK requires at least version 18.7.0 of MSBuild".
# Instead of editing the gallery's global.json, move every SDK newer than -MaxMajor out of the
# dotnet folder for this run. This changes the runner, not the app.
# MaxMajor is 9, not 8: build\common.ps1 lists projects with `dotnet sln list`, which cannot read
# the repo's .slnx file on SDK 8 ("Failed to find .csproj files found in solution ...Aspire.slnx").
param([int]$MaxMajor = 9)
. "$PSScriptRoot\common.ps1"
$sdkRoot = 'C:\Program Files\dotnet\sdk'
$parked = 'C:\dotnet-sdk-parked'
New-Item -ItemType Directory -Force -Path $parked | Out-Null
Write-Host 'SDKs before:'; & dotnet --list-sdks
Get-ChildItem $sdkRoot -Directory | Where-Object { $_.Name -match '^(\d+)\.' -and [int]$Matches[1] -gt $MaxMajor } | ForEach-Object {
    Write-Host "parking SDK $($_.Name)"
    Move-Item $_.FullName (Join-Path $parked $_.Name)
}
Write-Host 'SDKs after:'; & dotnet --list-sdks
Push-Location $GalleryDir
try { $v = (& dotnet --version).Trim() } finally { Pop-Location }
if ([int]($v.Split('.')[0]) -gt $MaxMajor) { throw "gallery folder resolves SDK $v, expected major <= $MaxMajor" }
Write-Summary "- dotnet SDK: SDKs newer than major $MaxMajor parked; gallery folder resolves SDK $v"
