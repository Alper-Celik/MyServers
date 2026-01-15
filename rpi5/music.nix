{ config, ... }:
{
  services.navidrome = {
    enable = true;
    settings = {
      MusicFolder = "${config.services.syncthing.dataDir}/Music";
      EnableInsightsCollector = true;
    };
  };

  services.nginx.virtualHosts."music.lab.alper-celik.dev" = {
    forceSSL = true;
    enableACME = true;
    acmeRoot = null;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.navidrome.settings.Port}";
      extraConfig = ''
        # Set headers
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_buffering    off;
      '';
    };
  };
}
