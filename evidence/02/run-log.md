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
- The SQL follows Entity Framework 6's generated SQL, as read from the plan cache: the same tables, join, filters, DISTINCT, TOP and ORDER BY. (Corrected after review: an earlier wording said "clause for clause". The text differs: Entity Framework adds `OR (1 = 0)`, orders some clauses differently and wraps the most-downloaded query in a `[Project2]` subquery.) The comparisons, the sort, and the order of unsorted results are left to SQL Server.
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

### Runs not in the tables above

- new-service spike and early runs, all green: [44659613592](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44659613592), [44660369348](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44660369348), [44660814677](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44660814677), [44661804808](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44661804808).
- new-service [44662729714](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44662729714): failed. It ran on the `.gitattributes` commit, before the re-record, so verification still saw the 5 normalised files.
- The `lint` runs this session: 6 of 6 green.
- Totals this session (`gh run list`): old-app 9 runs (8 pass, 1 fail), record 3 (2 pass, 1 fail), new-service 8 (5 pass, 3 fail), lint 6 (6 pass).

## 2026-11-20 (UTC): session 4

Work by a Claude Code agent session (session 4), after the human added amendments A1 to A3 to the spec. Final counts per check: `evidence/02/parity-report.md`.

### A1, A2, A3 applied

- **A1.** `recordings/parity-exclusions.txt` names the three non-GET requests with the reason. `compare.ps1 -Exclusions` skips them, lists them as `EXCLUDED` in every report, refuses a GET entry, and refuses an entry that is not a recorded request. The file is hashed in the manifest, so it changes only with a re-record. The service's `405` with `Allow: GET` is pinned by `Methods_other_than_GET_are_refused_with_405_and_Allow_GET`.
- **A2.** `seed/state-b.txt`: Serilog 4.4.1-dev-02453, Polly 8.0.0-beta.2, xunit 2.5.2-pre.6, Serilog.Exceptions 8.4.0+build.694, Ninject 3.3.0-ci.15+sha.f4793a7. Real nuget.org versions of seeded IDs, found by scanning the seeded IDs' versions and nuspecs on nuget.org. The record workflow records state A, pushes the list, snapshots `state-b-snapshot`, restores it, and records state B.
- **Credential gap.** The restored snapshot has no usable credential: the seed account's password and API key existed only in the seeding run. `push-state-b.ps1` registers a second account through the site's forms (`new-account.ps1`, moved out of `seed.ps1`). It then makes that account co-owner of the five IDs with one SQL row each in `PackageRegistrationOwners`, and pushes through the API. Without the row, the push is refused: `403` in exploratory run [44665262875](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44665262875). No package row is written by SQL.
- **A3.** Requests added for whitespace IDs and prefixes, and for `%`, `_`, `[`, `]`, `^` and `~` in prefixes and IDs. The `+` in versions comes from state B (`8.4.0+build.694`, `3.3.0-ci.15+sha.f4793a7`). `Serilog+Sinks` in a path was tried and left out: IIS request filtering answers 404.11 before the app runs, the same class as the existing "not sent" group.

### Runs

| Run | Workflow | Result | What happened | Change that followed |
|---|---|---|---|---|
| [44665262875](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44665262875) | record (branch, no commit) | pass | Exploration. Both states recorded, 296 requests, passes identical. Push before the ownership grant: 403. SQL login on LocalDB works (`IsIntegratedSecurityOnly=0`). Whitespace IDs: IIS 404.4 page. | Requests finalised; branch deleted |
| [44666187971](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44666187971) | record | pass | Committed both states. | |
| [44666638638](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44666638638) | new-service | fail | `seed/state-b.txt` hash differed: the Windows checkout converted it to CRLF. | `.gitattributes`: `seed/state-b.txt -text` |
| [44666951411](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44666951411) | record | pass, but committed nothing | `git add recordings/responses` failed (the folder was gone), and PowerShell carried on. | Stage only the state folders; fail if `git add` fails |
| [44667487773](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44667487773) | record | **pass** | The current recording: 295 requests, two states. | |
| [44667895990](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44667895990) | new-service | fail | Checks 3 and 7 ran: only the two whitespace IDs differ; 7 passes. The mutation job failed: from the repo root `dotnet` did not see `service/global.json` and used SDK 11.0.100, and the container publish picked win-x64. | Run `dotnet` from `service/`; `--os linux --arch x64` for the container |
| [44668584932](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44668584932) | new-service | fail | `no-recordings-in-build.sh` reported recorded bodies inside the build. False positive: the HTML error bodies were used as `grep -f` patterns, and their blank lines match everything. | Search only single-line JSON bodies |
| [44668840662](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44668840662) | new-service | fail (3 only) | Check 4 passes (9/9), check 5 passes, check 7 passes in both states. | |
| [44667897238](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44667897238), [44668586117](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44668586117) | live-parity | fail | Phases A and B: only the two whitespace IDs differ. Then `random-requests.ps1` failed: the run ID used as a seed overflows Int32. Then the extra phase failed because the A1 exclusions were applied to a request set without those requests. | Seed taken modulo Int32; exclusions only for the committed set |
| [44669109629](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44669109629) | live-parity | fail (2 records) | State A and B: 290/292. Extra phase: 326/326 identical. | |
| [44669108406](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44669108406) | new-service | fail (3 only) | Checks 4, 5 and 7 pass; check 3 290/292 in each state. | |
| [44668156090](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44668156090) | old-app | fail, then rerun | `restore-on-fresh-machine`: LocalDB "SQL Server process failed to start" in the gallery's setup script. The commit touched no Windows path. The failed job was rerun. | |

Service quality: service-quality ran on every push. Stryker scored 90.91% with both test projects ([44667442365](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44667442365)); a unit-test-only run on the Mac scored 24%, because the SQL, endpoints and startup are reachable only through integration tests. CodeQL reported 0 results on every push. Lint passed on every push.

### Decisions

- **Recording layout**: `recordings/state-a`, `recordings/state-b`. The manifest adds `stateBList`, `stateBSnapshotRun` and `stateBSnapshotSha256`. The state B snapshot is read from the run named in the manifest, so it changes with each re-record. Artifacts expire after 90 days, so the state B snapshot needs a re-record by then. The seed snapshot expires on 2027-02-18.
- **Check 4** runs the container image (`dotnet publish /t:PublishContainer`, base image pinned by digest) with `recordings/` moved out of the checkout before the build. Versions are compared as sets, because the old query has no ORDER BY. ID lists are compared in order.
- **Check 5** plants the fault in the database, so the wrong response comes through the real capture path. It compares the service with itself before and after, so the two whitespace records cannot hide or fake the result.
- **Check 7** compares row counts and `CHECKSUM_AGG(BINARY_CHECKSUM(*))` of every table, plus a SHA-256 of `Packages` and `PackageRegistrations` as ordered JSON.
- **Check 6** publishes a self-contained win-x64 build on Linux. The gallery build parks .NET SDKs above 9 on the Windows runner, so `RuntimeIdentifiers` (linux-x64, win-x64) are restored, which keeps locked mode working. The service runs as a SQL login with `db_datareader` on LocalDB, started through WMI.
- **Stryker** uses the MTP runner, which Stryker calls preview. It mutates every source file, with unit and integration tests.
- **Integration tests** write rows only for themselves (IDs starting `ZzFilters`) in a throwaway container.

### Open

- The two whitespace-ID records (`parity-report.md`, "Open decision"). Checks 3 and 6 stay red on them alone.

## 2026-11-20 (UTC): session 5

Work by a Claude Code agent session (session 5), after the human added amendment A4 to the spec. Final counts per check: `evidence/02/parity-report.md`.

### A4 applied

- **The service** answers a whitespace-only id with an empty `404`, the status IIS gives the old app's requests (both recorded records: `status: 404`, in both states). Before, it answered `500`, the old controller's answer to a blank id, which IIS never lets through. Pinned by `A_blank_id_is_not_found_with_an_empty_body` (status, no content type, empty body, `Cache-Control` and `X-Frame-Options`) for `%20` and `%20%20`.
- **The exclusions file** now gives each entry a mode: `excluded` (the three A1 entries, unchanged in meaning) or `status-only` (the two A4 entries). `compare.ps1` compares only the `status:` lines of a `status-only` record, counts it as compared, and fails if either side's record or status line is missing. It still refuses a GET in mode `excluded`, an unknown mode and a stale entry. Tried locally against copies of `recordings/state-a`: a changed body on a listed record passes; a changed status, a deleted record, and a changed body on an unlisted record each fail; each malformed entry throws.
- **Re-record.** Pushing the exclusions file ran the recording workflow ([44670190089](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44670190089)). Its commit changed only `recordings/manifest.json`: the run links, the state-B snapshot digest and the exclusions file hash. Every recorded byte is unchanged.

### Runs

| Run | Workflow | Result | What happened | Change that followed |
|---|---|---|---|---|
| [44670190089](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44670190089) | record | **pass** | The current recording. Checks 1 and 2. | |
| [44670190025](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44670190025), [44670190018](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44670190018), [44670190071](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44670190071), [44670190009](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44670190009) | service-quality, codeql, lint, old-app | pass | The same push, on the A4 code. | |
| [44670190106](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44670190106) | new-service | fail, expected | Ran on the push that changed the exclusions file, before the re-record: the manifest's hash of the file was stale. | None needed |
| [44670831746](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44670831746) | new-service | fail (check 5 only) | Checks 3, 4 and 7 pass. Check 5 failed because `negative-control.ps1` reads the report's `DIFFERENT` lines, and `compare.ps1` had widened their spacing. | Restored the report's line format |
| [44670834825](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44670834825) | live-parity | pass | State A 292/292, state B 292/292, extra 327/327, on the commit before the format fix. | |
| [44671063641](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44671063641) | new-service | **pass** | Checks 3, 4, 5, 7 on the final code, both states. | |
| [44671299999](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44671299999) | live-parity | **pass** | Check 6 on the final code. | |
| [44671063765](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44671063765) | service-quality | **pass** | 45 unit, 26 integration tests, Stryker 90.91%. | |
| [44670434468](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44670434468) | service-quality (branch `gate-proof-format`, deleted) | fail, intended | Gate proof: CSharpier failed on a collapsed `Program.cs`. Mutation testing passed. | |
| [44670438414](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44670438414) | service-quality (branch `gate-proof-mutation`, deleted) | fail, intended | Gate proof: with five of seven test files removed, Stryker scored 3.03% and failed the break threshold of 80. The other gates passed. | |
| [44668156090](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44668156090) | old-app (session 4) | pass on rerun | Attempt 1 failed in `restore-on-fresh-machine` (LocalDB "SQL Server process failed to start"); attempt 2 passed. | |
| [44671063570](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44671063570) | old-app | **pass** on attempt 2 | Job `old-app` (old app checks, empty source diff) passed. Job `restore-on-fresh-machine` failed on attempt 1 at LocalDB startup, as in 44668156090, and passed when rerun. | |

**The LocalDB start flake.** Across the old-app workflow's history, the `restore-on-fresh-machine` job has run 22 times, counting reruns. It failed twice, both times the same way: LocalDB "SQL Server process failed to start" inside the gallery's own `Setup-DevEnvironment.ps1`. Both failures are among the seven most recent attempts (44668156090 attempt 1, and 44671063570 attempt 1, the run on the final code); the fifteen before them were clean. Both passed when rerun. The failing script is the old app's, so it is not changed. No automatic retry was added: it would also hide a real setup fault. If it keeps recurring, a harness step that starts LocalDB before the gallery's setup is the place to look.

### Decisions

- **Status-only compares the status line only,** as A4 and the mode's name say. Comparing the other headers would be stricter, and they match today, but IIS's error-page headers are as much a host artefact as its body.
- **404 for every whitespace-only id.** The service uses `string.IsNullOrWhiteSpace`, so ids of tabs or other whitespace also get `404`. Only spaces are recorded; what IIS does with, say, `%09` is not known.
- **Report format kept.** `negative-control.ps1` matches `DIFFERENT  <record>  <request>` exactly, so new lines follow the old two-space layout.

Session 5 total: 16 workflow runs before the evidence commits (17 attempts with the rerun): the table above, plus codeql [44671063554](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44671063554) and lint [44671063449](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44671063449) on the final code, both passed. Each evidence commit also ran lint, which passed.

## 2026-11-20 (UTC): session 6, the review-fix pass

Work by Claude Code agent sessions, after three independent reviewer agents read commit `c355399`. Each finding, its resolution and the commit or run that resolved it: `evidence/02/reviews.md`. Final counts per check: `evidence/02/parity-report.md`.

**Names changed in this pass** (earlier entries in this log keep the old names): the `mutation` job in `new-service.yml` is now `data-change`, `mutate.sql` is `change-data.sql`, `mutate.ps1` is `push-extra.ps1`, and `mutation-check.ps1` is `data-change-check.ps1`. "Mutation" now means Stryker only.

### What changed

- **Recording.** `record.yml` is two jobs: a read-only `record` job, and a `commit` job with `contents: write`. The commit job keeps the recordings folder as the asset of the release `recordings-<run id>` before it pushes. `verify-recordings.ps1` compares `recordings/` with that asset, so verification no longer depends on a workflow artifact, which expires after 90 days.
- **Exclusions.** Each entry names its amendment, and CI checks the amendment's condition against the old app's record.
- **Request set.** It grew from 295 to 351 requests, adding the web server's refusals and limits, and state B grew from five pushes to seven. The re-record ([44678822763](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44678822763)) left every one of the 295 existing state-A records byte for byte unchanged and added 56. In state B, 20 `package-ids` answers changed, all because of the two new IDs.
- **Not recorded: request validation.** Three requests are a known gap (`parity-report.md`, "Known gaps"). The old app's own `ApiController.OnException` writes their 500 body, so amendment A4 does not cover them.
- **Kestrel limits.** `docs/engineering-standards.md` now says Kestrel's limits match the old app's (IIS `maxQueryString` and similar), not "defaults or tighter". Parity needs the service to accept and refuse the same requests.

### Runs

| Run | Workflow | Result | What happened | Change that followed |
|---|---|---|---|---|
| [44674677772](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44674677772) | record (branch `probe-a2`, no commit) | fail, exploration | Check 1 failed only on `/api/v2/package-versions/..`, which differs between passes. Gave the statuses and error pages of the new requests, and showed that request validation's 500 body is written by the app. | Dropped `..` (it resolves to another route); request-validation values left out |
| [44677460758](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44677460758) | record (`probe-a2`, no commit) | fail | State A passed. The state B push stopped at the co-ownership count: the two new IDs have no registration yet. | 60640af: grant only on IDs that exist |
| [44678323085](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44678323085) | record (`probe-a2`, no commit) | pass | 351/351 identical passes in both states; seven pushes, two of them new IDs. | Pushed `main` |
| [44678822763](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44678822763) | record | **pass** | The current recording. The commit job created release `recordings-44678822763` and committed 8e498db. | |
| [44678823125](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44678823125) | new-service | fail, expected | Ran on the push itself, before the re-record. The committed manifest still named run 44670190089, which has no release, so `verify-recordings.ps1` could not download one. This red window lasts until the bot's commit; bot pushes start no workflows, so the next runs were started by hand. | None needed |
| [44678823088](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44678823088), [44678823007](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44678823007), [44678822830](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44678822830), [44678822824](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44678822824) | old-app, lint, codeql, service-quality | pass | The same push. | |
| [44679454144](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44679454144) | new-service | fail (check 5 only) | Checks 3, 4 and 7 passed in both states. Check 5's deleted-record case found that `compare.ps1` crashed on a record missing from one side (`@()` unrolls to `$null` under strict mode) instead of reporting `MISSING`. | 6348baa |
| [44679458066](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44679458066) | live-parity | fail (extra phase) | States A and B passed. Then the extra phase counted the rows `download-counts.sql` set as 1, because `Invoke-Sql` returns one array and `@()` wrapped it. | 69d72bc |
| [44680388263](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44680388263) | new-service | **pass** | Checks 3, 4, 5 and 7 in both states, on 69d72bc. | |
| [44680388674](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44680388674) | live-parity | **pass** | Check 6: 348/348 in both states, extra 332/332. | |
| [44680388301](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44680388301), [44680388166](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44680388166), [44680388149](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44680388149), [44680388157](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44680388157) | service-quality, codeql, lint, old-app | **pass** | 69d72bc: 78 unit and 50 integration tests, Stryker 90.82%. | |

Session 6 total: 17 workflow runs before the evidence commit, none rerun. Pushing `.github/dependabot.yml` also started Dependabot: 6 "Dependabot Updates" runs and 9 update pull requests, all left open for the owner. One of them (NuGet.Versioning 8.0.0) would break parity; 6869372 tells Dependabot to leave that package alone.

**The LocalDB start flake (review C9).** `setup.ps1` now starts LocalDB itself before the gallery's setup, with up to five attempts, each logged. In this pass it started LocalDB 9 times, in every Windows job from probe 2 on, and every start answered on the first attempt. That is 0 retries in 9 starts, against 2 failures in 22 attempts before the wrapper.

### Decisions

- **Recordings kept in a release, not checked against the artifact.** The owner decided this. If GitHub ever answers 404 for the run, verification rests on the release asset and the manifest hashes, and says so. Any other error reading the run fails. A re-run of a recording run must find the same recording in its release; the release is never overwritten.
- **Signal, not control.** A release asset can be replaced by anyone who can push, while a run artifact cannot. The check binds the folder to the asset, and the asset's name to a successful run, but not the asset's bytes to that run. The "immutable releases" recommendation below would close this.
- **Request validation is a known gap**, not an amendment (owner's decision). Recording from a non-local client would close it.
- **No `docker` Dependabot entry, folders not renamed, README heading "Verify it yourself".** The reasons are in `reviews.md` (B4, C7, C1).

### Recommended repository settings (review B7, not applied)

Repository settings are the owner's decision; none of these was changed.
- **A ruleset on `main`** requiring the new-service, service-quality, codeql, lint and old-app checks to pass before a change lands. The gates would then block instead of flag. The recording workflow's commit job pushes to `main`, so it would need a bypass, or would have to open a pull request instead.
- **Immutable releases.** Once published, a release's assets and tag could not be changed, so `recordings-<run id>` would become as strong as a run artifact. The commit job currently adds the state B snapshot to the existing `snapshots-v1` release, which immutable releases would refuse. It would first have to put that snapshot in the run's own release.
- **A tag ruleset** on `recordings-*` and `snapshots-*` that blocks deleting or moving those tags.
- **Actions settings:** require actions to be pinned to a full-length commit SHA (every workflow already is), allow only GitHub-owned and listed actions, and keep the default `GITHUB_TOKEN` permission read-only.
- **Secret scanning with push protection, and Dependabot alerts.**
