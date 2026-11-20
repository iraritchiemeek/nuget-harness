using System.Buffers;
using Microsoft.AspNetCore.Http.Features;

namespace GalleryReadService;

/// <summary>
/// What the old app's web server (http.sys, IIS and ASP.NET) does with a request before the old
/// app's own code runs: the requests it answers by itself, and how it changes the path that routing
/// sees. Each rule was read from the recordings (the groups "Path characters", "Whitespace other
/// than the space" and "Long paths and query strings" in recordings/requests.txt, first recorded in
/// exploratory record run 44674677772) and from NuGetGallery's src/NuGetGallery/Web.config.
/// The old app's answers to the rejected requests are the web server's own error pages, which the
/// parity checks compare by status only (spec 02 amendment A4), so the service sends the status
/// with an empty body.
/// </summary>
internal static class HostingRules
{
    /// <summary>
    /// The longest query string, in characters after the <c>?</c>, that reaches the app. Web.config
    /// sets both requestFiltering/requestLimits maxQueryString and httpRuntime maxQueryStringLength
    /// to 12000. IIS answers anything longer with 404.15.
    /// </summary>
    internal const int MaxQueryStringLength = 12_000;

    /// <summary>
    /// The longest decoded path that reaches the app: ASP.NET's httpRuntime maxUrlLength, which
    /// Web.config leaves at its default of 260. ASP.NET answers anything longer with 400 (and
    /// http.sys answers 400 itself for a single segment over 260 characters).
    /// </summary>
    internal const int MaxPathLength = 260;

    /// <summary>
    /// Kestrel's limit on the request line (method, target and version). Its default of 8 KB is
    /// below the 12000-character query strings the old app accepts, and Kestrel would answer 414
    /// before this code could answer as IIS does, so it is raised to http.sys's own limit for a
    /// URL (MaxFieldLength, 16 KB). This is the one Kestrel limit looser than its default, because
    /// matching the old app comes first (docs/engineering-standards.md).
    /// </summary>
    internal const int MaxRequestLineSize = 16 * 1024;

    /// <summary>
    /// Web.config httpRuntime requestPathInvalidCharacters is <c>&lt; &gt; * % : \ ?</c>. The
    /// backslash never gets there, because IIS turns it into a slash first (see <see cref="RoutingPath"/>).
    /// </summary>
    private static readonly SearchValues<char> InvalidPathCharacters = SearchValues.Create(
        "<>*%:?"
    );

    /// <summary>
    /// The status the web server answers with before the old app runs, or null when the request
    /// reaches the app. Checked in the order the layers see the request.
    /// </summary>
    /// <param name="path">The path decoded once, as IIS decodes it, encoded slashes included.</param>
    /// <param name="queryLength">The length of the raw query string, without the <c>?</c>.</param>
    public static int? Rejection(string path, int queryLength)
    {
        // http.sys: a control character in the path (recorded: %09 to %0D) makes the URL invalid.
        if (path.Any(c => char.IsAscii(c) && char.IsControl(c)))
        {
            return StatusCodes.Status400BadRequest;
        }
        // IIS request filtering: 404.15 for a long query string, and 404.11 for "+" (raw or %2B),
        // because allowDoubleEscaping is left at false.
        if (queryLength > MaxQueryStringLength || path.Contains('+', StringComparison.Ordinal))
        {
            return StatusCodes.Status404NotFound;
        }
        // ASP.NET: maxUrlLength and requestPathInvalidCharacters, checked before routing.
        if (path.Length > MaxPathLength || path.AsSpan().ContainsAny(InvalidPathCharacters))
        {
            return StatusCodes.Status400BadRequest;
        }
        return null;
    }

    /// <summary>
    /// The path the old app's routing sees, from the path decoded once:
    /// <list type="bullet">
    /// <item>A backslash is a slash (recorded: <c>Seri%5Clog</c> finds no route, as <c>Seri/log</c>).</item>
    /// <item>Trailing white space is trimmed (recorded: <c>Serilog%20</c> and <c>Serilog%C2%A0</c>
    /// answer as <c>Serilog</c>; <c>%20</c>, <c>%C2%A0</c> and <c>%E3%80%80</c> alone find no route).</item>
    /// <item>A final <c>.</c> segment left by the trim is dropped, as a dot segment (recorded:
    /// <c>.%20</c> finds no route). A trailing dot on an ID stays (<c>Serilog.</c> is another ID).</item>
    /// </list>
    /// </summary>
    public static string RoutingPath(string path)
    {
        var routed = path.Replace('\\', '/').TrimEnd();
        return routed.EndsWith("/.", StringComparison.Ordinal) ? routed[..^1] : routed;
    }

    /// <summary>
    /// Applies the rules to every request: answers the rejected ones, and gives routing the path
    /// the old app's routing would see. Kestrel decodes the path itself but leaves <c>%2F</c>
    /// encoded, so the path is decoded here from the raw request target, once, as IIS does.
    /// </summary>
    public static IApplicationBuilder UseHostingRules(this IApplicationBuilder app) =>
        app.Use(
            (context, next) =>
            {
                var target = context.Features.Get<IHttpRequestFeature>()?.RawTarget;
                if (target is null || !target.StartsWith('/'))
                {
                    target = context.Request.Path.ToUriComponent() + context.Request.QueryString;
                }
                var queryStart = target.IndexOf('?', StringComparison.Ordinal);
                var rawPath = queryStart < 0 ? target : target[..queryStart];
                var queryLength = queryStart < 0 ? 0 : target.Length - queryStart - 1;
                var path = Uri.UnescapeDataString(rawPath);

                if (Rejection(path, queryLength) is { } status)
                {
                    context.Response.StatusCode = status;
                    return Task.CompletedTask;
                }
                context.Request.Path = new PathString(RoutingPath(path));
                return next(context);
            }
        );
}
