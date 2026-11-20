. "$PSScriptRoot\common.ps1"
Get-Process iisexpress -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Write-Host 'iisexpress stopped'
