using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;

namespace GalleryReadService.IntegrationTests;

public sealed class StartupTests
{
    private sealed class UnreachableDatabaseApp : WebApplicationFactory<Program>
    {
        protected override void ConfigureWebHost(IWebHostBuilder builder) =>
            builder.UseSetting(
                "Database:ConnectionString",
                "Server=127.0.0.1,9;Database=NuGetGallery;User Id=reader;Password=x;Connect Timeout=2;TrustServerCertificate=True"
            );
    }

    [Fact]
    public void Startup_fails_when_the_database_is_unreachable()
    {
        using var app = new UnreachableDatabaseApp();
        Assert.ThrowsAny<Exception>(() => app.CreateClient());
    }

    [Fact]
    public void Startup_fails_without_a_connection_string()
    {
        using var app = new WebApplicationFactory<Program>();
        Assert.ThrowsAny<Exception>(() => app.CreateClient());
    }
}
