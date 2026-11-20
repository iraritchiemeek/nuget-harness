# Start a server script detached from the SSH session, as SYSTEM, via a one-shot scheduled task.
# Long installs over SSH can be killed when the session drops, and SQL Server setup is unreliable
# under a key-auth network logon, so every long step goes through this.
# Usage: run-task.ps1 -Name install -Script C:\nuget-harness\server\install.ps1
# Output: C:\nuget-harness\logs\<Name>.log ; exit code in C:\nuget-harness\status\<Name>.exit
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Script
)
$ErrorActionPreference = 'Stop'
$root = 'C:\nuget-harness'
New-Item -ItemType Directory -Force -Path "$root\logs", "$root\status" | Out-Null
Remove-Item "$root\status\$Name.exit" -ErrorAction SilentlyContinue

$taskName = "nuget-harness-step-$Name"
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
$arg = "-NoProfile -ExecutionPolicy Bypass -File `"$root\server\wrap.ps1`" -Name $Name -Script `"$Script`""
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 6) -AllowStartIfOnBatteries
Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Output "started $taskName"
