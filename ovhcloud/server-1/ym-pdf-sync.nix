{
  config,
  lib,
  pkgs,
  ...
}:
let
  site-dir = "/var/lib/www/beta.ym-pdf.alper-celik.dev";
in
{
  users.users.ym-pdf = {
    isSystemUser = true;
    group = "ym-pdf";
  };
  users.groups.ym-pdf = { };

  sops.secrets.rclone-onedrive-config = {
    owner = "ym-pdf";
  };

  systemd.tmpfiles.rules = [
    "d ${site-dir} 0755 ym-pdf ym-pdf -"
  ];

  # rclone sync mirrors the remote, so deletions in OneDrive propagate here;
  # the hourly timer also covers files added straight to OneDrive from the phone.
  systemd.services.ym-pdf-sync = {
    description = "Sync OneDrive lecture PDFs into the beta.ym-pdf web root";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "ym-pdf";
      Group = "ym-pdf";
      # the web root predates this unit and was seeded as root; converge
      # ownership (self-heals if a manual root edit lands in between)
      ExecStartPre = "+${pkgs.coreutils}/bin/chown -R ym-pdf:ym-pdf ${site-dir}";
      ExecStart = "${pkgs.rclone}/bin/rclone sync --config ${config.sops.secrets.rclone-onedrive-config.path} \"onedrive:/Ders pdf'leri\" ${site-dir}/";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ site-dir ];
      PrivateTmp = true;
    };
  };

  systemd.timers.ym-pdf-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };
}
