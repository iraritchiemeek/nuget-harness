# Spec 02 run log

Times are UTC. Work by a Claude Code agent session (session 3 of the project), running from the operator Mac.

## 2026-11-20 (UTC): session 3

### Step 1: database spike. Result: pass

**Versions read, not guessed.**
- LocalDB on the `windows-2022` runner: `15.0.4382.1` (SQL Server 2019), from `diag/sqllocaldb-info.txt` in the `check-outputs` artifact of old-app run [44653627352](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44653627352).
- SQL Server image: `mcr.microsoft.com/mssql/server:2022-latest`, pinned as `@sha256:4525e3efac9f3e241cb003bb2ff2a82818b502f37e12049d788b1a9fa7e13b7f`. It reports `16.0.4325.4` (2022 RTM-CU28). 16 is newer than 15, so a LocalDB backup restores into it.

**Snapshot.** The `seed-snapshot` artifact of run 44653627352 (`NuGetGallery.bak`, `SupportRequest.bak`, `Files/`, `expected.json`). The artifact expires on 2027-02-18. After that date the snapshot has to be remade by an old-app run, and the recordings re-recorded against it.

**Mac (Apple M1 Pro, Docker, x64 image under emulation).**
- The image ran and answered under emulation.
- `RESTORE DATABASE ... WITH CHECKSUM, MOVE ...` succeeded. The engine upgraded the database from internal version 904 to 957, as it does for any 2019 backup restored into 2022.
- The restored database keeps compatibility level 150 (the 2019 level) and collation `SQL_Latin1_General_CP1_CI_AS`. Query semantics follow the compatibility level, not the engine version.
- 420 rows in `Packages`, 148 in `PackageRegistrations`, as spec 01 seeded.

**Linux runner.** New workflow `.github/workflows/new-service.yml`, job `restore-spike`, script `scripts/linux/sql-server.sh`.

| Run | Result | Wall time | What it showed | Change that followed |
|---|---|---|---|---|
| [1](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44658940554) | **pass** | 0:56 | Downloaded `seed-snapshot` from run 44653627352, started the pinned image, restored, and queried: version 16.0.4325.4, compatibility 150, collation `SQL_Latin1_General_CP1_CI_AS`, 420 packages. | |

### What the seeded data can and cannot show

Read from the restored database on the Mac:
- All 420 package rows are stable (`IsPrerelease = 0`) with `SemVerLevelKey = NULL`. No seeded version is prerelease or SemVer 2.0.0.
- No seeded ID contains `_` or `-`.
- Every `PackageRegistrations.DownloadCount` is 0.

Consequences for spec 02:
- The recordings send `includePrerelease` and `semVerLevel` in every combination (done-when 2), but against this snapshot the flags cannot change a response. The recordings therefore cannot tell apart a service that honours the flags from one that ignores them. The flags are made to matter elsewhere: the Linux mutation job (done-when 4) writes prerelease and SemVer 2.0.0 rows, and the Windows live-parity run (done-when 6) pushes such packages through the old app.
- `seed/packages.txt` and the pinned snapshot stay unchanged, because spec 01's evidence rests on them.

### Result order comes from the query plan

- `package-versions` has no `ORDER BY` in the old app (`AutocompleteDatabasePackageVersionsQuery.cs`). The recorded bodies are not in version order (for example `Serilog` gives `["1.4.128","1.3.30","4.4.0"]`).
- On the Mac container, a query of the same shape as the old app's (join, filters, no `ORDER BY`) gave byte-identical version lists for all 148 seeded IDs, compared against the old app's responses in run 44653627352's `check-outputs`.
- Spec 01's checks never tested order, because they compare sorted sets.
- The recording run's plan-cache dump (below) confirmed the shape of the old app's queries. On the Mac container, the blank-`partialId` query, a 148-way tie on `DownloadCount`, gave the same order as the recording.

### Step 2: harness cleanup (requested before spec 02 grew the workflows)

The AWS removal, the `gallery-build` composite action, shared helpers, and the `lint` workflow. Runs and results are in `evidence/01/run-log.md`, section "post-cleanup".

### Step 3: recording format and recording workflow

- **Format.** `capture.ps1` now stores one record per request: `<name>.meta` (request line, status, the compared headers lower-cased and sorted ordinally) and `<name>.body` (the bytes), plus `_index.tsv`. `<name>` is the first 16 hex digits of the SHA-256 of the request line. Spec 01's checks use the same records. `compare.ps1` compares record by record and lists every difference, with header lines and the start of both bodies.
- **Workflow.** `record.yml`, on `windows-2022`:
  1. restore `seed-snapshot` from run 44653627352
  2. send `recordings/requests.txt` twice; the passes must be byte-identical
  3. dump the old app's SQL from LocalDB's plan cache
  4. write `recordings/manifest.json` (run, app commit, snapshot digest, SHA-256 of every file)
  5. commit as `github-actions[bot]`
- **Guard.** `verify-recordings.ps1` runs first in every Linux job. It checks every hash in the manifest, the snapshot digest, and that the last commit touching the recordings was by `github-actions[bot]`. The author check is a tripwire, not proof: anyone with push access could set that author name. It needs a full-history checkout (`fetch-depth: 0`).

| Run | Workflow | Result | Wall time | What happened | Change that followed |
|---|---|---|---|---|---|
| [44660814724](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44660814724) | record | fail | 2:21 | The passes differed in 37 records. (1) The first 36 responses of pass 1, sent straight after the app started, had `Cache-Control: No-Cache`; every later response had `private`. (2) `X-SourceFiles`, an IIS Express header carrying the request's physical path on the runner, kept the casing of the first request that reached a path. | `start-site.ps1` waits until the probe stops getting `No-Cache`, with a bound. The cause is not identified. IIS Express starts the `applicationInitialization` requests from `Web.config` at the same moment, but nothing ties them to the header. `x-sourcefiles` added to `ignored-headers.txt`. |
| [44661804821](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44661804821) | record | **pass** | 2:15 | 262 requests, two byte-identical passes, committed by the bot. The plan-cache dump captured the exact SQL for both endpoints. | |
| [44662619447](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44662619447) | new-service | fail | 0:27 | `verify-recordings.ps1` caught 5 files whose hash differed from the manifest. The Windows checkout uses `core.autocrlf=true`, so the manifest hashed CRLF copies of the two input files, and committing normalised CRLF line ends in three HTML bodies. | `.gitattributes`: `recordings/** -text`; re-record. |
| [44662731013](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44662731013) | record | **pass** | 2:37 | The current recording: 262 records, passes byte-identical. Snapshot digest `e962712f…87e0`. | |
| [44663053674](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44663053674) | new-service | fail (expected, see blocker) | 1:48 | 527 recording files verified against the manifest, and the snapshot digest computed on Linux equals the Windows one. The restored database granted the service login `db_datareader` only. The service answered **259 of 262** records identically. The 3 that differ are the unsupported-method requests. | Stopped here: blocker below. |

Also on these commits: `lint` passed on every push, and `old-app` passed on every commit after `f75f577`.

**Request-set decisions** (each is written in `recordings/requests.txt`):
- Not sent: a blank `package-versions` id. The 500 body for a local client is a stack trace from the machine that built the gallery.
- Not sent: path characters that ASP.NET rejects before the app runs.
- Not sent: `/package-versions/Serilog/extra`. It matches neither route, so it is not the new service's to answer.
- POST and PUT send `Content-Length: 0`. Without it, http.sys answered PUT with 411 before the app saw it.

**Ignored headers** (`recordings/ignored-headers.txt`, each with its reason): `date`, `server`, `x-sourcefiles`, `content-length`, `transfer-encoding`. The headers still compared are `cache-control`, `content-type`, `strict-transport-security`, `x-content-type-options`, `x-frame-options`, plus anything else either side sends.

### Step 4: the service

`service/`: an ASP.NET Core minimal API on .NET 10 (SDK pinned in `global.json`, 10.0.400 band, `latestPatch`). Microsoft.Data.SqlClient, no ORM. Each copied rule cites its old-app source in a comment:
- The SQL repeats Entity Framework 6's generated SQL clause for clause, as read from the plan cache. The comparisons, the sort, and the order of unsorted results are left to SQL Server.
- `LikePattern`: escapes `%`, `_`, `[` and `~` with `~`, as EF6 does.
- `LegacyQuery`: takes the first value of a repeated key, and a `bool?` that does not parse binds null (MVC 5).
- `PackageFilter`: `semVerLevel` is parsed with NuGet.Versioning 6.13.2, the gallery's own version.
- `GalleryResponseHeaders`: the headers `Web.config` adds, and `Cache-Control: private`.
- The JSON encoder does not escape `+`.
- SqlClient refuses globalization-invariant mode, so the container base is `noble-chiseled-extra`, which carries ICU.

On the Mac (SQL Server 2022 container under emulation), the service matched 259 of 262 records on its first full comparison. This includes:
- repeated keys (`partialId=Serilog&partialId=Polly`)
- `includePrerelease=yes`
- trailing slashes
- `%2E`
- `Serilog%20`, which matches `Serilog` because SQL Server's `=` ignores trailing spaces
- the 30-ID cap
- the blank-prefix tie order

## Blocker: the old app's answer to an unsupported method

Spec 02 done-when 2 requires a request with an unsupported HTTP method. The recordings hold three: POST, DELETE and PUT to the two routes. For each, the old app answers `404` with `text/html`. The body is ASP.NET's "Server Error in '/' Application" page. It contains:
- the .NET Framework and ASP.NET versions (`4.0.30319`, `4.8.9344.0`)
- the `HttpException` stack trace inside an HTML comment

The routes accept any method (`Routes.cs`), so MVC finds no `[HttpGet]` action and calls `HandleUnknownAction`. Two settings shape the reply:
- `customErrors mode="RemoteOnly"` (Web.config) gives local clients the detailed page.
- `httpErrors errorMode="DetailedLocalOnly"` does the same at the IIS level.

**Every recording comes from a local client**, because the recorder runs on the same machine as IIS Express. So the error responses recorded are the old app's developer-detail variant, not what a remote client receives.

To match these three bodies byte for byte, the new service would have to embed ASP.NET's error page, the framework version strings, and the stack trace. Those come from the framework and the runner image, not from the app's own code. Doing that would mean pasting the bytes in. Not doing it means weakening check 3, or changing what is recorded. The spec says to stop and report, so work stopped here. Options for a decision, not chosen:
1. Reproduce the bytes in the service, as a quirk in one place, pinned by a test. It would break when the runner image's ASP.NET version changes.
2. For these records only, compare status and the compared headers, not the body. Each would be listed with its reason, the way the ignored headers are.
3. Record from a non-local client, so the old app returns its production error page (`App_404.aspx`). Untested. It needs a second network identity on the Windows runner, for example a Windows container, and the same check would then apply to that page.
4. Leave method handling to the proxy in the next spec, which would send non-GET requests to the old app. The three requests would then come out of this spec's set.

The new service currently answers these requests with ASP.NET Core's default `405` and `Allow: GET`.

### Not done (stopped at the blocker)

- Tests (xUnit v3, integration tests with Testcontainers, property-based tests), Stryker, and the CI gates for CSharpier, `dotnet format`, locked restore, audit, and CodeQL. The build-time analyzers pass locally with warnings as errors.
- Done-when 4 (mutation job, and recordings absent from the build output and container).
- Done-when 5 (negative control).
- Done-when 6 (Windows live parity).
- Done-when 7's before/after checksum. The read-only login is in place and shown in run 44663053674.
- `evidence/02/parity-report.md`.
