{ config, lib, ... }@args:

with lib;

let
  gconfig = args.config;
in
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
              whether to expose to the internet without tailscale auth
            '';
          };
          config = lib.mkIf (!config.expose) {
            #from https://github.com/NixOS/nixpkgs/blob/8c4dc69b9732f6bbe826b5fbb32184987520ff26/nixos/modules/services/web-servers/nginx/tailscale-auth.nix#L59
            locations."/auth" = {
              extraConfig = ''
                internal;

                proxy_pass http://unix:${gconfig.services.tailscaleAuth.socketPath};
                proxy_pass_request_body off;

                # Upstream uses $http_host here, but we are using gixy to check nginx configurations
                # gixy wants us to use $host: https://github.com/yandex/gixy/blob/master/docs/en/plugins/hostspoofing.md
                proxy_set_header Host $host;
                proxy_set_header Remote-Addr $remote_addr;
                proxy_set_header Remote-Port $remote_port;
                proxy_set_header Original-URI $request_uri;
                proxy_set_header X-Scheme                $scheme;
                proxy_set_header X-Auth-Request-Redirect $scheme://$host$request_uri;
              '';
            };
            locations."/".extraConfig = ''
              auth_request /auth;
              auth_request_set $auth_user $upstream_http_tailscale_user;
              auth_request_set $auth_name $upstream_http_tailscale_name;
              auth_request_set $auth_login $upstream_http_tailscale_login;
              auth_request_set $auth_tailnet $upstream_http_tailscale_tailnet;
              auth_request_set $auth_profile_picture $upstream_http_tailscale_profile_picture;

              proxy_set_header X-Webauth-User "$auth_user";
              proxy_set_header X-Webauth-Name "$auth_name";
              proxy_set_header X-Webauth-Login "$auth_login";
              proxy_set_header X-Webauth-Tailnet "$auth_tailnet";
              proxy_set_header X-Webauth-Profile-Picture "$auth_profile_picture";

              ${lib.optionalString (
                gconfig.services.nginx.tailscaleAuth.expectedTailnet != ""
              ) ''proxy_set_header Expected-Tailnet "${gconfig.services.nginx.tailscaleAuth.expectedTailnet}";''}
            '';
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

      tailscaleAuth = {
        enable = true;
      };
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
