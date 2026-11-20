namespace GalleryReadService;

/// <summary>Fails startup when the database cannot be reached, instead of failing the first request.</summary>
internal sealed partial class DatabaseStartupCheck(
    PackageQueries queries,
    ILogger<DatabaseStartupCheck> logger
) : IHostedService
{
    public async Task StartAsync(CancellationToken cancellationToken)
    {
        await queries.CheckConnectionAsync(cancellationToken);
        LogDatabaseReachable(logger);
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;

    [LoggerMessage(Level = LogLevel.Information, Message = "Database reachable")]
    private static partial void LogDatabaseReachable(ILogger logger);
}
