using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.WebUtilities;

namespace GalleryReadService.Tests;

public sealed class PackageFilterTests
{
    [Theory]
    [InlineData("2.0.0")]
    [InlineData("2.0.0.0")]
    [InlineData("2.0")]
    [InlineData("2")]
    [InlineData("3.0.0")]
    [InlineData("2.0.1")]
    [InlineData("2.0.0+meta")]
    public void A_level_of_at_least_2_0_0_includes_SemVer2_versions(string level) =>
        Assert.True(PackageFilter.IsSemVer2Level(level));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("1.0.0")]
    [InlineData("1.9.9")]
    [InlineData("2.0.0-beta")]
    [InlineData("banana")]
    [InlineData(" ")]
    public void Any_other_level_means_SemVer1_only(string? level) =>
        Assert.False(PackageFilter.IsSemVer2Level(level));

    [Theory]
    [InlineData("", false, false)]
    [InlineData("?includePrerelease=true", true, false)]
    [InlineData("?includePrerelease=yes", false, false)]
    [InlineData("?semVerLevel=2.0.0", false, true)]
    [InlineData("?includePrerelease=true&semVerLevel=2.0.0", true, true)]
    [InlineData("?INCLUDEPRERELEASE=true&SEMVERLEVEL=2.0.0", true, true)]
    public void Prerelease_and_SemVer2_versions_are_hidden_unless_requested(
        string queryString,
        bool includePrerelease,
        bool includeSemVer2
    ) =>
        Assert.Equal(
            new PackageFilter(includePrerelease, includeSemVer2),
            PackageFilter.FromQuery(new QueryCollection(QueryHelpers.ParseQuery(queryString)))
        );
}
