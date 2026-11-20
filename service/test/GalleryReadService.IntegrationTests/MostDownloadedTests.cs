namespace GalleryReadService.IntegrationTests;

/// <summary>
/// A blank partialId asks for the 30 most-downloaded IDs, highest count first. Every count in the
/// seed is 0, so this class gives 31 seeded IDs distinct counts first; the order of equal counts is
/// left to spec 02b. The counts follow neither ID order nor push order, so a sort by anything else
/// fails, and the cap of 30 leaves out the last ID. No other test depends on download counts.
/// </summary>
public sealed class MostDownloadedTests(GalleryDatabase database) : IAsyncLifetime
{
    private static readonly string[] ByDownloads =
    [
        "Moq",
        "Polly",
        "Ninject",
        "Dapper",
        "Refit",
        "Bogus",
        "NodaTime",
        "AutoMapper",
        "Shouldly",
        "Castle.Core",
        "MailKit",
        "Quartz",
        "CsvHelper",
        "NLog",
        "FluentValidation",
        "Scrutor",
        "Humanizer.Core",
        "MimeKit",
        "OneOf",
        "RestSharp",
        "MediatR",
        "Autofac",
        "SimpleInjector",
        "Spectre.Console",
        "HtmlAgilityPack",
        "NSubstitute",
        "StackExchange.Redis",
        "SharpZipLib",
        "DotNetZip",
        "FluentAssertions",
        "CommandLineParser",
    ];

    private readonly GalleryApp _app = new(database);

    public async ValueTask InitializeAsync()
    {
        var counts = string.Join(
            ", ",
            ByDownloads.Select((id, i) => $"(N'{id}', {10_000 - (100 * i)})")
        );
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
    public async Task A_blank_prefix_lists_the_30_most_downloaded_ids_highest_first(string path) =>
        Assert.Equal(ByDownloads[..30], await _app.GetJsonAsync(path));
}
