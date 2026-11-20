# Put the gallery back to a snapshot made by snapshot.ps1: stop IIS Express, restore both
# databases (works on a fresh machine too), replace the package store, start IIS Express.
param([Parameter(Mandatory)] [string]$Dir, [switch]$NoStart)
. "$PSScriptRoot\common.ps1"
$Dir = (Resolve-Path $Dir).Path
& "$PSScriptRoot\stop-site.ps1"
& sqllocaldb start MSSQLLocalDB | Out-Null
$dataPath = (Invoke-Sql "SELECT CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS nvarchar(400)) AS p")[0].p
foreach ($db in 'NuGetGallery', 'SupportRequest') {
    $bak = Join-Path $Dir "$db.bak"
    $moves = (Invoke-Sql "RESTORE FILELISTONLY FROM DISK = N'$bak'") | ForEach-Object {
        $ext = if ($_.Type -eq 'L') { '_log.ldf' } else { '.mdf' }
        "MOVE N'$($_.LogicalName)' TO N'$(Join-Path $dataPath ($db + $ext))'"
    }
    $exists = (Invoke-Sql "SELECT COUNT(*) AS n FROM sys.databases WHERE name = N'$db'")[0].n
    if ($exists) { Invoke-Sql "ALTER DATABASE [$db] SET SINGLE_USER WITH ROLLBACK IMMEDIATE" | Out-Null }
    Invoke-Sql "RESTORE DATABASE [$db] FROM DISK = N'$bak' WITH REPLACE, CHECKSUM, $($moves -join ', ')" | Out-Null
    Invoke-Sql "ALTER DATABASE [$db] SET MULTI_USER" | Out-Null
    Write-Host "restored $db"
}
$files = Join-Path $SiteDir 'App_Data\Files'
& robocopy (Join-Path $Dir 'Files') $files /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with $LASTEXITCODE" }
New-Item -ItemType Directory -Force -Path (Join-Path $OutDir 'seed') | Out-Null
Copy-Item (Join-Path $Dir 'expected.json') (Join-Path $OutDir 'seed\expected.json') -Force
Write-Summary "- reset: databases restored and package store replaced from $Dir"
if (-not $NoStart) { & "$PSScriptRoot\start-site.ps1" }
