# Spec 02b benchmark: load the old app and the new service, one at a time, on the same machine and
# the same LocalDB database, with the same request mix, and measure them. Never fails on speed.
#   Mix       GET requests from recordings/requests.txt that the old app answered 200 with JSON in
#             state A, in three groups: prefix searches (60% of the mix), package-versions (30%)
#             and most-downloaded, a blank partialId (10%). 1,000 slots, filled by cycling through
#             each group, then shuffled with a fixed seed, so both apps get the same sequence.
#   Like for like (spec 02b amendment B2): both apps are called over HTTPS on localhost (-Service
#             must be an https URL), and k6 must negotiate the same HTTP and TLS versions with both,
#             or the script fails. The certificate each app presents and the log bytes each app
#             writes per request are recorded next to the numbers.
#   Load      k6 (-K6), constant concurrency at each of -Levels; a warm-up of -WarmUp, discarded,
#             then a measured run of -Duration.
#   Database  measured apart from the timed runs, because the plan cache drops entries under load
#             and a before-and-after difference of sys.dm_exec_query_stats then undercounts (the
#             first runs, on ea4e68b). For each app: clear the plan cache, send the whole mix once
#             at concurrency 1, and read the NuGetGallery database's query stats, grouped by query
#             type (the SQL text: LIKE for a prefix search, DownloadCount for most-downloaded,
#             [Version] for package-versions). Every request runs exactly one query of its type, so
#             the executions must be exactly 600, 300 and 100, or the script fails.
# Writes out/benchmark/results.json (every number), out/benchmark/machine.json and a summary table.
param([Parameter(Mandatory)] [string]$K6, [ValidateSet('old-app', 'new-service')] [string]$First = 'old-app',
      [int[]]$Levels = @(1, 8, 32), [string]$WarmUp = '10s', [string]$Duration = '30s',
      [string]$Service = 'https://localhost:5443')
. "$PSScriptRoot\common.ps1"
if (-not $Service.StartsWith('https://')) { throw "-Service must be an https URL, as the old app is: $Service" }
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

# The certificate an app presents: subject and key, so the report can show both apps use alike ones.
function Get-ServerCertificate([string]$Url) {
    $u = [uri]$Url
    $tcp = New-Object Net.Sockets.TcpClient($u.Host, $u.Port)
    try {
        $ssl = New-Object Net.Security.SslStream($tcp.GetStream(), $false, { $true })
        $ssl.AuthenticateAsClient($u.Host)
        $c = New-Object Security.Cryptography.X509Certificates.X509Certificate2 $ssl.RemoteCertificate
        $rsa = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($c)
        return "$($c.Subject), RSA $($rsa.KeySize)-bit key, $($c.SignatureAlgorithm.FriendlyName)"
    } finally { $tcp.Close() }
}

$apps = [ordered]@{ 'old-app' = $BaseUrl; 'new-service' = $Service }
# The files each app's process writes its logs to: IIS Express's console and its W3C request logs
# for the old app, the service's console for the new service. Read through an open handle, because
# a file's size in its directory entry lags while another process is appending to it.
$logFiles = @{
    'old-app'     = { @(Get-ChildItem (Join-Path $OutDir 'iisexpress') -Filter *.log -File) + @(Get-ChildItem (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'IISExpress\Logs') -Filter *.log -File -Recurse -ErrorAction SilentlyContinue) }
    'new-service' = { @(Get-Item (Join-Path $OutDir 'service.log')) }
}
function Get-LogByte([string]$App) {
    $total = 0L
    foreach ($file in & $logFiles[$App]) {
        $f = [IO.File]::Open($file.FullName, 'Open', 'Read', 'ReadWrite')
        try { $total += $f.Length } finally { $f.Dispose() }
    }
    return $total
}
$logStart = @{}; foreach ($app in $apps.Keys) { $logStart[$app] = Get-LogByte $app }

# Machine details.
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$machine = [ordered]@{
    runnerImage = "$env:ImageOS $env:ImageVersion"
    cpu = $cpu.Name.Trim(); logicalProcessors = [int]$cpu.NumberOfLogicalProcessors
    memoryGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    sqlServer = (Invoke-Sql "SELECT CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(100)) + N' ' + CAST(SERVERPROPERTY('Edition') AS nvarchar(100)) AS v")[0].v
    k6 = ((& $K6 version) | Out-String).Trim()
    certificates = [ordered]@{ 'old-app' = Get-ServerCertificate $BaseUrl; 'new-service' = Get-ServerCertificate $Service }
    mix = $mixSummary; first = $First; warmUp = $WarmUp; duration = $Duration
}

# The cost of each query type in the NuGetGallery database since the plan cache was last cleared:
# executions, logical reads and CPU (worker) time. Plans are keyed by the database they ran in.
function Get-QueryCost {
    $rows = Invoke-Sql "SELECT qs.execution_count AS n, qs.total_logical_reads AS reads, qs.total_worker_time AS cpu, st.text AS text
      FROM sys.dm_exec_query_stats qs CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
      CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) pa
      WHERE pa.attribute = N'dbid' AND CAST(pa.value AS int) = DB_ID(N'NuGetGallery')"
    $cost = [ordered]@{}
    foreach ($r in $rows) {
        $type = if ($r.text -match '\bLIKE\b') { 'prefix' } elseif ($r.text -match 'DownloadCount') { 'most-downloaded' } elseif ($r.text -match '\[Version\]') { 'versions' } else { 'other' }
        if (-not $cost.Contains($type)) { $cost[$type] = @{ N = 0L; Reads = 0L; Cpu = 0L } }
        $cost[$type].N += [long]$r.n; $cost[$type].Reads += [long]$r.reads; $cost[$type].Cpu += [long]$r.cpu
    }
    $db = [ordered]@{}
    foreach ($type in 'prefix', 'versions', 'most-downloaded', 'other') {
        if (-not $cost.Contains($type)) { continue }
        $c = $cost[$type]
        $db[$type] = [ordered]@{ executions = $c.N; logicalReadsPerExecution = [math]::Round($c.Reads / $c.N, 1); cpuMicrosecondsPerExecution = [math]::Round($c.Cpu / $c.N, 1) }
    }
    return $db
}

# Runs k6: -Vus users for -Length, or with -Iterations, the mix once through by one user.
function Invoke-K6([string]$BaseUrl, [int]$Vus, [string]$Length, [string]$Summary, [int]$Iterations = 0) {
    & $K6 run --quiet --no-color -e "MIX=$mixFile" -e "BASE_URL=$BaseUrl" -e "VUS=$Vus" -e "DURATION=$Length" -e "ITERATIONS=$Iterations" -e "SUMMARY=$Summary" $script | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "k6 exited with $LASTEXITCODE" }
    return (Get-Content $Summary -Raw | ConvertFrom-Json).metrics
}

# The HTTP and TLS versions of a k6 run's requests, from the per-protocol counts load.js asks for.
function Get-Protocol($Metrics) {
    $seen = @($Metrics.PSObject.Properties | Where-Object { $_.Name -match '^http_reqs\{(proto|tls_version):' -and $_.Value.values.count -gt 0 } |
        ForEach-Object { "$($_.Name -replace '^http_reqs\{\w+:(.*)\}$', '$1') ($($_.Value.values.count))" } | Sort-Object)
    return $seen -join ', '
}

$order = if ($First -eq 'old-app') { 'old-app', 'new-service' } else { 'new-service', 'old-app' }
$results = @(); $databaseCost = [ordered]@{}; $requestsSent = @{}
foreach ($app in $order) {
    Invoke-Sql 'DBCC FREEPROCCACHE WITH NO_INFOMSGS' | Out-Null
    $m = Invoke-K6 $apps[$app] 1 '' (Join-Path $dir "$app-database.json") $mix.Count
    $requestsSent[$app] = [long]$m.http_reqs.values.count
    $databaseCost[$app] = Get-QueryCost
    foreach ($type in $shares.Keys) {
        $n = if ($databaseCost[$app].Contains($type)) { $databaseCost[$app][$type].executions } else { 0 }
        if ($n -ne $shares[$type]) { throw "$app ran $n $type queries for the $($shares[$type]) $type requests in the mix; the database cost would be wrong" }
    }
    foreach ($vus in $Levels) {
        $m = Invoke-K6 $apps[$app] $vus $WarmUp (Join-Path $dir "$app-$vus-warmup.json")
        $requestsSent[$app] += [long]$m.http_reqs.values.count
        $m = Invoke-K6 $apps[$app] $vus $Duration (Join-Path $dir "$app-$vus.json")
        $requestsSent[$app] += [long]$m.http_reqs.values.count
        $results += [pscustomobject][ordered]@{
            app = $app; concurrency = $vus; requests = [long]$m.http_reqs.values.count
            requestsPerSecond = [math]::Round($m.http_reqs.values.rate, 1)
            p50ms = [math]::Round($m.http_req_duration.values.med, 2); p95ms = [math]::Round($m.http_req_duration.values.'p(95)', 2)
            p99ms = [math]::Round($m.http_req_duration.values.'p(99)', 2); errors = [long]$m.http_req_failed.values.passes
            protocol = Get-Protocol $m
        }
        Write-Host "$app at $vus`: $($results[-1].requestsPerSecond) requests/s, p50 $($results[-1].p50ms) ms, $($results[-1].errors) errors, $($results[-1].protocol)"
    }
}
$machine.logBytesPerRequest = [ordered]@{}
foreach ($app in $apps.Keys) { $machine.logBytesPerRequest[$app] = [math]::Round(((Get-LogByte $app) - $logStart[$app]) / $requestsSent[$app], 1) }
Write-Utf8File (Join-Path $dir 'machine.json') @($machine | ConvertTo-Json -Depth 3)
Write-Utf8File (Join-Path $dir 'results.json') @(ConvertTo-Json ([ordered]@{ load = @($results); database = $databaseCost }) -Depth 5)

$table = @('| App | Concurrency | Requests/s | p50 ms | p95 ms | p99 ms | Errors |', '|---|---|---|---|---|---|---|')
foreach ($r in $results) { $table += "| $($r.app) | $($r.concurrency) | $($r.requestsPerSecond) | $($r.p50ms) | $($r.p95ms) | $($r.p99ms) | $($r.errors) |" }
$table += '', '| App | Query type | Executions | Logical reads per execution | CPU us per execution |', '|---|---|---|---|---|'
foreach ($app in $order) { foreach ($type in $databaseCost[$app].Keys) { $c = $databaseCost[$app][$type]; $table += "| $app | $type | $($c.executions) | $($c.logicalReadsPerExecution) | $($c.cpuMicrosecondsPerExecution) |" } }
Write-Summary "### Benchmark ($($machine.cpu), $($machine.logicalProcessors) logical processors, $($machine.runnerImage); $First first)"
Write-Summary "Mix: $mixSummary. Warm-up $WarmUp, then $Duration per level. Database cost: the mix once at concurrency 1. A shared CI runner gives noisy numbers; the job never fails on speed."
Write-Summary "Certificates: old app $($machine.certificates.'old-app'); new service $($machine.certificates.'new-service'). Log bytes per request: old app $($machine.logBytesPerRequest.'old-app'), new service $($machine.logBytesPerRequest.'new-service')."
$table | ForEach-Object { Write-Summary $_ }

# Like for like: the same HTTP and TLS versions at every level, for both apps.
$protocols = @($results | ForEach-Object { $_.protocol -replace ' \(\d+\)', '' } | Sort-Object -Unique)
if ($protocols.Count -ne 1 -or ($protocols[0] -split ', ').Count -ne 2) { throw "the apps were not called with one HTTP and TLS version each: $($results.protocol -join '; ')" }
