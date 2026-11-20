using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;

namespace GalleryReadService.IntegrationTests;

/// <summary>The service in memory, connected to <see cref="GalleryDatabase"/> as the read-only login.</summary>
public sealed class GalleryApp(GalleryDatabase database) : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder) =>
        builder.UseSetting("Database:ConnectionString", database.ReaderConnectionString);
}
