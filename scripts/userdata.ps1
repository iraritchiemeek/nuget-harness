<powershell>
# EC2 user-data (runs once at first boot as SYSTEM via EC2Launch v2).
# Turns on OpenSSH Server, installs the operator's ed25519 public key for Administrator,
# makes PowerShell the default SSH shell and opens TCP 22 in Windows Firewall.
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path C:\nuget-harness | Out-Null
Start-Transcript -Path C:\nuget-harness\userdata.log -Append

# 1. OpenSSH Server: Server 2025 ships it; install the capability only if the service is missing.
if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
}
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd   # first start generates host keys and %ProgramData%\ssh\sshd_config

# 2. Public key. EC2 refuses ED25519 key pairs on Windows AMIs ("ED25519 key pairs are not
#    supported with Windows AMIs"), so the instance launches without --key-name and IMDS has no
#    public-keys entry. provision.sh substitutes the ed25519 public key below before launch.
$key = '__SSH_PUBLIC_KEY__'
$akPath = 'C:\ProgramData\ssh\administrators_authorized_keys'
[System.IO.File]::WriteAllText($akPath, ($key.Trim() + "`n"), (New-Object System.Text.ASCIIEncoding))
icacls.exe $akPath /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F'

# 3. PowerShell as the default SSH shell.
New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell `
    -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force | Out-Null

# 4. Firewall: allow 22 inbound on every profile (the AWS security group limits the source IP).
if (-not (Get-NetFirewallRule -Name 'nuget-harness-sshd' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'nuget-harness-sshd' -DisplayName 'OpenSSH Server (nuget-harness)' `
        -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Profile Any | Out-Null
}

Restart-Service sshd
Get-Service sshd | Format-List Name, Status, StartType
Write-Output 'USERDATA-DONE'
Stop-Transcript
</powershell>
