{ config, ... }:
{
  services.vaultwarden = {
    enable = true;
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
