{ config, ... }:
{
  users.users.immich.extraGroups = [
    "video"
    "render"
    config.users.groups.media.name
  ];
  services.immich = {
    enable = true;
    environment = {
      IMMICH_TELEMETRY_INCLUDE = "all";
    };
    port = 2383;
    host = "0.0.0.0";
    database.enableVectors = false;
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ config.services.immich.port ];

  systemd.services."immich-backup" = {
    serviceConfig = {
      PAMName = "sudo";
      ExecStart = "${./backups/immich-backup.sh}";
      Type = "oneshot";
      User = "root";
      Group = "root";
    };
    startAt = "2:*";
  };

}
