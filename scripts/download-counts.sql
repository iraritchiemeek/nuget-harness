-- Distinct download counts for 32 seeded IDs, every other ID at 0. The seed has every count at 0,
-- so without this the most-downloaded order (package-ids with a blank partialId) could not be told
-- from any other. The counts follow neither ID order nor key (push) order, and the cap of 30 cuts
-- off the last two. Run as the administrator, on SQL Server in Docker by
-- scripts/linux/data-change-check.ps1 (spec 02 check 4) and on LocalDB by live-parity.yml (check 6).
-- Lists the IDs it gave a count, so the caller can work out the expected order.
SET NOCOUNT ON;
UPDATE dbo.PackageRegistrations SET DownloadCount = 0;
UPDATE r SET DownloadCount = c.n FROM dbo.PackageRegistrations r JOIN (VALUES
  (N'Moq', 9100), (N'Polly', 8700), (N'Ninject', 8650), (N'Dapper', 8200), (N'Refit', 7900), (N'Bogus', 7400),
  (N'NodaTime', 7100), (N'AutoMapper', 6800), (N'Shouldly', 6500), (N'Castle.Core', 6100), (N'MailKit', 5900),
  (N'Quartz', 5600), (N'CsvHelper', 5300), (N'NLog', 5000), (N'FluentValidation', 4700), (N'Scrutor', 4400),
  (N'Humanizer.Core', 4100), (N'MimeKit', 3800), (N'OneOf', 3500), (N'RestSharp', 3200), (N'MediatR', 2900),
  (N'Autofac', 2600), (N'SimpleInjector', 2300), (N'Spectre.Console', 2000), (N'HtmlAgilityPack', 1700),
  (N'NSubstitute', 1400), (N'StackExchange.Redis', 1100), (N'SharpZipLib', 800), (N'DotNetZip', 500),
  (N'FluentAssertions', 300), (N'CommandLineParser', 200), (N'Hangfire.Core', 100)
) AS c (Id, n) ON c.Id = r.Id;

SELECT N'downloads' AS kind, Id, DownloadCount FROM dbo.PackageRegistrations WHERE DownloadCount > 0;
