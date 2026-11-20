# Spec 02b run log

Spec: [`specs/02b-improve-behind-the-safety-net.md`](../../specs/02b-improve-behind-the-safety-net.md). Work by Claude Code agent sessions. Times are UTC.

## 2026-11-20: session 1

### Starting point

`main` at `cd84a7d`: the spec 02 service, with SQL copied from the old app's Entity Framework 6 queries, passing all eight spec 02 checks on recording run [44678822763](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44678822763).

### Approved differences: how they are checked

- **The file.** `recordings/approved-differences.json` holds the rules. Each rule has a name, the bug, its evidence (the old app's source line and a recorded example), the requests it applies to (a regular expression over the request line) and a transform.
- **Hashed like the exclusions.** `write-manifest.ps1` copies the file into the recording and hashes it in the manifest, `record.yml` re-records when it changes, and the commit job refuses a recording made from a different copy. So a rule cannot change without a recording run.
- **Applied in one place.** `compare.ps1 -ApprovedDifferences` applies a rule only where the old app answered 200 with JSON. The expected body is the old app's body after the transform, and it is still compared byte for byte with the new service's body. The `.meta` lines (status and headers) must still be identical. Every report lists each record a rule covered, by rule name.
- **Order only, by construction.** There is a closed set of transforms, written in `common.ps1`, not expressions in the JSON. The only one is `semver-order`. A transform reorders the element tokens of a flat JSON array of strings exactly as the old app wrote them, so it cannot add, drop or change an element.
- **What fails the check:**
  - an unknown transform, a missing field, or a rule with no evidence
  - a record matched by two rules
  - a matched body that is not a flat array of strings
  - a rule that applies to no record in either data state (`verify-recordings.ps1`)
- **An independent SemVer order.** The transform's SemVer comparison (`Compare-NuGetVersion` in `common.ps1`) is written out from NuGet.Versioning's rules instead of calling the library the service uses. A mistake in either implementation then shows up as a parity failure instead of passing on both sides.
- **Everywhere the comparison runs.** Check 3 (both states), check 5 (the negative control) and check 6 (live parity, in all three phases) all apply the rules. Live parity's extra phase sends requests that are not in the recorded set, and the rules apply there too, because a rule names its requests by pattern.

### Readable queries: EF Core LINQ

- `PackageQueries.cs` is now LINQ on EF Core 10 (`Microsoft.EntityFrameworkCore.SqlServer` 10.0.15, with the pinned `Microsoft.Data.SqlClient` 7.1.2). It uses a pooled context factory, no tracking, and no migrations. Only the five columns of `Packages` and three of `PackageRegistrations` that the queries use are mapped.
- **What EF Core sends.** Read from the service's command log on the Mac, against state A:
  - **versions:** `SELECT [p].[Version] FROM [dbo].[Packages] AS [p] INNER JOIN [dbo].[PackageRegistrations] AS [p0] ON ... WHERE [p].[PackageStatusKey] = 0 AND [p].[Listed] = CAST(1 AS bit) AND [p].[SemVerLevelKey] IS NULL AND [p].[IsPrerelease] = CAST(0 AS bit) AND [p0].[Id] = @id`. The service then sorts the versions with NuGet.Versioning.
  - **prefix:** `SELECT TOP(@p) [p].[Id] FROM [dbo].[PackageRegistrations] AS [p] WHERE EXISTS (SELECT 1 FROM [dbo].[Packages] AS [p0] WHERE <filters> AND [p0].[PackageRegistrationKey] = [p].[Key]) AND [p].[Id] LIKE @partialId_startswith ESCAPE N'\' ORDER BY [p].[Id]`
  - **most downloaded:** the same `EXISTS`, then `ORDER BY [p].[DownloadCount] DESC, <tie-break>`.
- **Prefix matching.** EF Core 10 translates `StartsWith` to `LIKE` with the wildcards escaped by `\`, not to `LEFT`/`LEN`. The old app used `~` as the escape character, but the result is the same. Every recorded prefix request still matches byte for byte: `%`, `_`, `[S]`, `~`, `~%`, leading and trailing spaces, `%20`, `é`, and the 2,090-character prefix. `LikePattern` and its tests are deleted.
- **The old `DISTINCT` over every column is gone.** Both ID queries now ask "which registrations have a visible version" (`EXISTS`) instead of `DISTINCT` over joined rows.

### Finding: the most-downloaded tie-break cannot be "by ID" against these recordings

This was recorded before deciding anything, as the spec asks.

- **What was tried.** The spec's fix: `OrderByDescending(DownloadCount).ThenBy(Id)`, with the versions rule applied.
- **Result on the Mac,** state A: 199 records matched after the SemVer rule, and 9 records differed. All 9 are the blank-`partialId` requests:
  - `GET /api/v2/package-ids`
  - `?partialId=`, `?partialId=%20`, `?partialId=+`, `?partialId=%20%20`, `?partialId=%09`, `?partialId=%0B`, `?partialId=%C2%A0`
  - `?includePrerelease=true&semVerLevel=2.0.0`
- **Why they fail.** Every seeded `DownloadCount` is 0, in both states. So the old app's answer is the first 30 of a 148-way tie, and the query plan chooses them. The recorded 30 run from `Serilog` to `NUnit3TestAdapter`, which is the order the IDs were registered in. An ID tie-break returns a different 30 (`Ardalis.GuardClauses`, `Ardalis.Specification`, `Autofac`, ...), not the same 30 in another order.
- **Why no rule can cover it.**
  - The spec's transform ("re-sort the recorded list by downloads, then by ID") reorders the recorded 30. It cannot produce IDs the old app never returned.
  - A rule that changes which IDs come back is not allowed.
  - The transform would also need the download counts, which are not in the body.
- **What does reproduce the recordings.** `ThenBy(Key)`, oldest registration first, matched all 9 records byte for byte in state A and in state B.
- **Decision (final, spec 02b amendment B1).** The service breaks ties by registration key, oldest registration first. This order was chosen because it is deterministic and also matches what the old app's query plan happened to return. So bug 2 is fixed: ties now have a defined order that no longer depends on the plan. Every recorded answer is unchanged, so `approved-differences.json` has no rule for bug 2. The interim fix is the final fix.
- **The same in CI.** Probe branch `probe-tiebreak-id` changed only `ThenBy(Key)` to `ThenBy(Id)`. Its new-service run [44686598178](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44686598178) failed check 3 in both states with 339/348 identical. The 9 differing records were exactly the 9 above, and the negative-control baseline failed for the same reason. The branch is deleted.

### Other plan-order or collation dependence

The old queries were checked for other places where the answer depends on chance. None was found that a transform could state:
- **Prefix search** orders by `Id`, and `Id` is unique under the database's case-insensitive collation (`IX_PackageRegistration_Id_Unique`, `SQL_Latin1_General_CP1_CI_AS`). So the order is fully defined. Collation order is not ordinal order (`Newtonsoft.Json` sorts before `NLog`), but that is the database's rule, not chance, and the query still applies it in SQL.
- **The 30 cap** on the prefix search comes after a total order, so which 30 come back is defined.
- **`package-versions/{id}`** matches with `=`, which ignores trailing spaces. A trailing-space ID never reaches the old app, though: IIS trims it (spec 02 amendment A4).

### Re-record with the rules file

- Record run [44685874893](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44685874893) on `1432eda` passed. The bot commit `4137f34` changed only `recordings/manifest.json`, which now hashes `approved-differences.json`. All 702 records (351 per state) are byte for byte unchanged. Release `recordings-44685874893` holds the recording.
- The record job checked the rules under Windows PowerShell 5.1 (`verify-recordings.ps1 -ThisRun`), and live parity then applied them under 5.1, so the comparator runs on both PowerShell editions.

### new-service no longer goes red by design on a re-record push

- **The problem.** A push that changes a recording input starts `record` and `new-service` together. `new-service` then checked the new inputs against the old manifest and failed, as it is built to. Examples: [44685874884](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44685874884) (this session) and [44678823125](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44678823125) (spec 02 session 6). Each such red run was expected, but it reads as a failure to anyone looking.
- **The fix,** in `193b99d`:
  - A first job, `inputs`, diffs the push against record.yml's input paths. If the push touched one, the check jobs are skipped on that push, not failed.
  - `new-service` also runs on `workflow_run` when `record` completes on `main`, whether the run succeeded or failed. It then checks `main` as the recording run left it.
  - The bot's commit is pushed with `GITHUB_TOKEN` and starts no workflow, which is why the trigger is the record run's completion, not the bot's push.
- **Nothing is weakened.** Every push that changes inputs still ends in a full new-service run against the new recording. If the re-record fails, the run still happens and is red.
- **Proof, in two steps.** `dab23b2` changes only a comment in `parity-exclusions.txt`, a recording input.
  1. Its push-triggered new-service run [44687279424](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44687279424) passed, with `inputs` green and the check jobs skipped.
  2. Record run [44687279180](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44687279180) passed, and the bot committed `72fa39b`. Its completion started new-service run [44687871606](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44687871606) (event `workflow_run`, on `72fa39b`), which ran every check job and passed: recordings (a) and (b), negative control and data change.

### Probe branches

A probe branch is a deliberate experiment: a throwaway branch that changes one thing to show what a check does with it. Its red runs are the intended result, and the branch is deleted afterwards.

| Branch | Change | Run | Intended result |
|---|---|---|---|
| `probe-tiebreak-id` | most-downloaded ties by ID (spec 02b's fix) instead of by registration key | new-service [44686598178](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44686598178) | **red**: check 3 fails in both states on exactly the 9 blank-`partialId` records |

### Mutation score

- Stryker on `1432eda`: 81.25%, against a break threshold of 80 ([44685875127](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44685875127)). Spec 02's code scored 90.82%.
- Most of the 20 survivors are in `GalleryDb.OnModelCreating`, the table and column mapping. EF Core builds the model once per process and caches it, so a mutant switched on after that changes nothing. A wrong table name would break every query.
- The other survivors are the same `HostingRules` and startup lines as before. Nothing was excluded from mutation.

## 2026-11-20: session 2

### Decisions settled by spec amendments B1 and B2

- **B1, tie-break.** Registration order is the final fix for bug 2. The code comment in `PackageQueries.cs` and the decision above now say so, and why: the order is deterministic and also matches what the old app's plan happened to return (`842ab51`).
- **B2, like-for-like benchmark** (`220ca2f`, `396c87d`):
  - **Transport.** The service is called over HTTPS on `localhost`, like the old app, with a self-signed RSA 2048 certificate made in the run. `benchmark.ps1` reads each app's certificate from its TLS handshake, and fails unless k6 negotiated the same HTTP and TLS versions with both. Both negotiated HTTP/2 over TLS 1.3 in every run.
  - **Logging.** "Same level" is matched by what each process actually writes, not by a level name. The old app's process writes two console lines per request (IIS Express), and the gallery's Serilog logger has no sink here (no console sink, empty Application Insights key). So the service logs ASP.NET Core's two request lines, one line each, and nothing else below Warning. Measured: 1.96 against 2.00 lines, and 190 against 658 bytes, per request. The byte difference is a caveat in `benchmark.md`.
- **Benchmark database cost, rebuilt.** The first three runs on `ea4e68b` were green, but their database numbers were wrong. Plan-cache entries were lost under load, so the DMV difference fell short of the requests sent: 36 prefix executions for about 13,800 requests, and negative reads in one case. The cost is now measured in its own pass per app: clear the plan cache, send the 1,000-request mix once at concurrency 1, and read the stats for the NuGetGallery database. Exact execution counts (600, 300, 100) are asserted. They held in every run.

### Dependabot PRs #1 to #8

- `75b9fe9` applies all four bumps at every use, SHA-pinned, taken from the PR diffs: checkout v7.0.1, upload-artifact v7.0.2, download-artifact v8.0.2, and cache/restore and cache/save v6.1.0. That covers every workflow, `benchmark.yml` and both composite actions. No old SHA remains.
- **Proof that the bot can still push under checkout v7.** Record run [44688687862](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44688687862) (dispatched, commit on) passed. Its commit job pushed `17efe10`, which changes only `recordings/manifest.json`. That record run's completion started new-service [44689314327](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44689314327) (`workflow_run`), which ran every check job and passed. This also exercises v7's `workflow_run` checkout change.
- Dependabot closed each PR itself once `main` was up to date. Each carries a comment linking the commit.

### Runs this session

| Run | Workflow | Commit | Result |
|---|---|---|---|
| [44687871606](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44687871606) | new-service (`workflow_run`, the race-fix proof) | `72fa39b` | pass |
| [44688625322](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44688625322) | benchmark | `75b9fe9` | **red**: the protocol check compared unsorted strings. Fixed in `396c87d`. |
| [44688687862](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44688687862) | record, commit on | `75b9fe9` | pass, bot commit `17efe10` |
| [44689314327](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44689314327) | new-service (`workflow_run`) | `17efe10` | pass |
| [44689681283](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44689681283) | new-service | `396c87d` | pass |
| [44689681324](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44689681324) | old-app | `396c87d` | pass |
| [44689681332](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44689681332) | service-quality | `396c87d` | pass |
| [44689681333](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44689681333) | lint | `396c87d` | pass |
| [44689681286](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44689681286) | codeql | `396c87d` | pass |
| [44689736187](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44689736187) | live-parity | `396c87d` | pass |
| [44689693749](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44689693749), [44689704828](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44689704828), [44689715248](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44689715248), [44689725788](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44689725788) | benchmark: old app, new service, old app, new service first | `396c87d` | pass; read together in [`benchmark.md`](benchmark.md) |

`396c87d` is the last code change. Later commits change only documentation.

### Benchmark findings

These are in [`benchmark.md`](benchmark.md). In all four runs, the new service served at least 4.1 times the old app's requests per second, with a lower p50 and p95 at every concurrency level and no errors from either app. Its queries read fewer pages per execution: prefix about 3.8 times fewer, versions about 22 times fewer, most-downloaded about 30% fewer. They also used less CPU per execution. p99 latency and scaling with concurrency did not agree across runs, so neither is claimed.
