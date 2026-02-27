{ pkgs, lib, ... }:
let
  mkIfStr = cond: as: if cond then as else "";
in
with lib;
{
  options.services.nginx.virtualHosts = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { config, ... }:
        {

          options.x-disable-http3 = mkOption {
            type = types.bool;
            default = false;
            description = ''
              whether to disable http3/quick on this virtualHost
            '';
          };
          options.x-expose = mkOption {
            type = types.bool;
            default = false;
            description = ''
              whether to expose to the internet without tailscale ip
            '';
          };
          config = {
            locations."/".extraConfig = (
              mkIfStr (config.x-expose) ''
                allow 0.0.0.0/0;
              ''
            );
            extraConfig = (
              mkIfStr (!config.x-disable-http3) ''
                add_header Alt-Svc 'h3=":443"; ma=86400';
              ''
            );

            quic = true;
            http3 = true;

          };
        }
      )
    );
  };
  config = {
    services.nginx = {
      package = pkgs.nginxMainline;

      enableQuicBPF = true;

      recommendedGzipSettings = true;
      recommendedBrotliSettings = true;

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
