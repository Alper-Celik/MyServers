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

  services.caddy.virtualHosts."p2p.lab.alper-celik.dev" = {
    extraConfig = "reverse_proxy http://127.0.0.1:${toString config.services.qbittorrent.webuiPort}";
  };
}
