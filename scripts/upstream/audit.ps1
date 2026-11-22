# Fail unless a build log holds exactly the known findings of NuGet's audit. upstream-fix.yml stops
# NU1903 (a high-severity finding, on any package) failing the restore, because the unpatched bases do
# not restore without that; this narrows it back to one advisory on one package version. A log with no
# finding fails too: the audit must have run. Any other audit code (NU1900 to NU1999) fails.
param([Parameter(Mandatory)] [string]$Log)
. "$PSScriptRoot/../runner/common.ps1"
$known = "NU1903 Package 'HtmlSanitizer' 9.0.892 has a known high severity vulnerability, https://github.com/advisories/GHSA-464h-4j8h-q5mf"

$findings = @(foreach ($line in Get-Content $Log) {
    $text = $line -replace '\x1b\[[0-9;]*m', ''
    # A finding is 'NU1903: ...' (NuGet writes it after WARNING:, MSBuild after warning or error). The
    # compiler's command line also names the code, as /warnaserror-:NU1903, with the colon in front.
    if ($text -cnotmatch '\b(NU19\d\d)\s*:\s*(.*)$') { continue }
    $code = $Matches[1]; $message = $Matches[2]
    if ($message -cmatch "^(Package '[^']+' \S+ has a known \w+ severity vulnerability, https://\S*?/GHSA(-[0-9a-z]{4}){3})(?![\w-])") { $message = $Matches[1] }
    "$code $message"
})
$distinct = @($findings | Sort-Object -Unique)
if ($distinct.Count -ne 1 -or $distinct[0] -cne $known) {
    throw "the NuGet audit did not report exactly the known advisory, but $($distinct.Count) finding(s): $($distinct -join '; ')"
}
Write-Summary "- NuGet audit of this build: exactly the known advisory, nothing else ($known)"
