{ config, ... }:
{
  services.postgresql = {
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
    passwordFile = config.sops.secrets.freshrss-admin-pass.path;
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

  systemd.services."freshrss-backup" = {
    serviceConfig = {
      PAMName = "sudo";
      ExecStart = "${./backups/freshrss-backup.sh}";
      Type = "oneshot";
      User = "root";
      Group = "root";
    };
    startAt = "2:17";
  };

}
