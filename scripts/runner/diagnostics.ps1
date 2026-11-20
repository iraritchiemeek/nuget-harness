# Collect diagnostics into out\diag. Runs on failure and success. Never fails.
$ErrorActionPreference = 'Continue'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$diag = Join-Path $RepoRoot 'out\diag'
New-Item -ItemType Directory -Force -Path $diag | Out-Null
& sqllocaldb info MSSQLLocalDB > (Join-Path $diag 'sqllocaldb-info.txt') 2>&1
Get-Process iisexpress -ErrorAction SilentlyContinue | Format-List * > (Join-Path $diag 'iisexpress-process.txt')
$logs = Join-Path $env:USERPROFILE 'Documents\IISExpress'
if (Test-Path $logs) { Copy-Item $logs (Join-Path $diag 'IISExpress-userdir') -Recurse -Force -ErrorAction SilentlyContinue }
Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = (Get-Date).AddHours(-3) } -MaxEvents 200 -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -match 'ASP.NET|IIS|\.NET Runtime|Application Error|MSSQL' } |
    Format-List TimeCreated, ProviderName, Id, Message > (Join-Path $diag 'eventlog.txt')
Write-Host "diagnostics written to $diag"
exit 0
