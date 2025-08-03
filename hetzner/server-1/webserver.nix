{ config, lib, ... }@args:
with lib;
{
  options.services.nginx.virtualHosts = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { config, ... }:
        {
          options.expose = mkOption {
            type = types.bool;
            default = false;
            description = ''
              whether to expose to the internet without tailscale ip
            '';
          };
          config = lib.mkIf (!config.expose) {
            locations."/".extraConfig = ''allow 0.0.0.0/0; '';
          };
        }
      )
    );
  };

  config = {
    services.nginx = {
      enable = true;

      recommendedZstdSettings = true;
      recommendedGzipSettings = true;

      recommendedTlsSettings = true;
      recommendedProxySettings = true;
      recommendedOptimisation = true;

      appendHttpConfig = ''
        proxy_headers_hash_bucket_size 128;
        proxy_headers_hash_max_size 1024;
      '';

      virtualHosts."_".locations."/".extraConfig = ''
        allow 100.64.0.0/10;

        deny all;
      '';

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
