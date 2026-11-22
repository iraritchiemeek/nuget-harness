# Draft pull request for PR A (not posted)

Branch name: `Bug-ISSUE`. Replace `ISSUE` with the number of the issue posted from `a-issue.md`. Everything below the line is the text to post; the backing of each claim is in [`evidence/03/run-log.md`](../evidence/03/run-log.md).

---

**Title:** Sort database package-versions results by SemVer

Sort database package-versions results by SemVer

* When no search service is configured, `AutocompleteDatabasePackageVersionsQuery` returned versions in no defined order. It now returns them oldest first, sorted in memory by `NuGetVersion`. The strings are returned as stored. Galleries with a search service configured don't use this class.
* Adds a test with versions stored out of order, which an ordinal string sort would fail.
* Known effect: a stored version that isn't a valid NuGet version would now throw, where before it was returned. The sorts in `PackagesController` and `ODataV2FeedController` already behave this way.

Tested with all of `NuGetGallery.Facts`, and by comparing a running gallery's answers to 351 recorded requests before and after the change: only the order of versions differs. [Test runs](https://github.com/iraritchiemeek/nuget-harness/blob/main/evidence/03/run-log.md).

AI agents wrote the fix and the test, and a human approved posting them.

Addresses https://github.com/NuGet/NuGetGallery/issues/ISSUE
