# Done-when check 5: responses after reset are byte-identical to responses before the change,
# and the change in between really did alter at least one response.
param([Parameter(Mandatory)] [string]$Before, [Parameter(Mandatory)] [string]$Changed, [Parameter(Mandatory)] [string]$After)
. "$PSScriptRoot\common.ps1"
$checkDir = Join-Path $OutDir 'checks'
New-Item -ItemType Directory -Force -Path $checkDir | Out-Null
function Hash-Dir([string]$d) {
    $h = @{}
    Get-ChildItem $d -File | ForEach-Object { $h[$_.Name] = (Get-FileHash $_.FullName -Algorithm SHA256).Hash }
    return $h
}
$b = Hash-Dir $Before; $c = Hash-Dir $Changed; $a = Hash-Dir $After
$names = @(@($b.Keys) + @($a.Keys) | Sort-Object -Unique)
$lines = @(); $diffAfter = 0; $diffChanged = 0
foreach ($n in $names) {
    $sameAfter = $b[$n] -and ($b[$n] -eq $a[$n])
    $sameChanged = $b[$n] -eq $c[$n]
    if (-not $sameAfter) { $diffAfter++ }
    if (-not $sameChanged) { $diffChanged++ }
    $lines += "$(if ($sameAfter) {'IDENTICAL'} else {'DIFFERENT'})  $n  before=$($b[$n])  after-reset=$($a[$n])  after-change=$($c[$n])"
}
$lines = @("files: $($names.Count)", "changed by mutation: $diffChanged", "different after reset: $diffAfter") + $lines
$lines | Set-Content (Join-Path $checkDir 'check5-reset.txt') -Encoding utf8
$ok = ($diffAfter -eq 0) -and ($diffChanged -gt 0) -and ($names.Count -gt 0)
Write-Result 5 'reset is exact' $ok "$($names.Count - $diffAfter)/$($names.Count) responses byte-identical after reset; the mutation changed $diffChanged (check5-reset.txt)"
if (-not $ok) { throw 'reset check failed' }
