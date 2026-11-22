# Draft issue for PR A (not posted)

Self-hosted issue template (`.github/ISSUE_TEMPLATE/SELF_HOSTED.yml`). Everything below the line is the text to post.

---

**Title:** [Self-hosted Bug]: package-versions returns versions in no defined order when no search service is configured

**Impact:** It bothers me. A fix would be nice

**Describe the bug**

`GET /api/v2/package-versions/{id}` returns versions in no defined order when no search service is configured, for example in local development. `AutocompleteDatabasePackageVersionsQuery` has no `OrderBy`, so the order is whatever the SQL query plan gives.

This is about the database fallback only. `DefaultDependenciesModule.ConfigureAutocomplete` uses `AutocompleteServicePackageVersionsQuery` when a search service is configured, and the parts of nuget.org's answers I read for Serilog and Newtonsoft.Json (2026-11-22) were in SemVer order, oldest first.

**Repro Steps**

1. Using this git commit of NuGetGallery: 06b7a81ab7bb92d5009082789b9e4ec5c81586cb (dev)
2. Run the gallery locally with no search service configured, and push Serilog 1.4.128, then 1.3.30, then 4.4.0.
3. Request `/api/v2/package-versions/Serilog`.
4. The answer is `["1.4.128","1.3.30","4.4.0"]`.

**Expected Behavior**

Versions in SemVer order, oldest first: `["1.3.30","1.4.128","4.4.0"]`.

**Additional Context and logs**

Found by an automated comparison of the endpoint's answers, written and run by AI agents. They also wrote a small fix with a test, which I can open as a pull request. A human approved posting this.
