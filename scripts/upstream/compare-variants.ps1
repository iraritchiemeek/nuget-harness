# Spec 03 checks 2 to 5 (and check 6 for -Pr all): compare the results test-variant.ps1 wrote for each
# variant with the unpatched base of the same run, against what upstream/fixes.json expects.
#   -Dir holds one folder per variant, test-results-<variant>.
param([Parameter(Mandatory)] [ValidateSet('a', 'b', 'c', 'all')] [string]$Pr, [Parameter(Mandatory)] [string]$Dir)
. "$PSScriptRoot/../runner/common.ps1"
$fixes = Get-Content (Join-Path $RepoRoot 'upstream/fixes.json') -Raw | ConvertFrom-Json
$selected = @(if ($Pr -eq 'all') { 'a', 'b', 'c' } else { $Pr }) | ForEach-Object { $fixes.$_ }
$added = @($selected | ForEach-Object { $_.addedTests })
$removed = @($selected | ForEach-Object { $_.removedTests })
$report = New-Object 'Collections.Generic.List[string]'
$problems = New-Object 'Collections.Generic.List[string]'

# class.method -> its results, each with Outcome and Detail
function Read-Result([string]$Variant) {
    $h = @{}
    foreach ($line in Get-Content (Join-Path $Dir "test-results-$Variant/tests.tsv")) {
        $f = $line -split "`t", 3
        if (-not $h.ContainsKey($f[0])) { $h[$f[0]] = @() }
        $h[$f[0]] += [pscustomobject]@{ Outcome = $f[1]; Detail = $f[2] }
    }
    return $h
}
function Get-Outcome($Results) { return (@($Results.Outcome) | Group-Object | Sort-Object Name | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', ' }
function Get-Match($Results, [string]$Pattern) { return @($Results.Keys | Where-Object { $_ -clike $Pattern }) }
function Get-Declared([string]$Test) { return @($added | Where-Object { $Test -clike $_.test }) }

$base = Read-Result 'base'
$baseFailed = @($base.Keys | Where-Object { $base[$_].Outcome -ccontains 'Failed' } | Sort-Object)
$report.Add("base: $($base.Count) test methods; failing methods: $($baseFailed.Count)")
foreach ($t in $baseFailed) { $report.Add("  already failing on the base: $t ($(Get-Outcome $base[$t]))") }

# Compare a variant with the base. Every method other than the added and removed ones must have the same
# results. Added methods must have the outcome -Expected says (a script block from the declaration).
function Compare-WithBase([string]$Variant, [scriptblock]$Expected) {
    $now = Read-Result $Variant
    $before = $problems.Count
    foreach ($t in @($base.Keys) + @($now.Keys) | Sort-Object -Unique) {
        $declared = @(Get-Declared $t)
        if ($declared.Count -and -not $base.ContainsKey($t)) {
            $want = & $Expected $declared[0]
            $bad = @($now[$t] | Where-Object { $_.Outcome -cne $want.Outcome -or ($want.Message -and $_.Detail -cnotmatch $want.Message) })
            $report.Add("${Variant}: new test $t -> $(Get-Outcome $now[$t]); $($now[$t][0].Detail)".TrimEnd('; '.ToCharArray()))
            if ($bad.Count) { $problems.Add("${Variant}: new test $t should be $($want.Outcome) $($want.Message)") }
            continue
        }
        if (-not $now.ContainsKey($t)) {
            $isRemoved = @($removed | Where-Object { $t -clike $_ }).Count -gt 0
            $report.Add("${Variant}: removed test $t")
            if (-not $isRemoved) { $problems.Add("${Variant}: $t is missing") }
            continue
        }
        if (-not $base.ContainsKey($t)) { $problems.Add("${Variant}: undeclared new test $t"); continue }
        if ((Get-Outcome $base[$t]) -cne (Get-Outcome $now[$t])) {
            $d = "${Variant}: $t was $(Get-Outcome $base[$t]), now $(Get-Outcome $now[$t]); $(@($now[$t] | Where-Object { $_.Detail } | ForEach-Object { $_.Detail })[0])"
            $report.Add($d); $problems.Add($d)
        }
    }
    foreach ($a in $added) {
        if (-not @(Get-Match $now $a.test).Count) { $problems.Add("${Variant}: new test $($a.test) did not run") }
    }
    Write-Summary "- $Variant against base: $(if ($problems.Count -eq $before) { 'as expected' } else { 'NOT as expected' }) ($($now.Count) test methods, $(@($now.Values | ForEach-Object { $_ }).Count) results)"
}

if ($Pr -ne 'all') {
    Compare-WithBase 'tests-only' { param($d) @{ Outcome = $d.withoutFix; Message = $(if ($d.PSObject.Properties.Name -ccontains 'message') { $d.message }) } }

    $wrong = Read-Result 'wrong-fix'
    foreach ($pattern in $selected[0].wrongFixFails) {
        $failed = @(Get-Match $wrong $pattern | Where-Object { $wrong[$_].Outcome -ccontains 'Failed' } | Sort-Object)
        $report.Add("wrong-fix: failing under ${pattern}: $($failed.Count)")
        foreach ($t in $failed) { $report.Add("  $t ($(Get-Outcome $wrong[$t])); $(@($wrong[$t] | Where-Object { $_.Detail } | ForEach-Object { $_.Detail })[0])") }
        if (-not $failed.Count) { $problems.Add("wrong-fix: no test failed under $pattern") }
    }
    Write-Summary "- wrong-fix: rejected by tests under $($selected[0].wrongFixFails -join ' and ')"
}
Compare-WithBase 'fix' { param($d) [void]$d; @{ Outcome = 'Passed'; Message = $null } }

$w0 = @(Get-Content (Join-Path $Dir 'test-results-base/warnings.txt') | Where-Object { $_ })
$w1 = @(Get-Content (Join-Path $Dir 'test-results-fix/warnings.txt') | Where-Object { $_ })
$newWarnings = @($w1 | Where-Object { $w0 -cnotcontains $_ })
$report.Add("Release build warnings: base $($w0.Count), fix $($w1.Count), new $($newWarnings.Count)")
foreach ($w in $newWarnings) { $problems.Add("new build warning: $w") }
Write-Summary "- Release build: $($w0.Count) distinct warnings on the base, $($newWarnings.Count) new with the fix"

New-Item -ItemType Directory -Force -Path (Join-Path $OutDir 'checks') | Out-Null
Write-Utf8File (Join-Path $OutDir "checks/spec03-$Pr-tests.txt") (@($report) + @($problems | ForEach-Object { "PROBLEM $_" }))
$report | Write-Host
if ($problems.Count) { $problems | ForEach-Object { Write-Host "PROBLEM $_" }; throw "$($problems.Count) unexpected result(s)" }
