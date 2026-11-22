# Draft pull request for PR C (not posted)

Branch name: `Bug-5675`. Everything below the line is the text to post.

Not to be posted before the repository owner approves it, after the independent review. The backing of each claim is in [`evidence/03/run-log.md`](../evidence/03/run-log.md).

Not in the text, and part of what backs it: every build behind these results had NuGet's NU1903 audit warning not treated as an error, because the HtmlSanitizer advisory fails the restore of unpatched `dev`. Each build still fails unless that advisory is its only audit finding. A pull request would fail upstream's CI until upstream moves the package (inferred).

---

**Title:** Fix manage packages page when a requested ID has no versions

Fix manage packages page when a requested ID has no versions

* `CreateOwnerRequestsListItemViewModel` passed a null package on when the ID of an ownership request has no versions, and `PackageViewModelFactory.Setup` threw `ArgumentNullException`, so the page returned a 500. The item is now built from the package registration in that case.
* #5675 doesn't say what the page should show. This keeps the request in the list, so the receiver can accept or reject it. It has no "Manage Ownership" link, because `PackagesController.Manage` returns 404 for an ID with no versions, so the sender can't cancel it from the page. If you'd rather leave such requests out of the list, I can change it.
* No permission changes: every permission on the new view model is false, and who can accept is checked as before. Adds a test for received and sent requests, which fails without the fix.

All of `NuGetGallery.Facts` passes. On a running gallery, the page returned a 500 for the sender and the receiver before the change. After it, it returns 200 for both, lists the request, and leaves the normal request unchanged. Accepting and rejecting the request both worked. The registration with no versions was inserted into the gallery's database for the test. [Test run](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44977407429).

AI agents wrote the fix and the test, and a human approved posting them. The bug was found by reading the open issues.

Addresses https://github.com/NuGet/NuGetGallery/issues/5675
