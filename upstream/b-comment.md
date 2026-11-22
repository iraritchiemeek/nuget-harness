# Draft comment for issue #6931 (not posted)

Everything below the line is the text to post.

**Not ready to post.** Nothing marked `[PENDING]` has been observed in a run yet. Each such claim goes back in only once a run backs it.

---

I'd like to fix this. `PackagesController.DeleteSymbols` on `dev` still has the fallback to the latest version. [PENDING: reproduction on a running gallery.] The change returns a 404 when a version was given and isn't found, and keeps the latest version when none was given or the version is `absoluteLatest`. AI agents wrote the fix and its tests, and a human approved posting this. Is a pull request welcome?
