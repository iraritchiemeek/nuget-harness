# Start IIS Express in the background with the site Setup-DevEnvironment.ps1 registered,
# then poll until the app answers. The first request compiles views, so allow minutes.
param([int]$TimeoutSeconds = 600)
. "$PSScriptRoot\common.ps1"

$iisx = Join-Path (Get-IISExpressDir) 'iisexpress.exe'
$logDir = Join-Path $OutDir 'iisexpress'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$p = Start-Process -FilePath $iisx -ArgumentList "/site:`"$SiteName`"" -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $logDir 'stdout.log') -RedirectStandardError (Join-Path $logDir 'stderr.log')
Write-Host "iisexpress pid $($p.Id)"
$p.Id | Set-Content (Join-Path $OutDir 'iisexpress.pid')

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$probe = Join-Path $OutDir 'start-probe.txt'
while ((Get-Date) -lt $deadline) {
    if ($p.HasExited) { throw "iisexpress exited with code $($p.ExitCode)" }
    $r = Invoke-Curl -Path '/api/v2/package-ids?partialId=a' -OutFile $probe
    Write-Host "$(Get-Date -Format o) probe status $($r.Status)"
    if ($r.Status -eq 200) {
        Write-Summary "- start: app answered GET /api/v2/package-ids?partialId=a with 200: ``$(Get-Content $probe -Raw)``"
        return
    }
    Start-Sleep -Seconds 10
}
throw "App did not answer 200 within $TimeoutSeconds s"
