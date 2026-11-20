# Spec 01 run log

All commands run from the operator Mac with `--profile nuget-harness`, region ap-southeast-2.
Times are UTC. Raw script output is in `evidence/01/logs/`.

## 2026-11-19 (UTC): session 1

### Step 0: orientation (read-only)
- `aws sts get-caller-identity --profile nuget-harness`: user `nuget-harness-agent`, account <account-id>.
- Base AMI: `aws ssm get-parameter --name /aws/service/ami-windows-latest/Windows_Server-2025-English-Full-Base` gave `ami-0dcf85379b0471a5d`.
- Default VPC `vpc-09d90e9d8b1de0160`. No instances existed before this run.
- I shallow-fetched NuGetGallery at `63e6ee4202b441e1c904d6f78fc7b070f36bc24f` into a scratch folder on the Mac to read it. Nothing was copied into this project. Findings that affect the plan:
  - The Validation DB context is registered only when `Gallery.AsynchronousPackageValidationEnabled` is true. Web.config sets it to `false`, so the Validation database should not be needed to boot. This still has to be confirmed on a running app.
  - `AsynchronousPackageValidationEnabled=false` should make pushed packages `Available` at once. This also still has to be confirmed (done-when 3).
  - `/api/v2/package-ids` (SQL fallback) returns at most 30 IDs. It excludes prerelease and SemVer2 versions by default and counts only `Available` and `Listed` packages.
  - `/api/v2/package-versions/{id}` returns `Package.Version`, which is the original version string from the nuspec, not the normalized one.
  - `Gallery.RejectSignedPackagesWithNoRegisteredCertificate=false`, so packages that nuget.org has repository-signed should be accepted.
  - `global.json` requires .NET SDK 8.0.318 with `rollForward: latestMajor`.

### Step 1: SSH key. Result: done
- `ssh-keygen -t ed25519 -N "" -C nuget-harness -f ~/.ssh/nuget-harness`
- `scripts/provision.sh` imported it as EC2 key pair `nuget-harness` (`key-055df88ca1ce04013`).

### Step 2: security group. Result: done
- `scripts/provision.sh` created `sg-08d3d07984aa44233` in the default VPC.
- It revokes all inbound rules, then adds exactly one: tcp/22 from <my-ip>/32 (from checkip.amazonaws.com). Tagged Project=nuget-harness.

### Step 3: launch. Result: failed twice, then blocked
- **Attempt 1.** Log: `logs/provision-1.log`. Error: `An error occurred (Unsupported) when calling the RunInstances operation: ED25519 key pairs are not supported with Windows AMIs.`
  - Fix: the instance now launches without `--key-name`. `provision.sh` substitutes the ed25519 public key into the user-data (`.state/userdata.rendered.ps1`), and the user-data writes that key to `administrators_authorized_keys` instead of fetching it from IMDS.
  - IMDSv2 is still required at launch (`HttpTokens=required`).
  - This deviates from the brief, which asked for the key to come from IMDS. The deviation is forced: IMDS only serves keys attached through `--key-name`.
- **Attempt 2.** Log: `logs/provision-2.log`. Error: `An error occurred (Blocked) when calling the RunInstances operation: This account is currently blocked and not recognized as a valid account. Please contact https://support.console.aws.amazon.com/support/home?region=us-east-1#/case/create?issueType=customer-service&serviceCode=account-management&categoryCode=account-verification if you have questions.`
- **Same call with `--dry-run`.** Result: `DryRunOperation: Request would have succeeded`. So IAM allows the launch, and the block is at account level, not from the IAM policy or the budget freeze.
- **Attempt 3** (one retry, about 25 s later). Log: `logs/provision-3.log`. Same `Blocked` error.

### Status: blocked, needs a human
EC2 `RunInstances` is refused for the whole account with error code `Blocked` (account verification). Only the account owner can clear this, through AWS Support or account verification. No agent-side workaround exists. Work stops here, as the brief requires.

- **Resources created (both free):** key pair `nuget-harness`, security group `sg-08d3d07984aa44233`.
- **Not created:** no instance and no volume.
- **To resume:** once the account is unblocked, re-run `scripts/provision.sh`. It is idempotent: it re-uses the key pair and security group, and re-points the ingress rule at the current IP.

## 2026-11-20 (UTC): session 2, GitHub Actions `windows-2022` runner

AWS was not touched in this session. The AWS scripts stay in `scripts/` for the record.

Everything below ran in the public workflow `.github/workflows/old-app.yml` (job `old-app`, `runs-on: windows-2022`), triggered by pushes to `main`. Each run's log, step summary and artifacts are the evidence. Scripts are in `scripts/runner/`.

### Runs

| Run | Result | Wall time | What it showed | Fix that followed |
|---|---|---|---|---|
| [1](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44644294670) | fail | 0:48 | Restore failed: `Version 11.0.100 of the .NET SDK requires at least version 18.7.0 of MSBuild. The current available version of MSBuild is 17.14.60.43110.` The gallery's `global.json` (8.0.318, `rollForward: latestMajor`) picks the newest SDK on the image (11.0.100); VS 2022 ships MSBuild 17.14. | Move SDKs newer than major 8 out of `C:\Program Files\dotnet\sdk` for the run (runner change, not app change). |
| [2](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44644940741) | fail | 0:43 | `Failed to find .csproj files found in solution ...\NuGetGallery.Aspire.slnx`. `build\common.ps1` lists projects with `dotnet sln list`, which cannot read `.slnx` on SDK 8. | Keep SDK 9 too (park majors above 9). The gallery folder then resolves SDK 9.0.321. |
| [3](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44645164897) | fail | 5:38 | **Route proven.** `build.ps1 -SkipJobs -SkipArtifacts` passed in 3:38, `Setup-DevEnvironment.ps1` passed (site registered, SSL bound, both databases migrated), IIS Express answered `GET /api/v2/package-ids?partialId=a` with `200 []`. The next step then got `Failed to connect to localhost:443`: the runner kills processes a step leaves behind when the step ends. | Start IIS Express through WMI (`Win32_Process.Create`) so it is outside the step's process tree, with `/config:` passed explicitly. |
| [4](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44646133434) | fail | 5:47 | IIS Express now outlives its step. Registration `POST /account/register` returned 302, but `/account/apikeys` also returned 302. | Log status, `Location` and cookie names (never values). |
| [5](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44647061481) | fail | 5:07 | Registration worked (302 to `/account/Thanks`, session cookie set). `/account/apikeys` redirects everyone to `/account/trustedpublishing?fromApiKeys=true` unless `forceApiKeys=true` is passed, which is what the Trusted Publishing page's link sends. | Request `/account/apikeys?forceApiKeys=true`. |
| [6](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44647778063) | fail | 0:52 | First build-cache hit, so `build.ps1` was skipped. `Setup-DevEnvironment.ps1` then failed: `Cannot find path 'C:\Users\runneradmin\.nuget\packages\EntityFramework\6.5.1\tools\net45\any\ef6.exe'`. The separate NuGet cache had never been saved, because `actions/cache` only saves when the whole job is green. | Put `~/.nuget/packages/entityframework` into the build cache, and drop the separate NuGet cache. |
| [7](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44647938416) | fail | 7:03 | Cache miss, so a full build ran. Form login and API key creation worked, but all 421 pushes got `403 The specified API key has expired.` The shipped `flags.json` enables `NuGetGallery.ApiKeyReduction`, and `ApiKeyReductionPolicy` caps any key lasting more than 30 days at 2026-11-01. A 365-day key is therefore expired when it is created. | Create the key with an 8-day expiry, one of the form's own choices. |
| [8](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44648938320) | fail | 8:01 | 420 of 421 pushed. `Nito.AsyncEx 0.13.0` got `400 Invalid package version for a dependency with id 'Microsoft.Bcl.Async' in package 'Nito.AsyncEx.0.13.0': ''` (its nuspec has an empty dependency version). This run also missed the build cache, because it landed on a different runner image (`win22-20261112.366.7` vs `win22-20261116.370.1`). | Drop that one line from `seed/packages.txt`, leaving 420 versions of 148 IDs. |
| [9](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44650025717) | fail | 3:29 | All 420 pushed in about 1 minute. `check.ps1` failed with `The property 'Count' cannot be found on this object`: PowerShell unrolled a one-element JSON array into a scalar under strict mode. | Wrap the parsed responses in `@()`. |
| [10](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44650564188) | fail | 3:00 | Checks 1 to 3 all passed. The snapshot step exited 1 only because robocopy returns 1 when it copies files successfully. | Reset `$LASTEXITCODE` after the robocopy success check. |
| [11](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44651015255) | **pass** | 3:28 | All seven done-when checks pass. | |

### Done-when results (run 11)

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | package-ids by prefix | pass | 31 of 31 prefixes return exactly the expected seeded IDs. Each prefix matches 2 to 16 IDs, and an empty list counts as a fail. See `check-outputs/checks/check1-package-ids.txt`. |
| 2 | package-versions | pass | 148 of 148 IDs return exactly the versions pushed, as written in each nuspec. See `check2-package-versions.txt`. |
| 3 | pushed packages are live | pass | 420 of 420 rows in `Packages` are `PackageStatusKey = 0` (Available) and `Listed = 1`. Checks 1 and 2 also only return Available and Listed packages. See `check3-available-listed.txt`. |
| 4 | seeding is scripted | pass | `seed.ps1` uses curl with a cookie jar and scraped antiforgery tokens, with no browser. It registers through the sign-up form, creates the API key through the API keys form (`GenerateApiKey`), downloads from nuget.org's flat container, and pushes with `PUT /api/v2/package`. |
| 5 | reset is exact | pass | Pushing one extra package (`Serilog.Sinks.Trace 4.0.0`) changed 2 responses. After `reset.ps1` (database restore plus package store replacement), all 180 captured responses are byte-identical (SHA-256) to the post-seed ones. See `check5-reset.txt`. |
| 6 | rebuild needs no hands | pass | Every run starts on a fresh hosted runner, and no step is manual. |
| 7 | config diff published, source diff empty | pass | `git diff HEAD` in the gallery checkout is empty, and `evidence/01/config.diff` has no hunks. See `check7-source-diff.txt`. |

Artifacts in each green run:
- `check-outputs`: check files, the raw responses, `seed/expected.json`, `seed/push-results.tsv`, and IIS Express and LocalDB diagnostics.
- `seed-snapshot`: `NuGetGallery.bak`, `SupportRequest.bak`, the `Files/` package store and `expected.json`. `reset.ps1 -Dir <unzipped artifact>` restores it, including on a fresh machine (it uses `RESTORE ... WITH MOVE`).

### Config changes

None. The app runs on its shipped `Web.config`, `flags.json` and `global.json`. Three behaviours were met by choosing request values or runner state instead of editing config:
- parking newer .NET SDKs
- `forceApiKeys=true`
- the 8-day key

These are listed in `evidence/01/config.diff` as runner-side notes.

### Secrets and public data

- The account password and the API key are generated inside the run and masked with `::add-mask::`.
- The cookie jar, form bodies and responses are kept in `$RUNNER_TEMP`, which is never uploaded.
- The account email is the placeholder `seeduser@example.com`.
- The public `seed-snapshot` artifact contains that account and the hashes of its password and API key. The key itself expires 8 days after creation.

### Loop length and caching

- **Build-output cache.** `src/NuGetGallery` (without `obj`) plus the EntityFramework NuGet package are saved right after a build. The cache key is the pinned SHA plus the runner image version. On a hit, `build.ps1` is skipped.
- **Build cost.** A build costs 3:28 (run 7) to 4:24 (run 8). Restoring the cache takes about 2 s.
- **Full run times.**
  - Green run with both caches hit (run 11): 3:28.
  - Full run with a cold build cache: about 7 to 8 minutes.
- **Remaining steps** on a warm run:
  - setup: about 55 s
  - first response: about 27 s
  - seed: about 45 s with the seed-package cache, about 80 s without
  - checks, snapshot and reset: about 45 s
- **Runner images are mixed during a rollout.** Two image versions (`20261112.366.7`, `20261116.370.1`) appeared within an hour, so the image-keyed cache misses on whichever image a run lands on first.
- **Seed packages** are cached separately, keyed on the hash of `seed/packages.txt`, and saved right after a successful seed.

Runs used in this session: 11 (10 failed while iterating, 1 green).
