# Create a gallery account with a push API key, with no browser and no clicks:
#   1. register the user through the site's sign-up form (cookie session + antiforgery token scrape)
#   2. create a push API key through the site's API keys form
# The password and the key are written to $PasswordFile and $ApiKeyFile in RUNNER_TEMP (never
# uploaded; secret-scan.ps1 reads them to prove neither reached an artifact) and masked in the log.
# -Email is a placeholder, not a real mailbox: database backups are published as artifacts.
param([Parameter(Mandatory)] [string]$Username, [Parameter(Mandatory)] [string]$Email)
. "$PSScriptRoot\common.ps1"
$secretDir = Join-Path $env:RUNNER_TEMP 'secrets'
New-Item -ItemType Directory -Force -Path $secretDir | Out-Null
$jar = Join-Path $secretDir 'cookies.txt'
if (Test-Path $jar) { Remove-Item $jar }

function Get-RandomSecret([int]$Length) {
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
    Show-ResponseHeader "POST $Url"
    return [int]$code
}

$hdrFile = Join-Path $secretDir 'headers.txt'
# Log status, Location and the names (never values) of cookies set, for debugging the flow.
function Show-ResponseHeader([string]$What) {
    $h = Get-Content $hdrFile
    $loc = ($h | Where-Object { $_ -match '^Location:' }) -join ' '
    $cookies = ($h | Where-Object { $_ -match '^Set-Cookie:\s*([^=]+)=' } | ForEach-Object { ([regex]::Match($_, '^Set-Cookie:\s*([^=]+)=')).Groups[1].Value }) -join ','
    Write-Host "$What -> $($h[0]) $loc cookies-set=[$cookies]"
}

function Get-Page([string]$Path, [string]$OutFile) {
    $code = [int](& curl.exe -sS -k -b $jar -c $jar -o $OutFile -D $hdrFile -w '%{http_code}' "$BaseUrl$Path")
    Show-ResponseHeader "GET $Path"
    return $code
}

# ---- 1. register ----------------------------------------------------------------------------
$password = Get-RandomSecret 24
Write-Host "::add-mask::$password"
# Kept in RUNNER_TEMP (never uploaded) only so secret-scan.ps1 can prove it is not in any artifact.
Set-Content -Path $PasswordFile -Value $password -NoNewline

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
    'Register.Username' = $Username
    'Register.EmailAddress' = $Email
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
    'description' = $Username
    'owner' = $Username
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
# Kept for later steps of this job only (the pushes). RUNNER_TEMP is never uploaded.
Set-Content -Path $ApiKeyFile -Value $apiKey -NoNewline
Remove-Item -Recurse -Force $secretDir
Write-Summary "- account ${Username}: registered through the sign-up form, API key created through the API keys form"
