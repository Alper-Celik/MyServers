# PostgreSQL side of the hindsight memory server.
{ config, lib, ... }:
{
  services.postgresql = {
    # pgvector — hindsight's `vector` extension. Immich's pgvecto-rs
    # (vectors.so) is related but NOT the same; do not copy its setup.
    # Note: changes the effective postgres package → postgres restarts on deploy.
    extensions = ps: [ ps.pgvector ];
    ensureDatabases = [ "hindsight" ];
    ensureUsers = [
      {
        name = "hindsight";
        ensureDBOwnership = true;
        ensureClauses.login = true;
      }
    ];
  };

  # enable the extension inside the hindsight DB (idempotent; immich-module pattern)
  systemd.services.postgresql.serviceConfig.ExecStartPost = [
    ''${lib.getExe' config.services.postgresql.package "psql"} -d hindsight -c "CREATE EXTENSION IF NOT EXISTS vector"''
  ];
}
