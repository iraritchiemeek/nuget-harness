# Done-when check 5: responses after reset are byte-identical to responses before the change,
# and the change in between really did alter at least one response.
# Without -Changed (e.g. restoring the snapshot onto a fresh machine) only the byte comparison is made.
param([Parameter(Mandatory)] [string]$Before, [string]$Changed, [Parameter(Mandatory)] [string]$After,
      [int]$CheckNumber = 5, [string]$Name = 'reset is exact', [string]$OutName = 'check5-reset.txt')
. "$PSScriptRoot\common.ps1"
$checkDir = Join-Path $OutDir 'checks'
New-Item -ItemType Directory -Force -Path $checkDir | Out-Null
function Hash-Dir([string]$d) {
    $h = @{}
    Get-ChildItem $d -File | ForEach-Object { $h[$_.Name] = (Get-FileHash $_.FullName -Algorithm SHA256).Hash }
    return $h
}
$b = Hash-Dir $Before; $a = Hash-Dir $After; $c = if ($Changed) { Hash-Dir $Changed } else { @{} }
$names = @(@($b.Keys) + @($a.Keys) | Sort-Object -Unique)
$lines = @(); $diffAfter = 0; $diffChanged = 0
foreach ($n in $names) {
    $sameAfter = $b[$n] -and ($b[$n] -eq $a[$n])
    $sameChanged = (-not $Changed) -or ($b[$n] -eq $c[$n])
    if (-not $sameAfter) { $diffAfter++ }
    if (-not $sameChanged) { $diffChanged++ }
    $lines += "$(if ($sameAfter) {'IDENTICAL'} else {'DIFFERENT'})  $n  before=$($b[$n])  after-reset=$($a[$n])  after-change=$($c[$n])"
}
$lines = @("files: $($names.Count)", "changed by mutation: $diffChanged", "different after reset: $diffAfter") + $lines
$lines | Set-Content (Join-Path $checkDir $OutName) -Encoding utf8
$ok = ($diffAfter -eq 0) -and ($names.Count -gt 0) -and ((-not $Changed) -or ($diffChanged -gt 0))
$detail = "$($names.Count - $diffAfter)/$($names.Count) responses byte-identical after reset" + $(if ($Changed) { "; the mutation changed $diffChanged" } else { '' }) + " ($OutName)"
Write-Result $CheckNumber $Name $ok $detail
Write-Summary "- $Name`: $(if ($ok) {'pass'} else {'FAIL'}) - $detail"
if (-not $ok) { throw 'reset check failed' }
