using System.Text.Encodings.Web;
using System.Text.Json;
using Microsoft.AspNetCore.Http.HttpResults;

namespace GalleryReadService;

/// <summary>
/// The two read endpoints of the gallery's V2 API (NuGetGallery src/NuGetGallery/App_Start/Routes.cs,
/// routes v2PackageIds and v2PackageVersions; Controllers/ApiController.cs, GetPackageIds and
/// GetPackageVersions).
/// </summary>
internal static class PackageEndpoints
{
    /// <summary>
    /// The old app serialises with MVC 5's JsonResult (JavaScriptSerializer), which does not escape
    /// <c>+</c>, as in a version with build metadata such as <c>1.0.0+abc</c>. System.Text.Json's
    /// default encoder would write it as <c>+</c>. The relaxed encoder writes it as is. It is
    /// "unsafe" only for embedding in HTML, and these responses are JSON.
    /// </summary>
    internal static readonly JsonSerializerOptions Json = new()
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public static IEndpointRouteBuilder MapPackageEndpoints(this IEndpointRouteBuilder app)
    {
        var v2 = app.MapGroup("/api/v2");
        v2.MapGet("/package-ids", GetPackageIdsAsync);
        v2.MapGet("/package-versions/{id}", GetPackageVersionsAsync);
        return app;
    }

    internal static async Task<JsonHttpResult<IReadOnlyList<string>>> GetPackageIdsAsync(
        HttpRequest request,
        PackageQueries queries,
        CancellationToken cancellationToken
    )
    {
        var partialId = LegacyQuery.Text(request.Query, "partialId");
        var ids = await queries.GetPackageIdsAsync(
            partialId,
            PackageFilter.FromQuery(request.Query),
            cancellationToken
        );
        return TypedResults.Json(ids, Json);
    }

    internal static async Task<
        Results<JsonHttpResult<IReadOnlyList<string>>, StatusCodeHttpResult>
    > GetPackageVersionsAsync(
        string id,
        HttpRequest request,
        PackageQueries queries,
        CancellationToken cancellationToken
    )
    {
        // The old query throws ArgumentNullException for a blank id, and the controller answers 500
        // (AutocompleteDatabasePackageVersionsQuery.cs). Its body is not reproduced: for a local
        // client it is a stack trace, and the request is not in the recorded set (recordings/requests.txt).
        if (string.IsNullOrWhiteSpace(id))
        {
            return TypedResults.StatusCode(StatusCodes.Status500InternalServerError);
        }

        var versions = await queries.GetPackageVersionsAsync(
            id,
            PackageFilter.FromQuery(request.Query),
            cancellationToken
        );
        return TypedResults.Json(versions, Json);
    }
}
