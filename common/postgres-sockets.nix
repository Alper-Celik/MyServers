# Persistent postgres socket dir, for containers that talk to the host postgres
# over the unix socket: /run/postgresql is a RuntimeDirectory, so its inode is
# replaced on every postgres restart and a bind mount of it goes stale.
{ lib, ... }:
let
  socketDir = "/var/lib/postgresql-sockets";
in
{
  _module.args.postgresSocketDir = socketDir;

  # /run/postgresql stays first so host clients (keycloak, freshrss, …) are untouched
  services.postgresql.settings.unix_socket_directories = lib.mkForce "/run/postgresql ${socketDir}";
  systemd.tmpfiles.rules = [ "d ${socketDir} 0755 postgres postgres -" ];
}
