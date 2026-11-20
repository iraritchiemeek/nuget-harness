# Spec 02: Move the two read endpoints to a new service

## Goal

Build a new, modern .NET service that answers the two read endpoints from spec 01 exactly as the old app does:

- `GET /api/v2/package-ids`
- `GET /api/v2/package-versions/{id}`

It reads the same database the old app uses, without changing it. "Exactly" means the same status code, the same content type and the same body bytes, for every recorded request.

The old app is the only source of truth. Expected answers are never written by hand or by the agent building the service. They are recorded from the running old app.

No human writes or reviews code at any stage. Every claim is backed by a public run anyone can open.

## How the work loops

Running the old app takes minutes per run, so it can't be the inner loop. There are three tiers:

| Tier | Where | What it proves | When it runs |
|---|---|---|---|
| Recordings | Mac, then GitHub Linux runner | The new service, reading a restored copy of the seeded database, gives the recorded answers | Mac on every change, Linux on every push |
| Live parity | GitHub Windows runner | The old app and the new service, running side by side on the same live database, give identical answers, including after the data changes | At milestones, and as the final check |
| Recording run | GitHub Windows runner | The recordings themselves are correct and stable | When the request set changes |

The Mac is only for development. It proves nothing to a reader, so every "Done when" check runs in GitHub Actions.

## Pinned versions

- **Old app:** same as spec 01, commit `63e6ee4202b441e1c904d6f78fc7b070f36bc24f`, untouched.
- **New service .NET version:** .NET 10 (LTS), pinned in `service/global.json`. The reasoning is in `docs/engineering-standards.md`.
- **SQL Server image:** a Microsoft `mssql/server` image pinned by digest. It must be the same major version as the runner's LocalDB or newer, so a LocalDB backup restores into it. The agent reads the LocalDB version from a run (`sqllocaldb info`) instead of guessing it.
- **Runners:** `windows-2022` and `ubuntu-24.04`, named explicitly.

## Done when

1. **The recordings are trustworthy.**
   - A Windows run restores `seed-snapshot` and sends the request set to the old app twice.
   - Both passes must be byte-identical before anything is committed.
   - Each recording keeps the status code, content type and body bytes.
   - `recordings/manifest.json` records the run URL, the app commit, the SHA-256 of the snapshot and a hash of every recording file.
2. **The request set covers the awkward cases, not just the happy path.** `recordings/requests.txt` includes at least:
   - every prefix in `seed/prefixes.txt` and every seeded ID (as spec 01 already checks)
   - `includePrerelease=true` and `false`, and `semVerLevel=2.0.0` and absent, on both endpoints
   - different casing of IDs and prefixes
   - `partialId` empty and missing
   - a prefix that matches nothing
   - a prefix that matches more than 30 IDs, so the cap is exercised
   - an unknown package ID
   - IDs and prefixes with dots, dashes, underscores, URL-encoded characters and trailing slashes
   - a request with an unsupported HTTP method (recorded, but see amendment A1)

   The request set comes from reading the old app's controller and routing code, with each group's source noted in a comment. Whatever the old app returns, including errors, is the expected answer.
3. **The new service passes against the recordings on Linux.** On `ubuntu-24.04`, the workflow:
   - starts the SQL Server container
   - restores the `seed-snapshot` backup into it
   - builds and starts the new service
   - sends every recorded request

   All responses must match. A mismatch report lists each difference.
4. **The new service answers from the database, not from the recordings.**
   - The service's build output and container must not include the recordings.
   - A second Linux job changes the restored database directly (adds a package version, unlists one, adds a new ID under an existing prefix). It then confirms the affected responses change in the way the data says they should.
5. **The comparator can fail.** A negative control serves one deliberately wrong response and confirms the comparison reports it and fails the job. A comparator that always passes proves nothing.
6. **Live parity on Windows.** On one `windows-2022` run, the old app and the new service run side by side against the same LocalDB database.
   - Every recorded request goes to both, and the answers must be byte-identical.
   - `mutate.ps1` then changes the data through the old app (an extra package push), and the comparison is repeated with requests the committed set doesn't contain. This shows parity isn't limited to the recorded cases.
7. **The new service writes nothing.**
   - It connects with a SQL login that has read-only rights (`db_datareader` only).
   - A check compares row counts and a checksum of the package tables before and after the full request set.
8. **Quality gates pass on every push.** Every gate in `docs/engineering-standards.md` that a tool can enforce runs in CI and fails the build: warnings as errors, analyzers, CSharpier, `dotnet format`, locked restore, NuGet audit, CodeQL, and the Stryker.NET mutation threshold. The old app's source and config diff (spec 01's check 7) stays empty.

## Approach

1. **Prove the database route first.** Before writing the service, check that the LocalDB backup restores into the SQL Server container and answers one query:
   - Do it on the Mac: download the `seed-snapshot` artifact with `gh`, restore it, query it.
   - Then do the same on a Linux runner.

   If the backup won't restore, record why in the run log and stop to report back. Don't work around it.
2. **Record.**
   - Extend `capture.ps1` and `compare.ps1` rather than starting a second format.
   - Each recording keeps the status, content type and body.
   - Headers that legitimately differ between two servers (such as `Date`, `Server` and `X-Powered-By`) are not compared. Each one is listed in `recordings/ignored-headers.txt` with a reason, the same way `evidence/01/config.diff` lists config changes.
   - Everything else is compared byte for byte.
3. **Build the service** in `service/`, following `docs/engineering-standards.md`.
   - The old app owns the database schema, so the service runs no migrations.
   - Any behaviour copied from the old app's code is noted with the source file it came from, so the run log can show where each rule came from.
4. **Local loop on the Mac.** Install the .NET SDK with Homebrew. Run SQL Server in Docker: x64 SQL Server under emulation on Apple silicon is unsupported but works, and the Linux runner is the supported check. Test changes against the recordings in seconds.
5. **Push to run the Linux checks.** Run Windows live parity at milestones, and once at the end.

## Guardrails

- **Recordings are read-only to the build agent.** Only the Windows recording workflow writes `recordings/`. Every run checks the recording hashes against the manifest, and fails if a file was changed by hand or by the agent.
- **No change to the old app.** Spec 01's source and config diff checks keep running.
- **Secrets.** The SQL login password is generated inside each run and masked. It is never committed.
- **Third-party actions** are pinned by commit SHA. The SQL Server image is pinned by digest.
- **Public repo.** Never commit personal details: no IPs, emails or account IDs.
- **Agent authorship is visible.** Commits carry the agent's co-author trailer, and the run log records which agent session did what.

## Amendments

Changes made after work started, each with its reason. The original wording above is kept so the change is visible.

**A1. Non-GET requests stay with the old app.**
- **What changed:** POST, PUT and DELETE to the two routes are still recorded, but they are excluded from the new service's parity checks (3 and 6).
- **Why:** the old app answers them with ASP.NET's developer-detail 404 page, because the recorder is a local client. That page embeds the framework build number and a stack trace. The new service would have to paste in framework bytes to match it.
- **Where these requests are checked instead:**
  - The new service answers them with `405` and `Allow: GET`. A test pins that behaviour.
  - In a strangler, routing is by method and path. The next spec's proxy sends only `GET` on these routes to the new service, and everything else to the old app. That spec's parity check covers these recorded requests end to end through the proxy.
- **This doesn't weaken the parity checks.** Each excluded record is listed by name in a committed exclusions file with this reason, and any other mismatch still fails.

**A2. A second data state covers prerelease and SemVer 2.0.0.**
- **The problem:** the spec 01 seed has no prerelease or SemVer 2.0.0 versions, so the `includePrerelease` and `semVerLevel` requests can't change any response. Spec 01's seed and evidence stay as they are.
- **What the recording workflow does now:**
  1. Records state A, the seed snapshot.
  2. Pushes a fixed list of real prerelease and SemVer 2.0.0 versions of already-seeded IDs through the old app's API. The list is in `seed/state-b.txt`. It includes at least one version with build metadata (`+`) and one with a dotted prerelease label.
  3. Snapshots the result as `state-b-snapshot`.
  4. Records the full request set again, as state B.
- **How the checks change:** checks 3 and 7 run against both states. Check 6 (live parity) also runs after the state-B pushes.

**A3. Undecided behaviour must be recorded.**
- **The problem:** a response the service chooses on its own isn't parity.
- **What to do:** add requests for blank or whitespace IDs, `+` in versions, and characters with special meaning in SQL `LIKE` (`%`, `_`, `[`, `~`) in prefixes. The service must then match whatever the old app does.

## Out of scope for this spec

- **The front proxy that routes these two endpoints to the new service and everything else to the old app.** That is the next spec, and it turns this side-by-side service into a real strangler.
- **Planted-bug checks.** Negative control 5 covers only the comparator.
- **Write endpoints, and unlist and relist.** Recording database changes belongs with these.
- **Search, OData feeds and the V3 API.**
- **The article.**

## Evidence produced

| Item | What's in it |
|---|---|
| GitHub Actions run history | The public record for every check above |
| `recordings/` | the request set, recorded responses, manifest and ignored-headers list |
| `service/` | the new service and its tests |
| `.github/workflows/` | the recording, Linux parity and Windows live-parity workflows |
| `evidence/02/run-log.md` | narrative log: version choices, database spike result, each failure and fix |
| `evidence/02/parity-report.md` | final counts per check, with links to the runs that produced them |
