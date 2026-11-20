# Spec 02b: Improve the new service behind the safety net

## Goal

Spec 02 proved the new service gives exactly the old app's responses. This spec makes it better than the old app, without losing that proof:

- **Fix the old app's bugs** instead of copying them.
- **Make the code readable,** replacing SQL copied from the old database library with plain queries.
- **Measure speed,** so any claim about performance is backed by numbers.

Every difference from the old app must be deliberate, named and checked. A difference that isn't on the approved list still fails the build.

## Approved differences

An approved difference is a rule, kept in a committed file `recordings/approved-differences.json`. Each rule has:

- a name and the bug it fixes
- which records it applies to
- a transform that describes the difference, for example "the same set of versions, sorted by SemVer order"

Parity for those records then means: the new response equals the old recorded response **after applying the transform**. The check still compares every byte of the result, so a fix that drops or adds a version fails.

An approved difference never means "this record isn't compared".

## Bugs to fix

1. **`package-versions` has no sort order.** Versions come back in whatever order the database reads them. They should come back in SemVer order, oldest first, which is the order NuGet clients expect.
   - **Transform:** sort the recorded list by SemVer.
2. **Ties in the most-downloaded list have no tie-break.** IDs with equal download counts are ordered by the database's query plan.
   - **Fix:** break ties by ID.
   - **Transform:** re-sort the recorded list by downloads descending, then by ID.
3. **Anything else the agents find.** Any other place where old behaviour depends on chance (plan order, collation accidents) or is plainly wrong is listed with evidence. It is fixed only if it can be stated as a transform like the two above.

## Readable code

Rewrite the queries in `service/` as plain LINQ on EF Core (read-only, no tracking, no migrations), replacing the SQL copied from Entity Framework 6's output.

- Once the ordering bugs are fixed, the old query shape no longer decides the output order. The copied SQL should then be unnecessary.
- If parity, with the approved differences applied, still fails on some record, the failing record shows which old behaviour forces it. Record that in the run log before deciding anything.
- **Watch prefix matching.** EF Core may translate `StartsWith` differently from Entity Framework 6, for example as `LEFT`/`LEN`. `LEN` ignores trailing spaces, and the `~` escape would be lost.
  - The recorded `%20` requests and the LIKE-character requests guard against this. They must still pass.
  - Once the old escaping code is no longer used, delete `LikePattern` and its tests.
- **Tighten the tests.** Once versions are SemVer-sorted, change the tests that compare sets of versions (`FilterTests`, `mutation-check.ps1 -AsSet`) to assert exact order.

## Speed

A benchmark job on `windows-2022` runs the old app and the new service side by side on the same machine and database.

- **Tool:** a pinned load tool (for example `bombardier` or `k6`), with the same request mix for both: drawn from the recorded request set, weighted toward prefix searches.
- **Load:** fixed concurrency levels, for example 1, 8 and 32, and a fixed duration per level after a warm-up.
- **Published per app and level:** requests per second, p50, p95 and p99 latency, and the error count.
- **Database cost:** also record SQL Server logical reads and CPU time per query type for each app, using Query Store or `sys.dm_exec_query_stats`. The old app's `DISTINCT` over every column is the likely cost.
- **Results** go to `evidence/02b/benchmark.md`, with the run link and machine details.
- **Interpretation:** a shared CI runner gives noisy numbers. The report states that, and runs the benchmark at least three times. Its conclusion must hold across all three runs or not be claimed.
- **No threshold.** The job never fails on speed alone. Its purpose is to measure, not to promise.

## Done when

1. Both ordering bugs are fixed and listed in `approved-differences.json`. Parity passes on both data states with the transforms applied, and fails on a planted out-of-order response (negative control).
2. The queries are LINQ on EF Core. No copied Entity Framework 6 SQL remains. All spec 02 checks still pass, and every engineering-standards gate still passes.
3. The benchmark has run at least three times and the report is published.
4. `evidence/02b/run-log.md` covers every run, decision and finding.

## Out of scope

- the front proxy (next spec)
- write endpoints
- changing response formats beyond the approved differences
