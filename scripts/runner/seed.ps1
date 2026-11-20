# Seed the running gallery with no browser and no clicks:
#   1-2. create the account `seeduser` with a push API key (new-account.ps1)
#   3. download every package in seed/packages.txt from nuget.org's flat container
#   4. push each one to the gallery's V2 push endpoint
# Writes out\seed\expected.json (IDs and versions read from each package's own nuspec) and
# out\seed\push-results.tsv. Secrets live only in $env:RUNNER_TEMP and are masked in the log.
param([string]$PackageCache = (Join-Path $env:RUNNER_TEMP 'seed-packages'))
. "$PSScriptRoot\common.ps1"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$seedOut = Join-Path $OutDir 'seed'
New-Item -ItemType Directory -Force -Path $seedOut, $PackageCache | Out-Null

# ---- 1-2. account and API key ---------------------------------------------------------------
& "$PSScriptRoot\new-account.ps1" -Username 'seeduser' -Email 'seeduser@example.com'
$apiKey = Get-Content $ApiKeyFile -Raw
$secretDir = Join-Path $env:RUNNER_TEMP 'secrets'
New-Item -ItemType Directory -Force -Path $secretDir | Out-Null

# ---- 3. download ----------------------------------------------------------------------------
$entries = Get-Content (Join-Path $RepoRoot 'seed\packages.txt') | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object {
    $p = $_.Trim() -split '\s+'
    [pscustomobject]@{ Id = $p[0]; Version = $p[1] }
}
Write-Host "seed list: $($entries.Count) package versions"
foreach ($e in $entries) {
    $e | Add-Member File (Get-SeedPackage -Id $e.Id -Version $e.Version -CacheDir $PackageCache)
}

# ---- 4. push --------------------------------------------------------------------------------
function Read-Nuspec([string]$Path) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -notmatch '/' -and $_.FullName -like '*.nuspec' } | Select-Object -First 1
        $reader = New-Object System.IO.StreamReader($entry.Open())
        try { [xml]$x = $reader.ReadToEnd() } finally { $reader.Close() }
        $md = $x.package.metadata
        return @{ Id = $md.id.Trim(); Version = $md.version.Trim() }
    } finally { $zip.Dispose() }
}

$results = @("id`tversion`tnuspecId`tnuspecVersion`tstatus`tseconds")
$expected = [ordered]@{}   # registration id (casing of first push) -> list of nuspec versions
$failures = 0
$sw = [Diagnostics.Stopwatch]::StartNew()
foreach ($e in $entries) {
    $ns = Read-Nuspec $e.File
    $t = [Diagnostics.Stopwatch]::StartNew()
    $code = Publish-Package -File $e.File -ApiKey $apiKey -ResponseFile (Join-Path $secretDir 'push-response.txt')
    $t.Stop()
    $results += "$($e.Id)`t$($e.Version)`t$($ns.Id)`t$($ns.Version)`t$code`t$([math]::Round($t.Elapsed.TotalSeconds,2))"
    # Expected values come from the seed list and each nuspec, never from which pushes succeeded.
    $key = ($expected.Keys | Where-Object { $_ -ieq $ns.Id } | Select-Object -First 1)
    if (-not $key) { $key = $ns.Id; $expected[$key] = New-Object System.Collections.ArrayList }
    [void]$expected[$key].Add($ns.Version)
    if ($code -ne 201) {
        $failures++
        $msg = (Get-Content (Join-Path $secretDir 'push-response.txt') -Raw -ErrorAction SilentlyContinue)
        Write-Host "::error::push $($e.Id) $($e.Version) -> $code $msg"
    }
}
$sw.Stop()
$results | Set-Content (Join-Path $seedOut 'push-results.tsv') -Encoding utf8
$expected | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $seedOut 'expected.json') -Encoding utf8
Remove-Item -Recurse -Force $secretDir

$ok = $entries.Count - $failures
Write-Summary "- seed: pushed $ok of $($entries.Count) package versions ($($expected.Count) IDs) in $([math]::Round($sw.Elapsed.TotalMinutes,1)) min"
if ($failures -gt 0) { throw "$failures pushes failed; see push-results.tsv" }
