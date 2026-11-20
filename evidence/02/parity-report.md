# Spec 02 parity report

Status on 2026-11-20 (UTC), session 6 (the review-fix pass). Every number links to the public run that produced it. The runs are on the current recording (record run [44678822763](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44678822763)) and the current code (commit `3a9e67f`), except where a row says otherwise. Session 5's report, on 295 requests, is in this file's history.

**The three runs to open first:** record [44678822763](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44678822763), new-service [44681844481](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44681844481) and live-parity [44681844828](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44681844828).

**Summary.** All eight checks pass in both data states. Of the 351 recorded requests, 312 are compared byte for byte, 36 by status only, and 3 are excluded. Every exclusion entry names its amendment, and CI checks the amendment's condition against the old app's record. Three requests are known not to be covered; see "Known gaps".

| # | Check | Result | Runs |
|---|---|---|---|
| 1 | Recordings trustworthy | pass: 351 requests in each of two states, two byte-identical passes per state (351/351 each). The manifest holds the run, the app commit, both snapshot digests, the state B list hash, the exclusions file hash and 1,409 file hashes. On every later run, `verify-recordings.ps1` checks that `recordings/` is, file for file, the asset of the release `recordings-44678822763`, and that the run is a successful `record.yml` run on `main` | record [44678822763](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44678822763) |
| 2 | Request set covers the awkward cases | **The agent's own judgement, not a tool check.** No tool measures coverage. The agent wrote the request set from the old app's source, and each group in `recordings/requests.txt` cites the file it comes from: A3 groups (blank and whitespace IDs, `LIKE` characters), the web server's limits and refusals (A2 review finding), and the flag requests that state B makes matter. The reviewers read it; the gaps they found are recorded in `reviews.md` | same run |
| 3 | Service matches the recordings on Linux | pass in both states: 348/348 compared records identical, 36 of them by status only; 3 excluded | new-service [44681844481](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44681844481) |
| 4 | Answers from the database | pass: no recording in the publish output or the container image; after `change-data.sql` and `download-counts.sql`, 11/11 affected responses changed as the data says, including the most-downloaded order | same run, job `data-change` |
| 5 | Comparator can fail | pass: the service's own answers pass first, then four planted faults each fail on exactly the planted record, for the planted reason: a wrong status on a status-only record, a changed compared header, a deleted record (`MISSING`), a wrong version served from the database | same run, job `negative-control` |
| 6 | Live parity on Windows | pass: state A 348/348, state B 348/348 (36 of them by status only; 3 excluded); after the extra pushes and distinct download counts, 332/332 requests outside the committed set identical | live-parity [44681844828](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44681844828) |
| 7 | Writes nothing | pass in both states: login `reader` has `db_datareader` only; 52 fingerprint lines (row count and checksum of every table, SHA-256 of `Packages` and `PackageRegistrations`) identical before and after the 351 requests | new-service [44681844481](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44681844481) |
| 8 | Quality gates on every push | pass: locked restore with audit, build with analyzers and warnings as errors, CSharpier, `dotnet format` style and analyzers, 78 unit and property tests, 50 integration tests (Testcontainers SQL Server), coverage reported, Stryker 90.82% (break 80), CodeQL, lint; old app's source and config diff empty | service-quality [44681844557](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44681844557), codeql [44681844700](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44681844700), lint [44681844498](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44681844498), old-app [44681844424](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44681844424) |

**The gates flag; they don't block.** The workflows run after a commit is pushed to `main`, and `main` has no branch protection, so a failing gate marks a bad commit as red but does not stop it from landing. Making them block is a repository setting (see `run-log.md`, session 6, recommendations), which is the owner's decision. Each gate does fail when it is violated: two were tried on throwaway branches in session 5, and each run failed at the gate's own step:
- CSharpier: `Program.cs` collapsed onto one line. Job `gates` failed at step `CSharpier`. service-quality [44670434468](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44670434468).
- Stryker break threshold: five of the seven test files removed. Job `mutation-testing` failed at step `Stryker.NET (break threshold 80)` with a score of 3.03%. service-quality [44670438414](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44670438414).

## Exclusions

`recordings/parity-exclusions.txt` lists 39 of the 351 recorded requests. Each entry names its amendment, and `Read-ParityExclusionFile` (`scripts/runner/common.ps1`) checks the amendment's condition against the old app's record in both states, on every comparison and in `verify-recordings.ps1`:
- `excluded` (A1) is allowed only for a method other than GET.
- `status-only` (A4) is allowed only where the recorded body is `text/html` and carries the signature of one of three pages the web server writes, not the app: IIS's detailed error page (`<title>IIS 10.0 Detailed Error - 404.x`), ASP.NET's error page (`Server Error in '/' Application` with an `HttpException`), or http.sys's "Bad Request - Invalid URL" page.

The file is hashed in the manifest, so it changes only with a re-record. Every report lists every entry, so none is silent.

| Requests | Mode | Old app's status | Reason |
|---|---|---|---|
| `POST`, `PUT`, `DELETE` on the two routes (3) | excluded | 404 | A1: not a GET. The old app answers with ASP.NET's developer-detail 404 page. The next spec's proxy sends these to the old app. The service answers `405` with `Allow: GET`, pinned by a test. |
| Whitespace-only IDs `%20`, `%20%20` (2) | status-only | 404 | A4: IIS trims the spaces and answers with its 404.4 page. |
| Other paths IIS answers with 404.4 (6) | status-only | 404 | A4: no handler: `%2F` and `%5C` in an ID, IDs of non-ASCII whitespace (`%C2%A0`, `%E3%80%80`), `.` and `.%20`. |
| `+` in a path (3) | status-only | 404 | A4: IIS 404.11, double escaping. |
| Query strings over 12,000 characters (4) | status-only | 404 | A4: IIS 404.15, `maxQueryString`. |
| `requestPathInvalidCharacters` in a path (8) | status-only | 400 | A4: ASP.NET's "potentially dangerous Request.Path". |
| Paths over `maxUrlLength` (2) | status-only | 400 | A4: ASP.NET's error page. |
| Control characters, and path segments over 260 characters (11) | status-only | 400 | A4: http.sys's "Bad Request - Invalid URL". |

In mode `status-only` only the `status:` lines are compared, and a missing record or status line fails. The service gives each of these statuses in one place, `HostingRules.cs`, with its source and a test.

## Known gaps

**Request-validation errors are not covered: 3 requests.** `partialId=%3Cx`, `partialId=%26%23x` and `semVerLevel=%3Cx` are not in the recorded set. They are listed in the "Not sent" block of `recordings/requests.txt`.
- **Why:** the old app answers 500, and its own code writes the body: `ApiController.OnException` (line 1045 at the pinned commit) catches the request-validation exception. What it writes depends on whether the client is local. A local client, which the recorder is, gets the exception's stack trace; a remote client gets `exception.Message`. Neither A1 nor A4 covers a body the app writes, and recording the local-client body would pin the service to a stack trace no production client sees (exploratory record run [44674677772](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44674677772)).
- **How to close it:** record these requests from a non-local client, so the recorded body is the message a real client gets.

**What state B covers, and what it doesn't.** It is state A plus seven real nuget.org versions. Five are new versions of seeded IDs, which change `package-versions` answers and the flag requests. Two are new IDs under `Serilog.Sinks`, which change 21 `package-ids` answers in state B. State B adds no new prefix, no unlisted package and no deleted package. The live extra phase (check 6) goes further, with seven more pushes, distinct download counts and 332 requests outside the committed set, but it is compared live, not recorded.

## Where the counts come from

- Recorded set: `recordings/requests.txt`, 351 requests. Records: `recordings/state-a`, `recordings/state-b`. Exclusions: `recordings/parity-exclusions.txt`, 39 entries.
- State B: `seed/state-b.txt`, seven real nuget.org versions: a SemVer 1 prerelease, two dotted prereleases, a stable version with `+` metadata, a dotted prerelease with `+` metadata (all of seeded IDs), and two new IDs, one stable and one whose only version is a prerelease.
- Download counts: `scripts/download-counts.sql`, 32 distinct counts.
- Live extra phase: `seed/live-parity-extra.txt` (seven pushes: new IDs with `-` and `_`, a prerelease-only SemVer 2 ID, another `+` version), `scripts/live-parity-requests.txt` (32 fixed requests) and 300 requests from `random-requests.ps1` seeded with the run ID.
