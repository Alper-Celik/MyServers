{ config, ... }:
{

  systemd.services."backup-cloud-replicate" = {

    environment = {
      AWS_ACCESS_KEY_ID_FILE = "${config.sops.secrets.b2-backup-rpi5-keyID.path}";
      AWS_SECRET_ACCESS_KEY_FILE = "${config.sops.secrets.b2-backup-rpi5-applicationKey.path}";
      RESTIC_PASSWORD_FILE = "${config.sops.secrets.REMOTE_RESTIC_PASSWORD.path}";
    };

    serviceConfig = {
      PAMName = "sudo";
      ExecStart = "${./backup-cloud-replicate.sh}";
      Type = "oneshot";
      User = "root";
      Group = "root";

    };
    startAt = "Wednesday 3:*:*"; # every wednesday at 3 (24h time)
  };
}
