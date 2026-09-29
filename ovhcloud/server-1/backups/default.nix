{
  config,
  lib,
  pkgs,
  ...
}:
let
  postgres-backup = pkgs.writeShellApplication {
    name = "postgres-backup";
    runtimeInputs = [
      pkgs.restic
      config.services.postgresql.package
      pkgs.coreutils
    ];
    text = builtins.readFile ./postgres-backup.sh;
  };
in
{
  systemd.tmpfiles.rules = [ "d /var/cache/restic/postgres 0750 postgres postgres - -" ];

  # After hetzner's Forgejo run: both write the same restic repo.
  systemd.services.postgres-backup = {
    description = "Back up the postgres cluster to the shared restic repo";

    # Runs as postgres, so pg_dumpall authenticates over the local socket as a
    # peer and the sops files it needs are owned by that user — no sudo.
    environment = {
      AWS_ACCESS_KEY_ID_FILE = config.sops.secrets."b2-restic-shared-keyID".path;
      AWS_SECRET_ACCESS_KEY_FILE = config.sops.secrets."b2-restic-shared-applicationKey".path;
      RESTIC_PASSWORD_FILE = config.sops.secrets.RESTIC_SHARED_PASSWORD.path;
    };

    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      Group = "postgres";
      ExecStart = lib.getExe postgres-backup;
    };

    startAt = "*-*-* 03:10:00";
  };
}
