using Microsoft.EntityFrameworkCore;

namespace GalleryReadService;

/// <summary>
/// The two read queries, against the database the old app owns. The service never writes and runs
/// no migrations.
/// </summary>
/// <remarks>
/// The filters are the old app's (NuGetGallery src/NuGetGallery/Queries/
/// AutocompleteDatabasePackageIdsQuery.cs and AutocompleteDatabasePackageVersionsQuery.cs).
/// Matching and the order of IDs stay in SQL, because the database collation decides them: IDs and
/// prefixes match case-insensitively, and IDs sort in collation order. Where the old app left an
/// order to the query plan, this service fixes it:
/// <list type="bullet">
/// <item>Versions come back in SemVer order, oldest first (<see cref="VersionOrder"/>). The old
/// query had no ORDER BY. This is an approved difference (recordings/approved-differences.json).</item>
/// <item>Most-downloaded IDs with equal download counts come back oldest registration first
/// (registration key). This order was chosen because it is deterministic and also matches what the
/// old app's query plan happened to return, so every recorded answer is unchanged and no approved
/// difference is needed. A tie-break by ID would return a different 30 IDs, not the same 30 in a
/// new order, because the recordings cut a tie of every seeded ID at 30 (spec 02b amendment B1,
/// evidence/02b/run-log.md).</item>
/// </list>
/// </remarks>
internal sealed class PackageQueries(IDbContextFactory<GalleryDb> databases)
{
    private const int MaxIds = 30;

    /// <summary>Up to 30 package IDs that start with <paramref name="partialId"/>, in ID order.
    /// A blank <paramref name="partialId"/> asks for the most-downloaded IDs instead.</summary>
    public async Task<IReadOnlyList<string>> GetPackageIdsAsync(
        string? partialId,
        PackageFilter filter,
        CancellationToken cancellationToken
    )
    {
        await using var db = await databases.CreateDbContextAsync(cancellationToken);
        var visible = Visible(db, filter);
        var registrations = db.PackageRegistrations.Where(r =>
            visible.Any(p => p.PackageRegistrationKey == r.Key)
        );

        // EF Core sends StartsWith as LIKE with the wildcards in partialId escaped, as the old app's
        // Entity Framework 6 did (with a different escape character). The recorded requests with
        // %, _, [ and ~ in partialId pin that.
        var ids = string.IsNullOrWhiteSpace(partialId)
            ? registrations.OrderByDescending(r => r.DownloadCount).ThenBy(r => r.Key)
            : registrations.Where(r => r.Id.StartsWith(partialId)).OrderBy(r => r.Id);
        return await ids.Select(r => r.Id).Take(MaxIds).ToListAsync(cancellationToken);
    }

    /// <summary>The version strings of package <paramref name="id"/>, as they were pushed, in
    /// SemVer order.</summary>
    public async Task<IReadOnlyList<string>> GetPackageVersionsAsync(
        string id,
        PackageFilter filter,
        CancellationToken cancellationToken
    )
    {
        await using var db = await databases.CreateDbContextAsync(cancellationToken);
        var versions = await Visible(db, filter)
            .Where(p => p.PackageRegistration.Id == id)
            .Select(p => p.Version)
            .ToListAsync(cancellationToken);
        return VersionOrder.Sort(versions);
    }

    /// <summary>Opens a connection and runs a trivial query, for startup and the health check.</summary>
    public async Task CheckConnectionAsync(CancellationToken cancellationToken)
    {
        await using var db = await databases.CreateDbContextAsync(cancellationToken);
        await db.Database.ExecuteSqlAsync($"SELECT 1", cancellationToken);
    }

    /// <summary>The versions both endpoints count: available, listed, and allowed by the filter.</summary>
    private static IQueryable<Package> Visible(GalleryDb db, PackageFilter filter)
    {
        var packages = db.Packages.Where(p => p.PackageStatusKey == Package.Available && p.Listed);
        packages = filter.IncludeSemVer2
            ? packages.Where(p => p.SemVerLevelKey == null || p.SemVerLevelKey == Package.SemVer2)
            : packages.Where(p => p.SemVerLevelKey == null);
        return filter.IncludePrerelease ? packages : packages.Where(p => !p.IsPrerelease);
    }
}
