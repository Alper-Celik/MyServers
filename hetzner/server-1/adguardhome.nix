{ config, ... }:
{
  services.adguardhome = {
    enable = true;
    allowDHCP = false;
  };

  services.nginx.virtualHosts."adguardhome.lab.alper-celik.dev" = {
    enableACME = true;
    forceSSL = true;
    acmeRoot = null;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${builtins.toString config.services.adguardhome.port}";
      proxyWebsockets = true;
    };
  };
}
