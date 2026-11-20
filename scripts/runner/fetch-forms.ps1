# Spike helper: save the sign-up, sign-in pages so the seed script can be written against real markup.
. "$PSScriptRoot\common.ps1"
$d = Join-Path $OutDir 'forms'
New-Item -ItemType Directory -Force -Path $d | Out-Null
foreach ($p in '/users/account/LogOn', '/users/account/LogOnNuGetAccount', '/users/account/SignUp') {
    $f = Join-Path $d (($p -replace '[/]', '_') + '.html')
    $r = Invoke-Curl -Path $p -OutFile $f -Extra @('-L')
    Write-Host "$p -> $($r.Status)"
}
