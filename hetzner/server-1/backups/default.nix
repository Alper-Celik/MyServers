{
  config,
  lib,
  pkgs,
  ...
}:
let
  forgejo-backup = pkgs.writeShellApplication {
    name = "forgejo-backup";
    # pg_dump comes from the server's own package so a client/server version
    # mismatch cannot silently break the dump after an upgrade
    runtimeInputs = [
      pkgs.restic
      config.services.postgresql.package
      pkgs.coreutils
    ];
    text = builtins.readFile ./forgejo-backup.sh;
  };
in
{
  systemd.tmpfiles.rules = [ "d /var/cache/restic/forgejo 0750 forgejo forgejo - -" ];

  # Timed 30 minutes ahead of ovhcloud's run: both write the same restic repo,
  # and --retry-lock only covers the overlap, not a fight for the lock.
  systemd.services.forgejo-backup = {
    description = "Back up the Forgejo database and repositories to the shared restic repo";

    # Runs as forgejo, so the sops files it needs are owned by that user: the
    # job needs no root and no sudo to reach its own data or the local socket.
    environment = {
      AWS_ACCESS_KEY_ID_FILE = config.sops.secrets."b2-restic-shared-keyID".path;
      AWS_SECRET_ACCESS_KEY_FILE = config.sops.secrets."b2-restic-shared-applicationKey".path;
      RESTIC_PASSWORD_FILE = config.sops.secrets.RESTIC_SHARED_PASSWORD.path;
    };

    serviceConfig = {
      Type = "oneshot";
      User = "forgejo";
      Group = "forgejo";
      ExecStart = lib.getExe forgejo-backup;
    };

    startAt = "*-*-* 02:40:00";
  };
}
