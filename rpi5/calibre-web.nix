{ config, ... }:
let
  cfg = config.services.calibre-web;
in
{
  services.calibre-web = {
    enable = true;
    listen = {
    };
    options = {
      enableBookConversion = true;
      enableKepubify = true;
      calibreLibrary = "${config.services.syncthing.dataDir}/Calibre Library/";
    };
  };

  services.nginx.virtualHosts."books.lab.alper-celik.dev" = {
    forceSSL = true;
    enableACME = true;
    acmeRoot = null;
    locations."/" = {
      proxyPass = "http://localhost:${builtins.toString cfg.listen.port}";
    };
  };
}
