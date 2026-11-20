using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace GalleryReadService;

/// <summary>The <c>/health</c> check: the database answers a query. Not part of the parity set.</summary>
internal sealed class DatabaseHealthCheck(PackageQueries queries) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default
    )
    {
        try
        {
            await queries.CheckConnectionAsync(cancellationToken);
            return HealthCheckResult.Healthy();
        }
        catch (Microsoft.Data.SqlClient.SqlException ex)
        {
            return HealthCheckResult.Unhealthy("Database query failed", ex);
        }
    }
}
