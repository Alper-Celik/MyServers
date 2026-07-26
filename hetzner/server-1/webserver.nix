{ config, lib, ... }@args:
with lib;
{
  config = {

    services.caddy = {
      enable = true;
      extraConfig = ''
        http:// {
            @acme path /.well-known/acme-challenge/*
            handle @acme {
                reverse_proxy rpi5.bobtail-stonecat.ts.net:80
            }
        }
      '';
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
