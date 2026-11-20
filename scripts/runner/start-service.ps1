# Spec 02 check 6: start the new service (a self-contained win-x64 build) next to the old app,
# on http://localhost:5080, reading the same LocalDB database as the old app with the read-only
# login `reader` (db_datareader only). The login's password is generated here and masked. Like
# IIS Express (start-site.ps1), the service is created through WMI so it outlives the step.
param([Parameter(Mandatory)] [string]$ServiceDir, [string]$Url = 'http://localhost:5080')
. "$PSScriptRoot\common.ps1"
$bytes = New-Object byte[] 16
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$password = 'Pw1-' + -join ($bytes | ForEach-Object { $_.ToString('x2') })
Write-Host "::add-mask::$password"
Invoke-Sql "IF SUSER_ID(N'reader') IS NULL CREATE LOGIN [reader] WITH PASSWORD = N'$password', CHECK_POLICY = OFF
            ELSE ALTER LOGIN [reader] WITH PASSWORD = N'$password'" | Out-Null
Invoke-Sql -Database 'NuGetGallery' "IF USER_ID(N'reader') IS NULL CREATE USER [reader] FOR LOGIN [reader];
                                      ALTER ROLE [db_datareader] ADD MEMBER [reader];" | Out-Null
$roles = @(Invoke-Sql -Database 'NuGetGallery' "SELECT r.name FROM sys.database_role_members m
  JOIN sys.database_principals r ON r.principal_id = m.role_principal_id
  JOIN sys.database_principals u ON u.principal_id = m.member_principal_id WHERE u.name = N'reader'" | ForEach-Object { $_.name })
Write-Summary "- service login reader: database roles $($roles -join ', ')"
if (($roles -join ',') -ne 'db_datareader') { throw "reader has roles $($roles -join ','), expected db_datareader only" }

$exe = Join-Path (Resolve-Path $ServiceDir).Path 'GalleryReadService.exe'
$log = Join-Path $OutDir 'service.log'
$cs = "Server=(localdb)\MSSQLLocalDB;Database=NuGetGallery;User Id=reader;Password=$password;TrustServerCertificate=True"
$cmdLine = "cmd.exe /c `"`"$exe`" --urls $Url `"--Database:ConnectionString=$cs`" > `"$log`" 2>&1`""
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmdLine }
if ($r.ReturnValue -ne 0) { throw "Win32_Process.Create returned $($r.ReturnValue)" }
foreach ($i in 1..60) {
    $h = Invoke-Curl -Path "$Url/health" -OutFile (Join-Path $OutDir 'service-health.txt')
    if ($h.Status -eq 200) { Write-Summary "- service: healthy at $Url"; return }
    Start-Sleep -Seconds 1
}
throw "the service did not become healthy: $(Get-Content $log -Raw -ErrorAction SilentlyContinue)"
