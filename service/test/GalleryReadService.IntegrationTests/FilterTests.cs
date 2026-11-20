using System.Net.Http.Json;

namespace GalleryReadService.IntegrationTests;

/// <summary>
/// The includePrerelease and semVerLevel filters, against rows written for this test. The seed data
/// holds no prerelease or SemVer 2.0.0 version, so these rows are what make the filters matter.
/// Each row is a copy of a seeded Packages row, so every other column holds a value the old app wrote.
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

                SELECT TOP (1) * INTO #p FROM dbo.Packages WHERE PackageRegistrationKey =
                    (SELECT [Key] FROM dbo.PackageRegistrations WHERE Id = N'Serilog') ORDER BY [Key];
                ALTER TABLE #p DROP COLUMN [Key];
                -- version, prerelease, SemVer level key (NULL = 1.0.0, 2 = 2.0.0), listed, status (0 = Available)
                DECLARE @rows TABLE (r int, v nvarchar(64), pre bit, semver int, listed bit, status int);
                INSERT INTO @rows VALUES
                    (@id, N'1.0.0', 0, NULL, 1, 0),
                    (@id, N'2.0.0-beta', 1, NULL, 1, 0),
                    (@id, N'3.0.0-rc.1', 1, 2, 1, 0),
                    (@id, N'4.0.0+meta', 0, 2, 1, 0),
                    (@id, N'5.0.0', 0, NULL, 0, 0),
                    (@id, N'6.0.0', 0, NULL, 1, 1),
                    (@only, N'1.0.0-rc.1', 1, 2, 1, 0);
                DECLARE @r int, @v nvarchar(64), @pre bit, @semver int, @listed bit, @status int;
                DECLARE rows CURSOR LOCAL FOR SELECT r, v, pre, semver, listed, status FROM @rows;
                OPEN rows;
                FETCH NEXT FROM rows INTO @r, @v, @pre, @semver, @listed, @status;
                WHILE @@FETCH_STATUS = 0
                BEGIN
                    UPDATE #p SET PackageRegistrationKey = @r, Version = @v, NormalizedVersion = @v,
                        IsPrerelease = @pre, SemVerLevelKey = @semver, Listed = @listed, PackageStatusKey = @status;
                    INSERT INTO dbo.Packages SELECT * FROM #p;
                    FETCH NEXT FROM rows INTO @r, @v, @pre, @semver, @listed, @status;
                END;
            END;
            COMMIT;
            """
        );

    public ValueTask DisposeAsync() => _app.DisposeAsync();

    private async Task<string[]> GetJsonAsync(string path)
    {
        using var client = _app.CreateClient();
        var result = await client.GetFromJsonAsync<string[]>(
            new Uri(path, UriKind.Relative),
            TestContext.Current.CancellationToken
        );
        return result ?? throw new InvalidOperationException($"{path} returned null");
    }

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
        // No ORDER BY in the old app's version query, so the order is the query plan's: compare as sets.
        var versions = await GetJsonAsync($"/api/v2/package-versions/{Id}{query}");
        Assert.Equal(
            expected.Order(StringComparer.Ordinal),
            versions.Order(StringComparer.Ordinal)
        );
    }

    [Theory]
    [InlineData("", false)]
    [InlineData("&includePrerelease=true", false)]
    [InlineData("&semVerLevel=2.0.0", false)]
    [InlineData("&includePrerelease=true&semVerLevel=2.0.0", true)]
    public async Task An_id_counts_only_if_one_of_its_versions_passes_the_filter(
        string query,
        bool listed
    )
    {
        var ids = await GetJsonAsync($"/api/v2/package-ids?partialId={Id}{query}");
        Assert.Equal(listed ? [Id, OnlySemVer2PrereleaseId] : [Id], ids);
    }
}
