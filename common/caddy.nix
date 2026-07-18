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
          trusted_proxies static private_ranges ${mkIfStr config.services.tailscale.enable "100.64.0.0/10"}
        }
      '';

      extraConfig = ''
        http:// {
            @acme path /.well-known/acme-challenge/*
            handle @acme {
                reverse_proxy rpi5.bobtail-stonecat.ts.net:80
            }
        }
      '';

      package = pkgs.caddy.withPlugins {
        plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
        hash = "sha256-hEHgAG0F0ozHRAPuxEqLyTATBrE+pajeXDiSNwniorg=";
      };
    };

  };
}
