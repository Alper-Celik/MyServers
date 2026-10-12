# ai generated
# Unblock activation after libc collation updates (glibc bump →
# "collation version mismatch" → postgresql-setup fails, deploy fails).
#
# postgresql-setup's checks fail because the superuser databases record an old
# libc collation version (pg_database.datcollversion): connecting to "postgres"
# warns, CREATE DATABASE errors because it validates against template1.
# This oneshot refreshes ONLY those two stamps, so setup passes and the
# activation succeeds.
#
# App databases (grafana, crow-server, …) are deliberately NOT refreshed: their
# stale datcollversion keeps a WARNING in the postgres log on every connect as
# the reminder that index rebuilds are still due. Reindexing is manual because
# REINDEX takes ACCESS EXCLUSIVE locks — it should run at a chosen time, not
# during an arbitrary activation of a fleet with public services.
#
# Manual procedure when a libc collation update happened (as postgres):
#   reindexdb --all
#   psql -d postgres -Atqc \
#     "SELECT 'ALTER DATABASE \"'||datname||'\" REFRESH COLLATION VERSION;' FROM pg_database WHERE datallowconn" \
#     | psql -d postgres
# (the generated ALTERs are no-ops for already-current databases)
{
  config,
  lib,
  ...
}:
let
  cfg = config.services.postgresql;
in
{
  config = lib.mkIf cfg.enable {
    systemd.services.postgresql-collation-refresh = {
      description = "PostgreSQL Collation Version Refresh";
      after = [ "postgresql.service" ];
      before = [ "postgresql-setup.service" ];
      requiredBy = [ "postgresql-setup.service" ];
      path = [ cfg.finalPackage ];
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        Group = "postgres";
      };
      script = ''
        set -euo pipefail
        if [[ -f "${cfg.dataDir}/standby.signal" ]]; then
          echo "Skipping collation refresh: PostgreSQL is in standby mode"
          exit 0
        fi
        psql -d postgres -v ON_ERROR_STOP=1 -qc 'ALTER DATABASE "postgres" REFRESH COLLATION VERSION;'
        psql -d postgres -v ON_ERROR_STOP=1 -qc 'ALTER DATABASE "template1" REFRESH COLLATION VERSION;'
        stale="$(psql -d postgres -Atqc "SELECT string_agg(datname, ', ') FROM pg_database
          WHERE datallowconn AND datcollversion IS NOT NULL
            AND datcollversion <> (SELECT datcollversion FROM pg_database WHERE datname = 'postgres')")"
        if [[ -n "$stale" ]]; then
          echo "WARNING: libc collation version changed; these databases still have stale collation versions:"
          echo "         $stale"
          echo "         reindex them manually (see comment in postgresql-collation-refresh.nix)"
        fi
      '';
    };
  };
}
