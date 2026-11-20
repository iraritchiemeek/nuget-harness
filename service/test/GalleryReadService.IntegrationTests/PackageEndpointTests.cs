using System.Net;
using System.Net.Http.Json;

namespace GalleryReadService.IntegrationTests;

/// <summary>The two endpoints against the restored seed data. Matching, casing and ordering are
/// decided by SQL Server, so they are tested here, against the real database.</summary>
public sealed class PackageEndpointTests(GalleryDatabase database) : IAsyncDisposable
{
    private readonly GalleryApp _app = new(database);

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

    [Fact]
    public async Task Prefixes_match_case_insensitively_under_the_database_collation()
    {
        var expected = await GetJsonAsync("/api/v2/package-ids?partialId=Serilog.Sinks");
        Assert.NotEmpty(expected);
        Assert.All(expected, id =>
            Assert.StartsWith("Serilog.Sinks.", id, StringComparison.Ordinal)
        );
        Assert.Equal(expected, await GetJsonAsync("/api/v2/package-ids?partialId=sErIlOg.SiNkS"));
    }

    [Fact]
    public async Task Ids_come_back_in_the_database_collation_order() =>
        Assert.Equal(
            ["xunit", "xunit.abstractions", "xunit.analyzers", "xunit.assert", "xunit.core"],
            (await GetJsonAsync("/api/v2/package-ids?partialId=xunit"))[..5]
        );

    [Fact]
    public async Task A_blank_prefix_asks_for_the_30_most_downloaded_ids()
    {
        // Every seeded DownloadCount is 0, so which 30 come back is the query plan's tie order,
        // which the recordings pin; here only the count is checked.
        Assert.Equal(30, (await GetJsonAsync("/api/v2/package-ids")).Length);
        Assert.Equal(30, (await GetJsonAsync("/api/v2/package-ids?partialId=%20")).Length);
    }

    // AutocompleteDatabasePackageVersionsQuery.cs throws for a blank id, and the controller answers
    // 500. Over HTTP the old app's host (IIS) answers first: it trims the trailing spaces and replies
    // 404.4 (recordings/requests.txt, A3). Which of the two the service should copy is undecided.
    [Fact]
    public async Task A_blank_id_is_answered_500_as_the_old_query_throws()
    {
        using var client = _app.CreateClient();
        using var response = await client.GetAsync(
            new Uri("/api/v2/package-versions/%20", UriKind.Relative),
            TestContext.Current.CancellationToken
        );
        Assert.Equal(HttpStatusCode.InternalServerError, response.StatusCode);
    }

    [Fact]
    public async Task At_most_30_ids_are_returned() =>
        Assert.Equal(30, (await GetJsonAsync("/api/v2/package-ids?partialId=S")).Length);

    [Theory]
    [InlineData("/api/v2/package-ids?partialId=Seri_og")]
    [InlineData("/api/v2/package-ids?partialId=Seri%25og")]
    [InlineData("/api/v2/package-ids?partialId=Seri%5Blo%5Dog")]
    public async Task Like_wildcards_in_a_prefix_match_only_themselves(string path) =>
        Assert.Empty(await GetJsonAsync(path));

    [Fact]
    public async Task Ids_compare_case_insensitively_and_ignore_trailing_spaces()
    {
        var expected = await GetJsonAsync("/api/v2/package-versions/Serilog");
        Assert.NotEmpty(expected);
        Assert.Equal(expected, await GetJsonAsync("/api/v2/package-versions/SERILOG"));
        Assert.Equal(expected, await GetJsonAsync("/api/v2/package-versions/Serilog%20"));
    }

    [Fact]
    public async Task An_unknown_id_has_no_versions() =>
        Assert.Empty(await GetJsonAsync("/api/v2/package-versions/Serilog.Sinks.Nope"));

    // Spec 02 amendment A1: other methods stay with the old app (the next spec's proxy sends them
    // there), so the service refuses them.
    [Theory]
    [InlineData("POST", "/api/v2/package-ids?partialId=Serilog")]
    [InlineData("PUT", "/api/v2/package-versions/Serilog")]
    [InlineData("DELETE", "/api/v2/package-versions/Serilog")]
    public async Task Methods_other_than_GET_are_refused_with_405_and_Allow_GET(
        string method,
        string path
    )
    {
        using var client = _app.CreateClient();
        using var request = new HttpRequestMessage(
            new HttpMethod(method),
            new Uri(path, UriKind.Relative)
        );
        using var response = await client.SendAsync(request, TestContext.Current.CancellationToken);
        Assert.Equal(HttpStatusCode.MethodNotAllowed, response.StatusCode);
        Assert.Equal(["GET"], response.Content.Headers.Allow);
    }

    [Fact]
    public async Task Responses_carry_the_old_apps_headers()
    {
        using var client = _app.CreateClient();
        using var response = await client.GetAsync(
            new Uri("/api/v2/package-ids?partialId=Polly", UriKind.Relative),
            TestContext.Current.CancellationToken
        );
        Assert.Equal(
            "application/json; charset=utf-8",
            response.Content.Headers.ContentType?.ToString()
        );
        Assert.Equal("private", response.Headers.CacheControl?.ToString());
        Assert.Equal("deny", Assert.Single(response.Headers.GetValues("X-Frame-Options")));
        Assert.Equal(
            "nosniff",
            Assert.Single(response.Headers.GetValues("X-Content-Type-Options"))
        );
        Assert.Equal(
            "max-age=31536000; includeSubDomains",
            Assert.Single(response.Headers.GetValues("Strict-Transport-Security"))
        );
    }

    [Fact]
    public async Task Health_checks_the_database()
    {
        using var client = _app.CreateClient();
        Assert.Equal(
            "Healthy",
            await client.GetStringAsync(
                new Uri("/health", UriKind.Relative),
                TestContext.Current.CancellationToken
            )
        );
    }
}
