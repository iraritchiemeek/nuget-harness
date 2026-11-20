namespace GalleryReadService;

/// <summary>One version of a package (the <c>Packages</c> table), with the columns the filters use.</summary>
internal sealed class Package
{
    /// <summary>NuGetGallery's PackageStatus.Available.</summary>
    public const int Available = 0;

    /// <summary>NuGetGallery's SemVerLevelKey.SemVer2. A null key means SemVer 1.0.0.</summary>
    public const int SemVer2 = 2;

    public int Key { get; init; }

    public int PackageRegistrationKey { get; init; }

    public PackageRegistration PackageRegistration { get; init; } = null!;

    /// <summary>The version string as it was pushed, not normalised.</summary>
    public required string Version { get; init; }

    public int PackageStatusKey { get; init; }

    public bool Listed { get; init; }

    public bool IsPrerelease { get; init; }

    public int? SemVerLevelKey { get; init; }
}
