# Engineering standards for the new service

These rules apply to every agent that writes code in `service/`. They describe the bar the code is held to, and how each rule is checked. Where a tool can enforce a rule, the tool enforces it and CI fails if it isn't met. The rest are checked by the independent reviewer agents.

Last researched: 2026-11-20. Sources are at the end.

## The one rule that overrides the rest

**Matching the old app comes first.** The new service must answer exactly as the old app does, quirks included. Where the old behaviour is odd:
- reproduce it in one clearly named place
- add a comment citing the old source file it comes from
- add a test that pins it

Never "fix" old behaviour silently, and never spread a quirk across the codebase.

The one way to differ on purpose is an **approved difference** (spec 02b): a named rule in `recordings/approved-differences.json` that cites the bug and its evidence, and whose transform the parity checks apply to the old app's answer before comparing it byte for byte. A rule may change only the order of a list, never which elements it holds.

## Platform

- **.NET 10 (LTS)**, supported until 2028-11-14.
  - .NET 11 shipped on 2026-11-10 as a standard-term release. It gets two years of support, so it ends around the same date.
  - We choose 10 because tooling (analyzers, Stryker.NET, Testcontainers) has had a year to catch up with it. On a days-old release, a broken tool would block a quality gate.
  - .NET 8 and 9 reached end of support on 2026-11-10, so they are not options.
- **C#:** the default language version for .NET 10. Don't set `LangVersion` by hand.
- **`global.json`** pins the SDK feature band with `rollForward: latestPatch`, so builds are repeatable.
- **ASP.NET Core minimal APIs.** Two endpoints don't justify controllers.

## Build settings (`Directory.Build.props`, applied to every project)

```xml
<Nullable>enable</Nullable>
<ImplicitUsings>enable</ImplicitUsings>
<TreatWarningsAsErrors>true</TreatWarningsAsErrors>
<AnalysisLevel>latest-recommended</AnalysisLevel>
<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
<GenerateDocumentationFile>true</GenerateDocumentationFile> <!-- needed for IDE0005 (unused usings) to run at build time -->
<Deterministic>true</Deterministic>
<ContinuousIntegrationBuild Condition="'$(CI)' == 'true'">true</ContinuousIntegrationBuild>
<ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
<RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
<RestoreLockedMode Condition="'$(CI)' == 'true'">true</RestoreLockedMode>
<NuGetAudit>true</NuGetAudit>
<NuGetAuditMode>all</NuGetAuditMode> <!-- audit transitive packages too -->
```

A rule may be raised or lowered only in `.editorconfig`, with a comment giving the reason. Don't use `NoWarn` in project files. Any `#pragma warning disable` or `[SuppressMessage]` must carry a justification and cover the smallest possible scope.

## Formatting and linting (the TypeScript equivalents)

| TypeScript | .NET | Role |
|---|---|---|
| Prettier | **CSharpier** (a local dotnet tool, pinned in `.config/dotnet-tools.json`) | Opinionated layout, almost no settings. Ported from Prettier's printer. |
| ESLint rules | **Roslyn analyzers**: the built-in `CA*`/`IDE*` rules, plus **Meziantou.Analyzer** | Bug patterns, culture and string-comparison mistakes, async misuse, style. Run inside the compiler, so they fail the build. |
| `.eslintrc` | **`.editorconfig`** | Rule severities and code-style preferences |
| `eslint --fix` | **`dotnet format style`** and **`dotnet format analyzers`** | Auto-fixes for analyzer and style findings |
| `tsc --noEmit` | `dotnet build` with nullable on and warnings as errors | Type and null safety |

- **Who owns whitespace:** CSharpier owns layout. Don't run `dotnet format whitespace`, because the two would fight. `dotnet format` is used only for its `style` and `analyzers` passes.
- **CI runs** `dotnet csharpier check .` and `dotnet format --verify-no-changes --exclude-diagnostics` scoped to style and analyzers. Either one failing fails the build.

## Code style

- File-scoped namespaces, `sealed` by default, `record` types for data with no behaviour.
- Use primary constructors only where they read clearly. Don't use them on types with complex initialisation.
- **No logic in `Program.cs`** beyond wiring. Endpoints live in feature files, grouped with `MapGroup`.
- **Handlers return `TypedResults`.** Declare a `Results<...>` union return type when a handler can return more than one result type.
- **Async all the way down.**
  - Pass a `CancellationToken` through every I/O call.
  - No `.Result`, `.Wait()`, `async void`, or `Task.Run` wrapped around synchronous work.
- **Strings:** every comparison states its `StringComparison`. Package IDs compare with `OrdinalIgnoreCase`, unless matching the old app requires otherwise. Formatting uses `CultureInfo.InvariantCulture`. Analyzer rules CA1307, CA1309, CA1310, CA1311, MA0074 and MA0075 enforce this.
- **Time:** inject `TimeProvider`. Never call `DateTime.Now` or `DateTime.UtcNow` directly.
- **Configuration:** use the options pattern, with `ValidateDataAnnotations` and `ValidateOnStart`, so a bad config fails at startup, not on the first request.
- **Logging:** structured logging with the `[LoggerMessage]` source generator. Never log secrets or connection strings.
- **Exceptions:** use them only for the unexpected. Don't catch `Exception` except in one top-level handler.
- **Keep it proportionate.** No repository layer wrapped around the data access library, no mediator library, and no interface with a single implementation unless a test needs to swap it. A senior reader sees two endpoints, and the design should look like two endpoints.

## Data access

- **The old app owns the schema.** No migrations, and no writes. The service connects with a login that has only `db_datareader`.
- **Queries are parameterised.** Build no SQL from strings.
  - Select only the columns the response needs.
  - With EF Core, use `AsNoTracking()` and projections.
  - With Dapper, keep the SQL as named constants next to the code that uses it.
- **Know where comparisons happen.** The database's collation decides case-insensitive matching and sorting inside SQL. If ordering or filtering moves into C#, the behaviour changes. Tests must cover casing and ordering against the real database.
- **Connection strings** come from configuration and environment variables, never from source.

## Tests

- **xUnit v3** on Microsoft.Testing.Platform.
- **Unit tests** cover pure logic: version filtering, SemVer level rules, ordering.
- **Integration tests** use `WebApplicationFactory` plus Testcontainers SQL Server, restored from the seed snapshot. Never mock the database.
- **Property-based tests** (CsCheck or FsCheck) generate IDs, prefixes and flag combinations. These feed the randomised comparison against the live old app.
- **Test names describe behaviour,** for example `Prerelease_versions_are_hidden_unless_requested`.
- **Mutation testing with Stryker.NET** gates the logic projects. The build fails below a break threshold of 80. Thresholds and surviving mutants are published with each run.
- Code coverage is reported, but it is not a target on its own. The mutation score is the gate.

## Security and supply chain

- NuGet audit fails the build on known-vulnerable packages, transitive ones included.
- Lock files plus locked-mode restore in CI.
- Central package versions in `Directory.Packages.props`.
- CodeQL runs on every push.
- Third-party GitHub Actions are pinned by SHA.
- Kestrel request limits match the old app's limits (IIS `maxQueryString`, `httpRuntime maxQueryStringLength` and similar), not the defaults, because parity needs the same requests to be accepted and refused. Query parameters have length limits that match the old app's behaviour.
- **Container:** built with the SDK's `dotnet publish /t:PublishContainer`, on a chiseled, non-root base image.

## Operability

- A `/health` endpoint checks database connectivity. It sits outside the parity set and is listed as such.
- Startup fails fast on bad configuration or an unreachable database.

## Review by agents, never by people

After the gates pass, independent reviewer agents read the code with fresh context. Each sees only the code, this file and the spec, never the builder's reasoning. Each has one lens:
- **Correctness:** edge cases, parity risks.
- **Security.**
- **Design and readability:** proportionality, naming, whether a newcomer could follow it.

Findings and their resolutions are logged in `evidence/`. A finding is closed by a code change plus a test, or by a written reason it doesn't apply.

## Sources

- [ASP.NET Core best practices](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/best-practices) (Microsoft Learn, updated 2026-11)
- [Minimal API responses and TypedResults](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/responses)
- [.NET support policy](https://dotnet.microsoft.com/en-US/platform/support/policy/dotnet-core) and [STS releases supported for 24 months](https://devblogs.microsoft.com/dotnet/dotnet-sts-releases-supported-for-24-months/)
- [.NET 11 release coverage](https://infoq.com/news/2026/11/dotnet-11-release)
- [Code analysis overview (AnalysisLevel, EnforceCodeStyleInBuild)](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/overview)
- [CA1310: specify StringComparison](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1310)
- [Meziantou.Analyzer](https://nuget.org/packages/Meziantou.Analyzer)
- [CSharpier](https://www.nuget.org/packages/csharpier) and [changelog](https://github.com/belav/csharpier/blob/main/CHANGELOG.md)
- [NuGet package auditing](https://learn.microsoft.com/nuget/concepts/auditing-packages)
- [xUnit v3 on Microsoft Testing Platform](https://xunit.net/docs/getting-started/v3/microsoft-testing-platform)
- [Testcontainers with ASP.NET Core](https://docs.docker.com/guides/testcontainers-dotnet-aspnet-core/)
- [Mutation testing in .NET](https://learn.microsoft.com/en-us/dotnet/core/testing/mutation-testing) and [Stryker.NET MTP runner](https://stryker-mutator.io/blog/stryker-net-mtp-runner/)
