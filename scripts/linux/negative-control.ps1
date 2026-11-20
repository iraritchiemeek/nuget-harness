# Spec 02 check 5: the comparator can fail, on the path check 3 takes: compare.ps1 between the
# committed state A recordings and the service's answers, with the parity exclusions and the
# approved differences (spec 02b).
#   - First the service's answers, captured as check 3 captures them, must pass. A fault planted
#     into answers that already fail would prove nothing.
#   - Then five faults, one per comparison. Four are planted into copies of those answers: a wrong
#     status on a status-only record, a changed compared header, a deleted record, and versions out
#     of SemVer order (the old app's own recorded body, served where the approved difference
#     'package-versions in SemVer order' applies). The fifth is served by the service: log4net's
#     lowest-keyed version string gets "-wrong" appended in the database (log4net appears in one
#     request only), and the request set is captured again.
# Each faulted comparison must fail, report exactly the planted record, and report it for the
# planted reason.
param([string]$Server = 'http://localhost:5080')
. "$PSScriptRoot/../runner/common.ps1"
$recordings = Join-Path $RepoRoot 'recordings'
$recorded = Join-Path $recordings 'state-a'
$requests = Join-Path $recordings 'requests.txt'
$exclusions = Join-Path $recordings 'parity-exclusions.txt'
$approved = Join-Path $recordings 'approved-differences.json'
$semVerRule = "  (after approved difference 'package-versions in SemVer order')"
$control = Join-Path $OutDir 'control'

function Invoke-Compare([string]$Answers, [string]$Case) {
    & "$PSScriptRoot/../runner/compare.ps1" -Before $recorded -After $Answers -Exclusions $exclusions -ApprovedDifferences $approved `
        -CheckNumber 0 -Name "negative control, $Case" -OutName "spec02-check5-$Case.txt"
}

# The records a comparison reported, each with its detail lines.
function Get-Reported([string]$Case) {
    $found = @(); $current = $null
    foreach ($line in Get-Content (Join-Path $OutDir "checks/spec02-check5-$Case.txt")) {
        if ($line -match '^(DIFFERENT|MISSING) ') { $current = [pscustomobject]@{ Line = $line; Detail = @() }; $found += $current }
        elseif ($line.StartsWith('    ') -and $current) { $current.Detail += $line }
        else { $current = $null }
    }
    return $found
}

$answers = Join-Path $control 'service'
& "$PSScriptRoot/../runner/capture.ps1" -Requests $requests -Dir $answers -Server $Server
Invoke-Compare $answers 'baseline'

# Each case: the planted record, the report line it must get, and a pattern every detail line must match.
$cases = @(
    @{ Case = 'status-only-status'; Request = 'GET /api/v2/package-versions/%20'; Suffix = '  (status only)'; Detail = '^    meta (expected  status: 404|actual    status: 500)$'
       Plant = { param($r) $m = "$r.meta"; (Get-Content $m) -replace '^status: \d+$', 'status: 500' | Set-Content $m } },
    @{ Case = 'header'; Request = 'GET /api/v2/package-ids?partialId=Serilog'; Suffix = ''; Detail = '^    meta (expected  x-frame-options: deny|actual    x-frame-options: sameorigin)$'
       Plant = { param($r) $m = "$r.meta"; (Get-Content $m) -creplace '^x-frame-options: deny$', 'x-frame-options: sameorigin' | Set-Content $m } },
    @{ Case = 'deleted'; Request = 'GET /api/v2/package-ids?partialId=Polly'; Suffix = '  (only in the expected side)'; Detail = '^$'
       Plant = { param($r) Remove-Item "$r.meta", "$r.body" } },
    @{ Case = 'out-of-order'; Request = 'GET /api/v2/package-versions/Newtonsoft.Json'; Suffix = $semVerRule
       Detail = '^    body (expected  \["5\.0\.7","8\.0\.3","13\.0\.4"\]|actual    \["8\.0\.3","5\.0\.7","13\.0\.4"\])$'
       Plant = { param($r) Copy-Item (Join-Path $recorded "$(Split-Path $r -Leaf).body") "$r.body" -Force } }
)
foreach ($c in $cases) {
    $dir = Join-Path $control $c.Case
    Copy-Item $answers $dir -Recurse
    & $c.Plant (Join-Path $dir (Get-RecordName $c.Request))
}
$log4net = 'GET /api/v2/package-versions/log4net'
$cases += @{ Case = 'served-body'; Request = $log4net; Suffix = $semVerRule; Detail = '^    body (expected|actual)  ' }
$sql = "SET NOCOUNT ON; UPDATE dbo.Packages SET Version = Version + N'-wrong' WHERE [Key] = (SELECT TOP (1) p.[Key]
  FROM dbo.Packages p JOIN dbo.PackageRegistrations r ON r.[Key] = p.PackageRegistrationKey WHERE r.Id = N'log4net' ORDER BY p.[Key]);
  SELECT @@ROWCOUNT;"
$n = & "$PSScriptRoot/sqlcmd.sh" -d NuGetGallery -h -1 -W -Q $sql
if ($LASTEXITCODE -ne 0 -or "$n".Trim() -ne '1') { throw "the fault was not planted in the database: $n" }
& "$PSScriptRoot/../runner/capture.ps1" -Requests $requests -Dir (Join-Path $control 'served-body') -Server $Server

$results = foreach ($c in $cases) {
    $failed = $false
    try { Invoke-Compare (Join-Path $control $c.Case) $c.Case } catch { $failed = $true }
    $reported = @(Get-Reported $c.Case)
    $verb = if ($c.Case -eq 'deleted') { 'MISSING   ' } else { 'DIFFERENT ' }
    $want = "$verb $(Get-RecordName $c.Request)  $($c.Request)$($c.Suffix)"
    $ok = $failed -and $reported.Count -eq 1 -and $reported[0].Line -ceq $want -and
        @($reported[0].Detail | Where-Object { $_ -cnotmatch $c.Detail }).Count -eq 0
    [pscustomobject]@{ Ok = $ok; Case = $c.Case; Failed = $failed; Reported = (@($reported | ForEach-Object { @($_.Line) + $_.Detail }) -join ' | ') }
}
$results | Format-Table -AutoSize -Wrap | Out-String -Width 250 | Write-Host

$bad = @($results | Where-Object { -not $_.Ok })
$ok = $bad.Count -eq 0
$detail = "the service's answers pass; $($results.Count - $bad.Count)/$($results.Count) planted faults (status-only status, header, deleted record, versions out of SemVer order, served body) each failed the comparison on exactly the planted record, for the planted reason"
Write-Result 5 'the comparator can fail' $ok $detail
Write-Summary "- check 5: $(if ($ok) {'pass'} else {'FAIL'}) - $detail"
if (-not $ok) { throw "check 5: $($bad.Count) planted faults were not reported as planted: $($bad.Case -join ', ')" }
