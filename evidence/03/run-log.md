# Spec 03 run log

Spec: [`specs/03-upstream-fixes.md`](../../specs/03-upstream-fixes.md). Work by two Claude Code agent sessions, the second taking over from the first. All dates are 2026-11-22, times UTC. The reviews (check 7) are separate and not part of this log.

"Read" below means taken from that job's own log or artifact. "Inferred" is said where it applies.

## Result

| PR | Bug seen on the unpatched app | Checks 1 to 6 | Extra check | Final run |
|---|---|---|---|---|
| A, version order | yes | pass | pass | [44977396894](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44977396894) |
| B, delete-symbols page | yes | pass | pass | [44977402047](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44977402047) |
| C, manage packages page | yes | pass | pass | [44977407429](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44977407429) |
| all three together (check 6) | | pass | not run, by design | [44977413038](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44977413038) |

Nothing was dropped, and nothing has been posted to NuGetGallery. The patches have not changed since `6364af1`: every failure below was in the harness or in the restore of the unpatched base.

## Every run of `upstream-fix.yml`

| Round | Head | a | b | c | all |
|---|---|---|---|---|---|
| 1 | `6bf20ff` | [44974421907](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44974421907) failed | [44974425852](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44974425852) failed | [44974430433](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44974430433) failed | [44974434531](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44974434531) failed |
| 2 | `3d00513` | [44974965905](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44974965905) failed | [44974969763](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44974969763) failed | [44974973739](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44974973739) failed | [44974977698](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44974977698) failed |
| 3 | `eea3455` | [44976343570](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44976343570) passed | [44976347405](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44976347405) passed | [44976350648](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44976350648) passed | [44976353881](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44976353881) passed |
| 4 | `e9466a4` | [44977396894](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44977396894) passed | [44977402047](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44977402047) passed | [44977407429](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44977407429) passed | [44977413038](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44977413038) passed |

The `patches` job passed in every run.

### Round 1: every build failed in restore

17 jobs failed: four test jobs and the app job of each of a, b and c, and the two test jobs of all. Each job's log was read, and each has the same cause: `NU1903: Warning As Error: Package 'HtmlSanitizer' 9.0.892 has a known high severity vulnerability, https://github.com/advisories/GHSA-464h-4j8h-q5mf`, then `Restore failed`. In A's app job the unpatched build came from the cache, so it failed later, in the rebuild with the patch. See "The HtmlSanitizer advisory".

### Round 2: two harness bugs

- **All 14 test jobs** (four each for a, b and c, two for all), each log read: the build passed, then the audit check in `test-variant.ps1` failed. Its filter matched the text `NU1903` anywhere, and the compiler command lines in the log hold `/warnaserror-:NU1903`, because of the variable that relaxes it. The only real finding in each log is the known one. No test ran. The `compare` jobs were skipped.
- **A's app job:** both comparisons passed (351 of 351 in each state). The job failed on the negative control `unsorted`, which did fail the comparison on exactly the 162 planted records, but whose expected-detail pattern had two spaces where `compare.ps1` writes four. The control's pattern was wrong, not the comparison.
- **B's and C's app jobs** passed, inside runs that failed. These were the first reproductions of both bugs.

Fixes: `98913ae` (the pattern), `eea3455` (the audit check, see below).

### Round 3: passed, with a hole in check 5

All four runs passed. Reading the build logs then showed that the warning filter skipped warnings without a code (`ASPNETCOMPILER : warning :`, from the Razor views) and codes like `xUnit2009`, so a new one would not have been seen. MSBuild's own total was 78 in all eight logs of base and fix, so nothing had been missed. Fixed in `e9466a4`: the filter takes every form, and MSBuild's total is compared too.

### Round 4: the runs the drafts cite

All four passed, with the wider warning check. Test results are the same as in round 3.

## What each check showed (round 4)

`NuGetGallery.Facts` is 3,904 test methods on the base. All results are from upstream's own build command in Release (`build.ps1 -Configuration Release -SkipCommon -SkipJobs -SkipArtifacts`) on `windows-2025-vs2026`.

| | A | B | C | all |
|---|---|---|---|---|
| 1. applies alone, only its files | pass | pass | pass | pass |
| base: passed / skipped / failed | 11,825 / 2 / 0 | 11,825 / 2 / 0 | 11,825 / 2 / 0 | 11,825 / 2 / 0 |
| 2. tests only: failed | 1, the new test | 1, the new test | 1, the new test | |
| 3. wrong fix: failed | 1, the new test | 28, all in the null-version and `absoluteLatest` classes | 1, the new test | |
| 4. fix: passed / skipped / failed | 11,826 / 2 / 0 | 11,826 / 2 / 0 | 11,826 / 2 / 0 | 11,828 / 2 / 0 |
| 5. build warnings, base and fix | 78 and 78, none new | 78 and 78, none new | 78 and 78, none new | 78 and 78, none new |
| 6. all six orders give one tree | pass | pass | pass | pass |

- **The two skipped tests** are the same in every variant: `TheDisplayPackageMethod.OneSecondCacheTime` and `V3HasherTests.ProcessingTimesForSuccessfulAuthAndFailedAuthAreSimilar`.
- **Check 2 failures, as reported:**
  - A: `Assert.Equal() Failure: Collections differ`
  - B: `Assert.IsType() Failure`, expected `HttpNotFoundResult`, actual `ViewResult`
  - C: `System.ArgumentNullException : Value cannot be null. Parameter name: package`
- **B's `absoluteLatest` tests pass without the fix.** They pin today's behaviour, so check 2 expects that, and the wrong fix fails them.

### A, on the running app (63e6ee4)

| | State A | State B |
|---|---|---|
| Records compared, unpatched with patched | 351 | 351 |
| Different before the rule | 162 | 162 |
| Different after the `semver-order` rule | 0 | 0 |

- **Serilog:** unpatched `["1.4.128","1.3.30","4.4.0"]`, patched `["1.3.30","1.4.128","4.4.0"]`, in both states. `seed.ps1` pushes `seed/packages.txt` in order, which is the unpatched order. The run restored that seeded snapshot; it did not push again.
- **Negative controls** (state A): `unsorted` reported on its 162 records, `dropped` on 1, `normalised` on 1. Each failed the comparison for the planted reason.
- The patched checkout's source diff equals the patch byte for byte.
- The unpatched build came from the shared cache, as built on 2026-11-20. The app was not run at 06b7a81 for A. The query file is the same blob (`ded4709a`) at both commits.

### B, on the running app (06b7a81)

| Account | Request | Before | After |
|---|---|---|---|
| owner | a version that exists | 200, that version | 200, that version |
| owner | no version | 200, 4.2.0 (the latest) | 200, 4.2.0 |
| owner | 9.9.9, which doesn't exist | 200, 4.2.0 | 404 |
| owner | `absoluteLatest`, `ABSOLUTELATEST` | 200, 4.2.0 | 200, 4.2.0 |
| not an owner | a version that exists | 403 | 403 |
| not an owner | 9.9.9, which doesn't exist | 403 | 404 |

### C, on the running app (06b7a81)

| Step | Receiver of the request | Sender of the request |
|---|---|---|
| Unpatched, normal request only | 200 | 200 |
| Unpatched, plus a request for an ID with no versions | 500 | 500 |
| Patched | 200, both requests listed, both can be accepted | 200, both requests listed, only the normal one has "Manage Ownership" |
| The normal request, against the first step | identical | identical |
| Reject the request with no versions | 200, and it leaves the list | |
| Confirm a new one | 200, and the ID has two owners | |

- Both 500s are `ArgumentNullException: Value cannot be null. Parameter name: package`, at `PackageViewModelFactory.Setup`, called from `UsersController.CreateOwnerRequestsListItemViewModel`.
- For the ID with no versions, the package page and the manage page both answer 404 to the sender.
- **How the state was made:** an SQL insert of a registration with no versions, in the run's own database. Nothing was pushed and hard deleted.

## The HtmlSanitizer advisory

**The problem.** GHSA-464h-4j8h-q5mf (HtmlSanitizer before 9.0.967, high) was published on 2026-11-19, after the last commit on `dev`. Upstream pins 9.0.892 and treats warnings as errors, so NU1903 fails the restore of the unpatched base. Upstream's CI failed the same way in run 44770292233 on 2026-11-20 (read).

**What was relaxed.** The two jobs that build set `WarningsNotAsErrors: NU1903`, which MSBuild reads as a property. No upstream file is edited, and the audit stays on. On its own this would let through a high-severity finding on any package.

**What still fails.**
- [`audit.ps1`](../../scripts/upstream/audit.ps1) reads the log of every build and fails it unless its audit findings are exactly that advisory on HtmlSanitizer 9.0.892. It runs in the test jobs, and through `scripts/runner/build.ps1` in the app jobs, on both bases. In `gallery-build` that is before anything is cached.
- A log with no finding fails, because the audit must have run. Any other package, version, advisory or audit code (NU1900 to NU1999) fails.
- Every run starts with [nine controls](../../scripts/upstream/test-audit.ps1) of that check. Seven must fail it, and did.

**What the two bases report (read):** exactly the known finding. At 06b7a81 that is every test job and every rebuild. At 63e6ee4 it is A's rebuild with the patch, which changes no package reference.

**Limits.**
- On a cache hit the unpatched app isn't rebuilt, so nothing is audited for it in that job. The patched rebuild in the same job restores the same packages and is audited. In rounds 3 and 4 both bases came from the cache, so the check's path through `gallery-build` itself has not run.
- The cached 06b7a81 build was made in round 2 with NU1903 relaxed, before the check covered the app jobs. B's and C's round 2 logs show only the known finding (read).
- The cache holds unpatched builds only: the save step runs before the patch, and its key was hit in rounds 3 and 4, so nothing was saved.
- **A pull request would fail upstream's CI** until upstream moves HtmlSanitizer (inferred from their run above).
- The harness's other workflows that build 63e6ee4 don't relax NU1903. They pass while the cached build is hit. A new runner image changes the key, and their build would then fail (inferred).

Relaxing it was the first agent's decision. The orchestrator confirmed that a workaround is needed, and asked for the check on every build.

## Decisions

- **A: sorted in memory**, after `ToList()`, by `NuGetVersion.Parse`. SQL can't express the order, and one package's versions are already read into memory.
- **B: one condition on the fallback**: no version, or `absoluteLatest`.
- **B: 404 instead of 403.** For a version that doesn't exist, someone who can't manage the package now gets 404, because not found is decided before the permission check. Before, the fallback found the latest version and then refused it. `DeleteSymbolsPackage`, the POST, has the same order: 404, then 403. A reviewer may object that the GET now tells a signed-in non-owner whether a version exists, including one not listed to them.
- **B: links to the page** (source reading): `DisplayPackage.cshtml`, and the page's own version list. Both use a version that exists.
- **C: the fix came before the repro.** The spec says to reproduce first. C's fix was written and committed (`6364af1`) from source reading, before the bug had been seen on the running app. It was first seen in round 2. `check-c.ps1` stops before patching if both 500s are not there, so every run since has reproduced it first. For B, likewise, the fallback was first seen on the running app in round 2, after the fix was committed.
- **C: the request stays in the list**, rather than being left out, so that the receiver can act on it.
- **C: why `ListPackageItemViewModelFactory.cs` is touched.** The spec allows the view-model, view and URL helper files C needs. This file is the view-model's factory. `OwnerRequestsListItemViewModel` needs a `ListPackageItemViewModel`, and the helper that builds its `Owners` (`GetBasicUserViewModel`) is private to the factory. The new method is there so that `UsersController` doesn't build the view-model by hand. No view, view-model class or URL helper changed.
- **C: the sender can't cancel from the page.** `CanCancel` comes from a permission on a package version, and there is none, so every permission is left false. The "Manage Ownership" link it controls would lead to a 404. The spec says "rejected or cancelled", so this half is not met. The PR says so.
- **The issue search for A** (session one): four queries, no matching open issue. #5486 is about OData. Session two repeated it with four queries and read the titles of the first 12 results of each: none matches.
- **nuget.org**, for A's issue: at 02:44, the whole answers to `GET /api/v2/package-versions/Serilog` (185 versions) and `/Newtonsoft.Json` (53) were in SemVer order, oldest first. Two anonymous GETs, and nothing else is claimed.
- **The drafts were public before anything was tested.** `17a7b1b` claimed reproductions and test results nobody had seen. `13a55b5` removed them or marked them pending, before round 2 was read. Claims went back in only with a run from round 4.

## What backs each claim in the drafts

Runs: A is 44977396894, B is 44977402047, C is 44977407429. "Source" is upstream at 06b7a81.

| Draft | Claim | Backed by |
|---|---|---|
| all | the audit was relaxed for the tests | "The HtmlSanitizer advisory", above. A note above the line in each pull request draft; not in the text to post |
| A issue, PR | only the database fallback is affected | Source: `DefaultDependenciesModule.ConfigureAutocomplete`, lines 1592 to 1618 |
| A issue | no `OrderBy` | Source: `AutocompleteDatabasePackageVersionsQuery.cs`, line 46 |
| A issue | the Serilog answer at 63e6ee4, and that the file is the same on `dev` | run A, artifact `app-check-a`, `state-a-unpatched`; blob `ded4709a` at both commits |
| A issue | nuget.org's order | the two GETs above |
| A PR | the new test fails without the fix, and with an ordinal sort | run A, `test-comparison` |
| A PR | all of `NuGetGallery.Facts` passes | run A: 11,826 passed, 2 skipped, 0 failed |
| A PR | 351 requests in two data states, only the order differs | run A, app job: 351 of 351 in each |
| A PR | an invalid stored version would throw, as in the existing sorts | Source: `PackagesController.cs` line 1986, `ODataV2FeedController.cs` lines 693 and 714. Not run |
| B comment, PR | the page shows the latest version for one that doesn't exist | run B, app job |
| B PR | `absoluteLatest` shows the latest version, before and after | run B, app job |
| B PR | 404 instead of 403 for non-owners | run B, app job |
| B PR | the POST answers in that order | Source: `PackagesController.cs`, lines 2211 to 2222 |
| B PR | the new test fails without the fix; all of `NuGetGallery.Facts` passes | run B: 11,826 passed, 2 skipped, 0 failed |
| C comment, PR | the page answers 500, for sender and receiver | run C, app job |
| C comment, PR | the receiver can accept and reject | run C, app job |
| C PR | `ArgumentNullException` from `PackageViewModelFactory.Setup` | run C, app job |
| C PR | no "Manage Ownership" link, and `Manage` answers 404 | run C, app job |
| C PR | who can accept is checked as before | Source: `UsersController.cs`, line 1772, unchanged by the patch |
| C PR | the new test fails without the fix; all of `NuGetGallery.Facts` passes | run C: 11,826 passed, 2 skipped, 0 failed |
| all | AI agents wrote the fix and tests | [README](../../README.md) |
| all | a human approved posting | **not yet true.** It must be true before anything is posted |

## Privacy

B's and C's app jobs scan their outputs before uploading, for each account's password and API key and for the session cookies: two accounts and four cookie values, none found. A's app job makes no account.
