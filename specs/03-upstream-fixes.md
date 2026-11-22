# Spec 03: Three small fixes for NuGetGallery

## Goal

Prepare three separate pull requests to NuGetGallery, each fixing one bug, each with public runs showing the bug before the fix and its absence after.

| PR | Bug | Issue | Found by |
|---|---|---|---|
| A | `package-versions` returns versions in no defined order when no search service is configured | new, to be posted first | this harness (spec 02b) |
| B | The delete-symbols page shows the latest version when the requested version doesn't exist | [#6931](https://github.com/NuGet/NuGetGallery/issues/6931) | reading open issues |
| C | The manage packages page fails when there is an ownership request for an ID with no versions | [#5675](https://github.com/NuGet/NuGetGallery/issues/5675) | reading open issues |

The three are independent. Any one can be dropped, posted or declined without affecting the others. If B or C turns out not to be a bug on the upstream base, that is a valid result: log it, drop it, and don't look for a replacement.

The spec ends with tested patches and drafted text. Nothing is posted to NuGetGallery until the repository owner approves it.

## Pinned versions

- **Upstream base:** `dev` at `06b7a81ab7bb92d5009082789b9e4ec5c81586cb`. If `dev` moves before a PR is submitted, rebase that patch, re-run its checks, and log the new commit.
- **Harness base (A only):** `63e6ee4202b441e1c904d6f78fc7b070f36bc24f`, as in specs 01 and 02.
- **Runners:** `windows-2025-vs2026` for upstream's build and tests (what upstream's CI uses), `windows-2022` for running the app.

## PR A: version order

### The bug

`GET /api/v2/package-versions/{id}` has two implementations, chosen by `DefaultDependenciesModule.ConfigureAutocomplete`:

| When | Class | Order of versions |
|---|---|---|
| A search service is configured | `AutocompleteServicePackageVersionsQuery` | Whatever the search service returns |
| No search service is configured (local development, some self-hosted galleries) | `AutocompleteDatabasePackageVersionsQuery` | None: the query has no `OrderBy` |

- **nuget.org:** on 2026-11-22, the parts of the answers read for `Serilog` and `Newtonsoft.Json` were in SemVer order, oldest first.
- **The database query:** our recording for `Serilog` is `["1.4.128","1.3.30","4.4.0"]`, which is push order.

This is a bug in the fallback, not on nuget.org, and the issue and PR must say so. The query file is the same blob (`ded4709a`) at our pinned commit, on `dev` and on `main`, as checked on 2026-11-22. Searches of the issue tracker found no open issue for it.

### The change

1. **`src/NuGetGallery/Queries/AutocompleteDatabasePackageVersionsQuery.cs`**: sort the result after `ToList()`, by `NuGetVersion`, oldest first.
   - Sort in memory, because SQL can't express SemVer order. One package's versions are already all read into memory.
   - Return the version strings exactly as stored. Don't normalise them.
   - Follow the existing style: `PackagesController.cs` and `ODataV2FeedController.cs` already sort by a `NuGetVersion` parsed from `Version`.
2. **`tests/NuGetGallery.Facts/Queries/AutocompleteDatabasePackageVersionsQueryFacts.cs`**: one test that stores versions out of order and asserts the exact list returned. The data must defeat a plain string sort (`1.10.0` and `1.2.0`), and cover prerelease labels (`2.0.0-beta.2` and `2.0.0-beta.10`) and a release after its own prereleases (`2.0.0`).

**Known effect, stated in the PR:** a stored version that isn't a valid NuGet version would now throw, where before it was returned. The gallery validates versions on push, and the existing sorts behave the same way.

**Wrong fix the test must reject:** an ordinal string sort.

### Extra check: the harness

On one `windows-2022` runner, in both data states:
- Capture every request in `recordings/requests.txt` from the unpatched app, then from the patched app.
- Compare with **no exclusions**, and only the existing `semver-order` rule applied. Every other record must be byte-identical.
- At least one record must have changed before the rule was applied, so the check can't pass by accident.
- The patched checkout's source diff equals `upstream/a-version-order.patch` exactly.
- **Negative controls:** the order left unsorted, a version dropped from a list, and a version string normalised must each fail the comparison, for the right reason.

## PR B: delete-symbols page

### The bug

`PackagesController.DeleteSymbols(id, version)` looks for the exact version. If it isn't there, it falls back to the latest version, on a page whose purpose is deletion. The issue asks for a 404 instead, because the fallback "could lead to unintentional deletions".

### The change

1. **`src/NuGetGallery/Controllers/PackagesController.cs`**: when a version was given and isn't found, return not found. With no version, keep falling back to the latest.
   - **Check `absoluteLatest` first.** `VersionRouteConstraint` also accepts `LatestPackageRouteVerifier.SupportedRoutes.AbsoluteLatestUrlString` as a version. Run the unpatched app with it, and keep whatever it does today, with a test if it reaches the fallback.
   - Find every link to this page in the source, and confirm none relies on the fallback for a missing version.
2. **`tests/NuGetGallery.Facts/Controllers/PackagesControllerFacts.cs`**: `TheDeleteSymbolsMethodWithMissingVersion` pins today's fallback, so it is replaced by a test that expects a 404. The PR says so and quotes the issue. The exact-version and null-version tests stay as they are.

`Manage` has the same fallback, but its tests show it is intended. It is not changed.

**Wrong fix the tests must reject:** returning 404 when no version was given.

### Extra check: the running app

On a seeded app, signed in as the package owner, compare before and after the fix:

| Request to the page | Before | After |
|---|---|---|
| a version that exists | 200, that version | unchanged |
| no version | 200, latest version | unchanged |
| a valid version that doesn't exist | 200, latest version | 404 |

## PR C: manage packages page

### The bug

`UsersController.CreateOwnerRequestsListItemViewModel` calls `FindPackageByIdAndVersion` for each ownership request and passes the result on without a null check. `PackageViewModelFactory.Setup` throws `ArgumentNullException` for a null package. The issue says the page returns a 500 when an ID in a request has no versions left, for example after they were all hard deleted.

**Reproduce it first**, on the running app at the upstream base. If the page doesn't fail, drop this PR.

### The change

- **Preferred:** keep the request in the list, using what the request itself knows (the registration's ID, the two users), so it can still be rejected or cancelled. The view-model, `Packages.cshtml` and the URL templates all read `Package`, so each use is checked.
- **Fallback:** if that needs more than a small change, leave requests with no versions out of the list. The issue doesn't say which behaviour is wanted, so the PR says which was chosen and why, and offers the other.
- Permissions must not widen. A user who couldn't accept, cancel or manage the request before must not be able to after.
- **Test:** `ThePackagesAction` in `UsersControllerFacts.cs` gets a case with one request for an ID with no versions and one normal request. The page's model builds, and the normal request is unchanged. Both received and sent requests are covered.

**Wrong fix the test must reject:** dropping every request when one has no versions.

### Extra check: the running app

Two accounts, one normal ownership request, and one for a registration with no versions, set up in the run's own database. Before the fix, the page fails. After it, the page returns 200 and shows the normal request. The check covers the receiving account and the sending account.

## Checks for every PR

Each PR is done when all of these pass, plus its extra check above:

1. **One patch, only its files.** Committed under `upstream/` as `a-version-order.patch`, `b-delete-symbols.patch` and `c-owner-requests.patch`. Each applies cleanly to the upstream base on its own, and a check fails if it touches a file not named in its section. C may also touch the view-model, view and URL helper files it needs, each listed in the run log with the reason.
2. **The new tests fail without the fix.** With only the test files patched, the solution compiles and the new tests fail on the assertion or exception that describes the bug. No other test changes result.
3. **The wrong fix fails.** With the fix replaced by the wrong one named above, a test fails.
4. **All of `NuGetGallery.Facts` passes with the fix.** Results are compared with the unpatched base in the same run. A test that already failed on the base is listed by name, and no other failure is allowed.
5. **A clean Release build,** which also compiles the Razor views, with no new warnings.
6. **All three together.** The patches apply in any order, and the full test project passes with all three.
7. **Independent review.** For each patch, reviewer agents with fresh context read the patch, its issue, upstream's `CONTRIBUTING.md` and `.github/copilot-instructions.md`, and the code around the change. One checks correctness and security, the other whether a maintainer would accept it. Findings and resolutions go in `evidence/03/reviews.md`.
8. **The draft is ready.** Under `upstream/`, one pull request draft per fix, following upstream's template. A also needs an issue draft, filling in the self-hosted issue template, because upstream doesn't accept a pull request without an issue. B and C get a short draft comment for their existing issue, as `CONTRIBUTING.md` asks. Every claim is backed by a linked run or a line of upstream's code.

## Also in this spec

**The README is corrected.** It states that the two migrated endpoints are served by a search service when one is configured, and that the harness migrates the database fallback. The benchmark report says the same next to its database figures.

## Approach

1. Build all three together, and run their checks in parallel. A problem in one doesn't hold up the others.
2. For each fix: reproduce the bug, write the test and see it fail, then write the fix.
3. One workflow, `upstream-fix.yml`, run by hand with the PR's letter as its input.
4. **Never let a patched build reach the shared build cache.** `gallery-build` keys its cache on the commit alone, so a patched build saved under that key would poison every other workflow.
5. Reuse `capture.ps1`, `compare.ps1`, the account and sign-in script, and `recordings/approved-differences.json` as they are. B and C build the app at the upstream base, so first prove that the existing setup scripts work there unchanged.

## Submitting (needs the owner)

Nothing here happens without the owner's explicit approval of that PR, after reading its drafts. Approval of one is not approval of the others.

1. **A:** post the issue, and put its number in the PR. **B and C:** check the issue is still open with no linked PR, then post the comment.
2. Fork NuGetGallery once. Push one branch per PR, named after its issue, from `dev`, with one commit. Each commit's diff must equal its patch.
3. Open each PR against `dev`. Recommended order: A, then B, then C, with time for maintainers to respond to the first before the next.
4. The owner signs the contributor licence agreement if upstream's check asks for it. An agent must not.
5. Any reply to a maintainer is drafted by an agent and approved by the owner before it is posted.

**What the text must be honest about:**
- AI agents wrote the fix and tests, and a human approved posting them.
- A affects the database fallback. Make no claim about nuget.org beyond the order seen on the live endpoint.
- B and C were found by reading the issue list, not by the harness.
- Keep it short: the bug, the fix, how it was tested, any known effect. One link to the evidence, and no pitch for this repository.

## Guardrails

- `recordings/` isn't touched, and no approved difference is added or widened.
- If an app check shows a difference the spec doesn't expect, stop and report it. Don't exclude it.
- B and C only ever run against the run's own local app. Never sign in to, or send a write to, nuget.org or any NuGet test site.
- No personal details, session cookies or API keys in any file, commit, log or draft. Commits use a GitHub no-reply address.
- `main` stays green.
- No unrelated clean-up in any patch, however tempting.

## Evidence produced

| Item | What's in it |
|---|---|
| `upstream/` | three patches and the drafts |
| `.github/workflows/upstream-fix.yml` | the checks |
| `evidence/03/run-log.md` | every run, decision and failure, with links |
| `evidence/03/reviews.md` | reviewer findings and resolutions |

## Out of scope

- the front proxy
- **#9514 (credential lookup):** considered and dropped. `UserService.FindByUsername` already includes every credential when it loads the signed-in user, so changing the lookups alone would save nothing.
- **#6797 (delete package page):** considered and dropped. That page was merged into `Manage`, where the fallback is tested behaviour.
- **#4951 (client version order):** considered and dropped. The live page sorts correctly.
- getting any pull request merged, which is up to its maintainers
