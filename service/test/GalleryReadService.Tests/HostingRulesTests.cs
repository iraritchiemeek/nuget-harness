namespace GalleryReadService.Tests;

/// <summary>
/// The old app's web server answers these requests itself. Each case is a recorded request (see
/// recordings/requests.txt), as the path decoded once and the length of its query string.
/// </summary>
public sealed class HostingRulesTests
{
    [Theory]
    [InlineData("/api/v2/package-versions/\t")]
    [InlineData("/api/v2/package-versions/Serilog\t")]
    [InlineData("/api/v2/package-versions/ \t")]
    [InlineData("/api/v2/package-versions/\v")]
    [InlineData("/api/v2/package-versions/\f")]
    [InlineData("/api/v2/package-versions/\n")]
    [InlineData("/api/v2/package-versions/\r")]
    public void A_control_character_in_the_path_is_a_bad_request(string path) =>
        Assert.Equal(400, HostingRules.Rejection(path, 0));

    [Theory]
    [InlineData("/api/v2/package-versions/Serilog+Sinks")]
    [InlineData("/api/v2/package-versions/Serilog.Exceptions+8.4.0")]
    public void A_plus_in_the_path_is_not_found(string path) =>
        Assert.Equal(404, HostingRules.Rejection(path, 0));

    [Theory]
    [InlineData('<')]
    [InlineData('>')]
    [InlineData('*')]
    [InlineData('%')]
    [InlineData(':')]
    [InlineData('?')]
    public void A_character_in_requestPathInvalidCharacters_is_a_bad_request(char c) =>
        Assert.Equal(400, HostingRules.Rejection($"/api/v2/package-versions/Seri{c}log", 0));

    [Fact]
    public void A_query_string_over_12000_characters_is_not_found()
    {
        Assert.Null(HostingRules.Rejection("/api/v2/package-ids", 12_000));
        Assert.Equal(404, HostingRules.Rejection("/api/v2/package-ids", 12_001));
    }

    [Fact]
    public void A_path_over_260_characters_is_a_bad_request()
    {
        const string route = "/api/v2/package-versions/";
        Assert.Null(HostingRules.Rejection(route + new string('a', 260 - route.Length), 0));
        Assert.Equal(400, HostingRules.Rejection(route + new string('a', 261 - route.Length), 0));
    }

    [Theory]
    [InlineData("/api/v2/package-versions/Serilog")]
    [InlineData("/api/v2/package-versions/Serilog/")]
    [InlineData("/api/v2/package-versions/Serilog.")]
    [InlineData("/api/v2/package-versions/ Serilog")]
    [InlineData("/api/v2/package-versions/Serilog ")]
    [InlineData("/api/v2/package-versions/Seri\\log")]
    public void Other_paths_reach_the_app(string path) =>
        Assert.Null(HostingRules.Rejection(path, 0));

    [Theory]
    [InlineData("/api/v2/package-versions/Serilog ", "/api/v2/package-versions/Serilog")]
    [InlineData("/api/v2/package-versions/Serilog ", "/api/v2/package-versions/Serilog")]
    [InlineData("/api/v2/package-versions/　", "/api/v2/package-versions/")]
    [InlineData("/api/v2/package-versions/  ", "/api/v2/package-versions/")]
    [InlineData("/api/v2/package-versions/. ", "/api/v2/package-versions/")]
    [InlineData("/api/v2/package-versions/Serilog. ", "/api/v2/package-versions/Serilog.")]
    [InlineData("/api/v2/package-versions/Serilog .", "/api/v2/package-versions/Serilog .")]
    [InlineData("/api/v2/package-versions/ Serilog", "/api/v2/package-versions/ Serilog")]
    [InlineData("/api/v2/package-versions/Seri\\log", "/api/v2/package-versions/Seri/log")]
    [InlineData("/api/v2/package-versions/Serilog/", "/api/v2/package-versions/Serilog/")]
    public void Routing_sees_the_path_as_the_old_apps_web_server_passes_it_on(
        string path,
        string routed
    ) => Assert.Equal(routed, HostingRules.RoutingPath(path));
}
