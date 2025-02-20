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
        dnsProvider = "cloudflare";
        credentialFiles =
          let
            s = config.sops.secrets;
          in
          {
            CLOUDFLARE_API_KEY_FILE = s.CLOUDFLARE_API_KEY.path;
            CLOUDFLARE_EMAIL_FILE = s.CLOUDFLARE_EMAIL.path;
          };
        dnsResolver = "1.1.1.1:53";
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
