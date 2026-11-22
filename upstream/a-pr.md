# Draft pull request for PR A (not posted)

Branch name: `Bug-ISSUE`. Replace `ISSUE` with the number of the issue posted from `a-issue.md`. Everything below the line is the text to post.

Not to be posted before the repository owner approves it and settles the disclosure line. It holds the fixes from the independent review ([`evidence/03/reviews.md`](../evidence/03/reviews.md)), and replaces the version that was reviewed. The backing of each claim is in [`evidence/03/run-log.md`](../evidence/03/run-log.md).

---

**Title:** Sort database package-versions results by SemVer

Sort database package-versions results by SemVer

* When no search service is configured, `AutocompleteDatabasePackageVersionsQuery` returned versions in no defined order. It now returns them oldest first, sorted in memory by `NuGetVersion`. The strings are returned as stored. For a partial ID, `AutocompleteDatabasePackageIdsQuery` already sorts its results, and nuget.org's search-backed answers for Serilog and Newtonsoft.Json (2026-11-22) were in SemVer order, oldest first. Galleries with a search service configured don't use this class.
* Adds a test with versions stored out of order. It fails without the fix, and with an ordinal string sort.
* Known effect: a stored version that isn't a valid NuGet version would now throw, where before it was returned. The sorts in `PackagesController` and `ODataV2FeedController` already behave this way.

`NuGetGallery.Facts` with the change: 11,826 passed, 2 skipped, 0 failed ([run](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44980456732)). The same run compared a gallery's answers to 351 requests before and after, at 63e6ee4, where the query file is the same as on `dev`: only the order of versions differs.

The run builds with NU1903 not treated as an error, because the HtmlSanitizer 9.0.892 advisory currently fails restore on `dev` ([example](https://github.com/NuGet/NuGetGallery/actions/runs/44770292233)).

AI agents wrote this change and its test. [OWNER TO CONFIRM BEFORE POSTING]

Addresses https://github.com/NuGet/NuGetGallery/issues/ISSUE
