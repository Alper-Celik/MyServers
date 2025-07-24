{ config, pkgs, ... }:
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_15;
    enableJIT = true;
  };

  services.pgadmin = {
    enable = true;
    initialEmail = "alper@alper-celik.dev";
    initialPasswordFile = config.sops.secrets.pgadmin-pass.path;
  };
  systemd.services.pgadmin.serviceConfig.TimeoutStartSec = "10min";

  services.nginx.virtualHosts."pgadmin.lab.alper-celik.dev" = {
    enableACME = true;
    forceSSL = true;
    acmeRoot = null;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.pgadmin.port}";
    };
  };
}
