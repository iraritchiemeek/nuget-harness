using GalleryReadService;

var builder = WebApplication.CreateBuilder(args);

builder
    .Services.AddOptions<DatabaseOptions>()
    .BindConfiguration(DatabaseOptions.Section)
    .ValidateDataAnnotations()
    .ValidateOnStart();
builder.Services.AddSingleton<PackageQueries>();
builder.Services.AddHostedService<DatabaseStartupCheck>();
builder.Services.AddHealthChecks().AddCheck<DatabaseHealthCheck>("database");

var app = builder.Build();

app.UseGalleryResponseHeaders();
app.MapPackageEndpoints();
app.MapHealthChecks("/health");

app.Run();

/// <summary>The entry point, visible to the integration tests' WebApplicationFactory.</summary>
public partial class Program;
