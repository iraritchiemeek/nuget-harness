# Capture the response bodies of every check request into -Dir, one file per request.
# The same request set is used for the checks and for the reset comparison.
param([Parameter(Mandatory)] [string]$Dir)
. "$PSScriptRoot\common.ps1"
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$expected = Get-Content (Join-Path $OutDir 'seed\expected.json') -Raw | ConvertFrom-Json
$prefixes = Get-Prefixes
$status = @()
foreach ($p in $prefixes) {
    $r = Invoke-Curl -Path "/api/v2/package-ids?partialId=$([uri]::EscapeDataString($p))" -OutFile (Join-Path $Dir "ids_$p.json")
    $status += "ids`t$p`t$($r.Status)"
}
foreach ($id in $expected.PSObject.Properties.Name) {
    $r = Invoke-Curl -Path "/api/v2/package-versions/$([uri]::EscapeDataString($id))" -OutFile (Join-Path $Dir "versions_$id.json")
    $status += "versions`t$id`t$($r.Status)"
}
$status | Set-Content (Join-Path $Dir '_status.tsv') -Encoding utf8
Write-Host "captured $($status.Count) responses into $Dir"
