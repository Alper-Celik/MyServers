{ config, ... }:
{
  services.postgresql = {
    enable = true;
    ensureDatabases = [ config.services.freshrss.database.name ];
    ensureUsers = [
      {
        name = config.services.freshrss.user;
        ensureDBOwnership = true;
      }
    ];
  };

  services.freshrss = {
    enable = true;
    baseUrl = "https://${config.services.freshrss.virtualHost}";
    virtualHost = "freshrss.lab.alper-celik.dev";
    passwordFile = config.sops.secrets.nextcloud-admin-pass.path;
    database = {
      name = "freshrss";
      user = "freshrss";
      type = "pgsql";
      host = "/run/postgresql";
    };
  };

  services.nginx.virtualHosts.${config.services.freshrss.virtualHost} = {
    forceSSL = true;
    enableACME = true;
    acmeRoot = null;
  };
}
