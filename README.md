# nuget-harness

An experiment in moving part of a legacy web app to a new service with agents doing all the coding, where the only evidence anyone needs to trust is public CI runs.

The legacy app is [NuGetGallery](https://github.com/NuGet/NuGetGallery), the ASP.NET MVC 5 app behind nuget.org, at a pinned commit and unmodified. This repository runs it from nothing on a GitHub-hosted Windows runner and records how it answers two read endpoints (`GET /api/v2/package-ids` and `GET /api/v2/package-versions/{id}`). It then holds a new .NET 10 service to those recordings: the same status, content type and body bytes for every recorded request, from the same database. The few answers that come from the web server rather than the app are compared by status only, each listed with the spec amendment that allows it.

**Who wrote what.** No human wrote or reviewed the code. A human wrote and directed the specs in `specs/`. The code, the tests, the workflows and the evidence in `evidence/` were produced by AI agents, and each commit carries the agent's co-author trailer. Independent reviewer agents read the code; their findings and resolutions are in [`evidence/02/reviews.md`](evidence/02/reviews.md).

## How the claim is checked

| Tier | Where | What it proves | When it runs |
|---|---|---|---|
| Recordings | Linux runner | The new service, reading a restored copy of the seeded database, gives the recorded answers | Every push |
| Live parity | Windows runner | The old app and the new service, side by side on one live database, give identical answers, including after the data changes | By hand, at milestones |
| Recording run | Windows runner | The recordings themselves are correct and stable | When a recording input changes |
| Benchmark | Windows runner | Speed and database cost of both apps, under the same load on one machine; it measures and never fails on speed | By hand |

The flow:

```
record.yml       old app on Windows, seed snapshot restored, every request in recordings/requests.txt sent twice
  record job       both passes byte-identical, in two data states -> artifact "recording" (+ state B snapshot)
  commit job       artifact checked again -> release recordings-<run id>; recordings/ + manifest committed by the bot
new-service.yml  on every push, and when record.yml finishes on main; on Linux, SQL Server in Docker restored from the snapshot
  inputs           a push that changes a recording input skips the checks and waits for the re-record
  verify           recordings/ is byte for byte the release asset of the successful record.yml run the manifest names
  capture          every recorded request sent to the new service
  compare          every record identical, or status-only / excluded as listed in recordings/parity-exclusions.txt;
                   an approved difference (recordings/approved-differences.json) only reorders the recorded body,
                   which is then still compared byte for byte
live-parity.yml  old app and new service side by side on Windows, same requests plus new data and new requests
benchmark.yml    old app and new service in turn under the same k6 load, both over HTTPS -> evidence/02b/benchmark.md
```

## Where to look

- Specs: [`specs/01-old-app-running.md`](specs/01-old-app-running.md), [`specs/02-new-service-read-endpoints.md`](specs/02-new-service-read-endpoints.md) (with its amendments), and [`specs/02b-improve-behind-the-safety-net.md`](specs/02b-improve-behind-the-safety-net.md) (done: SemVer-ordered versions as an approved difference, a defined most-downloaded tie-break, EF Core LINQ queries, and a benchmark).
- Evidence: [`evidence/01/run-log.md`](evidence/01/run-log.md), [`evidence/02/parity-report.md`](evidence/02/parity-report.md) (every check with the run that produced it), [`evidence/02/run-log.md`](evidence/02/run-log.md), [`evidence/02/reviews.md`](evidence/02/reviews.md), [`evidence/02b/run-log.md`](evidence/02b/run-log.md), [`evidence/02b/benchmark.md`](evidence/02b/benchmark.md).
- The bar the code is held to: [`docs/engineering-standards.md`](docs/engineering-standards.md).

## Verify it yourself

Open the three runs listed at the top of [`evidence/02/parity-report.md`](evidence/02/parity-report.md): the recording run, the new-service run and the live-parity run. Each job summary states its checks and counts, and each run's artifacts hold the full reports (`out/checks/spec02-*.txt`).

To run the service's tests locally (needs the .NET SDK named in `service/global.json`, Docker, and the GitHub CLI):

```sh
cd service
dotnet test --project test/GalleryReadService.Tests              # unit and property tests
gh release download snapshots-v1 --repo iraritchiemeek/nuget-harness --pattern 'seed-snapshot-*.tar.gz'
mkdir -p snapshot && tar -xzf seed-snapshot-*.tar.gz -C snapshot
SEED_SNAPSHOT_DIR=$PWD/snapshot dotnet test --project test/GalleryReadService.IntegrationTests
```

## Layout

- `service/`: the new service and its tests.
- `recordings/`: the request set, the old app's recorded answers in two data states, the manifest, the ignored headers and the parity exclusions. Only the recording workflow writes the records and the manifest.
- `seed/`: the packages pushed into the old app (spec 01) and the further pushes that make state B and the live-parity data.
- `scripts/runner/`: the PowerShell harness. Most of it drives the old app on the Windows runner (build, setup, seed, snapshot, reset). The recording and comparison scripts (`capture.ps1`, `compare.ps1`, `verify-recordings.ps1`, `get-snapshot.ps1`, `secret-scan.ps1`, `common.ps1`) also run under PowerShell on Linux. The folder keeps its name because spec 01's evidence refers to it.
- `scripts/linux/`: the Linux-only parts: SQL Server in Docker, the database fingerprint, the data change and the negative control.

**Snapshots.** The database snapshots the checks restore are kept as assets of the [`snapshots-v1`](https://github.com/iraritchiemeek/nuget-harness/releases/tag/snapshots-v1) release, because workflow artifacts expire. `scripts/runner/get-snapshot.ps1` checks each one against the digest in `recordings/manifest.json` before anything restores it. The recordings are kept the same way: each recording run's commit job attaches the folder it commits to a release named `recordings-<run id>`, and `verify-recordings.ps1` compares `recordings/` with that asset file by file, and checks that the run is a successful `record.yml` run on `main` while GitHub still has the run. A release asset can be replaced by anyone who can push, so it is weaker evidence than a run artifact; a run artifact expires after 90 days.

## License

MIT for this repository's own files; see [`LICENSE`](LICENSE). NuGetGallery is licensed under Apache-2.0 and is not included here: the workflows check it out at the pinned commit.
