# Draft pull request for PR A (not posted)

Branch name: `Bug-ISSUE`. Replace `ISSUE` with the number of the issue posted from `a-issue.md`. Everything below the line is the text to post; the backing of each claim will be in [`evidence/03/run-log.md`](../evidence/03/run-log.md).

**Not ready to post.** Nothing marked `[PENDING]` has been observed in a run yet. Each such claim goes back in only once a run backs it.

---

**Title:** Sort database package-versions results by SemVer

Sort database package-versions results by SemVer

* When no search service is configured, `AutocompleteDatabasePackageVersionsQuery` returned versions in no defined order. It now returns them oldest first, sorted in memory by `NuGetVersion`. The strings are returned as stored. Galleries with a search service configured don't use this class.
* Adds a test with versions stored out of order. [PENDING: that the test fails without the fix, and with an ordinal string sort.]
* Known effect: a stored version that isn't a valid NuGet version would now throw, where before it was returned. The sorts in `PackagesController` and `ODataV2FeedController` already behave this way.

[PENDING: results of `NuGetGallery.Facts`, and of comparing a running gallery's answers before and after the change.] [Test runs](https://github.com/iraritchiemeek/nuget-harness/blob/main/evidence/03/run-log.md).

AI agents wrote the fix and the test, and a human approved posting them.

Addresses https://github.com/NuGet/NuGetGallery/issues/ISSUE
