# Draft pull request for PR B (not posted)

Branch name: `Bug-6931`. Everything below the line is the text to post.

Not to be posted before the repository owner approves it, after the independent review. The backing of each claim is in [`evidence/03/run-log.md`](../evidence/03/run-log.md).

Not in the text, and part of what backs it: every build behind these results had NuGet's NU1903 audit warning not treated as an error, because the HtmlSanitizer advisory fails the restore of unpatched `dev`. Each build still fails unless that advisory is its only audit finding. A pull request would fail upstream's CI until upstream moves the package (inferred).

---

**Title:** Return 404 from delete symbols page when version doesn't exist

Return 404 from delete symbols page when version doesn't exist

* #6931 asks for a 404 because falling back to the latest version "could lead to unintentional deletions". The fallback is now only used when no version was given, or when the version is `absoluteLatest`, which `VersionRouteConstraint` accepts and which shows the latest version today.
* `TheDeleteSymbolsMethodWithMissingVersion` pinned the old fallback, so it is replaced by a test that expects the 404, which fails without the fix. A new class covers `absoluteLatest`. The exact-version and null-version tests are unchanged.
* Known effect: someone who can't manage the package now gets a 404 instead of a 403 for a version that doesn't exist. The POST action, `DeleteSymbolsPackage`, already answers in that order.

`Manage` has a similar fallback. Its tests show it is intended, so it is not changed.

All of `NuGetGallery.Facts` passes. On a running gallery, as the owner, a version that doesn't exist showed the latest version before the change and gives a 404 after it. An existing version, no version and `absoluteLatest` are unchanged. [Test run](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44977402047).

AI agents wrote the fix and the tests, and a human approved posting them. The bug was found by reading the open issues.

Addresses https://github.com/NuGet/NuGetGallery/issues/6931
