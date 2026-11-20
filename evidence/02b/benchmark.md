# Spec 02b benchmark: the old app and the new service

Four runs of [`benchmark.yml`](../../.github/workflows/benchmark.yml) on `396c87d`, alternating which app goes first. Every number below comes from the runs' `benchmark` artifacts (`out/benchmark/results.json` and `machine.json`) and job summaries.

## What holds in all four runs

- **Throughput.** The new service answered more requests per second than the old app at every concurrency level. The smallest margin in any run was 4.1 times (run 1, concurrency 8).
- **Median and p95 latency.** The new service's p50 and p95 were lower than the old app's at every level.
- **Errors.** Neither app returned an error in any run.
- **Database reads.** Per execution, the new service's queries read fewer pages: prefix searches about 3.8 times fewer, package-versions about 22 times fewer, and most-downloaded about 30% fewer. The reads were the same in every run, to one decimal place.
- **Database CPU.** Per execution, the new service's queries used less CPU time for each of the three query types.

## What does not hold, so is not claimed

- **p99 latency.** In run 1 at concurrency 1, the new service's p99 (18.09 ms) was higher than the old app's (12.13 ms). In run 3 at concurrency 32, the two were close (219.97 against 223.21 ms). The tail is not consistently better.
- **How either app scales.** From concurrency 8 to 32, the new service's throughput rose in two runs and fell in two. The old app's fell slightly in all four. With 4 logical processors shared by k6, SQL Server and the app, this says more about the machine than about either app.
- **Absolute numbers.** The same app's throughput varied by up to 1.8 times between runs (the new service at concurrency 8: 1,681 to 3,056 requests/s). Each run used a different shared machine, with three different CPU models across the four runs. Only comparisons within one run, on one machine, are meaningful.

## Method

- **Machine.** One GitHub-hosted `windows-2022` runner per run: 4 logical processors, 16 GB. SQL Server 2019 LocalDB (15.0.4382.1, Express Edition). The CPU model of each run is with its table below.
- **Database.** Both apps read the same LocalDB database, restored from the state A seed snapshot (148 package IDs, every download count 0).
- **The apps.**
  - The old app: NuGetGallery at the pinned commit, unmodified, on IIS Express, as the harness runs it everywhere else.
  - The new service: the self-contained win-x64 build of `service/` on Kestrel, reading with the `reader` login (`db_datareader` only).
- **Load tool.** k6 v2.4.0, its download checked against a SHA-256 in the workflow. It runs on the same machine.
- **Request mix.** Taken from `recordings/requests.txt`: every GET request the old app answered 200 with JSON in state A. 1,000 slots are filled by cycling through each group, then shuffled with a fixed seed, so both apps get the same sequence:
  - prefix searches, 60% (104 distinct requests)
  - package-versions, 30% (199 distinct requests)
  - most-downloaded (a blank `partialId`), 10% (9 distinct requests)
- **Load.** Constant concurrency of 1, 8 and 32 virtual users. At each level there is a 10 s warm-up, which is discarded, then a 30 s measured run. One app runs all its levels, then the other. Runs 1 and 3 started with the old app; runs 2 and 4 with the new service.
- **Database cost.** This is measured apart from the timed runs, before each app's first level:
  1. Clear the plan cache.
  2. Send the 1,000-request mix once at concurrency 1.
  3. Read `sys.dm_exec_query_stats` for plans compiled in the NuGetGallery database, grouped by query type.

  Each request runs exactly one query of its type, so the script fails unless the executions are exactly 600, 300 and 100. They were in all four runs.

  CPU is the statement's worker time, which excludes compilation. Because it is measured at concurrency 1, it shows each query's own cost, not its cost under contention.

## Like for like (spec 02b amendment B2)

| | Old app | New service |
|---|---|---|
| Transport | HTTPS on `localhost:443`, the certificate IIS Express is set up with | HTTPS on `localhost:5443`, a self-signed certificate made in the run |
| Certificate (read from each app's TLS handshake, every run) | `CN=localhost`, RSA 2048-bit key, sha256RSA | `CN=localhost`, RSA 2048-bit key, sha256RSA |
| Negotiated by k6 (every request, every run) | HTTP/2 over TLS 1.3 | HTTP/2 over TLS 1.3 |
| Logging | IIS Express's console: a line when a request starts and one when its response is sent. The gallery's own Serilog logger has no sink in this setup: no console sink, and an empty Application Insights key. No IIS Express W3C log grew at its default path (`Documents\IISExpress\Logs`): the console log alone accounts for the 190 bytes per request. | ASP.NET Core's two request lines (`Microsoft.AspNetCore.Hosting.Diagnostics` at Information, one line each), and nothing else below Warning |
| Log written, every run | 1.96 lines, 190 bytes per request | 2.00 lines, 658 bytes per request |

The script fails if the two apps negotiate different HTTP or TLS versions.

## Caveats

- **Log volume.** Both apps write about two lines per request to a redirected console, but the new service's lines are longer: about 3.5 times the bytes. This works against the new service.
- **Debug build.** The old app is built the way its README says (`.\build.ps1`), whose default configuration is Debug, and its `Web.config` has `<compilation debug="true">`. The new service is a Release build. This favours the new service, by an amount not measured here. A Release build of the old app was not tried: the harness builds it one way everywhere, and the recordings were made from that build.
- **Web server.** The old app runs on IIS Express, a development server, on .NET Framework. Under full IIS in production it may behave differently. The harness runs it on IIS Express everywhere, and this benchmark measures it as the recordings were made.
- **Shared machine.** k6, SQL Server and the app under test share 4 logical processors, and the runner is a shared CI machine. That is why the report gives every run, with no averages, and claims only what all four runs agree on.
- **Small data.** The database is the seed snapshot: 148 IDs, and every download count is 0. Costs on a database the size of nuget.org's were not measured. The relative reads could differ there.
- **Database cost at concurrency 1.** Under load, CPU per execution rises for both apps. In the earlier runs' measurements that were intact, it roughly doubled from concurrency 1 to 8. The table shows each query's own cost.
- **No query plans were captured.** The reads show that the new queries read less. They do not show why. The spec's guess, the old app's `DISTINCT` over every column, is not tested here.

## The runs

### Run 1: [44689693749](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44689693749), old app first

Machine: AMD EPYC 7763 64-Core Processor, 4 logical processors, 16 GB, runner image win22 20261112.366.7.

| App | Concurrency | Requests/s | p50 ms | p95 ms | p99 ms | Errors |
|---|---|---|---|---|---|---|
| old app | 1 | 148.4 | 6.54 | 8.27 | 12.13 | 0 |
| old app | 8 | 413 | 17.05 | 31.25 | 31.32 | 0 |
| old app | 32 | 388.9 | 78.13 | 93.76 | 207.93 | 0 |
| new service | 1 | 661.7 | 0.84 | 1.87 | 18.09 | 0 |
| new service | 8 | 1681.2 | 4.6 | 8.3 | 9.95 | 0 |
| new service | 32 | 2368 | 10.97 | 17.89 | 28.27 | 0 |

### Run 2: [44689704828](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44689704828), new service first

Machine: INTEL(R) XEON(R) PLATINUM 8573C, 4 logical processors, 16 GB, runner image win22 20261116.370.1.

| App | Concurrency | Requests/s | p50 ms | p95 ms | p99 ms | Errors |
|---|---|---|---|---|---|---|
| old app | 1 | 154.2 | 5.03 | 18.39 | 25.23 | 0 |
| old app | 8 | 548.2 | 15.62 | 19.73 | 31.26 | 0 |
| old app | 32 | 541.6 | 59.77 | 66.08 | 74.08 | 0 |
| new service | 1 | 1060.7 | 0.81 | 1.46 | 1.7 | 0 |
| new service | 8 | 3038.1 | 2.15 | 4.6 | 6.9 | 0 |
| new service | 32 | 3552 | 8.76 | 13.59 | 16.28 | 0 |

### Run 3: [44689715248](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44689715248), old app first

Machine: AMD EPYC 9V74 80-Core Processor, 4 logical processors, 16 GB, runner image win22 20261112.366.7.

| App | Concurrency | Requests/s | p50 ms | p95 ms | p99 ms | Errors |
|---|---|---|---|---|---|---|
| old app | 1 | 132.3 | 7.4 | 9.2 | 12.56 | 0 |
| old app | 8 | 420.2 | 15.64 | 31.25 | 31.34 | 0 |
| old app | 32 | 392.4 | 75.2 | 140.4 | 223.21 | 0 |
| new service | 1 | 829.2 | 0.79 | 1.77 | 10.84 | 0 |
| new service | 8 | 3055.9 | 2.3 | 5.1 | 6.45 | 0 |
| new service | 32 | 2335.2 | 12.09 | 17.04 | 219.97 | 0 |

### Run 4: [44689725788](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44689725788), new service first

Machine: AMD EPYC 7763 64-Core Processor, 4 logical processors, 16 GB, runner image win22 20261112.366.7.

| App | Concurrency | Requests/s | p50 ms | p95 ms | p99 ms | Errors |
|---|---|---|---|---|---|---|
| old app | 1 | 167.2 | 5.75 | 7.09 | 10.7 | 0 |
| old app | 8 | 440.9 | 17.37 | 25.92 | 31.25 | 0 |
| old app | 32 | 398.2 | 71.07 | 176.48 | 258.47 | 0 |
| new service | 1 | 996.5 | 0.82 | 1.67 | 2.21 | 0 |
| new service | 8 | 2839.2 | 2.44 | 5.58 | 7.15 | 0 |
| new service | 32 | 2345.3 | 10.75 | 17.65 | 44.31 | 0 |

### Database cost per execution

| Query type | App | Logical reads (every run) | CPU microseconds, runs 1 / 2 / 3 / 4 |
|---|---|---|---|
| prefix | old app | 603.4 | 577 / 397.6 / 610.3 / 510.6 |
| prefix | new service | 160.4 to 160.5 | 237.4 / 167.8 / 213.2 / 189.4 |
| versions | old app | 1665.6 | 944.1 / 702.1 / 978.9 / 880.5 |
| versions | new service | 76.4 | 115 / 89.9 / 106.5 / 94.4 |
| most-downloaded | old app | 1709.2 | 1091.8 / 831.4 / 1135.9 / 992.6 |
| most-downloaded | new service | 1200.2 | 992.4 / 657.1 / 870.5 / 823.8 |

## Earlier runs, not used

- **On `ea4e68b`:** runs [44686569195](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44686569195), [44686579215](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44686579215) and [44686589944](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44686589944). They are superseded for two reasons:
  - **Not like for like.** The new service ran over plain HTTP with logging at Warning (no request lines), while the old app ran over HTTPS.
  - **Database cost undercounted.** It was a before-and-after difference of `sys.dm_exec_query_stats` taken around each timed run. Under load, executions fell far short of the requests sent: 36 prefix executions for about 13,800 prefix requests in one case, and negative reads in another. The likely cause is plan-cache entries being replaced mid-run, but that was not investigated; the measurement was moved out of the timed runs instead.
- **On `75b9fe9`:** run [44688625322](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44688625322), the first like-for-like run. It measured everything, then failed the protocol check. Both apps had negotiated HTTP/2 over TLS 1.3, but k6 lists the counts in no fixed order, so the strings did not match. This was fixed in `396c87d`.
