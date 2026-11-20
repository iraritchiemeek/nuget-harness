# Spec 02 check 6: send one request set to the old app and to the new service, which read the same
# live database, and require identical answers (compare.ps1). The old app's answers are the
# expected side. -Exclusions (recordings/parity-exclusions.txt) applies to the committed request
# set, which holds the listed requests; compare.ps1 refuses an entry that names no request in the set.
# The approved differences (recordings/approved-differences.json, spec 02b) apply to every request
# set, because each rule names the requests it covers by pattern.
param([Parameter(Mandatory)] [string]$Requests, [Parameter(Mandatory)] [string]$Name,
      [string]$Exclusions, [string]$Service = 'http://localhost:5080')
. "$PSScriptRoot\common.ps1"
$dir = Join-Path $OutDir "live\$Name"
& "$PSScriptRoot\capture.ps1" -Requests $Requests -Dir "$dir\old-app"
& "$PSScriptRoot\capture.ps1" -Requests $Requests -Dir "$dir\new-service" -Server $Service
& "$PSScriptRoot\compare.ps1" -Before "$dir\old-app" -After "$dir\new-service" -Exclusions $Exclusions `
    -ApprovedDifferences (Join-Path $RepoRoot 'recordings\approved-differences.json') `
    -CheckNumber 6 -Name "live parity, $Name" -OutName "spec02-check6-$Name.txt"
