# Snapshot the seeded state: full backups of both gallery databases plus a copy of the
# FileSystem package store (src\NuGetGallery\App_Data\Files). reset.ps1 restores it.
param([Parameter(Mandatory)] [string]$Dir)
. "$PSScriptRoot\common.ps1"
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$Dir = (Resolve-Path $Dir).Path
foreach ($db in 'NuGetGallery', 'SupportRequest') {
    $bak = Join-Path $Dir "$db.bak"
    if (Test-Path $bak) { Remove-Item $bak }
    Invoke-Sql "BACKUP DATABASE [$db] TO DISK = N'$bak' WITH INIT, COPY_ONLY, CHECKSUM" | Out-Null
    Write-Host "backed up $db -> $bak ($((Get-Item $bak).Length) bytes)"
}
$files = Join-Path $SiteDir 'App_Data\Files'
& robocopy $files (Join-Path $Dir 'Files') /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with $LASTEXITCODE" }
$global:LASTEXITCODE = 0   # robocopy uses 1-7 for success; do not let it become the step exit code
Copy-Item (Join-Path $OutDir 'seed\expected.json') (Join-Path $Dir 'expected.json')
$n = (Get-ChildItem (Join-Path $Dir 'Files') -Recurse -File).Count
Write-Summary "- snapshot: databases backed up, package store copied ($n files)"
