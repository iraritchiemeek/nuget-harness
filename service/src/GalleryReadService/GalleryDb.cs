using Microsoft.EntityFrameworkCore;

namespace GalleryReadService;

/// <summary>
/// The two tables of the old app's database that the endpoints read, mapped for queries only. The
/// old app owns the schema: there are no migrations, and the service's login can only read.
/// Every query runs without change tracking.
/// </summary>
internal sealed class GalleryDb(DbContextOptions<GalleryDb> options) : DbContext(options)
{
    public DbSet<Package> Packages => Set<Package>();

    public DbSet<PackageRegistration> PackageRegistrations => Set<PackageRegistration>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<PackageRegistration>(registration =>
        {
            registration.ToTable("PackageRegistrations", "dbo");
            registration.HasKey(r => r.Key);
            registration.Property(r => r.Id).HasMaxLength(128);
        });
        modelBuilder.Entity<Package>(package =>
        {
            package.ToTable("Packages", "dbo");
            package.HasKey(p => p.Key);
            package.Property(p => p.Version).HasMaxLength(64);
            package
                .HasOne(p => p.PackageRegistration)
                .WithMany()
                .HasForeignKey(p => p.PackageRegistrationKey);
        });
    }
}
