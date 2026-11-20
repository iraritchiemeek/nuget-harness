# Shared helpers for the runner scripts. Dot-source this file.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$Script:RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Script:GalleryDir = Join-Path $RepoRoot 'gallery'
$Script:SiteDir    = Join-Path $GalleryDir 'src\NuGetGallery'
$Script:OutDir     = Join-Path $RepoRoot 'out'
$Script:SiteName   = 'NuGet Gallery (localhost)'
$Script:BaseUrl    = 'https://localhost'
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
