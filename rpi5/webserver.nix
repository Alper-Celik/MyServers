{ config, lib, ... }@args:

with lib;

let
  gconfig = args.config;
in
{

  config = {
    services.caddy.enable = true;
    services.nginx = {
      enable = false;
    };

    #open web server to firewall
    networking.firewall = {
      enable = true;
      allowedTCPPorts = [
        80
        443
      ];
      allowedUDPPorts = [
        80
        443
      ];
    };
  };
}
