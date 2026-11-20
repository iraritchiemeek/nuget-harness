# Start IIS Express in the background with the site Setup-DevEnvironment.ps1 registered,
# then poll until the app answers. The first request compiles views, so allow minutes.
param([int]$TimeoutSeconds = 600)
. "$PSScriptRoot\common.ps1"

$iisx = Join-Path (Get-IISExpressDir) 'iisexpress.exe'
$logDir = Join-Path $OutDir 'iisexpress'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
# The Actions runner kills processes a step leaves behind when the step ends (run 3: the app
# answered, then refused connections in the next step). Create IIS Express through WMI so it is
# not part of the step's process tree and outlives the step. Pass /config explicitly, because a
# WMI-created process does not get this step's environment.
$config = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'IISExpress\config\applicationhost.config'
if (-not (Test-Path $config)) { throw "applicationhost.config not found at $config" }
$cmdLine = "cmd.exe /c `"`"$iisx`" /config:`"$config`" /site:`"$SiteName`" > `"$logDir\stdout.log`" 2> `"$logDir\stderr.log`"`""
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmdLine }
if ($r.ReturnValue -ne 0) { throw "Win32_Process.Create returned $($r.ReturnValue)" }
Start-Sleep -Seconds 3
$p = Get-Process iisexpress -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { throw "iisexpress is not running after start. stdout: $(Get-Content $logDir\stdout.log -Raw -ErrorAction SilentlyContinue)" }
Write-Host "iisexpress pid $($p.Id)"

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$probe = Join-Path $OutDir 'start-probe.txt'
while ((Get-Date) -lt $deadline) {
    if (-not (Get-Process -Id $p.Id -ErrorAction SilentlyContinue)) { throw "iisexpress exited. stdout: $(Get-Content $logDir\stdout.log -Raw -ErrorAction SilentlyContinue)" }
    $r = Invoke-Curl -Path '/api/v2/package-ids?partialId=a' -OutFile $probe
    Write-Host "$(Get-Date -Format o) probe status $($r.Status)"
    if ($r.Status -eq 200) {
        Write-Summary "- start: app answered GET /api/v2/package-ids?partialId=a with 200: ``$(Get-Content $probe -Raw)``"
        break
    }
    Start-Sleep -Seconds 10
}
if ($r.Status -ne 200) { throw "App did not answer 200 within $TimeoutSeconds s" }

# For a while after it first answers, the app sends Cache-Control: No-Cache; after that, private
# (record run 44660814724: the first 36 responses of a pass that began straight after a start).
# The cause is not identified. IIS Express also starts the applicationInitialization requests from
# Web.config (/ and /api/health-probe) at that point. Wait for the steady state, so that every
# capture sees the app the same way, and fail if it does not arrive.
$headers = Join-Path $OutDir 'start-probe-headers.txt'
$sw = [Diagnostics.Stopwatch]::StartNew(); $probes = 0
do {
    $probes++
    $r = Invoke-Curl -Path '/api/v2/package-ids?partialId=a' -OutFile $probe -Extra @('-D', $headers)
    $cache = @(Get-Content $headers | Where-Object { $_ -match '^Cache-Control:\s*(.*)$' } | ForEach-Object { $Matches[1].Trim() })
    if ($r.Status -eq 200 -and $cache -notcontains 'No-Cache') { break }
    Start-Sleep -Milliseconds 500
} while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds)
if ($r.Status -ne 200 -or $cache -contains 'No-Cache') { throw "app still answering with Cache-Control: No-Cache after $probes probes" }
Write-Summary "- start: steady state (Cache-Control: $($cache -join ', ')) after $probes probes, $([math]::Round($sw.Elapsed.TotalSeconds, 1)) s"
