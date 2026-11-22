# Negative controls of audit.ps1: logs with a planted finding, and one with none, must each fail it,
# and the two forms in which the known finding is written must pass.
. "$PSScriptRoot/../runner/common.ps1"
$known = "Package 'HtmlSanitizer' 9.0.892 has a known high severity vulnerability, https://github.com/advisories/GHSA-464h-4j8h-q5mf"
$compiler = 'csc.exe /noconfig /warnaserror+ /warnaserror-:NU1903'
$other = "Package 'Newtonsoft.Json' 12.0.1 has a known high severity vulnerability, https://github.com/advisories/GHSA-5crp-9r3c-p9vr"
$cases = @(
    @{ Name = 'the known finding, as NuGet writes it'; Lines = @($compiler, "WARNING: NU1903: $known", "WARNING: NU1903: $known"); Pass = $true }
    @{ Name = 'the known finding, as MSBuild writes it'; Lines = @($compiler, "C:\x\NuGetGallery.csproj : warning NU1903: $known [C:\x\NuGetGallery.sln]"); Pass = $true }
    @{ Name = 'no finding'; Lines = @($compiler, 'Build succeeded.'); Pass = $false }
    @{ Name = 'another package'; Lines = @("WARNING: NU1903: $known", "WARNING: NU1903: $other"); Pass = $false }
    @{ Name = 'only another package'; Lines = @("WARNING: NU1903: $other"); Pass = $false }
    @{ Name = 'another version of the same package'; Lines = @("WARNING: NU1903: $($known.Replace('9.0.892', '9.0.886'))"); Pass = $false }
    @{ Name = 'another advisory for the same package'; Lines = @("WARNING: NU1903: $known", "WARNING: NU1903: $($known.Replace('464h-4j8h', '464h-4j8j'))"); Pass = $false }
    @{ Name = 'another severity'; Lines = @("WARNING: NU1903: $known", "x.csproj : error NU1904: $($other.Replace('high', 'critical'))"); Pass = $false }
    @{ Name = 'the audit could not read its source'; Lines = @("WARNING: NU1903: $known", 'WARNING: NU1900: Error occurred while getting package vulnerability data'); Pass = $false }
)
$summary = $env:GITHUB_STEP_SUMMARY; $env:GITHUB_STEP_SUMMARY = ''   # the controls are not builds
$bad = 0
foreach ($c in $cases) {
    $log = Join-Path $env:RUNNER_TEMP 'audit-control.log'
    Set-Content $log $c.Lines -Encoding utf8
    $passed = $true
    try { & "$PSScriptRoot/audit.ps1" -Log $log } catch { $passed = $false; Write-Host "  $_" }
    if ($passed -ne $c.Pass) { $bad++ }
    Write-Host "audit control '$($c.Name)': passed $passed, expected $($c.Pass)"
}
$env:GITHUB_STEP_SUMMARY = $summary
if ($bad) { throw "$bad audit control(s) did not behave as expected" }
Write-Summary "- audit controls: $($cases.Count) of $($cases.Count) as expected ($(@($cases | Where-Object { -not $_.Pass }).Count) must fail the check)"
