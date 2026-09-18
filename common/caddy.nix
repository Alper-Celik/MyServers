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
          options.x-enable-http-logs = mkOption {
            type = types.bool;
            default = true;
            description = ''
              whether to write json access logs for this virtual host.
              logs are tailed by grafana-alloy, disable for noisy vhosts.
            '';
          };
          config = {
            useACMEHost = config.hostName;

            # nixpkgs emits its own `log` block from logFormat, so null it out and
            # keep the whole access log config in extraConfig instead.
            logFormat = lib.mkDefault null;

            extraConfig = lib.mkMerge [
              (lib.mkOrder 400 (
                # even before mkBefore see : https://github.com/NixOS/nixpkgs/blob/dcd5b741d586068371ac436a5bd558ef76bbfb4d/nixos/doc/manual/development/option-def.section.md?plain=1#L107
                ''
                  @not_local_ip {
                    not client_ip private_ranges 100.64.0.0/10
                  }
                ''
                + (mkIfStr (!config.x-expose) ''
                  respond @not_local_ip "<h1>Access Denied</h1>" 403
                '')
              ))

              # ai generated start
              # json access log, per vhost so volume can be tuned independently.
              # mode 0640 so the alloy user (member of the caddy group) can read it.
              # caddy's native log already carries request headers, sizes, duration
              # and tls details, log_append adds the proxy timings it does not.
              (lib.mkIf config.x-enable-http-logs (
                lib.mkAfter ''
                  log {
                    format json
                    output file ${args.config.services.caddy.logDir}/access-${
                      lib.replaceStrings [ "/" " " ] [ "_" "_" ] config.hostName
                    }.log {
                      mode 0640
                    }
                  }

                  log_append remote_host {http.request.remote.host}
                  log_append upstream_host {http.reverse_proxy.upstream.host}
                  log_append upstream_latency_ms {http.reverse_proxy.upstream.latency_ms}
                  log_append upstream_duration_ms {http.reverse_proxy.upstream.duration_ms}
                  log_append request_duration_ms {http.request.duration_ms}
                  log_append scheme {http.request.scheme}
                ''
              ))

              # ai generated end
            ];
          };
        }
      )
    );
  };

  config = {
    services.caddy = {
      enable = true;
      openFirewall = true;
      email = "alper@alper-celik.dev";
      globalConfig = lib.mkBefore ''
        auto_https disable_certs # automated using nixos module of lego
        metrics {
          per_host
          otlp
        }

        servers {
          trusted_proxies static private_ranges ${mkIfStr config.services.tailscale.enable "100.64.0.0/10"}
        }
      '';
    };
  };
}
