# Draft comment for issue #6931 (not posted)

Everything below the line is the text to post.

Not to be posted before the repository owner approves it, after the independent review. The backing of each claim is in [`evidence/03/run-log.md`](../evidence/03/run-log.md).

---

I'd like to fix this. `PackagesController.DeleteSymbols` on `dev` still falls back to the latest version: on a gallery running in CI at 06b7a81, the page for a version that doesn't exist showed the latest one ([run](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44977402047)). The change returns a 404 when a version was given and isn't found, and keeps the latest version when none was given or the version is `absoluteLatest`. The bug was found by reading the open issues. AI agents wrote the fix and its tests, and a human approved posting this. Is a pull request welcome?
