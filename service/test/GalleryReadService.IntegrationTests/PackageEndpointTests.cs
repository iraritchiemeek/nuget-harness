using System.Net;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Options;

namespace GalleryReadService.IntegrationTests;

/// <summary>The two endpoints against the restored seed data. Matching, casing and ordering are
/// decided by SQL Server, so they are tested here, against the real database.</summary>
public sealed class PackageEndpointTests(GalleryDatabase database) : IAsyncDisposable
{
    private readonly GalleryApp _app = new(database);

    public ValueTask DisposeAsync() => _app.DisposeAsync();

    [Fact]
    public async Task Prefixes_match_case_insensitively_under_the_database_collation()
    {
        var expected = await _app.GetJsonAsync("/api/v2/package-ids?partialId=Serilog.Sinks");
        Assert.NotEmpty(expected);
        Assert.All(expected, id =>
            Assert.StartsWith("Serilog.Sinks.", id, StringComparison.Ordinal)
        );
        Assert.Equal(
            expected,
            await _app.GetJsonAsync("/api/v2/package-ids?partialId=sErIlOg.SiNkS")
        );
    }

    [Fact]
    public async Task Ids_come_back_in_the_database_collation_order()
    {
        // Case-insensitive under the database collation: "Newtonsoft.Json" before "NLog". An
        // ordinal sort would put every ID with a capital second letter (NLog, NSubstitute, NUnit) first.
        var ids = await _app.GetJsonAsync("/api/v2/package-ids?partialId=N");
        Assert.Equal(
            [
                "Newtonsoft.Json",
                "Newtonsoft.Json.Bson",
                "Newtonsoft.Json.Schema",
                "Ninject",
                "Nito.AsyncEx",
            ],
            ids[..5]
        );
        Assert.NotEqual(ids.Order(StringComparer.Ordinal), ids, StringComparer.Ordinal);
    }

    [Theory]
    [InlineData("Serilog", new[] { "1.3.30", "1.4.128", "4.4.0" })]
    [InlineData("Dapper", new[] { "1.42", "2.0.143", "2.1.89" })]
    [InlineData("serilog", new[] { "1.3.30", "1.4.128", "4.4.0" })]
    public async Task Versions_come_back_in_SemVer_order_not_push_order(
        string id,
        string[] expected
    )
    {
        // Pushed in the order 1.4.128, 1.3.30, 4.4.0 and 2.0.143, 1.42, 2.1.89 (seed/packages.txt).
        Assert.Equal(expected, await _app.GetJsonAsync($"/api/v2/package-versions/{id}"));
    }

    [Fact]
    public async Task A_blank_prefix_asks_for_the_30_most_downloaded_ids()
    {
        // Which 30 come back depends on the download counts, which MostDownloadedTests sets and
        // checks; here only the count is checked.
        Assert.Equal(30, (await _app.GetJsonAsync("/api/v2/package-ids")).Length);
        Assert.Equal(30, (await _app.GetJsonAsync("/api/v2/package-ids?partialId=%20")).Length);
    }

    // Over HTTP a blank id never reaches the old app's code: IIS trims the trailing spaces and
    // answers 404.4 with its own error page. Spec 02 amendment A4: the parity checks compare only
    // the status of these records (recordings/parity-exclusions.txt), so the service's own response,
    // an empty 404 with the gallery headers, is pinned here.
    // The requests the old app's web server answers by itself (HostingRules): the status is the
    // recorded one, the body is empty, and the old app's headers are still sent.
    [Theory]
    [InlineData("/api/v2/package-versions/%20", 404)]
    [InlineData("/api/v2/package-versions/%20%20", 404)]
    [InlineData("/api/v2/package-versions/%C2%A0", 404)]
    [InlineData("/api/v2/package-versions/.%20", 404)]
    [InlineData("/api/v2/package-versions/Serilog%2FSinks", 404)]
    [InlineData("/api/v2/package-versions/Seri%5Clog", 404)]
    [InlineData("/api/v2/package-versions/Serilog+Sinks", 404)]
    [InlineData("/api/v2/package-versions/Serilog%2BSinks", 404)]
    [InlineData("/api/v2/package-versions/Seri%3Clog", 400)]
    [InlineData("/api/v2/package-versions/Seri%25log", 400)]
    [InlineData("/api/v2/package-versions/Seri:log", 400)]
    [InlineData("/api/v2/package-versions/%09", 400)]
    [InlineData("/api/v2/package-versions/Serilog%09", 400)]
    public async Task Requests_the_old_apps_web_server_answers_itself_get_its_status_and_no_body(
        string path,
        int status
    )
    {
        using var response = await _app.GetAsync(path);
        Assert.Equal((HttpStatusCode)status, response.StatusCode);
        Assert.Null(response.Content.Headers.ContentType);
        Assert.Empty(
            await response.Content.ReadAsByteArrayAsync(TestContext.Current.CancellationToken)
        );
        Assert.Equal("private", response.Headers.CacheControl?.ToString());
        Assert.Equal("deny", Assert.Single(response.Headers.GetValues("X-Frame-Options")));
    }

    [Theory]
    [InlineData(HostingRules.MaxQueryStringLength, HttpStatusCode.OK)]
    [InlineData(HostingRules.MaxQueryStringLength + 1, HttpStatusCode.NotFound)]
    public async Task A_query_string_over_12000_characters_is_not_found(
        int queryLength,
        HttpStatusCode status
    )
    {
        var query = "partialId=Serilog&pad=";
        using var response = await _app.GetAsync(
            $"/api/v2/package-ids?{query}{new string('x', queryLength - query.Length)}"
        );
        Assert.Equal(status, response.StatusCode);
    }

    [Theory]
    [InlineData(HostingRules.MaxPathLength, HttpStatusCode.OK)]
    [InlineData(HostingRules.MaxPathLength + 1, HttpStatusCode.BadRequest)]
    public async Task A_path_over_260_characters_is_a_bad_request(
        int pathLength,
        HttpStatusCode status
    )
    {
        var route = "/api/v2/package-versions/";
        using var response = await _app.GetAsync(
            route + new string('a', pathLength - route.Length)
        );
        Assert.Equal(status, response.StatusCode);
    }

    [Theory]
    [InlineData("/api/v2/package-versions/Serilog%2F")]
    [InlineData("/api/v2/package-versions/Serilog%C2%A0")]
    public async Task An_encoded_slash_or_trailing_white_space_leaves_the_id_as_is(string path) =>
        Assert.Equal(
            await _app.GetJsonAsync("/api/v2/package-versions/Serilog"),
            await _app.GetJsonAsync(path)
        );

    [Theory]
    [InlineData("/api/v2/package-versions/Serilog.")]
    [InlineData("/api/v2/package-versions/Serilog.%20")]
    [InlineData("/api/v2/package-versions/Serilog%20.")]
    public async Task A_trailing_dot_is_part_of_the_id(string path) =>
        Assert.Empty(await _app.GetJsonAsync(path));

    [Fact]
    public async Task At_most_30_ids_are_returned() =>
        Assert.Equal(30, (await _app.GetJsonAsync("/api/v2/package-ids?partialId=S")).Length);

    [Theory]
    [InlineData("/api/v2/package-ids?partialId=Seri_og")]
    [InlineData("/api/v2/package-ids?partialId=Seri%25og")]
    [InlineData("/api/v2/package-ids?partialId=Seri%5Blo%5Dog")]
    public async Task Like_wildcards_in_a_prefix_match_only_themselves(string path) =>
        Assert.Empty(await _app.GetJsonAsync(path));

    [Fact]
    public async Task Ids_compare_case_insensitively_and_ignore_trailing_spaces()
    {
        var expected = await _app.GetJsonAsync("/api/v2/package-versions/Serilog");
        Assert.NotEmpty(expected);
        Assert.Equal(expected, await _app.GetJsonAsync("/api/v2/package-versions/SERILOG"));
        Assert.Equal(expected, await _app.GetJsonAsync("/api/v2/package-versions/Serilog%20"));
    }

    [Fact]
    public async Task An_unknown_id_has_no_versions() =>
        Assert.Empty(await _app.GetJsonAsync("/api/v2/package-versions/Serilog.Sinks.Nope"));

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

    [Fact]
    public void Health_has_one_check_named_database()
    {
        // The name is what a failing check reports under; /health itself answers only its status.
        var registrations = _app
            .Services.GetRequiredService<IOptions<HealthCheckServiceOptions>>()
            .Value.Registrations;
        Assert.Equal("database", Assert.Single(registrations).Name);
    }
}
