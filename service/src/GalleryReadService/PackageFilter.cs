using NuGet.Versioning;

namespace GalleryReadService;

/// <summary>
/// Which package versions count, from the <c>includePrerelease</c> and <c>semVerLevel</c> query
/// parameters. Both endpoints always require Available and Listed versions on top of this.
/// </summary>
/// <param name="IncludePrerelease">Prerelease versions count only when asked for.</param>
/// <param name="IncludeSemVer2">SemVer 2.0.0 versions count only when <c>semVerLevel</c> asks for them.</param>
internal sealed record PackageFilter(bool IncludePrerelease, bool IncludeSemVer2)
{
    private static readonly NuGetVersion SemVer2 = new(2, 0, 0);

    public static PackageFilter FromQuery(IQueryCollection query) =>
        new(
            LegacyQuery.Boolean(query, "includePrerelease") ?? false,
            IsSemVer2Level(LegacyQuery.Text(query, "semVerLevel"))
        );

    /// <summary>
    /// NuGetGallery.Core SemVerLevelKey.ForSemVerLevel: a value that NuGetVersion parses and that is
    /// at least 2.0.0 means SemVer 2.0.0. Anything else, including a missing value, means SemVer 1.
    /// </summary>
    internal static bool IsSemVer2Level(string? semVerLevel) =>
        NuGetVersion.TryParse(semVerLevel, out var level) && level >= SemVer2;
}
