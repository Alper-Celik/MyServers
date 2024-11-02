{ config, ... }:
let
  vaultwarden-db = "vaultwarden";
  vaultwarden-db-user = "vaultwarden";
in
{

  environment.persistence."/persistent-important" = {

    enable = true;
    directories = [
      {
        directory = "/var/lib/bitwarden_rs/";
        user = config.users.users.vaultwarden.name;
        group = config.users.users.vaultwarden.name;
        mode = "u=rwx,g=,o=";
      }

    ];
  };
  services.postgresql = {
    ensureDatabases = [ vaultwarden-db ];
    ensureUsers = [
      {
        name = vaultwarden-db-user;
        ensureDBOwnership = true;
      }
    ];
  };
  services.vaultwarden = {
    enable = true;
    dbBackend = "postgresql";
    config = {
      ROCKET_ADDRESS = "::1";
      ROCKET_PORT = 8222;

      DATABASE_URL = "postgresql://%2Frun%2Fpostgresql/${vaultwarden-db}?user=${vaultwarden-db-user}";
    };
  };

  services.nginx.virtualHosts."bitwarden.lab.alper-celik.dev" = {
    enableACME = true;
    forceSSL = true;
    acmeRoot = null;
    locations."/" = {
      proxyPass = "http://localhost:${toString config.services.vaultwarden.config.ROCKET_PORT}";
    };
  };
}
