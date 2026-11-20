using CsCheck;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.WebUtilities;

namespace GalleryReadService.Tests;

public sealed class LegacyQueryTests
{
    private static QueryCollection Query(string queryString) =>
        new(QueryHelpers.ParseQuery(queryString));

    [Fact]
    public void A_repeated_key_binds_its_first_value() =>
        Assert.Equal(
            "Serilog",
            LegacyQuery.Text(Query("?partialId=Serilog&partialId=Polly"), "partialId")
        );

    [Fact]
    public void Keys_match_case_insensitively() =>
        Assert.Equal("Serilog", LegacyQuery.Text(Query("?PARTIALID=Serilog"), "partialId"));

    [Fact]
    public void A_missing_key_binds_null() =>
        Assert.Null(LegacyQuery.Text(Query("?other=1"), "partialId"));

    [Fact]
    public void An_empty_value_binds_the_empty_string() =>
        Assert.Equal("", LegacyQuery.Text(Query("?partialId="), "partialId"));

    [Theory]
    [InlineData("?includePrerelease=true", true)]
    [InlineData("?includePrerelease=TRUE", true)]
    [InlineData("?includePrerelease=True", true)]
    [InlineData("?includePrerelease=%20true%20", true)]
    [InlineData("?includePrerelease=false", false)]
    [InlineData("?includePrerelease=False", false)]
    public void A_boolean_binds_true_or_false_in_any_case(string queryString, bool expected) =>
        Assert.Equal(expected, LegacyQuery.Boolean(Query(queryString), "includePrerelease"));

    [Theory]
    [InlineData("?includePrerelease=1")]
    [InlineData("?includePrerelease=yes")]
    [InlineData("?includePrerelease=")]
    [InlineData("?other=true")]
    public void A_boolean_that_does_not_parse_binds_null(string queryString) =>
        Assert.Null(LegacyQuery.Boolean(Query(queryString), "includePrerelease"));

    [Fact]
    public void Only_true_and_false_bind_a_boolean() =>
        Gen.String.Sample(value =>
        {
            var query = new QueryCollection(
                new Dictionary<string, Microsoft.Extensions.Primitives.StringValues>(
                    StringComparer.OrdinalIgnoreCase
                )
                {
                    ["includePrerelease"] = value,
                }
            );
            var expected = value.Trim().ToUpperInvariant() switch
            {
                "TRUE" => true,
                "FALSE" => (bool?)false,
                _ => null,
            };
            Assert.Equal(expected, LegacyQuery.Boolean(query, "includePrerelease"));
        });
}
