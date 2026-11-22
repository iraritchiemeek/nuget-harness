# Draft pull request for PR B (not posted)

Branch name: `Bug-6931`. Everything below the line is the text to post.

Not to be posted before the repository owner approves it and settles the disclosure line. It holds the fixes from the independent review ([`evidence/03/reviews.md`](../evidence/03/reviews.md)), and replaces the version that was reviewed. The backing of each claim is in [`evidence/03/run-log.md`](../evidence/03/run-log.md).

---

**Title:** Return 404 from delete symbols page when version doesn't exist

Return 404 from delete symbols page when version doesn't exist

* #6931 says of the fallback to the latest version: "This could lead to unintentional deletions. Instead, we should show a 404 if the specified version does not exist." The page now falls back only when no version, or an empty one, was given.
* `absoluteLatest`, which `VersionRouteConstraint` accepts, now gives a 404 too. It has no handling of its own here: it fell into the same fallback, which prefers the latest stable version. Nothing in `src` links to this page with it.
* `TheDeleteSymbolsMethodWithMissingVersion` pinned the old fallback. It is replaced by a theory that expects the 404, for "missing" and "2.0.0". Both cases fail without the fix. A new class covers the empty version. The null-version tests are unchanged.
* Known effect: someone who can't manage the package now gets a 404 instead of a 403 for a version that doesn't exist. The POST action, `DeleteSymbolsPackage`, already answers in that order.

`Manage` has a similar fallback. #6931 is only about delete symbols, so it is not changed.

`NuGetGallery.Facts` with the change: 11,827 passed, 2 skipped, 0 failed ([run](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44980465212)). In the same run, on a running gallery as the owner, a version that doesn't exist showed the latest version before the change and gives a 404 after it. An existing version and no version are unchanged.

The run builds with NU1903 not treated as an error, because the HtmlSanitizer 9.0.892 advisory currently fails restore on `dev` ([example](https://github.com/NuGet/NuGetGallery/actions/runs/44770292233)).

AI agents wrote this change and its test. [OWNER TO CONFIRM BEFORE POSTING]

Addresses https://github.com/NuGet/NuGetGallery/issues/6931
