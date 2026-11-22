# Spec 03, PR A's extra check: every request in recordings/requests.txt, in both data states, from the
# unpatched app and then from the patched app (out\a\<state>-<build>). No record is excluded and only
# the approved difference 'package-versions in SemVer order' applies; at least one record must differ
# before the rule is applied. Then three planted faults must each fail the comparison, on exactly the
# planted records, for the planted reason.
param([Parameter(Mandatory)] [string]$SnapshotA, [Parameter(Mandatory)] [string]$SnapshotB)
. "$PSScriptRoot/../runner/common.ps1"
$runner = Join-Path $PSScriptRoot '../runner'
$dir = Join-Path $OutDir 'a'
$requests = Join-Path $RepoRoot 'recordings/requests.txt'
$approved = Join-Path $RepoRoot 'recordings/approved-differences.json'

function Save-Answer([string]$State, [string]$Snapshot, [string]$Build) {
    & "$runner/reset.ps1" -Dir $Snapshot
    & "$runner/capture.ps1" -Requests $requests -Dir (Join-Path $dir "$State-$Build")
}
function Invoke-Compare([string]$State, [string]$After, [string]$Case) {
    $before = Join-Path $dir "$State-unpatched"
    & "$runner/compare.ps1" -Before $before -Changed $After -After $After -ApprovedDifferences $approved `
        -CheckNumber 0 -Name "PR A, $Case" -OutName "spec03-a-$Case.txt"
}

Save-Answer 'state-a' $SnapshotA 'unpatched'
Save-Answer 'state-b' $SnapshotB 'unpatched'
& "$PSScriptRoot/rebuild-patched.ps1" -Patch (Join-Path $RepoRoot 'upstream/a-version-order.patch') -NoStart
Save-Answer 'state-a' $SnapshotA 'patched'
Save-Answer 'state-b' $SnapshotB 'patched'

$broken = @()
foreach ($state in 'state-a', 'state-b') {
    try { Invoke-Compare $state (Join-Path $dir "$state-patched") $state } catch { $broken += "${state}: $_" }
}
if ($broken.Count) { throw ($broken -join '; ') }

# ---- negative controls, on copies of the patched app's state A answers ---------------------------
$unpatched = Join-Path $dir 'state-a-unpatched'
$patched = Join-Path $dir 'state-a-patched'
$reordered = @(Get-ChildItem $patched -Filter *.body | Where-Object {
    (Get-FileHash $_.FullName).Hash -ne (Get-FileHash (Join-Path $unpatched $_.Name)).Hash } | ForEach-Object { $_.BaseName })
$newtonsoft = Get-RecordName 'GET /api/v2/package-versions/Newtonsoft.Json'
$dapper = Get-RecordName 'GET /api/v2/package-versions/Dapper'
function Edit-Body([string]$File, [string]$From, [string]$To) {
    $text = [IO.File]::ReadAllText($File)
    if (-not $text.Contains($From)) { throw "$File does not hold $From`: $text" }
    [IO.File]::WriteAllText($File, $text.Replace($From, $To), (New-Object Text.UTF8Encoding $false))
}
# Each case: the fault, the records it must be reported on, and a pattern every detail line must match.
$cases = @(
    @{ Case = 'unsorted'; Records = $reordered; Detail = '^    body (expected|actual)  \['
       Plant = { param($d) foreach ($r in $reordered) { Copy-Item (Join-Path $unpatched "$r.body") (Join-Path $d "$r.body") -Force } } },
    @{ Case = 'dropped'; Records = @($newtonsoft); Detail = '^    body (expected  \["5\.0\.7","8\.0\.3","13\.0\.4"\]|actual    \["8\.0\.3","13\.0\.4"\])$'
       Plant = { param($d) Edit-Body (Join-Path $d "$newtonsoft.body") '"5.0.7",' '' } },
    @{ Case = 'normalised'; Records = @($dapper); Detail = '^    body (expected  \[.*"1\.42".*\]|actual    \[.*"1\.42\.0".*\])$'
       Plant = { param($d) Edit-Body (Join-Path $d "$dapper.body") '"1.42"' '"1.42.0"' } }
)
$results = foreach ($c in $cases) {
    $copy = Join-Path $dir "control-$($c.Case)"
    Copy-Item $patched $copy -Recurse
    & $c.Plant $copy
    $failed = $false
    try { Invoke-Compare 'state-a' $copy "control-$($c.Case)" } catch { $failed = $true }
    $lines = Get-Content (Join-Path $OutDir "checks/spec03-a-control-$($c.Case).txt")
    $reported = @($lines | Where-Object { $_ -cmatch '^(DIFFERENT|MISSING) ' } | ForEach-Object { ($_ -split '\s+')[1] })
    $details = @($lines | Where-Object { $_.StartsWith('    ') })
    $ok = $failed -and $c.Records.Count -and -not (Compare-Object $reported $c.Records) -and
        -not @($lines | Where-Object { $_ -cmatch '^DIFFERENT ' -and $_ -cnotlike "*(after approved difference 'package-versions in SemVer order')" }).Count -and
        -not @($details | Where-Object { $_ -cnotmatch $c.Detail }).Count
    Write-Summary "- PR A control '$($c.Case)': planted on $($c.Records.Count) record(s); comparison failed: $failed; reported on $($reported.Count): $(if ($ok) { 'pass' } else { 'FAIL' })"
    $ok
}
if ($results -contains $false) { throw 'a planted fault was not reported as planted' }
