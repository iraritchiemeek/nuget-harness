#!/usr/bin/env bash
# Print a fingerprint of the NuGetGallery database in the SQL Server container started by
# sql-server.sh, for spec 02 check 7 (the new service writes nothing): taken before and after the
# full request set, the two must be identical.
#   - every table: row count and CHECKSUM_AGG(BINARY_CHECKSUM(*))
#   - the two tables the service reads: SHA-256 of the whole table as JSON, ordered by key, which
#     catches any change to any column, unlike the 32-bit aggregate checksum
# Usage: db-fingerprint.sh > file. Needs SA_PASSWORD.
set -euo pipefail
: "${SA_PASSWORD:?SA_PASSWORD must be set}"

"$(dirname "$0")/sqlcmd.sh" -d NuGetGallery -h -1 -W -s ' ' -Q "SET NOCOUNT ON;
  DECLARE @sql nvarchar(max) = N'';
  SELECT @sql += N'SELECT N''' + s.name + N'.' + t.name + N''' AS t, COUNT_BIG(*) AS n, CHECKSUM_AGG(BINARY_CHECKSUM(*)) AS c FROM '
    + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) + N' UNION ALL '
  FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id;
  SET @sql = LEFT(@sql, LEN(@sql) - LEN(N' UNION ALL')) + N' ORDER BY t';
  EXEC (@sql);
  SELECT N'sha256 dbo.Packages', CONVERT(char(64), HASHBYTES('SHA2_256',
    CAST((SELECT * FROM dbo.Packages ORDER BY [Key] FOR JSON PATH) AS nvarchar(max))), 2);
  SELECT N'sha256 dbo.PackageRegistrations', CONVERT(char(64), HASHBYTES('SHA2_256',
    CAST((SELECT * FROM dbo.PackageRegistrations ORDER BY [Key] FOR JSON PATH) AS nvarchar(max))), 2);"
