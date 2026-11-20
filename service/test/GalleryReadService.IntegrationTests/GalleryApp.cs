using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;

namespace GalleryReadService.IntegrationTests;

/// <summary>The service in memory, connected to <see cref="GalleryDatabase"/> as the read-only login.</summary>
public sealed class GalleryApp(GalleryDatabase database) : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder) =>
        builder.UseSetting("Database:ConnectionString", database.ReaderConnectionString);

    /// <summary>Sends a GET for <paramref name="path"/> and returns the response.</summary>
    public async Task<HttpResponseMessage> GetAsync(string path)
    {
        using var client = CreateClient();
        return await client.GetAsync(
            new Uri(path, UriKind.Relative),
            TestContext.Current.CancellationToken
        );
    }

    /// <summary>Sends a GET for <paramref name="path"/> and reads the JSON array of strings it answers with.</summary>
    public async Task<string[]> GetJsonAsync(string path)
    {
        using var client = CreateClient();
        var result = await client.GetFromJsonAsync<string[]>(
            new Uri(path, UriKind.Relative),
            TestContext.Current.CancellationToken
        );
        return result ?? throw new InvalidOperationException($"{path} returned null");
    }
}
