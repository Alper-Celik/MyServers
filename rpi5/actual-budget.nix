{ config, pkgs, ... }:
{
  services.actual = {
    enable = true;
    settings = {
      port = 3456;
    };
  };

  services.nginx.virtualHosts."actual-budget.lab.alper-celik.dev" = {
    enableACME = true;
    forceSSL = true;
    acmeRoot = null;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${builtins.toString config.services.actual.settings.port}";
      extraConfig = ''
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $host;
      '';
    };
  };
}
