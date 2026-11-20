# Seed the running gallery with no browser and no clicks:
#   1. register a user through the site's sign-up form (cookie session + antiforgery token scrape)
#   2. create a push API key through the site's API keys form
#   3. download every package in seed/packages.txt from nuget.org's flat container
#   4. push each one to the gallery's V2 push endpoint
# Writes out\seed\expected.json (IDs and versions read from each package's own nuspec) and
# out\seed\push-results.tsv. Secrets live only in $env:RUNNER_TEMP and are masked in the log.
param([string]$PackageCache = (Join-Path $env:RUNNER_TEMP 'seed-packages'))
. "$PSScriptRoot\common.ps1"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$seedOut = Join-Path $OutDir 'seed'
New-Item -ItemType Directory -Force -Path $seedOut, $PackageCache | Out-Null
$secretDir = Join-Path $env:RUNNER_TEMP 'secrets'
New-Item -ItemType Directory -Force -Path $secretDir | Out-Null
$jar = Join-Path $secretDir 'cookies.txt'
if (Test-Path $jar) { Remove-Item $jar }

function New-Secret([int]$Length) {
    $bytes = New-Object byte[] 64
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $s = ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '').Substring(0, $Length)
    return "Aa1$s"   # guarantees the upper/lower/digit classes the password regex wants
}

function Get-FormToken([string]$Html, [string]$FormMarker) {
    # Return the __RequestVerificationToken inside the first <form> whose text contains $FormMarker.
    foreach ($m in [regex]::Matches($Html, '(?s)<form\b.*?</form>')) {
        if ($m.Value -like "*$FormMarker*") {
            $t = [regex]::Match($m.Value, 'name="__RequestVerificationToken"[^>]*value="([^"]+)"')
            $a = [regex]::Match($m.Value, '<form[^>]*action="([^"]*)"')
            if ($t.Success) { return @{ Token = $t.Groups[1].Value; Action = [System.Net.WebUtility]::HtmlDecode($a.Groups[1].Value) } }
        }
    }
    throw "No form containing '$FormMarker' with an antiforgery token"
}

function Invoke-FormPost([string]$Url, [hashtable]$Fields, [string]$OutFile, [string[]]$Arrays = @()) {
    $pairs = @()
    foreach ($k in $Fields.Keys) { $pairs += "$([uri]::EscapeDataString($k))=$([uri]::EscapeDataString([string]$Fields[$k]))" }
    $pairs += $Arrays
    $bodyFile = Join-Path $secretDir 'body.txt'
    Set-Content -Path $bodyFile -Value ($pairs -join '&') -NoNewline -Encoding ascii
    $code = & curl.exe -sS -k -b $jar -c $jar -o $OutFile -D $hdrFile -w '%{http_code}' `
        -H 'Content-Type: application/x-www-form-urlencoded' --data-binary "@$bodyFile" "$BaseUrl$Url"
    Remove-Item $bodyFile
    Show-Headers "POST $Url"
    return [int]$code
}

$hdrFile = Join-Path $secretDir 'headers.txt'
# Log status, Location and the names (never values) of cookies set, for debugging the flow.
function Show-Headers([string]$What) {
    $h = Get-Content $hdrFile
    $loc = ($h | Where-Object { $_ -match '^Location:' }) -join ' '
    $cookies = ($h | Where-Object { $_ -match '^Set-Cookie:\s*([^=]+)=' } | ForEach-Object { ([regex]::Match($_, '^Set-Cookie:\s*([^=]+)=')).Groups[1].Value }) -join ','
    Write-Host "$What -> $($h[0]) $loc cookies-set=[$cookies]"
}

function Get-Page([string]$Path, [string]$OutFile) {
    $code = [int](& curl.exe -sS -k -b $jar -c $jar -o $OutFile -D $hdrFile -w '%{http_code}' "$BaseUrl$Path")
    Show-Headers "GET $Path"
    return $code
}

# ---- 1. register ----------------------------------------------------------------------------
$username = 'seeduser'
$email = 'seeduser@example.com'   # placeholder, not a real mailbox; the DB backup artifact is public
$password = New-Secret 24
Write-Host "::add-mask::$password"

$page = Join-Path $secretDir 'signup.html'
$code = Get-Page '/users/account/SignUp' $page
if ($code -ne 200) { throw "GET sign-up page returned $code" }
$form = Get-FormToken (Get-Content $page -Raw) 'Register.Username'
Write-Host "register form action: $($form.Action)"
$resp = Join-Path $secretDir 'register-response.html'
$code = Invoke-FormPost $form.Action @{
    '__RequestVerificationToken' = $form.Token
    'ReturnUrl' = '/'
    'LinkingAccount' = 'false'
    'Register.Username' = $username
    'Register.EmailAddress' = $email
    'Register.Password' = $password
} $resp
Write-Host "register POST -> $code"
if ($code -ne 302) {
    $errs = [regex]::Matches((Get-Content $resp -Raw), '(?s)class="[^"]*(field-validation-error|validation-summary-errors)[^"]*"[^>]*>(.*?)</') | ForEach-Object { $_.Groups[2].Value.Trim() }
    throw "Registration did not redirect (status $code). Validation messages: $($errs -join ' | ')"
}

# ---- 2. API key -----------------------------------------------------------------------------
# Follow the post-registration redirect like a browser would (the landing page consumes TempData).
$loc = (Get-Content $hdrFile | Where-Object { $_ -match '^Location:\s*(\S+)' } | ForEach-Object { $Matches[1] } | Select-Object -First 1)
Write-Host "register redirected to: $loc"
if ($loc -and $loc -match '/users/account/LogOn') { throw "Registration redirected to sign-in ($loc), so no session was created" }
$landing = if ($loc -and $loc.StartsWith('/')) { $loc } elseif ($loc) { ([uri]$loc).PathAndQuery } else { '/' }
[void](Get-Page $landing (Join-Path $secretDir 'landing.html'))
$page = Join-Path $secretDir 'apikeys.html'
# /account/apikeys redirects everyone to Trusted Publishing unless forceApiKeys=true, which is
# what the "API keys" link on the Trusted Publishing page sends.
$code = Get-Page '/account/apikeys?forceApiKeys=true' $page
if ($code -ne 200) { throw "GET /account/apikeys?forceApiKeys=true returned $code" }
$html = Get-Content $page -Raw
$form = Get-FormToken $html '__RequestVerificationToken'
$gen = [regex]::Match($html, '"GenerateUrl"\s*:\s*"([^"]+)"')
$generateUrl = if ($gen.Success) { $gen.Groups[1].Value -replace '\\u0026', '&' } else { '/account/GenerateApiKey' }
Write-Host "GenerateApiKey url: $generateUrl"
$resp = Join-Path $secretDir 'apikey-response.json'
$code = Invoke-FormPost $generateUrl @{
    '__RequestVerificationToken' = $form.Token
    'description' = 'seed'
    'owner' = $username
    # Not 365: with the ApiKeyReduction flag on (shipped flags.json), keys lasting over 30 days are
    # treated as expiring at 2026-11-01, so a 365-day key is born expired (run 7: every push got 403).
    'expirationInDays' = '8'
} $resp @('scopes=package%3Apush', 'scopes=package%3Apushversion', 'subjects=*')
Write-Host "GenerateApiKey POST -> $code"
if ($code -ne 200) { throw "GenerateApiKey returned ${code}: $((Get-Content $resp -Raw) -replace '[A-Za-z0-9]{40,}', '<redacted>')" }
$apiKey = (Get-Content $resp -Raw | ConvertFrom-Json).Value
if (-not $apiKey) { throw 'GenerateApiKey response had no Value' }
Write-Host "::add-mask::$apiKey"
Remove-Item $resp
# Kept for later steps of this job only (mutate.ps1). RUNNER_TEMP is never uploaded.
Set-Content -Path (Join-Path $env:RUNNER_TEMP 'apikey.txt') -Value $apiKey -NoNewline
Write-Summary "- seed: user registered through the sign-up form, API key created through the API keys form"

# ---- 3. download ----------------------------------------------------------------------------
$entries = Get-Content (Join-Path $RepoRoot 'seed\packages.txt') | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object {
    $p = $_.Trim() -split '\s+'
    [pscustomobject]@{ Id = $p[0]; Version = $p[1] }
}
Write-Host "seed list: $($entries.Count) package versions"
foreach ($e in $entries) {
    $low = $e.Id.ToLowerInvariant(); $v = $e.Version.ToLowerInvariant()
    $file = Join-Path $PackageCache "$low.$v.nupkg"
    $e | Add-Member File $file
    if (Test-Path $file) { continue }
    $url = "https://api.nuget.org/v3-flatcontainer/$low/$v/$low.$v.nupkg"
    $code = & curl.exe -sS -L --retry 3 -o $file -w '%{http_code}' $url
    if ($code -ne '200') { throw "download $url returned $code" }
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
    $code = & curl.exe -sS -k -o (Join-Path $secretDir 'push-response.txt') -w '%{http_code}' -X PUT `
        -H "X-NuGet-ApiKey: $apiKey" -H 'X-NuGet-Protocol-Version: 4.1.0' `
        -F "package=@$($e.File);type=application/octet-stream" "$BaseUrl/api/v2/package/"
    $t.Stop()
    $results += "$($e.Id)`t$($e.Version)`t$($ns.Id)`t$($ns.Version)`t$code`t$([math]::Round($t.Elapsed.TotalSeconds,2))"
    # Expected values come from the seed list and each nuspec, never from which pushes succeeded.
    $key = ($expected.Keys | Where-Object { $_ -ieq $ns.Id } | Select-Object -First 1)
    if (-not $key) { $key = $ns.Id; $expected[$key] = New-Object System.Collections.ArrayList }
    [void]$expected[$key].Add($ns.Version)
    if ($code -ne '201') {
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
