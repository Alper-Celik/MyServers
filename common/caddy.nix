{
  config,
  lib,
  pkgs,
  ...
}@args:
with lib;
let
  mkIfStr = cond: as: if cond then as else "";
in
{
  options.services.caddy.virtualHosts = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { config, ... }:
        {
          options.x-expose = mkOption {
            type = types.bool;
            default = false;
            description = ''
              whether to expose to the internet without tailscale or local ip
            '';
          };
          config = {
            extraConfig = lib.mkOrder 400 (
              # even before mkBefore see : https://github.com/NixOS/nixpkgs/blob/dcd5b741d586068371ac436a5bd558ef76bbfb4d/nixos/doc/manual/development/option-def.section.md?plain=1#L107
              ''
                @not_local_ip {
                  not client_ip private_ranges 100.64.0.0/10
                }
              ''
              + (mkIfStr (!config.x-expose) ''
                respond @not_local_ip "<h1>Access Denied</h1>" 403
              '')
            );
          };
        }
      )
    );
  };

  config = {

    sops.templates."caddy.env".content = ''
      CF_API_TOKEN=${config.sops.placeholder.CLOUDFLARE_CADDY_TOKEN}
    '';

    services.caddy = {
      enable = true;
      email = "alper@alper-celik.dev";
      environmentFile = config.sops.templates."caddy.env".path;

      globalConfig = lib.mkBefore ''
        servers {
          0rtt off
        }
      '';

      extraConfig = ''
        *.lab.alper-celik.dev, *.alper-celik.dev {
          tls {
            dns cloudflare {env.CF_API_TOKEN}
          }
          abort
        }
      '';

      package = pkgs.caddy.withPlugins {
        plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
        hash = "sha256-Q0lgI8MY90u/5R/xXBVPQWCZBN7dUZ0kcuDxD0xd0fo=";
      };
    };

  };
}
