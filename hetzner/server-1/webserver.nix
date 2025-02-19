{ config, lib, ... }@args:

{

  config = {
    services.nginx = {
      enable = true;

      recommendedZstdSettings = true;
      recommendedGzipSettings = true;

      recommendedTlsSettings = true;
      recommendedProxySettings = true;
      recommendedOptimisation = true;
    };

    security.acme = {
      acceptTerms = true;
      defaults = {
        email = "alper@alper-celik.dev";
      };
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
