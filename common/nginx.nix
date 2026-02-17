{ lib, ... }:
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
            locations."/".extraConfig = "allow 0.0.0.0/0; ";
          };
        }
      )
    );
  };
  config = {
    services.nginx = {
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
        allow 172.25.42.0/24;

        deny all;
      '';
    };
  };

}
