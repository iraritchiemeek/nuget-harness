namespace GalleryReadService;

/// <summary>
/// Response headers the old app adds to every response, so the new service sends them too.
/// </summary>
internal static class GalleryResponseHeaders
{
    public static IApplicationBuilder UseGalleryResponseHeaders(this IApplicationBuilder app) =>
        app.Use(
            (context, next) =>
            {
                var headers = context.Response.Headers;
                // NuGetGallery src/NuGetGallery/Web.config, system.webServer/httpProtocol/customHeaders.
                headers.XFrameOptions = "deny";
                headers.XContentTypeOptions = "nosniff";
                headers.StrictTransportSecurity = "max-age=31536000; includeSubDomains";
                // ASP.NET (System.Web) marks every response it does not otherwise cache as private.
                headers.CacheControl = "private";
                return next(context);
            }
        );
}
