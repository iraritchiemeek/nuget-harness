using System.ComponentModel.DataAnnotations;

namespace GalleryReadService;

/// <summary>Where the gallery database is. Bound from the <c>Database</c> configuration section.</summary>
internal sealed class DatabaseOptions
{
    public const string Section = "Database";

    /// <summary>
    /// A connection string for a login with read-only rights (db_datareader). It comes from
    /// configuration or the <c>Database__ConnectionString</c> environment variable, never from source.
    /// </summary>
    [Required]
    public string ConnectionString { get; set; } = "";
}
