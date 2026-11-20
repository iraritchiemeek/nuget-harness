# Shared helpers for the runner scripts. Dot-source this file.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$Script:RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Script:GalleryDir = Join-Path $RepoRoot 'gallery'
$Script:SiteDir    = Join-Path $GalleryDir 'src\NuGetGallery'
$Script:OutDir     = Join-Path $RepoRoot 'out'
$Script:SiteName   = 'NuGet Gallery (localhost)'
$Script:BaseUrl    = 'https://localhost'
$Script:Databases  = 'NuGetGallery', 'SupportRequest'
# Secrets made by seed.ps1. RUNNER_TEMP is never uploaded; secret-scan.ps1 reads these files to
# prove neither secret reached an artifact.
$Script:ApiKeyFile   = Join-Path $env:RUNNER_TEMP 'apikey.txt'
$Script:PasswordFile = Join-Path $env:RUNNER_TEMP 'password.txt'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Get-IISExpressDir {
    $ver = Get-ChildItem 'HKLM:\Software\Microsoft\IISExpress' |
        ForEach-Object { New-Object System.Version ($_.PSChildName) } |
        Sort-Object -Descending | Select-Object -First 1
    if (-not $ver) { throw 'IIS Express registry key not found' }
    return (Get-ItemProperty "HKLM:\Software\Microsoft\IISExpress\$ver").InstallPath
}

function Write-Summary([string]$Text) {
    if ($env:GITHUB_STEP_SUMMARY) { Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $Text -Encoding utf8 }
    Write-Host $Text
}

# curl.exe wrapper: -k because the site uses a self-signed cert.
# Returns @{ Status = <int>; Body = <path> }.
function Invoke-Curl {
    param([string]$Path, [string]$OutFile, [string[]]$Extra = @())
    $url = if ($Path -match '^https?://') { $Path } else { "$BaseUrl$Path" }
    $code = & curl.exe -sS -k --max-time 300 -o $OutFile -w '%{http_code}' @Extra $url
    return @{ Status = [int]$code; Body = $OutFile }
}

# Run a SQL query against LocalDB with System.Data.SqlClient (no dependency on sqlcmd).
# Returns an array of rows (each a hashtable keyed by column name).
function Invoke-Sql {
    param([string]$Query, [string]$Database = 'master', [int]$TimeoutSeconds = 600)
    $cs = "Data Source=(localdb)\MSSQLLocalDB;Initial Catalog=$Database;Integrated Security=True;Pooling=False"
    $conn = New-Object System.Data.SqlClient.SqlConnection $cs
    $conn.Open()
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $Query
        $cmd.CommandTimeout = $TimeoutSeconds
        $reader = $cmd.ExecuteReader()
        $rows = @()
        while ($reader.Read()) {
            $row = @{}
            for ($i = 0; $i -lt $reader.FieldCount; $i++) { $row[$reader.GetName($i)] = $reader.GetValue($i) }
            $rows += $row
        }
        $reader.Close()
        return ,$rows
    } finally { $conn.Close() }
}

# The prefixes for the package-ids check, from seed\prefixes.txt (comments and blanks skipped).
function Get-PrefixList {
    return @(Get-Content (Join-Path $RepoRoot 'seed\prefixes.txt') |
        Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object { $_.Trim() })
}

# Download one package from nuget.org's flat container into -CacheDir unless it is already there.
# Returns the .nupkg path.
function Get-SeedPackage {
    param([string]$Id, [string]$Version, [string]$CacheDir)
    $low = $Id.ToLowerInvariant(); $v = $Version.ToLowerInvariant()
    $file = Join-Path $CacheDir "$low.$v.nupkg"
    if (Test-Path $file) { return $file }
    $url = "https://api.nuget.org/v3-flatcontainer/$low/$v/$low.$v.nupkg"
    $code = & curl.exe -sS -L --retry 3 -o $file -w '%{http_code}' $url
    if ($code -ne '200') { throw "download $url returned $code" }
    return $file
}

# Push one .nupkg through the gallery's V2 push endpoint. Returns the HTTP status.
function Publish-Package {
    param([string]$File, [string]$ApiKey, [string]$ResponseFile = 'NUL')
    $code = & curl.exe -sS -k -o $ResponseFile -w '%{http_code}' -X PUT `
        -H "X-NuGet-ApiKey: $ApiKey" -H 'X-NuGet-Protocol-Version: 4.1.0' `
        -F "package=@$File;type=application/octet-stream" "$BaseUrl/api/v2/package/"
    return [int]$code
}

# Mirror one folder onto another with robocopy.
function Copy-Mirror {
    param([string]$From, [string]$To)
    & robocopy $From $To /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed with $LASTEXITCODE" }
    $global:LASTEXITCODE = 0   # robocopy uses 1-7 for success; do not let it become the step exit code
}

# Record one done-when result; summary.ps1 renders them as a table at the end of the run.
function Write-Result([int]$N, [string]$Name, [bool]$Pass, [string]$Detail) {
    $d = Join-Path $OutDir 'checks'
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    $r = if ($Pass) { 'pass' } else { 'FAIL' }
    Add-Content -Path (Join-Path $d 'results.tsv') -Value "$N`t$Name`t$r`t$Detail" -Encoding utf8
    Write-Host "check $N ($Name): $r - $Detail"
}
