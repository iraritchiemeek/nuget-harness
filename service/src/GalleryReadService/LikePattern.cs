using System.Text;

namespace GalleryReadService;

/// <summary>
/// Builds a SQL LIKE pattern for "starts with", escaped the way Entity Framework 6 escapes the
/// argument of <c>string.StartsWith</c> (SqlProviderManifest.EscapeLikeText): the wildcard
/// characters <c>%</c>, <c>_</c> and <c>[</c>, and the escape character <c>~</c> itself, are
/// prefixed with <c>~</c>, and the query says <c>ESCAPE N'~'</c>.
/// </summary>
internal static class LikePattern
{
    private const char Escape = '~';

    public static string StartsWith(string prefix)
    {
        var pattern = new StringBuilder(prefix.Length + 2);
        foreach (var c in prefix)
        {
            if (c is '%' or '_' or '[' or Escape)
            {
                pattern.Append(Escape);
            }
            pattern.Append(c);
        }
        return pattern.Append('%').ToString();
    }
}
