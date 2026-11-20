# Spec 02 check 4: the service answers from the database, not from the recordings. Runs
# change-data.sql and ../download-counts.sql against the restored state A database as the administrator, then asks the service
# for the affected responses and checks each one against what the data now says: the state A
# recording plus exactly the change change-data.sql made.
# Versions are compared as sets, because the old app's version query has no ORDER BY; ID lists
# are compared in order (ORDER BY Id, or by download count for a blank partialId). The new IDs
# start with "Zz" after their prefix, so under the database collation they sort after every seeded
# ID with that prefix. Every response must be 200 with a JSON array; anything else fails its case.
param([Parameter(Mandatory)] [string]$Recorded, [string]$Server = 'http://localhost:5080')
. "$PSScriptRoot/../runner/common.ps1"
$recordedDir = $Recorded; $serverUrl = $Server

$out = @()
foreach ($file in "$PSScriptRoot/change-data.sql", "$PSScriptRoot/../download-counts.sql") {
    $name = Split-Path $file -Leaf
    & docker cp $file "nuget-sql:/tmp/$name"
    if ($LASTEXITCODE -ne 0) { throw "docker cp of $name failed" }
    $out += & "$PSScriptRoot/sqlcmd.sh" -d NuGetGallery -h -1 -W -s '|' -i "/tmp/$name"
    if ($LASTEXITCODE -ne 0) { throw "$name failed: $out" }
}
$unlisted = @($out | Where-Object { $_ -like 'unlisted|*' } | ForEach-Object { $_.Split('|')[1] })
if ($unlisted.Count -ne 1) { throw "expected one unlisted version, got: $out" }
$unlisted = $unlisted[0]
# The most-downloaded order, from the counts download-counts.sql set: highest first, then the cap of 30.
$downloads = @($out | Where-Object { $_ -like 'downloads|*' } | ForEach-Object {
    $f = $_.Split('|'); [pscustomobject]@{ Id = $f[1]; Downloads = [long]$f[2] }
})
if ($downloads.Count -ne 32 -or @($downloads | Select-Object -ExpandProperty Downloads -Unique).Count -ne 32) {
    throw "expected 32 distinct download counts, got: $($downloads | Out-String)"
}
$mostDownloaded = [string[]]@($downloads | Sort-Object Downloads -Descending | Select-Object -First 30 -ExpandProperty Id)
Write-Host "change-data.sql: added Serilog 9.9.9, Serilog.Sinks.ZzHarness 1.0.0, Serilog.ZzHarness 1.0.0-beta.1; unlisted Serilog.Sinks.Console $unlisted; set 32 distinct download counts"

function Get-Recorded([string]$Path) {
    $file = Join-Path $recordedDir "$(Get-RecordName "GET $Path").body"
    if (-not (Test-Path $file)) { throw "not in the recordings: GET $Path" }
    return [string[]]@(Get-Content $file -Raw | ConvertFrom-Json)
}

$cases = @()
function Test-Case([string]$What, [string]$Path, [string[]]$Expected, [switch]$AsSet) {
    $body = New-TemporaryFile
    try {
        $status = & $Curl -sS -o $body.FullName -w '%{http_code}' "$serverUrl$Path"
        $curlExit = $LASTEXITCODE
        $text = Get-Content $body.FullName -Raw
    } finally { Remove-Item $body.FullName -ErrorAction SilentlyContinue }
    if ($curlExit -ne 0 -or $status -ne '200') {
        $script:cases += [pscustomobject]@{ Ok = $false; What = $What; Path = $Path; Expected = ($Expected -join ','); Actual = "curl exit $curlExit, status $status" }
        return
    }
    $actual = [string[]]@($text | ConvertFrom-Json)
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
Test-Case 'blank partialId lists the 30 most-downloaded IDs, highest first' '/api/v2/package-ids?partialId=' $mostDownloaded
Test-Case 'missing partialId lists the 30 most-downloaded IDs, highest first' '/api/v2/package-ids' $mostDownloaded

$cases | Format-Table Ok, What, Path, Expected, Actual -AutoSize -Wrap | Out-String -Width 250 | Write-Host
$failed = @($cases | Where-Object { -not $_.Ok }).Count
$ok = $failed -eq 0
$detail = "$($cases.Count - $failed)/$($cases.Count) responses changed as the data says (scripts/linux/change-data.sql, scripts/download-counts.sql)"
Write-Result 4 'the service answers from the database' $ok $detail
Write-Summary "- check 4: $(if ($ok) {'pass'} else {'FAIL'}) - $detail"
if (-not $ok) { throw "check 4: $failed responses did not change as the data says" }
