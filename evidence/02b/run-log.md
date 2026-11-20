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
- **Decision (interim; the owner decides).** The service breaks ties by registration key. It is deterministic, does not depend on the plan, and needs no approved difference, because every recorded answer is unchanged. So spec 02b bug 2 is fixed (ties have a defined order), but not as specified (by ID). Switching to ID would take one line in `PackageQueries.cs`, plus a way to record answers whose top 30 is not cut inside a tie. For example, a data state with distinct download counts, recorded by the recording workflow, would let a reorder-only rule cover it. That is the owner's call, so `approved-differences.json` has no rule for bug 2.
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
- **Proof (in progress at hand-off):** `dab23b2` changes a comment in `parity-exclusions.txt`. Its new-service run [44687279424](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44687279424) should skip the checks, and record [44687279180](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44687279180) should then start a `workflow_run` new-service run.

### Probe branches

A probe branch is a deliberate experiment: a throwaway branch that changes one thing to show what a check does with it. Its red runs are the intended result, and the branch is deleted afterwards.

| Branch | Change | Run | Intended result |
|---|---|---|---|
| `probe-tiebreak-id` | most-downloaded ties by ID (spec 02b's fix) instead of by registration key | new-service [44686598178](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44686598178) | **red**: check 3 fails in both states on exactly the 9 blank-`partialId` records |

### Mutation score

- Stryker on `1432eda`: 81.25%, against a break threshold of 80 ([44685875127](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44685875127)). Spec 02's code scored 90.82%.
- Most of the 20 survivors are in `GalleryDb.OnModelCreating`, the table and column mapping. EF Core builds the model once per process and caches it, so a mutant switched on after that changes nothing. A wrong table name would break every query.
- The other survivors are the same `HostingRules` and startup lines as before. Nothing was excluded from mutation.
