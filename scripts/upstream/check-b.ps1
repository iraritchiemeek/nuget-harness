# Spec 03, PR B's extra check: the delete-symbols page on the running app, before and after the fix.
# Account `owner` pushes two versions of one package; account `stranger` owns nothing.
param([string]$Id = 'Serilog', [string]$Older = '4.1.0', [string]$Latest = '4.2.0', [string]$Missing = '9.9.9')
. "$PSScriptRoot/../runner/common.ps1"
. "$PSScriptRoot/session.ps1"

Register-TestAccount 'stranger'
Register-TestAccount 'owner'
foreach ($v in $Older, $Latest) {
    $code = Publish-Package -File (Get-SeedPackage -Id $Id -Version $v -CacheDir $env:RUNNER_TEMP) -ApiKey (Get-Content $ApiKeyFile -Raw)
    if ($code -ne 201) { throw "push of $Id $v returned $code" }
}

# The page names the version it would delete in the form field Packages[].
function Get-PageResult([string]$Username, [string]$Path) {
    $r = Invoke-Session $Username $Path
    $shown = [regex]::Match($r.Body, 'name="Packages\[\]" value="([^"]*)"')
    if ($shown.Success) { return "$($r.Status) $($shown.Groups[1].Value)" }
    return "$($r.Status)"
}
$showsOlder = "200 $Id|$Older"; $showsLatest = "200 $Id|$Latest"
$cases = @(
    @{ User = 'owner'; What = 'a version that exists'; Path = "/packages/$Id/$Older/DeleteSymbols"; Before = $showsOlder; After = $showsOlder },
    @{ User = 'owner'; What = 'no version'; Path = "/packages/$Id/DeleteSymbols"; Before = $showsLatest; After = $showsLatest },
    @{ User = 'owner'; What = 'a valid version that does not exist'; Path = "/packages/$Id/$Missing/DeleteSymbols"; Before = $showsLatest; After = '404' },
    @{ User = 'owner'; What = 'absoluteLatest'; Path = "/packages/$Id/absoluteLatest/DeleteSymbols"; Before = $showsLatest; After = $showsLatest },
    @{ User = 'owner'; What = 'ABSOLUTELATEST'; Path = "/packages/$Id/ABSOLUTELATEST/DeleteSymbols"; Before = $showsLatest; After = $showsLatest },
    @{ User = 'stranger'; What = 'a version that exists'; Path = "/packages/$Id/$Older/DeleteSymbols"; Before = '403'; After = '403' },
    @{ User = 'stranger'; What = 'a valid version that does not exist'; Path = "/packages/$Id/$Missing/DeleteSymbols"; Before = '403'; After = '404' }
)

function Get-AllResult {
    foreach ($u in 'owner', 'stranger') { Connect-Account $u }
    return @($cases | ForEach-Object { Get-PageResult $_.User $_.Path })
}
$before = Get-AllResult
& "$PSScriptRoot/rebuild-patched.ps1" -Patch (Join-Path $RepoRoot 'upstream/b-delete-symbols.patch')
$after = Get-AllResult

$bad = 0
$table = @('| Account | Request | Before | After | Result |', '|---|---|---|---|---|')
for ($i = 0; $i -lt $cases.Count; $i++) {
    $ok = $before[$i] -ceq $cases[$i].Before -and $after[$i] -ceq $cases[$i].After
    if (-not $ok) { $bad++ }
    $table += "| $($cases[$i].User) | $($cases[$i].What) (``$($cases[$i].Path)``) | $($before[$i] -replace '\|', ' ') | $($after[$i] -replace '\|', ' ') | $(if ($ok) { 'as expected' } else { 'NOT as expected' }) |"
}
Write-Utf8File (Join-Path $OutDir 'checks/spec03-b-pages.md') $table
Write-Summary (@('') + $table + @('') -join "`n")
if ($bad) { throw "$bad request(s) did not answer as the spec expects" }
