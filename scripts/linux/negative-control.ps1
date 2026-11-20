# Spec 02 check 5: the comparator can fail. Captures every request from the service, then makes
# the service serve one wrong response, by changing one row as the administrator: log4net's
# lowest-keyed version string gets "-wrong" appended (log4net appears in one request only). The
# request set is captured again, and compare.ps1 must fail and report exactly that one record.
param([string]$Server = 'http://localhost:5080')
. "$PSScriptRoot/../runner/common.ps1"
$requests = Join-Path $RepoRoot 'recordings/requests.txt'
$target = 'GET /api/v2/package-versions/log4net'

& "$PSScriptRoot/../runner/capture.ps1" -Requests $requests -Dir (Join-Path $OutDir 'control/before') -Server $Server
$sql = "SET NOCOUNT ON; UPDATE dbo.Packages SET Version = Version + N'-wrong' WHERE [Key] = (SELECT TOP (1) p.[Key]
  FROM dbo.Packages p JOIN dbo.PackageRegistrations r ON r.[Key] = p.PackageRegistrationKey WHERE r.Id = N'log4net' ORDER BY p.[Key]);
  SELECT @@ROWCOUNT;"
$n = & docker exec nuget-sql /opt/mssql-tools18/bin/sqlcmd -C -b -S localhost -U sa -P $env:SA_PASSWORD -d NuGetGallery -h -1 -W -Q $sql
if ($LASTEXITCODE -ne 0 -or "$n".Trim() -ne '1') { throw "the fault was not planted: $n" }
& "$PSScriptRoot/../runner/capture.ps1" -Requests $requests -Dir (Join-Path $OutDir 'control/after') -Server $Server

$failed = $false
try {
    & "$PSScriptRoot/../runner/compare.ps1" -Before (Join-Path $OutDir 'control/before') -After (Join-Path $OutDir 'control/after') `
        -CheckNumber 0 -Name 'negative control comparison (must fail)' -OutName check5-control.txt
} catch { $failed = $true; Write-Host "compare.ps1 failed, as it must: $_" }
$reported = @(Get-Content (Join-Path $OutDir 'checks/check5-control.txt') | Where-Object { $_ -like 'DIFFERENT *' })
$expected = "DIFFERENT  $(Get-RecordName $target)  $target"
$ok = $failed -and $reported.Count -eq 1 -and $reported[0] -ceq $expected
$detail = "compare.ps1 $(if ($failed) {'failed'} else {'PASSED'}) and reported $($reported.Count) different record(s): $($reported -join '; ')"
Write-Result 5 'the comparator can fail' $ok $detail
Write-Summary "- check 5: $(if ($ok) {'pass'} else {'FAIL'}) - $detail"
if (-not $ok) { throw "check 5: expected compare.ps1 to fail on exactly '$target'" }
