# Spec 02 parity report

Status on 2026-11-20 (UTC), session 4. Every number links to the public run that produced it.

**Summary.** Checks 1, 2, 4, 5, 7 and 8 pass. Checks 3 and 6 fail on the same two records, and only on those: `GET /api/v2/package-versions/%20` and `GET /api/v2/package-versions/%20%20`. Every other recorded request matches byte for byte in both data states, on Linux against the recordings and on Windows against the live old app. The two records need a decision (see "Open decision").

| # | Check | Result | Runs |
|---|---|---|---|
| 1 | Recordings trustworthy | pass: 295 requests in each of two states, two byte-identical passes per state, manifest with run, app commit, both snapshot digests, the state-B list hash and 1,185 file hashes | record [44667487773](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44667487773) |
| 2 | Request set covers the awkward cases | pass as recorded: 295 requests, each group citing its old-app source; A3 groups added (blank IDs, LIKE characters); state B makes the flag requests matter | same run |
| 3 | Service matches the recordings on Linux | **fail, 290/292 compared records in each state** (3 excluded under A1). The 2 differences are the blank IDs. | new-service [44669108406](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44669108406) |
| 4 | Answers from the database | pass: no recording in the publish output (42 files) or the container image (1,333 files); after `mutate.sql`, 9/9 affected responses changed as the data says | new-service [44669108406](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44669108406), job `mutation` |
| 5 | Comparator can fail | pass: one planted wrong row; `compare.ps1` failed and reported exactly `GET /api/v2/package-versions/log4net` | new-service [44669108406](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44669108406), job `negative-control` |
| 6 | Live parity on Windows | **fail on the same 2 records**: state A 290/292, state B 290/292 (3 excluded); after the extra pushes, 326/326 requests outside the committed set identical | live-parity [44669109629](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44669109629) |
| 7 | Writes nothing | pass in both states: login `reader` has `db_datareader` only; 52 fingerprint lines (row count and checksum of every table, SHA-256 of `Packages` and `PackageRegistrations`) identical before and after the full request set | new-service [44669108406](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44669108406) |
| 8 | Quality gates on every push | pass: locked restore with audit (0 vulnerable packages), build with analyzers and warnings as errors, CSharpier, `dotnet format` style and analyzers, 45 unit/property tests, 25 integration tests (Testcontainers SQL Server), Stryker 90.91% (break 80), CodeQL with zero results; old app's source and config diff empty (old-app runs) | service-quality [44667442365](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44667442365), codeql [44669108389](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44669108389), old-app [44667896122](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44667896122) |

## Open decision: whitespace-only package IDs (A3)

A3 asks for blank and whitespace IDs to be recorded and matched. The recording shows that the old app never sees them:
- IIS trims trailing spaces from the path, so `/api/v2/package-versions/%20` becomes `/api/v2/package-versions/`, which matches no MVC route.
- IIS answers itself: `404`, `text/html`, its "IIS 10.0 Detailed Error - 404.4" page. Because the recorder is a local client, the page names the runner's physical path (`D:\a\nuget-harness\...\api\v2\package-versions\`).
- The `ArgumentNullException` 500 in `AutocompleteDatabasePackageVersionsQuery.cs` is not reachable over HTTP on this host.

To match, the service would have to paste in IIS's error page and the recording machine's path. That is the A1 problem on a GET. `parity-exclusions.txt` refuses GET entries, so the two records are not excluded and checks 3 and 6 stay red. The service answers `500` with an empty body (the old controller's behaviour), pinned by `A_blank_id_is_answered_500_as_the_old_query_throws`.

Options for a human:
1. Extend A1 to requests the old app's host answers before the app runs, and list these two by name.
2. Reproduce the IIS page in the service.
3. Leave them to the next spec's proxy: if IIS fronts the strangler, it trims the path and answers 404.4 before routing.

## Where the counts come from

- Recorded set: `recordings/requests.txt`, 295 requests. Records: `recordings/state-a`, `recordings/state-b`. Exclusions (A1): `recordings/parity-exclusions.txt`, three non-GET requests.
- State B: `seed/state-b.txt`, five real nuget.org versions of seeded IDs: SemVer 1 prerelease, dotted prerelease (two), stable with `+` metadata, dotted prerelease with `+` metadata.
- Live extra phase: `seed/live-parity-extra.txt` (seven pushes: new IDs with `-` and `_`, a prerelease-only SemVer 2 ID, another `+` version), `scripts/live-parity-requests.txt` (27 fixed requests) and 300 requests from `random-requests.ps1` seeded with the run ID.
