# Save the SQL the old app sent for the two read endpoints, read from LocalDB's plan cache after
# the recording passes. This reads the database server, not the app, and shows the exact queries
# Entity Framework 6 generated, including how StartsWith is escaped and what is ordered.
param([Parameter(Mandatory)] [string]$OutFile)
. "$PSScriptRoot\common.ps1"
$rows = Invoke-Sql @'
SELECT st.text AS text, qs.execution_count AS n
FROM sys.dm_exec_query_stats qs CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE st.text LIKE N'%PackageRegistrations%' AND st.text NOT LIKE N'%dm_exec_query_stats%'
ORDER BY st.text
'@ -Database NuGetGallery
$out = @()
foreach ($r in $rows) { $out += "-- executions: $($r.n)"; $out += $r.text; $out += '' }
Write-Utf8File $OutFile $out
Write-Host "saved $(@($rows).Count) distinct statements to $OutFile"
