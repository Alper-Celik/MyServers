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

  # The postmaster runs under ProtectSystem=strict, so the socket dir has to be in
  # its writable set, and that bind mount is set up BEFORE ExecStartPre runs - the
  # directory must therefore already exist when the unit starts, which a tmpfiles
  # rule (boot only) and an ExecStartPre (too late) both fail to guarantee.
  systemd.services.postgresql.serviceConfig.ReadWritePaths = [ socketDir ];

  systemd.services.postgresql = {
    requires = [ "postgresql-socket-dir.service" ];
    after = [ "postgresql-socket-dir.service" ];
  };

  systemd.services.postgresql-socket-dir = {
    description = "Create the persistent postgres socket directory";
    serviceConfig = {
      Type = "oneshot";
      # 0755 so container clients (not in group postgres) can traverse it, and
      # install -d re-applies mode/owner on every start, which also recovers a
      # mount point podman may have created as root.
      ExecStart = "${pkgs.coreutils}/bin/install -d -o postgres -g postgres -m 0755 ${socketDir}";
    };
  };
}
