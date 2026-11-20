# Render out\checks\results.tsv as the done-when table on the run's summary page.
# Checks 4 and 6 are recorded here from the outcomes of earlier steps.
param([string]$SeedOutcome, [string]$JobStatus)
. "$PSScriptRoot\common.ps1"
Write-Result 4 'seeding is scripted' ($SeedOutcome -eq 'success') "seed.ps1: register via form, API key via form, push over HTTP; step outcome: $SeedOutcome"
Write-Result 6 'rebuild needs no hands' ($JobStatus -eq 'success') "fresh windows-2022 runner, no manual step; job status before summary: $JobStatus"
$rows = Get-Content (Join-Path $OutDir 'checks\results.tsv') | ForEach-Object { $c = $_ -split "`t"; [pscustomobject]@{ N = [int]$c[0]; Name = $c[1]; R = $c[2]; D = $c[3] } } | Sort-Object N
Write-Summary ''
Write-Summary '| # | Done-when check | Result | Detail |'
Write-Summary '|---|---|---|---|'
foreach ($r in $rows) { Write-Summary "| $($r.N) | $($r.Name) | $($r.R) | $($r.D) |" }
foreach ($n in 1..7) { if (-not ($rows | Where-Object { $_.N -eq $n })) { Write-Summary "| $n | (not reached) | not reached | |" } }
