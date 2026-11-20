# Compare two folders of records made by capture.ps1, record by record: the .meta file (status
# and compared headers) and the .body file, byte for byte. Every difference is listed in the
# report, with the differing header lines and the start of both bodies. A record that is on one
# side only is reported as MISSING.
# -Before is the expected side (for spec 02, the old app's recordings) and -After the actual side.
# With -Changed (spec 01 check 5) the change in between must also have altered at least one record,
# so that the comparison is not vacuous.
# -Exclusions names the parity exclusions file (recordings/parity-exclusions.txt), read and checked
# against -Before by Read-ParityExclusionFile in common.ps1. The report lists every entry, so none is silent.
#   excluded     (spec 02 amendment A1) left out of the comparison
#   status-only  (spec 02 amendment A4) only the status lines must match; the headers and body are
#                the web server's own error page and are not compared
# -ApprovedDifferences names the approved differences file (recordings/approved-differences.json,
# spec 02b), read by Read-ApprovedDifferenceFile in common.ps1. Where a rule applies to a record,
# the expected body is -Before's body after the rule's transform (Get-ApprovedBody), still compared
# byte for byte, and the .meta files must still be identical. The report names the rule for every
# record it applied to.
# The report is written to out/checks/<OutName>; OutName starts with the spec, as in spec02-check3-state-a.txt.
param([Parameter(Mandatory)] [string]$Before, [string]$Changed, [Parameter(Mandatory)] [string]$After,
      [Parameter(Mandatory)] [int]$CheckNumber, [Parameter(Mandatory)] [string]$Name,
      [Parameter(Mandatory)] [ValidatePattern('^spec\d\d[a-z]?-')] [string]$OutName, [string]$Exclusions,
      [string]$ApprovedDifferences)
. "$PSScriptRoot\common.ps1"
$checkDir = Join-Path $OutDir 'checks'
New-Item -ItemType Directory -Force -Path $checkDir | Out-Null

function Get-DirectoryHash([string]$Dir) {
    $h = @{}
    Get-ChildItem $Dir -File | Where-Object { $_.Extension -in '.meta', '.body' } |
        ForEach-Object { $h[$_.Name] = (Get-FileHash $_.FullName -Algorithm SHA256).Hash }
    return $h
}
function Test-SameRecord($x, $y, [string]$Record) {
    foreach ($ext in '.meta', '.body') {
        $k = "$Record$ext"
        if (-not $x.ContainsKey($k) -or -not $y.ContainsKey($k) -or $x[$k] -ne $y[$k]) { return $false }
    }
    return $true
}
# Show a body as text, with control characters escaped and long bodies cut.
function Format-Body([string]$Path) {
    if (-not (Test-Path $Path)) { return '(missing)' }
    return Format-Text ([IO.File]::ReadAllText($Path))
}
function Format-Text([string]$Text) {
    $text = [regex]::Replace($text, '[\x00-\x1f]', { param($m) '\x{0:x2}' -f [int][char]$m.Value })
    if ($text.Length -gt 400) { $text = $text.Substring(0, 400) + " ...($($text.Length) chars)" }
    return $text
}
function Read-Meta([string]$Path) { if (Test-Path $Path) { return @(Get-Content $Path) } else { return @() } }
# The status line of a record, or $null when the record or its status line is missing.
function Get-Status([string]$Dir, [string]$Record) {
    return Read-Meta (Join-Path $Dir "$Record.meta") | Where-Object { $_.StartsWith('status: ') } | Select-Object -First 1
}

$b = Get-DirectoryHash $Before; $a = Get-DirectoryHash $After
$c = if ($Changed) { Get-DirectoryHash $Changed } else { @{} }
$records = @(@($b.Keys) + @($a.Keys) | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) } | Sort-Object -Unique)
$report = @(); $differ = 0; $changedCount = 0

$excluded = @{}; $statusOnly = @{}
if ($Exclusions) {
    $entries = Read-ParityExclusionFile -File $Exclusions -Recorded $Before
    foreach ($r in $entries.Keys | Sort-Object) {
        $e = $entries[$r]
        if ($e.Mode -ceq 'excluded') { $excluded[$r] = $true; $report += "EXCLUDED   $r  $($e.Request)  ($($e.Reason))" }
        else { $statusOnly[$r] = $e.Request; $report += "STATUS-ONLY  $r  $($e.Request)  ($($e.Reason))" }
    }
}
$rules = @(); $approved = 0
if ($ApprovedDifferences) { $rules = @(Read-ApprovedDifferenceFile $ApprovedDifferences) }
foreach ($r in $records) {
    if ($excluded.ContainsKey($r)) { continue }
    if ($statusOnly.ContainsKey($r)) {
        $expected = Get-Status $Before $r; $actual = Get-Status $After $r
        if ($Changed -and (Get-Status $Changed $r) -ne $expected) { $changedCount++ }
        if ($expected -and $expected -ceq $actual) { continue }
        $differ++
        $report += "DIFFERENT  $r  $($statusOnly[$r])  (status only)"
        $report += "    meta expected  $expected"
        $report += "    meta actual    $actual"
        continue
    }
    if ($Changed -and -not (Test-SameRecord $b $c $r)) { $changedCount++ }
    $bm = @(Read-Meta (Join-Path $Before "$r.meta")); $am = @(Read-Meta (Join-Path $After "$r.meta"))
    $request = if ($bm.Count) { $bm[0] } elseif ($am.Count) { $am[0] } else { $r }
    $rule = if ($rules.Count) { Get-ApprovedDifference $rules $bm } else { $null }
    if ($rule -and $am.Count) {
        $approved++
        $report += "APPROVED   $r  $request  ($($rule.name))"
        $expectedText = $null
        try { $expectedBody = Get-ApprovedBody $rule (Join-Path $Before "$r.body") }
        catch { $expectedBody = $null; $expectedText = "(the rule cannot apply: $_)" }
        $actualBody = [IO.File]::ReadAllBytes((Join-Path $After "$r.body"))
        $sameBody = $null -ne $expectedBody -and [Convert]::ToBase64String($expectedBody) -ceq [Convert]::ToBase64String($actualBody)
        if ($sameBody -and $b["$r.meta"] -eq $a["$r.meta"]) { continue }
        $differ++
        $report += "DIFFERENT  $r  $request  (after approved difference '$($rule.name)')"
        foreach ($d in Compare-Object $bm $am -CaseSensitive) {
            $side = if ($d.SideIndicator -eq '<=') { 'expected' } else { 'actual  ' }
            $report += "    meta $side  $($d.InputObject)"
        }
        if (-not $sameBody) {
            if ($null -eq $expectedText) { $expectedText = Format-Text ([Text.Encoding]::UTF8.GetString($expectedBody)) }
            $report += "    body expected  $expectedText"
            $report += "    body actual    $(Format-Body (Join-Path $After "$r.body"))"
        }
        continue
    }
    if (Test-SameRecord $b $a $r) { continue }
    $differ++
    if (-not $am.Count -or -not $bm.Count) {
        $report += "MISSING    $r  $request  (only in $(if ($bm.Count) { 'the expected side' } else { 'the actual side' }))"
        continue
    }
    $report += "DIFFERENT  $r  $request"
    foreach ($d in Compare-Object $bm $am -CaseSensitive) {
        $side = if ($d.SideIndicator -eq '<=') { 'expected' } else { 'actual  ' }
        $report += "    meta $side  $($d.InputObject)"
    }
    if ($b["$r.body"] -ne $a["$r.body"]) {
        $report += "    body expected  $(Format-Body (Join-Path $Before "$r.body"))"
        $report += "    body actual    $(Format-Body (Join-Path $After "$r.body"))"
    }
}
$compared = $records.Count - $excluded.Count
$summary = @("records: $($records.Count)", "excluded: $($excluded.Count)", "status only: $($statusOnly.Count)", "by approved difference: $approved", "different: $differ")
if ($Changed) { $summary += "changed by the data change: $changedCount" }
@($summary + $report) | Set-Content (Join-Path $checkDir $OutName) -Encoding utf8
$report | Select-Object -First 60 | Write-Host

$ok = ($differ -eq 0) -and ($compared -gt 0) -and ((-not $Changed) -or ($changedCount -gt 0))
$detail = "$($compared - $differ)/$compared records identical" + $(if ($statusOnly.Count) { " ($($statusOnly.Count) by status only)" } else { '' }) + $(if ($approved) { ", $approved after an approved difference" } else { '' }) + $(if ($excluded.Count) { ", $($excluded.Count) excluded" } else { '' }) + $(if ($Changed) { "; the data change changed $changedCount" } else { '' }) + " ($OutName)"
Write-Result $CheckNumber $Name $ok $detail
Write-Summary "- $Name`: $(if ($ok) {'pass'} else {'FAIL'}) - $detail"
if (-not $ok) { throw "$Name`: failed" }
