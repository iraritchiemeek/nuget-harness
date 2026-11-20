using CsCheck;
using NuGet.Versioning;

namespace GalleryReadService.Tests;

public sealed class VersionOrderTests
{
    [Theory]
    [InlineData("1.4.128,1.3.30,4.4.0", "1.3.30,1.4.128,4.4.0")]
    [InlineData("2.0.143,1.42,2.1.89", "1.42,2.0.143,2.1.89")]
    [InlineData("1.42,1.4.128", "1.4.128,1.42")]
    [InlineData("1.0.0.1,1.0.0", "1.0.0,1.0.0.1")]
    [InlineData("2.0.0,2.0.0-beta", "2.0.0-beta,2.0.0")]
    [InlineData("1.0.0-rc.10,1.0.0-rc.2,1.0.0-rc.2.1", "1.0.0-rc.2,1.0.0-rc.2.1,1.0.0-rc.10")]
    [InlineData("1.0.0-beta,1.0.0-Alpha", "1.0.0-Alpha,1.0.0-beta")]
    [InlineData("1.0.0-alpha,1.0.0-1", "1.0.0-1,1.0.0-alpha")]
    [InlineData("2.0.0+b,1.0.0+z", "1.0.0+z,2.0.0+b")]
    public void Versions_sort_oldest_first_in_SemVer_order(string versions, string expected) =>
        Assert.Equal(expected.Split(','), VersionOrder.Sort(versions.Split(',')));

    [Theory]
    [InlineData("1.0.0,1.0", "1.0,1.0.0")]
    [InlineData("1.0.0+b,1.0.0+a", "1.0.0+a,1.0.0+b")]
    [InlineData("1.0.0-RC,1.0.0-rc", "1.0.0-RC,1.0.0-rc")]
    public void Versions_equal_in_SemVer_order_fall_back_to_ordinal_order(
        string versions,
        string expected
    ) => Assert.Equal(expected.Split(','), VersionOrder.Sort(versions.Split(',')));

    [Fact]
    public void A_string_that_is_not_a_version_throws() =>
        Assert.Throws<ArgumentException>(() => VersionOrder.Sort(["1.0.0", "not-a-version"]));

    [Fact]
    public void Sorting_keeps_every_version_and_orders_them_by_NuGet_version() =>
        Gen.Select(
                Gen.Int[0, 3],
                Gen.Int[0, 12],
                Gen.Int[0, 3],
                Gen.OneOf<string>("", "-alpha", "-beta.2", "-rc.10", "+meta")
            )
            .Select((major, minor, patch, suffix) => $"{major}.{minor}.{patch}{suffix}")
            .Array[0, 12]
            .Sample(versions =>
            {
                var sorted = VersionOrder.Sort(versions);
                Assert.Equal(
                    versions.Order(StringComparer.Ordinal),
                    sorted.Order(StringComparer.Ordinal)
                );
                for (var i = 1; i < sorted.Count; i++)
                {
                    Assert.True(
                        VersionComparer.Default.Compare(
                            NuGetVersion.Parse(sorted[i - 1]),
                            NuGetVersion.Parse(sorted[i])
                        ) <= 0
                    );
                }
            });
}
