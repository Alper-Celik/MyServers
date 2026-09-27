{ config, pkgs-unstable, ... }:
{
  services.navidrome = {
    enable = true;
    package = pkgs-unstable.navidrome;
    # Navidrome plugins are wasi/wasm artifacts and nixpkgs marks them
    # platforms = wasi, so the native pkgs instance refuses to evaluate them.
    plugins = with pkgs-unstable.pkgsCross.wasi32.navidromePlugins; [ audiomuseai ];
    settings = {
      Agents = "audiomuseai,lastfm,deezer,listenbrainz";
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
