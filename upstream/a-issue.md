# Draft issue for PR A (not posted)

Self-hosted issue template (`.github/ISSUE_TEMPLATE/SELF_HOSTED.yml`). Everything below the line is the text to post.

Not to be posted before the repository owner approves it. It holds the fixes from the independent review ([`evidence/03/reviews.md`](../evidence/03/reviews.md)), and replaces the version that was reviewed. The backing of each claim is in [`evidence/03/run-log.md`](../evidence/03/run-log.md).

---

**Title:** [Self-hosted Bug]: package-versions returns versions in no defined order when no search service is configured

**Impact:** It bothers me. A fix would be nice

**Describe the bug**

`GET /api/v2/package-versions/{id}` returns versions in no defined order when no search service is configured, for example in local development. `AutocompleteDatabasePackageVersionsQuery` has no `OrderBy`, so nothing defines the order.

This is about the database fallback only. `DefaultDependenciesModule.ConfigureAutocomplete` uses `AutocompleteServicePackageVersionsQuery` when a search service is configured, and nuget.org's answers for Serilog and Newtonsoft.Json (2026-11-22) were in SemVer order, oldest first.

**Repro Steps**

1. Using this git commit of NuGetGallery: 63e6ee4202b441e1c904d6f78fc7b070f36bc24f (the query file is the same on `dev` at 06b7a81ab7bb92d5009082789b9e4ec5c81586cb).
2. Run the gallery with no search service configured, and push Serilog 1.4.128, 1.3.30 and 4.4.0 in that order.
3. Request `/api/v2/package-versions/Serilog`. The answer is `["1.4.128","1.3.30","4.4.0"]` ([run](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44980456732), on a gallery restored from a snapshot).

**Expected Behavior**

Versions in SemVer order, oldest first: `["1.3.30","1.4.128","4.4.0"]`.

**Additional Context and logs**

A small fix with a test is ready.
