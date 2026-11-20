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
