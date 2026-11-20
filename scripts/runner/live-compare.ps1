# Spec 02 check 6: send one request set to the old app and to the new service, which read the same
# live database, and require identical answers (compare.ps1). The old app's answers are the
# expected side. -Exclusions (the A1 file) applies to the committed request set, which holds the
# excluded requests; compare.ps1 refuses an exclusion that names no request in the set.
param([Parameter(Mandatory)] [string]$Requests, [Parameter(Mandatory)] [string]$Name,
      [string]$Exclusions, [string]$Service = 'http://localhost:5080')
. "$PSScriptRoot\common.ps1"
$dir = Join-Path $OutDir "live\$Name"
& "$PSScriptRoot\capture.ps1" -Requests $Requests -Dir "$dir\old-app"
& "$PSScriptRoot\capture.ps1" -Requests $Requests -Dir "$dir\new-service" -Server $Service
& "$PSScriptRoot\compare.ps1" -Before "$dir\old-app" -After "$dir\new-service" -Exclusions $Exclusions `
    -CheckNumber 6 -Name "live parity, $Name" -OutName "check6-$Name.txt"
