# Change the seeded state through the app. With no -List (spec 01 check 5, so the reset check is
# not vacuous): push one extra real package that is not in the seed list. With -List (spec 02
# check 6): push every "<Id> <version>" line of the file. Uses the API key a script earlier in
# the job made (seed.ps1 or push-state-b.ps1). Every push must answer 201.
param([string]$Id = 'Serilog.Sinks.Trace', [string]$Version = '4.0.0', [string]$List)
. "$PSScriptRoot\common.ps1"
$apiKey = Get-Content $ApiKeyFile -Raw
$entries = if ($List) {
    @(Get-Content $List | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object {
        $p = $_ -split '\s+'; [pscustomobject]@{ Id = $p[0]; Version = $p[1] }
    })
} else { @([pscustomobject]@{ Id = $Id; Version = $Version }) }
foreach ($e in $entries) {
    $file = Get-SeedPackage -Id $e.Id -Version $e.Version -CacheDir $env:RUNNER_TEMP
    $code = Publish-Package -File $file -ApiKey $apiKey
    if ($code -ne 201) { throw "push of $($e.Id) $($e.Version) returned $code" }
    Write-Summary "- extra push: pushed package $($e.Id) $($e.Version)"
}
