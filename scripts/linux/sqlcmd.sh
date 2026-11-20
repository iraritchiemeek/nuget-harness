#!/usr/bin/env bash
# Run sqlcmd as sa in the SQL Server container that sql-server.sh started; arguments go to sqlcmd.
# Passwords reach the container through the environment, never a command line: sqlcmd reads
# SQLCMDPASSWORD, and READER_PASSWORD is available to scripts as the variable $(READER_PASSWORD).
set -euo pipefail
: "${SA_PASSWORD:?SA_PASSWORD must be set}"
export SQLCMDPASSWORD=$SA_PASSWORD
exec docker exec -e SQLCMDPASSWORD -e READER_PASSWORD nuget-sql /opt/mssql-tools18/bin/sqlcmd -C -b -S localhost -U sa "$@"
