# Compare two folders of records made by capture.ps1, record by record: the .meta file (status
# and compared headers) and the .body file, byte for byte. Every difference is listed in the
# report, with the differing header lines and the start of both bodies.
# -Before is the expected side (for spec 02, the old app's recordings) and -After the actual side.
# With -Changed (spec 01 check 5) the change in between must also have altered at least one record,
# so that the comparison is not vacuous.
# -Exclusions names a file of requests compared in part, one per line: the request line, the mode,
# then the reason. Each one must be a recorded request. The report lists them, so none is silent.
#   excluded     (spec 02 amendment A1) left out of the comparison. A GET cannot be excluded.
#   status-only  (spec 02 amendment A4) only the status lines must match; the headers and body are
#                the web server's own error page and are not compared.
param([Parameter(Mandatory)] [string]$Before, [string]$Changed, [Parameter(Mandatory)] [string]$After,
      [int]$CheckNumber = 5, [string]$Name = 'reset is exact', [string]$OutName = 'check5-reset.txt',
      [string]$Exclusions)
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
    $text = [IO.File]::ReadAllText($Path)
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
    foreach ($line in Get-Content $Exclusions | Where-Object { $_.Trim() -and -not $_.StartsWith('#') }) {
        if ($line -notmatch '^(\S+ \S+)\s+(\S+)\s+(\S.*)$') { throw "exclusion needs a request, a mode and a reason: $line" }
        $request = $Matches[1]; $mode = $Matches[2]; $reason = $Matches[3]
        $r = Get-RecordName $request
        if ($records -notcontains $r) { throw "exclusion is not a recorded request: $request" }
        switch -CaseSensitive ($mode) {
            'excluded' {
                if ($request.StartsWith('GET ')) { throw "a GET request cannot be excluded: $request" }
                $excluded[$r] = $true
                $report += "EXCLUDED   $r  $request  ($reason)"
            }
            'status-only' {
                $statusOnly[$r] = $request
                $report += "STATUS-ONLY  $r  $request  ($reason)"
            }
            default { throw "unknown exclusion mode '$mode': $line" }
        }
    }
}
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
    if (Test-SameRecord $b $a $r) { continue }
    $differ++
    $bm = Read-Meta (Join-Path $Before "$r.meta"); $am = Read-Meta (Join-Path $After "$r.meta")
    $request = if ($bm.Count) { $bm[0] } elseif ($am.Count) { $am[0] } else { $r }
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
$summary = @("records: $($records.Count)", "excluded: $($excluded.Count)", "status only: $($statusOnly.Count)", "different: $differ")
if ($Changed) { $summary += "changed by the mutation: $changedCount" }
@($summary + $report) | Set-Content (Join-Path $checkDir $OutName) -Encoding utf8
$report | Select-Object -First 60 | Write-Host

$ok = ($differ -eq 0) -and ($compared -gt 0) -and ((-not $Changed) -or ($changedCount -gt 0))
$detail = "$($compared - $differ)/$compared records identical" + $(if ($statusOnly.Count) { " ($($statusOnly.Count) by status only)" } else { '' }) + $(if ($excluded.Count) { ", $($excluded.Count) excluded" } else { '' }) + $(if ($Changed) { "; the mutation changed $changedCount" } else { '' }) + " ($OutName)"
Write-Result $CheckNumber $Name $ok $detail
Write-Summary "- $Name`: $(if ($ok) {'pass'} else {'FAIL'}) - $detail"
if (-not $ok) { throw "$Name`: failed" }
