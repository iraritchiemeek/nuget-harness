using System.Data;
using System.Text;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Options;

namespace GalleryReadService;

/// <summary>
/// The two read queries, against the database the old app owns. The service never writes and runs
/// no migrations.
/// </summary>
/// <remarks>
/// The SQL repeats, clause for clause, what NuGetGallery's Entity Framework 6 queries generate
/// (src/NuGetGallery/Queries/AutocompleteDatabasePackageIdsQuery.cs and
/// AutocompleteDatabasePackageVersionsQuery.cs). The text was read from the old app's database
/// plan cache by the recording workflow (scripts/runner/dump-sql.ps1). Matching, sorting and the
/// order of unsorted results are all decided by SQL Server, so they must stay in SQL:
/// <list type="bullet">
/// <item>IDs and prefixes match case-insensitively, under the database collation.</item>
/// <item><c>package-versions</c> has no ORDER BY. Versions come back in the order the query plan reads them.</item>
/// <item>With no prefix, the 30 most-downloaded IDs are returned, and ties keep the plan's order.</item>
/// </list>
/// Each query is built from the constant clauses below, chosen by the two filter flags, the way
/// Entity Framework composed it. Values are always parameters.
/// </remarks>
internal sealed class PackageQueries(IOptions<DatabaseOptions> options)
{
    private const string WhereAvailableAndListed =
        " WHERE (0 = [Extent1].[PackageStatusKey]) AND ([Extent1].[Listed] = 1)";
    private const string SemVer1Only = " AND ([Extent1].[SemVerLevelKey] IS NULL)";
    private const string SemVer1Or2 =
        " AND ([Extent1].[SemVerLevelKey] = 2 OR [Extent1].[SemVerLevelKey] IS NULL)";
    private const string StableOnly = " AND ([Extent1].[IsPrerelease] <> 1)";
    private const string PackagesJoin =
        " FROM [dbo].[Packages] AS [Extent1]"
        + " INNER JOIN [dbo].[PackageRegistrations] AS [Extent2]"
        + " ON [Extent1].[PackageRegistrationKey] = [Extent2].[Key]";

    private const string VersionsQuery =
        "SELECT [Extent1].[Version] AS [Version]"
        + PackagesJoin
        + WhereAvailableAndListed
        + " AND ([Extent2].[Id] = @id)";

    private const string IdsByPrefixQuery =
        "SELECT TOP (30) [Distinct1].[Id] AS [Id] FROM (SELECT DISTINCT [Extent2].[Id] AS [Id]"
        + PackagesJoin
        + WhereAvailableAndListed
        + " AND ([Extent2].[Id] LIKE @prefix ESCAPE N'~')";
    private const string IdsByPrefixEnd = ") AS [Distinct1] ORDER BY [Distinct1].[Id] ASC";

    // DISTINCT over every scalar column of PackageRegistrations, as Entity Framework wrote it for
    // .Select(p => p.PackageRegistration).Distinct(). The columns shape the plan, and so the order of ties.
    private const string MostDownloadedIdsQuery =
        "SELECT TOP (30) [Distinct1].[Id] AS [Id] FROM (SELECT DISTINCT [Extent2].[Key] AS [Key],"
        + " [Extent2].[Id] AS [Id], [Extent2].[DownloadCount] AS [DownloadCount],"
        + " [Extent2].[IsVerified] AS [IsVerified], [Extent2].[IsLocked] AS [IsLocked],"
        + " [Extent2].[RenamedMessage] AS [RenamedMessage], [Extent2].[SponsorshipUrls] AS [SponsorshipUrls]"
        + PackagesJoin
        + WhereAvailableAndListed;
    private const string MostDownloadedIdsEnd =
        ") AS [Distinct1] ORDER BY [Distinct1].[DownloadCount] DESC";

    // Entity Framework sent every string parameter as nvarchar(4000).
    private const int StringParameterSize = 4000;

    private readonly string _connectionString = options.Value.ConnectionString;

    /// <summary>Up to 30 package IDs that start with <paramref name="partialId"/>, in ID order.
    /// A blank <paramref name="partialId"/> asks for the most-downloaded IDs instead.</summary>
    public Task<IReadOnlyList<string>> GetPackageIdsAsync(
        string? partialId,
        PackageFilter filter,
        CancellationToken cancellationToken
    )
    {
        if (string.IsNullOrWhiteSpace(partialId))
        {
            var sql = WithFilter(MostDownloadedIdsQuery, filter) + MostDownloadedIdsEnd;
            return ReadStringsAsync(sql, parameter: null, cancellationToken);
        }

        var prefix = StringParameter("@prefix", LikePattern.StartsWith(partialId));
        return ReadStringsAsync(
            WithFilter(IdsByPrefixQuery, filter) + IdsByPrefixEnd,
            prefix,
            cancellationToken
        );
    }

    /// <summary>The version strings of package <paramref name="id"/>, as they were pushed.</summary>
    public Task<IReadOnlyList<string>> GetPackageVersionsAsync(
        string id,
        PackageFilter filter,
        CancellationToken cancellationToken
    ) =>
        ReadStringsAsync(
            WithFilter(VersionsQuery, filter),
            StringParameter("@id", id),
            cancellationToken
        );

    /// <summary>Opens a connection and runs a trivial query, for startup and the health check.</summary>
    public async Task CheckConnectionAsync(CancellationToken cancellationToken)
    {
        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new SqlCommand("SELECT 1", connection);
        await command.ExecuteScalarAsync(cancellationToken);
    }

    private static string WithFilter(string query, PackageFilter filter)
    {
        var sql = new StringBuilder(query);
        sql.Append(filter.IncludeSemVer2 ? SemVer1Or2 : SemVer1Only);
        if (!filter.IncludePrerelease)
        {
            sql.Append(StableOnly);
        }
        return sql.ToString();
    }

    private static SqlParameter StringParameter(string name, string value) =>
        new(name, SqlDbType.NVarChar, StringParameterSize) { Value = value };

    private async Task<IReadOnlyList<string>> ReadStringsAsync(
        string sql,
        SqlParameter? parameter,
        CancellationToken cancellationToken
    )
    {
        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new SqlCommand(sql, connection);
        if (parameter is not null)
        {
            command.Parameters.Add(parameter);
        }

        var values = new List<string>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            values.Add(reader.GetString(0));
        }
        return values;
    }
}
