# Wrapper used by run-task.ps1: runs a step script, captures all output to a log,
# and writes the exit code to a status file the Mac polls.
param([string]$Name, [string]$Script)
$root = 'C:\nuget-harness'
$log = "$root\logs\$Name.log"
$code = 1
try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script *>&1 |
        ForEach-Object { "[{0:u}] {1}" -f (Get-Date).ToUniversalTime(), $_ } |
        Out-File -FilePath $log -Append -Encoding utf8
    $code = $LASTEXITCODE
} catch {
    "[wrap] $_" | Out-File -FilePath $log -Append -Encoding utf8
}
Set-Content -Path "$root\status\$Name.exit" -Value $code -Encoding ascii
