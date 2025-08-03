{ config, ... }:
{
  services.adguardhome = {
    enable = true;
    allowDHCP = false;
    port = 5566;
  };

  services.nginx.virtualHosts."adguardhome.lab.alper-celik.dev" = {
    enableACME = true;
    forceSSL = true;
    acmeRoot = null;
    locations."/" = {
      proxyPass = "127.0.0.1:${builtins.toString config.services.adguardhome.port}";
    };
  };
}
