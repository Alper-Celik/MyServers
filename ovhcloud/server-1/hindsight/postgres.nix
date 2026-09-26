# PostgreSQL side of the hindsight memory server.
{ config, lib, ... }:
{
  services.postgresql = {
    # pgvector — the plain `vector` extension hindsight requires. (Immich uses
    # pgvecto-rs/vectors.so — related but NOT the same extension; do not copy.)
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
    # Keep /run/postgresql first for host tools; the persistent dir is for the
    # container mount (see default.nix for why /run/postgresql cannot be
    # bind-mounted).
    settings.unix_socket_directories = lib.mkForce "/run/postgresql /var/lib/postgresql-sockets";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/postgresql-sockets 0755 postgres postgres -"
  ];

  # Enable the extension inside the hindsight DB (idempotent; immich-module
  # ExecStartPost pattern).
  systemd.services.postgresql.serviceConfig.ExecStartPost = [
    ''${lib.getExe' config.services.postgresql.package "psql"} -d hindsight -c "CREATE EXTENSION IF NOT EXISTS vector"''
  ];
}
