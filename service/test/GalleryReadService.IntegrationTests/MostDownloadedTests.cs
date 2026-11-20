namespace GalleryReadService.IntegrationTests;

/// <summary>
/// A blank partialId asks for the 30 most-downloaded IDs, highest count first. Every count in the
/// seed is 0, so this class gives 31 seeded IDs counts first. The counts follow neither ID order
/// nor push order, so a sort by anything else fails, and the cap of 30 leaves out the last ID.
/// Two pairs tie, and in each the older registration comes first although its ID sorts later:
/// Polly (registered before Moq) and NodaTime (registered before Ninject), so a tie-break by ID
/// fails. No other test depends on download counts.
/// </summary>
public sealed class MostDownloadedTests(GalleryDatabase database) : IAsyncLifetime
{
    private static readonly (string Id, int Downloads)[] ByDownloads =
    [
        ("Polly", 10000),
        ("Moq", 10000),
        ("NodaTime", 9900),
        ("Ninject", 9900),
        ("Dapper", 9800),
        ("Refit", 9700),
        ("Bogus", 9600),
        ("AutoMapper", 9500),
        ("Shouldly", 9400),
        ("Castle.Core", 9300),
        ("MailKit", 9200),
        ("Quartz", 9100),
        ("CsvHelper", 9000),
        ("NLog", 8900),
        ("FluentValidation", 8800),
        ("Scrutor", 8700),
        ("Humanizer.Core", 8600),
        ("MimeKit", 8500),
        ("OneOf", 8400),
        ("RestSharp", 8300),
        ("MediatR", 8200),
        ("Autofac", 8100),
        ("SimpleInjector", 8000),
        ("Spectre.Console", 7900),
        ("HtmlAgilityPack", 7800),
        ("NSubstitute", 7700),
        ("StackExchange.Redis", 7600),
        ("SharpZipLib", 7500),
        ("DotNetZip", 7400),
        ("FluentAssertions", 7300),
        ("CommandLineParser", 7200),
    ];

    private readonly GalleryApp _app = new(database);

    public async ValueTask InitializeAsync()
    {
        var counts = string.Join(", ", ByDownloads.Select(c => $"(N'{c.Id}', {c.Downloads})"));
        await database.ExecuteAsAdminAsync(
            $"""
            UPDATE dbo.PackageRegistrations SET DownloadCount = 0;
            UPDATE r SET DownloadCount = c.n FROM dbo.PackageRegistrations r
                JOIN (VALUES {counts}) AS c (Id, n) ON c.Id = r.Id;
            """
        );
    }

    public ValueTask DisposeAsync() => _app.DisposeAsync();

    [Theory]
    [InlineData("/api/v2/package-ids")]
    [InlineData("/api/v2/package-ids?partialId=")]
    [InlineData("/api/v2/package-ids?partialId=%20")]
    [InlineData("/api/v2/package-ids?includePrerelease=true&semVerLevel=2.0.0")]
    public async Task A_blank_prefix_lists_the_30_most_downloaded_ids_highest_first_and_ties_oldest_first(
        string path
    )
    {
        var ids = await _app.GetJsonAsync(path);
        Assert.Equal(ByDownloads[..30].Select(c => c.Id), ids, StringComparer.Ordinal);
    }
}
