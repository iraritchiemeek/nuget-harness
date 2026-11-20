# Spec 02b benchmark: load the old app and the new service, one at a time, on the same machine and
# the same LocalDB database, with the same request mix, and measure them. Never fails on speed.
#   Mix       GET requests from recordings/requests.txt that the old app answered 200 with JSON in
#             state A, in three groups: prefix searches (60% of the mix), package-versions (30%)
#             and most-downloaded, a blank partialId (10%). 1,000 slots, filled by cycling through
#             each group, then shuffled with a fixed seed, so both apps get the same sequence.
#   Load      k6 (-K6), constant concurrency at each of -Levels; a warm-up of -WarmUp, discarded,
#             then a measured run of -Duration.
#   Database  the plan cache is cleared before each warm-up; sys.dm_exec_query_stats is read before
#             and after each measured run, and the difference is grouped by query type (the SQL
#             text names the tables, LIKE for a prefix search, DownloadCount for most-downloaded).
# Writes out/benchmark/results.json (every number), out/benchmark/machine.json and a summary table.
param([Parameter(Mandatory)] [string]$K6, [ValidateSet('old-app', 'new-service')] [string]$First = 'old-app',
      [int[]]$Levels = @(1, 8, 32), [string]$WarmUp = '10s', [string]$Duration = '30s',
      [string]$Service = 'http://localhost:5080')
. "$PSScriptRoot\common.ps1"
$dir = Join-Path $OutDir 'benchmark'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$script = Join-Path $RepoRoot 'scripts\benchmark\load.js'

# The request mix.
$recorded = Join-Path $RepoRoot 'recordings\state-a'
$groups = @{ prefix = @(); versions = @(); 'most-downloaded' = @() }
foreach ($line in Get-Content (Join-Path $RepoRoot 'recordings\requests.txt') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }) {
    $meta = @(Get-Content (Join-Path $recorded "$(Get-RecordName $line).meta"))
    if (-not $line.StartsWith('GET ') -or $meta -cnotcontains 'status: 200' -or -not @($meta | Where-Object { $_ -clike 'content-type: application/json*' }).Count) { continue }
    $path = ((Expand-RequestLine $line) -split ' ', 2)[1]
    if ($path -match '(?i)^/api/v2/package-versions/') { $groups.versions += $path; continue }
    $partialId = if ($path -match '(?i)[?&]partialId=([^&]*)') { [uri]::UnescapeDataString($Matches[1].Replace('+', ' ')) } else { '' }
    if ($partialId.Trim()) { $groups.prefix += $path } else { $groups['most-downloaded'] += $path }
}
$shares = [ordered]@{ prefix = 600; versions = 300; 'most-downloaded' = 100 }
$mix = New-Object 'Collections.Generic.List[string]'
foreach ($g in $shares.Keys) { for ($i = 0; $i -lt $shares[$g]; $i++) { $mix.Add($groups[$g][$i % $groups[$g].Count]) } }
$random = New-Object Random 20261120
for ($i = $mix.Count - 1; $i -gt 0; $i--) { $j = $random.Next($i + 1); $t = $mix[$i]; $mix[$i] = $mix[$j]; $mix[$j] = $t }
$mixFile = Join-Path $dir 'mix.json'
Write-Utf8File $mixFile @(ConvertTo-Json @($mix) -Compress)
$mixSummary = @($shares.Keys | ForEach-Object { "$_ $($shares[$_] / 10)% ($($groups[$_].Count) distinct requests)" }) -join ', '

# Machine details.
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$machine = [ordered]@{
    runnerImage = "$env:ImageOS $env:ImageVersion"
    cpu = $cpu.Name.Trim(); logicalProcessors = [int]$cpu.NumberOfLogicalProcessors
    memoryGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    sqlServer = (Invoke-Sql "SELECT CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(100)) + N' ' + CAST(SERVERPROPERTY('Edition') AS nvarchar(100)) AS v")[0].v
    k6 = ((& $K6 version) | Out-String).Trim()
    mix = $mixSummary; first = $First; warmUp = $WarmUp; duration = $Duration
}
Write-Utf8File (Join-Path $dir 'machine.json') @($machine | ConvertTo-Json)

# The cost of the gallery queries so far, by query type: executions, logical reads, CPU (worker) time.
function Get-QueryCost {
    $rows = Invoke-Sql "SELECT CONVERT(varchar(130), qs.plan_handle, 1) + ':' + CAST(qs.statement_start_offset AS varchar(10)) AS k,
        qs.execution_count AS n, qs.total_logical_reads AS reads, qs.total_worker_time AS cpu, st.text AS text
      FROM sys.dm_exec_query_stats qs CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
      WHERE st.text LIKE N'%PackageRegistrations%' AND st.text NOT LIKE N'%dm_exec_query_stats%'"
    $cost = @{}
    foreach ($r in $rows) {
        $type = if ($r.text -match '\bLIKE\b') { 'prefix' } elseif ($r.text -match 'DownloadCount') { 'most-downloaded' } elseif ($r.text -match '\[Version\]') { 'versions' } else { 'other' }
        $cost[$r.k] = @{ Type = $type; N = [long]$r.n; Reads = [long]$r.reads; Cpu = [long]$r.cpu }
    }
    return $cost
}

function Invoke-K6([string]$BaseUrl, [int]$Vus, [string]$Length, [string]$Summary) {
    & $K6 run --quiet --no-color -e "MIX=$mixFile" -e "BASE_URL=$BaseUrl" -e "VUS=$Vus" -e "DURATION=$Length" -e "SUMMARY=$Summary" $script | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "k6 exited with $LASTEXITCODE" }
}

$apps = [ordered]@{ 'old-app' = $BaseUrl; 'new-service' = $Service }
$order = if ($First -eq 'old-app') { 'old-app', 'new-service' } else { 'new-service', 'old-app' }
$results = @()
foreach ($app in $order) {
    foreach ($vus in $Levels) {
        Invoke-Sql 'DBCC FREEPROCCACHE WITH NO_INFOMSGS' | Out-Null
        Invoke-K6 $apps[$app] $vus $WarmUp (Join-Path $dir "$app-$vus-warmup.json")
        $before = Get-QueryCost
        $summaryFile = Join-Path $dir "$app-$vus.json"
        Invoke-K6 $apps[$app] $vus $Duration $summaryFile
        $after = Get-QueryCost
        $db = [ordered]@{}
        foreach ($type in 'prefix', 'versions', 'most-downloaded', 'other') {
            $n = 0L; $reads = 0L; $cpu = 0L
            foreach ($k in $after.Keys | Where-Object { $after[$_].Type -eq $type }) {
                $was = if ($before.ContainsKey($k)) { $before[$k] } else { @{ N = 0L; Reads = 0L; Cpu = 0L } }
                $n += $after[$k].N - $was.N; $reads += $after[$k].Reads - $was.Reads; $cpu += $after[$k].Cpu - $was.Cpu
            }
            if ($n -gt 0) { $db[$type] = [ordered]@{ executions = $n; logicalReadsPerExecution = [math]::Round($reads / $n, 1); cpuMicrosecondsPerExecution = [math]::Round($cpu / $n, 1) } }
        }
        $m = (Get-Content $summaryFile -Raw | ConvertFrom-Json).metrics
        $results += [pscustomobject][ordered]@{
            app = $app; concurrency = $vus; requests = [long]$m.http_reqs.values.count
            requestsPerSecond = [math]::Round($m.http_reqs.values.rate, 1)
            p50ms = [math]::Round($m.http_req_duration.values.med, 2); p95ms = [math]::Round($m.http_req_duration.values.'p(95)', 2)
            p99ms = [math]::Round($m.http_req_duration.values.'p(99)', 2); errors = [long]$m.http_req_failed.values.passes
            database = $db
        }
        Write-Host "$app at $vus`: $($results[-1].requestsPerSecond) requests/s, p50 $($results[-1].p50ms) ms, $($results[-1].errors) errors"
    }
}
Write-Utf8File (Join-Path $dir 'results.json') @(ConvertTo-Json @($results) -Depth 5)

$table = @('| App | Concurrency | Requests/s | p50 ms | p95 ms | p99 ms | Errors | DB reads/exec (prefix, versions, most-downloaded) | DB CPU us/exec (same order) |', '|---|---|---|---|---|---|---|---|---|')
foreach ($r in $results) {
    $reads = @('prefix', 'versions', 'most-downloaded' | ForEach-Object { if ($r.database.Contains($_)) { $r.database[$_].logicalReadsPerExecution } else { '-' } }) -join ', '
    $cpuUs = @('prefix', 'versions', 'most-downloaded' | ForEach-Object { if ($r.database.Contains($_)) { $r.database[$_].cpuMicrosecondsPerExecution } else { '-' } }) -join ', '
    $table += "| $($r.app) | $($r.concurrency) | $($r.requestsPerSecond) | $($r.p50ms) | $($r.p95ms) | $($r.p99ms) | $($r.errors) | $reads | $cpuUs |"
}
Write-Summary "### Benchmark ($($machine.cpu), $($machine.logicalProcessors) logical processors, $($machine.runnerImage); $First first)"
Write-Summary "Mix: $mixSummary. Warm-up $WarmUp, then $Duration per level. A shared CI runner gives noisy numbers; the job never fails on speed."
$table | ForEach-Object { Write-Summary $_ }
