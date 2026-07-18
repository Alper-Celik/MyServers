{ config, pkgs-unstable, ... }:
{
  services.actual = {
    package = pkgs-unstable.actual-server;
    enable = true;
    settings = {
      port = 3456;
    };
  };

  services.nginx.virtualHosts."actual-budget.lab.alper-celik.dev" = {
    extraConfig = "reverse_proxy http://127.0.0.1:${toString config.services.actual.settings.port}";
  };
}
