-- Spec 02 check 4: change the restored state A database directly, as the administrator, so that
-- answers the recordings cannot contain must come from the database. scripts/linux/data-change-check.ps1
-- runs this, then checks each affected response against the recording plus the change below.
-- New rows are copies of existing rows with a few columns changed, so every other NOT NULL column
-- holds a value the old app wrote.
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRANSACTION;

-- Copies one Packages row with a new version, registration, prerelease flag and SemVer level.
DECLARE @source int = (SELECT TOP (1) p.[Key] FROM dbo.Packages p
  JOIN dbo.PackageRegistrations r ON r.[Key] = p.PackageRegistrationKey
  WHERE r.Id = N'Serilog' ORDER BY p.[Key]);

-- 1. A new stable version of an existing ID: Serilog 9.9.9.
SELECT * INTO #p FROM dbo.Packages WHERE [Key] = @source;
ALTER TABLE #p DROP COLUMN [Key];
UPDATE #p SET Version = N'9.9.9', NormalizedVersion = N'9.9.9', IsPrerelease = 0, SemVerLevelKey = NULL, Listed = 1;
INSERT INTO dbo.Packages SELECT * FROM #p;

-- 2. Unlist one version of an existing ID: Serilog.Sinks.Console, its lowest-keyed version.
UPDATE dbo.Packages SET Listed = 0 WHERE [Key] = (SELECT TOP (1) p.[Key] FROM dbo.Packages p
  JOIN dbo.PackageRegistrations r ON r.[Key] = p.PackageRegistrationKey
  WHERE r.Id = N'Serilog.Sinks.Console' ORDER BY p.[Key]);

-- 3. A new ID under an existing prefix, with one stable version: Serilog.Sinks.ZzHarness 1.0.0.
-- 4. A new ID whose only version is a SemVer 2.0.0 prerelease: Serilog.ZzHarness 1.0.0-beta.1, so
--    package-ids shows it only with includePrerelease=true and semVerLevel=2.0.0.
SELECT * INTO #r FROM dbo.PackageRegistrations WHERE Id = N'Serilog';
ALTER TABLE #r DROP COLUMN [Key];
UPDATE #r SET Id = N'Serilog.Sinks.ZzHarness';
INSERT INTO dbo.PackageRegistrations SELECT * FROM #r;
DECLARE @sinks int = SCOPE_IDENTITY();
UPDATE #r SET Id = N'Serilog.ZzHarness';
INSERT INTO dbo.PackageRegistrations SELECT * FROM #r;
DECLARE @semver2 int = SCOPE_IDENTITY();

UPDATE #p SET PackageRegistrationKey = @sinks, Version = N'1.0.0', NormalizedVersion = N'1.0.0';
INSERT INTO dbo.Packages SELECT * FROM #p;
UPDATE #p SET PackageRegistrationKey = @semver2, Version = N'1.0.0-beta.1', NormalizedVersion = N'1.0.0-beta.1',
  IsPrerelease = 1, SemVerLevelKey = 2;
INSERT INTO dbo.Packages SELECT * FROM #p;

COMMIT;
SELECT N'unlisted', p.Version FROM dbo.Packages p JOIN dbo.PackageRegistrations r ON r.[Key] = p.PackageRegistrationKey
  WHERE r.Id = N'Serilog.Sinks.Console' AND p.Listed = 0;
