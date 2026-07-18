{ config, lib, ... }@args:
with lib;
{
  config = {

    services.caddy = {
      enable = true;
    };

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
        443
      ];
    };
  };
}
