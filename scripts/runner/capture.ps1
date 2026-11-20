# Send a request set to a server and store one record per request in -Dir:
#   <name>.meta   request line, status code, and the response headers that are compared
#   <name>.body   the response body, byte for byte
#   _index.tsv    name, method, path and status of every record, in request order
# <name> comes from Get-RecordName. -Requests is a file of "METHOD path" lines (# starts a
# comment); without it, the spec 01 check requests are sent. Headers listed in -IgnoredHeaders
# are left out of .meta, so they are never compared. Header names are lower-cased and sorted,
# because HTTP header names are case-insensitive and their order carries no meaning.
param(
    [Parameter(Mandatory)] [string]$Dir,
    [string]$Requests,
    [string]$Server,
    [string]$IgnoredHeaders = (Join-Path $PSScriptRoot '..\..\recordings\ignored-headers.txt')
)
. "$PSScriptRoot\common.ps1"
if (-not $Server) { $Server = $BaseUrl }
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$Dir = (Resolve-Path $Dir).Path

$lines = if ($Requests) {
    @(Get-Content $Requests | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
} else {
    @(Get-CheckRequest | ForEach-Object { $_.Line })
}
$ignored = @{}
if (Test-Path $IgnoredHeaders) {
    Get-Content $IgnoredHeaders | Where-Object { $_ -match '^\s*([A-Za-z0-9-]+)\s' } | ForEach-Object { $ignored[$Matches[1].ToLowerInvariant()] = $true }
}

$headerFile = Join-Path $Dir '_headers.tmp'
$index = @()
foreach ($line in $lines) {
    $method, $path = $line -split ' ', 2
    $name = Get-RecordName $line
    $body = Join-Path $Dir "$name.body"
    # --path-as-is and -g send the path exactly as written (no dot-segment squashing, no globbing).
    # POST and PUT carry an empty body and say so with Content-Length: 0, as an HTTP client would.
    # Without it, http.sys answers PUT with 411 Length Required before the app sees the request.
    $extra = @('--path-as-is', '-g', '-X', $method, '-D', $headerFile)
    if ($method -in 'POST', 'PUT') { $extra += @('-H', 'Content-Length: 0') }
    $r = Invoke-Curl -Path "$Server$path" -OutFile $body -Extra $extra
    if ($r.Status -eq 0) { throw "no HTTP response for $line from $Server" }
    if (-not (Test-Path $body)) { New-Item -ItemType File -Path $body | Out-Null }   # curl writes no file for an empty body

    # With interim responses (100 Continue) curl writes several header blocks; keep the last one.
    $block = @((Get-Content $headerFile -Raw) -split "`r?`n`r?`n" | Where-Object { $_.Trim() })[-1]
    $headers = [string[]]@($block -split "`r?`n" | Select-Object -Skip 1 | Where-Object { $_ -match '^([^:\s]+):\s?(.*)$' } | ForEach-Object {
        $n = $Matches[1].ToLowerInvariant()
        if (-not $ignored.ContainsKey($n)) { "${n}: $($Matches[2].TrimEnd())" }
    })
    [Array]::Sort($headers, [StringComparer]::Ordinal)   # ordinal, so Windows and Linux sort alike
    Write-Utf8File (Join-Path $Dir "$name.meta") (@($line, "status: $($r.Status)") + $headers)
    $index += "$name`t$method`t$path`t$($r.Status)"
}
Remove-Item $headerFile -ErrorAction SilentlyContinue
Write-Utf8File (Join-Path $Dir '_index.tsv') $index
Write-Host "captured $($lines.Count) responses from $Server into $Dir"
