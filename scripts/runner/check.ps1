# Done-when checks 1-3, evaluated against responses captured by capture.ps1 and the database.
# Writes out\checks\*.txt and a summary table. Exits non-zero if any check fails.
param([Parameter(Mandatory)] [string]$Dir)
. "$PSScriptRoot\common.ps1"
$checkDir = Join-Path $OutDir 'checks'
New-Item -ItemType Directory -Force -Path $checkDir | Out-Null
$expected = Get-Content (Join-Path $OutDir 'seed\expected.json') -Raw | ConvertFrom-Json
$ids = @($expected.PSObject.Properties.Name)
$prefixes = Get-Content (Join-Path $RepoRoot 'seed\prefixes.txt') | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object { $_.Trim() }
$statusOf = @{}
Get-Content (Join-Path $Dir '_status.tsv') | ForEach-Object { $c = $_ -split "`t"; $statusOf["$($c[0])|$($c[1])"] = [int]$c[2] }

function Read-JsonArray([string]$Path) { return @((Get-Content $Path -Raw | ConvertFrom-Json) | Where-Object { $_ -ne $null }) }
function Same-Set($a, $b) {
    $x = @($a | Sort-Object { $_.ToLowerInvariant() }) -join "`n"; $y = @($b | Sort-Object { $_.ToLowerInvariant() }) -join "`n"
    return ($x -ceq $y) -and (@($a).Count -eq @($b).Count)
}
$allPass = $true

# ---- check 1: package-ids by prefix -----------------------------------------------------------
$lines = @(); $fail1 = 0
foreach ($p in $prefixes) {
    $want = @($ids | Where-Object { $_.StartsWith($p, [StringComparison]::OrdinalIgnoreCase) })
    $got = @(Read-JsonArray (Join-Path $Dir "ids_$p.json"))
    $st = $statusOf["ids|$p"]
    $ok = ($st -eq 200) -and ($want.Count -ge 1) -and ($want.Count -lt 30) -and ($got.Count -gt 0) -and (Same-Set $got $want)
    if (-not $ok) { $fail1++ }
    $lines += "$(if ($ok) {'PASS'} else {'FAIL'})  partialId=$p  status=$st  expected=$($want.Count)  got=$($got.Count)"
    if (-not $ok) { $lines += "      expected: $($want -join ', ')"; $lines += "      got:      $($got -join ', ')" }
}
$lines | Set-Content (Join-Path $checkDir 'check1-package-ids.txt') -Encoding utf8
if ($fail1) { $allPass = $false }
$lines | Write-Host

# ---- check 2: package-versions per id ---------------------------------------------------------
$lines = @(); $fail2 = 0
foreach ($id in $ids) {
    $want = @($expected.$id)
    $got = @(Read-JsonArray (Join-Path $Dir "versions_$id.json"))
    $st = $statusOf["versions|$id"]
    $ok = ($st -eq 200) -and ($got.Count -gt 0) -and (Same-Set $got $want)
    if (-not $ok) { $fail2++ }
    $lines += "$(if ($ok) {'PASS'} else {'FAIL'})  $id  status=$st  expected=[$($want -join ', ')]  got=[$($got -join ', ')]"
}
$lines | Set-Content (Join-Path $checkDir 'check2-package-versions.txt') -Encoding utf8
if ($fail2) { $allPass = $false }
Write-Host "check 2: $($ids.Count - $fail2)/$($ids.Count) IDs match"

# ---- check 3: every pushed package is Available (0) and Listed in the database -----------------
$rows = Invoke-Sql @'
SELECT pr.Id AS Id, p.Version AS Version, p.PackageStatusKey AS Status, p.Listed AS Listed
FROM Packages p JOIN PackageRegistrations pr ON p.PackageRegistrationKey = pr.[Key]
ORDER BY pr.Id, p.Version
'@ -Database NuGetGallery
$wantCount = 0; foreach ($id in $ids) { $wantCount += @($expected.$id).Count }
$bad = @($rows | Where-Object { $_.Status -ne 0 -or -not $_.Listed })
$lines = @("packages in DB: $($rows.Count) (expected $wantCount)", "not Available+Listed: $($bad.Count)")
$lines += $rows | ForEach-Object { "$($_.Id)`t$($_.Version)`tstatus=$($_.Status)`tlisted=$($_.Listed)" }
$lines | Set-Content (Join-Path $checkDir 'check3-available-listed.txt') -Encoding utf8
$ok3 = ($rows.Count -eq $wantCount) -and ($bad.Count -eq 0)
if (-not $ok3) { $allPass = $false }

Write-Result 1 'package-ids by prefix' ($fail1 -eq 0) "$($prefixes.Count - $fail1)/$($prefixes.Count) prefixes return exactly the expected seeded IDs (check1-package-ids.txt)"
Write-Result 2 'package-versions' ($fail2 -eq 0) "$($ids.Count - $fail2)/$($ids.Count) IDs return exactly the pushed nuspec versions (check2-package-versions.txt)"
Write-Result 3 'pushed packages are live' $ok3 "$($rows.Count)/$wantCount packages in DB, $($bad.Count) not Available+Listed (check3-available-listed.txt)"
if (-not $allPass) { throw 'one or more checks failed' }
