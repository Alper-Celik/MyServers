{ config, ... }:
{
  services.nginx.virtualHosts."id.lab.alper-celik.dev" = {
    forceSSL = true;
    enableACME = true;
    acmeRoot = null;
    locations = {
      "/" = {
        proxyPass = "http://localhost:${toString config.services.keycloak.settings.http-port}";
      };
    };
  };

  services.keycloak = {
    enable = true;
    database = {
      type = "postgresql";
      passwordFile = config.sops.secrets."postgres/keycloak-pass".path;
      createLocally = true;
    };
    settings = {
      hostname = "id.lab.alper-celik.dev";
      hostname-port = 443;
      http-port = 38080;
      http-enabled = true;
    };

  };
}
