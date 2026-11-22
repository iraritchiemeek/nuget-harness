# Spec 03 reviews

Two independent reviewer agents with fresh context read the three patches as they stood from `6364af1`, against upstream at 06b7a81. R1 looked at correctness and security: it read the code and ran nothing. R2 looked at whether a maintainer would accept them: it read the code, the drafts and the linked runs. This file records each finding, how it was resolved, and the commit or run that resolved it.

Neither found a technical blocker. R2 raised two blockers outside the code (T1, T2). The patches they reviewed are superseded by `8c6e50d`, which holds the code fixes. The drafts they reviewed are superseded by `d8f775c`.

Status: T6 (the order of posting) is open, and is the owner's decision. T1 was settled by the owner on 2026-11-22. The revised patches and drafts have not had a second independent review. Every check ran again on `8c6e50d`: a [44980456732](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44980456732), b [44980465212](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44980465212), c [44980473424](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44980473424), all [44980481812](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44980481812).

## A. Version order

| # | Finding | Resolution | Commit or run |
|---|---|---|---|
| A1 | (R1, note) A stored version that can't be parsed makes the endpoint throw. | No change. Other code already parses the same column, and the pull request text says it. | none |
| A2 | (R1, optional) The test has no 4-part version. | `1.2.0.5` is in the test data, after `1.2.0` in the expected order. | 8c6e50d; run a |
| A3 | (R2) The pull request doesn't say why this order. | The first bullet says it. `AutocompleteDatabasePackageIdsQuery` sorts by ID only for a partial ID (a blank one sorts by downloads), so the text says "for a partial ID". | d8f775c |
| A4 | (R2) The 351-request sentence and the issue are too long. | Shortened. The repro commit, 63e6ee4, and that the query file is the same on `dev`, are kept. | d8f775c |

## B. Delete-symbols page

| # | Finding | Resolution | Commit or run |
|---|---|---|---|
| B1 | (R1, R2) The `absoluteLatest` special case keeps a fallback that prefers the latest stable version, which is not what the alias means elsewhere. | The special case and its test class are gone, and it gives a 404 (amendment U1). Both app rows: 200 before, 404 after. | 8c6e50d, ebe906f; run b |
| B2 | (R1) An empty version should count as no version. | It does. Backed by the `TheDeleteSymbolsMethodWithEmptyVersion` tests. They pass with and without the fix, and the wrong fix fails 14 of them. The app row `?version=` shows the latest version before and after, but may not reach the empty-string branch: MVC's binder probably turns an empty value into null (inferred, not read). | 8c6e50d; run b |
| B3 | (R1, R2, note) A non-owner now gets 404 instead of 403. | No change. The text already says it, and the POST action answers in that order. | none |
| B4 | (R1) Keep an unparsable version as well as a valid one that doesn't exist. | One theory, `Returns404IfVersionNotFound`, with `missing` and `2.0.0`. Both fail without the fix. | 8c6e50d; run b |
| B5 | (R2) The test is too heavy. | The theory is in `TheDeleteSymbolsMethodWithExactVersion` and uses its `CreatePackageService()`. `FilterLatestPackage` is set up to return a package: the class's own mock returns null, which would give a 404 without the fix. | 8c6e50d |
| B6 | (R2) "`Manage`'s tests show it is intended" is a bad argument, because this change replaces the same kind of test. | The text says #6931 is only about delete symbols. | d8f775c |
| B7 | (R1) Don't overstate the risk. | The text quotes the issue and makes no severity claim. | d8f775c |

## C. Manage packages page

| # | Finding | Resolution | Commit or run |
|---|---|---|---|
| C1 | (R1) The same method probably throws `ArgumentOutOfRangeException` when the fallback version is Staged, because `GetPackageStatusSummary` has no Staged case. | **Scoped out.** Read from the code, not run. #5675 is only about no versions. Not in the patch, and not claimed in the text. | none |
| C2 | (R2) Say how the state is reached. | The text says it: a hard delete of every version with `DeletePackagesRequest.DeleteEmptyPackageRegistration` unchecked, read from the code and not run. It also says the registration was inserted into the test database. | d8f775c |
| C3 | (R2) Disclose that the item's package link gives a 404, and that the request's email leads here. | Both are in the text. The run shows the 404. The email's links are read from the code: `PackageOwnershipManagementService` takes its confirm and reject links from `IUrlHelper` (`UrlHelperWrapper`), they go to the `...Redirect` actions, and those redirect to this page. | d8f775c; run c |
| C4 | (R2) The test is too long. | Shorter, with one normal and one empty request received, one empty request sent. One assertion on `Owners` is kept, for the factory's mapping. "Drop every request" still fails it. | 8c6e50d; run c |
| C5 | (R2) `CreateWithoutVersion` need not be public; the doc comment is long. | It is `internal`, and the comment is one line. | 8c6e50d |
| C6 | (R1, note) A try/catch around everything would pass the test. | No change. | none |
| C7 | (R2) Keep-or-omit is the one open question, so it goes last. | It is the last paragraph before the issue link. | d8f775c |

## T. All the texts

| # | Finding | Resolution | Commit or run |
|---|---|---|---|
| T1 | (R2) Wording of the authorship line in the drafts. | Owner decision, 2026-11-22: the drafts carry no authorship line (spec 03, amendment U3). |
| T2 | (R2) Upstream's CI fails on the HtmlSanitizer advisory, and the text should say so. | Each pull request says its run builds with NU1903 not treated as an error, and why. It links [upstream run 44770292233](https://github.com/NuGet/NuGetGallery/actions/runs/44770292233), whose "NuGetGallery build and test" and "Build artifacts" logs were read. Its pull request changes only `RemovedPackages.md`. | d8f775c |
| T3 | (R2) Remove "Is a pull request welcome?", and the comment drafts. | Done (amendment U2). The only question left is C's. | d8f775c, ebe906f |
| T4 | (R2) Remove "found by reading the open issues" from the posts. | Done. The run log says it. | d8f775c |
| T5 | (R2) Trim the evidence. | One line of totals with the run, then one or two sentences on the app. | d8f775c |
| T6 | (R2) Post B, then C, then A, one at a time, after upstream's CI is green. | **Owner decision, pending.** The spec's order (A, B, C) is unchanged. | none |
