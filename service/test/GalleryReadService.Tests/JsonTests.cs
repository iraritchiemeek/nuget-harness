using System.Text.Json;

namespace GalleryReadService.Tests;

public sealed class JsonTests
{
    private static readonly string[] VersionsWithMetadata =
    [
        "8.4.0+build.694",
        "3.3.0-ci.15+sha.f4793a7",
    ];

    [Fact]
    public void Build_metadata_plus_is_written_unescaped_like_MVC5_JsonResult() =>
        Assert.Equal(
            """["8.4.0+build.694","3.3.0-ci.15+sha.f4793a7"]""",
            JsonSerializer.Serialize(VersionsWithMetadata, PackageEndpoints.JsonOptions)
        );

    [Fact]
    public void An_empty_result_is_an_empty_array() =>
        Assert.Equal(
            "[]",
            JsonSerializer.Serialize(Array.Empty<string>(), PackageEndpoints.JsonOptions)
        );
}
