# Change the seeded state through the app so the reset check is not vacuous:
# push one extra real package that is not in the seed list.
param([string]$Id = 'Serilog.Sinks.Trace', [string]$Version = '4.0.0')
. "$PSScriptRoot\common.ps1"
$apiKey = Get-Content $ApiKeyFile -Raw
$file = Get-SeedPackage -Id $Id -Version $Version -CacheDir $env:RUNNER_TEMP
$code = Publish-Package -File $file -ApiKey $apiKey
if ($code -ne 201) { throw "push of $Id $Version returned $code" }
Write-Summary "- mutate: pushed extra package $Id $Version (not in the seed list)"
