# Spec 02 check 4: the service answers from the database, not from the recordings. Runs
# mutate.sql against the restored state A database as the administrator, then asks the service
# for the affected responses and checks each one against what the data now says: the state A
# recording plus exactly the change mutate.sql made.
# Versions are compared as sets, because the old app's version query has no ORDER BY; ID lists
# are compared in order (ORDER BY Id). The new IDs start with "Zz" after their prefix, so under
# the database collation they sort after every seeded ID with that prefix.
param([Parameter(Mandatory)] [string]$Recorded, [string]$Server = 'http://localhost:5080')
. "$PSScriptRoot/../runner/common.ps1"
$recordedDir = $Recorded; $serverUrl = $Server

& docker cp "$PSScriptRoot/mutate.sql" nuget-sql:/tmp/mutate.sql
$out = & docker exec nuget-sql /opt/mssql-tools18/bin/sqlcmd -C -b -S localhost -U sa -P $env:SA_PASSWORD -d NuGetGallery -h -1 -W -s '|' -i /tmp/mutate.sql
if ($LASTEXITCODE -ne 0) { throw "mutate.sql failed: $out" }
$unlisted = @($out | Where-Object { $_ -like 'unlisted|*' } | ForEach-Object { $_.Split('|')[1] })
if ($unlisted.Count -ne 1) { throw "expected one unlisted version, got: $out" }
$unlisted = $unlisted[0]
Write-Host "mutate.sql: added Serilog 9.9.9, Serilog.Sinks.ZzHarness 1.0.0, Serilog.ZzHarness 1.0.0-beta.1; unlisted Serilog.Sinks.Console $unlisted"

function Get-Recorded([string]$Path) {
    $file = Join-Path $recordedDir "$(Get-RecordName "GET $Path").body"
    if (-not (Test-Path $file)) { throw "not in the recordings: GET $Path" }
    return [string[]]@(Get-Content $file -Raw | ConvertFrom-Json)
}
function Get-Live([string]$Path) {
    return [string[]]@(& $Curl -sS --fail "$serverUrl$Path" | ConvertFrom-Json)
}

$cases = @()
function Test-Case([string]$What, [string]$Path, [string[]]$Expected, [switch]$AsSet) {
    $actual = Get-Live $Path
    $e = $Expected; $a = $actual
    if ($AsSet) { $e = @($e | Sort-Object); $a = @($a | Sort-Object) }
    $ok = ($e -join "`n") -ceq ($a -join "`n")
    $script:cases += [pscustomobject]@{ Ok = $ok; What = $What; Path = $Path; Expected = ($Expected -join ','); Actual = ($actual -join ',') }
}

$serilog = Get-Recorded '/api/v2/package-versions/Serilog'
Test-Case 'added version appears' '/api/v2/package-versions/Serilog' ($serilog + '9.9.9') -AsSet
$console = Get-Recorded '/api/v2/package-versions/Serilog.Sinks.Console'
if ($console -cnotcontains $unlisted) { throw "the unlisted version $unlisted was not in the recording" }
Test-Case 'unlisted version disappears' '/api/v2/package-versions/Serilog.Sinks.Console' @($console | Where-Object { $_ -cne $unlisted }) -AsSet
Test-Case 'new ID appears under its prefix' '/api/v2/package-ids?partialId=Serilog.Sinks' ((Get-Recorded '/api/v2/package-ids?partialId=Serilog.Sinks') + 'Serilog.Sinks.ZzHarness')
Test-Case 'new ID has its version' '/api/v2/package-versions/Serilog.Sinks.ZzHarness' @('1.0.0')
Test-Case 'SemVer 2.0.0 prerelease ID hidden by default' '/api/v2/package-ids?partialId=Serilog' ((Get-Recorded '/api/v2/package-ids?partialId=Serilog') + 'Serilog.Sinks.ZzHarness')
Test-Case 'SemVer 2.0.0 prerelease ID hidden without semVerLevel' '/api/v2/package-ids?partialId=Serilog&includePrerelease=true' ((Get-Recorded '/api/v2/package-ids?partialId=Serilog&includePrerelease=true') + 'Serilog.Sinks.ZzHarness')
Test-Case 'SemVer 2.0.0 prerelease ID shown when both are asked for' '/api/v2/package-ids?partialId=Serilog&includePrerelease=true&semVerLevel=2.0.0' ((Get-Recorded '/api/v2/package-ids?partialId=Serilog&includePrerelease=true&semVerLevel=2.0.0') + 'Serilog.Sinks.ZzHarness' + 'Serilog.ZzHarness')
Test-Case 'SemVer 2.0.0 prerelease version hidden by default' '/api/v2/package-versions/Serilog.ZzHarness' @()
Test-Case 'SemVer 2.0.0 prerelease version shown when both are asked for' '/api/v2/package-versions/Serilog.ZzHarness?includePrerelease=true&semVerLevel=2.0.0' @('1.0.0-beta.1')

$cases | Format-Table Ok, What, Path, Expected, Actual -AutoSize -Wrap | Out-String -Width 250 | Write-Host
$failed = @($cases | Where-Object { -not $_.Ok }).Count
$ok = $failed -eq 0
$detail = "$($cases.Count - $failed)/$($cases.Count) responses changed as the data says (scripts/linux/mutate.sql)"
Write-Result 4 'the service answers from the database' $ok $detail
Write-Summary "- check 4: $(if ($ok) {'pass'} else {'FAIL'}) - $detail"
if (-not $ok) { throw "check 4: $failed responses did not change as the data says" }
