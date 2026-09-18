{
  config,
  lib,
  pkgs,
  ...
}:
let
  kanidm = pkgs.kanidm_1_11;
  cfg = config.services.kanidm.server;
  certDir = config.security.acme.certs.${cfg.settings.domain}.directory;
in
{
  systemd.services.kanidm = {
    serviceConfig = {
      ExecReload = "${kanidm}/bin/kanidmd scripting reload -c /etc/kanidm/server.toml";
      LimitNOFILE = 65536;
      OOMPolicy = "stop";
      OOMScoreAdjust = -100;
    };
  };

  security.acme.certs.${cfg.settings.domain} = {
    reloadServices = [ config.systemd.services.kanidm.name ];
  };

  # The caddy module sets security.acme.certs.<useACMEHost>.group = services.caddy.group
  # ("caddy"), and acme chowns the cert dir acme:caddy with g=r. Kanidm terminates TLS
  # itself on the loopback listener, so it needs the caddy group to read these files.
  users.users.kanidm.extraGroups = [ "caddy" ];

  services.caddy.virtualHosts.${cfg.settings.domain} = {
    x-expose = true;
    # ai generated
    # kanidm's certificate is issued for the domain, not for the loopback address
    # caddy dials, so pin the verification name (otherwise caddy answers 502 with
    # an empty body: "cannot validate certificate for ::1 because it doesn't
    # contain any IP SANs").
    extraConfig = ''
      reverse_proxy https://${cfg.settings.bindaddress} {
        transport http {
          tls_server_name ${cfg.settings.domain}
        }
      }
    '';
    # ai generated
  };

  services.kanidm.package = kanidm;
  services.kanidm.server = {
    enable = true;
    settings = {
      tls_chain = "${certDir}/fullchain.pem";
      tls_key = "${certDir}/key.pem";
      bindaddress = "[::1]:8443";
      domain = "id.auth.how";
      origin = "https://id.auth.how";
      http_client_address_info.x-forward-for = [ "::1" ];
      online_backup = {
        schedule = "45 22 * * *"; # 45 1 * * * UTC+3 in UTC
        compression = "nocompression";
      };
    };
  };
}
