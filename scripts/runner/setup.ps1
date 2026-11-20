# Run the gallery's own tools\Setup-DevEnvironment.ps1, then assert what it should have done,
# because the script itself does not check the exit codes of appcmd or ef6.exe.
. "$PSScriptRoot\common.ps1"

& sqllocaldb create MSSQLLocalDB
& sqllocaldb start MSSQLLocalDB
& sqllocaldb info MSSQLLocalDB

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $GalleryDir 'tools\Setup-DevEnvironment.ps1')
Write-Host "Setup-DevEnvironment.ps1 exit code: $LASTEXITCODE"

$appcmd = Join-Path (Get-IISExpressDir) 'appcmd.exe'
$site = & $appcmd list site "$SiteName"
Write-Host "appcmd: $site"
if (-not $site) { throw "IIS Express site '$SiteName' was not registered" }

$ssl = (& netsh http show sslcert hostnameport=localhost:443 | Out-String)
Write-Host $ssl
if ($ssl -notmatch 'Certificate Hash') { throw 'No SSL binding for localhost:443' }

$found = @((Invoke-Sql 'SELECT name FROM sys.databases') | ForEach-Object { $_.name })
$missing = @($Databases | Where-Object { $found -notcontains $_ })
Write-Host "databases: $($found -join ',')"
if ($missing.Count) { throw "Expected databases missing: $($missing -join ',')" }

$mig = (Invoke-Sql 'SELECT COUNT(*) AS n FROM __MigrationHistory' -Database NuGetGallery)[0].n
Write-Summary "- setup: ok (site registered, SSL bound, databases $($Databases -join ' + '), $mig gallery migrations applied)"
