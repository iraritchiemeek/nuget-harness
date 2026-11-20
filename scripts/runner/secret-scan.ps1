# Fail if a secret made in this job appears anywhere under the given folder, as ASCII/UTF-8 or as
# UTF-16LE (SQL Server stores nvarchar as UTF-16). Run before every upload. The secrets: the
# gallery's API key and account password (Windows jobs, files written by seed.ps1), and the SQL
# Server sa and reader passwords (Linux jobs, SA_PASSWORD and READER_PASSWORD in the environment).
# Prints only file names and which secret matched, never the secret.
param([Parameter(Mandatory)] [string]$Dir)
. "$PSScriptRoot\common.ps1"
$secrets = @{}
foreach ($s in @{ Name = 'apikey'; File = $ApiKeyFile }, @{ Name = 'password'; File = $PasswordFile }) {
    if (Test-Path $s.File) { $secrets[$s.Name] = (Get-Content $s.File -Raw).Trim() }
}
foreach ($name in 'SA_PASSWORD', 'READER_PASSWORD') {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ($value) { $secrets[$name] = $value }
}
if ($secrets.Count -eq 0) { Write-Host 'no secrets were created in this job; nothing to scan'; return }

Add-Type -TypeDefinition @"
public static class ByteSearch {
    public static bool Contains(byte[] hay, byte[] needle) {
        for (int i = 0; i <= hay.Length - needle.Length; i++) {
            int j = 0;
            while (j < needle.Length && hay[i + j] == needle[j]) j++;
            if (j == needle.Length) return true;
        }
        return false;
    }
}
"@

$needles = @()
foreach ($k in $secrets.Keys) {
    $needles += @{ Name = "$k (ascii)"; Bytes = [Text.Encoding]::ASCII.GetBytes($secrets[$k]) }
    $needles += @{ Name = "$k (utf-16le)"; Bytes = [Text.Encoding]::Unicode.GetBytes($secrets[$k]) }
}
$hits = @(); $n = 0
foreach ($file in Get-ChildItem $Dir -Recurse -File) {
    $n++
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    foreach ($nd in $needles) { if ([ByteSearch]::Contains($bytes, $nd.Bytes)) { $hits += "$($file.FullName): $($nd.Name)" } }
}
if ($hits.Count) { $hits | Write-Host; throw "secret found in $($hits.Count) place(s) under $Dir" }
Write-Summary "- secret scan: $n files under $Dir contain neither the API key nor the password (ascii or utf-16)"
