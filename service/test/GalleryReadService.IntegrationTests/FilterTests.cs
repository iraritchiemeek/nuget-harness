namespace GalleryReadService.IntegrationTests;

/// <summary>
/// The includePrerelease and semVerLevel filters, against rows written for this test. The seed data
/// holds no prerelease or SemVer 2.0.0 version, so these rows are what make the filters matter.
/// Each row is a copy of a seeded Packages row, so every other column holds a value the old app wrote.
/// The rows are isolated from the other tests: they belong to IDs that start with "ZzFilters", which
/// no other test asks for, and which no other prefix in the tests matches. The database is shared by
/// the whole test assembly and each test runs InitializeAsync, so the rows are written once.
/// </summary>
public sealed class FilterTests(GalleryDatabase database) : IAsyncLifetime
{
    private const string Id = "ZzFilters";
    private const string OnlySemVer2PrereleaseId = "ZzFilters.SemVer2Prerelease";
    private readonly GalleryApp _app = new(database);

    public async ValueTask InitializeAsync() =>
        await database.ExecuteAsAdminAsync(
            $"""
            SET XACT_ABORT ON;
            BEGIN TRANSACTION;
            IF NOT EXISTS (SELECT 1 FROM dbo.PackageRegistrations WHERE Id = N'{Id}')
            BEGIN
                SELECT * INTO #r FROM dbo.PackageRegistrations WHERE Id = N'Serilog';
                ALTER TABLE #r DROP COLUMN [Key];
                UPDATE #r SET Id = N'{Id}';
                INSERT INTO dbo.PackageRegistrations SELECT * FROM #r;
                DECLARE @id int = SCOPE_IDENTITY();
                UPDATE #r SET Id = N'{OnlySemVer2PrereleaseId}';
                INSERT INTO dbo.PackageRegistrations SELECT * FROM #r;
                DECLARE @only int = SCOPE_IDENTITY();

                -- One copy of a seeded Serilog row per version below, with these columns changed:
                -- registration, version, prerelease, SemVer level key (NULL = 1.0.0, 2 = 2.0.0),
                -- listed, status (0 = Available).
                SELECT p.*, c.r AS NewRegistration, c.v AS NewVersion, c.pre AS NewPrerelease,
                    c.semver AS NewSemVer, c.listed AS NewListed, c.status AS NewStatus
                INTO #p
                FROM (SELECT TOP (1) * FROM dbo.Packages WHERE PackageRegistrationKey =
                    (SELECT [Key] FROM dbo.PackageRegistrations WHERE Id = N'Serilog') ORDER BY [Key]) AS p
                -- Written newest first, so that row order is not SemVer order.
                CROSS JOIN (VALUES
                    (@id, N'6.0.0', 0, NULL, 1, 1),
                    (@id, N'5.0.0', 0, NULL, 0, 0),
                    (@id, N'4.0.0+meta', 0, 2, 1, 0),
                    (@id, N'3.0.0-rc.1', 1, 2, 1, 0),
                    (@id, N'2.0.0-beta', 1, NULL, 1, 0),
                    (@id, N'1.0.0', 0, NULL, 1, 0),
                    (@only, N'1.0.0-rc.1', 1, 2, 1, 0)
                ) AS c (r, v, pre, semver, listed, status);
                UPDATE #p SET PackageRegistrationKey = NewRegistration, Version = NewVersion,
                    NormalizedVersion = NewVersion, IsPrerelease = NewPrerelease, SemVerLevelKey = NewSemVer,
                    Listed = NewListed, PackageStatusKey = NewStatus;
                ALTER TABLE #p DROP COLUMN [Key], NewRegistration, NewVersion, NewPrerelease, NewSemVer,
                    NewListed, NewStatus;
                INSERT INTO dbo.Packages SELECT * FROM #p;
            END;
            COMMIT;
            """
        );

    public ValueTask DisposeAsync() => _app.DisposeAsync();

    [Theory]
    [InlineData("", new[] { "1.0.0" })]
    [InlineData("?includePrerelease=true", new[] { "1.0.0", "2.0.0-beta" })]
    [InlineData("?semVerLevel=2.0.0", new[] { "1.0.0", "4.0.0+meta" })]
    [InlineData(
        "?includePrerelease=true&semVerLevel=2.0.0",
        new[] { "1.0.0", "2.0.0-beta", "3.0.0-rc.1", "4.0.0+meta" }
    )]
    public async Task Prerelease_and_SemVer2_versions_are_hidden_unless_requested(
        string query,
        string[] expected
    )
    {
        // In SemVer order, which is not the order the rows were written in (see InitializeAsync).
        Assert.Equal(expected, await _app.GetJsonAsync($"/api/v2/package-versions/{Id}{query}"));
    }

    [Theory]
    [InlineData("", false)]
    [InlineData("&includePrerelease=true", false)]
    [InlineData("&semVerLevel=2.0.0", false)]
    [InlineData("&includePrerelease=true&semVerLevel=2.0.0", true)]
    public async Task An_id_counts_only_if_one_of_its_versions_passes_the_filter(
        string query,
        bool includesTheSemVer2PrereleaseOnlyId
    )
    {
        var ids = await _app.GetJsonAsync($"/api/v2/package-ids?partialId={Id}{query}");
        Assert.Equal(
            includesTheSemVer2PrereleaseOnlyId ? [Id, OnlySemVer2PrereleaseId] : [Id],
            ids
        );
    }
}
