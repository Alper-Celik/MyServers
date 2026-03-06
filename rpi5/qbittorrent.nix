{
  config,
  pkgs,
  ...
}:
{
  users.users.${config.services.qbittorrent.user}.extraGroups = [ "media" ];
  services.qbittorrent = {
    enable = true;
    webuiPort = 4359;
    serverConfig = {
      Preferences = {
        WebUI = {
          AlternativeUIEnabled = true;
          RootFolder = "${pkgs.vuetorrent}/share/vuetorrent";
        };
      };
    };
  };

  services.nginx.virtualHosts."p2p.lab.alper-celik.dev" = {
    enableACME = true;
    acmeRoot = null;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${builtins.toString config.services.qbittorrent.webuiPort}";
      proxyWebsockets = true;
    };
  };
}
