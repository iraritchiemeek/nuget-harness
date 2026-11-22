# Draft pull request for PR C (not posted)

Branch name: `Bug-5675`. Everything below the line is the text to post; the backing of each claim will be in [`evidence/03/run-log.md`](../evidence/03/run-log.md).

**Not ready to post.** Nothing marked `[PENDING]` has been observed in a run yet. Each such claim goes back in only once a run backs it.

---

**Title:** Fix manage packages page when a requested ID has no versions

Fix manage packages page when a requested ID has no versions

* `CreateOwnerRequestsListItemViewModel` passed a null package on when the ID of an ownership request has no versions, and `PackageViewModelFactory.Setup` throws `ArgumentNullException` for a null package. [PENDING: that the page fails because of it.] The item is now built from the package registration in that case.
* #5675 doesn't say what the page should show. This keeps the request in the list. [PENDING: that the receiver can still accept or reject it.] It has no "Manage Ownership" link, because `PackagesController.Manage` returns 404 for an ID with no versions, so the sender can't cancel it from the page. If you'd rather leave such requests out of the list, I can change it.
* No permission changes: every permission on the new view model is false, and who can accept is checked as before. Adds a test for received and sent requests.

[PENDING: results of `NuGetGallery.Facts`, and of a running gallery as the sender and the receiver before and after the change.] [Test runs](https://github.com/iraritchiemeek/nuget-harness/blob/main/evidence/03/run-log.md).

AI agents wrote the fix and the test, and a human approved posting them. The bug was found by reading the open issues.

Addresses https://github.com/NuGet/NuGetGallery/issues/5675
