# Draft pull request for PR C (not posted)

Branch name: `Bug-5675`. Everything below the line is the text to post; the backing of each claim is in [`evidence/03/run-log.md`](../evidence/03/run-log.md).

---

**Title:** Fix manage packages page when a requested ID has no versions

Fix manage packages page when a requested ID has no versions

* `CreateOwnerRequestsListItemViewModel` passed a null package on when the ID of an ownership request has no versions, and `PackageViewModelFactory.Setup` threw `ArgumentNullException`. The item is now built from the package registration in that case.
* #5675 doesn't say what the page should show. This keeps the request in the list, so the receiver can still accept or reject it. It has no "Manage Ownership" link, because `PackagesController.Manage` returns 404 for an ID with no versions, so the sender can't cancel it from the page. If you'd rather leave such requests out of the list, I can change it.
* No permission changes: every permission on the new view model is false, and who can accept is checked as before. Adds a test for received and sent requests.

Tested with all of `NuGetGallery.Facts`, and on a running gallery as the sender and the receiver before and after the change. [Test runs](https://github.com/iraritchiemeek/nuget-harness/blob/main/evidence/03/run-log.md).

AI agents wrote the fix and the test, and a human approved posting them. The bug was found by reading the open issues.

Addresses https://github.com/NuGet/NuGetGallery/issues/5675
