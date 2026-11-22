# Draft pull request for PR A (not posted)

Branch name: `Bug-ISSUE`. Replace `ISSUE` with the number of the issue posted from `a-issue.md`. Everything below the line is the text to post.

Not to be posted before the repository owner approves it, after the independent review. The backing of each claim is in [`evidence/03/run-log.md`](../evidence/03/run-log.md).

Not in the text, and part of what backs it: every build behind these results had NuGet's NU1903 audit warning not treated as an error, because the HtmlSanitizer advisory fails the restore of unpatched `dev`. Each build still fails unless that advisory is its only audit finding. A pull request would fail upstream's CI until upstream moves the package (inferred).

---

**Title:** Sort database package-versions results by SemVer

Sort database package-versions results by SemVer

* When no search service is configured, `AutocompleteDatabasePackageVersionsQuery` returned versions in no defined order. It now returns them oldest first, sorted in memory by `NuGetVersion`. The strings are returned as stored. Galleries with a search service configured don't use this class.
* Adds a test with versions stored out of order. It fails without the fix, and with an ordinal string sort.
* Known effect: a stored version that isn't a valid NuGet version would now throw, where before it was returned. The sorts in `PackagesController` and `ODataV2FeedController` already behave this way.

All of `NuGetGallery.Facts` passes. A running gallery's answers to 351 requests were compared before and after the change, in two data states: only the order of versions differs. That comparison ran at 63e6ee4, where the query file is the same as on `dev`. [Test run](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44977396894).

AI agents wrote the fix and the test, and a human approved posting them.

Addresses https://github.com/NuGet/NuGetGallery/issues/ISSUE
