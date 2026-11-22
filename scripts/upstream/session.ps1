# Accounts and signed-in requests for PR B's and PR C's checks of the running app. Dot-source after
# common.ps1. Everything that may hold a cookie, a token or a password stays under RUNNER_TEMP,
# which is never uploaded: pages are read there, and only statuses and named values reach out/.
$Script:AccountsDir = Join-Path $env:RUNNER_TEMP 'accounts'

# Register an account with new-account.ps1, and keep its password and API key apart, because
# new-account.ps1 overwrites them for the next account.
function Register-TestAccount([string]$Username) {
    & "$PSScriptRoot/../runner/new-account.ps1" -Username $Username -Email "$Username@example.com"
    $dir = Join-Path $AccountsDir $Username
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Copy-Item $PasswordFile, $ApiKeyFile $dir
}

# One request as a signed-in account: GET, or POST when -Fields is given. Returns status and body.
function Invoke-Session([string]$Username, [string]$Path, [hashtable]$Fields) {
    $dir = Join-Path $AccountsDir $Username
    $jar = Join-Path $dir 'cookies.txt'
    $page = Join-Path $dir 'page.html'
    if (Test-Path $page) { Remove-Item $page }
    $extra = @('-b', $jar, '-c', $jar)
    if ($Fields) {
        $form = Join-Path $dir 'form.txt'
        $pairs = foreach ($k in $Fields.Keys) { "$([uri]::EscapeDataString($k))=$([uri]::EscapeDataString([string]$Fields[$k]))" }
        Set-Content $form ($pairs -join '&') -NoNewline -Encoding ascii
        $extra += @('-H', 'Content-Type: application/x-www-form-urlencoded', '--data-binary', "@$form")
    }
    $r = Invoke-Curl -Path $Path -OutFile $page -Extra $extra
    if ($Fields) { Remove-Item $form }
    $body = if (Test-Path $page) { [IO.File]::ReadAllText($page) } else { '' }
    return [pscustomobject]@{ Status = $r.Status; Body = $body }
}

function Get-AntiforgeryToken([string]$Html) {
    $m = [regex]::Match($Html, 'name="__RequestVerificationToken"[^>]*value="([^"]+)"')
    if (-not $m.Success) { throw 'the page has no antiforgery token' }
    return $m.Groups[1].Value
}

# Sign in through the sign-in form, as a new session.
function Connect-Account([string]$Username) {
    $dir = Join-Path $AccountsDir $Username
    Remove-Item (Join-Path $dir 'cookies.txt') -ErrorAction SilentlyContinue
    New-Item -ItemType File -Path (Join-Path $dir 'cookies.txt') | Out-Null
    $page = Invoke-Session $Username '/users/account/LogOnNuGetAccount'
    if ($page.Status -ne 200) { throw "the sign-in page answered $($page.Status)" }
    $r = Invoke-Session $Username '/users/account/SignIn' @{
        '__RequestVerificationToken' = Get-AntiforgeryToken $page.Body
        'ReturnUrl' = '/'
        'LinkingAccount' = 'False'
        'SignIn.UserNameOrEmail' = $Username
        'SignIn.Password' = Get-Content (Join-Path $dir (Split-Path $PasswordFile -Leaf)) -Raw
    }
    if ($r.Status -ne 302) { throw "signing in as $Username answered $($r.Status)" }
    $check = Invoke-Session $Username '/account/apikeys?forceApiKeys=true'
    if ($check.Status -ne 200) { throw "after signing in as $Username, a page that needs a session answered $($check.Status)" }
    Write-Host "signed in as $Username"
}

# A short description of a developer error page: the exception line and the top app frames.
function Get-ExceptionText([string]$Html) {
    $text = [Net.WebUtility]::HtmlDecode(($Html -replace '<[^>]+>', ' '))
    $exception = [regex]::Match($text, '\[(\w+Exception[^\]]*)\]').Groups[1].Value -replace '\s+', ' '
    $frames = @([regex]::Matches($text, 'NuGetGallery\.[\w.<>`]+\([^)]*\)') | ForEach-Object { $_.Value -replace '\(.*$', '' } | Select-Object -Unique -First 4)
    return "$exception at $($frames -join ' < ')"
}
