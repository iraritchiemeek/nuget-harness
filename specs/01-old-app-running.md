# Spec 01: Get the old app running

## Goal

Get the current NuGetGallery (the code behind nuget.org) running with real packages in it, and answering API requests. It runs on GitHub's hosted Windows machines (GitHub Actions), from a clean machine every time.

This is the "before" half of every later comparison. The new service will be compared against this running app, so it has to be:

- **Repeatable.** Every run starts from a fresh machine, so "it works" means "it works from nothing".
- **Resettable.** The data can go back to a known state on command.
- **Untouched.** No changes to the old app's source code. Config changes are allowed, but every one is recorded as a diff.

No human writes or reviews code at any stage. Every claim is backed by a public run log anyone can open.

## Why GitHub Actions, not a cloud server

The first attempt used an AWS Windows server. AWS blocked server launches on the account and needs a support ticket to clear it, so the run is recorded in `evidence/01/run-log.md`. GitHub's `windows-2022` runner already has everything the project's README asks for:

- **Visual Studio 2022 Enterprise**, with the web workload, IIS Express, the .NET Framework 4.7.2 targeting pack, and SQL LocalDB
- **.NET SDK 8.0.319**, which satisfies the repo's `global.json` (8.0.318 or newer)
- **Admin rights**, which the setup script needs

So the old app can run exactly as Microsoft documents it, with no database or hosting changes.

## Pinned versions

- **App:** https://github.com/NuGet/NuGetGallery (Apache-2.0), commit `63e6ee4202b441e1c904d6f78fc7b070f36bc24f` (main, 2026-11-11). If that commit won't build, an earlier one may be used, with the reason in the run log.
- **Runner:** `windows-2022`, named explicitly, not `windows-latest`.

## Done when

Each check runs inside the workflow and saves its output as a run artifact. A summary is written to the run's summary page.

1. **Search by prefix works.** `GET /api/v2/package-ids?partialId=<prefix>` returns exactly the expected seeded IDs.
   - The prefixes must match fewer than 30 seeded IDs, because the endpoint caps its results at 30.
   - An empty list counts as a fail, even with a 200 status.
2. **Version lookup works.** `GET /api/v2/package-versions/<id>` returns the versions that were pushed for that package. Expected values come from each package's nuspec file.
3. **Pushed packages are actually live.** A check confirms they show as listed and available, not stuck waiting on validation.
4. **Seeding is scripted.** One script does all of this, with no browser and no clicking:
   - creates the user account
   - creates an API key through the site's form
   - pushes the packages
5. **Reset is exact.** Restoring the database backup and package store, then repeating the same requests, gives byte-identical responses.
6. **Rebuild needs no hands.** True by construction: every run starts from a clean machine. Any manual step would show up as a failed run.
7. **The config diff is published.** `evidence/01/config.diff` lists every config change with a one-line reason. It is ideally empty. The source code diff must be empty.

## Approach

1. **Prove the route first, before anything else.** Run a minimal workflow:
   - check out the pinned commit
   - `build.ps1 -SkipJobs -SkipArtifacts`
   - `tools/Setup-DevEnvironment.ps1`
   - start IIS Express
   - `curl` one `package-ids` call

   Any response from the app proves the route.
2. **Seed.** Put a fixed list of a few hundred real public packages in `seed/packages.txt`. Download them from nuget.org and push them through the app's API. Include several shared prefixes so the search checks mean something.
3. **Snapshot and reset.** After seeding, back up the database and copy the package store, and save both as an artifact. The `reset` script restores them. Later jobs restore from this instead of reseeding.
4. **Keep the loop short.**
   - Cache NuGet packages and build output between runs.
   - Trigger runs with `workflow_dispatch`, and watch them with `gh run watch`.
   - Don't use third-party remote-shell actions unless you're stuck.

## Guardrails

- **Secrets.** The API key and the test account password are generated inside the run and masked with `::add-mask::`. They are never committed or printed.
- **Third-party actions** are pinned by commit SHA.
- **Public repo.** Never commit personal details: no IPs, emails or account IDs.

## Out of scope for this spec

- the new .NET service
- the parity harness
- planted-bug checks
- unlist and relist

## Evidence produced

| Item | What's in it |
|---|---|
| GitHub Actions run history | The public record. Each run logs every command and result. |
| `.github/workflows/` | the workflow files |
| `scripts/` | build, setup, seed, reset and check scripts |
| `seed/packages.txt` | the fixed package list |
| `evidence/01/run-log.md` | a narrative log covering both the AWS attempt and the runner route |
| `evidence/01/config.diff` | config changes, with reasons |
