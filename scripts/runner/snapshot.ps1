# Snapshot the seeded state: full backups of both gallery databases plus a copy of the
# FileSystem package store (src\NuGetGallery\App_Data\Files). reset.ps1 restores it.
param([Parameter(Mandatory)] [string]$Dir)
. "$PSScriptRoot\common.ps1"
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$Dir = (Resolve-Path $Dir).Path
foreach ($db in $Databases) {
    $bak = Join-Path $Dir "$db.bak"
    if (Test-Path $bak) { Remove-Item $bak }
    Invoke-Sql "BACKUP DATABASE [$db] TO DISK = N'$bak' WITH INIT, COPY_ONLY, CHECKSUM" | Out-Null
    Write-Host "backed up $db -> $bak ($((Get-Item $bak).Length) bytes)"
}
$files = Join-Path $SiteDir 'App_Data\Files'
Copy-Mirror -From $files -To (Join-Path $Dir 'Files')
Copy-Item (Join-Path $OutDir 'seed\expected.json') (Join-Path $Dir 'expected.json')
$n = (Get-ChildItem (Join-Path $Dir 'Files') -Recurse -File).Count
Write-Summary "- snapshot: databases backed up, package store copied ($n files)"
