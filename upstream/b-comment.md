# Draft comment for issue #6931 (not posted)

Everything below the line is the text to post.

---

I'd like to fix this. `PackagesController.DeleteSymbols` on `dev` still falls back to the latest version, and I've reproduced that on a local gallery. The change returns a 404 when a version was given and isn't found, and keeps the latest version when none was given or the version is `absoluteLatest`. AI agents wrote the fix and its tests, and a human approved posting this. Is a pull request welcome?
