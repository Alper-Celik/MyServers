{ config, ... }:
{
  services.freshrss = {
    enable = true;
    baseUrl = "https://${config.services.freshrss.virtualHost}";
    virtualHost = "freshrss.lab.alper-celik.dev";
    passwordFile = config.sops.secrets.nextcloud-admin-pass.path;
    database = {
      type = "pgsql";
      tableprefix = "freshrss";
    };
  };

  services.nginx.virtualHosts.${config.services.freshrss.virtualHost} = {
    forceSSL = true;
    enableACME = true;
    acmeRoot = null;
  };
}
