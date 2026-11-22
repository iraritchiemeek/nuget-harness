# Draft pull request for PR B (not posted)

Branch name: `Bug-6931`. Everything below the line is the text to post; the backing of each claim will be in [`evidence/03/run-log.md`](../evidence/03/run-log.md).

**Not ready to post.** Nothing marked `[PENDING]` has been observed in a run yet. Each such claim goes back in only once a run backs it.

---

**Title:** Return 404 from delete symbols page when version doesn't exist

Return 404 from delete symbols page when version doesn't exist

* #6931 asks for a 404 because falling back to the latest version "could lead to unintentional deletions". The fallback is now only used when no version was given, or when the version is `absoluteLatest`, which `VersionRouteConstraint` accepts. [PENDING: what `absoluteLatest` shows today.]
* `TheDeleteSymbolsMethodWithMissingVersion` pinned the old fallback, so it is replaced by a test that expects the 404. A new class covers `absoluteLatest`. The exact-version and null-version tests are unchanged.
* Known effect: someone who can't manage the package now gets a 404 instead of a 403 for a version that doesn't exist. The POST action, `DeleteSymbolsPackage`, already answers in that order.

`Manage` has a similar fallback. Its tests show it is intended, so it is not changed.

[PENDING: results of `NuGetGallery.Facts`, and of a running gallery as the package owner before and after the change.] [Test runs](https://github.com/iraritchiemeek/nuget-harness/blob/main/evidence/03/run-log.md).

AI agents wrote the fix and the tests, and a human approved posting them. The bug was found by reading the open issues.

Addresses https://github.com/NuGet/NuGetGallery/issues/6931
