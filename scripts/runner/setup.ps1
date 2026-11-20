# Run the gallery's own tools\Setup-DevEnvironment.ps1, then assert what it should have done,
# because the script itself does not check the exit codes of appcmd or ef6.exe.
. "$PSScriptRoot\common.ps1"

# Create and start LocalDB, and wait until it answers a query, before the gallery's script uses it.
# On a fresh runner the first start sometimes fails with "SQL Server process failed to start"
# (spec 02 run log: 2 of 22 attempts of restore-on-fresh-machine). Up to five attempts, each logged
# to the job summary, so the run log can count them.
$attempt = 0
while ($true) {
    $attempt++
    & sqllocaldb create MSSQLLocalDB 2>&1 | Write-Host
    & sqllocaldb start MSSQLLocalDB 2>&1 | Write-Host
    try { Invoke-Sql 'SELECT 1 AS ok' -TimeoutSeconds 30 | Out-Null; break }
    catch {
        Write-Summary "- setup: LocalDB attempt $attempt did not answer: $($_.Exception.Message)"
        if ($attempt -ge 5) { throw "LocalDB did not start in $attempt attempts" }
        & sqllocaldb stop MSSQLLocalDB -k 2>&1 | Write-Host
        Start-Sleep -Seconds (10 * $attempt)
    }
}
& sqllocaldb info MSSQLLocalDB
Write-Summary "- setup: LocalDB answering after $attempt attempt(s)"

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
