#!/usr/bin/env bash
# Start SQL Server in Docker and restore the NuGetGallery database from a seed-snapshot folder.
# Usage: sql-server.sh <snapshot-dir>
# Needs SA_PASSWORD and READER_PASSWORD in the environment (generated and masked by the workflow,
# never committed). Creates the login `reader`, a member of db_datareader only, for the new service.
# Prints the server version, the restored database's compatibility level and collation, and a
# row count, so each run log shows what the backup was restored into.
set -euo pipefail

# The runner's LocalDB is 15.0 (SQL Server 2019), read from `sqllocaldb info` in the old-app run.
# A backup restores into the same major version or newer, so 2022 (16.0) qualifies.
SQL_IMAGE='mcr.microsoft.com/mssql/server@sha256:4525e3efac9f3e241cb003bb2ff2a82818b502f37e12049d788b1a9fa7e13b7f'
CONTAINER=nuget-sql
snapshot_dir=$(cd "$1" && pwd)
: "${SA_PASSWORD:?SA_PASSWORD must be set}"
: "${READER_PASSWORD:?READER_PASSWORD must be set}"

# The password comes from the environment, and the port is reachable from this machine only.
export MSSQL_SA_PASSWORD=$SA_PASSWORD
docker run -d --name "$CONTAINER" -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD \
  -p 127.0.0.1:1433:1433 -v "$snapshot_dir:/snapshot:ro" "$SQL_IMAGE" >/dev/null

sql() { "$(dirname "$0")/sqlcmd.sh" -W -s '|' "$@"; }

for _ in $(seq 1 60); do
  if sql -Q 'SELECT 1' >/dev/null 2>&1; then break; fi
  sleep 2
done
sql -h -1 -Q 'SET NOCOUNT ON; SELECT @@VERSION'

# The backup was taken on Windows, so its files must be moved to the container's data folder.
sql -Q "RESTORE DATABASE [NuGetGallery] FROM DISK = N'/snapshot/NuGetGallery.bak' WITH CHECKSUM,
  MOVE N'NuGetGallery' TO N'/var/opt/mssql/data/NuGetGallery.mdf',
  MOVE N'NuGetGallery_log' TO N'/var/opt/mssql/data/NuGetGallery_log.ldf'" | tail -n 1
sql -Q "SET NOCOUNT ON;
  SELECT name, compatibility_level, collation_name FROM sys.databases WHERE name = N'NuGetGallery';
  SELECT COUNT(*) AS packages FROM NuGetGallery.dbo.Packages;"

# The service's login can read and nothing else (spec 02, done-when 7).
sql -Q "SET NOCOUNT ON;
  CREATE LOGIN [reader] WITH PASSWORD = N'\$(READER_PASSWORD)', CHECK_POLICY = OFF;
  USE [NuGetGallery];
  CREATE USER [reader] FOR LOGIN [reader];
  ALTER ROLE [db_datareader] ADD MEMBER [reader];
  SELECT r.name AS role_of_reader FROM sys.database_role_members m
    JOIN sys.database_principals r ON r.principal_id = m.role_principal_id
    JOIN sys.database_principals u ON u.principal_id = m.member_principal_id
  WHERE u.name = N'reader';"
