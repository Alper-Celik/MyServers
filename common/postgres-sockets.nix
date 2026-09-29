# Persistent postgres socket dir, for containers that talk to the host postgres
# over the unix socket: /run/postgresql is a RuntimeDirectory, so its inode is
# replaced on every postgres restart and a bind mount of it goes stale.
{ lib, pkgs, ... }:
let
  socketDir = "/var/lib/postgresql-sockets";
in
{
  _module.args.postgresSocketDir = socketDir;

  # unix_socket_directories takes a COMMA-separated list. With a space postgres
  # reads the whole value as one directory name and the postmaster exits at
  # startup (spin up any postgres and pass the old value to see it):
  #   FATAL:  could not create lock file "/run/postgresql /var/lib/postgresql-sockets/.s.PGSQL.5432.lock": No such file or directory
  # /run/postgresql stays first so host clients (keycloak, freshrss, …) are untouched.
  services.postgresql.settings.unix_socket_directories = lib.mkForce "/run/postgresql,${socketDir}";

  # postgres also exits when a directory in that list is missing, and a tmpfiles
  # rule only runs at boot, so the directory is created by the unit itself before
  # every start: as root (the `+` prefix escapes User= and the unit's sandbox,
  # which is ProtectSystem=strict), 0755 so container clients can reach the socket.
  systemd.services.postgresql.serviceConfig.ExecStartPre = [
    "+${pkgs.coreutils}/bin/install -d -o postgres -g postgres -m 0755 ${socketDir}"
  ];
}
