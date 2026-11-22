# Clean Release build of the checkout in gallery/ (which compiles the Razor views) and a run of
# NuGetGallery.Facts, with the commands of upstream's own CI. A failing test does not fail this
# script; compare-variants.ps1 judges the results. Writes to out\variant:
#   warnings.txt  the distinct warnings of the build, without paths and line numbers
#   tests.tsv     one line per test result: class.method, outcome, the display name and message of a failure
. "$PSScriptRoot/../runner/common.ps1"
$dir = Join-Path $OutDir 'variant'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$log = Join-Path $dir 'build.log'
Push-Location $GalleryDir
try {
    & pwsh -NoProfile -File .\build.ps1 -Configuration Release -SkipCommon -SkipJobs -SkipArtifacts *>&1 | Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0) { throw "build.ps1 exited $LASTEXITCODE" }
    $warnings = @(Get-Content $log | Where-Object { $_ -cmatch '\bwarning [A-Z]+\d*\s?:' } |
        ForEach-Object { ($_ -creplace '^.*?([^\\/(:]+)\(\d+(,\d+)*\): ', '$1: ' -creplace '\s*\[[^\]]*\]\s*$', '').Trim() } | Sort-Object -Unique)
    Write-Utf8File (Join-Path $dir 'warnings.txt') $warnings

    # upstream-fix.yml keeps NuGet's audit on but stops NU1903 failing the restore (see its env). The only
    # finding that may be let through is the one on the upstream base; any other is a failure here.
    $known = "Package 'HtmlSanitizer' 9.0.892 has a known high severity vulnerability, https://github.com/advisories/GHSA-464h-4j8h-q5mf"
    $audit = @(Get-Content $log | Where-Object { $_ -cmatch '\bNU19\d\d\b' } | ForEach-Object { $_ -creplace '^.*?Package ', 'Package ' -creplace '\s*\[[^\]]*\]\s*$', '' } | Sort-Object -Unique)
    if (Compare-Object $audit @($known)) { throw "the NuGet audit did not report exactly the known advisory: $($audit -join '; ')" }
    Write-Summary "- NuGet audit: exactly one advisory, the one on the unpatched base ($known)"

    $trx = Join-Path $env:RUNNER_TEMP 'facts.trx'
    & dotnet test tests\NuGetGallery.Facts\NuGetGallery.Facts.csproj --no-restore --no-build --configuration Release "-l:trx;LogFileName=$trx" | Select-Object -Last 15
    if (-not (Test-Path $trx)) { throw 'the test run wrote no result file' }
} finally { Pop-Location }

[xml]$x = Get-Content $trx -Raw
$methods = @{}
foreach ($u in $x.TestRun.TestDefinitions.UnitTest) { $methods[$u.id] = "$($u.TestMethod.className).$($u.TestMethod.name)" }
$lines = New-Object 'Collections.Generic.List[string]'
foreach ($r in $x.TestRun.Results.UnitTestResult) {
    # The arguments of a theory case can be part of the method name; the key is the method alone.
    $method = $methods[$r.testId] -replace '(?s)\(.*$', ''
    $message = if ($r.outcome -eq 'Failed') { $r.testName + ': ' + $r.Output.ErrorInfo.Message } else { '' }
    $lines.Add($method + "`t" + $r.outcome + "`t" + ($message -replace '\s+', ' '))
}
Write-Utf8File (Join-Path $dir 'tests.tsv') $lines
$c = $x.TestRun.ResultSummary.Counters
if ([int]$c.total -ne $lines.Count -or [int]$c.total -lt 10000) { throw "$($c.total) results in the summary, $($lines.Count) written" }
$global:LASTEXITCODE = 0   # failing tests are judged by compare-variants.ps1
Write-Summary "- Release build: ok, $($warnings.Count) distinct warnings; NuGetGallery.Facts: $($c.total) results, $($c.passed) passed, $($c.failed) failed"
