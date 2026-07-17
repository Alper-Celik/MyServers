{ config, ... }:
{
  services.navidrome = {
    enable = true;
    settings = {
      Backup = {
        Path = "./backups";
        Schedule = "0 0 * * *";
        Count = 3;
      };
      Address = "[::1]";
      MusicFolder = "${config.services.syncthing.dataDir}/Music";
      EnableInsightsCollector = true;
    };
    environmentFile = config.sops.secrets.navidrome_secret_file.path;
  };

  services.caddy.virtualHosts."music.lab.alper-celik.dev" = {
    extraConfig = "reverse_proxy http://[::1]:${toString config.services.navidrome.settings.Port}";
  };
  systemd.services."navidrome-backup-store" = {
    serviceConfig = {
      PAMName = "sudo";
      ExecStart = "${./backups/navidrome-backup.sh}";
      Type = "oneshot";
      User = "root";
      Group = "root";
    };
    startAt = "1:*";
  };
}
