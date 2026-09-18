{ pkgs, config, ... }:
let
  cfg = config.services.keycloak;
  domain = "id.auth.how";
  admin-domain = "admin.id.auth.how";
  certDir = config.security.acme.certs.${domain}.directory;
in
{
  services.caddy.virtualHosts.${domain} = {
    x-expose = true;
    extraConfig = ''
      @public_paths path /realms/* /resources/* /.well-known/*  /lb-check*

      reverse_proxy @public_paths https://[::1]:${toString cfg.settings.https-port} {
        transport http {
          tls_server_name ${domain}
        }
      }
    '';
  };

  services.caddy.virtualHosts.${admin-domain} = {
    x-expose = false;
    extraConfig = ''
      reverse_proxy https://[::1]:${toString cfg.settings.https-port} {
        transport http {
          tls_server_name ${domain}
        }
      }
    '';
  };

  # The caddy module sets security.acme.certs.<useACMEHost>.group = services.caddy.group
  # ("caddy"), and acme chowns the cert dir acme:caddy with g=r.
  users.users.keycloak.extraGroups = [ "caddy" ];

  services.keycloak = {
    enable = true;
    database = {
      host = "/run/postgresql";
      createLocally = true;
    };
    plugins = with pkgs.keycloak.plugins; [
      junixsocket-common
      junixsocket-native-common
    ];
    sslCertificate = "${certDir}/fullchain.pem";
    sslCertificateKey = "${certDir}/key.pem";

    settings = {
      https-port = 4338;
      hostname = domain;
      proxy-headers = "xforwarded";
      hostname-admin = admin-domain;
      http-enabled = false;
    };

  };
}
