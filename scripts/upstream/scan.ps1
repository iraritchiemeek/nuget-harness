# secret-scan.ps1 over out/ for every account a check made, because it knows one password and one
# API key at a time. Gates every upload of the app jobs.
. "$PSScriptRoot/../runner/common.ps1"
$accounts = @(Get-ChildItem (Join-Path $env:RUNNER_TEMP 'accounts') -Directory -ErrorAction SilentlyContinue)
foreach ($a in $accounts) {
    foreach ($file in $PasswordFile, $ApiKeyFile) { Copy-Item (Join-Path $a.FullName (Split-Path $file -Leaf)) $file -Force }
    & "$PSScriptRoot/../runner/secret-scan.ps1" -Dir $OutDir
}
if (-not $accounts.Count) { & "$PSScriptRoot/../runner/secret-scan.ps1" -Dir $OutDir }

# The session cookies of every account, by value.
$values = @($accounts | ForEach-Object { Join-Path $_.FullName 'cookies.txt' } | Where-Object { Test-Path $_ } | ForEach-Object { Get-Content $_ } |
    Where-Object { $_ -match '\t' } | ForEach-Object { ($_ -split "`t")[-1] } | Where-Object { $_.Length -ge 20 })
foreach ($file in Get-ChildItem $OutDir -Recurse -File) {
    $text = [IO.File]::ReadAllText($file.FullName)
    foreach ($v in $values) { if ($text.Contains($v)) { throw "a session cookie value is in $($file.Name)" } }
}
Write-Summary "- secret scan: $($accounts.Count) account(s), $($values.Count) cookie values, none found under out/"
