# Spec 02 parity report

Status on 2026-11-20 (UTC), session 5. Every number links to the public run that produced it. The runs are on the current recording (record run [44670190089](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44670190089)) and the current code (commit `5ef37ec`), except where a row says otherwise.

**Summary.** All eight checks pass in both data states. Of the 295 recorded requests, 290 are compared byte for byte. Three are excluded and two are compared by status only. Each of the five is listed below with its reason.

| # | Check | Result | Runs |
|---|---|---|---|
| 1 | Recordings trustworthy | pass: 295 requests in each of two states, two byte-identical passes per state (295/295 each); manifest with run, app commit, both snapshot digests, the state-B list hash, the exclusions file hash and 1,185 file hashes | record [44670190089](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44670190089) |
| 2 | Request set covers the awkward cases | pass as recorded: 295 requests, each group citing its old-app source; A3 groups (blank IDs, LIKE characters); state B makes the flag requests matter | same run |
| 3 | Service matches the recordings on Linux | pass in both states: 292/292 compared records identical, 2 of them by status only; 3 excluded | new-service [44671063641](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44671063641) |
| 4 | Answers from the database | pass: no recording in the publish output or the container image; after `mutate.sql`, 9/9 affected responses changed as the data says | same run, job `mutation` |
| 5 | Comparator can fail | pass: one planted wrong row; `compare.ps1` failed and reported exactly `GET /api/v2/package-versions/log4net` | same run, job `negative-control` |
| 6 | Live parity on Windows | pass: state A 292/292, state B 292/292 (2 of them by status only; 3 excluded); after the extra pushes, 327/327 requests outside the committed set identical | live-parity [44671299999](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44671299999) |
| 7 | Writes nothing | pass in both states: login `reader` has `db_datareader` only; 52 fingerprint lines (row count and checksum of every table, SHA-256 of `Packages` and `PackageRegistrations`) identical before and after the 295 requests | new-service [44671063641](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44671063641) |
| 8 | Quality gates on every push | pass: locked restore with audit (0 vulnerable packages), build with analyzers and warnings as errors, CSharpier, `dotnet format` style and analyzers, 45 unit/property tests, 26 integration tests (Testcontainers SQL Server), Stryker 90.91% (break 80), CodeQL, lint; old app's source and config diff empty | service-quality [44671063765](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44671063765), codeql [44671063554](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44671063554), lint [44671063449](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44671063449), old-app [44671063570](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44671063570) (job `restore-on-fresh-machine` passed on its second attempt; see the run log on the LocalDB start flake) |

**The gates block.** Two gates were violated on throwaway branches, each run failed at the gate's own step, and the branches were deleted:
- CSharpier: `Program.cs` collapsed onto one line. Job `gates` failed at step `CSharpier` ("Program.cs - Was not formatted"). service-quality [44670434468](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44670434468).
- Stryker break threshold: five of the seven test files removed. Job `mutation-testing` failed at step `Stryker.NET (break threshold 80)` with a score of 3.03%. service-quality [44670438414](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44670438414).

## Exclusions

`recordings/parity-exclusions.txt` lists five of the 295 recorded requests. It is hashed in the manifest, so it changes only with a re-record. `compare.ps1` lists every entry in each report, and fails on an unknown mode, on a GET in mode `excluded`, and on an entry that is not a recorded request.

| Request | Mode | Reason |
|---|---|---|
| `POST /api/v2/package-ids?partialId=Serilog` | excluded | A1: not a GET. The old app answers with ASP.NET's developer-detail 404 page (framework build, stack trace). The next spec's proxy sends it to the old app. The service answers `405` with `Allow: GET`, pinned by `Methods_other_than_GET_are_refused_with_405_and_Allow_GET`. |
| `DELETE /api/v2/package-versions/Serilog` | excluded | A1, as above |
| `PUT /api/v2/package-versions/Serilog` | excluded | A1, as above |
| `GET /api/v2/package-versions/%20` | status-only | A4: the old app's code never sees it. IIS trims the trailing spaces, finds no route and answers `404` with its "404.4" detailed error page, which names the recording machine's paths. Both answer `404`. The service's body (empty, no content type, the gallery headers) is pinned by `A_blank_id_is_not_found_with_an_empty_body`. |
| `GET /api/v2/package-versions/%20%20` | status-only | A4, as above |

In mode `status-only` only the `status:` lines are compared. The headers and body are not. A missing record or a missing status line fails. The other recorded headers of these two records happen to match too: the only meta difference in the last run before A4 was the status and the content type ([44669108406](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44669108406)).

## Where the counts come from

- Recorded set: `recordings/requests.txt`, 295 requests. Records: `recordings/state-a`, `recordings/state-b`. Exclusions: `recordings/parity-exclusions.txt`.
- State B: `seed/state-b.txt`, five real nuget.org versions of seeded IDs: SemVer 1 prerelease, dotted prerelease (two), stable with `+` metadata, dotted prerelease with `+` metadata.
- Live extra phase: `seed/live-parity-extra.txt` (seven pushes: new IDs with `-` and `_`, a prerelease-only SemVer 2 ID, another `+` version), `scripts/live-parity-requests.txt` (27 fixed requests) and 300 requests from `random-requests.ps1` seeded with the run ID.
