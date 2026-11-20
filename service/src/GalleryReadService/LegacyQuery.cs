using Microsoft.Extensions.Primitives;

namespace GalleryReadService;

/// <summary>
/// Reads query-string values the way ASP.NET MVC 5's model binder fills the old app's action
/// parameters (ApiController.GetPackageIds and GetPackageVersions in NuGetGallery). Keys match
/// case-insensitively in both frameworks; the differences are handled here.
/// </summary>
internal static class LegacyQuery
{
    /// <summary>
    /// MVC 5 binds the first value when a key repeats (<c>?partialId=a&amp;partialId=b</c> binds "a"),
    /// where ASP.NET Core would join them as "a,b".
    /// </summary>
    public static string? Text(IQueryCollection query, string key)
    {
        StringValues values = query[key];
        return values.Count > 0 ? values[0] : null;
    }

    /// <summary>
    /// A <c>bool?</c> parameter binds "true" or "false" in any case, with surrounding whitespace.
    /// Any other value (<c>1</c>, <c>yes</c>, empty) binds null instead of failing the request.
    /// </summary>
    public static bool? Boolean(IQueryCollection query, string key) =>
        bool.TryParse(Text(query, key), out var value) ? value : null;
}
