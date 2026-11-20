using CsCheck;

namespace GalleryReadService.Tests;

public sealed class LikePatternTests
{
    [Theory]
    [InlineData("Serilog", "Serilog%")]
    [InlineData("", "%")]
    [InlineData("Seri%og", "Seri~%og%")]
    [InlineData("Seri_og", "Seri~_og%")]
    [InlineData("Seri[lo]og", "Seri~[lo]og%")]
    [InlineData("Seri~log", "Seri~~log%")]
    [InlineData("a]b^c-d", "a]b^c-d%")]
    public void Wildcards_and_the_escape_character_are_escaped_with_a_tilde(
        string prefix,
        string pattern
    ) => Assert.Equal(pattern, LikePattern.StartsWith(prefix));

    [Fact]
    public void Unescaping_the_pattern_gives_back_the_prefix() =>
        Gen.String.Sample(prefix =>
        {
            var pattern = LikePattern.StartsWith(prefix);
            Assert.EndsWith("%", pattern, StringComparison.Ordinal);
            Assert.Equal(prefix, Unescape(pattern[..^1]));
        });

    // Reads a pattern the way SQL Server does with ESCAPE N'~': a tilde makes the next character literal,
    // and no unescaped wildcard may remain.
    private static string Unescape(string pattern)
    {
        var text = new System.Text.StringBuilder();
        for (var i = 0; i < pattern.Length; i++)
        {
            var c = pattern[i];
            if (c == '~')
            {
                text.Append(pattern[++i]);
            }
            else
            {
                Assert.DoesNotContain(c, "%_[");
                text.Append(c);
            }
        }
        return text.ToString();
    }
}
