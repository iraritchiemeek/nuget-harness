# Change the seeded state through the app so the reset check is not vacuous:
# push one extra real package that is not in the seed list.
param([string]$Id = 'Serilog.Sinks.Trace', [string]$Version = '4.0.0')
. "$PSScriptRoot\common.ps1"
$apiKey = Get-Content (Join-Path $env:RUNNER_TEMP 'apikey.txt') -Raw
$low = $Id.ToLowerInvariant()
$file = Join-Path $env:RUNNER_TEMP "$low.$Version.nupkg"
$code = & curl.exe -sS -L --retry 3 -o $file -w '%{http_code}' "https://api.nuget.org/v3-flatcontainer/$low/$Version/$low.$Version.nupkg"
if ($code -ne '200') { throw "download returned $code" }
$code = & curl.exe -sS -k -o NUL -w '%{http_code}' -X PUT -H "X-NuGet-ApiKey: $apiKey" -H 'X-NuGet-Protocol-Version: 4.1.0' `
    -F "package=@$file;type=application/octet-stream" "$BaseUrl/api/v2/package/"
if ($code -ne '201') { throw "push of $Id $Version returned $code" }
Write-Summary "- mutate: pushed extra package $Id $Version (not in the seed list)"
