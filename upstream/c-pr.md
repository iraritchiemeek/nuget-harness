# Draft pull request for PR C (not posted)

Branch name: `Bug-5675`. Everything below the line is the text to post.

Not to be posted before the repository owner approves it. It holds the fixes from the independent review ([`evidence/03/reviews.md`](../evidence/03/reviews.md)), and replaces the version that was reviewed. The backing of each claim is in [`evidence/03/run-log.md`](../evidence/03/run-log.md).

---

**Title:** Fix manage packages page when a requested ID has no versions

Fix manage packages page when a requested ID has no versions

* `CreateOwnerRequestsListItemViewModel` passed a null package on when the ID of an ownership request has no versions, and `PackageViewModelFactory.Setup` threw `ArgumentNullException`, so the page returned a 500. From the code, hard deleting every version of an ID leaves this state when `DeletePackagesRequest.DeleteEmptyPackageRegistration` is unchecked, because the registration and its ownership requests stay. The item is now built from the registration in that case.
* The receiver can accept or reject the request. The sender can't cancel it from the page: it has no "Manage Ownership" link, and `PackagesController.Manage` returns 404 for an ID with no versions. The item's package link also gives a 404. The confirm and reject links in the ownership request email redirect to this page.
* No permission changes: every permission on the new view model is false, and who can accept is checked as before. Adds a test for received and sent requests, which fails without the fix.

`NuGetGallery.Facts` with the change: 11,826 passed, 2 skipped, 0 failed ([run](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44980473424)). In the same run, on a running gallery, the page returned a 500 for the sender and the receiver before the change, and returns 200 and lists the request after it. The registration with no versions was inserted into the test database.

The run builds with NU1903 not treated as an error, because the HtmlSanitizer 9.0.892 advisory currently fails restore on `dev` ([example](https://github.com/NuGet/NuGetGallery/actions/runs/44770292233)).

#5675 doesn't say what the page should show. This keeps the request in the list. Would you rather leave such requests out?

Addresses https://github.com/NuGet/NuGetGallery/issues/5675
