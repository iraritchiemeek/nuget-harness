using NuGet.Versioning;

namespace GalleryReadService;

/// <summary>
/// SemVer order for version strings as they were pushed, oldest first: the order NuGet clients use
/// (NuGet.Versioning's <see cref="VersionComparer.Default"/>, which ignores build metadata).
/// </summary>
internal static class VersionOrder
{
    /// <summary>
    /// Sorts <paramref name="versions"/> oldest first. Versions equal in SemVer order, such as
    /// <c>1.0</c> and <c>1.0.0</c>, fall back to the ordinal order of the strings, so the order is
    /// always defined; the gallery refuses such duplicates anyway. A string that is not a NuGet
    /// version throws <see cref="ArgumentException"/>: the gallery validates every version it
    /// stores, so that means a broken database, and guessing its place would hide it.
    /// </summary>
    public static IReadOnlyList<string> Sort(IEnumerable<string> versions) =>
        [
            .. versions
                .Select(text => (Text: text, Version: NuGetVersion.Parse(text)))
                .OrderBy(v => v.Version, VersionComparer.Default)
                .ThenBy(v => v.Text, StringComparer.Ordinal)
                .Select(v => v.Text),
        ];
}
