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

# On Windows, `curl` is an alias for Invoke-WebRequest, so name the real binary there.
$Script:Curl = if ([Environment]::OSVersion.Platform -eq 'Win32NT') { 'curl.exe' } else { 'curl' }

# curl wrapper: -k because the site uses a self-signed cert.
# Returns @{ Status = <int>; Body = <path> }.
function Invoke-Curl {
    param([string]$Path, [string]$OutFile, [string[]]$Extra = @())
    $url = if ($Path -match '^https?://') { $Path } else { "$BaseUrl$Path" }
    $code = & $Curl -sS -k --max-time 300 -o $OutFile -w '%{http_code}' @Extra $url
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

# The spec 01 check requests: package-ids for every prefix, package-versions for every seeded ID.
# Each item carries the check it belongs to (Kind) and the prefix or ID it asks about (Key).
function Get-CheckRequest {
    $expected = Get-Content (Join-Path $OutDir 'seed\expected.json') -Raw | ConvertFrom-Json
    foreach ($p in Get-PrefixList) {
        [pscustomobject]@{ Kind = 'ids'; Key = $p; Line = "GET /api/v2/package-ids?partialId=$([uri]::EscapeDataString($p))" }
    }
    foreach ($id in $expected.PSObject.Properties.Name) {
        [pscustomobject]@{ Kind = 'versions'; Key = $id; Line = "GET /api/v2/package-versions/$([uri]::EscapeDataString($id))" }
    }
}

# A record's file name: the first 16 hex digits of the SHA-256 of its request line, so names stay
# the same when requests are added or reordered.
function Get-RecordName([string]$Line) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Line)) } finally { $sha.Dispose() }
    return -join ($hash[0..7] | ForEach-Object { $_.ToString('x2') })
}

# A request line as sent: "<c*N>" stands for the character c repeated N times, so very long paths
# and query strings stay readable in a request file. Record names and reports use the line as written.
function Expand-RequestLine([string]$Line) {
    return [regex]::Replace($Line, '<(.)\*(\d+)>', { param($m) [string]::new($m.Groups[1].Value[0], [int]$m.Groups[2].Value) })
}

# Error pages that the web server writes, not the old app (spec 02 amendment A4): IIS's detailed
# error page, ASP.NET's error page for an HttpException, and http.sys's invalid-URL page. Their
# signatures were read from the recordings (exploratory record run 44674677772).
$Script:ServerErrorPageSignatures = @(
    @{ Name = "IIS's detailed error page"; Pattern = '<title>IIS 10\.0 Detailed Error - \d{3}\.\d+ - ' },
    @{ Name = "ASP.NET's error page"; Pattern = "(?s)Server Error in '/' Application.*\[HttpException \(0x[0-9A-Fa-f]{8}\): " },
    @{ Name = "http.sys's invalid-URL page"; Pattern = '<h2>Bad Request - Invalid URL</h2>' }
)

# Read the parity exclusions file (recordings/parity-exclusions.txt) and check every entry against
# the recorded side in -Recorded (the old app's records): each must name a recorded request, and
# must meet the condition of the amendment that allows its mode:
#   excluded     A1, and only for a method other than GET
#   status-only  A4, and only where the recorded body is a web-server error page: content type
#                text/html and one of $ServerErrorPageSignatures
# Returns a hashtable from record name to @{ Request; Mode; Reason }. Throws on any broken entry.
function Read-ParityExclusionFile([string]$File, [string]$Recorded) {
    $entries = @{}
    foreach ($line in Get-Content $File | Where-Object { $_.Trim() -and -not $_.StartsWith('#') }) {
        if ($line -notmatch '^(\S+ \S+)\s+(\S+)\s+((A\d+): \S.*)$') { throw "exclusion needs a request, a mode and a reason that starts with its amendment: $line" }
        $e = @{ Request = $Matches[1]; Mode = $Matches[2]; Reason = $Matches[3]; Amendment = $Matches[4] }
        $r = Get-RecordName $e.Request
        $meta = Join-Path $Recorded "$r.meta"
        if (-not (Test-Path $meta)) { throw "exclusion is not a recorded request: $($e.Request)" }
        if ($entries.ContainsKey($r)) { throw "exclusion listed twice: $($e.Request)" }
        switch -CaseSensitive ($e.Mode) {
            'excluded' {
                if ($e.Amendment -cne 'A1') { throw "mode excluded is allowed by amendment A1 only: $line" }
                if ($e.Request.StartsWith('GET ')) { throw "a GET request cannot be excluded: $line" }
            }
            'status-only' {
                if ($e.Amendment -cne 'A4') { throw "mode status-only is allowed by amendment A4 only: $line" }
                $html = @(Get-Content $meta | Where-Object { $_ -clike 'content-type: text/html*' }).Count -gt 0
                $text = [IO.File]::ReadAllText((Join-Path $Recorded "$r.body"))
                $page = @($ServerErrorPageSignatures | Where-Object { $text -cmatch $_.Pattern })
                if (-not $html -or -not $page) { throw "status-only needs a recorded web-server error page (text/html and a known signature): $line" }
            }
            default { throw "unknown exclusion mode '$($e.Mode)': $line" }
        }
        $entries[$r] = $e
    }
    return $entries
}

# The GitHub Release whose assets keep the database snapshots (get-snapshot.ps1), and an asset's
# name: the artifact name and the id of the run that made it, from that run's URL.
$Script:SnapshotRelease = 'snapshots-v1'
function Get-SnapshotAssetName([string]$Artifact, [string]$RunUrl) {
    if ($RunUrl -notmatch '/actions/runs/(\d+)$') { throw "not a run URL: $RunUrl" }
    return "$Artifact-$($Matches[1]).tar.gz"
}

# Write text as UTF-8 without a BOM and with LF line ends, so Windows PowerShell 5.1 and pwsh on
# Linux produce the same bytes.
function Write-Utf8File([string]$Path, [string[]]$Lines) {
    [IO.File]::WriteAllText($Path, (($Lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
}

# SHA-256 over every file under -Dir: one "<hash>  <relative path>" line per file, sorted ordinally,
# then hashed as UTF-8. Gives the same value on Windows and Linux for the same files.
function Get-FolderDigest([string]$Dir) {
    $root = (Resolve-Path $Dir).Path.TrimEnd('\', '/')
    $lines = [string[]]@(Get-ChildItem $root -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($root.Length + 1).Replace('\', '/')
        "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $rel"
    })
    [Array]::Sort($lines, [StringComparer]::Ordinal)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($lines -join "`n") + "`n")) } finally { $sha.Dispose() }
    return -join ($hash | ForEach-Object { $_.ToString('x2') })
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
