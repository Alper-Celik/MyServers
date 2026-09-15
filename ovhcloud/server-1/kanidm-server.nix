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

  services.caddy.virtualHosts.${cfg.settings.domain} = {
    x-expose = true;
    extraConfig = "reverse_proxy https://${cfg.settings.bindaddress}";
  };

  services.kanidm.package = kanidm;
  services.kanidm.server = {
    enable = true;
    settings = {
      tls_chain = "${certDir}/chain.pem";
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
