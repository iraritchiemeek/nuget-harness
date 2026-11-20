namespace GalleryReadService;

/// <summary>A package ID (the <c>PackageRegistrations</c> table).</summary>
internal sealed class PackageRegistration
{
    public int Key { get; init; }

    public required string Id { get; init; }

    public long DownloadCount { get; init; }
}
