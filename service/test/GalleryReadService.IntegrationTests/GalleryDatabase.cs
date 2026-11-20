using System.Security.Cryptography;
using DotNet.Testcontainers.Configurations;
using Microsoft.Data.SqlClient;
using Testcontainers.MsSql;

[assembly: AssemblyFixture(typeof(GalleryReadService.IntegrationTests.GalleryDatabase))]

namespace GalleryReadService.IntegrationTests;

/// <summary>
/// SQL Server in a container, with the NuGetGallery database restored from the seed snapshot that
/// the old app was recorded against, and the read-only login the service uses. One per test run.
/// </summary>
public sealed class GalleryDatabase : IAsyncLifetime
{
    // The image the Linux parity job uses (scripts/linux/sql-server.sh), pinned by digest.
    private const string Image =
        "mcr.microsoft.com/mssql/server@sha256:4525e3efac9f3e241cb003bb2ff2a82818b502f37e12049d788b1a9fa7e13b7f";

    private readonly string _readerPassword = NewPassword();
    private readonly MsSqlContainer _container;

    public GalleryDatabase()
    {
        var snapshot = Environment.GetEnvironmentVariable("SEED_SNAPSHOT_DIR")
            ?? throw new InvalidOperationException(
                "Set SEED_SNAPSHOT_DIR to a downloaded seed-snapshot artifact."
            );
        _container = new MsSqlBuilder(Image)
            .WithPassword(NewPassword())
            .WithBindMount(Path.GetFullPath(snapshot), "/snapshot", AccessMode.ReadOnly)
            .Build();
    }

    /// <summary>The service's login: db_datareader on NuGetGallery, nothing else.</summary>
    public string ReaderConnectionString =>
        new SqlConnectionStringBuilder(_container.GetConnectionString())
        {
            InitialCatalog = "NuGetGallery",
            UserID = "reader",
            Password = _readerPassword,
        }.ConnectionString;

    /// <summary>The administrator login, for tests that change the data.</summary>
    public string AdminConnectionString =>
        new SqlConnectionStringBuilder(_container.GetConnectionString())
        {
            InitialCatalog = "NuGetGallery",
        }.ConnectionString;

    public async ValueTask InitializeAsync()
    {
        await _container.StartAsync();
        var result = await _container.ExecScriptAsync(
            $"""
            RESTORE DATABASE [NuGetGallery] FROM DISK = N'/snapshot/NuGetGallery.bak' WITH CHECKSUM,
              MOVE N'NuGetGallery' TO N'/var/opt/mssql/data/NuGetGallery.mdf',
              MOVE N'NuGetGallery_log' TO N'/var/opt/mssql/data/NuGetGallery_log.ldf';
            GO
            CREATE LOGIN [reader] WITH PASSWORD = N'{_readerPassword}', CHECK_POLICY = OFF;
            GO
            USE [NuGetGallery];
            CREATE USER [reader] FOR LOGIN [reader];
            ALTER ROLE [db_datareader] ADD MEMBER [reader];
            """
        );
        if (result.ExitCode != 0)
        {
            throw new InvalidOperationException($"restore failed: {result.Stderr}{result.Stdout}");
        }
    }

    public ValueTask DisposeAsync() => _container.DisposeAsync();

    /// <summary>Runs SQL as the administrator and returns the number of rows it changed.</summary>
    public async Task<int> ExecuteAsAdminAsync(string sql)
    {
        await using var connection = new SqlConnection(AdminConnectionString);
        await connection.OpenAsync(TestContext.Current.CancellationToken);
        await using var command = new SqlCommand(sql, connection);
        return await command.ExecuteNonQueryAsync(TestContext.Current.CancellationToken);
    }

    private static string NewPassword() => $"Pw1-{RandomNumberGenerator.GetHexString(32)}";
}
