{ config, pkgs, ... }:
let
  cfg = config.services.calibre-web;
in
{
  services.calibre-web = {
    enable = true;
    package = pkgs.calibre-web.overridePythonAttrs (old: {
      dependencies = old.dependencies ++ [ pkgs.calibre-web.optional-dependencies.kobo ];
    });
    listen.ip = "0.0.0.0";
    options = {
      enableBookConversion = true;
      enableKepubify = true;
      calibreLibrary = "${config.services.syncthing.dataDir}/Calibre Library/";
    };
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.listen.port ];
}
